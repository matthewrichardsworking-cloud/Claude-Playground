"""The playtest bot's test runner (playtest-bot.md): drives the game copy's menus into a
mission, hands the pilot (CoopPilotMod) its orders, retries until the mission is done, and
writes a report a Claude session (or you) can read.

    python tools\\playtest.py run playtests\\orders\\m01-casual.yaml
        a whole test, as the order file says (see the example orders in playtests\\orders)
    python tools\\playtest.py goto --mission 1 --difficulty casual
        only the menu route: from the title screen to the first moment the player can fly

What comes back, in playtests\\<date>_<time>_m<NN>_<name>\\:
    report.md      what happened, in words: each attempt, kills, damage, why it ended
    events.jsonl   every event the pilot logged during the test (one JSON object per line)
    flight-*.csv   the plane ten times a second, one file per attempt
    pilot.log      the pilot's own running commentary for the test
    pictures\\      the game window at the start of each attempt and at its end
    order.yaml     the order as it was run
    saves-check.txt your real save folder compared with the backup taken before the test

Keys go to the copy's window only (tools\\game-input.ps1), and the pilot's own key presses
only happen while the game window is in front (CoopPadMod), so the game must stay in front
while a test runs: it pauses itself otherwise. Never touches the real install or saves.
"""

import datetime
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = r"C:\AC7-Coop-Game"
PILOT_DIR = os.path.join(GAME, "UserProfile", "pilot")
NOTES = r"C:\Users\Matth\AppData\Roaming\Claude\side-session-notes\local_57d76d5e-ada0-4477-ab40-a583a1de4927"
IN_USE = os.path.join(NOTES, "IN-USE-game-copy.md")
sys.path.insert(0, HERE)
import pilot  # noqa: E402  (tools\pilot.py: sends orders to the pilot)

DIFFICULTIES = ["casual", "easy", "normal", "hard", "ace", "free_flight"]
FAIL_EVENTS = {"player_dead": "shot down or crashed", "out_of_zone": "left the mission area",
               "time_out": "ran out of time", "objective_failed": "an objective failed"}


def say(msg):
    print(time.strftime("%H:%M:%S ") + msg, flush=True)


# ---- the order file: a small YAML subset (key: value, [lists], one level of nesting) ----

def parse_value(v):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        return [parse_value(x) for x in v[1:-1].split(",") if x.strip()]
    if v.lower() in ("true", "yes"):
        return True
    if v.lower() in ("false", "no"):
        return False
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        return v.strip('"').strip("'")


def read_order(path):
    order, section = {}, None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].rstrip()
            if not line.strip():
                continue
            indented = line.startswith((" ", "\t"))
            key, _, value = line.strip().partition(":")
            key = key.strip()
            if indented and section is not None:
                order[section][key] = parse_value(value)
            elif value.strip() == "":
                section = key
                order[section] = {}
            else:
                section = None
                order[key] = parse_value(value)
    return order


# ---- the game window and the pilot -----------------------------------------------------

def keys(names, gap_ms=900, hold_ms=80, wait_ms=0):
    """Press keys in the copy's window (game-input.ps1), then wait."""
    cmd = ["powershell", "-NoProfile", "-File", os.path.join(HERE, "game-input.ps1"),
           "-Keys", ",".join(names), "-GapMs", str(gap_ms), "-HoldMs", str(hold_ms)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("game-input.ps1 failed: " + (r.stderr or r.stdout).strip()[:300])
    if wait_ms:
        time.sleep(wait_ms / 1000)   # game-input.ps1's own -WaitMs only waits before a picture


def picture(path):
    """The game window, brought to the front with a harmless Shift tap."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "game-input.ps1"),
                    "-Keys", "Shift", "-Screenshot", path], capture_output=True, text=True)


def status():
    try:
        with open(os.path.join(PILOT_DIR, "status.json"), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def wait_status(test, seconds, what):
    deadline = time.time() + seconds
    while time.time() < deadline:
        s = status()
        if s and test(s):
            return s
        time.sleep(1)
    raise TimeoutError(f"waited {seconds:.0f} s for {what}")


def game_running():
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Ace7Game.exe"], capture_output=True, text=True)
    return "Ace7Game.exe" in r.stdout


def file_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def read_from(path, offset):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            f.seek(offset)
            return f.read()
    except OSError:
        return ""


def events_from(offset):
    out = []
    for line in read_from(os.path.join(PILOT_DIR, "events.jsonl"), offset).splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def order(*words):
    pilot.send([str(w) for w in words])


# ---- getting into the mission ------------------------------------------------------------

def plane_ready(s):
    return s.get("plane") and (s.get("input_enabled") or {}).get("move")


def page():
    """The menu page showing, as the pilot sees it (status.json 'page'), or None."""
    return status().get("page") or None


def wait_page(pages, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        p = page()
        if p in pages:
            return p
        time.sleep(0.5)
    return page()


def press_until(key, pages, tries=4, wait_s=4.0):
    """Press a key until one of the pages shows (screens sometimes swallow a press)."""
    for _ in range(tries):
        keys([key])
        p = wait_page(pages, wait_s)
        if p in pages:
            return p
    return page()


STORY = ("CampaignMissionTitle_C", "CampaignMV_C", "CampaignBriefingMV_C", "CampaignBriefingMenu_C", "CampaignMenuActionSelect_C")


def goto_mission(mission=1, difficulty="casual", from_title=True, folder=None):
    """From the title screen or the main menu to the first moment the player can fly.

    Every step checks which menu page the game shows (the pilot reports it: the menus live
    inside one front-screen widget and each page is its own widget, mapped on 18 Oct,
    workbench section 10) and presses until the next page appears. The traps: the Campaign
    submenu opens on "Continue", which goes straight into your story save's current mission,
    and a Down pressed while it slides in is swallowed; so the route checks where Enter led,
    and backs out of a story mission through Mission Prep > Quit Mission if it went wrong.
    """
    if not game_running():
        raise RuntimeError("the copy is not running")
    wait_status(lambda s: "screens" in s, 90, "the pilot to report (is CoopPilotMod loaded?)")
    free_flight = difficulty.lower() == "free_flight"

    def fail(what):
        if folder:
            picture(os.path.join(folder, "pictures", "menu-route-stuck.png"))
        raise RuntimeError(f"menu route: {what} (page now: {page()})")

    p = page()
    say(f"menu page at the start: {p}")
    if p in PREP:
        say("already in Mission Prep or the hangar: carrying on from there")
        return prep_and_sortie(fail)
    if p not in ("CampaignMenuMain_C",) + STORY and p not in ("CampaignFreeMissionDifficulty_C", "CampaignFreeMission_C"):
        if from_title or p in (None, "MainTitle_C"):
            say("title screen: Enter")
            keys(["Enter"], wait_ms=7000)
        say("main menu: Campaign")
        if press_until("Enter", ("CampaignMenuMain_C",), tries=3, wait_s=5) != "CampaignMenuMain_C":
            fail("Campaign did not open")
    for round_ in range(3):
        p = page()
        if p == "CampaignMenuMain_C":
            time.sleep(2.0)                     # let the submenu finish sliding in
            say("Campaign submenu: Down to Free Mission, Enter")
            keys(["Down"], wait_ms=1200)
            keys(["Enter"])
            p = wait_page(("CampaignFreeMissionDifficulty_C",) + STORY, 6)
        if p in STORY:
            say(f"landed in the story mission ({p}); backing out through Mission Prep > Quit Mission")
            if p != "CampaignMenuActionSelect_C":
                for _ in range(150):
                    if page() == "CampaignBriefingMenu_C":
                        break
                    keys(["Escape"], wait_ms=300)
                press_until("F1", ("CampaignMenuActionSelect_C",), tries=4, wait_s=4)
            keys(["Down"], wait_ms=600)
            keys(["Down"], wait_ms=600)
            keys(["Down"], wait_ms=600)
            keys(["Enter"])
            wait_page(("CampaignMenuMain_C",), 10)
            continue
        if p == "CampaignFreeMissionDifficulty_C":
            break
    else:
        fail("could not reach the Free Mission difficulty list")

    d = DIFFICULTIES.index(difficulty.lower())
    say(f"difficulty: {difficulty}")
    time.sleep(1.0)
    for _ in range(d):
        keys(["Down"], wait_ms=500)
    keys(["Enter"])
    if wait_page(("CampaignFreeMission_C",), 6) != "CampaignFreeMission_C":
        fail("the mission list did not open")
    say(f"mission {mission:02d}")
    time.sleep(1.5)
    for _ in range(mission - 1):
        keys(["Down"], wait_ms=400)
    keys(["Enter"])
    if not free_flight:
        if wait_page(("CampaignMissionTitle_C", "CampaignMV_C", "CampaignBriefingMV_C"), 12) is None:
            fail("the briefing did not start")
        say("briefing: Escape until the operation map shows")
        for n in range(200):
            if page() == "CampaignBriefingMenu_C":
                say(f"operation map after {n} Escape presses")
                break
            keys(["Escape"], wait_ms=900)
        else:
            fail("the briefing did not end")
        time.sleep(2.0)
        if press_until("F1", ("CampaignMenuActionSelect_C",), tries=5, wait_s=4) != "CampaignMenuActionSelect_C":
            fail("Mission Prep did not open")
    elif wait_page(("CampaignMenuActionSelect_C",), 15) != "CampaignMenuActionSelect_C":
        fail("Mission Prep did not open")
    return prep_and_sortie(fail)


PREP = ("CampaignMenuActionSelect_C", "CampaignHangarAircraft_C", "CampaignHangarWeapon_C", "CampaignHangarReview_C")


def prep_and_sortie(fail):
    """From Mission Prep (or any hangar page after it) to the plane on its runway or in the air."""
    if page() == "CampaignMenuActionSelect_C":
        say("Mission Prep: Start Mission")
        if press_until("Enter", ("CampaignHangarAircraft_C",), tries=4) != "CampaignHangarAircraft_C":
            fail("the aircraft page did not open")
    if page() == "CampaignHangarAircraft_C":
        say("aircraft: the copy's last-used plane")
        if press_until("Enter", ("CampaignHangarWeapon_C",), tries=4) != "CampaignHangarWeapon_C":
            fail("the special weapon page did not open")
    if page() == "CampaignHangarWeapon_C":
        say("special weapon: the last-used one")
        if press_until("Enter", ("CampaignHangarReview_C",), tries=4) != "CampaignHangarReview_C":
            fail("the standby page did not open")
    say("standby: Sortie")
    for _ in range(4):
        keys(["Enter"])
        deadline = time.time() + 8
        while time.time() < deadline and page() == "CampaignHangarReview_C":
            time.sleep(0.5)
        if page() != "CampaignHangarReview_C":
            break
    s = wait_status(lambda s: s.get("plane"), 150, "the mission to load")
    say(f"mission loaded, plane {s.get('plane')}")
    s = wait_status(plane_ready, 150, "the controls to switch on")
    say(f"controls on: {s.get('kmh')} km/h at {s.get('alt_m')} m")
    return s


def retry(how):
    """On the retry menu after a failed attempt: from the checkpoint (fast) or the start."""
    say(f"retry ({how})")
    # After "Mission failed" the game first shows the crash for several seconds; the retry
    # menu (Retry from checkpoint / Retry mission / Quit mission) comes after that.
    time.sleep(8)
    if how == "mission":
        keys(["Down"], wait_ms=800)
    for _ in range(8):
        keys(["Enter"], wait_ms=4000)
        s = status()
        if not s.get("failed") and not s.get("plane"):
            break                      # the restart is loading
        if plane_ready(s) and not s.get("failed"):
            return
    wait_status(lambda s: plane_ready(s) and not s.get("failed"), 150, "the retried mission to start")


# ---- one attempt ---------------------------------------------------------------------

def fly_attempt(n, order_, folder, limit_s):
    """Fly until the mission is accomplished, fails, or the time limit passes."""
    ev_start = file_size(os.path.join(PILOT_DIR, "events.jsonl"))
    log_start = file_size(os.path.join(PILOT_DIR, "pilot.log"))
    t0 = time.time()
    started = datetime.datetime.now()
    order("mark", f"attempt {n} begins")
    picture(os.path.join(folder, "pictures", f"attempt{n}-start.png"))
    s = status()
    if (s.get("alt_m") or 0) < 30 and (s.get("kmh") or 0) < 100:
        say("on the runway: take-off")
        order("takeoff")
        deadline = time.time() + 45
        while time.time() < deadline:
            if any(e.get("kind") == "takeoff_end" for e in events_from(ev_start)):
                break
            time.sleep(1)
    tactics = order_.get("tactics") or {}
    words = ["fly", "attack"]
    if "floor_m" in tactics:
        words += ["floor", tactics["floor_m"]]
    if "missile_range_m" in tactics:
        words += ["range", tactics["missile_range_m"]]
    order(*words)
    result, cause = None, None
    last_report = 0
    while True:
        time.sleep(2)
        evs = events_from(ev_start)
        kinds = [e.get("kind") for e in evs]
        if "mission_accomplished" in kinds:
            result, cause = "completed", "mission accomplished"
            break
        fails = [k for k in kinds if k in FAIL_EVENTS]
        if fails:
            result, cause = "failed", FAIL_EVENTS[fails[0]]
            break
        s = status()
        if s.get("failed") and not s.get("completed"):
            result, cause = "failed", "the mission reported failure"
            break
        if time.time() - t0 > limit_s:
            result, cause = "stopped", f"time limit of {limit_s / 60:.0f} min"
            break
        if time.time() - last_report > 30:
            last_report = time.time()
            kills = sum(1 for e in evs if e.get("kind") == "kill")
            say(f"  attempt {n}: {time.time() - t0:.0f} s, {kills} kills, health {s.get('health')}/{s.get('max_health')}, score {s.get('score')}")
    time.sleep(1.5)
    order("fly", "stop")
    picture(os.path.join(folder, "pictures", f"attempt{n}-end.png"))
    evs = events_from(ev_start)
    duration = time.time() - t0
    say(f"attempt {n}: {result} ({cause}) after {duration:.0f} s")
    with open(os.path.join(folder, "events.jsonl"), "a", encoding="utf-8") as f:
        for e in evs:
            e["attempt"] = n
            f.write(json.dumps(e) + "\n")
    with open(os.path.join(folder, "pilot.log"), "a", encoding="utf-8") as f:
        f.write(f"===== attempt {n} =====\n")
        f.write(read_from(os.path.join(PILOT_DIR, "pilot.log"), log_start))
    # this attempt's flight logs (the pilot starts a new one for every order)
    for name in sorted(os.listdir(PILOT_DIR)):
        if name.startswith("flight-") and name.endswith(".csv"):
            p = os.path.join(PILOT_DIR, name)
            if os.path.getmtime(p) >= t0 - 1:
                shutil.copy2(p, os.path.join(folder, f"attempt{n}-{name}"))
    return {"n": n, "result": result, "cause": cause, "duration_s": duration, "started": started,
            "events": evs, "final": status()}


# ---- the report ----------------------------------------------------------------------

def write_report(folder, order_, attempts, notes):
    lines = []
    m = order_.get("mission")
    name = order_.get("name", "")
    done = [a for a in attempts if a["result"] == "completed"]
    lines.append(f"# Playtest: Mission {int(m):02d} {name}".rstrip())
    lines.append("")
    run_by = order_.get("run_by", "tools\\playtest.py")
    lines.append(f"Run {attempts[0]['started']:%d %b %Y, %H:%M} by {run_by}; "
                 f"difficulty {order_.get('difficulty', 'casual')}, mode {order_.get('mode', 'fair')}.")
    lines.append("")
    if done:
        lines.append(f"**Completed on attempt {done[0]['n']} of {len(attempts)}.**")
    else:
        lines.append(f"**Not completed** in {len(attempts)} attempt(s).")
    lines.append("")
    lines.append("| Attempt | Result | Why it ended | Time | Kills | Missiles fired (special) | Damage taken | Missiles at us (lock broken) | Score |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for a in attempts:
        ev = a["events"]
        kills = [e for e in ev if e.get("kind") == "kill"]
        shots = sum(1 for e in ev if e.get("kind") == "missile")
        dmg = sum(float(e.get("amount", 0)) for e in ev if e.get("kind") == "damage")
        launched = [e for e in ev if e.get("kind") == "launch"]
        if launched:   # real launches counted from the ammunition (limited on Normal and up)
            shots = sum(int(e.get("n", 1)) for e in launched if e.get("weapon") == "missile")
            special = sum(int(e.get("n", 1)) for e in launched if e.get("weapon") == "special")
        else:          # unlimited ammunition: trigger presses
            special = sum(1 for e in ev if e.get("kind") == "missile" and e.get("special"))
        at_us = sum(1 for e in ev if e.get("kind") == "missile_at_me")
        broken = sum(1 for e in ev if e.get("kind") == "missile_lost_lock")
        lines.append(f"| {a['n']} | {a['result']} | {a['cause']} | {a['duration_s'] / 60:.1f} min | {len(kills)} | {shots} ({special}) | "
                     f"{dmg:.0f} | {at_us} ({broken}) | {a['final'].get('score', '?')} |")
    for a in attempts:
        lines.append("")
        lines.append(f"## Attempt {a['n']}")
        lines.append("")
        t_first = None
        for e in a["events"]:
            k = e.get("kind")
            if t_first is None and "t" in e:
                t_first = e["t"]
            rel = e.get("t", 0) - (t_first or 0)
            stamp = f"{int(rel // 60):02d}:{int(rel % 60):02d}"
            if k == "kill":
                lines.append(f"- {stamp} destroyed {e.get('target')} {e.get('callsign', '')} "
                             f"({e.get('missiles')} missiles, {float(e.get('after_s', 0)):.0f} s after picking it)")
            elif k == "damage":
                lines.append(f"- {stamp} took {float(e.get('amount', 0)):.0f} damage, health {e.get('health')}")
            elif k in ("phase_start", "phase_cleared", "phase_failed"):
                lines.append(f"- {stamp} {k.replace('_', ' ')}: {e.get('phase')}")
            elif k in FAIL_EVENTS or k == "mission_accomplished":
                lines.append(f"- {stamp} **{k.replace('_', ' ')}**")
            elif k == "missile_at_me":
                lines.append(f"- {stamp} missile fired at us by {e.get('from')} from {float(e.get('dist_m', 0)):.0f} m ({e.get('homing')})")
            elif k == "missile_lost_lock":
                lines.append(f"- {stamp} that missile lost its lock at {float(e.get('dist_m', 0)):.0f} m")
            elif k == "missile_gone":
                lines.append(f"- {stamp} missile from {e.get('from')} gone after {float(e.get('flew_s', 0)):.0f} s, closest {float(e.get('closest_m', 0)):.0f} m")
            elif k == "evade":
                lines.append(f"- {stamp} break turn: missile {float(e.get('dist_m', 0)):.0f} m away, impact in {float(e.get('tgo_s', 0)):.1f} s")
            elif k == "weapon_switch":
                lines.append(f"- {stamp} weapon switch to {e.get('to')} ({e.get('why')}, target {float(e.get('dist_m', 0)):.0f} m)")
            elif k == "prediction_stats":
                lines.append(f"- {stamp} how well enemy positions 2 s ahead were predicted: {e.get('text')}")
            elif k == "pursuer":
                lines.append(f"- {stamp} {e.get('enemy')} is after us, {float(e.get('dist_m', 0)):.0f} m behind ({e.get('state')})")
            elif k in ("takeoff_end", "ground_recovery", "beyond_pullout", "frozen", "missile_warning", "flare"):
                detail = ", ".join(f"{x}={y}" for x, y in e.items() if x not in ("t", "kind", "clock", "attempt"))
                lines.append(f"- {stamp} {k.replace('_', ' ')}{(': ' + detail) if detail else ''}")
    if notes:
        lines.append("")
        lines.append("## Notes")
        lines.append("")
        lines.extend(f"- {n}" for n in notes)
    lines.append("")
    lines.append("Files: events.jsonl (every event), attempt*-flight-*.csv (the plane ten times a second), "
                 "pilot.log (the pilot's commentary), pictures\\, saves-check.txt.")
    with open(os.path.join(folder, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# ---- a whole test --------------------------------------------------------------------

def run(order_path):
    order_ = read_order(order_path)
    mission = int(order_.get("mission", 1))
    difficulty = str(order_.get("difficulty", "casual"))
    attempts_max = int(order_.get("attempts", 3))
    limit_s = float(order_.get("time_limit_min", 25)) * 60
    how = str(order_.get("retry", "checkpoint"))
    notes = []
    if order_.get("plane"):
        notes.append(f"Plane '{order_['plane']}' asked for, but choosing planes is not built yet: the copy's last-used plane flew.")
    if str(order_.get("mode", "fair")) != "fair":
        notes.append(f"Mode '{order_['mode']}' asked for; only 'fair' is built so far, so it flew fair.")
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    folder = os.path.join(ROOT, "playtests", f"{stamp}_m{mission:02d}_{order_.get('name', difficulty)}")
    os.makedirs(os.path.join(folder, "pictures"), exist_ok=True)
    shutil.copy2(order_path, os.path.join(folder, "order.yaml"))
    say(f"test folder: {folder}")

    started_game = False
    wrote_in_use = False
    if not os.path.exists(IN_USE):
        with open(IN_USE, "w", encoding="utf-8") as f:
            f.write("# The game copy is in use\n\ntools\\playtest.py is running a test "
                    f"({datetime.datetime.now():%d %b %Y %H:%M}). Please wait; this note is removed when it ends.\n")
        wrote_in_use = True
    attempts = []
    try:
        s = status()
        if not game_running():
            say("starting the copy (tools\\start-copy.ps1 backs up your saves first)")
            r = subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "start-copy.ps1")],
                               capture_output=True, text=True)
            say(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr.strip()[:200])
            started_game = True
            time.sleep(20)
            goto_mission(mission, difficulty, from_title=True, folder=folder)
        elif plane_ready(s):
            notes.append("The copy was already in a mission when the test began; the test flew from there.")
        else:
            goto_mission(mission, difficulty, from_title=bool(order_.get("from_title", False)), folder=folder)
        for n in range(1, attempts_max + 1):
            a = fly_attempt(n, order_, folder, limit_s)
            attempts.append(a)
            if a["result"] == "completed":
                break
            if n < attempts_max:
                if a["result"] == "stopped":
                    keys(["Escape"], wait_ms=1500)      # pause menu: Restart from checkpoint is second
                    keys(["Down"], wait_ms=800)
                    keys(["Enter"], wait_ms=3000)
                    wait_status(lambda s: plane_ready(s), 150, "the restarted mission")
                else:
                    retry(how)
    finally:
        if attempts:
            write_report(folder, order_, attempts, notes)
            say(f"report: {os.path.join(folder, 'report.md')}")
        if order_.get("close_game", started_game):
            subprocess.run(["powershell", "-NoProfile", "-Command", "Stop-Process -Name Ace7Game -Force"],
                           capture_output=True, text=True)
            say("closed the copy")
            time.sleep(3)
        r = subprocess.run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "compare-saves.ps1")],
                           capture_output=True, text=True)
        with open(os.path.join(folder, "saves-check.txt"), "w", encoding="utf-8") as f:
            f.write(r.stdout + r.stderr)
        say("saves check: " + (r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "?"))
        if wrote_in_use and os.path.exists(IN_USE):
            os.remove(IN_USE)
    return folder


def rebuild_report(folder):
    """Write report.md again from a test folder's events.jsonl and order.yaml (for example
    after the report writer learned about new kinds of events)."""
    order_ = read_order(os.path.join(folder, "order.yaml"))
    by_attempt = {}
    with open(os.path.join(folder, "events.jsonl"), "r", encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            by_attempt.setdefault(int(e.get("attempt", 1)), []).append(e)
    attempts = []
    day = datetime.datetime.fromtimestamp(os.path.getmtime(os.path.join(folder, "events.jsonl"))).date()
    for n in sorted(by_attempt):
        ev = by_attempt[n]
        kinds = [e.get("kind") for e in ev]
        if "mission_accomplished" in kinds:
            result, cause = "completed", "mission accomplished"
        else:
            fails = [k for k in kinds if k in FAIL_EVENTS]
            result, cause = ("failed", FAIL_EVENTS[fails[0]]) if fails else ("stopped", "time limit or stopped")
        ts = [e["t"] for e in ev if "t" in e]
        first_clock = next((e["clock"] for e in ev if "clock" in e), "00:00:00")
        hh, mm, ss = (int(x) for x in first_clock.split(":"))
        attempts.append({"n": n, "result": result, "cause": cause, "duration_s": (max(ts) - min(ts)) if ts else 0,
                         "started": datetime.datetime.combine(day, datetime.time(hh, mm, ss)), "events": ev,
                         "final": {"score": "?"}})
    write_report(folder, order_, attempts, [])
    return os.path.join(folder, "report.md")


def main(argv):
    if len(argv) >= 3 and argv[1] == "run":
        run(argv[2])
        return 0
    if len(argv) >= 3 and argv[1] == "report":
        print(rebuild_report(argv[2]))
        return 0
    if len(argv) >= 2 and argv[1] == "goto":
        mission, difficulty = 1, "casual"
        if "--mission" in argv:
            mission = int(argv[argv.index("--mission") + 1])
        if "--difficulty" in argv:
            difficulty = argv[argv.index("--difficulty") + 1]
        goto_mission(mission, difficulty, from_title="--from-menu" not in argv)
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
