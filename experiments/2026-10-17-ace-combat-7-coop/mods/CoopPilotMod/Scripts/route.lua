-- route.lua: following a planned route (CoopPilotMod, phase 3, 18 Oct 2026)
--
-- A route is a list of way points (x, y, z in game units, a speed in km/h, the corridor's
-- width in metres), planned outside the game by tools\route-plan.py from the pilot's own
-- terrain survey. Following it works like a driver looking down the road: find where on
-- the route the plane is now, pick the point a little way further along (farther at speed),
-- and steer at that point. The speed for the stretch ahead comes from the route (lower for
-- tight bends), and the plane's sideways distance from the route is logged so a session
-- can see how well it held the line.

return function(env)
    local log, event, now = env.log, env.event, env.now
    local R = {}

    function R.load(path)
        local f = io.open(path, "r")
        if not f then return nil, "cannot open " .. tostring(path) end
        local header = f:read("l")
        local cols = {}
        local i = 0
        for name in (header or ""):gmatch("[^,]+") do i = i + 1; cols[name] = i end
        if not (cols.x and cols.y and cols.z) then f:close(); return nil, "no x, y, z columns" end
        local pts = {}
        for line in f:lines() do
            local v = {}
            for cell in (line .. ","):gmatch("([^,]*),") do v[#v + 1] = cell end
            local x, y, z = tonumber(v[cols.x]), tonumber(v[cols.y]), tonumber(v[cols.z])
            if x and y and z then
                pts[#pts + 1] = { x, y, z, kmh = cols.kmh and tonumber(v[cols.kmh]) or nil, lit = cols.lit and v[cols.lit] == "1" or false,
                                  width = cols.width_m and tonumber(v[cols.width_m]) or nil }
            end
        end
        f:close()
        if #pts < 2 then return nil, "fewer than two way points" end
        -- each point's sideways direction (unit, to the left of the route), for wall checks
        for k = 1, #pts do
            local a, b = pts[math.max(1, k - 1)], pts[math.min(#pts, k + 1)]
            local dx, dy = b[1] - a[1], b[2] - a[2]
            local l = math.sqrt(dx * dx + dy * dy)
            if l > 0 then pts[k].px, pts[k].py = -dy / l, dx / l end
        end
        local s = 0
        pts[1].s = 0
        for k = 2, #pts do
            local a, b = pts[k - 1], pts[k]
            s = s + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            b.s = s
        end
        return { pts = pts, length = s, idx = 1, name = path:match("([^\\/]+)$") or path }
    end

    -- the point at along-route distance s (game units), interpolated
    local function at(rt, s)
        local pts = rt.pts
        if s <= 0 then return { pts[1][1], pts[1][2], pts[1][3] }, 1 end
        if s >= rt.length then local p = pts[#pts]; return { p[1], p[2], p[3] }, #pts end
        local k = rt.idx
        while k > 1 and pts[k].s > s do k = k - 1 end
        while k < #pts - 1 and pts[k + 1].s < s do k = k + 1 end
        local a, b = pts[k], pts[k + 1]
        local u = (s - a.s) / math.max(b.s - a.s, 1)
        return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u }, k
    end
    R.at = at

    -- Where the plane is along the route: the nearest point on the segments near the last
    -- known place. Returns along-route distance, sideways error (game units, + = right of
    -- the route), segment index.
    function R.locate(rt, p)
        local pts = rt.pts
        local best, bestD, bestS, bestSide = rt.idx, math.huge, 0, 0
        local lo, hi = math.max(1, rt.idx - 3), math.min(#pts - 1, rt.idx + 40)
        if rt.lost then lo, hi = 1, #pts - 1 end
        for k = lo, hi do
            local a, b = pts[k], pts[k + 1]
            local dx, dy = b[1] - a[1], b[2] - a[2]
            local L2 = dx * dx + dy * dy
            local u = L2 > 0 and ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / L2 or 0
            if u < 0 then u = 0 elseif u > 1 then u = 1 end
            local qx, qy = a[1] + dx * u, a[2] + dy * u
            local d = (p[1] - qx) ^ 2 + (p[2] - qy) ^ 2
            if d < bestD then
                local side = (dx * (p[2] - a[2]) - dy * (p[1] - a[1])) >= 0 and 1 or -1
                best, bestD, bestS, bestSide = k, d, a.s + math.sqrt(L2) * u, side
            end
        end
        rt.idx = best
        local err = math.sqrt(bestD)
        rt.lost = err > 30000            -- more than 3 km off: search the whole route next time
        return bestS, err * bestSide, best
    end

    -- The aim for this frame: a unit vector toward the point 'look' (game units) further
    -- along the route, the speed wanted for the stretch ahead, and the progress.
    function R.steer(rt, p, speedUps)
        local s, side, k = R.locate(rt, p)
        local look = math.max(2000, math.min(5000, (speedUps or 1500) * 1.6))
        -- sideways: steer at the point 'look' ahead; up and down: follow the height profile
        -- only 150 m ahead (looking further cuts a dip short, and a dip in the profile is
        -- usually there to pass under a searchlight's sweep: 18 Oct 2026, Mission 14 Hard)
        local tp, tk = at(rt, s + look)
        -- a sideways shift asked for by the beam planner (rt.dy, game units, + = left)
        if rt.dy and rt.dy ~= 0 and rt.pts[tk] and rt.pts[tk].px then
            tp = { tp[1] + rt.pts[tk].px * rt.dy, tp[2] + rt.pts[tk].py * rt.dy, tp[3] }
        end
        local d = { tp[1] - p[1], tp[2] - p[2] }
        local horiz = math.max(math.sqrt(d[1] ^ 2 + d[2] ^ 2), 1)
        local zp = at(rt, s + 1500)
        local climb = (zp[3] + (rt.dz or 0) - p[3]) / 1500
        if climb > 0.35 then climb = 0.35 elseif climb < -0.35 then climb = -0.35 end
        local cg = 1 / math.sqrt(1 + climb * climb)
        local aim = { d[1] / horiz * cg, d[2] / horiz * cg, climb * cg }
        -- the slowest speed asked for over the next 1.5 km
        local kmh = nil
        local pts = rt.pts
        for j = k, #pts do
            if pts[j].s > s + 15000 then break end
            if pts[j].kmh and (not kmh or pts[j].kmh < kmh) then kmh = pts[j].kmh end
        end
        local here = at(rt, s)
        rt.s, rt.side, rt.zWanted = s, side, here[3]
        rt.done = s >= rt.length - 1500
        return aim, kmh, s / rt.length, side
    end

    -- The stretches ahead (within 'range' game units) where every height is inside some
    -- searchlight's sweep (the planner's 'lit' column): the pilot has to time those. Returns
    -- a list of { s0, s1, pts = {points} } with along-route distances.
    function R.litAhead(rt, range)
        local out, cur = {}, nil
        local s = rt.s or 0
        for j = rt.idx, #rt.pts do
            local q = rt.pts[j]
            if q.s > s + range then break end
            if q.s >= s and q.lit then
                if cur and q.s - cur.s1 <= 1200 then
                    cur.s1 = q.s; cur.pts[#cur.pts + 1] = q
                else
                    cur = { s0 = q.s, s1 = q.s, pts = { q } }
                    out[#out + 1] = cur
                end
            end
        end
        return out
    end

    return R
end
