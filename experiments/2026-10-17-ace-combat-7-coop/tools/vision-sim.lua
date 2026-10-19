-- vision-sim.lua: fly a simple simulated plane through real geometry with vision.lua, inside
-- the running game (the rays are the game's own line traces). Run with the pilot's eval:
--   python tools\pilot.py send eval "return dofile('C:/.../tools/vision-sim.lua')(args)"
-- The plane: constant speed, its flight direction follows the vision's choice through a lag
-- (tau, s) and a turn-rate limit (deg/s); a crash is a trace hit between two positions.
-- Written 19 Oct 2026 for the owner's tunnel test (Mission 06), before flying it for real.
return function(a)
    local V = dofile(a.vision)({ log = function() end, event = function() end, now = os.clock })
    local function add(x, y) return { x[1] + y[1], x[2] + y[2], x[3] + y[3] } end
    local function mul(x, k) return { x[1] * k, x[2] * k, x[3] * k } end
    local function dot(x, y) return x[1] * y[1] + x[2] * y[2] + x[3] * y[3] end
    local function unit(x) local l = math.sqrt(dot(x, x)); return mul(x, 1 / math.max(l, 1e-9)) end
    local P, dir0 = a.through, unit(a.dir)
    local speed = a.kmh / 3.6 * 10                          -- game units per second
    local off = a.offset or 0                               -- metres to the right of the line
    local p = { P[1] - dir0[1] * a.start + dir0[2] * off * 10, P[2] - dir0[2] * a.start - dir0[1] * off * 10, a.startZ }
    local v = unit({ dir0[1], dir0[2], (P[3] - a.startZ) / a.start })
    local cmd = v
    local dt, tau, rate = a.dt or 0.05, a.tau or 0.3, math.rad(a.rate or 25)
    local passed, closest, log, minWall = false, 1e18, {}, 1e9
    local steps = math.floor((a.seconds or 30) / dt)
    for k = 1, steps do
        local toP = { P[1] - p[1], P[2] - p[2], P[3] - p[3] }
        local dP = math.sqrt(dot(toP, toP))
        if dP < closest then closest = dP end
        if not passed and dot(toP, dir0) < 0 then passed = true; log[#log + 1] = string.format("t%.1f PASSED P, closest %.1f m", k * dt, closest / 10) end
        local aim = passed and unit({ dir0[1], dir0[2], a.afterZ or 0.3 }) or unit(toP)
        local d = V.choose(p, mul(v, speed), aim, { horizon = 4.5, need = 3.0, centre = true })
        local L = V.last
        if L.walls then
            local w = math.min(L.walls.left, L.walls.right, L.walls.up, L.walls.down)
            if w < minWall then minWall = w end
        end
        cmd = unit(add(mul(cmd, 1 - dt / tau), mul(d, dt / tau)))
        local c = math.max(-1, math.min(1, dot(v, cmd)))
        local ang = math.acos(c)
        if ang > rate * dt then
            local perp = unit(add(cmd, mul(v, -c)))
            v = unit(add(mul(v, math.cos(rate * dt)), mul(perp, math.sin(rate * dt))))
        else v = cmd end
        local q = add(p, mul(v, speed * dt))
        local hit, hx, hy, hz = CoopTrace_Line(p[1], p[2], p[3], q[1], q[2], q[3])
        if hit then
            log[#log + 1] = string.format("t%.1f CRASH at (%.0f, %.0f, %.0f m)", k * dt, hx, hy, hz / 10)
            return table.concat(log, " | ")
        end
        p = q
        if k % math.floor(1 / dt) == 0 then
            local s = dot({ p[1] - P[1], p[2] - P[2], 0 }, dir0) / 10
            log[#log + 1] = string.format("t%.0f s%+.0f z%.0f %s L%.0f R%.0f U%.0f D%.0f", k * dt, s, p[3] / 10,
                L.i == 0 and "aim" or string.format("%d/%d", L.yaw or 0, L.pitch or 0),
                L.walls and L.walls.left or -1, L.walls and L.walls.right or -1, L.walls and L.walls.up or -1, L.walls and L.walls.down or -1)
        end
    end
    log[#log + 1] = string.format("END ok, closest to P %.1f m, nearest wall %.0f m", closest / 10, minWall)
    return table.concat(log, " | ")
end
