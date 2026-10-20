"""Where a fight's time went, and how fast it killed: general numbers for any playtest run
(the score-race plan of 19 Oct 2026, "faster test loop": judge changes by kills per minute
inside a cluster and by the time breakdown, computed for every run).

    python tools\\run-stats.py playtests\\2026-10-19_0841_m06_ace
        the numbers for each attempt in that run folder, printed
    python tools\\run-stats.py playtests\\<folder> --from 0 --to 480
        only the first 8 minutes of each attempt (seconds from the attempt's first event)

Works from what every run folder has:
  * events.jsonl: the pilot's own time split (a "time_split" event every 60 s and at the end,
    from 19 Oct 2026 on: seconds per class, measured frame by frame), kills, launches, locks,
    breaks, damage;
  * pilot.log: for older runs without time_split events, the combat line the pilot writes once
    a second is classified instead (one line = one second).

The classes (the same in both):
  locked    the chosen target is locked
  ahead     a target within 3 km and within 45 degrees of the nose, not locked yet
  offnose   a target within 3 km but more than 45 degrees off the nose (turning back, orbiting)
  defend    the defensive attack: still attacking, turned across a missile's line (from 19 Oct 2026)
  break     breaking away from a missile
  transit   the target more than 3 km away, or flying toward one not selected yet
  pursuer   turning into an enemy that is after us
  notarget  nothing to attack anywhere
  recovery  climbing away from the ground
  other     anything else (escort, ...)
"""

import json
import os
import re
import sys
from collections import Counter, defaultdict

CLASSES = ["locked", "ahead", "offnose", "defend", "break", "transit", "pursuer", "notarget", "recovery", "other"]

LINE_RE = re.compile(r"^(\d\d):(\d\d):(\d\d)\s+combat: (.*)$")
TGT_RE = re.compile(r"^target \S+ .*?(\d+) m, (\d+) deg off nose")
SCAN_RE = re.compile(r"^no target selected; flying toward \S+ .*?(\d+) m away \((\d+) deg off the nose")


def classify_line(text):
    """One combat line (pilot.log, once a second) -> a class."""
    body = text.split(" | kills")[0]
    if body.startswith("BREAK"):
        return "break"
    if body.startswith("turning into"):
        return "pursuer"
    if body.startswith("no targets anywhere"):
        return "notarget"
    if body.startswith("escorting"):
        return "other"
    m = SCAN_RE.match(body)
    if m:
        d, off = int(m.group(1)), int(m.group(2))
        if d > 3000:
            return "transit"
        return "ahead" if off <= 45 else "offnose"
    m = TGT_RE.match(body)
    if m:
        d, off = int(m.group(1)), int(m.group(2))
        if ", LOCKED" in body.split(";")[0]:
            return "locked"
        if d > 3000:
            return "transit"
        return "ahead" if off <= 45 else "offnose"
    return "other"


def to_s(hh, mm, ss):
    return int(hh) * 3600 + int(mm) * 60 + int(ss)


def read_events(folder):
    by = defaultdict(list)
    path = os.path.join(folder, "events.jsonl")
    if not os.path.exists(path):
        return by
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            by[int(e.get("attempt", 1))].append(e)
    return by


def read_log_lines(folder):
    """pilot.log's combat lines per attempt: [(clock seconds, class)]."""
    by = defaultdict(list)
    path = os.path.join(folder, "pilot.log")
    if not os.path.exists(path):
        return by
    attempt = 1
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("===== attempt "):
                try:
                    attempt = int(line.split()[2])
                except (IndexError, ValueError):
                    pass
                continue
            if "combat:" not in line:
                continue
            m = LINE_RE.match(line.rstrip("\n"))
            if not m:
                continue
            by[attempt].append((to_s(m.group(1), m.group(2), m.group(3)), classify_line(m.group(4))))
    return by


def clock_s(e):
    c = e.get("clock")
    if not c:
        return None
    hh, mm, ss = c.split(":")
    return to_s(hh, mm, ss)


def stats_for(events, log_lines, t_from=None, t_to=None):
    """The numbers for one attempt. Times are seconds from the attempt's first event."""
    if not events:
        return None
    t0 = min(e["t"] for e in events if "t" in e)
    c0 = next((clock_s(e) for e in events if e.get("clock")), None)

    def inside(rel):
        return (t_from is None or rel >= t_from) and (t_to is None or rel <= t_to)

    out = {"source": None, "split": Counter(), "span_s": 0.0}
    # 1. the pilot's own split (time_split events carry running totals since the order began;
    #    differences between consecutive ones give each window)
    splits = [e for e in events if e.get("kind") == "time_split" and isinstance(e.get("split"), dict)]
    if splits and t_from is None and t_to is None:
        # totals of the last split of each fly order (a new order starts from zero)
        last_per_order = {}
        for e in splits:
            last_per_order[e.get("order_t0", 0)] = e
        for e in last_per_order.values():
            for k, v in e["split"].items():
                out["split"][k] += float(v)
        out["source"] = "pilot's frame-by-frame split"
    elif splits:
        prev = {}
        for e in splits:
            rel = e["t"] - t0
            key = e.get("order_t0", 0)
            p = prev.get(key, {})
            if inside(rel):
                for k, v in e["split"].items():
                    out["split"][k] += float(v) - float(p.get(k, 0))
            prev[key] = e["split"]
        out["source"] = "pilot's frame-by-frame split (60 s windows)"
    elif log_lines:
        for cs, cls in log_lines:
            rel = cs - c0 if c0 is not None else 0
            if rel < -43200:
                rel += 86400
            if inside(rel):
                out["split"][cls] += 1.0
        out["source"] = "pilot.log combat lines (1 per second)"
    total = sum(out["split"].values())
    out["span_s"] = total

    # 2. kills, launches, locks, breaks, damage
    ev = [e for e in events if inside(e.get("t", t0) - t0)]
    kills = [e for e in ev if e.get("kind") == "kill"]
    out["kills"] = len(kills)
    out["points"] = sum(float(e.get("bounty") or 0) for e in kills)
    by_kind = Counter(e.get("class") or e.get("kill_kind") or "?" for e in kills)
    out["kills_by_kind"] = dict(by_kind)
    launches = [e for e in ev if e.get("kind") == "launch" and e.get("weapon") == "missile"]
    out["missiles"] = sum(int(e.get("n", 1)) for e in launches)
    out["special"] = sum(int(e.get("n", 1)) for e in ev if e.get("kind") == "launch" and e.get("weapon") == "special")
    if not launches:
        out["missiles"] = sum(1 for e in ev if e.get("kind") == "missile")
    out["breaks"] = sum(1 for e in ev if e.get("kind") == "evade")
    out["jinks"] = sum(1 for e in ev if e.get("kind") == "jink")
    # the pilot's own missiles: hits by weapon and launch distance (2 km bands)
    mine = {}
    for e in ev:
        if e.get("kind") == "my_missile":
            key = (e.get("weapon") or "?", e.get("target_kind") or "?", int(float(e.get("dist_m") or 0) // 2000) * 2)
            v = mine.setdefault(key, [0, 0])
            v[0] += 1
            v[1] += 1 if e.get("hit") else 0
    out["my_missiles"] = mine
    out["defends"] = sum(1 for e in ev if e.get("kind") == "defend")
    out["damage"] = sum(float(e.get("amount") or 0) for e in ev if e.get("kind") == "damage")
    locks = [float(e["after_s"]) for e in ev if e.get("kind") == "lock" and e.get("after_s") is not None]
    out["locks"] = len(locks)
    out["lock_s_median"] = sorted(locks)[len(locks) // 2] if locks else None
    out["chained"] = sum(1 for e in ev if e.get("kind") == "chain")
    skips = Counter(e.get("why") or "?" for e in ev if e.get("kind") == "skip")
    out["skips"] = dict(skips)
    acts = [e for e in ev if e.get("kind") == "activated" and not e.get("start")]
    out["activations"] = [(round(e["t"] - t0), e.get("class"), e.get("n"), e.get("points"), e.get("x"), e.get("y"),
                           e.get("plane_x"), e.get("plane_y")) for e in acts]
    out["active_at_start"] = sum(int(e.get("n") or 0) for e in ev if e.get("kind") == "activated" and e.get("start"))
    fin = [e for e in ev if e.get("kind") == "time_split" and e.get("final")]
    if fin and fin[-1].get("audit_plans"):
        f = fin[-1]
        out["audit"] = (int(f["audit_plans"]), float(f.get("audit_expected") or 0), float(f.get("audit_launched") or 0))
        out["learned"] = {k: f.get(k) for k in ("lock_base_s", "lock_rate_dps", "load_s", "turn_dps") if f.get(k) is not None}
    scores = [e for e in ev if e.get("kind") == "score_tick"]
    out["score_ticks"] = [(round(e["t"] - t0), e.get("hud_score"), e.get("goal")) for e in scores]
    # time spanned by the attempt's events (for rates when there is no split)
    ts = [e["t"] for e in ev if "t" in e]
    span = (max(ts) - min(ts)) if ts else 0.0
    minutes = (total if total > 0 else span) / 60.0
    out["minutes"] = minutes
    out["kills_per_min"] = out["kills"] / minutes if minutes > 0 else 0.0
    out["missiles_per_min"] = out["missiles"] / minutes if minutes > 0 else 0.0
    # in a cluster: everything but transit, no target and recovery
    busy = sum(out["split"][k] for k in ("locked", "ahead", "offnose", "break", "pursuer"))
    out["busy_min"] = busy / 60.0
    out["kills_per_busy_min"] = out["kills"] / (busy / 60.0) if busy > 0 else None
    out["missiles_per_kill"] = out["missiles"] / out["kills"] if out["kills"] else None
    return out


def describe(st):
    """Plain-language lines for a report."""
    if not st:
        return ["(no events)"]
    lines = []
    total = sum(st["split"].values())
    if total > 0:
        parts = []
        for k in CLASSES:
            v = st["split"].get(k, 0)
            if v > 0:
                parts.append(f"{k} {100 * v / total:.0f}%")
        lines.append(f"Time split over {total / 60:.1f} min ({st['source']}): " + ", ".join(parts) + ".")
    lines.append(f"Kills {st['kills']} ({st['kills_per_min']:.1f} a minute"
                 + (f"; {st['kills_per_busy_min']:.1f} a minute while engaged" if st.get("kills_per_busy_min") else "")
                 + f"), missiles {st['missiles']} ({st['missiles_per_min']:.1f} a minute"
                 + (f", {st['missiles_per_kill']:.1f} per kill" if st.get("missiles_per_kill") else "") + ")"
                 + (f", special weapon {st['special']}" if st.get("special") else "") + ".")
    if st.get("kills_by_kind") and any(k != "?" for k in st["kills_by_kind"]):
        lines.append("Kills by kind (game data): " + ", ".join(f"{k} {v}" for k, v in sorted(st["kills_by_kind"].items())) + ".")
    if st.get("points"):
        lines.append(f"Points from kills (the game's bounty per kill): {st['points']:.0f}.")
    extra = []
    if st.get("locks"):
        extra.append(f"{st['locks']} locks (median {st['lock_s_median']:.1f} s from selection)")
    if st.get("chained"):
        extra.append(f"{st['chained']} chained selections (next target picked in the cone right after a launch)")
    extra.append(f"{st['breaks']} break turns" + (f", {st['jinks']} jinks" if st.get("jinks") else "")
                 + (f", {st['defends']} defensive attacks" if st.get("defends") else ""))
    extra.append(f"{st['damage']:.0f} damage taken")
    lines.append("; ".join(extra) + ".")
    if st.get("skips"):
        lines.append("Targets set aside: " + ", ".join(f"{k} {v}" for k, v in sorted(st["skips"].items())) + ".")
    if st.get("steering"):
        g = st["steering"]
        lines.append(f"Steering (flight log): {100 * g['turn_share']:.0f}% of the time in hard turns, pulling in "
                     f"{100 * g['pull_in_turn']:.0f}% of that; {100 * g['past95']:.0f}% of the time banked past 95 degrees; "
                     f"median speed {g['kmh_median']:.0f} km/h.")
    if st.get("my_missiles"):
        parts = [f"{w} at {k} from {b}-{b + 2} km: {h} of {n}" for (w, k, b), (n, h) in sorted(st["my_missiles"].items())]
        lines.append("Own missiles that hit (target lost health or died): " + "; ".join(parts) + ".")
    if st.get("audit"):
        n, ex, got = st["audit"]
        lines.append(f"Lane plans audited: {n} plans expected {ex / max(n, 1):.1f} shots each in their look-ahead, "
                     f"{got / max(n, 1):.1f} were launched (the planner's model is {ex / max(got, 1):.1f} times optimistic).")
    if st.get("learned"):
        L = st["learned"]
        lines.append("Learned in the fight: " + ", ".join(f"{k} {v:.2f}" if isinstance(v, (int, float)) else f"{k} {v}" for k, v in L.items()) + ".")
    if st.get("activations"):
        parts = []
        for t, cls, n, pts, x, y, px, py in st["activations"][:20]:
            parts.append(f"{t // 60}:{t % 60:02d} {n} x {cls} ({pts} points) at ({(x or 0) / 10000:.0f}, {(y or 0) / 10000:.0f}) km, "
                         f"the plane at ({(px or 0) / 10000:.0f}, {(py or 0) / 10000:.0f}) km")
        lines.append(f"Switched on by the mission during the fight ({st.get('active_at_start', 0)} enemies active at the start): "
                     + "; ".join(parts) + ".")
    if st.get("score_ticks"):
        ticks = [f"{t // 60}:{t % 60:02d} {s}" for t, s, g in st["score_ticks"][::2] if s]
        if ticks:
            lines.append("Score on the HUD: " + ", ".join(ticks) + ".")
    return lines


def steering_stats(folder, n):
    """From the attempt's flight logs (ten rows a second): how the plane was flown. Time in the
    big-turn mode, how much of it with the pull key down, time banked past 95 degrees, and the
    speed; a turn that is not pulling is time lost whatever the plan was."""
    import csv
    import glob
    rows = 0
    turn = pull_in_turn = past95 = 0
    kmh = []
    for path in sorted(glob.glob(os.path.join(folder, f"attempt{n}-flight-*.csv"))):
        try:
            with open(path, newline="", encoding="utf-8", errors="replace") as f:
                r = csv.reader(f)
                next(r, None)
                for row in r:
                    if len(row) < 13:
                        continue
                    try:
                        roll, speed = float(row[6]), float(row[7])
                    except ValueError:
                        continue
                    keys = set(row[13:])
                    rows += 1
                    kmh.append(speed)
                    if abs(roll) > 95:
                        past95 += 1
                    if row[10] == "turn":
                        turn += 1
                        if "3" in keys:
                            pull_in_turn += 1
        except OSError:
            pass
    if rows < 50:
        return None
    kmh.sort()
    return {"turn_share": turn / rows, "pull_in_turn": pull_in_turn / max(turn, 1), "past95": past95 / rows,
            "kmh_median": kmh[len(kmh) // 2]}


def folder_stats(folder, t_from=None, t_to=None):
    evs = read_events(folder)
    logs = read_log_lines(folder)
    res = {}
    for n in sorted(set(evs) | set(logs)):
        res[n] = stats_for(evs.get(n, []), logs.get(n, []), t_from, t_to)
        if res[n] is not None and t_from is None and t_to is None:
            res[n]["steering"] = steering_stats(folder, n)
    return res


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    folder = argv[1]
    t_from = float(argv[argv.index("--from") + 1]) if "--from" in argv else None
    t_to = float(argv[argv.index("--to") + 1]) if "--to" in argv else None
    for n, st in folder_stats(folder, t_from, t_to).items():
        print(f"== attempt {n}")
        for line in describe(st):
            print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
