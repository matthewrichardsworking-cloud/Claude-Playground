-- vision.lua: seeing in 3D with fans of rays (CoopPilotMod, 19 Oct 2026)
--
-- The height map in nav.lua knows the highest solid thing over each square of ground. That
-- is blind exactly where the owner wants to see the bot fly (memory "ac7-bot-vision-tests"):
-- under a bridge, between the legs of the Space Elevator, between city towers, inside a
-- tunnel. This layer looks the way eyes do: every 50 ms it casts a fan of rays from the plane
-- (the engine's own line traces through CoopPadMod, about 1.4 microseconds each), measures
-- how far each direction is free, and steers.
--
--   * Free directions: a grid of rays around the direction the pilot wants (yaw and pitch
--     steps out to 40 degrees), each as far as the plane flies in 4.5 seconds. A direction
--     counts as free as far as its own ray AND its neighbours go (the plane is not a point:
--     a Typhoon is 11 m wide), so a gap is only used if it is wide enough.
--   * Choosing: the free direction closest to the wanted one wins; a direction blocked
--     sooner than the plane can turn away costs a lot, the sooner the more.
--   * Corridors (a tunnel, a gap between towers): rays to the sides, up and down measure the
--     walls; when walls are close on both sides the aim is pulled toward the middle, and the
--     deepest forward rays show which way the corridor bends.
--
-- Nothing is surveyed beforehand: this is the "surprise" test, live sensing only.
-- Units: game units (10 cm) inside, metres in anything logged.

return function(env)
    local log, event, now = env.log, env.event, env.now
    local V = {}

    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); if l < 1e-9 then return { 1, 0, 0 }, 0 end; return mul(a, 1 / l), l end
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

    V.rays, V.evals = 0, 0
    -- How far along direction d (unit) from p is free, up to range (game units). Needs the
    -- fast traces (nav.lua's setupFast). Returns the free distance, and whether it hit.
    local function free(p, d, range)
        if type(CoopTrace_Line) ~= "function" then return range, false end
        local hit, hx, hy, hz, dist = CoopTrace_Line(p[1], p[2], p[3], p[1] + d[1] * range, p[2] + d[2] * range, p[3] + d[3] * range)
        V.rays = V.rays + 1
        if hit then
            if dist and dist > 0 then return dist, true end
            return len({ hx - p[1], hy - p[2], hz - p[3] }), true
        end
        return range, false
    end
    V.free = free

    -- A frame around a direction: forward f, right r, up u (u as close to world-up as possible).
    local function frame(f)
        local r = cross(f, { 0, 0, 1 })
        if len(r) < 1e-3 then r = { 0, 1, 0 } end
        r = unit(r)
        local u = unit(cross(r, f))
        return f, r, u
    end
    local function dirAt(f, r, u, yawDeg, pitchDeg)
        local y, pch = math.rad(yawDeg), math.rad(pitchDeg)
        -- yaw to the right (+), pitch up (+)
        local d = add(add(mul(f, math.cos(y) * math.cos(pch)), mul(r, math.sin(y) * math.cos(pch))), mul(u, math.sin(pch)))
        return unit(d)
    end

    local YAWS = { -40, -30, -22, -15, -10, -6, -3, 0, 3, 6, 10, 15, 22, 30, 40 }
    local PITCHES = { -30, -20, -13, -8, -4, 0, 4, 8, 13, 20, 30 }
    V.last = nil

    -- The walls around the plane: free distance (m) to the left, right, above, below, and the
    -- forward diagonals, measured from p in the frame of the flight direction.
    function V.walls(p, fwd)
        local f, r, u = frame(fwd)
        local R = 3000          -- 300 m: beyond that it is open air for this purpose
        local function m(d) return (free(p, d, R)) / 10 end
        return {
            left = m(mul(r, -1)), right = m(r), up = m(u), down = m(mul(u, -1)),
            upLeft = m(unit(add(u, mul(r, -1)))), upRight = m(unit(add(u, r))),
            downLeft = m(unit(add(mul(u, -1), mul(r, -1)))), downRight = m(unit(add(mul(u, -1), r))),
        }
    end

    -- The direction to fly: as close as possible to 'aim' (unit vector) and free for the next
    -- seconds. p: plane position, vel: its velocity (game units/s). opts.horizon (s, default
    -- 4.5), opts.margin (s, how soon trouble must be met to count fully, default 1.2).
    -- Returns the direction and a short text (nil text: the wanted direction is free).
    function V.choose(p, vel, aim, opts)
        opts = opts or {}
        V.evals = V.evals + 1
        local _, speed = unit(vel)
        speed = math.max(speed, 1200)
        local horizon = opts.horizon or 4.5
        local range = clamp(speed * horizon, 6000, 40000)
        -- the grid is centred between the flight direction and the wanted one (the plane can
        -- only turn so fast; directions far from where it is going are reached late)
        local vu = unit(vel)
        local centre = unit(add(mul(vu, 0.6), mul(aim, 0.4)))
        local f, r, u = frame(centre)
        local grid, gridDir = {}, {}
        for i, yd in ipairs(YAWS) do
            grid[i], gridDir[i] = {}, {}
            for j, pd in ipairs(PITCHES) do
                local d = dirAt(f, r, u, yd, pd)
                gridDir[i][j] = d
                grid[i][j] = free(p, d, range)
            end
        end
        -- a direction is free as far as it and its neighbours are (room for the wings)
        local best, bestCost, bestI, bestJ, bestFree = nil, math.huge, nil, nil, 0
        local wantedFree = nil
        local needed = speed * (opts.need or 3.0)
        for i = 1, #YAWS do
            for j = 1, #PITCHES do
                local fd = grid[i][j]
                for di = -1, 1 do
                    for dj = -1, 1 do
                        local row = grid[i + di]
                        local v = row and row[j + dj]
                        if v and v < fd then fd = v end
                    end
                end
                local d = gridDir[i][j]
                local off = math.deg(math.acos(clamp(dot(d, aim), -1, 1)))
                local turn = math.deg(math.acos(clamp(dot(d, vu), -1, 1)))
                local cost = off + turn * 0.3
                if fd < needed then
                    -- blocked within the time the plane needs: the sooner, the worse
                    cost = cost + 400 * (1 - fd / needed) + 100
                end
                if V.last and V.last.i == i and V.last.j == j then cost = cost - 2 end   -- stickiness
                if cost < bestCost then best, bestCost, bestI, bestJ, bestFree = d, cost, i, j, fd end
                if off < 2.5 and (not wantedFree or fd > wantedFree) then wantedFree = fd end
            end
        end
        -- corridor centring: walls close on both sides (or above and below) pull the aim
        -- toward the middle, harder the closer they are
        local walls = nil
        if opts.centre ~= false then
            walls = V.walls(p, vu)
            local _, rr, uu = frame(vu)
            local shift = { 0, 0, 0 }
            if walls.left < 120 and walls.right < 120 then
                shift = add(shift, mul(rr, clamp((walls.right - walls.left) / math.max(walls.left + walls.right, 10), -0.5, 0.5) * 0.35))
            end
            if walls.up < 120 and walls.down < 120 then
                shift = add(shift, mul(uu, clamp((walls.up - walls.down) / math.max(walls.up + walls.down, 10), -0.5, 0.5) * 0.35))
            end
            if len(shift) > 0 and best then best = unit(add(best, shift)) end
        end
        -- straight along the present flight path (the aim may lie outside the grid in a hard turn)
        local velFree = free(p, vu, range)
        V.last = { i = bestI, j = bestJ, free = bestFree / 10, wantedFree = wantedFree and wantedFree / 10 or nil, walls = walls,
                   velFree = velFree / 10,
                   yaw = YAWS[bestI], pitch = PITCHES[bestJ], range = range / 10 }
        local text = nil
        if best and (bestI ~= 8 or bestJ ~= 6 or (wantedFree and wantedFree < needed)) then
            text = string.format("vision: free %.0f m ahead the way it wants (%.0f m needed); flying %+d deg yaw, %+d deg pitch of centre, free %.0f m",
                (wantedFree or 0) / 10, needed / 10, YAWS[bestI] or 0, PITCHES[bestJ] or 0, bestFree / 10)
        end
        if walls and (walls.left < 120 or walls.right < 120 or walls.up < 120 or walls.down < 120) then
            text = (text and (text .. "; ") or "vision: ") .. string.format("walls left %.0f right %.0f up %.0f down %.0f m", walls.left, walls.right, walls.up, walls.down)
        end
        return best or aim, text
    end

    -- For the log: a small picture of the fan, nearest blocked distance per yaw column.
    function V.describe()
        local l = V.last
        if not l then return "vision: nothing yet" end
        return string.format("vision: %d rays in all, %d choices; last: free %.0f m (range %.0f m), wanted direction free %s m",
            V.rays, V.evals, l.free or 0, l.range or 0, l.wantedFree and string.format("%.0f", l.wantedFree) or "?")
    end

    return V
end
