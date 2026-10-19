"""The playtest bot's story-campaign driver (19 Oct 2026): flies Ace Combat 7's campaign in the
game copy from the Campaign menu onwards, mission after mission, with tools\\playtest.py's
pieces (menus, attempts, retries, reports) and the pilot (CoopPilotMod).

    python tools\\campaign.py run playtests\\orders\\campaign-ace.yaml
        the whole campaign as the order says (start: restart or continue, difficulty,
        attempts per mission, last mission); stops when a mission is not completed in its
        attempts, so a session can improve the bot and run it again with start: continue
    python tools\\campaign.py step
        look at the screen once, say what the driver would do, and do it (for learning)

What the story looks like to the driver (learned 19 Oct 2026, workbench section 15):
    Campaign submenu (CampaignMenuMain_C): RESTART STORY / CONTINUE / FREE MISSION / SP MISSION;
        which item is selected is read from the page's description text (menu_desc)
    reset dialog (DialogWidget_C): YES / NO, NO selected; the selected one is drawn brighter
    difficulty (CampaignMenuDifficulty_C): CASUAL -EASY- / EASY / NORMAL / HARD / ACE
    movies (CampaignMV_C, the opening and cutscenes): a key shows "F1 SKIP", F1 skips
    mission title (CampaignMissionTitle_C: "MISSION 01" / "Charge Assault"), briefing movie
        (CampaignBriefingMV_C) and pages: Escape, as in a free mission
    operation map (CampaignBriefingMenu_C): F1 opens Mission Prep (CampaignMenuActionSelect_C)
    hangar: CampaignHangarAircraft_C, CampaignHangarWeapon_C, CampaignHangarReview_C (Sortie)
    after the mission: (being mapped) replay, results, debriefing, the next mission's movies

Per mission, playtests\\missions\\mNN\\ may hold plan.txt (the pilot's orders per phase,
playtest.py's plan format) and mission.txt (lines "key: value": plane, weapon, attempts,
time_limit_min, retry). Every mission gets its own report folder and a line in
playtests\\campaign-<name>.md.
"""

import datetime
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import playtest as pt  # noqa: E402

ROOT = pt.ROOT
say = pt.say
SHOTS = os.path.join(ROOT, "playtests", "campaign-pictures")

MOVIE_PAGES = ("CampaignMV_C",)
BRIEFING_PAGES = ("CampaignMissionTitle_C", "CampaignBriefingMV_C")
DIFFICULTY_ORDER = ["casual", "easy", "normal", "hard", "ace"]


def st():
    return pt.status()


def menu_fail(what):
    raise RuntimeError(f"menu route: {what} (page now: {pt.page()})")


def mission_number(s):
    """The mission being flown or briefed: from the loaded level (ms01) or the title page."""
    lvl = s.get("mission_level") or ""
    m = re.match(r"ms(\d+)", str(lvl))
    if m:
        return int(m.group(1))
    m = re.search(r"(\d+)", str(s.get("story_mission") or ""))
    if m:
        return int(m.group(1))
    return None


def read_mission_cfg(n):
    folder = os.path.join(ROOT, "playtests", "missions", f"m{n:02d}")
    cfg = {"folder": folder}
    path = os.path.join(folder, "mission.txt")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.split("#", 1)[0].strip()
                if ":" in line:
                    k, v = line.split(":", 1)
                    cfg[k.strip()] = pt.parse_value(v)
    plan_path = os.path.join(folder, "plan.txt")
    cfg["plan"] = pt.read_plan(plan_path) if os.path.exists(plan_path) else None
    return cfg


class Driver:
    def __init__(self, order):
        self.order = order
        self.name = str(order.get("name", "campaign"))
        self.difficulty = str(order.get("difficulty", "ace")).lower()
        self.restart = str(order.get("start", "continue")).lower() == "restart"
        self.restart_done = False
        self.attempts = int(order.get("attempts", 10))
        self.limit_s = float(order.get("time_limit_min", 30)) * 60
        self.last_mission = int(order.get("last_mission", 20))
        self.log_path = os.path.join(ROOT, "playtests", f"campaign-{self.name}.md")
        self.unknown_seen = {}
        self.stop = None
        self.flown = []
        self.briefed = None              # the mission number last seen on a title page
        self.results_shot = {}
        self.last_folder = None

    # ---- the campaign log ----------------------------------------------------------------
    def record(self, line):
        new = not os.path.exists(self.log_path)
        with open(self.log_path, "a", encoding="utf-8") as f:
            if new:
                f.write(f"# Campaign run: {self.name} ({self.difficulty})\n\n"
                        "Written by tools\\campaign.py, one line per mission flown (newest last).\n\n"
                        "| When | Mission | Result | Attempts | Time | Kills | Damage | Report |\n"
                        "|---|---|---|---|---|---|---|---|\n")
            f.write(line + "\n")

    # ---- screens ---------------------------------------------------------------------------
    def learn(self, s, what):
        """An unknown screen: a picture and the widget list, once per kind of screen."""
        key = (s.get("page"), tuple(s.get("screens") or []))
        n = self.unknown_seen.get(key, 0)
        self.unknown_seen[key] = n + 1
        if n == 0:
            os.makedirs(SHOTS, exist_ok=True)
            shot = os.path.join(SHOTS, datetime.datetime.now().strftime("%H%M%S") + f"-{s.get('page') or 'unknown'}.png")
            pt.picture(shot)
            pt.order("uilist")
            say(f"unknown screen ({what}): page {s.get('page')}, screens {s.get('screens')}; picture {shot}")
        return n

    def handle_dialog(self, s):
        d = s["dialog"]
        text = (d.get("text") or "").lower()
        opts = [o.upper() for o in d.get("options") or []]
        want = None
        if "reset your campaign" in text:
            want = "YES" if self.restart and not self.restart_done else "NO"
            if want == "YES":
                self.restart_done = True
        elif "yes" in [o.lower() for o in opts]:
            # unknown yes/no question: log it and take the safe default the game offers
            say(f"dialog: '{d.get('text')}' options {opts}, selected {d.get('selected')}: keeping the game's default")
            pt.keys(["Enter"], wait_ms=1500)
            return
        else:
            say(f"dialog: '{d.get('text')}' {opts}: Enter")
            pt.keys(["Enter"], wait_ms=1500)
            return
        target = opts.index(want) + 1 if want in opts else None
        say(f"dialog: '{d.get('text')[:80]}...' -> {want}")
        for _ in range(4):
            sel = (st().get("dialog") or {}).get("selected")
            if sel == target or target is None:
                break
            pt.keys(["Left" if (sel or 99) > target else "Right"], wait_ms=600)
        pt.keys(["Enter"], wait_ms=2500)

    def campaign_menu(self, s):
        time.sleep(1.5)                         # let the submenu finish sliding in
        if self.restart and not self.restart_done:
            want, label = "from the beginning", "RESTART STORY"
        else:
            want, label = "continue the game", "CONTINUE"
        for _ in range(8):
            desc = (st().get("menu_desc") or "").lower()
            if want in desc:
                break
            pt.keys(["Up"], wait_ms=700)
        say(f"Campaign submenu: {label}")
        pt.keys(["Enter"], wait_ms=2500)

    def difficulty_menu(self, s):
        idx = DIFFICULTY_ORDER.index(self.difficulty) if self.difficulty in DIFFICULTY_ORDER else 4
        pt.keys(["Up"] * 6, gap_ms=200)
        time.sleep(0.4)
        for _ in range(idx):
            pt.keys(["Down"], wait_ms=500)
        say(f"difficulty: {self.difficulty} ({st().get('menu_desc')})")
        pt.keys(["Enter"], wait_ms=3000)

    def skip_movie(self, s):
        # a key shows "F1 SKIP"; F1 skips (the opening movie, 19 Oct 2026)
        pt.keys(["Escape"], wait_ms=700)
        pt.keys(["F1"], wait_ms=2500)

    def briefing(self, s):
        n = mission_number(s)
        if n:
            self.briefed = n
        if s.get("story_mission"):
            say(f"briefing: {s.get('story_mission')} {s.get('story_title')}")
        presses = 0
        for _ in range(300):
            p = pt.page()
            if p not in BRIEFING_PAGES + MOVIE_PAGES:
                break
            pt.keys(["Escape"], wait_ms=300)
            presses += 1
            time.sleep(0.4)
        say(f"briefing done after {presses} Escape presses; page now {pt.page()}")
        return n

    # ---- the hangar: plane and special weapon ------------------------------------------------
    PLANES_FILE = os.path.join(ROOT, "playtests", "missions", "planes.json")

    def planes_known(self):
        try:
            with open(self.PLANES_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def choose_plane(self, want):
        """On the aircraft page: move the cursor until the plane named 'want' (or its number)
        is under it. The game's selected-plane number follows the cursor; names are read from
        the page and remembered in playtests\\missions\\planes.json."""
        known = self.planes_known()
        want_s = str(want).strip().lower()
        def match(s):
            name = (s.get("hangar_plane") or "").strip().lower()
            return name == want_s or str(s.get("hangar_plane_id")) == want_s
        seen = set()
        for direction in ("Up", "Down"):
            for _ in range(70):
                time.sleep(0.6)
                s = st()
                pid, name = s.get("hangar_plane_id"), s.get("hangar_plane")
                if pid is not None and name:
                    known[name] = pid
                if match(s):
                    with open(self.PLANES_FILE, "w", encoding="utf-8") as f:
                        json.dump(known, f, indent=1, sort_keys=True)
                    say(f"aircraft: {name} (number {pid})")
                    return True
                if (pid, direction) in seen and direction == "Down":
                    break
                seen.add((pid, direction))
                pt.keys([direction], wait_ms=350)
        with open(self.PLANES_FILE, "w", encoding="utf-8") as f:
            json.dump(known, f, indent=1, sort_keys=True)
        say(f"aircraft: '{want}' not found in the list; keeping {st().get('hangar_plane')}")
        return False

    def choose_weapon(self, want):
        s = st()
        names = [str(x).upper() for x in (s.get("hangar_weapons") or [])]
        if str(want).upper() not in names:
            say(f"special weapon: '{want}' not offered ({names}); keeping {names[s.get('hangar_swp') or 0] if names else '?'}")
            return False
        target = names.index(str(want).upper())
        for _ in range(6):
            cur = st().get("hangar_swp")
            if cur == target:
                break
            pt.keys(["Down" if (cur or 0) < target else "Up"], wait_ms=700)
        say(f"special weapon: {want}")
        return st().get("hangar_swp") == target

    def prep(self, s):
        """Mission Prep and the hangar, with the plane and weapon the mission's mission.txt
        names (or the order's), then Sortie."""
        n = mission_number(s) or self.briefed
        cfg = read_mission_cfg(n) if n else {}
        plane = cfg.get("plane") or self.order.get("plane")
        weapon = cfg.get("weapon") or self.order.get("weapon")
        if pt.page() == "CampaignMenuActionSelect_C":
            if pt.press_until("Enter", ("CampaignHangarAircraft_C",), tries=4) != "CampaignHangarAircraft_C":
                menu_fail("the aircraft page did not open")
        if pt.page() == "CampaignHangarAircraft_C":
            if plane:
                self.choose_plane(plane)
            if pt.press_until("Enter", ("CampaignHangarWeapon_C",), tries=4) != "CampaignHangarWeapon_C":
                menu_fail("the special weapon page did not open")
        if pt.page() == "CampaignHangarWeapon_C":
            time.sleep(1.0)
            if weapon:
                self.choose_weapon(weapon)
        pt.prep_and_sortie(menu_fail)

    # ---- one mission ---------------------------------------------------------------------
    def fly_mission(self, s):
        n = mission_number(s) or 0
        cfg = read_mission_cfg(n) if n else {"plan": None}
        plan = cfg.get("plan")
        if plan:
            pt.install_plan_files(plan)
        attempts_max = int(cfg.get("attempts", self.attempts))
        limit_s = float(cfg.get("time_limit_min", self.limit_s / 60)) * 60
        how = str(cfg.get("retry", "checkpoint"))
        stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
        folder = os.path.join(ROOT, "playtests", f"{stamp}_m{n:02d}_{self.name}")
        os.makedirs(os.path.join(folder, "pictures"), exist_ok=True)
        order_ = {"mission": n, "name": self.name, "difficulty": self.difficulty, "mode": "fair",
                  "run_by": "tools\\campaign.py (story mode)", "tactics": {}}
        plan_name = ("playtests\\missions\\m%02d\\plan.txt" % n) if plan else "-"
        with open(os.path.join(folder, "order.yaml"), "w", encoding="utf-8") as f:
            f.write(f"# story mission flown by tools\\campaign.py\nmission: {n}\ndifficulty: {self.difficulty}\n"
                    f"attempts: {attempts_max}\ntime_limit_min: {limit_s / 60:.0f}\nretry: {how}\nplan: {plan_name}\n")
        say(f"=== Mission {n:02d}: flying (up to {attempts_max} attempts, {limit_s / 60:.0f} min each), folder {folder}")
        attempts = []
        entry = "start"
        phase_now = next(iter(plan["retry"]), None) if plan else None
        t0 = time.time()
        for a in range(1, attempts_max + 1):
            att = pt.fly_attempt(a, order_, folder, limit_s, plan, entry)
            attempts.append(att)
            if att["result"] == "completed":
                break
            phase_now = att.get("phase") or phase_now
            if a < attempts_max:
                this_how = plan["retry"].get(phase_now, how) if plan else how
                entry = (phase_now or "start") if this_how == "checkpoint" else "start"
                if entry == "start":
                    phase_now = next(iter(plan["retry"]), None) if plan else None
                if att["result"] == "stopped":
                    pt.keys(["Escape"], wait_ms=1500)
                    pt.keys(["Down"], wait_ms=800)
                    pt.keys(["Enter"], wait_ms=3000)
                    pt.wait_status(lambda x: pt.plane_ready(x), 150, "the restarted mission")
                elif not pt.retry(this_how):
                    entry = phase_now or "start"
        self.last_folder = folder
        self.briefed = n or self.briefed
        pt.write_report(folder, order_, attempts, [f"Story mode, flown by tools\\campaign.py ({self.name})."])
        done = attempts[-1]["result"] == "completed"
        kills = sum(sum(1 for e in x["events"] if e.get("kind") == "kill") for x in attempts)
        dmg = sum(sum(pt.fnum(e.get("amount")) for e in x["events"] if e.get("kind") == "damage") for x in attempts)
        rel = os.path.relpath(os.path.join(folder, "report.md"), os.path.join(ROOT, "playtests")).replace("\\", "/")
        self.record(f"| {datetime.datetime.now():%d %b %H:%M} | {n:02d} | {'completed' if done else 'NOT completed'} | "
                    f"{len(attempts)} | {(time.time() - t0) / 60:.0f} min | {kills} | {dmg:.0f} | [report]({rel}) |")
        self.flown.append((n, done))
        say(f"=== Mission {n:02d}: {'COMPLETED' if done else 'not completed'} after {len(attempts)} attempt(s)")
        if not done:
            self.stop = f"Mission {n:02d} not completed in {len(attempts)} attempts"
        elif n >= self.last_mission:
            self.stop = f"Mission {n:02d} was the last one asked for"
        return done

    # ---- one look at the screen, one action ------------------------------------------------
    def step(self):
        s = st()
        if not s:
            time.sleep(1)
            return "no status"
        p = s.get("page")
        if s.get("dialog"):
            self.handle_dialog(s)
            return "dialog"
        if pt.plane_ready(s) and not s.get("failed") and not s.get("completed") and p not in ("CampaignHudPause_C", "CampaignRetry_C"):
            self.fly_mission(s)
            return "mission"
        if p == "MainTitle_C":
            pt.keys(["Enter"], wait_ms=5000)
            return "title"
        if p == "MainMenu_C":
            pt.press_until("Enter", ("CampaignMenuMain_C",), tries=4, wait_s=4)
            return "main menu"
        if p == "CampaignMenuMain_C":
            self.campaign_menu(s)
            return "campaign menu"
        if p == "CampaignMenuDifficulty_C":
            self.difficulty_menu(s)
            return "difficulty"
        if p in MOVIE_PAGES or (p and re.match(r"CampaignMv", p, re.I) and p != "CampaignMV_C" and "Briefing" not in p):
            self.skip_movie(s)
            return "movie"
        if p in BRIEFING_PAGES:
            self.briefing(s)
            return "briefing"
        if p == "CampaignBriefingMenu_C":
            time.sleep(1.5)
            pt.press_until("F1", ("CampaignMenuActionSelect_C",), tries=4, wait_s=4)
            return "operation map"
        if p in pt.PREP:
            self.prep(s)
            return "prep and sortie"
        if p == "ReplayWidget_C":
            # the replay after "mission accomplished": the first Enter shows "PRESS Enter TO
            # SKIP", a second one while it shows skips the whole replay
            pt.keys(["Enter", "Enter"], gap_ms=500, wait_ms=4000)
            return "replay"
        if p == "CampaignDebriefing_C":
            # MISSION RESULTS: the first Enter finishes the counting, the next goes on
            n = self.briefed or mission_number(s)
            if n and not self.results_shot.get(n):
                # F1 skips the counting animation; then a picture of the final numbers
                time.sleep(3)
                pt.keys(["F1"], wait_ms=2500)
                self.results_shot[n] = True
                if self.last_folder:
                    pt.picture(os.path.join(self.last_folder, "pictures", "results.png"))
                return "results"
            pt.keys(["Enter"], wait_ms=3000)
            return "results"
        if p == "CampaignMenuNext_C":
            for _ in range(5):
                if "next mission" in (st().get("menu_desc") or "").lower():
                    break
                pt.keys(["Up"], wait_ms=600)
            say("mission complete: NEXT MISSION")
            pt.keys(["Enter"], wait_ms=4000)
            return "next mission"
        if p == "CampaignRetry_C":
            say("retry menu outside an attempt: Retry mission")
            pt.retry("mission")
            return "retry menu"
        n = self.learn(s, "no handler")
        # something new: give it time first (screens advance by themselves), then Enter
        if n >= 2:
            pt.keys(["Enter"], wait_ms=2500)
        else:
            time.sleep(3)
        return "unknown"

    def run(self):
        while not self.stop:
            what = self.step()
            if what in ("unknown", "no status"):
                continue
        say(f"campaign driver stops: {self.stop}")


def main(argv):
    if len(argv) >= 3 and argv[1] == "run":
        order = pt.read_order(argv[2])
        d = Driver(order)
        try:
            d.run()
        finally:
            r = __import__("subprocess").run(["powershell", "-NoProfile", "-File", os.path.join(HERE, "compare-saves.ps1")],
                                             capture_output=True, text=True)
            say("saves check: " + (r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "?"))
        return 0
    if len(argv) >= 2 and argv[1] == "step":
        d = Driver({"start": "continue"})
        print(d.step())
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
