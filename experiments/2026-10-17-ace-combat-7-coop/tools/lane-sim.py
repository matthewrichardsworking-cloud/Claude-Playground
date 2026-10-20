"""The lane planner's offline simulator (19 Oct 2026, the Mission 06 score-race plan's "punch 2"):
general rules for chaining kills, tuned across many varied target layouts rather than one level.

    python tools\\lane-sim.py compare            lanes against the old nose-on attack, every layout kind
    python tools\\lane-sim.py tune               search the planner's parameters (coordinate descent)
    python tools\\lane-sim.py sweep laneKmh 500 650 800     one parameter at several values, all layouts
    python tools\\lane-sim.py one --kind rows --seed 3 --trace   one run, second by second
    python tools\\lane-sim.py layout <file.json> a layout dumped from the game (the pilot's "targets"
                                                 order) as one more test case

The planner here is a line-for-line copy of mods\\CoopPilotMod\\Scripts\\lanes.lua (keep the two
the same), except the vertical attacks of 20 Oct 2026 (lanes.lua's L.simulateDive and the dive
legs in L.plan): they need a 3D plane, which this world does not have yet, and were tuned in the
game itself. Around it a simple world: a plane that turns at a measured rate after a roll-in lag
(the Typhoon's flight logs: about 35-45 deg/s at 500-700 km/h with a full pull), holds its speed,
and eases to the pass height; the standard missile's lock cone, lock range, lock time (a base
time plus the angle the seeker travels), two loaded missiles with a reload clock each, missile
flight time and a hit chance. Every scenario also varies the plane and weapon numbers, so the
parameters that win are the ones that hold for other planes, weapons and parts too.

Layout kinds: clusters, rows, scatter, ring (a base), harbour (rows along a shore), mixed.
Units as in the game: 10 cm per unit, seconds, radians inside.
"""

import json
import math
import os
import random
import sys
import time
from concurrent.futures import ProcessPoolExecutor

KMH = 1000 / 3.6 * 10 / 1000 * 10 / 10   # km/h -> units/s: 1 km/h = 2.7778 units/s
KMH = 10000 / 3600.0

# ---- the planner: a copy of lanes.lua --------------------------------------------------------

P_DEFAULT = {
    "horizon": 12.0, "dt": 0.25,
    "turns": [0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90, 120, -120, 150, -150, 179, -179],
    "extend": [[0, 2.5, 179], [0, 2.5, -179], [0, 5.0, 179], [0, 5.0, -179]],
    "rollIn": 0.15, "rollRate": 120.0, "bankTurn": 80.0, "discount": 8.0, "terminal": 0.25, "hysteresis": 0.15, "passAgl": 250.0,
    "minRange": 500.0, "coneMargin": 1.0, "rangeMargin": 0.97, "climbRate": 0.3,
    # the world's pilot (not the planner): pass speed, and the share of the measured turn rate
    # the planner counts on
    "laneKmh": 650.0, "omegaShare": 0.85,
}


def clamp(x, a, b):
    return a if x < a else (b if x > b else x)


def wrap_pi(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def pick(x, y, z, fx, fy, fz, tg, skip, cos_cone, r_min, r_max):
    best, best_score, best_ang = None, -1e300, None
    sqrt, acos, log, deg = math.sqrt, math.acos, math.log, math.degrees
    for i, q in enumerate(tg):
        if skip(i):
            continue
        dx, dy, dz = q[0] - x, q[1] - y, q[2] - z
        d = sqrt(dx * dx + dy * dy + dz * dz)
        if r_min <= d <= r_max:
            dp = dx * fx + dy * fy + dz * fz
            if dp > cos_cone * d:
                ang = acos(clamp(dp / d, -1.0, 1.0))
                score = -deg(ang) + 10 * log(max(q[3], 1e-6))
                if score > best_score:
                    best, best_score, best_ang = i, score, ang
    return best, best_ang


def simulate(pl, wp, tg, leg, P):
    x, y, z, psi, v = pl["x"], pl["y"], pl["z"], pl["psi"], pl["v"]
    omega = pl["omega"]
    loaded = wp["loaded"]
    reload = list(wp.get("reloadIn") or [])
    done = set()
    is_done = done.__contains__
    sel, sel_need, sel_t = wp.get("sel"), wp.get("selLeft") or 0.0, 0.0
    cos_cone = math.cos(wp["cone"] - math.radians(P["coneMargin"]))
    r_max = wp["range"] * P["rangeMargin"]
    r_min = wp.get("minRange") or P["minRange"] * 10
    value, shots, first, raw = 0.0, 0, None, 0.0
    heading = leg["psi1"]
    switched = leg.get("tSwitch") is None
    roll_rate, bank_turn = math.radians(P["rollRate"]), math.radians(P["bankTurn"])

    def roll_time(direction, bank):
        return P["rollIn"] + abs(direction * bank_turn - bank) / roll_rate
    d1 = wrap_pi(heading - psi)
    dir1 = 1 if d1 > 0.03 else (-1 if d1 < -0.03 else 0)
    roll_until = roll_time(dir1, pl.get("roll", 0.0)) if dir1 != 0 else 0.0
    t = 0.0
    dt = P["dt"]
    horizon, discount, climb = P["horizon"], P["discount"], P["climbRate"]
    z_pass = pl["zPass"]
    sqrt, cos, sin, exp = math.sqrt, math.cos, math.sin, math.exp
    while t < horizon - 1e-6:
        t += dt
        if not switched and t >= leg["tSwitch"]:
            bank_now = dir1 * bank_turn if abs(wrap_pi(heading - psi)) > 0.03 else 0.0
            d2 = wrap_pi(leg["psi2"] - psi)
            heading, switched = leg["psi2"], True
            roll_until = t + roll_time(1 if d2 >= 0 else -1, bank_now)
        if t > roll_until:
            step = omega * dt
            psi += clamp(wrap_pi(heading - psi), -step, step)
        vz = clamp((z_pass - z) / 3, -v * climb, v * climb)
        ch, sh = cos(psi), sin(psi)
        vh = sqrt(max(v * v - vz * vz, 1))
        x += vh * ch * dt
        y += vh * sh * dt
        z += vz * dt
        fx, fy, fz = vh * ch / v, vh * sh / v, vz / v
        if reload:
            keep = []
            for r in reload:
                if r <= t:
                    loaded += 1
                else:
                    keep.append(r)
            reload = keep
        if sel is not None:
            q = tg[sel]
            dx, dy, dz = q[0] - x, q[1] - y, q[2] - z
            d = sqrt(dx * dx + dy * dy + dz * dz)
            if sel in done or d > r_max or d < r_min or (dx * fx + dy * fy + dz * fz) < cos_cone * d:
                sel = None
        if sel is None:
            sel, ang = pick(x, y, z, fx, fy, fz, tg, is_done, cos_cone, r_min, r_max)
            if sel is not None:
                sel_need = wp["lockBase"] + ang / wp["lockRate"]
                sel_t = 0.0
        if sel is not None:
            sel_t += dt
            if sel_t >= sel_need and loaded > 0:
                loaded -= 1
                reload.append(t + wp["loadTime"])
                value += tg[sel][3] * exp(-t / discount)
                raw += tg[sel][3]
                shots += 1
                if first is None:
                    first = t
                done.add(sel)
                sel = None
    term = 0.0
    reach = wp["range"] * 3
    ch, sh = cos(psi), sin(psi)
    for i, q in enumerate(tg):
        if i in done:
            continue
        dx, dy = q[0] - x, q[1] - y
        d = sqrt(dx * dx + dy * dy)
        if 1 < d < reach:
            c = (dx * ch + dy * sh) / d
            if c > 0.5:
                term += q[3] * (c - 0.5) * 2 * (1 - d / reach)
    return value + P["terminal"] * term * exp(-horizon / discount), shots, first, x, y, psi, raw


def plan(pl, wp, tg, prev, now, ok_end, P):
    legs = [{"psi1": wrap_pi(pl["psi"] + math.radians(a))} for a in P["turns"]]
    for e in P.get("extend") or []:
        legs.append({"psi1": wrap_pi(pl["psi"] + math.radians(e[0])), "tSwitch": e[1],
                     "psi2": wrap_pi(pl["psi"] + math.radians(e[0] + e[2]))})
    best, best_v, best_shots, best_first, best_raw = None, -1.0, 0, None, 0.0
    for leg in legs:
        v, shots, first, ex, ey, _, raw = simulate(pl, wp, tg, leg, P)
        if ok_end and not ok_end(ex, ey):
            v *= 0.2
        if v > best_v:
            best, best_v, best_shots, best_first, best_raw = leg, v, shots, first, raw
    kept = False
    if prev is not None and best is not None:
        leg = {"psi1": prev["psi1"]}
        if prev.get("switchAt") is not None and prev["switchAt"] > now:
            leg["tSwitch"], leg["psi2"] = prev["switchAt"] - now, prev["psi2"]
        elif prev.get("switchAt") is not None:
            leg["psi1"] = prev["psi2"]
        v, shots, first, ex, ey, _, raw = simulate(pl, wp, tg, leg, P)
        if ok_end and not ok_end(ex, ey):
            v *= 0.2
        if v > 0 and v >= best_v * (1 - P["hysteresis"]):
            best, best_v, best_shots, best_first, best_raw, kept = leg, v, shots, first, raw, True
    if best is None:
        return None
    return {"psi1": best["psi1"], "psi2": best.get("psi2"),
            "switchAt": (now + best["tSwitch"]) if best.get("tSwitch") is not None else None,
            "value": best_v, "shots": best_shots, "first": best_first, "raw": best_raw, "kept": kept}


def heading(pl_, now):
    if pl_.get("switchAt") is not None and now >= pl_["switchAt"]:
        return pl_["psi2"]
    return pl_["psi1"]


def cone_pick(px, py, pz, fx, fy, fz, wp, tg, skip, P):
    return pick(px, py, pz, fx, fy, fz, tg, skip or (lambda i: False),
                math.cos(wp["cone"] - math.radians(P["coneMargin"])), wp.get("minRange") or P["minRange"] * 10,
                wp["range"] * P["rangeMargin"])


# ---- layouts ----------------------------------------------------------------------------------

def make_layout(kind, rng):
    """Targets: [x, y, z, points, hp] in game units around (0, 0); ground at z 0 (or a hill)."""
    pts = []

    def tgt(x, y):
        hp = 40 if rng.random() < 0.8 else rng.choice([80, 120, 160])
        pval = rng.choice([100, 120, 150, 150, 200, 200]) if rng.random() < 0.85 else rng.choice([300, 400, 500])
        pts.append([x, y, rng.uniform(0, 300), pval, hp])

    if kind == "clusters":
        for _ in range(rng.randint(2, 5)):
            cx, cy = rng.uniform(-25000, 25000), rng.uniform(-25000, 25000)
            sig = rng.uniform(1500, 6000)
            for _ in range(rng.randint(4, 12)):
                tgt(cx + rng.gauss(0, sig), cy + rng.gauss(0, sig))
    elif kind == "rows":
        for _ in range(rng.randint(3, 6)):
            cx, cy = rng.uniform(-25000, 25000), rng.uniform(-25000, 25000)
            a = rng.uniform(0, math.pi)
            gap = rng.uniform(800, 2500)
            n = rng.randint(5, 12)
            for k in range(n):
                s = (k - n / 2) * gap
                tgt(cx + s * math.cos(a) + rng.gauss(0, 150), cy + s * math.sin(a) + rng.gauss(0, 150))
    elif kind == "scatter":
        for _ in range(rng.randint(20, 40)):
            tgt(rng.uniform(-30000, 30000), rng.uniform(-30000, 30000))
    elif kind == "ring":
        r = rng.uniform(4000, 9000)
        n = rng.randint(8, 16)
        for k in range(n):
            a = 2 * math.pi * k / n + rng.gauss(0, 0.1)
            tgt(r * math.cos(a), r * math.sin(a))
        for _ in range(rng.randint(3, 8)):
            tgt(rng.gauss(0, r / 3), rng.gauss(0, r / 3))
    elif kind == "harbour":
        a = rng.uniform(0, math.pi)
        for row in (0, 1):
            off = row * rng.uniform(2500, 6000)
            n = rng.randint(6, 12)
            gap = rng.uniform(1200, 3000)
            for k in range(n):
                s = (k - n / 2) * gap
                tgt(s * math.cos(a) - off * math.sin(a) + rng.gauss(0, 300), s * math.sin(a) + off * math.cos(a) + rng.gauss(0, 300))
        for _ in range(rng.randint(4, 10)):
            tgt(rng.uniform(-20000, 20000), rng.uniform(-20000, 20000))
    else:  # mixed
        for k in ("clusters", "rows", "scatter"):
            sub = make_layout(k, rng)
            pts.extend(sub[: max(4, len(sub) // 2)])
    return pts


def make_world(kind, seed):
    """One scenario: a layout and a plane and weapon drawn from a range of plausible numbers."""
    rng = random.Random(f"{kind}:{seed}")
    tg = make_layout(kind, rng)
    cx = sum(q[0] for q in tg) / len(tg)
    cy = sum(q[1] for q in tg) / len(tg)
    a = rng.uniform(0, 2 * math.pi)
    start = (cx + 80000 * math.cos(a), cy + 80000 * math.sin(a))
    psi0 = math.atan2(cy - start[1], cx - start[0]) + rng.uniform(-0.5, 0.5)
    plane = {"omega": math.radians(rng.uniform(25, 45)), "lag": rng.uniform(0.1, 0.3), "rollRate": rng.uniform(100, 160),
             "start": start, "psi0": psi0, "z0": rng.uniform(3000, 15000)}
    weapon = {"cone": math.radians(rng.uniform(28, 35)), "range": rng.uniform(18000, 24000), "maxLoaded": 2,
              "loadTime": rng.uniform(4.0, 6.0), "lockBase": rng.uniform(0.2, 0.8), "lockRate": math.radians(rng.uniform(40, 100)),
              "mspeed": rng.uniform(7000, 10000), "damage": 40, "phit": rng.uniform(0.85, 0.97)}
    return {"kind": kind, "seed": seed, "targets": tg, "plane": plane, "weapon": weapon, "rng_seed": rng.random()}


# ---- the world and the pilot ------------------------------------------------------------------

CLASSES = ("locked", "ahead", "offnose", "transit")


def run(world, P, policy="lanes", duration=180.0, trace=False, speed_kmh=None, transit_kmh=1100.0):
    """Fly one scenario for 'duration' seconds; points per minute counted from the first time a
    target is within 6 km (the time in the area), so the approach from 8 km does not count."""
    rng = random.Random(world["rng_seed"])
    speed_kmh = speed_kmh or P.get("laneKmh", 650.0)
    tg = [list(q) for q in world["targets"]]
    pw, ww = world["plane"], world["weapon"]
    x, y = pw["start"]
    z = pw["z0"]
    psi = pw["psi0"]
    rate = 0.0
    bank, bank_target = 0.0, 0.0
    omega = pw["omega"]
    alive = [True] * len(tg)
    hp = [q[4] for q in tg]
    incoming = [0.0] * len(tg)        # damage on its way
    loaded = ww["maxLoaded"]
    reload = []
    flying = []                       # (arrival time, target index, damage)
    sel, sel_t, sel_need = None, 0.0, 0.0
    psi_cmd, z_cmd = psi, z
    prev_plan = None
    last_plan = -9.0
    points, kills, shots = 0.0, 0, 0
    split = {k: 0.0 for k in CLASSES}
    t = 0.0
    dt = 0.1
    t_area = None
    log = []
    while t < duration + (t_area or 0):
        t += dt
        v = (speed_kmh if t_area is not None else transit_kmh) * KMH
        # nearest live target (for the transit / area clock)
        near_d = 1e18
        for i, q in enumerate(tg):
            if alive[i]:
                d = math.hypot(q[0] - x, q[1] - y)
                if d < near_d:
                    near_d = d
        if near_d > 1e17:
            break
        if t_area is None and near_d < 60000:
            t_area = t
        if t_area is not None and near_d > 60000:
            v = transit_kmh * KMH
        # reloads and missiles arriving
        if reload:
            keep = []
            for r in reload:
                if r <= t:
                    loaded += 1
                else:
                    keep.append(r)
            reload = keep
        if flying:
            keep = []
            for (ta, i, dmg) in flying:
                if ta <= t:
                    incoming[i] -= dmg
                    if alive[i] and rng.random() < ww["phit"]:
                        hp[i] -= dmg
                        if hp[i] <= 0:
                            alive[i] = False
                            if t_area is not None:
                                points += tg[i][3]
                                kills += 1
                            if sel == i:
                                sel = None
                else:
                    keep.append((ta, i, dmg))
            flying = keep
        speed = v
        vz_now = clamp((z_cmd - z) / 3, -speed * 0.25, speed * 0.25)
        vh = math.sqrt(max(speed * speed - vz_now * vz_now, 1))
        fx, fy, fz = vh * math.cos(psi) / speed, vh * math.sin(psi) / speed, vz_now / speed
        # the target list the pilot sees: alive, and not already covered by missiles on their way
        def value_of(i):
            rem = hp[i] - incoming[i]
            return tg[i][3] * min(1.0, ww["damage"] / max(rem, 1))
        avail = [i for i in range(len(tg)) if alive[i] and hp[i] - incoming[i] > 0]
        # the plan, twice a second
        if policy == "lanes" and t - last_plan >= 0.5:
            last_plan = t
            reach = v * P["horizon"] + ww["range"] * 3
            near = [i for i in avail if math.hypot(tg[i][0] - x, tg[i][1] - y) < reach]
            tl = [[tg[i][0], tg[i][1], tg[i][2], value_of(i)] for i in near]
            zg = sorted(tg[i][2] for i in near)[len(near) // 2] if near else 0.0
            z_pass = zg + P["passAgl"] * 10
            wpl = {"cone": ww["cone"], "range": ww["range"], "loaded": loaded,
                   "reloadIn": [r - t for r in reload], "loadTime": ww["loadTime"], "lockBase": P.get("lockBaseEst", 0.5),
                   "lockRate": P.get("lockRateEst", math.radians(60)), "sel": None, "selLeft": 0.0}
            if sel is not None and sel in near:
                wpl["sel"] = near.index(sel)
                wpl["selLeft"] = max(0.0, sel_need - sel_t)
            pl = {"x": x, "y": y, "z": z, "psi": psi, "v": v, "omega": omega * P.get("omegaShare", 0.85), "zPass": z_pass,
                  "roll": bank if P.get("rollAware", True) else 0.0}
            res = plan(pl, wpl, tl, prev_plan, t, None, P) if tl else None
            if res and res["value"] > 1e-3:
                prev_plan = res
                z_cmd = z_pass
            else:
                prev_plan = None
                # transit: toward the most value per distance
                best, bv = None, -1
                for i in avail:
                    d = math.hypot(tg[i][0] - x, tg[i][1] - y)
                    s = value_of(i) / (d + 20000)
                    if s > bv:
                        best, bv = i, s
                if best is not None:
                    psi_cmd = math.atan2(tg[best][1] - y, tg[best][0] - x)
                    z_cmd = tg[best][2] + P["passAgl"] * 10
        if policy == "nose":
            # the old way: nose on the chosen target (most value for the time to get it), a loop
            # out to 1.5 km when it is close and off the nose
            if t - last_plan >= 1.0 or sel is None:
                last_plan = t
                best, bs = None, -1
                for i in avail:
                    dx, dy = tg[i][0] - x, tg[i][1] - y
                    d = math.hypot(dx, dy)
                    ang = abs(wrap_pi(math.atan2(dy, dx) - psi))
                    tt = d / v + math.degrees(ang) / 30 + (10 if (d < 16000 and ang > math.radians(15)) else 0)
                    s = value_of(i) / (tt + 10)
                    if s > bs:
                        best, bs = i, s
                if best is not None and best != sel:
                    sel, sel_t = best, 0.0
                    dx, dy, dz = tg[best][0] - x, tg[best][1] - y, tg[best][2] - z
                    dd = math.sqrt(dx * dx + dy * dy + dz * dz)
                    ang0 = math.acos(clamp((dx * fx + dy * fy + dz * fz) / max(dd, 1), -1, 1))
                    sel_need = ww["lockBase"] + ang0 / ww["lockRate"]
            if sel is not None:
                dx, dy = tg[sel][0] - x, tg[sel][1] - y
                d = math.hypot(dx, dy)
                ang = abs(wrap_pi(math.atan2(dy, dx) - psi))
                if d < 7000 or (d < 15000 and ang > math.radians(35)):
                    psi_cmd = math.atan2(-dy, -dx)
                else:
                    psi_cmd = math.atan2(dy, dx)
                z_cmd = tg[sel][2] + 5500
        if policy == "lanes" and prev_plan is not None:
            psi_cmd = heading(prev_plan, t)
        # selection in the lanes way: keep it while it stays in the cone, else the cone pick
        if policy == "lanes":
            if sel is not None:
                ok = alive[sel] and hp[sel] - incoming[sel] > 0
                if ok:
                    dx, dy, dz = tg[sel][0] - x, tg[sel][1] - y, tg[sel][2] - z
                    d = math.sqrt(dx * dx + dy * dy + dz * dz)
                    cc = math.cos(ww["cone"])
                    ok = d <= ww["range"] and (dx * fx + dy * fy + dz * fz) >= cc * d
                if not ok:
                    sel = None
            if sel is None:
                tl_all = [[q[0], q[1], q[2], 0] for q in tg]
                for i in range(len(tg)):
                    tl_all[i][3] = value_of(i) if alive[i] else 0
                i, ang = cone_pick(x, y, z, fx, fy, fz, ww, tl_all,
                                   lambda k: not alive[k] or hp[k] - incoming[k] <= 0, P)
                if i is not None:
                    sel, sel_t = i, 0.0
                    sel_need = ww["lockBase"] + ang / ww["lockRate"]
        # the lock: the selected target inside the game's real cone and range
        locked = False
        if sel is not None:
            dx, dy, dz = tg[sel][0] - x, tg[sel][1] - y, tg[sel][2] - z
            d = math.sqrt(dx * dx + dy * dy + dz * dz)
            in_cone = d <= ww["range"] and (dx * fx + dy * fy + dz * fz) >= math.cos(ww["cone"]) * d
            if in_cone:
                sel_t += dt
            else:
                sel_t = 0.0
            locked = in_cone and sel_t >= sel_need
            if locked and loaded > 0 and hp[sel] - incoming[sel] > 0:
                loaded -= 1
                reload.append(t + ww["loadTime"])
                flying.append((t + d / ww["mspeed"] + 0.3, sel, ww["damage"]))
                incoming[sel] += ww["damage"]
                shots += 1
                if hp[sel] - incoming[sel] <= 0:
                    sel = None                 # the chain: the next one at once
        # where the time goes
        if t_area is not None:
            if locked:
                cls = "locked"
            elif sel is not None:
                cls = "ahead"
            elif near_d < 30000:
                cls = "offnose"
            else:
                cls = "transit"
            split[cls] += dt
        # fly: bank toward the turn (at the roll rate, after a reaction lag), the turn rate
        # following the bank: a reversal has to roll through level first
        err = wrap_pi(psi_cmd - psi)
        bank_cmd = clamp(err * 4.0, -math.radians(80), math.radians(80))
        roll_rate_w = math.radians(pw.get("rollRate", 130.0))
        bank_target += (bank_cmd - bank_target) * min(1.0, dt / pw["lag"])
        bank += clamp(bank_target - bank, -roll_rate_w * dt, roll_rate_w * dt)
        rate = omega * math.sin(bank) / math.sin(math.radians(80))
        psi = wrap_pi(psi + rate * dt)
        z += vz_now * dt
        x += vh * math.cos(psi) * dt
        y += vh * math.sin(psi) * dt
        if trace and int(t * 10) % 10 == 0:
            log.append(f"{t:6.1f} pos ({x / 10000:6.2f},{y / 10000:6.2f}) km z {z / 10:5.0f} m psi {math.degrees(psi):5.0f} "
                       f"cmd {math.degrees(psi_cmd):5.0f} sel {sel} locked {locked} loaded {loaded} kills {kills} pts {points:.0f}")
    area_min = max((t - (t_area or t)) / 60.0, 1e-6)
    total = len(tg)
    return {"points_per_min": points / area_min, "kills_per_min": kills / area_min, "kills": kills, "shots": shots,
            "share_killed": kills / total, "split": {k: split[k] / max(sum(split.values()), 1e-6) for k in CLASSES},
            "log": log}


# ---- experiments ------------------------------------------------------------------------------

KINDS = ["clusters", "rows", "scatter", "ring", "harbour", "mixed"]


def _one(args):
    world, P, policy, duration = args
    r = run(world, P, policy, duration)
    r.pop("log", None)
    return world["kind"], world["seed"], r


def evaluate(P, policy="lanes", seeds=6, duration=180.0, kinds=KINDS, extra=(), workers=int(os.environ.get("LANESIM_WORKERS", "16"))):
    jobs = [(make_world(k, s), P, policy, duration) for k in kinds for s in range(seeds)]
    jobs += [(w, P, policy, duration) for w in extra]
    with ProcessPoolExecutor(max_workers=workers) as ex:
        res = list(ex.map(_one, jobs))
    by_kind = {}
    for kind, seed, r in res:
        by_kind.setdefault(kind, []).append(r)
    summary = {}
    for kind, rs in by_kind.items():
        n = len(rs)
        summary[kind] = {"ppm": sum(r["points_per_min"] for r in rs) / n, "kpm": sum(r["kills_per_min"] for r in rs) / n,
                         "killed": sum(r["share_killed"] for r in rs) / n,
                         "split": {c: sum(r["split"][c] for r in rs) / n for c in CLASSES}}
    allr = [r for _, _, r in res]
    summary["ALL"] = {"ppm": sum(r["points_per_min"] for r in allr) / len(allr),
                      "kpm": sum(r["kills_per_min"] for r in allr) / len(allr),
                      "killed": sum(r["share_killed"] for r in allr) / len(allr),
                      "split": {c: sum(r["split"][c] for r in allr) / len(allr) for c in CLASSES},
                      "worst_kind_ppm": min(summary[k]["ppm"] for k in by_kind)}
    return summary


def show(summary, title):
    print(f"--- {title}")
    for k, s in summary.items():
        sp = ", ".join(f"{c} {100 * s['split'][c]:.0f}%" for c in CLASSES)
        print(f"  {k:9s} {s['ppm']:7.0f} points/min  {s['kpm']:5.2f} kills/min  {100 * s['killed']:3.0f}% killed  | {sp}")


def tune(seeds=8, duration=150.0, extra=()):
    P = dict(P_DEFAULT)
    grid = {
        "horizon": [5.0, 6.5, 8.0, 10.0, 12.0],
        "discount": [8.0, 12.0, 20.0, 40.0],
        "terminal": [0.0, 0.25, 0.5, 1.0],
        "hysteresis": [0.0, 0.1, 0.2, 0.35],
        "passAgl": [200.0, 300.0, 400.0],
        "minRange": [300.0, 500.0, 800.0],
        "coneMargin": [1.0, 3.0, 6.0],
        "omegaShare": [0.6, 0.85, 1.0],
        "laneKmh": [500.0, 650.0, 800.0],
    }
    base = evaluate(P, seeds=seeds, duration=duration, extra=extra)
    score = base["ALL"]["ppm"]
    print(f"start: {score:.0f} points/min (worst kind {base['ALL']['worst_kind_ppm']:.0f})", flush=True)
    for rnd in range(2):
        for key, vals in grid.items():
            best_v, best_s = P.get(key), score
            for v in vals:
                if v == P.get(key):
                    continue
                Q = dict(P)
                Q[key] = v
                s = evaluate(Q, seeds=seeds, duration=duration, extra=extra)
                sc = s["ALL"]["ppm"]
                print(f"  round {rnd + 1} {key} = {v}: {sc:.0f} (worst kind {s['ALL']['worst_kind_ppm']:.0f})", flush=True)
                # better on average and not worse for the weakest layout kind by more than 3%
                if sc > best_s * 1.01 and s["ALL"]["worst_kind_ppm"] >= base["ALL"]["worst_kind_ppm"] * 0.97:
                    best_v, best_s, best_sum = v, sc, s
            if best_v != P.get(key):
                P[key] = best_v
                score = best_s
                base = best_sum
                print(f"-> {key} = {best_v} ({score:.0f} points/min)", flush=True)
    print("tuned:", json.dumps({k: P.get(k) for k in grid}))
    return P


def load_layout(path):
    """A layout the pilot dumped from the game: [{x, y, z, bounty, hp, ...}] -> a world."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    # what the lanes would take: on the ground (or helicopters), with a HUD box, worth points
    tg = [[q["x"], q["y"], q["z"], q.get("bounty", 150), max(q.get("hp", 40), 1)] for q in data["targets"]
          if not q.get("air") and q.get("hud_box", True) and q.get("bounty", 0) > 0 and q.get("lockable", True)]
    rng = random.Random(path)
    cx = sum(q[0] for q in tg) / len(tg)
    cy = sum(q[1] for q in tg) / len(tg)
    start = (data.get("plane", {}).get("x", cx + 80000), data.get("plane", {}).get("y", cy))
    plane = {"omega": math.radians(38), "lag": 0.35, "start": start,
             "psi0": math.atan2(cy - start[1], cx - start[0]), "z0": data.get("plane", {}).get("z", 10000)}
    w = data.get("weapon", {})
    weapon = {"cone": math.radians(w.get("cone_deg", 32.5)), "range": w.get("range", 20000), "maxLoaded": w.get("loaded", 2),
              "loadTime": w.get("load_s", 5.5), "lockBase": 0.5, "lockRate": math.radians(60), "mspeed": w.get("mspeed", 9000),
              "damage": w.get("damage", 40), "phit": 0.92}
    return {"kind": "game:" + os.path.basename(path), "seed": 0, "targets": tg, "plane": plane, "weapon": weapon,
            "rng_seed": rng.random()}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    extra = []
    if "--layout" in argv:
        extra.append(load_layout(argv[argv.index("--layout") + 1]))
    if cmd == "compare":
        t0 = time.time()
        show(evaluate(dict(P_DEFAULT), "nose", extra=extra), "old way: nose on one target, loop out and back")
        show(evaluate(dict(P_DEFAULT), "lanes", extra=extra), "lanes: the flight path for the cone, chained picks")
        print(f"({time.time() - t0:.0f} s)")
    elif cmd == "tune":
        tune(extra=extra)
    elif cmd == "sweep":
        key = argv[2]
        vals = [float(v) for v in argv[3:] if not v.startswith("--")]
        for v in vals:
            P = dict(P_DEFAULT)
            P[key] = math.radians(v) if key == "lockRateEst" else v
            s = evaluate(P, seeds=8, duration=150.0, extra=extra)
            print(f"{key} = {v}: {s['ALL']['ppm']:.0f} points/min, {s['ALL']['kpm']:.2f} kills/min, "
                  f"worst kind {s['ALL']['worst_kind_ppm']:.0f}, killed {100 * s['ALL']['killed']:.0f}%", flush=True)
    elif cmd == "one":
        kind = argv[argv.index("--kind") + 1] if "--kind" in argv else "clusters"
        seed = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 0
        policy = argv[argv.index("--policy") + 1] if "--policy" in argv else "lanes"
        r = run(make_world(kind, seed), dict(P_DEFAULT), policy, 180.0, trace="--trace" in argv)
        for line in r.pop("log"):
            print(line)
        print(json.dumps(r, indent=1))
    elif cmd == "layout":
        w = load_layout(argv[2])
        for policy in ("nose", "lanes"):
            r = run(w, dict(P_DEFAULT), policy, 300.0)
            r.pop("log")
            print(policy, json.dumps(r))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
