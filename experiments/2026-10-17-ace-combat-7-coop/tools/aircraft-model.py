"""What the plane can do, measured from the pilot's own flight logs (20 Oct 2026; the owner: the bot
needs "innate knowledge of its own aircraft's capabilities and how to use them in maneuvering").

    python tools\\aircraft-model.py <flight.csv or folder> [...]      print the model
    python tools\\aircraft-model.py --json out.json <csv/folder> ...  also write it as JSON

From each flight log (clock, x, y, z, pitch, yaw, roll, kmh, ..., keys; one row a frame) it
measures, for one plane (the logs are per order; mix only logs of the same plane):
  * the turn rate of the flight path (the velocity's direction, from the positions) while
    pulling, by speed band, with and without the high-G turn;
  * the roll rate while rolling (A/D held), and how long a pull takes to build up;
  * the speed change (m/s each second) by climb angle and by what is pressed: throttle, brake,
    high-G, nothing; and the speeds seen (lowest, highest);
  * the same by climb angle (30-degree bands) and speed (200 km/h bands) together: the game's
    speed is not one drag curve. Held level the brake takes off about 60 m/s each second at
    800 km/h, but in a 30-60 degree dive it only holds the speed (20 Oct 2026, 145 logs of
    Missions 06 and 07): a steep dive is flown at the speed it starts with.
These are the numbers a manoeuvre planner needs to fly the plane it has, not a guessed one.
Keys in the logs (main.lua's KEY): 3 pitch up, 1 pitch down, A/D roll, Q/E yaw, W throttle,
S brake, 2 high-G turn. Units: game units are 10 cm; speeds here in m/s and km/h, angles in deg.
"""

import csv
import glob
import json
import math
import os
import sys


def rows_of(path):
    out = []
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        r = csv.reader(f)
        head = next(r, None)
        for row in r:
            if len(row) < 13:
                continue
            try:
                t, x, y, z = float(row[0]), float(row[1]), float(row[2]), float(row[3])
                pitch, yaw, roll, kmh = float(row[4]), float(row[5]), float(row[6]), float(row[7])
            except ValueError:
                continue
            keys = set(k.strip() for k in row[13:] if k.strip())
            rec = row[12].strip() == "1"
            out.append((t, x, y, z, pitch, yaw, roll, kmh, keys, rec))
    return out


def unit(v):
    l = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (v[0] / l, v[1] / l, v[2] / l) if l > 1e-9 else (1.0, 0.0, 0.0), l


def angle(a, b):
    d = max(-1.0, min(1.0, a[0] * b[0] + a[1] * b[1] + a[2] * b[2]))
    return math.degrees(math.acos(d))


def pct(xs, q):
    if not xs:
        return float("nan")
    xs = sorted(xs)
    i = min(len(xs) - 1, max(0, int(round(q * (len(xs) - 1)))))
    return xs[i]


def analyse(paths):
    turn = {}          # (band, highg) -> [deg/s]
    rollr = []         # deg/s while A or D held for a while
    dv = {}            # (gamma band, what) -> [m/s per s]
    dv2 = {}           # (what, 30-degree gamma band, 200 km/h band) -> [m/s per s]
    speeds = []
    pull_build = []    # s from pitch-up press to 80% of the band's median rate
    W = 1              # rows each side for the velocity (the logs have about 10 rows a second)
    for path in paths:
        rs = rows_of(path)
        if len(rs) < 50:
            continue
        # velocity from positions over +-W frames
        vel = [None] * len(rs)
        for i in range(W, len(rs) - W):
            a, b = rs[i - W], rs[i + W]
            dt = b[0] - a[0]
            if dt <= 0.05 or dt > 0.5:
                continue
            v = ((b[1] - a[1]) / dt / 10, (b[2] - a[2]) / dt / 10, (b[3] - a[3]) / dt / 10)   # m/s
            vel[i] = v
        for i in range(W + 2, len(rs) - W - 2):
            r0, r1 = rs[i - 2], rs[i + 2]
            v0, v1 = vel[i - 2], vel[i + 2]
            if not v0 or not v1:
                continue
            dt = r1[0] - r0[0]
            if dt <= 0.15 or dt > 1.0:
                continue
            u0, s0 = unit(v0)
            u1, s1 = unit(v1)
            kmh = rs[i][7]
            keys = rs[i][8]
            speeds.append(kmh)
            # held the same for the whole window
            held = keys & r0[8] & r1[8]
            band = int(kmh // 100) * 100
            if "3" in held and not rs[i][9]:
                rate = angle(u0, u1) / dt
                turn.setdefault((band, "2" in held), []).append(rate)
            if ("A" in held or "D" in held) and not ("3" in held):
                dr = (r1[6] - r0[6] + 540) % 360 - 180
                rollr.append(abs(dr) / dt)
            gamma = math.degrees(math.asin(max(-1.0, min(1.0, (u0[2] + u1[2]) / 2))))
            gb = int(math.floor(gamma / 15.0)) * 15
            what = "high-G" if "2" in held else ("brake" if "S" in held else ("throttle" if "W" in held else ("pull" if "3" in held else "none")))
            dv.setdefault((gb, what), []).append((s1 - s0) / dt)
            dv2.setdefault((what, int(math.floor(gamma / 30.0)) * 30, int(kmh // 200) * 200), []).append((s1 - s0) / dt)
    return turn, rollr, dv, speeds, dv2


def model_of(turn, rollr, dv, speeds, dv2=None):
    m = {"turn_deg_s": {}, "roll_deg_s": None, "dv_m_s2": {}, "kmh": {}, "dv_by_kmh": {}}
    for (band, hg), xs in sorted(turn.items()):
        if len(xs) >= 20:
            m["turn_deg_s"].setdefault(str(band), {})["high_g" if hg else "pull"] = {
                "median": round(pct(xs, 0.5), 1), "p80": round(pct(xs, 0.8), 1), "n": len(xs)}
    if rollr:
        m["roll_deg_s"] = {"median": round(pct(rollr, 0.5)), "p80": round(pct(rollr, 0.8)), "n": len(rollr)}
    for (gb, what), xs in sorted(dv.items()):
        if len(xs) >= 20:
            m["dv_m_s2"].setdefault(what, {})[str(gb)] = {"median": round(pct(xs, 0.5), 1), "n": len(xs)}
    if speeds:
        m["kmh"] = {"p02": round(pct(speeds, 0.02)), "median": round(pct(speeds, 0.5)), "p98": round(pct(speeds, 0.98))}
    # what -> climb band (30 degrees, its start) -> speed band (200 km/h, its start) -> median
    for (what, gb, kb), xs in sorted((dv2 or {}).items()):
        if len(xs) >= 15:
            m["dv_by_kmh"].setdefault(what, {}).setdefault(str(gb), {})[str(kb)] = {"median": round(pct(xs, 0.5), 1), "n": len(xs)}
    return m


def main(argv):
    out_json = None
    args = argv[1:]
    if args[:1] == ["--json"]:
        out_json, args = args[1], args[2:]
    paths = []
    for a in args:
        if os.path.isdir(a):
            paths += sorted(glob.glob(os.path.join(a, "*flight*.csv")))
        else:
            paths += glob.glob(a)
    if not paths:
        print(__doc__)
        return 1
    turn, rollr, dv, speeds, dv2 = analyse(paths)
    m = model_of(turn, rollr, dv, speeds, dv2)
    print(f"{len(paths)} flight logs")
    print("turn rate of the flight path while pulling (deg/s; median / 80th percentile, samples):")
    for band, d in m["turn_deg_s"].items():
        parts = [f"{k} {v['median']}/{v['p80']} ({v['n']})" for k, v in d.items()]
        print(f"  {band:>5} km/h: " + "; ".join(parts))
    print("roll rate (deg/s):", m["roll_deg_s"])
    print("speed change (m/s each second) by climb angle (deg, band start):")
    for what, d in m["dv_m_s2"].items():
        print(f"  {what:9}: " + "  ".join(f"{g}:{v['median']:+.0f}" for g, v in sorted(d.items(), key=lambda kv: int(kv[0]))))
    print("speeds seen (km/h):", m["kmh"])
    print("speed change by climb band and speed (m/s each second; climb band start: km/h band start):")
    for what, d in m["dv_by_kmh"].items():
        for gb, row in sorted(d.items(), key=lambda kv: int(kv[0])):
            print(f"  {what:9} {int(gb):+4d}: " + "  ".join(f"{k}:{v['median']:+.0f}" for k, v in sorted(row.items(), key=lambda kv: int(kv[0]))))
    if out_json:
        with open(out_json, "w", encoding="utf-8") as f:
            json.dump(m, f, indent=1)
        print("written", out_json)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
