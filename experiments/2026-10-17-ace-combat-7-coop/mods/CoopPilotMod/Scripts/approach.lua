-- approach.lua: attack lines, the way onto a ground target a pilot plans (CoopPilotMod, 20 Oct
-- 2026; the owner: "pathfinding, maneuvering, innate knowledge of its own aircraft's
-- capabilities and how to use them in maneuvering, and decision making").
--
-- Where a ground target can be seen from: rays out of it (3 m above it, from 40 m out: what the
-- pilot's line-of-sight check before a shot sees) in 16 directions at 10-80 degrees, 3 km long,
-- traced with the engine's own line traces; the result is the target's visibility map. A line
-- is usable when it is clear, 10 degrees lower is clear too (a plane a little below it still
-- sees the target) and a neighbouring side is clear at its angle. Of the usable lines the one
-- the plane is on soonest wins: the way to its approach point 3 km out (the horizontal way or
-- the climb, whichever takes longer, at the plane's speed), the two turns at the plane's
-- measured turn rate, and the run down to the shot. A choice is held unless another is 4 s
-- sooner (decisiveness).
--
-- Flying it: from outside, a point on the line 800 m nearer the target is the aim, so the plane
-- closes on the line and then follows it down (the line falls toward the target at its angle:
-- that is the dive). From inside the gate (2.2 km) without being on the line, or after a pass
-- (closer than 700 m), it repositions: out along the line on a track two turn radii to one
-- side, until a turn radius past the gate, so the turn back in ends on the line. A line that turns out
-- blocked from the plane inside the gate for a second is dropped for 30 s and another chosen.
-- A target already in sight ahead (700-2,600 m, within 40 degrees of the nose) is attacked on
-- the line the plane is on: the next target of a cluster after a kill needs no going round.
--
-- Wargamed first in tools\maneuver-sim.py over Mission 07's surveyed ground with the Typhoon's
-- measured model (SIM_LINE=1): ten-minute flights at the mission's 17 ground targets, 3.1
-- shots a minute against 1.1 for the entry-point runs it replaces, no crashes in 160 flights;
-- with the speed-aware model and a 1.8 km lock range (SIM_SHORTOUT=1) 2.76 a minute and one
-- crash in 192 flights.
-- Nothing here is level-specific: the ground comes from traces, the turn rate from the logs.
-- Units: game units (10 cm) for positions, m/s for speeds, radians inside.

return function(env)
    local event, now = env.event, env.now
    local M = {}

    M.P = {
        azn = 16,                          -- directions around the target
        els = { 10, 20, 30, 40, 50, 60, 70, 80 },   -- angles up from it (degrees)
        range = 30000,                     -- the rays' length (3 km)
        gate = 22000,                      -- along the line: on it by here, then down it
        approach = 30000,                  -- the approach point
        carrot = 8000,                     -- the aim: this much nearer the target on the line
        keep = 4.0,                        -- s another line must be sooner to replace the one held
        keepGrow = 0.5,                    -- ...plus this much for each second it has been held
        keepMax = 12.0,                    -- ...up to this
        badFor = 30,                       -- s a line found blocked is left out
        blockShort = 150,                  -- m short of the target that counts as blocked
        blockFor = 1.0,                    -- s blocked before the line is dropped
        mapAge = 60,                       -- s a visibility map is kept (or until the target moves 50 m)
        share = 0.85,                      -- share of the measured turn rate counted on
        climb = 0.42,                      -- the climb's sine counted on the way (about 25 degrees)
    }
    M.ctx = {
        trace = nil,                       -- function(x1, y1, z1, x2, y2, z2) -> hit
        omega = function() return math.rad(38) end,
    }
    M.maps = {}        -- key -> { clear = { [i] = { [j] = bool } }, at, x, y, z }
    M.st = {}          -- key -> { line, lineAt, est, run, bad, blockedAt, side, r }
    M.stats = { maps = 0, traces = 0, lines = 0, blocked = 0, direct = 0 }

    local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
    local function unit(v)
        local l = len(v)
        if l < 1e-9 then return { 1, 0, 0 }, 0 end
        return { v[1] / l, v[2] / l, v[3] / l }, l
    end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function clamp(x, a, b) return math.max(a, math.min(b, x)) end

    -- An aim more than 80 degrees off the nose as a level turn toward its side (90 degrees off,
    -- 3 degrees up): pulling straight at a point behind lets its small up or down part pick the
    -- turn's plane, and a little down is a split-S (the wargame: two crashes into hillsides)
    -- (not for an aim steeper than about 70 degrees, below or above: that is a dive or a pull up
    -- onto it, and a level turn never brings it ahead; 20 Oct 2026, Mission 07: a line point
    -- almost straight below kept the plane circling over it for 160 s, climbing to 5 km)
    local function levelTurn(d, u)
        if dot(d, u) > 0.17 or d[1] * d[1] + d[2] * d[2] < 0.35 * 0.35 then return d end
        local uh = unit({ u[1], u[2], 0 })
        local side = { -uh[2], uh[1], 0 }
        if side[1] * d[1] + side[2] * d[2] < 0 then side = { -side[1], -side[2], 0 } end
        return (unit({ side[1], side[2], 0.05 }))
    end

    local function hits(a, b)
        M.stats.traces = M.stats.traces + 1
        local ok, hit = pcall(M.ctx.trace, a[1], a[2], a[3], b[1], b[2], b[3])
        return ok and hit and true or false
    end

    local function lineDir(i, j)
        local az = (i - 1) * 2 * math.pi / M.P.azn
        local er = math.rad(M.P.els[j])
        return { math.cos(az) * math.cos(er), math.sin(az) * math.cos(er), math.sin(er) }
    end

    -- The visibility map of the target at T (3 m above it: { x, y, z })
    function M.map(key, T)
        local m = M.maps[key]
        local t = now()
        if m and t - m.at < M.P.mapAge and (m.x - T[1]) ^ 2 + (m.y - T[2]) ^ 2 + (m.z - T[3]) ^ 2 < 500 ^ 2 then return m end
        local clear = {}
        for i = 1, M.P.azn do
            clear[i] = {}
            for j = 1, #M.P.els do
                local d = lineDir(i, j)
                local a = { T[1] + d[1] * 400, T[2] + d[2] * 400, T[3] + d[3] * 400 }
                local b = { T[1] + d[1] * M.P.range, T[2] + d[2] * M.P.range, T[3] + d[3] * M.P.range }
                clear[i][j] = not hits(a, b)
            end
        end
        m = { clear = clear, at = t, x = T[1], y = T[2], z = T[3] }
        M.maps[key] = m
        M.stats.maps = M.stats.maps + 1
        return m
    end

    local function usable(clear, i, j)
        local n = M.P.azn
        if not clear[i][j] then return false end
        if j > 1 and not clear[i][j - 1] then return false end
        local ip, im = i % n + 1, (i - 2) % n + 1
        return clear[ip][j] or clear[im][j]
    end

    -- The target in sight ahead: the line from it to the plane, and the seconds to it
    function M.direct(P, u, s, T)
        local d, dist = unit({ T[1] - P[1], T[2] - P[2], T[3] - P[3] })
        if dist < 7000 or dist > 26000 or dot(d, u) < math.cos(math.rad(40)) then return nil end
        local a = { P[1] + d[1] * 300, P[2] + d[2] * 300, P[3] + d[3] * 300 }
        local b = { T[1] - d[1] * 400, T[2] - d[2] * 400, T[3] - d[3] * 400 }
        if hits(a, b) then return nil end
        return { -d[1], -d[2], -d[3] }, dist / (math.max(s, 120) * 10)
    end

    -- Seconds until the plane (at P, flying u at s m/s) is on line r at the gate, heading in
    function M.cost(P, u, s, T, r, cloudZ)
        local v = math.max(s, 120) * 10
        local A = { T[1] + r[1] * M.P.approach, T[2] + r[2] * M.P.approach, T[3] + r[3] * M.P.approach }
        local dx, dy, dz = A[1] - P[1], A[2] - P[2], A[3] - P[3]
        local hA = math.sqrt(dx * dx + dy * dy)
        local tA = math.max(hA / v, dz / (v * M.P.climb))
        local om = math.max(M.ctx.omega(s) * M.P.share, 0.1)
        local uh = unit({ u[1], u[2], 0 })
        local toA = hA > 1 and unit({ dx, dy, 0 }) or uh
        local rin = unit({ -r[1], -r[2], 0 })
        local turn1 = math.acos(clamp(dot(uh, toA), -1, 1))
        local turn2 = math.acos(clamp(dot(toA, rin), -1, 1))
        local c = tA + (turn1 + turn2) / om + (M.P.approach - 20000) / v
        -- (a gate inside a cloud layer the target is below: the lock range is shorter there)
        if cloudZ and T[3] < cloudZ and T[3] + r[3] * M.P.gate > cloudZ - 800 then c = c + 8 end
        return c
    end

    -- The best line for the target now: { i, j } or { direct = r }, and its cost in seconds
    function M.best(key, P, u, s, T, cloudZ)
        local st = M.st[key]
        local r, tc = M.direct(P, u, s, T)
        if r then return { direct = r }, tc end
        local m = M.map(key, T)
        local best, bc = nil, 1e18
        local t = now()
        for i = 1, M.P.azn do
            for j = 1, #M.P.els do
                local bad = st and st.bad[i * 100 + j]
                if not (bad and bad > t) and usable(m.clear, i, j) then
                    local c = M.cost(P, u, s, T, lineDir(i, j), cloudZ)
                    if c < bc then best, bc = { i = i, j = j }, c end
                end
            end
        end
        return best, bc
    end

    local function sameLine(a, b)
        if not a or not b then return false end
        if a.direct or b.direct then return a == b end
        return a.i == b.i and a.j == b.j
    end

    -- Where to fly for the attack on target key at T (3 m above it), from P flying u at s m/s,
    -- agl m above the ground. Returns the aim (unit vector) and "in" or "out", or nil when no
    -- line is usable (the caller sets the target aside).
    function M.guide(key, P, u, s, agl, T, cloudZ)
        local t = now()
        local st = M.st[key]
        if not st then
            st = { bad = {}, run = "in", est = false, side = 1, lineAt = -100 }
            M.st[key] = st
        end
        if not st.line or (t - st.lineAt > 1.0 and not st.est) then
            local cand, cc = M.best(key, P, u, s, T, cloudZ)
            if not cand then return nil end
            -- (held unless another is sooner by 4 s, and by half the time it has been held more, up
            -- to 12 s: decisiveness. 20 Oct 2026, Mission 07: near the target steeper lines kept
            -- looking a little cheaper, 60, 70, 80 then 40 degrees in 9 s)
            if st.line and not cand.direct and not sameLine(cand, st.line) and not st.line.direct then
                local bad = st.bad[st.line.i * 100 + st.line.j]
                if not (bad and bad > t) then
                    local held = M.cost(P, u, s, T, lineDir(st.line.i, st.line.j), cloudZ)
                    local keep = math.min(M.P.keepMax, M.P.keep + M.P.keepGrow * (t - (st.lineSince or t)))
                    if held <= cc + keep then cand = st.line end
                end
            end
            if not sameLine(cand, st.line) then
                st.lineSince = t
                st.est = cand.direct and true or false
                if cand.direct then st.run = "in"; M.stats.direct = M.stats.direct + 1 end
                M.stats.lines = M.stats.lines + 1
                local r = cand.direct or lineDir(cand.i, cand.j)
                event("attack_line", { target = key, direct = cand.direct and true or false,
                    az_deg = math.floor(math.deg(math.atan(r[2], r[1])) + 0.5), el_deg = math.floor(math.deg(math.asin(clamp(r[3], -1, 1))) + 0.5),
                    soon_s = math.floor(cc * 10 + 0.5) / 10 })
            end
            st.line, st.lineAt = cand, t
        end
        local r = st.line.direct or lineDir(st.line.i, st.line.j)
        local w = { P[1] - T[1], P[2] - T[2], P[3] - T[3] }
        local sAl = dot(w, r)
        local C = { T[1] + r[1] * sAl, T[2] + r[2] * sAl, T[3] + r[3] * sAl }
        local e = len({ P[1] - C[1], P[2] - C[2], P[3] - C[3] })
        local vin = -dot(u, r)
        local dist = len(w)
        if st.run == "in" and (dist < 7000 or (agl < 150 and P[3] < T[3] + 3000)) then st.run, st.est = "out", false end
        if not st.est and st.run == "in" and sAl > M.P.gate * 0.8 and e < math.max(3000, 0.12 * sAl) and vin > math.cos(math.rad(35)) then
            st.est = true
            event("on_line", { target = key, along_m = sAl / 10, off_m = e / 10 })
        end
        if st.est and (e > math.max(6000, 0.25 * sAl) or vin < 0.3) then st.est = false end
        if st.run == "in" and not st.est and sAl < M.P.gate then st.run = "out" end
        -- (back in once past the gate by a turn radius: as soon as the turn can still end on the
        -- line before the lock, the way a skilled player turns back; out past the approach point,
        -- as at first, the wargame flew 2.68 shots a minute and crashed in 4.7% of ten-minute
        -- flights, this way 2.76 and 0.5%: the long legs out met the hills)
        local om = math.max(M.ctx.omega(s) * M.P.share, 0.1)
        local R = math.max(s, 150) * 10 / om
        if st.run == "out" and sAl > M.P.gate + R then st.run = "in" end
        -- on the line inside the gate and the target hidden for a second: that line is no good
        if st.est and sAl < M.P.gate then
            local d = unit({ T[1] - P[1], T[2] - P[2], T[3] - P[3] })
            local a = { P[1] + d[1] * 300, P[2] + d[2] * 300, P[3] + d[3] * 300 }
            local b = { T[1] - d[1] * 400, T[2] - d[2] * 400, T[3] - d[3] * 400 }
            local ok, hit, hx, hy, hz = pcall(M.ctx.trace, a[1], a[2], a[3], b[1], b[2], b[3])
            M.stats.traces = M.stats.traces + 1
            local short = (ok and hit and hx) and len({ T[1] - hx, T[2] - hy, T[3] - hz }) / 10 or 0
            if short > M.P.blockShort then
                st.blockedAt = st.blockedAt or t
                if t - st.blockedAt > M.P.blockFor then
                    if not st.line.direct then st.bad[st.line.i * 100 + st.line.j] = t + M.P.badFor end
                    M.stats.blocked = M.stats.blocked + 1
                    event("line_blocked", { target = key, short_m = short, dist_m = dist / 10, direct = st.line.direct and true or false })
                    st.line, st.est, st.blockedAt, st.run = nil, false, nil, "out"
                    return unit({ u[1], u[2], math.max(u[3], 0.1) }), "out"
                end
            else
                st.blockedAt = nil
            end
        end
        if st.run == "out" then
            -- out along the line, two turn radii to the plane's side, climbing to the line's height
            local n = unit({ -r[2], r[1], 0 })
            if sAl < M.P.approach then st.side = (dot(w, n) >= 0) and 1 or -1 end
            local far = M.P.gate + R + 5000
            local Q = { T[1] + r[1] * far + n[1] * 2 * R * st.side, T[2] + r[2] * far + n[2] * 2 * R * st.side, T[3] + r[3] * far }
            local dx, dy, dz = Q[1] - P[1], Q[2] - P[2], Q[3] - P[3]
            local hq = math.max(math.sqrt(dx * dx + dy * dy), 1)
            return levelTurn((unit({ dx / hq, dy / hq, clamp(dz / hq, -0.3, 0.5) })), u), "out"
        end
        local A = { T[1] + r[1] * M.P.approach, T[2] + r[2] * M.P.approach, T[3] + r[3] * M.P.approach }
        -- (straight for the approach point until 2.5 km from it, then onto the line: from 5 km the
        -- way onto the line crossed it with the target far off the nose; wargame 2.85 shots a
        -- minute against 2.79, 2.68 from 1.5 km)
        if (A[1] - P[1]) ^ 2 + (A[2] - P[2]) ^ 2 > 25000 ^ 2 then
            local dx, dy, dz = A[1] - P[1], A[2] - P[2], A[3] - P[3]
            local hq = math.max(math.sqrt(dx * dx + dy * dy), 1)
            return levelTurn((unit({ dx / hq, dy / hq, clamp(dz / hq, -0.3, 0.5) })), u), "in"
        end
        local sc = math.max(sAl - M.P.carrot, 0)
        local d = unit({ T[1] + r[1] * sc - P[1], T[2] + r[2] * sc - P[2], T[3] + r[3] * sc - P[3] })
        -- (climbing no steeper than about 27 degrees on the way; and while the line is more than
        -- 70 degrees off the nose, the turn onto it level, within -8..+17 degrees)
        local hq = math.sqrt(d[1] * d[1] + d[2] * d[2])
        local lo, hi = -9, 0.5
        if dot(d, u) < 0.34 then lo, hi = -0.15, 0.3 end
        if hq > 1e-6 and (d[3] / hq > hi or d[3] / hq < lo) then d = unit({ d[1] / hq, d[2] / hq, clamp(d[3] / hq, lo, hi) }) end
        return levelTurn(d, u), "in"
    end

    -- The angle (degrees up from the target) of the line flown at target key, or nil
    function M.lineEl(key)
        local st = M.st[key]
        if not st or not st.line then return nil end
        local r = st.line.direct or lineDir(st.line.i, st.line.j)
        return math.deg(math.asin(clamp(r[3], -1, 1)))
    end

    -- What the status shows: the line flown at target key
    function M.text(key)
        local st = M.st[key]
        if not st or not st.line then return nil end
        local r = st.line.direct or lineDir(st.line.i, st.line.j)
        return string.format("%s line %d deg up from %d deg%s", st.line.direct and "direct" or "attack",
            math.floor(math.deg(math.asin(clamp(r[3], -1, 1))) + 0.5), math.floor((math.deg(math.atan(r[2], r[1])) + 360) % 360 + 0.5),
            st.run == "out" and ", repositioning" or (st.est and ", on it" or ", closing on it"))
    end

    return M
end
