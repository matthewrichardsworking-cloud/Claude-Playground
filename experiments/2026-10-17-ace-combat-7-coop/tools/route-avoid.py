"""Plan a low route that stays out of a mission's radar spheres (Mission 04 Rescue, 19 Oct 2026).

The radar areas (SystemObjectRadarArea) are spheres sitting on the ground: measured on 19 Oct,
the plane at 167 m was "in radar" exactly 5.97 km from the centre of a 6 km one, and three
seconds later the mission said "We've been spotted! Abort mission!". Flying low does not get
under them; the only way is around. This planner:

  1. marks every square of a grid (250 m) closer than radius + margin to an active radar
     centre as closed (horizontally: low flight barely shrinks a sphere);
  2. finds the shortest open path from start to goal (A*, 8 neighbours);
  3. pulls the path straight where a straight line stays open (string pulling);
  4. gives every point a height: the highest ground within 'look' metres ahead and around
     (from the pilot's terrain survey) plus 'clear' metres, smoothed so the climbs stay gentle;
  5. writes a route CSV for the pilot's "fly route" order (x, y, z, kmh).

    python tools\\route-avoid.py --radar m04-radar.csv --survey m04-survey.csv
        --start X Y --goal X Y [--margin 900] [--clear 120] [--kmh 650] --out m04-route.csv
        [--picture route.png]
Units: game units (10 cm) in the files, metres for --margin / --clear.
"""

import argparse
import csv
import heapq
import math


def read_radar(path):
    out = []
    for r in csv.DictReader(open(path, encoding="utf-8")):
        if str(r.get("active", "true")).lower() == "true":
            out.append((float(r["x"]), float(r["y"]), float(r["radius"]), r["name"]))
    return out


def read_survey(path):
    pts = {}
    xs, ys = set(), set()
    for r in csv.DictReader(open(path, encoding="utf-8")):
        x, y = float(r["x"]), float(r["y"])
        z = float(r["z"]) if r["z"] else 0.0
        pts[(x, y)] = z
        xs.add(x)
        ys.add(y)
    xs, ys = sorted(xs), sorted(ys)
    step = xs[1] - xs[0]
    return pts, xs[0], ys[0], step, len(xs), len(ys)


class Ground:
    def __init__(self, path):
        self.pts, self.x0, self.y0, self.step, self.nx, self.ny = read_survey(path)

    def at(self, x, y):
        i = round((x - self.x0) / self.step)
        j = round((y - self.y0) / self.step)
        return self.pts.get((self.x0 + i * self.step, self.y0 + j * self.step), 0.0)

    def highest(self, x, y, r):
        """The highest ground within r (game units) of (x, y)."""
        best = -1e9
        k = int(r // self.step) + 1
        i0 = round((x - self.x0) / self.step)
        j0 = round((y - self.y0) / self.step)
        for di in range(-k, k + 1):
            for dj in range(-k, k + 1):
                if (di * self.step) ** 2 + (dj * self.step) ** 2 > r * r:
                    continue
                z = self.pts.get((self.x0 + (i0 + di) * self.step, self.y0 + (j0 + dj) * self.step))
                if z is not None and z > best:
                    best = z
        return best if best > -1e9 else 0.0


def blocked_fn(radar, margin):
    def blocked(x, y):
        for cx, cy, r, _ in radar:
            if (x - cx) ** 2 + (y - cy) ** 2 < (r + margin) ** 2:
                return True
        return False
    return blocked


def line_open(a, b, blocked, step=1000):
    d = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(1, int(d / step))
    for i in range(n + 1):
        t = i / n
        if blocked(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t):
            return False
    return True


def plan(start, goal, blocked, cell=1500, pad=150000):
    x0 = min(start[0], goal[0]) - pad
    y0 = min(start[1], goal[1]) - pad
    def to_cell(p):
        return (int((p[0] - x0) // cell), int((p[1] - y0) // cell))
    def centre(c):
        return (x0 + (c[0] + 0.5) * cell, y0 + (c[1] + 0.5) * cell)
    s, g = to_cell(start), to_cell(goal)
    nx = int((max(start[0], goal[0]) + pad - x0) // cell) + 1
    ny = int((max(start[1], goal[1]) + pad - y0) // cell) + 1
    openq = [(0, 0, s)]
    came, cost = {s: None}, {s: 0}
    while openq:
        _, gcost, cur = heapq.heappop(openq)
        if cur == g:
            break
        if gcost > cost.get(cur, 1e18):
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nb = (cur[0] + dx, cur[1] + dy)
                if not (0 <= nb[0] < nx and 0 <= nb[1] < ny):
                    continue
                if nb != g and blocked(*centre(nb)):
                    continue
                nc = gcost + math.hypot(dx, dy)
                if nc < cost.get(nb, 1e18):
                    cost[nb] = nc
                    came[nb] = cur
                    h = math.hypot(nb[0] - g[0], nb[1] - g[1])
                    heapq.heappush(openq, (nc + h, nc, nb))
    if g not in came:
        return None
    path = []
    c = g
    while c is not None:
        path.append(centre(c))
        c = came[c]
    path.reverse()
    path[0], path[-1] = start, goal
    # string pulling
    out = [path[0]]
    i = 0
    while i < len(path) - 1:
        j = len(path) - 1
        while j > i + 1 and not line_open(path[i], path[j], blocked):
            j -= 1
        out.append(path[j])
        i = j
    return out


def resample(pts, step=5000):
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        n = max(1, int(d // step))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--radar", required=True)
    ap.add_argument("--survey", required=True)
    ap.add_argument("--start", nargs=2, type=float, required=True)
    ap.add_argument("--goal", nargs=2, type=float, required=True)
    ap.add_argument("--margin", type=float, default=900, help="metres kept outside every radar sphere")
    ap.add_argument("--clear", type=float, default=120, help="metres above the highest ground nearby")
    ap.add_argument("--look", type=float, default=600, help="metres around each point checked for ground")
    ap.add_argument("--kmh", type=float, default=650)
    ap.add_argument("--out", required=True)
    ap.add_argument("--picture")
    ap.add_argument("--stop-within", type=float, default=0, help="end the route this many metres from the goal (a phase's clear zone)")
    a = ap.parse_args()
    radar = read_radar(a.radar)
    ground = Ground(a.survey)
    blocked = blocked_fn(radar, a.margin * 10)
    route = plan(tuple(a.start), tuple(a.goal), blocked)
    if not route:
        raise SystemExit("no radar-free way found")
    pts = resample(route, 3000)
    if a.stop_within > 0:
        for k, (x, y) in enumerate(pts):
            if math.hypot(x - a.goal[0], y - a.goal[1]) < a.stop_within * 10:
                pts = pts[:k + 8]          # a little way inside the zone
                break
    zs = [ground.highest(x, y, a.look * 10) + a.clear * 10 for x, y in pts]
    # smooth: a climb must start early enough (the highest of the next 1.5 km), descents gently
    ahead = 5
    zs2 = [max(zs[i:i + ahead + 1]) for i in range(len(zs))]
    for k in range(1, len(zs2)):                  # descend no faster than 60 m per 300 m
        zs2[k] = max(zs2[k], zs2[k - 1] - 600)
    length = sum(math.hypot(b[0] - a_[0], b[1] - a_[1]) for a_, b in zip(pts, pts[1:])) / 10000
    with open(a.out, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["x", "y", "z", "kmh"])
        for (x, y), z in zip(pts, zs2):
            w.writerow([round(x), round(y), round(z), round(a.kmh)])
    closest = min(math.hypot(x - cx, y - cy) - r for x, y in pts for cx, cy, r, _ in radar) / 10
    print(f"route: {len(route)} legs, {len(pts)} points, {length:.1f} km, heights {min(zs2) / 10:.0f}-{max(zs2) / 10:.0f} m, "
          f"closest to a radar sphere's edge {closest:.0f} m; written to {a.out}")
    if a.picture:
        try:
            from PIL import Image, ImageDraw
        except ImportError:
            print("(no picture: Pillow is not installed)")
            return
        xs = [p[0] for p in pts] + [c[0] for c in radar]
        ys = [p[1] for p in pts] + [c[1] for c in radar]
        lo_x, hi_x = min(p[0] for p in pts) - 80000, max(p[0] for p in pts) + 80000
        lo_y, hi_y = min(p[1] for p in pts) - 80000, max(p[1] for p in pts) + 80000
        W = 1000
        sc = W / max(hi_x - lo_x, hi_y - lo_y)
        img = Image.new("RGB", (W, W), (12, 16, 24))
        d = ImageDraw.Draw(img)
        def px(x, y):
            return ((x - lo_x) * sc, W - (y - lo_y) * sc)
        for cx, cy, r, _ in radar:
            X, Y = px(cx, cy)
            d.ellipse([X - r * sc, Y - r * sc, X + r * sc, Y + r * sc], outline=(220, 60, 60))
        d.line([px(x, y) for x, y in pts], fill=(90, 220, 120), width=3)
        d.ellipse([*[v - 5 for v in px(*pts[0])], *[v + 5 for v in px(*pts[0])]], fill=(255, 255, 255))
        d.ellipse([*[v - 5 for v in px(*pts[-1])], *[v + 5 for v in px(*pts[-1])]], fill=(255, 200, 0))
        img.save(a.picture)
        print("picture:", a.picture)


if __name__ == "__main__":
    main()
