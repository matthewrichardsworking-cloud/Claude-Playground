-- nav.lua: seeing the ground and the obstacles ahead, and steering through them
-- (CoopPilotMod, phase 3, 18 Oct 2026)
--
-- Three layers, each building on the one before:
--
-- 1. A height map of the ground, learned as the plane flies. Line traces straight down
--    (UE4's own collision test, the call the game uses for its own checks) at the centre
--    of 100 m squares find the highest solid thing there: ground, a building, a bridge.
--    Squares near the plane's path are measured first, then a wide fan ahead. Ground does
--    not move, so every square is measured once and kept for the whole mission.
-- 2. A look ahead along the path. For a direction the plane could fly, the path it would
--    really fly (turning there at the rate it can turn, then straight on) is followed for
--    several seconds and checked against the height map (clearance above the ground),
--    the altitude ceiling, the searchlight beams (where they will point when the plane is
--    there; gimmicks.lua), and other planes. A short trace along the path itself catches
--    what a height map can miss (an overhang, a tower between two squares).
-- 3. Choosing the direction. Many directions around the one the pilot wants are checked;
--    the safe one closest to it wins, with a little stickiness so the choice does not
--    flicker. With a ceiling over a valley, the safe directions are the ones that follow
--    the open corridor, so the plane follows the valley by itself.
--
-- A route planner on the height map (layer 4: plan) finds a way around high ground when
-- the ceiling forbids climbing over it: the squares where the ground leaves enough room
-- under the ceiling are the open ones, and the cheapest path through them to the goal is
-- searched (A*, unknown squares assumed open until measured, and measured first).
--
-- Units: game units (10 cm) inside, metres in anything logged.

return function(env)
    local log, event, now = env.log, env.event, env.now
    local N = {}
    local UEHelpers = require("UEHelpers")

    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); if l < 1e-9 then return { 1, 0, 0 }, 0 end; return mul(a, 1 / l), l end
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

    -- ---- tracing ---------------------------------------------------------------------
    local KSL = nil
    local NO = { R = 0, G = 0, B = 0, A = 0 }
    N.traces, N.traceMs = 0, 0          -- totals, for the cost report
    N.frameTraces = 0
    local function ksl()
        if not KSL then KSL = UEHelpers.GetKismetSystemLibrary() end
        return KSL
    end
    -- The fast way (CoopPadMod's CoopTrace_*, C++ calling the engine's trace directly), set
    -- up once with the function, the library and a world-context object (the plane).
    N.fast = false
    local fastCtx = nil
    function N.setupFast(ctx)
        if type(CoopTrace_Setup) ~= "function" then return false, "CoopPadMod has no CoopTrace (old build)" end
        local ok, res = pcall(function()
            local fn = StaticFindObject("/Script/Engine.KismetSystemLibrary:LineTraceSingle")
            local cdo = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            if not (fn and fn:IsValid() and cdo and cdo:IsValid() and ctx and ctx:IsValid()) then return false end
            return CoopTrace_Setup(cdo:GetAddress(), fn:GetAddress(), ctx:GetAddress())
        end)
        N.fast = ok and res == true
        fastCtx = N.fast and ctx or nil
        return N.fast, ok and (N.fast and "ready" or "objects not found") or tostring(res)
    end

    -- One line trace from a to b: the hit point {x, y, z} or nil.
    local function trace(ctx, a, b)
        if N.fast then
            if not rawequal(ctx, fastCtx) then
                local okA, addr = pcall(function() return ctx:GetAddress() end)
                if okA and addr then CoopTrace_Context(addr); fastCtx = ctx end
            end
            local t0f = os.clock()
            local hit, x, y, z = CoopTrace_Line(a[1], a[2], a[3], b[1], b[2], b[3])
            N.traceMs = N.traceMs + (os.clock() - t0f) * 1000
            N.traces = N.traces + 1
            N.frameTraces = N.frameTraces + 1
            if hit == nil then N.fast = false
            elseif hit then return { x, y, z }
            else return nil end
        end
        local hit = {}
        local t0 = os.clock()
        local ok, wasHit = pcall(function()
            return ksl():LineTraceSingle(ctx, { X = a[1], Y = a[2], Z = a[3] }, { X = b[1], Y = b[2], Z = b[3] }, 0, false, {}, 0, hit, true, NO, NO, 0.0)
        end)
        N.traceMs = N.traceMs + (os.clock() - t0) * 1000
        N.traces = N.traces + 1
        N.frameTraces = N.frameTraces + 1
        if not ok then N.traceError = tostring(wasHit); KSL = nil; return nil end
        if not wasHit then return nil end
        local okP, p = pcall(function() local ip = hit.ImpactPoint; return { ip.X, ip.Y, ip.Z } end)
        if okP then return p end
        return nil
    end
    N.trace = trace

    -- ---- 1. the height map -------------------------------------------------------------
    N.CELL = 1000                 -- 100 m squares
    N.TOP = 120000                -- traces start 12 km up (above any ground in the game)
    N.SEA = 0                     -- the sea's height (game units); learned if the sea is solid
    local H = {}                  -- key -> highest solid z in the square (false: nothing there, sea)
    local Hfar = {}               -- key -> true when measured from far away (re-measure when near)
    N.cells = 0
    local function key(ix, iy) return (ix + 1000000) * 2000000 + (iy + 1000000) end
    local function cellOf(x, y) return math.floor(x / N.CELL), math.floor(y / N.CELL) end
    N.key, N.cellOf = key, cellOf

    local function measure(ctx, ix, iy, far)
        local x, y = (ix + 0.5) * N.CELL, (iy + 0.5) * N.CELL
        local p = trace(ctx, { x, y, N.TOP }, { x, y, -20000 })
        local k = key(ix, iy)
        if H[k] == nil then N.cells = N.cells + 1 end
        H[k] = p and p[3] or false
        Hfar[k] = far or nil
        return H[k]
    end

    -- The ground's height at a point as far as known: the highest of the squares around it
    -- (a peak between square centres must not be missed). nil = not measured yet.
    N.precise = false          -- true: the square itself only (a fine survey), not its neighbours too
    function N.groundAt(x, y)
        local ix, iy = cellOf(x, y)
        if N.precise then
            local v = H[key(ix, iy)]
            if v == nil then return nil end
            return v or N.SEA
        end
        local best, known = nil, false
        local fx, fy = x / N.CELL - ix, y / N.CELL - iy
        local dx = fx < 0.5 and -1 or 1
        local dy = fy < 0.5 and -1 or 1
        for _, d in ipairs({ { 0, 0 }, { dx, 0 }, { 0, dy }, { dx, dy } }) do
            local v = H[key(ix + d[1], iy + d[2])]
            if v ~= nil then
                known = true
                local z = v or N.SEA
                if not best or z > best then best = z end
            end
        end
        if not known then return nil end
        return best
    end
    function N.known(x, y) local ix, iy = cellOf(x, y); return H[key(ix, iy)] ~= nil end

    -- Squares waiting to be measured, most urgent first: each frame the budget goes to the
    -- path ahead first, then to the fan.
    local want = {}
    local wantSet = {}
    function N.ask(x, y, urgent)
        local ix, iy = cellOf(x, y)
        local k = key(ix, iy)
        if H[k] ~= nil and not Hfar[k] then return end
        if wantSet[k] then return end
        wantSet[k] = true
        if urgent then table.insert(want, 1, { ix, iy, k }) else want[#want + 1] = { ix, iy, k } end
    end

    -- Spend up to 'budget' traces measuring squares, nearest the plane first among the
    -- urgent ones. Returns how many were measured.
    function N.measureSome(ctx, budget, myP)
        local n = 0
        while n < budget and #want > 0 do
            local w = table.remove(want, 1)
            wantSet[w[3]] = nil
            if H[w[3]] == nil or Hfar[w[3]] then
                local cx, cy = (w[1] + 0.5) * N.CELL, (w[2] + 0.5) * N.CELL
                local far = myP and ((cx - myP[1]) ^ 2 + (cy - myP[2]) ^ 2) > (60000 ^ 2)
                if not (Hfar[w[3]] and far) then measure(ctx, w[1], w[2], far); n = n + 1 end
            end
        end
        if #want > 4000 then for i = #want, 3001, -1 do wantSet[want[i][3]] = nil; want[i] = nil end end
        return n
    end
    function N.pending() return #want end

    -- ---- 2. the path a direction leads to ----------------------------------------------
    -- The plane's path if it now turns toward direction d (unit vector) at 'rate' rad/s and
    -- then flies straight: points every 'step' seconds up to 'horizon' seconds.
    function N.pathFor(p, v, d, rate, horizon, step)
        local u, s = unit(v)
        if s < 100 then s = 100 end
        local pts = {}
        local pos = { p[1], p[2], p[3] }
        local dir = u
        local t = 0
        while t < horizon - 1e-6 do
            t = t + step
            -- turn the direction toward d by at most rate*step
            local c = clamp(dot(dir, d), -1, 1)
            local ang = math.acos(c)
            local maxA = rate * step
            if ang <= maxA or ang < 1e-4 then dir = d
            else
                local axis = cross(dir, d)
                local al = len(axis)
                if al < 1e-6 then axis = { 0, 0, 1 } else axis = mul(axis, 1 / al) end
                -- rotate dir about axis by maxA (Rodrigues)
                local ca, sa = math.cos(maxA), math.sin(maxA)
                local kxd = cross(axis, dir)
                local kd = dot(axis, dir)
                dir = unit(add(add(mul(dir, ca), mul(kxd, sa)), mul(axis, kd * (1 - ca))))
            end
            pos = add(pos, mul(dir, s * step))
            pts[#pts + 1] = { t = t, p = pos, dir = dir }
        end
        return pts
    end

    -- Check one path. Returns the first time something is wrong (nil if nothing), what it
    -- is, and the smallest ground clearance on the way (metres; nil where unmeasured).
    --   rules.floor:   metres of clearance wanted above the ground
    --   rules.ceiling: game units (absolute z) not to go above, or nil
    --   rules.beams:   function(q, t) -> light or nil (gimmicks.lua's beamHit)
    --   rules.planes:  list of { p, v, r } other planes (game units) to keep r away from
    function N.checkPath(pts, rules, myP)
        local minClear, unknown = nil, 0
        for _, pt in ipairs(pts) do
            local q = pt.p
            local g = N.groundAt(q[1], q[2])
            if g == nil then
                unknown = unknown + 1
                N.ask(q[1], q[2], true)
            else
                local clear = (q[3] - g) / 10
                if not minClear or clear < minClear then minClear = clear end
                if clear < rules.floor then return pt.t, "ground", minClear, unknown end
            end
            if rules.ceiling and q[3] > rules.ceiling then return pt.t, "ceiling", minClear, unknown end
            if rules.beams then
                local L = rules.beams(q, pt.t)
                if L then return pt.t, "searchlight", minClear, unknown end
            end
            if rules.planes then
                for _, o in ipairs(rules.planes) do
                    local op = add(o.p, mul(o.v, pt.t))
                    if len(sub(op, q)) < o.r then return pt.t, "plane", minClear, unknown end
                end
            end
        end
        return nil, nil, minClear, unknown
    end

    -- ---- 3. choosing the direction ------------------------------------------------------
    -- Directions to try: around the wanted one, by heading and by climb angle.
    local YAWS = { 0, -8, 8, -16, 16, -25, 25, -35, 35, -50, 50, -70, 70, -95, 95, -125, 125 }
    local CLIMBS = { 0, 6, -6, 12, -12, 22, -20, 35 }

    local function headingClimb(d)
        local h = math.atan(d[2], d[1])
        local c = math.atan(d[3], math.sqrt(d[1] ^ 2 + d[2] ^ 2))
        return h, c
    end
    local function fromHC(h, c)
        return { math.cos(c) * math.cos(h), math.cos(c) * math.sin(h), math.sin(c) }
    end

    N.last = nil              -- the last choice, for stickiness and the log
    N.stats = { evals = 0, changed = 0, blockedWanted = 0 }

    -- The safe direction closest to 'aim' (unit vector), for a plane at p (game units)
    -- moving with velocity v. rules: as checkPath, plus horizon (s), rate (rad/s).
    -- Returns the direction to fly and a short description.
    function N.choose(ctx, p, v, aim, rules)
        local horizon = rules.horizon or 7
        local rate = rules.rate or math.rad(18)
        local step = rules.step or 0.5
        local h0, c0 = headingClimb(aim)
        -- what the pilot wants, checked first
        local wantedPts = N.pathFor(p, v, aim, rate, horizon, step)
        local badT, why, clear = N.checkPath(wantedPts, rules, p)
        N.stats.evals = N.stats.evals + 1
        -- trouble far enough ahead (rules.minBadT) is left to the pilot's own plan (a route
        -- that was planned around it), only near trouble makes the look-ahead step in
        if not badT or (rules.minBadT and badT >= rules.minBadT) then
            N.last = { d = aim, dh = 0, dc = 0, why = nil, clear = clear }
            return aim, nil
        end
        N.stats.blockedWanted = N.stats.blockedWanted + 1
        -- the wanted direction runs into something: look around it
        local best, bestCost, bestInfo = nil, math.huge, nil
        local stickH = N.last and N.last.dh or 0
        for _, dy in ipairs(YAWS) do
            for _, dc in ipairs(CLIMBS) do
                local c = clamp(c0 + math.rad(dc), math.rad(-40), math.rad(45))
                local d = fromHC(h0 + math.rad(dy), c)
                local pts = N.pathFor(p, v, d, rate, horizon, step)
                local bT, bWhy, bClear = N.checkPath(pts, rules, p)
                -- cost: how far from the wanted direction, plus a big price for trouble,
                -- the sooner the bigger
                local cost = math.abs(dy) + math.abs(dc) * 0.8
                cost = cost + math.abs(dy - stickH) * 0.15                 -- stickiness
                if bT then cost = cost + 1000 * (horizon - bT + step) / horizon end
                if bClear and bClear < rules.floor * 2 then cost = cost + (rules.floor * 2 - bClear) * 0.3 end
                if cost < bestCost then best, bestCost, bestInfo = d, cost, { dh = dy, dc = dc, bad = bT, why = bWhy, clear = bClear } end
            end
        end
        if not best then return aim, "no way found" end
        if not N.last or N.last.dh ~= bestInfo.dh then N.stats.changed = N.stats.changed + 1 end
        N.last = { d = best, dh = bestInfo.dh, dc = bestInfo.dc, why = why, clear = bestInfo.clear, bad = bestInfo.bad }
        local text = string.format("%s ahead in %.1f s: steering %+d deg, climb %+d deg%s", why, badT, bestInfo.dh, bestInfo.dc,
            bestInfo.bad and string.format(" (still %s in %.1f s)", bestInfo.why, bestInfo.bad) or "")
        return best, text
    end

    -- Squares to measure ahead: along the present path (urgent) and a fan of directions
    -- out to 'range' (game units), so the choices above find the ground already known.
    function N.scanAhead(p, v, range)
        local u, s = unit({ v[1], v[2], 0 })
        if s < 100 then return end
        local h = math.atan(u[2], u[1])
        for i = 1, 8 do
            local q = add(p, mul(v, i * 0.75))
            N.ask(q[1], q[2], true)
        end
        for _, dy in ipairs({ 0, -12, 12, -25, 25, -40, 40, -60, 60, -90, 90 }) do
            local a = h + math.rad(dy)
            for r = N.CELL, range, N.CELL * 1.5 do
                N.ask(p[1] + math.cos(a) * r, p[2] + math.sin(a) * r, false)
            end
        end
    end

    -- ---- 4. a route around high ground (A* on the height map) ----------------------------
    -- Open squares: where the highest thing (and its neighbours') leaves 'room' (game units)
    -- below the ceiling. Unknown squares count as open but cost a little more, and the
    -- squares along the found route are asked for first, so the route corrects itself as
    -- the ground gets measured. Returns a list of {x, y} way points (square centres), or nil.
    function N.plan(from, goal, ceiling, room, maxNodes)
        local CELL = N.CELL * 2               -- the planner works on 200 m squares
        local function cell(x, y) return math.floor(x / CELL), math.floor(y / CELL) end
        local function blocked(ix, iy)
            -- the highest of the four 100 m squares inside
            local worst, known = nil, false
            for a = 0, 1 do
                for b = 0, 1 do
                    local v = H[key(ix * 2 + a, iy * 2 + b)]
                    if v ~= nil then known = true; local z = v or N.SEA; if not worst or z > worst then worst = z end end
                end
            end
            if not known then return false, false end
            return worst + room > ceiling, true
        end
        local sx, sy = cell(from[1], from[2])
        local gx, gy = cell(goal[1], goal[2])
        local function h(ix, iy) return math.sqrt((ix - gx) ^ 2 + (iy - gy) ^ 2) end
        local open = { { sx, sy, 0, h(sx, sy) } }
        local came, gcost = {}, { [key(sx, sy)] = 0 }
        local closed = {}
        local n = 0
        local found = nil
        maxNodes = maxNodes or 6000
        while #open > 0 and n < maxNodes do
            -- the cheapest open node (a plain list: fine for a few thousand nodes)
            local bi, bf = 1, math.huge
            for i, o in ipairs(open) do if o[3] + o[4] < bf then bi, bf = i, o[3] + o[4] end end
            local cur = table.remove(open, bi)
            local ck = key(cur[1], cur[2])
            if not closed[ck] then
                closed[ck] = true
                n = n + 1
                if (cur[1] == gx and cur[2] == gy) or h(cur[1], cur[2]) < 1.5 then found = cur; break end
                for dx = -1, 1 do
                    for dy = -1, 1 do
                        if dx ~= 0 or dy ~= 0 then
                            local nx, ny = cur[1] + dx, cur[2] + dy
                            local nk = key(nx, ny)
                            if not closed[nk] then
                                local bl, known = blocked(nx, ny)
                                if not bl then
                                    local step = (dx ~= 0 and dy ~= 0) and 1.414 or 1
                                    if not known then step = step * 1.3 end
                                    local g = cur[3] + step
                                    if not gcost[nk] or g < gcost[nk] then
                                        gcost[nk] = g
                                        came[nk] = ck
                                        open[#open + 1] = { nx, ny, g, h(nx, ny) }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if not found then return nil, n end
        -- walk back
        local route = {}
        local k = key(found[1], found[2])
        local guard = 0
        while k and guard < 100000 do
            guard = guard + 1
            local ix = math.floor(k / 2000000) - 1000000
            local iy = k % 2000000 - 1000000
            table.insert(route, 1, { (ix + 0.5) * CELL, (iy + 0.5) * CELL })
            k = came[k]
        end
        for _, w in ipairs(route) do N.ask(w[1], w[2], false) end
        return route, n
    end

    -- Fill the height map from a survey file (the "survey" order's CSV: x, y, z), at the
    -- survey's own spacing ('cell', game units). Squares already known keep the higher value.
    function N.loadSurvey(path, cell)
        local f = io.open(path, "r")
        if not f then return nil, "cannot open " .. tostring(path) end
        if cell and cell ~= N.CELL then
            -- a new square size: what was measured at the old size no longer fits
            for k in pairs(H) do H[k] = nil end
            for k in pairs(Hfar) do Hfar[k] = nil end
            want, wantSet = {}, {}
            N.cells = 0
            N.CELL = cell
        end
        f:read("l")
        local n = 0
        for line in f:lines() do
            local x, y, z = line:match("^([^,]*),([^,]*),([^,]*)")
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            if x and y then
                local ix, iy = cellOf(x + 1, y + 1)
                local k = key(ix, iy)
                local v = z or false
                local old = H[k]
                if old == nil then N.cells = N.cells + 1; H[k] = v
                elseif v and (old == false or v > old) then H[k] = v end
                n = n + 1
            end
        end
        f:close()
        return n
    end

    function N.describe()
        return string.format("height map %d squares of %.0f m%s (%d waiting), %d %straces so far, %.3f ms each%s",
            N.cells, N.CELL / 10, N.precise and ", precise" or "", #want, N.traces, N.fast and "fast (C++) " or "", N.traces > 0 and N.traceMs / N.traces or 0, N.traceError and (", last trace error: " .. N.traceError) or "")
    end

    return N
end
