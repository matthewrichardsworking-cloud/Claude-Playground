"""Plan a low-level route through a mission's terrain (the playtest bot, phase 3).

Reads the pilot's terrain survey (CoopPilotMod "survey" order: x, y, z of the highest
solid thing on a grid, game units) and finds a way from a start to a goal that stays under
an altitude ceiling, keeping to the middle of the open corridor (a valley under the
ceiling), with a safe speed for every bend. The pilot then flies it ("route load").

    python tools\\route-plan.py <survey.csv> --start X,Y --goal X,Y --out route.csv
        [--ceiling 600] [--alt 530] [--clear 60] [--spacing 300] [--png picture.png]
        [--gimmicks g.json]

  --ceiling  metres above the sea not to go above (the mission's restriction)
  --alt      the height to fly at where the ground allows (metres above the sea)
  --clear    metres to keep above the ground and away from the walls' tops
  --spacing  metres between the route's way points
  --fans     fans.json from tools\beam-fans.py: squares where every flyable height is
             inside some searchlight's sweep cost --litcost times more (so the route
             crosses a beam's sweep far from its lamp, where a short dark gap is enough,
             or passes behind the lamp, or out of its reach)
  --litcost  how much more such a square costs (default 15)
  --hardclear metres of clearance accepted where nothing better exists (default 20):
             ground between --alt minus --clear and the ceiling minus --hardclear is
             passable but costly, so the route only crosses it where it must (a plateau
             at the start, a saddle)

Output CSV columns: x, y, z (game units), kmh (the speed for that stretch), width_m (the
corridor's width there), ground_m (the highest ground near it), turn_m (the bend's radius).

How it works, in short: a square is open when its ground is low enough to fly over it at
--alt with --clear to spare. For every open square the distance to the nearest closed one
is worked out (a "distance map"); the cheapest path from start to goal is searched (A*)
with a price that grows near the walls, so it keeps to the middle. The path is then
smoothed, cut into way points, and each way point gets its height (as high as allowed
under the ceiling, never lower than the ground plus --clear) and a speed the plane can
turn at (a tighter bend, a lower speed).
"""

import csv
import heapq
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_grid(path):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows.append((float(r["x"]), float(r["y"]), float(r["z"]) if r["z"] else 0.0))
    xs = sorted(set(r[0] for r in rows))
    ys = sorted(set(r[1] for r in rows))
    step = xs[1] - xs[0]
    x0, y0 = xs[0], ys[0]
    nx, ny = len(xs), len(ys)
    z = [0.0] * (nx * ny)
    for x, y, h in rows:
        i = int(round((x - x0) / step))
        j = int(round((y - y0) / step))
        z[j * nx + i] = h
    return {"x0": x0, "y0": y0, "step": step, "nx": nx, "ny": ny, "z": z}


def distance_map(free, nx, ny):
    """Distance (in squares) from every square to the nearest closed one (chamfer 1/1.414)."""
    INF = 1e9
    d = [0.0 if not f else INF for f in free]
    D2 = 1.41421356
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            if d[k] == 0.0:
                continue
            best = d[k]
            if i > 0: best = min(best, d[k - 1] + 1)
            if j > 0:
                best = min(best, d[k - nx] + 1)
                if i > 0: best = min(best, d[k - nx - 1] + D2)
                if i < nx - 1: best = min(best, d[k - nx + 1] + D2)
            d[k] = best
    for j in range(ny - 1, -1, -1):
        for i in range(nx - 1, -1, -1):
            k = j * nx + i
            if d[k] == 0.0:
                continue
            best = d[k]
            if i < nx - 1: best = min(best, d[k + 1] + 1)
            if j < ny - 1:
                best = min(best, d[k + nx] + 1)
                if i < nx - 1: best = min(best, d[k + nx + 1] + D2)
                if i > 0: best = min(best, d[k + nx - 1] + D2)
            d[k] = best
    # the edge of the survey counts as closed too (nothing is known beyond it)
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            e = min(i, j, nx - 1 - i, ny - 1 - j)
            if e < d[k]:
                d[k] = float(e)
    return d


def snap(g, d, x, y, radius_sq=40):
    """The open square near (x, y) with the most room around it."""
    i0 = int(round((x - g["x0"]) / g["step"]))
    j0 = int(round((y - g["y0"]) / g["step"]))
    best, bestv = None, -1
    for j in range(max(0, j0 - radius_sq), min(g["ny"], j0 + radius_sq + 1)):
        for i in range(max(0, i0 - radius_sq), min(g["nx"], i0 + radius_sq + 1)):
            k = j * g["nx"] + i
            if d[k] <= 0:
                continue
            v = d[k] - 0.15 * math.hypot(i - i0, j - j0)
            if v > bestv:
                best, bestv = (i, j), v
    return best


def astar(g, d, start, goal, wall_weight, min_room, soft=None, soft_cost=8.0, lit=None, lit_cost=15.0):
    nx, ny = g["nx"], g["ny"]
    sk = start[1] * nx + start[0]
    gk = goal[1] * nx + goal[0]
    openh = [(0.0, 0.0, sk)]
    came = {sk: None}
    cost = {sk: 0.0}
    nbrs = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0), (-1, -1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (1, 1, 1.414)]
    gi, gj = goal
    while openh:
        _, c, k = heapq.heappop(openh)
        if k == gk:
            break
        if c > cost.get(k, 1e18) + 1e-9:
            continue
        i, j = k % nx, k // nx
        for di, dj, s in nbrs:
            a, b = i + di, j + dj
            if a < 0 or b < 0 or a >= nx or b >= ny:
                continue
            nk = b * nx + a
            room = d[nk]
            if room < min_room:
                continue
            step = s * (1.0 + wall_weight / (room * room))
            if soft is not None and soft[nk]:
                step *= soft_cost
            if lit is not None and lit[nk]:
                step *= lit[nk]                 # 1 + how lit the square is, + how near a lamp
            nc = c + step
            if nc < cost.get(nk, 1e18):
                cost[nk] = nc
                came[nk] = k
                h = math.hypot(a - gi, b - gj)
                heapq.heappush(openh, (nc + h, nc, nk))
    if gk not in came:
        return None
    path = []
    k = gk
    while k is not None:
        path.append((k % nx, k // nx))
        k = came[k]
    path.reverse()
    return path


def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


def lit_box(fan, x, y, z, margin_deg, pad_m):
    """Can this sweep light (x, y, z)? A sweep is a box in the angles the lamp sees a point
    at (yaw, pitch), widened by the cone's half-angle, a margin and the plane's size seen
    from that far away. A ring (a helicopter's light turning all the way round) is a band
    of pitch, widened by how far the helicopter wanders."""
    o = fan["origin"]
    dx, dy, dz = x - o[0], y - o[1], z - o[2]
    horiz = math.hypot(dx, dy)
    dl = math.hypot(horiz, dz)
    if dl < 1 or dl > fan["reach"] + fan.get("spread", 0):
        return False
    h = fan["half"] + margin_deg + math.degrees(math.atan2(pad_m * 10, dl))
    elev = math.degrees(math.atan2(dz, horiz))
    lo, hi = fan["pitch_range"]
    if fan.get("kind") == "ring":
        w = math.degrees(math.atan2(fan.get("spread", 0), dl))
        return lo - h - w <= elev <= hi + h + w
    if not (lo - h <= elev <= hi + h):
        return False
    ylo = fan["yaw_ref"] + fan["yaw_rel"][0]
    span = fan["yaw_rel"][1] - fan["yaw_rel"][0]
    rel = wrap(math.degrees(math.atan2(dy, dx)) - ylo)
    if rel < -90:
        rel += 360
    return -h <= rel <= span + h


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    opts = {"ceiling": 600.0, "alt": 530.0, "clear": 60.0, "spacing": 300.0, "start": None, "goal": None,
            "out": None, "png": None, "gimmicks": None, "wall": 6.0, "hardclear": 20.0, "fans": None, "litcost": 15.0}
    i = 2
    while i < len(argv):
        k = argv[i].lstrip("-")
        v = argv[i + 1]
        if k in ("start", "goal"):
            opts[k] = tuple(float(t) for t in v.split(","))
        elif k in ("out", "png", "gimmicks", "fans"):
            opts[k] = v
        else:
            opts[k] = float(v)
        i += 2
    g = load_grid(argv[1])
    nx, ny, step = g["nx"], g["ny"], g["step"]
    top = (opts["alt"] - opts["clear"]) * 10          # ground should be below this (game units)
    hard = (opts["ceiling"] - opts["hardclear"]) * 10  # and must be below this
    free = [z < hard for z in g["z"]]
    soft = [top <= z < hard for z in g["z"]]
    d = distance_map(free, nx, ny)
    # the room counted for the planner is the room at the comfortable height: soft squares
    # count as walls for it, so the route keeps to the middle of the comfortable corridor
    d_comfort = distance_map([z < top for z in g["z"]], nx, ny)
    d = [max(dc, min(dh, 1.0)) for dc, dh in zip(d_comfort, d)]
    # squares where no flyable height is dark (every one inside some sweep): costly
    soft_lit = None
    if opts["fans"]:
        import json
        fans = [f for f in json.load(open(opts["fans"], encoding="utf-8")) if f.get("on") and f.get("pitch_range")
                and not (f.get("kind") == "ring" and f.get("spread", 0) > 6000)]
        soft_lit = [False] * (nx * ny)
        levels = list(range(1000, int(hard) + 1, 200))
        n_lit = 0
        for k in range(nx * ny):
            if not free[k]:
                continue
            x = g["x0"] + (k % nx) * step
            y = g["y0"] + (k // nx) * step
            near = [f for f in fans if abs(f["origin"][0] - x) < f["reach"] + 4000 and abs(f["origin"][1] - y) < f["reach"] + 4000]
            if not near:
                continue
            low = g["z"][k] + opts["clear"] * 10 * 0.5
            tried = lit = 0
            for z in levels:
                if z < low:
                    continue
                tried += 1
                if any(lit_box(f, x, y, z, 2.0, 25.0) for f in near):
                    lit += 1
            frac = lit / tried if tried else 0.0
            # close to a lamp its sweep crosses a plane faster than any change of speed can
            # dodge (Mission 14, searchlight 32 passed at 74 m): keep 350 m away where possible
            lamp = min((math.hypot(f["origin"][0] - x, f["origin"][1] - y) for f in near), default=1e9)
            prox = max(0.0, 1.0 - lamp / 3500.0)
            mult = 1.0 + opts["litcost"] * frac * frac + 8.0 * prox
            if mult > 1.01:
                soft_lit[k] = mult
            if frac >= 1.0:
                n_lit += 1
        print(f"{n_lit} open squares where every flyable height is inside some searchlight's sweep")
    s = snap(g, d, *opts["start"])
    e = snap(g, d, *opts["goal"])
    if not s or not e:
        print("no open square near the start or the goal")
        return 2
    path = None
    for min_room in (3.0, 2.0, 1.4, 1.0):
        path = astar(g, d, s, e, opts["wall"], min_room, soft, 8.0, soft_lit, opts["litcost"])
        if path:
            break
    if not path:
        print("no way through under the ceiling with that clearance")
        return 3
    # smooth: moving average over about 150 m, then cut into way points
    def wx(p): return g["x0"] + p[0] * step
    def wy(p): return g["y0"] + p[1] * step
    pts = [(wx(p), wy(p)) for p in path]
    win = max(1, int(1500 / step))
    sm = []
    for k in range(len(pts)):
        a, b = max(0, k - win), min(len(pts), k + win + 1)
        sm.append((sum(p[0] for p in pts[a:b]) / (b - a), sum(p[1] for p in pts[a:b]) / (b - a)))
    sm[0], sm[-1] = pts[0], pts[-1]
    way = [sm[0]]
    acc = 0.0
    for k in range(1, len(sm)):
        acc += math.hypot(sm[k][0] - sm[k - 1][0], sm[k][1] - sm[k - 1][1])
        if acc >= opts["spacing"] * 10:
            way.append(sm[k]); acc = 0.0
    if way[-1] != sm[-1]:
        way.append(sm[-1])

    def ground_near(x, y, r_units):
        i0 = int(round((x - g["x0"]) / step)); j0 = int(round((y - g["y0"]) / step))
        rr = int(math.ceil(r_units / step))
        best = 0.0
        for j in range(max(0, j0 - rr), min(ny, j0 + rr + 1)):
            for i2 in range(max(0, i0 - rr), min(nx, i0 + rr + 1)):
                best = max(best, g["z"][j * nx + i2])
        return best

    def room_at(x, y):
        i0 = int(round((x - g["x0"]) / step)); j0 = int(round((y - g["y0"]) / step))
        i0 = min(max(i0, 0), nx - 1); j0 = min(max(j0, 0), ny - 1)
        return d[j0 * nx + i0] * step / 10 * 2      # metres, wall to wall roughly

    rows = []
    for k, (x, y) in enumerate(way):
        gz = ground_near(x, y, 0)                     # the ground right under the way point
        z = min(opts["alt"] * 10, opts["ceiling"] * 10 - 400)
        z = max(z, gz + opts["clear"] * 10)
        z = min(z, (opts["ceiling"] - opts["hardclear"]) * 10)   # never planned closer than that to the ceiling
        # bend radius from the turn at this way point
        turn = 99999.0
        if 0 < k < len(way) - 1:
            ax, ay = x - way[k - 1][0], y - way[k - 1][1]
            bx, by = way[k + 1][0] - x, way[k + 1][1] - y
            la, lb = math.hypot(ax, ay), math.hypot(bx, by)
            if la > 0 and lb > 0:
                ang = math.acos(max(-1.0, min(1.0, (ax * bx + ay * by) / (la * lb))))
                if ang > 1e-3:
                    turn = ((la + lb) / 2) / ang / 10   # metres
        rows.append([x, y, z, turn, room_at(x, y), gz / 10])
    # speed: the plane turns at about 25 deg/s in a hard bank, so speed = radius * rate;
    # a bend limits the speed for a stretch before it too (look 3 way points back)
    rate = math.radians(25)
    for r in rows:
        bend = r[3] * rate * 3.6
        narrow = 380.0 + max(0.0, r[4] - 150.0) * 0.5     # 200 m wide: 405 km/h, 500 m: 555 km/h
        r.append(max(380.0, min(opts.get("maxkmh", 650.0), bend, narrow)))
    for k in range(len(rows) - 1, -1, -1):
        for b in range(1, 4):
            if k - b >= 0:
                rows[k - b][6] = min(rows[k - b][6], rows[k][6] + 60 * b)
    with open(opts["out"], "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["x", "y", "z", "kmh", "width_m", "ground_m", "turn_m"])
        for x, y, z, turn, width, gm, kmh in rows:
            w.writerow([f"{x:.0f}", f"{y:.0f}", f"{z:.0f}", f"{kmh:.0f}", f"{width:.0f}", f"{gm:.0f}", f"{min(turn, 99999):.0f}"])
    length = sum(math.hypot(way[k][0] - way[k - 1][0], way[k][1] - way[k - 1][1]) for k in range(1, len(way))) / 10
    narrow = min(r[4] for r in rows)
    tight = min(r[3] for r in rows)
    over = sum(1 for r in rows if r[2] > (opts["ceiling"] - 20) * 10)
    print(f"route: {len(rows)} way points, {length / 1000:.1f} km, narrowest {narrow:.0f} m, tightest bend {tight:.0f} m, "
          f"speeds {min(r[6] for r in rows):.0f}-{max(r[6] for r in rows):.0f} km/h, {over} way points within 20 m of the ceiling")
    if opts["png"]:
        import subprocess
        cmd = [sys.executable, os.path.join(HERE, "terrain-map.py"), argv[1], opts["png"], "--ceiling", str(opts["ceiling"]),
               "--route", opts["out"], "--scale", "1"]
        if opts["gimmicks"]:
            cmd += ["--gimmicks", opts["gimmicks"]]
        subprocess.run(cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
