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
--     steps out to 40 degrees), each as far as the plane flies in 4.5 seconds, and the wanted
--     direction itself. The plane is not a point (a Typhoon is 11 m wide): the best few
--     directions are checked again with four rays parallel to it, 7 m to each side and 4 m
--     above and below, so a gap is only used if the plane fits through it. (Until 19 Oct
--     05:10 a direction counted only as far as its neighbouring grid rays, 3-4 degrees away,
--     went: at 400 m that is 25 m to each side, and a 36 m high tunnel mouth looked shut.)
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

    -- The plane's size for the tube check: half the Typhoon's 11 m span plus a margin, and
    -- half its height plus a margin (game units).
    V.halfWidth, V.halfHeight = 70, 40

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

    -- How far a plane-sized tube along direction d (unit) from p is free: four rays parallel
    -- to d, offset to the sides and up and down in d's own frame. The shortest one counts.
    function V.tube(p, d, range, scale)
        local _, r, u = frame(d)
        local m = range
        local hw, hh = V.halfWidth * (scale or 1), V.halfHeight * (scale or 1)
        for _, o in ipairs({ mul(r, hw), mul(r, -hw), mul(u, hh), mul(u, -hh) }) do
            local fd = free(add(p, o), d, range)
            if fd < m then m = fd end
        end
        return m
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
    -- opts.wide: the fight's safety net (19 Oct 2026, Mission 06: blocked 300 m ahead at 650 km/h
    -- by a bridge, the closest free direction was 3 degrees off the obstacle's edge, free for a
    -- plane-sized tube, and the plane, still turning onto it, hit the edge): the tube is three
    -- times as wide and high, and climbing costs less than diving or turning (structures stand
    -- on the ground; the sky above them is free). Threading a gap keeps the plane-sized tube.
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
        -- In a corridor (walls close on both sides, or above and below), follow the corridor:
        -- the wanted direction is pulled toward the deepest free direction ahead, so a bend is
        -- taken while it is still far ahead (19 Oct 2026, Mission 06's tunnel: steering only
        -- when the straight-ahead way was blocked, the plane met the bend near the far end too
        -- late and hit the wall). A fan of level rays 30 degrees each side; the deepest wins.
        local wallsNow = nil
        if opts.centre ~= false then
            wallsNow = V.walls(p, vu)
            local sideWalls = wallsNow.left < 120 and wallsNow.right < 120
            local roofFloor = wallsNow.up < 120 and wallsNow.down < 120
            if sideWalls or roofFloor then
                local fv, rv, uv = frame(vu)
                local bestY, bestD = 0, -1
                local depth = {}
                for k = -10, 10 do depth[k] = free(p, dirAt(fv, rv, uv, k * 3, 0), range) end
                for k = -9, 9 do
                    local dk = (depth[k - 1] + depth[k] * 2 + depth[k + 1]) / 4
                    if dk > bestD + 1 or (math.abs(dk - bestD) <= 1 and math.abs(k) < math.abs(bestY)) then bestY, bestD = k, dk end
                end
                local corridor = dirAt(fv, rv, uv, bestY * 3, 0)
                aim = unit(add(mul(aim, 0.3), mul(corridor, 0.7)))
                V.corridorYaw = bestY * 3
            else
                V.corridorYaw = nil
            end
        end
        local centre = unit(add(mul(vu, 0.6), mul(aim, 0.4)))
        local f, r, u = frame(centre)
        local needed = speed * (opts.need or 3.0)
        local tubeScale = opts.wide and 3 or 1
        local function costOf(d, fd)
            local off = math.deg(math.acos(clamp(dot(d, aim), -1, 1)))
            local turn = math.deg(math.acos(clamp(dot(d, vu), -1, 1)))
            local cost = off + turn * 0.3
            if opts.wide then cost = cost - math.deg(math.asin(clamp(d[3], -1, 1))) * 0.5 end
            if fd < needed then
                -- blocked within the time the plane needs: the sooner, the worse
                cost = cost + 400 * (1 - fd / needed) + 100
            end
            return cost
        end
        -- candidates: the grid's centre rays, and the wanted direction itself (index 0, 0),
        -- with the cost their centre ray alone gives (the best case)
        local cands = {}
        for i, yd in ipairs(YAWS) do
            for j, pd in ipairs(PITCHES) do
                local d = dirAt(f, r, u, yd, pd)
                local fd = free(p, d, range)
                local c = costOf(d, fd)
                if V.last and V.last.i == i and V.last.j == j then c = c - 2 end   -- stickiness
                cands[#cands + 1] = { d = d, fd = fd, cost = c, i = i, j = j }
            end
        end
        local aimFd = free(p, aim, range)
        cands[#cands + 1] = { d = aim, fd = aimFd, cost = costOf(aim, aimFd) - ((V.last and V.last.i == 0) and 2 or 0), i = 0, j = 0 }
        table.sort(cands, function(a, b) return a.cost < b.cost end)
        -- room for the plane: the best candidates again with four parallel rays (a tube);
        -- the tube can only shorten the free distance, so the first candidate whose checked
        -- cost is no worse than the next one's best case wins
        local best, bestCost, bestI, bestJ, bestFree = nil, math.huge, nil, nil, 0
        local wantedFree = nil
        for k = 1, math.min(#cands, 12) do
            local cd = cands[k]
            if best and bestCost <= cd.cost then break end
            local fd = math.min(cd.fd, V.tube(p, cd.d, range, tubeScale))
            local c = costOf(cd.d, fd) + (cd.cost - costOf(cd.d, cd.fd))
            if cd.i == 0 then wantedFree = fd end
            if c < bestCost then best, bestCost, bestI, bestJ, bestFree = cd.d, c, cd.i, cd.j, fd end
        end
        if not wantedFree then wantedFree = math.min(aimFd, V.tube(p, aim, range, tubeScale)) end
        -- corridor centring: walls close on both sides (or above and below) pull the aim
        -- toward the middle, harder the closer they are
        local walls = nil
        if opts.centre ~= false then
            walls = wallsNow or V.walls(p, vu)
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
        if best and (bestI ~= 0 or (wantedFree and wantedFree < needed)) then
            text = string.format("vision: free %.0f m ahead the way it wants (%.0f m needed); flying %s, free %.0f m",
                (wantedFree or 0) / 10, needed / 10,
                bestI == 0 and "the wanted way" or string.format("%+d deg yaw, %+d deg pitch of centre", YAWS[bestI] or 0, PITCHES[bestJ] or 0), bestFree / 10)
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
