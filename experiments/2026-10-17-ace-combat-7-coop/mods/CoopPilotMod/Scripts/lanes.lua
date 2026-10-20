-- lanes.lua: the flight path chosen for the targets it brings into the lock cone
-- (CoopPilotMod, 19 Oct 2026; the Mission 06 score-race plan's "lane planner").
--
-- A player does not point the plane at one ground target at a time and set up a dive: he
-- flies a line through a group and shoots whatever comes into the missile's lock cone,
-- then the next. So twice a second the pilot tries a set of manoeuvres (straight on, turns
-- of 15 to 179 degrees either way, and "run out, then turn back" for targets too close to
-- point at), flies each one forward some seconds in a simple model, and counts the value of
-- the targets each would let it shoot:
--   * the plane: turns at its measured turn rate after a short roll-in, then flies
--     straight, easing toward a low pass height over the targets;
--   * the weapon: its real lock cone and lock range (read from the game), the lock time
--     (a base time plus the angle the seeker travels; learned from the pilot's own locks),
--     the missiles loaded and each one's reload clock;
--   * the shooting: the target nearest the nose inside the cone is selected, locks, gets a
--     missile, and the next one is selected at once (the chain).
-- The manoeuvre with the most value (earlier shots count a little more, and what lies ahead
-- at the end counts a little) is flown; a new plan has to beat the one being flown clearly.
-- Nothing here is level-specific: targets, values, the weapon and the plane all come in live
-- (main.lua). tools\lane-sim.py runs the same planner (a line-for-line Python copy) over many
-- generated layouts to tune the parameters below.

return function(env)
    local L = {}

    -- General parameters (tuned with tools\lane-sim.py across varied layouts, not one level)
    L.P = {
        horizon = 12.0,          -- s looked ahead
        dt = 0.25,               -- s per model step
        turns = { 0, 15, -15, 30, -30, 45, -45, 60, -60, 90, -90, 120, -120, 150, -150, 179, -179 },
        -- run out straight for some seconds, then turn back (left or right)
        extend = { { 0, 2.5, 179 }, { 0, 2.5, -179 }, { 0, 5.0, 179 }, { 0, 5.0, -179 } },
        rollIn = 0.15,           -- s of reaction before the roll into a turn begins
        rollRate = 120,          -- deg/s the plane rolls (the Typhoon: up to about 160, building up)
        bankTurn = 80,           -- deg of bank in a hard turn
        discount = 8,            -- s: a shot t seconds ahead counts exp(-t / discount)
        terminal = 0.25,         -- weight of the value still ahead at the end of the look-ahead
        hysteresis = 0.15,       -- a new plan must be this much better than the one flown
        passAgl = 250,           -- m: pass height above the targets (the simulator liked 200; 250 for hills and flak)
        minRange = 500,          -- m: closer targets are not counted (too steep below, too late)
        coneMargin = 1,          -- deg inside the weapon's lock cone
        rangeMargin = 0.97,      -- share of the weapon's lock range
        climbRate = 0.3,         -- the steepest climb or descent toward the pass height (sin of the angle; main.lua's dive, far above)
        omegaShare = 0.85,       -- share of the measured turn rate the plans count on
    }
    -- (tools\lane-sim.py, 19 Oct 2026, 48 layouts of six kinds with the plane's turn rate, the
    -- weapon's cone, range, reload and lock time varied: the lanes cleared 92% of the targets in
    -- 3 minutes against 60% for the old nose-on attack, 9.7 kills a minute against 5.8; the
    -- tuning moved discount 20 -> 8, pass height 300 -> 200, cone margin 3 -> 1, +6%; speed
    -- 500-850 km/h and the lock-time estimate mattered little)

    local sqrt, cos, sin, acos, exp, rad, log = math.sqrt, math.cos, math.sin, math.acos, math.exp, math.rad, math.log
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
    local function wrapPi(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    L.wrapPi = wrapPi

    -- The target to select from (x, y, z) with the nose along (fx, fy, fz): inside the cone
    -- (cosine above cosCone) and between rMin and rMax, nearest the nose; a degree counts like
    -- 10% more value. 'skip(i)' leaves out targets already shot at. Returns its index and angle.
    local function pick(x, y, z, fx, fy, fz, tg, skip, cosCone, rMin, rMax)
        local best, bestScore, bestAng = nil, -math.huge, nil
        for i = 1, #tg do
            if not skip(i) then
                local q = tg[i]
                local dx, dy, dz = q[1] - x, q[2] - y, q[3] - z
                local d = sqrt(dx * dx + dy * dy + dz * dz)
                if d <= rMax and d >= rMin and (dx * fx + dy * fy + dz * fz) > cosCone * d then
                    local ang = acos(clamp((dx * fx + dy * fy + dz * fz) / d, -1, 1))
                    local score = -math.deg(ang) + 10 * log(math.max(q[4], 1e-6))
                    if score > bestScore then best, bestScore, bestAng = i, score, ang end
                end
            end
        end
        return best, bestAng
    end

    -- One look-ahead along a manoeuvre 'leg': turn (the shorter way) to heading leg.psi1;
    -- from leg.tSwitch seconds on (if given), to leg.psi2.
    --   pl: { x, y, z (game units), psi (heading, rad), v (units/s), omega (rad/s), zPass (units),
    --         roll (bank now, rad, + = right) }
    -- A turn bites once the plane has rolled from its bank now to the turn's bank: continuing a
    -- turn costs nothing, reversing one about a second (19 Oct 2026: plans that swapped sides
    -- mid-turn left the plane rolling from wing to wing without pulling).
    --   wp: { cone (rad), range (units), minRange (units), loaded, reloadIn = { s, ... },
    --         loadTime (s), lockBase (s), lockRate (rad/s), sel (index of the target selected
    --         now, or nil), selLeft (s of lock still needed for it) }
    --   tg: { { x, y, z, value }, ... } (value per missile: points, or points times the share
    --         of the target's health one missile takes)
    -- Returns the value, the shots, the time of the first shot, the end point and heading, and
    -- the shots' value without the discount.
    function L.simulate(pl, wp, tg, leg, P)
        P = P or L.P
        local x, y, z, psi, v = pl.x, pl.y, pl.z, pl.psi, pl.v
        local omega = pl.omega
        local loaded = wp.loaded
        local reload = {}
        for i, r in ipairs(wp.reloadIn or {}) do reload[i] = r end
        local done = {}
        local function isDone(i) return done[i] end
        local sel, selNeed, selT = wp.sel, wp.selLeft or 0, 0
        local cosCone = cos(wp.cone - rad(P.coneMargin))
        local rMax = wp.range * P.rangeMargin
        local rMin = wp.minRange or P.minRange * 10
        local value, shots, first, raw = 0, 0, nil, 0
        local heading = leg.psi1
        local switched = leg.tSwitch == nil
        local rollRate, bankTurn = rad(P.rollRate), rad(P.bankTurn)
        local function rollTime(dir, bank) return P.rollIn + math.abs(dir * bankTurn - bank) / rollRate end
        local d1 = wrapPi(heading - psi)
        local dir1 = (d1 > 0.03 and 1) or (d1 < -0.03 and -1) or 0
        local rollUntil = dir1 ~= 0 and rollTime(dir1, pl.roll or 0) or 0
        local t = 0
        local dt = P.dt
        while t < P.horizon - 1e-6 do
            t = t + dt
            if not switched and t >= leg.tSwitch then
                -- (the plane is level after the run-out if its first turn was done)
                local bankNow = (math.abs(wrapPi(heading - psi)) > 0.03) and dir1 * bankTurn or 0
                local d2 = wrapPi(leg.psi2 - psi)
                heading, switched = leg.psi2, true
                rollUntil = t + rollTime(d2 >= 0 and 1 or -1, bankNow)
            end
            if t > rollUntil then
                local step = omega * dt
                psi = psi + clamp(wrapPi(heading - psi), -step, step)
            end
            local vz = clamp((pl.zPass - z) / 3, -v * P.climbRate, v * P.climbRate)
            local ch, sh = cos(psi), sin(psi)
            local vh = sqrt(math.max(v * v - vz * vz, 1))
            x = x + vh * ch * dt
            y = y + vh * sh * dt
            z = z + vz * dt
            local fx, fy, fz = vh * ch / v, vh * sh / v, vz / v
            for i = #reload, 1, -1 do
                if reload[i] <= t then loaded = loaded + 1; table.remove(reload, i) end
            end
            -- the selected target still in the cone and in range?
            if sel then
                local q = tg[sel]
                local dx, dy, dz = q[1] - x, q[2] - y, q[3] - z
                local d = sqrt(dx * dx + dy * dy + dz * dz)
                if done[sel] or d > rMax or d < rMin or (dx * fx + dy * fy + dz * fz) < cosCone * d then sel = nil end
            end
            -- if not, the one nearest the nose inside the cone (the chain's next link)
            if not sel then
                local ang
                sel, ang = pick(x, y, z, fx, fy, fz, tg, isDone, cosCone, rMin, rMax)
                if sel then
                    selNeed = wp.lockBase + ang / wp.lockRate
                    selT = 0
                end
            end
            if sel then
                selT = selT + dt
                if selT >= selNeed and loaded > 0 then
                    loaded = loaded - 1
                    reload[#reload + 1] = t + wp.loadTime
                    value = value + tg[sel][4] * exp(-t / P.discount)
                    raw = raw + tg[sel][4]
                    shots = shots + 1
                    first = first or t
                    done[sel] = true
                    sel = nil
                end
            end
        end
        -- what lies ahead at the end: targets within three lock ranges, ahead of the nose
        local term = 0
        local reach = wp.range * 3
        local ch, sh = cos(psi), sin(psi)
        for i = 1, #tg do
            if not done[i] then
                local q = tg[i]
                local dx, dy = q[1] - x, q[2] - y
                local d = sqrt(dx * dx + dy * dy)
                if d < reach and d > 1 then
                    local c = (dx * ch + dy * sh) / d
                    if c > 0.5 then term = term + q[4] * (c - 0.5) * 2 * (1 - d / reach) end
                end
            end
        end
        return value + P.terminal * term * exp(-P.horizon / P.discount), shots, first, x, y, psi, raw
    end

    -- The plan: every manoeuvre in the set, the best one. 'prev' is the plan being flown
    -- ({ psi1, psi2, switchAt } with switchAt on the clock 'now'), kept unless clearly beaten;
    -- 'okEnd(x, y)' says whether a plan's end point is acceptable (inside the combat zone).
    -- Returns { psi1, psi2, switchAt, value, shots, first, raw (the shots' value undiscounted),
    -- kept } or nil.
    function L.plan(pl, wp, tg, prev, now, okEnd, P)
        P = P or L.P
        local legs = {}
        for _, a in ipairs(P.turns) do legs[#legs + 1] = { psi1 = wrapPi(pl.psi + rad(a)) } end
        for _, e in ipairs(P.extend or {}) do
            legs[#legs + 1] = { psi1 = wrapPi(pl.psi + rad(e[1])), tSwitch = e[2], psi2 = wrapPi(pl.psi + rad(e[1] + e[3])) }
        end
        local best, bestV, bestShots, bestFirst, bestRaw = nil, -1, 0, nil, 0
        for _, leg in ipairs(legs) do
            local v, shots, first, ex, ey, _, raw = L.simulate(pl, wp, tg, leg, P)
            if okEnd and not okEnd(ex, ey) then v = v * 0.2 end
            if v > bestV then best, bestV, bestShots, bestFirst, bestRaw = leg, v, shots, first, raw end
        end
        local kept = false
        if prev and best then
            local leg = { psi1 = prev.psi1 }
            if prev.switchAt and prev.switchAt > now then leg.tSwitch, leg.psi2 = prev.switchAt - now, prev.psi2
            elseif prev.switchAt then leg.psi1 = prev.psi2 end
            local v, shots, first, ex, ey, _, raw = L.simulate(pl, wp, tg, leg, P)
            if okEnd and not okEnd(ex, ey) then v = v * 0.2 end
            if v > 0 and v >= bestV * (1 - P.hysteresis) then
                best, bestV, bestShots, bestFirst, bestRaw, kept = leg, v, shots, first, raw, true
            end
        end
        if not best then return nil end
        return { psi1 = best.psi1, psi2 = best.psi2, switchAt = best.tSwitch and (now + best.tSwitch) or nil,
                 value = bestV, shots = bestShots, first = bestFirst, raw = bestRaw, kept = kept }
    end

    -- The heading a plan wants at clock time 'now'
    function L.heading(plan, now)
        if plan.switchAt and now >= plan.switchAt then return plan.psi2 end
        return plan.psi1
    end

    -- The target to select now (the same choice the look-ahead makes): inside the cone and
    -- lock range, nearest the nose. 'skip(i)' leaves out targets already shot at (missile on
    -- its way). Returns its index and its angle off the nose (rad).
    function L.conePick(px, py, pz, fx, fy, fz, wp, tg, skip, P)
        P = P or L.P
        return pick(px, py, pz, fx, fy, fz, tg, skip or function() return false end,
                    cos(wp.cone - rad(P.coneMargin)), wp.minRange or P.minRange * 10, wp.range * P.rangeMargin)
    end

    return L
end
