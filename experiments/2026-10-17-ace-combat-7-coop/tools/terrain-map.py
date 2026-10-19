"""Draw a picture of a mission's ground from the pilot's terrain survey (CoopPilotMod
"survey" order), so a session can see valleys, ridges, the altitude ceiling and the
mission's searchlights at a glance.

    python tools\\terrain-map.py <survey.csv> <out.png> [--ceiling 600] [--gimmicks g.json]
                                 [--flight flight.csv ...] [--route route.csv] [--scale 3]
                                 [--radar radar.csv]   (red circles: active radar spheres)

Colours: dark blue = sea (nothing solid), greens = ground below the ceiling (the darker,
the more room under it), orange to white = ground above the ceiling (closed to a plane
that must stay under it), yellow dots = searchlights (with a line for the beam), red =
flight paths, cyan = a planned route. North (the game's -Y) is up, as on the in-game map.

Only Python's standard library is used (the PNG is written by hand).
"""

import csv
import json
import math
import struct
import sys
import zlib


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def colour(z, ceiling):
    if z is None:
        return (10, 30, 80)
    m = z / 10.0  # metres
    if ceiling is not None and m >= ceiling:
        k = min(1.0, (m - ceiling) / 1500.0)
        return (int(200 + 55 * k), int(120 + 135 * k), int(40 + 215 * k))
    lim = ceiling if ceiling else 2000.0
    k = max(0.0, min(1.0, m / lim))
    return (int(20 + 80 * k), int(70 + 150 * k), int(30 + 40 * k))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    src, out = argv[1], argv[2]
    ceiling, gim, flights, route, scale, radar = None, None, [], None, 2, None
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--ceiling":
            ceiling = float(argv[i + 1]); i += 2
        elif a == "--gimmicks":
            gim = argv[i + 1]; i += 2
        elif a == "--flight":
            flights.append(argv[i + 1]); i += 2
        elif a == "--route":
            route = argv[i + 1]; i += 2
        elif a == "--scale":
            scale = int(argv[i + 1]); i += 2
        elif a == "--radar":
            radar = argv[i + 1]; i += 2
        else:
            print("unknown option", a); return 1
    pts = {}
    xs, ys = set(), set()
    with open(src, newline="") as f:
        for r in csv.DictReader(f):
            x, y = float(r["x"]), float(r["y"])
            z = float(r["z"]) if r["z"] not in ("", None) else None
            pts[(x, y)] = z
            xs.add(x); ys.add(y)
    xs, ys = sorted(xs), sorted(ys)
    step = xs[1] - xs[0] if len(xs) > 1 else 1000.0
    x0, y0 = xs[0], ys[0]
    nx, ny = len(xs), len(ys)
    # picture: x to the right (east), -y up (north)
    W, H = nx * scale, ny * scale
    img = [[(0, 0, 0)] * W for _ in range(H)]

    def to_px(x, y):
        px = int((x - x0) / step * scale)
        py = int((y - y0) / step * scale)
        return px, py

    for (x, y), z in pts.items():
        px, py = to_px(x, y)
        c = colour(z, ceiling)
        for a in range(scale):
            for b in range(scale):
                if 0 <= py + b < H and 0 <= px + a < W:
                    img[py + b][px + a] = c

    def dot(px, py, c, r=1):
        for a in range(-r, r + 1):
            for b in range(-r, r + 1):
                if 0 <= py + b < H and 0 <= px + a < W:
                    img[py + b][px + a] = c

    def line(xa, ya, xb, yb, c):
        pa, pb = to_px(xa, ya), to_px(xb, yb)
        n = max(abs(pb[0] - pa[0]), abs(pb[1] - pa[1]), 1)
        for k in range(n + 1):
            dot(int(pa[0] + (pb[0] - pa[0]) * k / n), int(pa[1] + (pb[1] - pa[1]) * k / n), c, 0)

    for fl in flights:
        with open(fl, newline="") as f:
            for k, r in enumerate(csv.DictReader(f)):
                if k % 5 == 0:
                    px, py = to_px(float(r["x"]), float(r["y"]))
                    dot(px, py, (230, 40, 40), 0)
    if radar:
        with open(radar, newline="") as f:
            for r in csv.DictReader(f):
                if str(r.get("active", "true")).lower() != "true":
                    continue
                cx, cy, rad = float(r["x"]), float(r["y"]), float(r["radius"])
                n = max(24, int(rad / step * scale * 6))
                for k in range(n):
                    a1, a2 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
                    line(cx + rad * math.cos(a1), cy + rad * math.sin(a1), cx + rad * math.cos(a2), cy + rad * math.sin(a2), (230, 50, 50))
    if route:
        prev = None
        with open(route, newline="") as f:
            for r in csv.DictReader(f):
                p = (float(r["x"]), float(r["y"]))
                if prev:
                    line(prev[0], prev[1], p[0], p[1], (40, 230, 230))
                prev = p
    if gim:
        with open(gim, encoding="utf-8") as f:
            g = json.load(f)
        for L in g.get("lights", []):
            p = L.get("p")
            if not p:
                continue
            reach = L.get("reach") or 20000
            pitch, yaw = L.get("beam_pitch"), L.get("beam_yaw")
            if pitch is not None and yaw is not None:
                d = reach * math.cos(math.radians(pitch))
                line(p[0], p[1], p[0] + d * math.cos(math.radians(yaw)), p[1] + d * math.sin(math.radians(yaw)), (200, 200, 60))
            px, py = to_px(p[0], p[1])
            dot(px, py, (255, 255, 0), 1)
        for e in g.get("others", []):
            p = e.get("p")
            if p:
                px, py = to_px(p[0], p[1])
                dot(px, py, (255, 0, 255), 2)
    write_png(out, W, H, [[v for c in row for v in c] for row in img])
    lo = [z for z in pts.values() if z is not None]
    print(f"{out}: {nx} x {ny} samples every {step / 10:.0f} m, x {x0:.0f}..{xs[-1]:.0f}, y {y0:.0f}..{ys[-1]:.0f}; "
          f"ground {min(lo) / 10:.0f}..{max(lo) / 10:.0f} m, {sum(1 for z in pts.values() if z is None)} points with nothing solid")
    if ceiling:
        under = sum(1 for z in lo if z / 10 < ceiling)
        print(f"  {under} of {len(lo)} ground points are below the {ceiling:.0f} m ceiling")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
