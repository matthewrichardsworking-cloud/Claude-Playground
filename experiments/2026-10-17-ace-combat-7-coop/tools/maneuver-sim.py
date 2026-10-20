"""Terrain wargames for the pilot's manoeuvring (20 Oct 2026; the owner: work on the bot's
"pathfinding, maneuvering, innate knowledge of its own aircraft's capabilities and how to use
them in maneuvering, and decision making").

    python tools\\maneuver-sim.py compare [--n 300]          every safety layer on the same scenarios
    python tools\\maneuver-sim.py one --seed 7 --layer planner --trace
    python tools\\maneuver-sim.py sweep margin 40 80 120     one planner parameter, several values
    set SIM_LINE=1 (attack lines, approach.lua), SIM_GEOMETRY=1 (the entry-point runs before it),
    SIM_PICK=near|geo|random (the next target), SIM_DG/SIM_DA/SIM_CARROT/SIM_STRICT (the lines),
    SIM_WORKERS (processes); compare --dur 600 flies ten-minute flights (a mission phase)

The world: a mission's surveyed ground (the pilot's "survey" order: the top of whatever is there,
every 50 m; playtests\\missions\\m07\\terrain-50m.csv by default) and the plane as measured from
its own flight logs (tools\\aircraft-model.py -> playtests\\aircraft\\typhoon.json): the turn rate
of the flight path, the roll rate, and the speed change by climb angle for throttle, brake,
high-G or nothing. The pilot here flies ground attack runs the way main.lua's groundRun does
(level at 550 m over the ground until 2.6 km out, then at the target, diving 28 degrees at most;
out again at 700 m or 250 m above the ground) at Mission 07's 17 ground targets (where the game
has them), or with SIM_LINE=1 on attack lines as approach.lua flies them; a shot counts when the
target has been 500-2,000 m away within 25 degrees of the nose with nothing in the line for a
second (the lock), and that target is then gone until all are (a mission phase's targets).

Safety layers compared (each turns the pilot's wanted direction into the one flown):
  none     the wanted direction as it is
  vision   main.lua's fight safety net today: straight rays along the wanted way; when blocked
           within 3 s, the free direction nearest it in a fan (yaw +-40, pitch +-30 degrees),
           and 550 km/h for 20 s after
  planner  maneuver.lua's planner (this file is its test bed): candidate manoeuvres (where the
           lift points x how hard to pull x keep speed or brake), each flown ahead in the plane's
           measured model; the wanted way if it stays clear, else the safe one closest to it
Units: game units (10 cm) for positions, m/s for speeds, radians inside.
"""

import json
import math
import os
import random
import sys
import time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TERRAIN = os.path.join(ROOT, "playtests", "missions", "m07", "terrain-50m.csv")
MODEL = os.path.join(ROOT, "playtests", "aircraft", "typhoon.json")
GEOMETRY = "--geometry" in sys.argv or os.environ.get("SIM_GEOMETRY") == "1"
# the approach on a line of sight (attack lines, 20 Oct 2026): the line chosen by how soon the plane
# can be on it, flown onto from outside and down to the target ("SIM_LINE=1"); and the target
# chosen with the time its approach takes, not by distance alone ("SIM_PICK=geo", or "near")
LINE = "--line" in sys.argv or os.environ.get("SIM_LINE") == "1"
PICK = os.environ.get("SIM_PICK", "random")
SPEEDPLAN = os.environ.get("SIM_SPEEDPLAN", "1") == "1"
STEEP = os.environ.get("SIM_STEEP", "1") == "1"      # an aim steeper than 70 degrees is flown, not turned level
WIDE = os.environ.get("SIM_WIDE", "0") == "1"
SHORTOUT = os.environ.get("SIM_SHORTOUT", "1") == "1"
FAR_A = float(os.environ.get("SIM_FARA", "25000"))     # straight for the approach point beyond this (units)        # the carrot at least twice the distance off the line (worse: 2.18 shots a minute against 2.68)
LOCK_M = float(os.environ.get("SIM_LOCKR", "2000"))      # the lock range (m) for a shot
# Mission 07's ground targets where the game has them (x, y, z in game units; 20 Oct 2026, the
# pilot's eval at 11:11): SAM sites, radar sites, AA guns
TARGETS = [(-33924, 79084, 2984), (-41200, -5800, 22905), (69909, -82258, 2522), (50634, -142857, 1908),
           (-42250, -6180, 22905), (68600, -82800, 2522), (-29744, 80673, 2655), (-32265, 82595, 2606),
           (146738, -136213, 2610), (143867, -145457, 2541), (151525, -144957, 2283), (48164, -137186, 2008),
           (55500, -139362, 883), (-41730, -5780, 22905), (8620, -21859, 15018), (9484, -28815, 14562),
           (5440, -27520, 14929)]


# ---- the world ---------------------------------------------------------------------------------

class Ground:
    def __init__(self, path=TERRAIN):
        xs, ys, pts = set(), set(), {}
        with open(path, encoding="utf-8") as f:
            next(f)
            for line in f:
                a = line.strip().split(",")
                if len(a) < 3 or a[2] == "":
                    continue
                x, y, z = float(a[0]), float(a[1]), float(a[2])
                pts[(x, y)] = z
                xs.add(x)
                ys.add(y)
        self.xs, self.ys = sorted(xs), sorted(ys)
        self.x0, self.y0 = self.xs[0], self.ys[0]
        self.step = self.xs[1] - self.xs[0]
        self.nx, self.ny = len(self.xs), len(self.ys)
        self.h = [0.0] * (self.nx * self.ny)
        for (x, y), z in pts.items():
            ix = int(round((x - self.x0) / self.step))
            iy = int(round((y - self.y0) / self.step))
            self.h[ix + iy * self.nx] = z
        self.outside = 100000.0     # off the map: high ground (stay over the surveyed part)

    def cell(self, ix, iy):
        if ix < 0 or iy < 0 or ix >= self.nx or iy >= self.ny:
            return self.outside
        return self.h[ix + iy * self.nx]

    def at(self, x, y):
        """The ground's height, bilinear between the four nearest points (the truth here)."""
        fx, fy = (x - self.x0) / self.step, (y - self.y0) / self.step
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        tx, ty = fx - ix, fy - iy
        a, b = self.cell(ix, iy), self.cell(ix + 1, iy)
        c, d = self.cell(ix, iy + 1), self.cell(ix + 1, iy + 1)
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty

    def top(self, x, y):
        """The highest of the four nearest points (what a careful look-ahead assumes)."""
        fx, fy = (x - self.x0) / self.step, (y - self.y0) / self.step
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        return max(self.cell(ix, iy), self.cell(ix + 1, iy), self.cell(ix, iy + 1), self.cell(ix + 1, iy + 1))

    def ray(self, p, d, rng, use_top=False):
        """How far along unit direction d from p (game units) the way is free, up to rng."""
        stepl = self.step * 0.5
        n = max(1, int(rng / stepl))
        f = self.top if use_top else self.at
        for i in range(1, n + 1):
            s = i * stepl
            q = (p[0] + d[0] * s, p[1] + d[1] * s, p[2] + d[2] * s)
            if q[2] < f(q[0], q[1]):
                return s - stepl * 0.5
        return rng


# ---- the plane ---------------------------------------------------------------------------------

def load_model(path=MODEL):
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    return m


class Plane:
    """The plane as measured: turn rate of the flight path by speed (the high-G median), roll
    rate, and speed change by climb angle for throttle, brake, high-G and nothing."""

    def __init__(self, m, share=1.0):
        self.turn = {}
        for band, d in m.get("turn_deg_s", {}).items():
            v = max((d.get("high_g") or {}).get("median") or 0, (d.get("pull") or {}).get("median") or 0) or None
            if v:
                self.turn[int(band)] = v
        self.roll = math.radians((m.get("roll_deg_s") or {}).get("p80", 120))
        self.dv = {}
        for what, d in m.get("dv_m_s2", {}).items():
            self.dv[what] = {int(g): v["median"] for g, v in d.items()}
        # by climb band (30 degrees) and speed band (200 km/h) together, where measured (the
        # brake holds the speed in a steep dive but takes 60 m/s off each second held level)
        self.dv2 = {}
        if os.environ.get("SIM_DV2", "1") == "1":
            for what, d in m.get("dv_by_kmh", {}).items():
                self.dv2[what] = {int(g): {int(k): v["median"] for k, v in row.items()} for g, row in d.items()}
        self.share = share

    def omega(self, s):
        """rad/s the flight path turns with a full pull at speed s (m/s): the measured medians
        (since 20 Oct 2026's 145 logs about 37-43 deg/s from 300 to 1,600 km/h: the turn rate
        hardly changes with speed, so the radius grows with it), 38 deg/s where none."""
        kmh = s * 3.6
        band = int(kmh // 100) * 100
        v = self.turn.get(band)
        if v is None or v < 25:
            v = 38.0
        return math.radians(min(v, 48.0)) * self.share

    def accel(self, what, gamma, s=None):
        t2 = self.dv2.get(what)
        if t2 and s is not None:
            g = max(-90, min(60, int(math.floor(math.degrees(gamma) / 30.0)) * 30))
            row = t2.get(g)
            if row:
                kb = int(s * 3.6 // 200) * 200
                if kb in row:
                    return row[kb]
                near = min(row, key=lambda k: abs(k - kb))
                if abs(near - kb) <= 400:
                    return row[near]
        tab = self.dv.get(what) or self.dv.get("none") or {0: 0.0}
        g = int(math.floor(math.degrees(gamma) / 15.0)) * 15
        if g in tab:
            return tab[g]
        keys = sorted(tab)
        nearest = min(keys, key=lambda k: abs(k - g))
        return tab[nearest]


def norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if l < 1e-12:
        return (1.0, 0.0, 0.0), 0.0
    return (v[0] / l, v[1] / l, v[2] / l), l


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def perp(v, u):
    """The part of v square to u, as a unit vector (or None)."""
    d = dot(v, u)
    w = (v[0] - d * u[0], v[1] - d * u[1], v[2] - d * u[2])
    n, l = norm(w)
    return n if l > 1e-6 else None


def rotate_toward(a, b, step):
    """Turn unit vector a toward unit vector b by at most 'step' rad (in their plane)."""
    c = max(-1.0, min(1.0, dot(a, b)))
    ang = math.acos(c)
    if ang <= step:
        return b
    w = perp(b, a)
    if w is None:
        return a
    cs, sn = math.cos(step), math.sin(step)
    return norm((a[0] * cs + w[0] * sn, a[1] * cs + w[1] * sn, a[2] * cs + w[2] * sn))[0]


class State:
    __slots__ = ("p", "u", "L", "s", "k")

    def __init__(self, p, u, L, s, k=0.0):
        self.p, self.u, self.L, self.s, self.k = p, u, L, s, k

    def copy(self):
        return State(self.p, self.u, self.L, self.s, self.k)


def roll_toward(L, Lc, u, step_):
    """Roll the lift L toward Lc about the flight path u by at most step_ rad (either way)."""
    th = math.atan2(dot(cross(L, Lc), u), max(-1.0, min(1.0, dot(L, Lc))))
    a = max(-step_, min(step_, th))
    ux = cross(u, L)
    L2 = (L[0] * math.cos(a) + ux[0] * math.sin(a), L[1] * math.cos(a) + ux[1] * math.sin(a), L[2] * math.cos(a) + ux[2] * math.sin(a))
    return perp(L2, u) or L


def step(plane, st, Lc, kc, mode, dt):
    """One step of the model: roll the lift toward Lc, build the pull toward kc (a push, k < 0,
    turns the other way at half the rate), turn the flight path toward the lift, change speed by
    the mode and the climb angle, move."""
    u, L = st.u, st.L
    if Lc is not None:
        L = roll_toward(L, Lc, u, plane.roll * dt)
    k = st.k + max(-3.0 * dt, min(3.0 * dt, kc - st.k))
    k = max(-0.5, min(1.0, k))
    w = plane.omega(st.s) * k * dt
    if abs(w) > 1e-6:
        cs, sn = math.cos(w), math.sin(w)
        u2 = norm((u[0] * cs + L[0] * sn, u[1] * cs + L[1] * sn, u[2] * cs + L[2] * sn))[0]
        L2 = norm((L[0] * cs - u[0] * sn, L[1] * cs - u[1] * sn, L[2] * cs - u[2] * sn))[0]
        u, L = u2, L2
    gamma = math.asin(max(-1.0, min(1.0, u[2])))
    s = st.s + plane.accel(mode, gamma, st.s) * dt
    if mode == "brake":
        s = max(s, 105.0)          # the brake is held only down to about 380 km/h
    s = max(70.0, min(560.0, s))
    sp = s * 10 * dt
    p = (st.p[0] + u[0] * sp, st.p[1] + u[1] * sp, st.p[2] + u[2] * sp)
    return State(p, u, L, s, k)


def chase(st, aim):
    """main.lua's way of following an aim, in short: roll the lift toward the aim, pull in
    proportion to the angle once the roll is close (bank-to-turn)."""
    Lc = perp(aim, st.u)
    ang = math.degrees(math.acos(max(-1.0, min(1.0, dot(st.u, aim)))))
    if Lc is None:
        return st.L, 0.0
    rollerr = math.degrees(math.acos(max(-1.0, min(1.0, dot(st.L, Lc)))))
    # a small correction the other way: push the nose, no roll (main.lua's small-corrections mode)
    if ang < 12 and rollerr > 120:
        return st.L, -min(0.5, ang / 8.0)
    k = min(1.0, ang / 8.0)
    if rollerr > 60:
        k = 0.0
    elif rollerr > 30:
        k = min(k, 0.6)
    return Lc, k


# ---- the pilot: ground attack runs (main.lua's groundRun, short) -------------------------------

def level_turn(d, u):
    """An aim more than 80 degrees off the nose as a level turn toward its side (90 degrees off,
    3 degrees up): pulling straight at a point behind lets its small up or down part pick the
    turn's plane, and a little down is a split-S (20 Oct 2026, the wargame: two crashes)."""
    if dot(d, u) > 0.17 or (STEEP and d[0] * d[0] + d[1] * d[1] < 0.35 * 0.35):
        return d                    # (ahead, or steeper than about 70 degrees: a dive or a pull up)
    uh = norm((u[0], u[1], 0.0))[0]
    side = (-uh[1], uh[0], 0.0)
    if side[0] * d[0] + side[1] * d[1] < 0:
        side = (-side[0], -side[1], 0.0)
    return norm((side[0], side[1], 0.05))[0]


class Pilot:
    def __init__(self, ground, targets, rng, plane=None):
        self.g, self.targets, self.rng, self.plane = ground, targets, rng, plane
        self.ti = rng.randrange(len(targets))
        self.run = "in"
        self.shots = 0
        self.lastShot = -99.0
        self.high, self.entered, self.geo, self.t = {}, {}, {}, 0.0
        self.alive = set(range(len(targets)))
        self.vis = {}              # target -> clear[az][el] (the lines of sight from it)
        self.line = None           # (target, az index, el index): the attack line flown
        self.lineAt = -99.0
        self.est = False           # on the line, heading in
        self.bad = {}              # (target, az index, el index) -> until (the line was blocked)
        self.blockedAt = None
        self.side = 1.0
        self.picked = False
        self.lineRs = {}

    def target(self):
        x, y, z = self.targets[self.ti]
        return (x, y, z + 30)

    # ---- attack lines (20 Oct 2026): where a target can be seen from, and the way onto it ----

    AZN = 16
    ELS = (10, 20, 30, 40, 50, 60, 70, 80)
    DG = float(os.environ.get("SIM_DG", "24000"))      # the gate (the dive from here), along the line
    DA = float(os.environ.get("SIM_DA", "32000"))      # the approach point
    CARROT = float(os.environ.get("SIM_CARROT", "8000"))
    STRICT = os.environ.get("SIM_STRICT", "1") == "1"

    def visibility(self, ti):
        """From the target (3 m up, from 40 m out: what the pilot's line-of-sight check sees), rays
        in 16 directions at 10-80 degrees, 3 km long: clear or not."""
        v = self.vis.get(ti)
        if v is not None:
            return v
        x, y, z = self.targets[ti]
        T = (x, y, z + 30)
        clear = []
        for i in range(self.AZN):
            az = i * 2 * math.pi / self.AZN
            row = []
            for e in self.ELS:
                er = math.radians(e)
                d = (math.cos(az) * math.cos(er), math.sin(az) * math.cos(er), math.sin(er))
                p0 = (T[0] + d[0] * 400, T[1] + d[1] * 400, T[2] + d[2] * 400)
                row.append(self.g.ray(p0, d, 29600) >= 29600 - 1)
            clear.append(row)
        self.vis[ti] = clear
        return clear

    def line_dir(self, i, j):
        if i < 0:
            return self.lineRs.get(self.ti, (0.0, 0.0, 1.0))
        az, er = i * 2 * math.pi / self.AZN, math.radians(self.ELS[j])
        return (math.cos(az) * math.cos(er), math.sin(az) * math.cos(er), math.sin(er))

    def usable(self, clear, i, j):
        """A line with room around it: clear, and 10 degrees lower clear too (a plane a little below
        it still sees), and a neighbouring side clear at that angle."""
        n = self.AZN
        if not clear[i][j]:
            return False
        if self.STRICT and j > 0 and not clear[i][j - 1]:
            return False
        return clear[(i + 1) % n][j] or clear[(i - 1) % n][j]

    def line_cost(self, st, ti, i, j):
        """Seconds until the plane is on line (i, j) at the gate, heading in: to the approach point
        (the horizontal way or the climb, whichever is longer, at the plane's speed), the turns
        (the plane's measured turn rate), and the run down the line to the shot."""
        if i < 0:
            dr = self.direct(st, ti)
            return dr[1] if dr else 1e9
        x, y, z = self.targets[ti]
        T = (x, y, z + 30)
        r = self.line_dir(i, j)
        A = (T[0] + r[0] * self.DA, T[1] + r[1] * self.DA, T[2] + r[2] * self.DA)
        v = max(st.s, 120.0) * 10
        dx, dy, dz = A[0] - st.p[0], A[1] - st.p[1], A[2] - st.p[2]
        hA = math.hypot(dx, dy)
        tA = max(hA / v, dz / (v * 0.42))
        om = (self.plane.omega(st.s) * 0.85) if self.plane else math.radians(35)
        uh = norm((st.u[0], st.u[1], 0.0))[0]
        toA = norm((dx, dy, 0.0))[0] if hA > 1 else uh
        rin = norm((-r[0], -r[1], 0.0))[0]
        turn1 = math.acos(max(-1.0, min(1.0, dot(uh, toA))))
        turn2 = math.acos(max(-1.0, min(1.0, dot(toA, rin))))
        return tA + (turn1 + turn2) / om + (self.DA - 20000) / v

    def direct(self, st, ti):
        """The target in sight now, 700-2,600 m away and within 40 degrees of the nose: the line
        from it to the plane (the next target of a cluster after a kill: no going round again)."""
        x, y, z = self.targets[ti]
        T = (x, y, z + 30)
        d, dist = norm((T[0] - st.p[0], T[1] - st.p[1], T[2] - st.p[2]))
        if not (7000 < dist < 26000) or dot(d, st.u) < math.cos(math.radians(40)):
            return None
        if self.g.ray(st.p, d, dist - 400) < dist - 400 - 1:
            return None
        return (-d[0], -d[1], -d[2]), dist / (max(st.s, 120.0) * 10)

    def best_line(self, st, ti):
        clear = self.visibility(ti)
        dr = self.direct(st, ti)
        if dr:
            self.lineRs[ti] = dr[0]
            return (ti, -1, 0), dr[1]
        best, bc = None, 1e18
        for i in range(self.AZN):
            for j in range(len(self.ELS)):
                if self.bad.get((ti, i, j), -1) > self.t or not self.usable(clear, i, j):
                    continue
                c = self.line_cost(st, ti, i, j)
                if c < bc:
                    best, bc = (ti, i, j), c
        return best, bc

    def pick(self, st):
        """The next target: the one whose attack line the plane is on soonest (PICK=geo), the
        nearest (near), or any (random)."""
        alive = sorted(self.alive) or list(range(len(self.targets)))
        if PICK == "random":
            self.ti = self.rng.choice(alive)
        elif PICK == "near":
            self.ti = min(alive, key=lambda k: math.hypot(self.targets[k][0] - st.p[0], self.targets[k][1] - st.p[1]))
        else:
            self.ti = min(alive, key=lambda k: self.best_line(st, k)[1])
        self.line, self.est, self.run, self.blockedAt = None, False, "in", None

    def shot_done(self, st):
        self.alive.discard(self.ti)
        if not self.alive:
            self.alive = set(range(len(self.targets)))
        self.pick(st)

    def wanted_line(self, st, t):
        """Fly the attack line. Approach: onto it from outside (a carrot on the line 800 m nearer
        the target) and down it to the shot. Reposition (inside the gate and not on the line, or
        after a pass): out along it on a track two turn radii to the side, past the approach
        point, then the turn in lands on the line."""
        T = self.target()
        if self.line is None or self.line[0] != self.ti or (t - self.lineAt > 1.0 and not self.est):
            cand, cc = self.best_line(st, self.ti)
            if cand is None:
                self.alive.discard(self.ti)
                self.pick(st)
                return st.u, "in"
            # (held unless another is sooner by 4 s, and by half the time it has been held more, up
            # to 12 s: decisiveness; near the target steeper lines keep looking a little cheaper)
            if self.line and self.line[0] == self.ti and cand != self.line and not self.bad.get(self.line, -1) > t:
                keep = min(12.0, 4.0 + 0.5 * (t - getattr(self, "lineSince", t)))
                if self.line_cost(st, *self.line) <= cc + keep:
                    cand = self.line
            if cand != self.line:
                self.lineSince = t
                self.est = cand[1] < 0         # (a direct line: on it already)
                if self.est:
                    self.run = "in"
            self.line, self.lineAt = cand, t
        _, i, j = self.line
        r = self.line_dir(i, j)
        P = st.p
        w = (P[0] - T[0], P[1] - T[1], P[2] - T[2])
        s = dot(w, r)
        C = (T[0] + r[0] * s, T[1] + r[1] * s, T[2] + r[2] * s)
        e = math.sqrt((P[0] - C[0]) ** 2 + (P[1] - C[1]) ** 2 + (P[2] - C[2]) ** 2)
        vin = -dot(st.u, r)
        dm = math.sqrt(dot(w, w)) / 10
        agl = (P[2] - self.g.at(P[0], P[1])) / 10
        self.kmh = 1150 if dm > 4500 else (850 if dm > 2600 else 700)
        # (a steep line: slow before it, the brake only holds the speed in a 30-60 degree dive)
        if SPEEDPLAN and r[2] > 0.45 and dm <= 4500:
            self.kmh = 600
        if self.run == "in" and (dm < 700 or (agl < 150 and P[2] < T[2] + 3000)):
            self.run, self.est = "out", False
        if not self.est and self.run == "in" and s > self.DG * 0.8 and e < max(3000.0, 0.12 * s) and vin > math.cos(math.radians(35)):
            self.est = True
        if self.est and (e > max(6000.0, 0.25 * s) or vin < 0.3):
            self.est = False
        if self.run == "in" and not self.est and s < self.DG:
            self.run = "out"
        om0 = self.plane.omega(st.s) * 0.85 if self.plane else math.radians(35)
        R0 = max(st.s, 150.0) * 10 / om0
        # (SIM_SHORTOUT=1: back in once past the gate by a turn radius, as a skilled player turns
        # back as soon as the turn can still end on the line before the lock; else past the
        # approach point)
        outAt = (self.DG + R0) if SHORTOUT else (self.DA + 3000)
        if self.run == "out" and s > outAt:
            self.run = "in"
        self.dbg = f"s {s / 10:5.0f} e {e / 10:4.0f} vin {vin:+.2f} dm {dm:5.0f}"
        # blocked on the line inside the gate for a second: that line is no good (30 s), another
        if self.est and s < self.DG:
            d, dist = norm((T[0] - P[0], T[1] - P[1], T[2] - P[2]))
            free = self.g.ray((P[0] + d[0] * 300, P[1] + d[1] * 300, P[2] + d[2] * 300), d, dist - 700)
            if free < dist - 700 - 1500:
                self.blockedAt = self.blockedAt if self.blockedAt is not None else t
                if t - self.blockedAt > 1.0:
                    self.bad[self.line] = t + 30
                    self.line, self.est, self.blockedAt = None, False, None
                    self.run = "out"
                    return st.u, "out"
            else:
                self.blockedAt = None
        if self.run == "out":
            # out along the line, two turn radii to the plane's side, climbing to the line's height
            om = self.plane.omega(st.s) * 0.85 if self.plane else math.radians(35)
            R = max(st.s, 150.0) * 10 / om
            n = norm((-r[1], r[0], 0.0))[0]
            if s < self.DA:
                self.side = 1.0 if dot(w, n) >= 0 else -1.0
            far = (self.DG + R0 + 5000) if SHORTOUT else (self.DA + 8000)
            Q = (T[0] + r[0] * far + n[0] * 2 * R * self.side, T[1] + r[1] * far + n[1] * 2 * R * self.side, T[2] + r[2] * far)
            dx, dy, dz = Q[0] - P[0], Q[1] - P[1], Q[2] - P[2]
            hq = max(math.hypot(dx, dy), 1)
            return level_turn(norm((dx / hq, dy / hq, max(-0.3, min(0.5, dz / hq))))[0], st.u), "out"
        A = (T[0] + r[0] * self.DA, T[1] + r[1] * self.DA, T[2] + r[2] * self.DA)
        if math.hypot(A[0] - P[0], A[1] - P[1]) > FAR_A:
            dx, dy, dz = A[0] - P[0], A[1] - P[1], A[2] - P[2]
            hq = max(math.hypot(dx, dy), 1)
            return level_turn(norm((dx / hq, dy / hq, max(-0.3, min(0.5, dz / hq))))[0], st.u), "in"
        sc = max(s - max(self.CARROT, (2 * e) if WIDE else 0.0), 0.0)
        Cc = (T[0] + r[0] * sc, T[1] + r[1] * sc, T[2] + r[2] * sc)
        d = norm((Cc[0] - P[0], Cc[1] - P[1], Cc[2] - P[2]))[0]
        # (climbing no steeper than about 27 degrees on the way; and while the line is more than
        # 70 degrees off the nose, the turn onto it level, within -8..+17 degrees: pulling toward a
        # point behind and below is a split-S, and one at 380 km/h ended in a hillside)
        hq = math.hypot(d[0], d[1])
        lim = (-0.15, 0.3) if dot(d, st.u) < 0.34 else (-9.0, 0.5)
        if hq > 1e-6 and not (lim[0] <= d[2] / hq <= lim[1]):
            d = norm((d[0] / hq, d[1] / hq, max(lim[0], min(lim[1], d[2] / hq))))[0]
        return level_turn(d, st.u), "in"

    def geometry(self, T, st):
        """main.lua's attackGeometry: from the target, rays in eight directions (the plane's side
        first) at 20-80 degrees, 3 km long; the lowest clear angle and its side."""
        key = self.ti
        g = self.geo.get(key)
        if g and g[2] > self.t - 15:
            return g
        az0 = math.atan2(st.p[1] - T[1], st.p[0] - T[0])
        best = None
        for i in range(8):
            az = az0 + i * math.pi / 4
            for e in (20, 30, 40, 50, 60, 70, 80):
                er = math.radians(e)
                d = (math.cos(az) * math.cos(er), math.sin(az) * math.cos(er), math.sin(er))
                p0 = (T[0] + d[0] * 300, T[1] + d[1] * 300, T[2] + 270 + d[2] * 300)
                if self.g.ray(p0, d, 27000) >= 27000 - 1:
                    cost = e + (0 if i == 0 else 3)
                    if best is None or cost < best[3]:
                        best = (az, e, self.t, cost)
                    break
        g = best or (None, None, self.t, None)
        self.geo[key] = g
        return g

    def wanted(self, st, t):
        self.t = t
        if not self.picked:
            self.picked = True
            if PICK != "random":
                self.pick(st)
        if LINE:
            return self.wanted_line(st, t)
        T = self.target()
        dx, dy, dz = T[0] - st.p[0], T[1] - st.p[1], T[2] - st.p[2]
        hd = math.hypot(dx, dy)
        dm = math.sqrt(hd * hd + dz * dz) / 10
        h = (dx / max(hd, 1), dy / max(hd, 1))
        agl = (st.p[2] - self.g.at(st.p[0], st.p[1])) / 10
        high = GEOMETRY and self.high.get(self.ti)
        outH, inH, minAbove, maxDive = (1600, 1600, 500, -0.8) if high else (700, 550, 250, -0.47)
        geoAim = None
        if high:
            az, el, _, _ = self.geometry(T, st)
            if el is None:
                self.pick(st)      # seen from nowhere: another
                return st.u, "in"
            elr = math.radians(min(el + 5, 80))
            maxDive = -math.tan(elr)
            if not self.entered.get(self.ti):
                ce = math.cos(math.radians(el))
                E = (T[0] + math.cos(az) * 24000 * ce, T[1] + math.sin(az) * 24000 * ce, T[2] + 270 + math.sin(math.radians(el)) * 24000)
                ex, ey, ez = E[0] - st.p[0], E[1] - st.p[1], E[2] - st.p[2]
                if math.sqrt(ex * ex + ey * ey + ez * ez) < 6000:
                    self.entered[self.ti] = True
                else:
                    he = max(math.hypot(ex, ey), 1)
                    geoAim = norm((ex / he, ey / he, max(-0.3, min(0.5, ez / he))))[0]
        if self.run == "in" and (dm < 700 or agl < minAbove):
            self.run = "out"
        # (main.lua: terrain in the line inside 2.6 km: the next run from above, then another target)
        if GEOMETRY and self.run == "in" and dm < 2600 and geoAim is None:
            d, dist = norm((dx, dy, dz))
            free = self.g.ray((st.p[0] + d[0] * 300, st.p[1] + d[1] * 300, st.p[2] + d[2] * 300), d, dist - 450)
            if free < dist - 450 - 1500:
                self.run = "out"
                if self.high.get(self.ti):
                    self.pick(st)
                else:
                    self.high[self.ti] = True
        if self.run == "out" and dm > 2600:
            self.run = "in"
        # the speed main.lua's attack asks for: fast while far, slower for the run's turns
        self.kmh = 1150 if dm > 3000 else (850 if dm > 1200 else 650)
        if self.run == "out":
            self.entered.pop(self.ti, None)
            return norm((-h[0], -h[1], max(-0.3, min(0.4, (outH - agl) / 1500))))[0], "out"
        if geoAim is not None:
            return geoAim, "in"
        if hd / 10 > 2600:
            return norm((h[0], h[1], max(-0.3, min(0.4, (inH - agl) / 1500))))[0], "in"
        return norm((h[0], h[1], max(dz / max(hd, 1), maxDive)))[0], "in"

    def speed_mode(self, st):
        kmh = st.s * 3.6
        if kmh < self.kmh - 25:
            return "throttle"
        if kmh > self.kmh + 40:
            return "brake"
        return "none"

    def try_shot(self, st, t):
        if t - self.lastShot < 2.0:
            return False
        T = self.target()
        d, dist = norm((T[0] - st.p[0], T[1] - st.p[1], T[2] - st.p[2]))
        dm = dist / 10
        # (a lock takes the target within 25 degrees of the nose, 500-2,000 m, in sight, for a
        # second; the pilot holds fire with terrain more than 40 m short of it)
        if 500 <= dm <= LOCK_M and dot(d, st.u) > math.cos(math.radians(25)) and self.g.ray(st.p, d, dist - 400) >= dist - 400 - 1:
            if getattr(self, "lockSince", None) is None:
                self.lockSince = t
            if t - self.lockSince >= 1.0:
                self.lockSince = None
                self.shots += 1
                self.lastShot = t
                self.shot_done(st)
                return True
        else:
            self.lockSince = None
        return False


# ---- safety layers -----------------------------------------------------------------------------

class Vision:
    """Today's fight safety net in main.lua (vision.lua's V.choose with opts.wide, short)."""
    YAWS = [-40, -30, -22, -15, -10, -6, -3, 0, 3, 6, 10, 15, 22, 30, 40]
    PITCHES = [-30, -20, -13, -8, -4, 0, 4, 8, 13, 20, 30]

    def __init__(self, g):
        self.g = g
        self.blockedAt = -99.0

    def filter(self, st, aim, mode, t):
        sp = st.s * 10
        rng = max(6000, min(40000, sp * 4.5))
        need = sp * 3.0
        wf = self.g.ray(st.p, aim, rng)
        vf = self.g.ray(st.p, st.u, rng)
        if wf >= need and vf >= need * 0.8:
            if t - self.blockedAt < 20 and st.s * 3.6 > 550:
                mode = "brake"
            return aim, mode
        self.blockedAt = t
        centre = norm(tuple(st.u[i] * 0.6 + aim[i] * 0.4 for i in range(3)))[0]
        r = perp((0, 0, 1), centre)
        side = norm(cross(centre, (0, 0, 1)))[0]
        up = norm(cross(side, centre))[0]
        best, bestc = aim, 1e18
        for yd in self.YAWS:
            for pd in self.PITCHES:
                y, pc = math.radians(yd), math.radians(pd)
                d = norm(tuple(centre[i] * math.cos(y) * math.cos(pc) + side[i] * math.sin(y) * math.cos(pc) + up[i] * math.sin(pc) for i in range(3)))[0]
                fd = self.g.ray(st.p, d, rng)
                off = math.degrees(math.acos(max(-1, min(1, dot(d, aim)))))
                turn = math.degrees(math.acos(max(-1, min(1, dot(d, st.u)))))
                c = off + turn * 0.3 - math.degrees(math.asin(max(-1, min(1, d[2])))) * 0.5
                if fd < need:
                    c += 400 * (1 - fd / need) + 100
                if c < bestc:
                    best, bestc = d, c
        if st.s * 3.6 > 550:
            mode = "brake"
        return best, mode


class Planner:
    """The manoeuvre planner (maneuver.lua's design): candidate manoeuvres flown ahead in the
    plane's measured model, checked against the ground; the wanted way if it stays clear."""

    def __init__(self, g, plane, P=None):
        self.g, self.plane = g, plane
        self.P = dict(horizon=5.0, dt=0.25, margin=80.0, share=0.85, keep=1.6, lead=1.0, stick=4.0, hold=1.5, comfort=25.0, sideHold=4.0, sideCost=30.0, escapeAfter=1.0)
        if P:
            self.P.update(P)
        self.last = None
        self.lastAt = -99.0
        self.choice = None
        self.evals = 0
        self.hold = None            # (how, t): an override manoeuvre held while it stays clear
        self.side = None            # (sign, t): the side of the last turn away

    def roll_out(self, st, how):
        """Fly a manoeuvre ahead: how = ('follow', aim) or ('fixed', phi, k); with a speed mode.
        Returns the states every dt and the first time below the margin (or None)."""
        P = self.P
        pl = self.plane
        s = st.copy()
        pts = []
        bad = None
        minc = 1e9
        close = 0
        n = int(P["horizon"] / P["dt"])
        for i in range(n):
            if how[0] == "follow":
                Lc, k = chase(s, how[1])
            else:
                phi, k = how[1], how[2]
                # the lift pointed phi around the flight path from "up" (0 = pull up, pi = push
                # over by rolling inverted), held
                up = perp((0, 0, 1), s.u) or s.L
                side = norm(cross(s.u, up))[0]
                Lc = norm(tuple(up[j] * math.cos(phi) + side[j] * math.sin(phi) for j in range(3)))[0]
            s2 = step(pl, s, Lc, k, how[-1], P["dt"])
            # clear of the ground along the way (the highest nearby point, and the middle of the step)
            for q in (s2.p, tuple((s.p[j] + s2.p[j]) * 0.5 for j in range(3))):
                c = (q[2] - self.g.top(q[0], q[1])) / 10
                minc = min(minc, c)
                if c < P["margin"] and bad is None:
                    bad = (i + 1) * P["dt"]
            if bad is None and i % 2 == 1 and (s2.p[2] - self.g.top(s2.p[0], s2.p[1])) / 10 < P["margin"] * 2:
                close += 1
            pts.append(s2)
            s = s2
            if bad is not None:
                break
        self.close = close
        # and it must end where a pull-out is still possible (the safe end of a look-ahead: a
        # steep dive that is clear for 5 s can still be past saving; 20 Oct 2026, the wargame's
        # crashes were spirals over a target that looked clear to the end of every plan)
        if bad is None and pts:
            e = pts[-1]
            if e.u[2] < 0:
                cg = math.sqrt(max(0.0, 1 - e.u[2] * e.u[2]))
                R = e.s / max(pl.omega(e.s) * P["share"], 0.05)
                need = R * (1 - cg) + e.s * 0.5 * (-e.u[2]) + P["margin"]
                c = (e.p[2] - self.g.top(e.p[0], e.p[1])) / 10
                if c < need:
                    bad = P["horizon"]
        return pts, bad, minc

    def filter(self, st, aim, mode, t):
        P = self.P
        self.evals += 1
        follow, bad, minc = self.roll_out(st, ("follow", aim, mode))
        if bad is None and minc >= P["margin"] * P["keep"]:
            self.last, self.hold = None, None
            return aim, mode
        # diving at something: kept while, after one more second of it, a hard pull-up is clear
        if aim[2] < -0.3 and P["escapeAfter"] > 0:
            saveH = P["horizon"]
            P["horizon"] = P["escapeAfter"]
            f1, b1, _ = self.roll_out(st, ("follow", aim, mode))
            P["horizon"] = saveH
            if b1 is None and f1:
                s1 = f1[-1]
                for pd in (0, 30, -30):
                    _, b2, _ = self.roll_out(s1, ("fixed", math.radians(pd), 1.0, "brake"))
                    if b2 is None:
                        self.hold = None
                        return aim, mode
        # a manoeuvre chosen in the last moment and still clear is kept (decisiveness)
        if self.hold and t - self.hold[1] < P["hold"]:
            how = self.hold[0]
            if how[0] == "follow":
                how = ("follow", aim, "brake")
            pts, b, _ = self.roll_out(st, how)
            if b is None and pts:
                if how[0] == "follow":
                    return aim, "brake"
                lead = pts[min(len(pts) - 1, int(P["lead"] / P["dt"]))]
                return norm((lead.p[0] - st.p[0], lead.p[1] - st.p[1], lead.p[2] - st.p[2]))[0], how[-1]
        # the wanted way runs into the ground (or close): the candidates
        cands = [("follow", aim, "brake")]
        for phi_deg in (0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180):
            for k in (0.6, 1.0):
                for sm in ("none", "brake"):
                    cands.append(("fixed", math.radians(phi_deg), k, sm))
        cands.append(("fixed", 0.0, 0.0, "none"))
        best, bestc, bestpts = None, 1e18, None
        for how in cands:
            pts, b, mc = self.roll_out(st, how)
            if b is not None:
                c = 1e6 - b * 1000.0           # the later the trouble the better
            else:
                end = pts[-1]
                lead = pts[min(len(pts) - 1, int(P["lead"] / P["dt"]))]
                c = math.degrees(math.acos(max(-1, min(1, dot(lead.u, aim))))) * 1.0
                c += math.degrees(math.acos(max(-1, min(1, dot(end.u, aim))))) * 0.5
                c += self.close * P["comfort"]
                if end.s * 3.6 < 330:
                    c += (330 - end.s * 3.6) * 0.3
            key = (how[0], how[1] if how[0] == "fixed" else 0, how[2] if how[0] == "fixed" else 0, how[-1])
            if self.last == key and t - self.lastAt < 1.0:
                c -= P["stick"]
            if self.side and t - self.side[1] < P["sideHold"] and how[0] == "fixed" and how[2] > 0:
                sd = 1 if how[1] > 0.1 else (-1 if how[1] < -0.1 else 0)
                if sd != 0 and sd != self.side[0]:
                    c += P["sideCost"]
            if c < bestc:
                best, bestc, bestpts = how, c, pts
        self.last = (best[0], best[1] if best[0] == "fixed" else 0, best[2] if best[0] == "fixed" else 0, best[-1])
        self.lastAt = t
        self.choice = best
        self.hold = (best, t) if bestc < 1e5 else None
        if bestc < 1e5 and best[0] == "fixed" and best[2] > 0:
            sd = 1 if best[1] > 0.1 else (-1 if best[1] < -0.1 else 0)
            if sd != 0:
                self.side = (sd, t)
        if best[0] == "follow":
            return aim, best[-1]
        # where the manoeuvre has the plane in 'lead' seconds, as the aim (tried on 20 Oct 2026:
        # the manoeuvre's own roll and pull as an aim tilted toward its lift; 22.5% of the
        # wargame's runs crashed against 4% this way)
        lead = bestpts[min(len(bestpts) - 1, int(P["lead"] / P["dt"]))]
        d = norm((lead.p[0] - st.p[0], lead.p[1] - st.p[1], lead.p[2] - st.p[2]))[0]
        return d, best[-1]


# ---- one scenario --------------------------------------------------------------------------------

def scenario(g, seed):
    rng = random.Random(seed)
    targets = [tuple(tg) for tg in TARGETS]
    tx, ty, _ = targets[rng.randrange(len(targets))]
    for _ in range(100):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(5000, 12000) * 10
        x, y = tx + math.cos(a) * r, ty + math.sin(a) * r
        gz = g.at(x, y)
        if gz >= g.outside - 1:
            continue
        z = gz + rng.uniform(300, 1500) * 10
        hd = rng.uniform(0, 2 * math.pi)
        u = (math.cos(hd), math.sin(hd), 0.0)
        s = rng.uniform(450, 850) / 3.6
        # (a start with the first 3 s of flight clear: not born about to hit a hill)
        if g.ray((x, y, z), u, s * 10 * 3.0) >= s * 10 * 3.0 - 1:
            break
    return {"seed": seed, "p": (x, y, z), "u": u, "s": s, "targets": targets}


def run(g, plane, sc, layer, duration=120.0, trace=False, P=None):
    rng = random.Random(sc["seed"] * 7 + 1)
    st = State(sc["p"], sc["u"], (0.0, 0.0, 1.0), sc["s"])
    pilot = Pilot(g, sc["targets"], rng, plane)
    safety = None
    if layer == "vision":
        safety = Vision(g)
    elif layer == "planner":
        safety = Planner(g, plane, P)
    dt, t = 0.1, 0.0
    aim, mode = st.u, "none"
    nextDecision = 0.0
    log = []
    while t < duration:
        if t >= nextDecision:
            want, how = pilot.wanted(st, t)
            mode = pilot.speed_mode(st)
            aim = want
            if safety:
                aim, mode = safety.filter(st, want, mode, t)
            nextDecision = t + (0.05 if layer == "vision" else 0.25)
        elif not safety or getattr(safety, "last", None) is None:
            mode = pilot.speed_mode(st) if not (layer == "vision" and mode == "brake") else mode
        Lc, k = chase(st, aim)
        st = step(plane, st, Lc, k, mode, dt)
        t += dt
        pilot.try_shot(st, t)
        ground = g.at(st.p[0], st.p[1])
        if st.p[2] < ground:
            return {"crash": True, "t": t, "shots": pilot.shots, "log": log}
        if trace and int(t * 10) % 10 == 0:
            log.append(f"{t:5.1f} pos ({st.p[0] / 10000:6.2f},{st.p[1] / 10000:6.2f}) km alt {st.p[2] / 10:5.0f} agl {(st.p[2] - ground) / 10:5.0f} "
                       f"{st.s * 3.6:4.0f} km/h climb {math.degrees(math.asin(max(-1, min(1, st.u[2])))):4.0f} mode {mode} run {pilot.run} shots {pilot.shots}"
                       + (f" tgt {pilot.ti} line {pilot.line[1:] if pilot.line else None} est {pilot.est} {getattr(pilot, 'dbg', '')}" if LINE else ""))
    return {"crash": False, "t": t, "shots": pilot.shots, "log": log}


# ---- experiments -----------------------------------------------------------------------------------

_G, _PL = None, None


def _init():
    global _G, _PL
    if _G is None:
        _G = Ground()
        _PL = Plane(load_model())


def _one(args):
    seed, layer, duration, P = args
    _init()
    sc = scenario(_G, seed)
    r = run(_G, _PL, sc, layer, duration, P=P)
    r.pop("log", None)
    return seed, layer, r


def compare(n=300, layers=("none", "vision", "planner"), duration=120.0, P=None, workers=int(os.environ.get("SIM_WORKERS", "16"))):
    jobs = [(s, layer, duration, P) for s in range(n) for layer in layers]
    out = {layer: [] for layer in layers}
    with ProcessPoolExecutor(max_workers=workers) as ex:
        for seed, layer, r in ex.map(_one, jobs, chunksize=4):
            r["seed"] = seed
            out[layer].append(r)
    res = {}
    for layer, rs in out.items():
        crashes = sum(1 for r in rs if r["crash"])
        mins = sum(r["t"] for r in rs) / 60
        shots = sum(r["shots"] for r in rs)
        res[layer] = {"crash_share": crashes / len(rs), "crashes_per_hour": crashes / mins * 60, "shots_per_min": shots / mins, "n": len(rs),
                      "crashed": sorted((r["seed"], round(r["t"], 1)) for r in rs if r["crash"])}
    return res


def show(res, list_crashes=False):
    for layer, r in res.items():
        print(f"  {layer:8} crashed in {r['crash_share'] * 100:5.1f}% of {r['n']} runs ({r['crashes_per_hour']:5.1f} an hour of flying), "
              f"{r['shots_per_min']:.2f} shots a minute")
        if list_crashes and r["crashed"]:
            print("           crashed (seed, s):", r["crashed"][:30])


def main(argv):
    args = argv[1:]
    if not args:
        print(__doc__)
        return 1
    if args[0] == "compare":
        n = int(args[args.index("--n") + 1]) if "--n" in args else 300
        layers = tuple(args[args.index("--layers") + 1].split(",")) if "--layers" in args else ("none", "vision", "planner")
        t0 = time.time()
        dur = float(args[args.index("--dur") + 1]) if "--dur" in args else 120.0
        show(compare(n, layers=layers, duration=dur), list_crashes="--list" in args)
        print(f"({time.time() - t0:.0f} s)")
    elif args[0] == "one":
        seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 1
        layer = args[args.index("--layer") + 1] if "--layer" in args else "planner"
        _init()
        r = run(_G, _PL, scenario(_G, seed), layer, trace="--trace" in args)
        for line in r["log"]:
            print(line)
        print({k: v for k, v in r.items() if k != "log"})
    elif args[0] == "sweep":
        name, vals = args[1], [float(v) for v in args[2:]]
        for v in vals:
            print(f"{name} = {v}:")
            show(compare(int(os.environ.get("SIM_N", "200")), layers=("planner",), duration=float(os.environ.get("SIM_DUR", "120")), P={name: v}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
