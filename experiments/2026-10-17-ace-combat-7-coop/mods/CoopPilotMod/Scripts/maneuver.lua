-- maneuver.lua: flying the plane it has through the ground that is there (CoopPilotMod,
-- 20 Oct 2026; the owner: the bot needs better "pathfinding, maneuvering, innate knowledge of
-- its own aircraft's capabilities and how to use them in maneuvering, and decision making").
--
-- A model-predictive check on every way the pilot wants to fly. Four times a second the wanted
-- way is flown ahead for 5 seconds in a model of this plane (its measured turn rate of the
-- flight path, roll rate, and speed change by climb angle for throttle, brake and nothing), and
-- the path is traced against the real ground and structures with the engine's own line traces
-- (each step, extended by a margin, and a margin below). It must also end where a pull-out is
-- still possible. If it does, the pilot's way is flown unchanged. If not, about 50 other
-- manoeuvres are flown ahead the same way (the lift pointed up, down or to either side at
-- several angles, a medium or full pull, keeping speed or braking hard: this plane's brake
-- takes off about 70 m/s each second), and the safe one closest to the pilot's way wins, kept
-- a moment for decisiveness. Its point one second ahead becomes the aim; the brake comes on
-- with it when it brakes.
--
-- Tested first in tools\maneuver-sim.py (the same planner over Mission 07's surveyed ground and
-- the Typhoon's measured model): of 200 two-minute attack flights, 64% ended in the ground with
-- the fight's straight-ray safety net and 1.5% with this, with more shots a minute.
-- Nothing here is level-specific: the ground comes from the traces, the plane from its logs.
-- Units: game units (10 cm) for positions, m/s for speeds, radians inside, metres in logs.

return function(env)
    local log, event, now = env.log, env.event, env.now
    local M = {}

    M.P = {
        horizon = 5.0,      -- s flown ahead
        dt = 0.25,          -- s a step
        margin = 80,        -- m kept from the ground and structures (ahead and below; 60 was
                            -- flown on 20 Oct 2026 after the wargame gave 50 m 2.84 shots a
                            -- minute against 2.76 for 80, no more crashes: the first attempt hit a
                            -- rock pillar at 780 km/h, 0.6 s after the planner's last turn; the
                            -- survey's 50 m grid smooths such pillars away, so back to 80)
        keep = 1.6,         -- the pilot's way is kept when its clearance is this many margins
        lead = 1.0,         -- s: the chosen manoeuvre's point this far ahead is the aim
        stick = 4,          -- degrees of cost a choice saves by being the last one (decisiveness)
        hold = 1.5,         -- s an override manoeuvre is held while it stays clear (decisiveness)
        comfort = 25,       -- cost a step pays for coming within two margins (turn away early)
        escapeAfter = 1.0,  -- s of a dive the pilot keeps while a way out is still clear after it
        sideHold = 4.0,     -- s the side of the last turn away is preferred (decisiveness)
        sideCost = 30,      -- what turning the other way costs meanwhile
        share = 0.85,       -- share of the measured turn rate counted on
        roll = math.rad(120), -- rad/s the lift rolls (the Typhoon's logs: 80 typical, 130 at full roll)
        every = 0.25,       -- s between plans
    }
    -- speed change (m/s each second) by climb angle (15-degree bands, the band's start) for
    -- each way of flying: the Typhoon's logs of 20 Oct 2026 (tools\aircraft-model.py); learned
    -- further in flight by M.learn
    M.dv = {
        throttle = { [-90] = 30, [-75] = 39, [-60] = 3, [-45] = 11, [-30] = 20, [-15] = 15, [0] = 14, [15] = 13, [30] = 11, [45] = 16, [60] = 8, [75] = 0 },
        none = { [-90] = 30, [-75] = 35, [-60] = 4, [-45] = 16, [-30] = 3, [-15] = 2, [0] = 1, [15] = 1, [30] = 1, [45] = 0, [60] = 5, [75] = -13 },
        brake = { [-90] = 0, [-75] = 0, [-60] = -12, [-45] = 1, [-30] = -6, [-15] = -70, [0] = -65, [15] = -80, [30] = -91, [45] = -58, [60] = -40, [75] = -40 },
    }
    M.minBrake = 105        -- m/s (about 380 km/h): the brake is not held below this
    -- The brake by climb band (30 degrees, its start) and speed band (200 km/h, its start)
    -- together, where measured (toolsircraft-model.py's dv_by_kmh over 145 logs of Missions 06
    -- and 07, 20 Oct 2026): held level it takes off about 60 m/s each second at 800 km/h and 100
    -- at 1,200, but in a 30-60 degree dive it only holds the speed: a steep dive is flown at the
    -- speed it starts with, and the slowing has to come before it
    M.dv2 = {
        brake = { [-60] = { [400] = 5, [600] = 0, [800] = -1, [1000] = -9, [1200] = 12 },
            [-30] = { [400] = -3, [600] = -10, [800] = -27, [1000] = -38, [1200] = -75, [1400] = -91, [1600] = -109, [1800] = -101 },
            [0] = { [400] = -8, [600] = -46, [800] = -63, [1000] = -75, [1200] = -98, [1400] = -124, [1600] = -132, [1800] = -110 },
            [30] = { [400] = -12, [600] = -56, [800] = -77, [1000] = -95, [1200] = -104, [1400] = -111, [1600] = -122 } },
    }

    local sqrt, cos, sin, acos, asin, atan, floor = math.sqrt, math.cos, math.sin, math.acos, math.asin, math.atan, math.floor
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function unit(a) local l = sqrt(dot(a, a)); if l < 1e-12 then return { 1, 0, 0 }, 0 end; return { a[1] / l, a[2] / l, a[3] / l }, l end
    local function perp(v, u)
        local d = dot(v, u)
        local w, l = unit({ v[1] - d * u[1], v[2] - d * u[2], v[3] - d * u[3] })
        if l < 1e-6 then return nil end
        return w
    end
    local function ang(a, b) return acos(clamp(dot(a, b), -1, 1)) end

    local function cell2(mode, gamma, s)
        local t2 = M.dv2[mode]
        if not t2 or not s then return nil end
        local row = t2[clamp(floor(math.deg(gamma) / 30) * 30, -90, 60)]
        return row and row[floor(s * 3.6 / 200) * 200] and row or nil, floor(s * 3.6 / 200) * 200
    end

    function M.accel(mode, gamma, s)
        local row, kb = cell2(mode, gamma, s)
        if row then return row[kb] end
        local tab = M.dv[mode] or M.dv.none
        local g = clamp(floor(math.deg(gamma) / 15) * 15, -90, 75)
        return tab[g] or 0
    end

    -- the lift rolled toward Lc about the flight path u, by at most 'step' rad, either way
    local function rollToward(L, Lc, u, step)
        local th = atan(dot(cross(L, Lc), u), clamp(dot(L, Lc), -1, 1))
        local a = clamp(th, -step, step)
        local ux = cross(u, L)
        local ca, sa = cos(a), sin(a)
        return perp({ L[1] * ca + ux[1] * sa, L[2] * ca + ux[2] * sa, L[3] * ca + ux[3] * sa }, u) or L
    end

    -- the pilot's controller, short: roll the lift toward the aim and pull in proportion to the
    -- angle once the roll is close; a small correction the other way is a push, no roll
    local function chase(s, aim)
        local Lc = perp(aim, s.u)
        if not Lc then return s.L, 0 end
        local a = math.deg(ang(s.u, aim))
        local rollErr = math.deg(ang(s.L, Lc))
        if a < 12 and rollErr > 120 then return s.L, -math.min(0.5, a / 8) end
        local k = math.min(1, a / 8)
        if rollErr > 60 then k = 0 elseif rollErr > 30 then k = math.min(k, 0.6) end
        return Lc, k
    end

    -- one step of the model
    local function step(s, Lc, kc, mode, dt, omega)
        local u, L = s.u, s.L
        if Lc then L = rollToward(L, Lc, u, M.P.roll * dt) end
        local k = s.k + clamp(kc - s.k, -3 * dt, 3 * dt)
        k = clamp(k, -0.5, 1)
        local w = omega(s.s) * k * dt
        if math.abs(w) > 1e-6 then
            local cw, sw = cos(w), sin(w)
            local u2 = unit({ u[1] * cw + L[1] * sw, u[2] * cw + L[2] * sw, u[3] * cw + L[3] * sw })
            local L2 = unit({ L[1] * cw - u[1] * sw, L[2] * cw - u[2] * sw, L[3] * cw - u[3] * sw })
            u, L = u2, L2
        end
        local sp = s.s + M.accel(mode, asin(clamp(u[3], -1, 1)), s.s) * dt
        if mode == "brake" then sp = math.max(sp, math.min(s.s, M.minBrake)) end
        sp = clamp(sp, 70, 560)
        local d = sp * 10 * dt
        return { p = { s.p[1] + u[1] * d, s.p[2] + u[2] * d, s.p[3] + u[3] * d }, u = u, L = L, s = sp, k = k }
    end

    -- Fly one manoeuvre ahead: how = { "follow", aim, mode } or { "fixed", phi, k, mode } (the
    -- lift phi around the flight path from "up", held, pulling k). ctx: segFree(a, b) -> true
    -- when the line a-b is clear; clearBelow(p, m) -> true when nothing is within m metres
    -- under p; omega(speed) -> rad/s. Returns the states, the first time it gets too close
    -- (nil when clear), the step count.
    function M.rollOut(s0, how, ctx, comfort)
        local P = M.P
        local s = s0
        local pts = {}
        local n = math.floor(P.horizon / P.dt + 0.5)
        local mu = P.margin * 10
        local close = 0
        for i = 1, n do
            local Lc, k
            if how[1] == "follow" then
                Lc, k = chase(s, how[2])
            else
                local up = perp({ 0, 0, 1 }, s.u) or s.L
                local side = unit(cross(s.u, up))
                local c, sn = cos(how[2]), sin(how[2])
                Lc = unit({ up[1] * c + side[1] * sn, up[2] * c + side[2] * sn, up[3] * c + side[3] * sn })
                k = how[3]
            end
            local s2 = step(s, Lc, k, how[#how], P.dt, ctx.omega)
            -- the way there, and the margin beyond it, clear of everything; the margin under it too
            local d = s2.u
            local ahead = { s2.p[1] + d[1] * mu, s2.p[2] + d[2] * mu, s2.p[3] + d[3] * mu }
            if not ctx.segFree(s.p, ahead) or not ctx.clearBelow(s2.p, P.margin) then
                return pts, i * P.dt, n, close
            end
            -- (and how often within two margins: a manoeuvre that skims the ground or a wall
            -- costs more than one that keeps away; checked every other step)
            if comfort and i % 2 == 0 then
                local far = { s2.p[1] + d[1] * mu * 2, s2.p[2] + d[2] * mu * 2, s2.p[3] + d[3] * mu * 2 }
                if not ctx.segFree(s2.p, far) or not ctx.clearBelow(s2.p, P.margin * 2) then close = close + 1 end
            end
            pts[#pts + 1] = s2
            s = s2
        end
        -- the end must leave room for a pull-out (the safe end of the look-ahead)
        local e = pts[#pts]
        if e and e.u[3] < 0 then
            local cg = sqrt(math.max(0, 1 - e.u[3] ^ 2))
            local R = e.s / math.max(ctx.omega(e.s) * P.share, 0.05)
            local need = R * (1 - cg) + e.s * 0.5 * (-e.u[3]) + P.margin
            if not ctx.clearBelow(e.p, need) then return pts, P.horizon, n, close end
        end
        return pts, nil, n, close
    end

    local PHIS = { 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }
    M.stats = { plans = 0, overrides = 0, noWay = 0, traces = 0 }
    M.last = nil

    -- The way to fly. s: { p, u, L, s (m/s), k }; aim: the pilot's (unit); mode: the speed the
    -- pilot wants ("throttle", "none", "brake"); t: clock. Returns the aim, the mode, and a
    -- short text when the plan overrode the pilot (nil when the pilot's way is clear).
    local function leadAim(s, pts)
        local ld = pts[math.min(#pts, math.floor(M.P.lead / M.P.dt + 0.5))]
        return unit({ ld.p[1] - s.p[1], ld.p[2] - s.p[2], ld.p[3] - s.p[3] })
    end

    function M.filter(s, aim, mode, t, ctx)
        local P = M.P
        M.stats.plans = M.stats.plans + 1
        local fp, bad = M.rollOut(s, { "follow", aim, mode }, ctx)
        if not bad then
            -- clear, and with room to spare ahead and below (a margin and a half): the pilot's
            -- way is flown, and a held manoeuvre is let go
            local spare = true
            local mk = P.margin * P.keep * 10
            for i = 2, #fp, 2 do
                local q, d = fp[i].p, fp[i].u
                if not ctx.clearBelow(q, P.margin * P.keep) or not ctx.segFree(q, { q[1] + d[1] * mk, q[2] + d[2] * mk, q[3] + d[3] * mk }) then
                    spare = false
                    break
                end
            end
            if spare then M.hold, M.last = nil, nil; return aim, mode, nil end
        end
        -- Diving at something (the pilot's aim more than about 17 degrees down: an attack points
        -- at the ground on purpose and pulls out after the shot): the pilot's way is kept while,
        -- after one more second of it, a hard pull-up (straight, or 30 degrees to either side,
        -- braking) is still clear. 20 Oct 2026, Mission 07: without this every dive at a SAM in
        -- a canyon looked like flying into the ground, and the plane circled it, never firing.
        if aim[3] < -0.3 then
            local saveH = P.horizon
            P.horizon = P.escapeAfter
            local f1, b1 = M.rollOut(s, { "follow", aim, mode }, ctx)
            P.horizon = saveH
            if not b1 and #f1 > 0 then
                local s1 = f1[#f1]
                for _, pd in ipairs({ 0, 30, -30 }) do
                    local _, b2 = M.rollOut(s1, { "fixed", math.rad(pd), 1.0, "brake" }, ctx)
                    if not b2 then M.hold = nil; return aim, mode, nil end
                end
            end
        end
        M.stats.overrides = M.stats.overrides + 1
        -- a manoeuvre chosen in the last moment and still clear is kept (decisiveness: until
        -- this was added, a test plane at a wall switched between six ways to turn in two
        -- seconds, waited, and flew into it, 20 Oct 2026)
        local H = M.hold
        if H and t - H.t < P.hold then
            local how = H.how[1] == "follow" and { "follow", aim, "brake" } or H.how
            local pts, b = M.rollOut(s, how, ctx)
            if not b and #pts > 0 then
                if how[1] == "follow" then return aim, "brake", "manoeuvre: holding the pilot's way, braking" end
                return leadAim(s, pts), how[#how], "manoeuvre: holding " .. H.key
            end
        end
        local best, bestC, bestPts, bestKey = nil, math.huge, nil, nil
        local function consider(how, key)
            local pts, b, _, close = M.rollOut(s, how, ctx, true)
            local c
            if b then
                c = 1e6 - b * 1000
            else
                local e = pts[#pts]
                local ld = pts[math.min(#pts, math.floor(P.lead / P.dt + 0.5))]
                c = math.deg(ang(ld.u, aim)) + 0.5 * math.deg(ang(e.u, aim))
                if e.s * 3.6 < 330 then c = c + (330 - e.s * 3.6) * 0.3 end
                c = c + (close or 0) * P.comfort
            end
            if M.last and M.last.key == key and t - M.last.t < 1.0 then c = c - P.stick end
            -- (and the same side as the last turn away for a few seconds: in Mission 07's first
            -- flight with the planner it held each choice, but the next one flipped from lift left
            -- to lift right and back four times in five seconds)
            if M.side and t - M.side.t < P.sideHold and how[1] == "fixed" and how[3] > 0 then
                local sd = (how[2] > 0.1 and 1) or (how[2] < -0.1 and -1) or 0
                if sd ~= 0 and sd ~= M.side.sd then c = c + P.sideCost end
            end
            if c < bestC then best, bestC, bestPts, bestKey = how, c, pts, key end
        end
        consider({ "follow", aim, "brake" }, "follow|brake")
        for _, pd in ipairs(PHIS) do
            for _, k in ipairs({ 0.6, 1.0 }) do
                for _, sm in ipairs({ "none", "brake" }) do
                    consider({ "fixed", math.rad(pd), k, sm }, pd .. "|" .. k .. "|" .. sm)
                end
            end
        end
        consider({ "fixed", 0, 0, "none" }, "straight")
        M.last = { key = bestKey, t = t }
        local text
        if bestC >= 1e5 then
            M.stats.noWay = M.stats.noWay + 1
            text = "manoeuvre: no clear way; the one with the trouble latest"
            M.hold = nil
        else
            M.hold = { how = best, key = bestKey, t = t }
            if best[1] == "fixed" and best[3] > 0 then
                local sd = (best[2] > 0.1 and 1) or (best[2] < -0.1 and -1) or 0
                if sd ~= 0 then M.side = { sd = sd, t = t } end
            end
        end
        if best[1] == "follow" then
            return aim, best[#best], text or "manoeuvre: the pilot's way, braking"
        end
        if not bestPts or #bestPts == 0 then return aim, "brake", text or "manoeuvre: nothing flown" end
        return leadAim(s, bestPts), best[#best], text or string.format("manoeuvre: lift %s, pull %.1f, %s", bestKey:match("^[^|]+") or "?", best[3] or 0, best[#best])
    end

    -- Learning this plane's speed changes in flight: (mode, climb angle) -> m/s each second,
    -- blended into the table (a slow average: one second of flying moves it 2%).
    function M.learn(mode, gamma, dv, dt, s)
        local tab = M.dv[mode]
        if not tab or dt <= 0 or dt > 0.5 then return end
        local g = clamp(floor(math.deg(gamma) / 15) * 15, -90, 75)
        local w = clamp(dt * 0.02, 0, 0.05)
        tab[g] = (tab[g] or dv) * (1 - w) + dv * w
        local row, kb = cell2(mode, gamma, s)
        if row then row[kb] = row[kb] * (1 - w) + dv * w end
    end

    return M
end
