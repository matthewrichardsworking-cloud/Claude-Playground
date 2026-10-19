"""Choose the heights along a planned route so that no searchlight's swing can reach the
plane (the playtest bot, phase 3; Mission 14, Cape Rainy).

    python tools\\route-heights.py <survey.csv> <route.csv> <fans.json> --out route-h.csv
        [--ceiling 550] [--hardclear 20] [--alt 510] [--clear 40] [--margin 1.0]
        [--step 50] [--grade 0.12] [--pad 30]

What it does: the route (from tools\\route-plan.py) is cut into points every --step metres.
At each point every height from the ground plus --clear up to the ceiling minus
--hardclear (10 m apart) is checked against every beam's fan (tools\\beam-fans.py): a
height is "lit" when some position of some beam's swing comes within its cone's
half-angle plus --margin degrees (plus the plane's own size) of it. Then the profile is
chosen by dynamic programming: the cheapest sequence of heights where the cost is being
lit (very high), being far from the preferred --alt, and being near the canyon walls,
with climbs and descents no steeper than --grade (0.12 = 12 m per 100 m). Way points keep
the route's speeds.

Output: the route at --step spacing with the chosen z, plus a column 'lit' (1 where no
unlit height exists there: the pilot must time that crossing).
"""

import csv
import json
import math
import sys
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 1
    rp = load("route-plan")
    bf = load("beam-fans")
    opts = {"ceiling": 550.0, "hardclear": 20.0, "alt": 510.0, "clear": 40.0, "margin": 1.0, "step": 50.0,
            "grade": 0.12, "out": None, "pad": 30.0, "follow": 0.0}
    i = 4
    while i < len(argv):
        k = argv[i].lstrip("-")
        opts[k] = argv[i + 1] if k == "out" else float(argv[i + 1])
        i += 2
    g = rp.load_grid(argv[1])
    nx, ny, st = g["nx"], g["ny"], g["step"]

    def gz(x, y):
        a = int(round((x - g["x0"]) / st)); b = int(round((y - g["y0"]) / st))
        if 0 <= a < nx and 0 <= b < ny:
            return g["z"][b * nx + a]
        return 1e9

    route = list(csv.DictReader(open(argv[2], newline="")))
    # fixed sweeps, and rings of hovering helicopters (a helicopter that wanders more than
    # 300 m is the pilot's to dodge in flight); a light that does not move at all ("stopped")
    # is a fixed beam, kept as a fan of one direction
    fans = [f for f in json.load(open(argv[3], encoding="utf-8")) if f.get("on")
            and not (f.get("kind") == "ring" and f.get("spread", 0) > 6000)]
    dirs = {f["name"]: bf.fan_dirs(f, 60) for f in fans}
    # densify
    pts = []
    for k in range(len(route) - 1):
        a, b = route[k], route[k + 1]
        ax, ay, bx, by = float(a["x"]), float(a["y"]), float(b["x"]), float(b["y"])
        L = math.hypot(bx - ax, by - ay)
        n = max(1, int(L / (opts["step"] * 10)))
        for j in range(n):
            u = j / n
            pts.append((ax + (bx - ax) * u, ay + (by - ay) * u, float(a["kmh"]) + (float(b["kmh"]) - float(a["kmh"])) * u,
                        math.atan2(by - ay, bx - ax), float(a["z"]) + (float(b["z"]) - float(a["z"])) * u))
    last = route[-1]
    pts.append((float(last["x"]), float(last["y"]), float(last["kmh"]), pts[-1][3] if pts else 0.0, float(last["z"])))
    top = (opts["ceiling"] - opts["hardclear"]) * 10
    levels = [z for z in range(1000, int(top) + 1, 50)]      # every 5 m
    # cost table
    INF = 1e12
    cost = []
    litcount = 0
    for (x, y, kmh, hd, zin) in pts:
        ground = max(gz(x, y), gz(x + 250, y), gz(x - 250, y), gz(x, y + 250), gz(x, y - 250))
        near = [f for f in fans if math.hypot(f["origin"][0] - x, f["origin"][1] - y) < f["reach"] + 2000]
        row = []
        any_unlit = False
        px, py = -math.sin(hd), math.cos(hd)
        for z in levels:
            if z < ground + 100:                          # closer than 10 m to the ground: only if nothing else
                row.append(1e9 + (ground + 100 - z) * 1000); continue
            # 1 per metre from the preferred height: --alt, or with --follow 1 the route's own
            want = zin if opts["follow"] else opts["alt"] * 10
            c = abs(z - want) / 10.0
            if z < ground + opts["clear"] * 10:            # closer than wanted: allowed, but dear
                c += (ground + opts["clear"] * 10 - z) / 10.0 * 500
            # room to the walls at this height (metres to the nearest wall either side)
            room = 0
            for side in (1, -1):
                t = 0
                while t < 400 and gz(x + px * side * t * 10, y + py * side * t * 10) < z - 100:
                    t += 25
                room = min(room, t) if room else t
            if room < 120:
                c += (120 - room) * 2.0
            lit = False
            for f in near:
                o = f["origin"]
                d = math.sqrt((x - o[0]) ** 2 + (y - o[1]) ** 2 + (z - o[2]) ** 2)
                pad = math.degrees(math.atan2(opts["pad"] * 10, max(d, 1)))   # the plane's size and its height error
                e = bf.exposure(f, (x, y, z), opts["margin"] + pad, dirs[f["name"]])
                if e is not None and e < 0:
                    lit = True
                    break
            if lit:
                c += 100000
            else:
                any_unlit = True
            row.append(c)
        if not any_unlit:
            litcount += 1
            print(f"  no unlit, clear height at {len(cost) * opts['step'] / 1000:.2f} km (ground {ground / 10:.0f} m within 25 m)")
        cost.append(row)
    # dynamic programming with a limit on climb/descent between points
    maxdz = opts["grade"] * opts["step"] * 10
    n, m = len(pts), len(levels)
    best = [cost[0][:]]
    back = []
    for k in range(1, n):
        prev = best[-1]
        cur, bk = [], []
        for j in range(m):
            if cost[k][j] >= INF:
                cur.append(INF); bk.append(0); continue
            bv, bj = INF, 0
            for jj in range(max(0, j - 4), min(m, j + 5)):
                if abs(levels[j] - levels[jj]) <= maxdz + 1 and prev[jj] < bv:
                    bv, bj = prev[jj], jj
            cur.append(bv + cost[k][j]); bk.append(bj)
        best.append(cur); back.append(bk)
    j = min(range(m), key=lambda q: best[-1][q])
    zs = [0] * n
    for k in range(n - 1, -1, -1):
        zs[k] = levels[j]
        if k > 0:
            j = back[k - 1][j]
    with open(opts["out"], "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["x", "y", "z", "kmh", "lit"])
        for (x, y, kmh, hd, zin), z, row in zip(pts, zs, cost):
            jz = levels.index(z)
            w.writerow([f"{x:.0f}", f"{y:.0f}", f"{z:.0f}", f"{kmh:.0f}", 1 if row[jz] >= 100000 else 0])
    lit_on_route = sum(1 for z, row in zip(zs, cost) if row[levels.index(z)] >= 100000)
    print(f"{n} points every {opts['step']:.0f} m; heights {min(zs) / 10:.0f}..{max(zs) / 10:.0f} m; "
          f"{litcount} points where every height is lit, {lit_on_route} points of the chosen profile lit")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
