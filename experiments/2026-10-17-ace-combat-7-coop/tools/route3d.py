"""Plan a low-level route in three dimensions: where to fly AND at what height, together
(the playtest bot, phase 3; written for Mission 14, Cape Rainy).

    python tools\\route3d.py <survey.csv> --start X,Y --goal X,Y --fans fans.json --out route.csv
        [--ceiling 550] [--hardclear 20] [--clear 40] [--levels 290,320,...] [--litcost 6]

Why: tools\\route-plan.py finds the middle of the corridor at one height and
tools\\route-heights.py then picks heights along that line. In a canyon the two fight:
the middle of the corridor high up is not the middle lower down (a canyon narrows toward
its floor), and the height that passes under a searchlight's sweep may be where the line
runs close to a wall (18 Oct 2026: a wall hit at 31 km, a searchlight lamp passed at 74 m).
Here the search runs over squares AND heights at once: at each of several heights the
open squares, the room to the walls there, and whether some searchlight's sweep can reach
that square at that height (tools\\beam-fans.py's fans, with a margin and the plane's size)
and how near a lamp it is. Moving sideways costs distance, more near walls and in lit
places; changing height costs as much as the distance a gentle climb needs. The result's
heights are then smoothed by tools\\route-heights.py (run it on this output).

Output CSV: x, y, z (game units), kmh, width_m (room to the walls at that height, both
sides), lit (1 where the chosen square-and-height is inside a sweep: the pilot times it).
"""

import csv
import heapq
import importlib.util
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    rp = load("route-plan")
    opts = {"ceiling": 550.0, "hardclear": 20.0, "clear": 40.0, "start": None, "goal": None, "out": None, "fans": None,
            "levels": "290,320,350,380,410,440,470,500,530", "litcost": 6.0, "wall": 6.0, "climbcost": 6.0, "spacing": 50.0}
    i = 2
    while i < len(argv):
        k = argv[i].lstrip("-"); v = argv[i + 1]
        if k in ("start", "goal"):
            opts[k] = tuple(float(t) for t in v.split(","))
        elif k in ("out", "fans", "levels"):
            opts[k] = v
        else:
            opts[k] = float(v)
        i += 2
    g = rp.load_grid(argv[1])
    nx, ny, st = g["nx"], g["ny"], g["step"]
    levels = [float(x) * 10 for x in opts["levels"].split(",")]
    levels = [z for z in levels if z <= (opts["ceiling"] - opts["hardclear"]) * 10]
    L = len(levels)
    fans = []
    if opts["fans"]:
        fans = [f for f in json.load(open(opts["fans"], encoding="utf-8")) if f.get("on") and f.get("pitch_range")
                and not (f.get("kind") == "ring" and f.get("spread", 0) > 6000)]
    # per height: open squares, room to the walls, lit or not, lamp nearness
    free, room, cost = [], [], []
    for li, z in enumerate(levels):
        fr = [gz + opts["clear"] * 10 < z for gz in g["z"]]
        d = rp.distance_map(fr, nx, ny)
        c = [0.0] * (nx * ny)
        nlit = 0
        for k in range(nx * ny):
            if not fr[k]:
                continue
            x = g["x0"] + (k % nx) * st
            y = g["y0"] + (k // nx) * st
            mult = 1.0 + opts["wall"] / max(d[k] * d[k], 1.0)
            for f in fans:
                o = f["origin"]
                if abs(o[0] - x) > f["reach"] + 4000 or abs(o[1] - y) > f["reach"] + 4000:
                    continue
                if rp.lit_box(f, x, y, z, 2.0, 25.0):
                    mult += opts["litcost"]; nlit += 1
                    break
            for f in fans:
                o = f["origin"]
                dd = math.hypot(o[0] - x, o[1] - y)
                if dd < 3500:
                    mult += 6.0 * (1.0 - dd / 3500.0)
            c[k] = mult
        free.append(fr); room.append(d); cost.append(c)
        print(f"height {z / 10:.0f} m: {sum(fr)} open squares, {nlit} of them lit by some sweep")
    # start and goal: the open square near each with the most room, at the highest level
    top = L - 1
    s = rp.snap(g, room[top], *opts["start"])
    e = rp.snap(g, room[top], *opts["goal"])
    if not s or not e:
        print("no open square near the start or the goal")
        return 2
    sk = (s[1] * nx + s[0], top)
    gi, gj = e
    nb = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0), (-1, -1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (1, 1, 1.414)]
    climb_cells = opts["climbcost"]        # a height step costs as much as this many squares
    openh = [(0.0, 0.0, sk)]
    came = {sk: None}
    best = {sk: 0.0}
    found = None
    while openh:
        _, c0, node = heapq.heappop(openh)
        if c0 > best.get(node, 1e18) + 1e-9:
            continue
        k, li = node
        i0, j0 = k % nx, k // nx
        if math.hypot(i0 - gi, j0 - gj) < 1.5:
            found = node
            break
        moves = []
        for di, dj, sd in nb:
            a, b = i0 + di, j0 + dj
            if 0 <= a < nx and 0 <= b < ny:
                nk = b * nx + a
                if free[li][nk] and room[li][nk] >= 1.4:
                    moves.append(((nk, li), sd * cost[li][nk]))
        for dl in (-1, 1):
            nl = li + dl
            if 0 <= nl < L and free[nl][k] and room[nl][k] >= 1.4:
                moves.append(((k, nl), climb_cells * cost[nl][k]))
        for nn, step in moves:
            nc = c0 + step
            if nc < best.get(nn, 1e18):
                best[nn] = nc
                came[nn] = node
                a, b = nn[0] % nx, nn[0] // nx
                heapq.heappush(openh, (nc + math.hypot(a - gi, b - gj), nc, nn))
    if not found:
        print("no way through")
        return 3
    path = []
    node = found
    while node is not None:
        path.append(node)
        node = came[node]
    path.reverse()
    # to way points every --spacing m, smoothed sideways a little; heights as found
    pts = []
    for k, li in path:
        pts.append((g["x0"] + (k % nx) * st, g["y0"] + (k // nx) * st, levels[li], room[li][k], cost[li][k]))
    win = 2
    sm = []
    for q in range(len(pts)):
        a, b = max(0, q - win), min(len(pts), q + win + 1)
        sm.append((sum(p[0] for p in pts[a:b]) / (b - a), sum(p[1] for p in pts[a:b]) / (b - a)) + pts[q][2:])
    out = [sm[0]]
    acc = 0.0
    for q in range(1, len(sm)):
        acc += math.hypot(sm[q][0] - sm[q - 1][0], sm[q][1] - sm[q - 1][1])
        if acc >= opts["spacing"] * 10:
            out.append(sm[q]); acc = 0.0
    out.append(sm[-1])
    with open(opts["out"], "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["x", "y", "z", "kmh", "width_m", "lit"])
        for x, y, z, rm, c in out:
            width = rm * st / 10 * 2
            kmh = max(470.0, min(650.0, 380.0 + max(0.0, width - 150.0) * 0.5))
            w.writerow([f"{x:.0f}", f"{y:.0f}", f"{z:.0f}", f"{kmh:.0f}", f"{width:.0f}", 1 if c > 1.0 + opts["litcost"] * 0.99 else 0])
    length = sum(math.hypot(out[q][0] - out[q - 1][0], out[q][1] - out[q - 1][1]) for q in range(1, len(out))) / 10
    changes = sum(1 for q in range(1, len(path)) if path[q][1] != path[q - 1][1])
    lit = sum(1 for p in pts if p[4] > 1.0 + opts["litcost"] * 0.99)
    print(f"route: {len(out)} points, {length / 1000:.1f} km, heights {min(p[2] for p in out) / 10:.0f}-{max(p[2] for p in out) / 10:.0f} m, "
          f"{changes} height steps, {lit} of {len(pts)} squares lit, narrowest {min(p[3] for p in out) * st / 10 * 2:.0f} m")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
