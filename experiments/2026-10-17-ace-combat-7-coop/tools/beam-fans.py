"""Work out each searchlight's sweep from a beam recording (CoopPilotMod "lights" order)
and check a planned route against them (the playtest bot, phase 3).

    python tools\\beam-fans.py <lights.csv> <gimmicks.json> --out fans.json [--route route.csv]

A searchlight's beam is a thin cone (Mission 14: 1.5 degrees either side of its axis)
that swings between two ends, in yaw (side to side) or in pitch (up and down). All the
directions it takes over one swing make a "fan". A point outside every fan is never lit;
a point inside a fan is lit whenever the beam passes it, which the pilot has to time.

fans.json: one entry per light: where the beam starts, the axis it swings about, its two
ends (pitch and yaw at each), the swing speed (deg/s), the cone's half-angle, its reach.

With --route: for each way point, which fans it is inside (with a margin), and the
height band at that spot that no fan touches (so the planner can pick a height).
"""

import csv
import json
import math
import os
import sys
from collections import defaultdict


def fwd(pitch, yaw):
    p, y = math.radians(pitch), math.radians(yaw)
    return (math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p))


def wrap(a):
    return (a + 180.0) % 360.0 - 180.0


def fans_from_recording(lights_csv, gimmicks_json):
    g = json.load(open(gimmicks_json, encoding="utf-8"))
    info = {L["name"]: L for L in g.get("lights", [])}
    by = defaultdict(list)
    with open(lights_csv, newline="") as f:
        for r in csv.DictReader(f):
            if all(r.get(k) not in (None, "") for k in ("t", "pitch", "yaw", "bx", "by", "bz")):
                by[r["light"]].append(r)            # (a recording cut off mid-line leaves a broken last row)
    fans = []
    for name, rows in by.items():
        free = [r for r in rows if r["on"] == "true" and r["tracking"] != "true"]
        # after a light has tracked a plane it swings back the long way before sweeping
        # again: only the samples before it first tracked describe its own sweep
        first_track = next((k for k, r in enumerate(rows) if r["tracking"] == "true"), None)
        if first_track is not None:
            before = [r for r in rows[:first_track] if r["on"] == "true"]
            if len(before) >= 30:
                free = before
        L = info.get(name, {})
        if not free:
            fans.append({"name": name, "on": False, "origin": L.get("beam_p") or L.get("p")})
            continue
        ps = [float(r["pitch"]) for r in free]
        ys = [float(r["yaw"]) for r in free]
        ref = ys[0]
        rel = [wrap(y - ref) for y in ys]
        lo_i = min(range(len(rel)), key=lambda i: rel[i] + 0 * ps[i])
        hi_i = max(range(len(rel)), key=lambda i: rel[i])
        mode = L.get("mode", "?")
        if mode == "pitch sweep":
            lo_i = min(range(len(ps)), key=lambda i: ps[i])
            hi_i = max(range(len(ps)), key=lambda i: ps[i])
        o = free[0]
        origin = [float(o["bx"]), float(o["by"]), float(o["bz"])]
        # swing speed: median of sample-to-sample angle change over time
        speeds = []
        for a, b in zip(free, free[1:]):
            dt = float(b["t"]) - float(a["t"])
            if 0.05 < dt < 0.3:
                d = math.degrees(math.acos(max(-1.0, min(1.0, sum(x * y for x, y in zip(fwd(float(a["pitch"]), float(a["yaw"])), fwd(float(b["pitch"]), float(b["yaw"]))))))))
                speeds.append(d / dt)
        speeds.sort()
        # a light that turns all the way round (a helicopter's, sweeping under it) is a ring
        # of beams: every direction at its pitch; where it sits is the mean of where it was,
        # and how far it wandered is kept (a hovering one barely moves, a patrolling one does)
        span = max(rel) - min(rel)
        pos = [(float(r["bx"]), float(r["by"]), float(r["bz"])) for r in free]
        mean = [sum(p[k] for p in pos) / len(pos) for k in range(3)]
        spread = max(math.dist(p, mean) for p in pos)
        kind = "ring" if span > 150 or "heli" in name else "fan"
        if kind == "ring":
            origin = mean
        fans.append({
            "name": name, "on": True, "mode": mode, "origin": origin, "kind": kind, "spread": spread,
            "ends": [[ps[lo_i], ys[lo_i]], [ps[hi_i], ys[hi_i]]],
            "pitch_range": [min(ps), max(ps)], "yaw_rel": [min(rel), max(rel)], "yaw_ref": ref,
            "speed": speeds[len(speeds) // 2] if speeds else 0.0,
            "half": (L.get("collision_deg") or 3.0) / 2.0, "reach": L.get("reach") or 30000,
            "samples": len(free), "tracked_samples": sum(1 for r in rows if r["tracking"] == "true"),
        })
    return fans


def fan_dirs(fan, n=40):
    """Beam directions across the fan (unit vectors)."""
    (p0, y0), (p1, y1) = fan["ends"]
    out = []
    dy = wrap(y1 - y0)
    for k in range(n + 1):
        u = k / n
        out.append(fwd(p0 + (p1 - p0) * u, y0 + dy * u))
    return out


def exposure(fan, q, margin_deg, dirs=None):
    """Smallest angle (deg) between q and any beam direction of the fan, minus the cone's
    half-angle and the margin: below 0 = the beam can light q. None if out of reach."""
    o = fan["origin"]
    d = (q[0] - o[0], q[1] - o[1], q[2] - o[2])
    dl = math.sqrt(sum(x * x for x in d))
    if dl > fan["reach"] + fan.get("spread", 0) or dl < 1:
        return None
    if fan.get("kind") == "ring":
        # the angle below (or above) the horizon that q is seen at, against the pitch band;
        # a wandering light's band is widened by how far it wanders, seen from q
        elev = math.degrees(math.atan2(d[2], math.hypot(d[0], d[1])))
        lo, hi = fan["pitch_range"]
        wander = math.degrees(math.atan2(fan.get("spread", 0), max(dl, 1)))
        off = max(0.0, lo - elev, elev - hi) - wander
        return off - fan["half"] - margin_deg
    u = tuple(x / dl for x in d)
    best = 180.0
    for f in dirs or fan_dirs(fan):
        c = max(-1.0, min(1.0, u[0] * f[0] + u[1] * f[1] + u[2] * f[2]))
        best = min(best, math.degrees(math.acos(c)))
    return best - fan["half"] - margin_deg


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    out, route = None, None
    i = 3
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]; i += 2
        elif argv[i] == "--route":
            route = argv[i + 1]; i += 2
        else:
            print("unknown option", argv[i]); return 1
    fans = fans_from_recording(argv[1], argv[2])
    on = [f for f in fans if f.get("on")]
    print(f"{len(fans)} lights recorded, {len(on)} were on and sweeping")
    for f in sorted(on, key=lambda f: -f["origin"][1])[:80]:
        print(f"  {f['name']:38s} at ({f['origin'][0]:.0f}, {f['origin'][1]:.0f}, {f['origin'][2] / 10:.0f} m) {f['mode']:11s} "
              f"pitch {f['pitch_range'][0]:6.1f}..{f['pitch_range'][1]:6.1f}  yaw {f['yaw_ref'] + f['yaw_rel'][0]:7.1f}..{f['yaw_ref'] + f['yaw_rel'][1]:7.1f}  "
              f"{f['speed']:4.1f} deg/s  reach {f['reach'] / 10:.0f} m{'  TRACKED US' if f['tracked_samples'] else ''}")
    if out:
        with open(out, "w", encoding="utf-8") as fo:
            json.dump(fans, fo, indent=1)
        # the same sweeps as CSV for the pilot ("fans" order): the two ends on the sweep's
        # own axis (yaw for a yaw sweep, pitch for a pitch sweep) and the speed
        with open(os.path.splitext(out)[0] + ".csv", "w", newline="") as fc:
            w = csv.writer(fc)
            w.writerow(["name", "mode", "lo", "hi", "speed"])
            for f in on:
                if f.get("kind") == "ring":
                    w.writerow([f["name"], "ring", 0, 0, f["speed"]])
                elif f["mode"] == "pitch sweep":
                    w.writerow([f["name"], "pitch", f"{f['pitch_range'][0]:.2f}", f"{f['pitch_range'][1]:.2f}", f"{f['speed']:.2f}"])
                elif f["mode"] == "yaw sweep":
                    w.writerow([f["name"], "yaw", f"{f['yaw_ref'] + f['yaw_rel'][0]:.2f}", f"{f['yaw_ref'] + f['yaw_rel'][1]:.2f}", f"{f['speed']:.2f}"])
                else:
                    w.writerow([f["name"], "stopped", 0, 0, 0])
    if route:
        rows = list(csv.DictReader(open(route, newline="")))
        dirs = {f["name"]: fan_dirs(f) for f in on}
        s = 0.0
        prev = None
        for r in rows:
            x, y, z = float(r["x"]), float(r["y"]), float(r["z"])
            if prev:
                s += math.hypot(x - prev[0], y - prev[1]) / 10
            prev = (x, y)
            lit = []
            for f in on:
                e = exposure(f, (x, y, z), 1.0, dirs[f["name"]])
                if e is not None and e < 0:
                    lit.append(f["name"].replace("_SystemObject_SearchLight", ""))
            if lit:
                # the heights at this spot that no fan touches, from 100 m to 545 m
                free = []
                for zz in range(1000, 5460, 100):
                    if all((exposure(f, (x, y, zz), 1.0, dirs[f["name"]]) or 1) >= 0 for f in on):
                        free.append(zz // 10)
                print(f"  {s / 1000:5.1f} km at {z / 10:.0f} m: inside the fan of {', '.join(lit)}; unlit heights here: {free[:3]}...{free[-3:] if free else ''} ({len(free)} of 45)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
