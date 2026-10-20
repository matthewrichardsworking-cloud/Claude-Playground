-- gunnery.lua: the gun against ground targets (CoopPilotMod, 20 Oct 2026; the Mission 06
-- ammunition work, playtests\missions\m06\gap-analysis.md).
--
-- A player kills trucks and guns with the gun and keeps the missiles for what the gun cannot
-- reach. The gun needs the nose on the target within a few degrees inside about a kilometre,
-- which the missile attack runs never give (they stay 300 m up and dive no steeper than 25
-- degrees, so a target 1 km out sits 10-15 degrees below the nose). So a strafing pass of its
-- own: in low and nearly level, the nose on the target for the last stretch, fire, break off
-- early enough to clear the ground, out and back for the next pass.
--
-- Nothing here is level-specific: the target, the ground (the terrain sensor's height above
-- the ground) and the gun's numbers come in live. Loaded again in flight with "module gunnery".

return function(env)
    local G = {}

    G.P = {
        inAgl = 130,         -- m above the ground for the run-in
        aimFrom = 1600,      -- m: inside this the nose goes straight at the target
        lowFrom = 6000,      -- m: inside this the run-in is flown low (the pass's own floor)
        fireRange = 1200,    -- m: fire inside this ...
        fireOff = 3.0,       -- deg: ... with the target this close to the nose
        aimUp = 2.0,         -- m above the target's origin to aim at (its middle, not its base)
        breakAt = 450,       -- m: break off the pass here
        minAgl = 45,         -- m: break off below this height above the ground
        outTo = 2800,        -- m: after a pass, out this far before turning back
        outAgl = 250,        -- m above the ground on the way out
        offAbort = 35,       -- deg: a target this far off the nose inside aimFrom ends the pass
        floor = 50,          -- m: the safety floor while in a pass (the order's is 300)
        aheadMin = 10,       -- m: the clearance wanted over the ground ahead while in a pass
        kmh = 600,           -- km/h inside 3.5 km: more time with the target in reach
    }

    local sqrt, deg, acos = math.sqrt, math.deg, math.acos
    local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
    local function unit(v)
        local l = sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
        if l < 1e-9 then return { 0, 0, 0 }, 0 end
        return { v[1] / l, v[2] / l, v[3] / l }, l
    end

    -- One strafing pass at a ground object at st (game units; X, Y, Z) from the plane at loc
    -- with the nose along F, 'above' metres above the ground. c.gunRuns keeps each target's
    -- phase ("in" or "out"). Returns the aim, the phase, the distance (m), and whether the
    -- plane is in the low part of a pass (the safety floor is lowered then).
    function G.run(c, key, st, loc, F, above)
        local P = G.P
        c.gunRuns = c.gunRuns or {}
        local dx, dy, dz = st.X - loc.X, st.Y - loc.Y, st.Z + P.aimUp * 10 - loc.Z
        local hd = sqrt(dx * dx + dy * dy)
        local dm = sqrt(hd * hd + dz * dz) / 10
        local h = { dx / math.max(hd, 1), dy / math.max(hd, 1) }
        local Fh = unit({ F[1], F[2], 0 })
        local offH = deg(acos(clamp(h[1] * Fh[1] + h[2] * Fh[2], -1, 1)))
        local run = c.gunRuns[key]
        if not run then run = (dm < P.outTo and offH > 30) and "out" or "in" end
        if run == "in" and (dm < P.breakAt or (dm < P.aimFrom and offH > P.offAbort) or (above < P.minAgl and dm < P.aimFrom)) then run = "out" end
        if run == "out" and dm > P.outTo then run = "in" end
        if run ~= c.gunRuns[key] and env.event then
            env.event("gun_pass", { target = key, phase = run == "in" and "running in" or "breaking off", dist_m = dm, off_deg = offH, agl_m = above })
        end
        c.gunRuns[key] = run
        if run == "out" then
            -- away and up a little; straight on first if the target is already behind
            local away = offH > 90 and Fh or { -h[1], -h[2] }
            return unit({ away[1], away[2], clamp((P.outAgl - above) / 1000, -0.2, 0.35) }), run, dm, false
        end
        if dm > P.aimFrom then
            return unit({ h[1], h[2], clamp((P.inAgl - above) / 800, -0.25, 0.25) }), run, dm, dm < P.lowFrom
        end
        return unit({ dx, dy, dz }), run, dm, true
    end

    -- Fire the gun now? (distance in m, angle off the nose in degrees)
    function G.fire(dm, off)
        return dm < G.P.fireRange and off < G.P.fireOff
    end

    -- Zeroing: where the bullets have gone on average, as angles off the line to the target
    -- (rad; + = above, + = right), learned from the bullet measurement below. The aim of a gun
    -- burst is moved the other way.
    G.zero = { up = 0, right = 0, n = 0 }
    local function learnZero(upM, rightM, distM, n)
        if not distM or distM < 200 or n < 3 then return end
        local Z = G.zero
        local w = math.min(n, 20)
        Z.up = (Z.up * Z.n + (upM / distM) * w) / (Z.n + w)
        Z.right = (Z.right * Z.n + (rightM / distM) * w) / (Z.n + w)
        Z.n = math.min(Z.n + w, 200)
    end

    -- The point to aim the nose at for a gun burst at a target at tp (game units), from the
    -- plane at me: the target's middle, moved against the learned bullet offsets.
    local function gunAimPoint(tp, me)
        local P, Z = G.P, G.zero
        local q = { tp[1], tp[2], tp[3] + P.aimUp * 10 }
        local los = { q[1] - me[1], q[2] - me[2], q[3] - me[3] }
        local d = sqrt(los[1] ^ 2 + los[2] ^ 2 + los[3] ^ 2)
        if d < 1 or Z.n == 0 then return q, d end
        local fa = { los[1] / d, los[2] / d, los[3] / d }
        local r = { fa[2], -fa[1], 0 }                      -- right of the line (level)
        local rl = sqrt(r[1] ^ 2 + r[2] ^ 2)
        if rl < 1e-6 then return q, d end
        r = { r[1] / rl, r[2] / rl, 0 }
        local u = { r[2] * fa[3] - 0, -(r[1] * fa[3]), r[1] * fa[2] - r[2] * fa[1] }   -- up = r x fa
        return { q[1] - (u[1] * Z.up + r[1] * Z.right) * d, q[2] - (u[2] * Z.up + r[2] * Z.right) * d,
                 q[3] - (u[3] * Z.up + r[3] * Z.right) * d }, d
    end

    -- A gun "snap" while the lanes are flown (20 Oct 2026): a target the gun can kill (its
    -- health no more than snapHp) nearly on the nose, inside the gun's reach and not too far
    -- below, gets a short burst with the nose put exactly on it, while the missiles do their
    -- own work. cands: { { obj, x, y, z, hp, name }, ... }. Returns the aim and whether to fire
    -- (and the snap's target), or nil when there is nothing to snap at.
    G.P.snapHp = 40          -- health a snap target may have
    G.P.snapFrom = 1150      -- m
    G.P.snapTo = 450         -- m: no nearer (the pull-out)
    G.P.snapOff = 10         -- deg off the nose at most to start
    G.P.snapDive = 16        -- deg below the horizon at most
    G.P.snapFor = 2.5        -- s at most on one target
    G.P.snapFireOff = 1.5    -- deg: fire inside this
    G.P.snapMinAgl = 70      -- m above the ground
    function G.snap(c, t, loc, F, cands, above)
        local P = G.P
        if (above or 0) < P.snapMinAgl then c.snapT = nil; return nil end
        local cur = c.snapT
        if cur and (t - cur.t0 > P.snapFor or not cur.alive()) then
            c.snapRest = t + 1.0
            c.snapT = nil
            cur = nil
        end
        if not cur then
            if c.snapRest and t < c.snapRest then return nil end
            local best, bestOff = nil, P.snapOff
            for _, q in ipairs(cands) do
                if (q.hp or 99) <= P.snapHp then
                    local dx, dy, dz = q.x - loc.X, q.y - loc.Y, q.z - loc.Z
                    local d = sqrt(dx * dx + dy * dy + dz * dz)
                    local dm = d / 10
                    if dm < P.snapFrom and dm > P.snapTo then
                        local off = deg(acos(clamp((dx * F[1] + dy * F[2] + dz * F[3]) / d, -1, 1)))
                        local below = deg(math.asin(clamp(-dz / d, -1, 1)))
                        if off < bestOff and below < P.snapDive then best, bestOff = q, off end
                    end
                end
            end
            if not best then return nil end
            cur = { q = best, t0 = t, alive = best.alive or function() return true end }
            c.snapT = cur
            if env.event then env.event("gun_snap", { target = best.name, off_deg = bestOff, hp = best.hp or -1 }) end
        end
        local q = cur.q
        local okL, l = pcall(function() return q.obj:K2_GetActorLocation() end)
        if not okL or not l then c.snapT = nil; return nil end
        local ap_, d = gunAimPoint({ l.X, l.Y, l.Z }, { loc.X, loc.Y, loc.Z })
        local dm = d / 10
        if dm < P.snapTo then c.snapT = nil; c.snapRest = t + 1.0; return nil end
        local aim = unit({ ap_[1] - loc.X, ap_[2] - loc.Y, ap_[3] - loc.Z })
        local off = deg(acos(clamp(aim[1] * F[1] + aim[2] * F[2] + aim[3] * F[3], -1, 1)))
        return aim, off < P.snapFireOff and dm < P.fireRange, q
    end

    -- Where the bullets go (a measurement): the pilot's own bullets are game objects (the gun's
    -- class, plwp_gun_x1_C in the Typhoon; the game reuses them), so during a burst at a target
    -- and 1.5 s after, ten times a second, each moving bullet's path is checked against the
    -- target: how close it passed, and where (above or below, left or right, short or beyond,
    -- in metres, in the frame of the line from the plane to the target). Reported per burst as
    -- a "gun_bullets" event. Called every fight frame by main.lua (G.tick).
    local W = { at = -100 }
    local function sub3(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function dot3(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross3(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    function G.tick(c, t, tgt, loc, firing, gunClass)
        if firing and tgt then
            local okL, tl = pcall(function() return tgt:K2_GetActorLocation() end)
            if okL and tl then
                if not W.burst then W.burst = { b = {}, t0 = t, name = c.targetName, aimUp = G.P.aimUp } end
                W.burst.tp = { tl.X, tl.Y, tl.Z + G.P.aimUp * 10 }
                W.burst.base = { tl.X, tl.Y, tl.Z }
                W.burst.me = { loc.X, loc.Y, loc.Z }
                W.burst.last = t
            end
        end
        local B = W.burst
        if not B then return end
        if t - B.last > 1.5 then
            -- report: the closest passes of the bullets that came within 60 m
            local n, sumUp, sumRight, sumAlong, within5, misses, speeds = 0, 0, 0, 0, 0, {}, {}
            for _, b in pairs(B.b) do
                if b.best and b.best < 600 then
                    n = n + 1
                    sumUp, sumRight, sumAlong = sumUp + b.up, sumRight + b.right, sumAlong + b.along
                    if b.best < 50 then within5 = within5 + 1 end
                    misses[#misses + 1] = b.best
                end
                if b.speed then speeds[#speeds + 1] = b.speed end
            end
            table.sort(misses); table.sort(speeds)
            if n > 0 and B.me and B.tp then
                local dd = sqrt((B.tp[1] - B.me[1]) ^ 2 + (B.tp[2] - B.me[2]) ^ 2 + (B.tp[3] - B.me[3]) ^ 2) / 10
                learnZero(sumUp / n / 10, sumRight / n / 10, dd, n)
            end
            if env.event then
                env.event("gun_bullets", { target = B.name, bullets = n, within_5m = within5, aim_up_m = B.aimUp,
                    miss_median_m = misses[1] and misses[math.floor(#misses / 2) + 1] / 10 or -1,
                    up_m = n > 0 and sumUp / n / 10 or 0, right_m = n > 0 and sumRight / n / 10 or 0, along_m = n > 0 and sumAlong / n / 10 or 0,
                    speed_ms = speeds[1] and speeds[math.floor(#speeds / 2) + 1] / 10 or -1, seen = #speeds,
                    zero_up_deg = math.deg(G.zero.up), zero_right_deg = math.deg(G.zero.right) })
            end
            W.burst = nil
            return
        end
        if t - W.at < 0.1 then return end
        W.at = t
        local okF, objs = pcall(function() return FindAllOf(gunClass or "plwp_gun_x1_C") or {} end)
        if not okF then return end
        -- the frame: along the line from the plane to the target, right of it, and up
        local los = sub3(B.tp, B.me)
        local ll = math.sqrt(dot3(los, los))
        if ll < 1 then return end
        local fa = { los[1] / ll, los[2] / ll, los[3] / ll }
        local rr = cross3(fa, { 0, 0, 1 })
        local rl = math.sqrt(dot3(rr, rr))
        if rl < 1e-6 then return end
        rr = { rr[1] / rl, rr[2] / rl, rr[3] / rl }
        local up = cross3(rr, fa)
        for _, o in ipairs(objs) do
            local okN, name = pcall(function() return o:GetFName():ToString() end)
            local okP, l = pcall(function() return o:K2_GetActorLocation() end)
            if okN and okP and l then
                local p = { l.X, l.Y, l.Z }
                local b = B.b[name]
                if not b then b = {}; B.b[name] = b end
                if b.p and b.t and t > b.t then
                    local seg = sub3(p, b.p)
                    local sl = math.sqrt(dot3(seg, seg))
                    -- (a bullet in flight goes away from the plane toward the target at a sane
                    -- speed; a jump of a reused bullet back to the gun is neither)
                    local sp = sl / (t - b.t)
                    if sl > 300 and sp < 30000 and dot3(seg, fa) > 0.8 * sl then
                        b.speed = sp
                        -- the closest point of this stretch of its path to the target
                        local k = math.max(0, math.min(1, dot3(sub3(B.tp, b.p), seg) / (sl * sl)))
                        local q = { b.p[1] + seg[1] * k, b.p[2] + seg[2] * k, b.p[3] + seg[3] * k }
                        local off = sub3(q, B.tp)
                        local dd = math.sqrt(dot3(off, off))
                        if not b.best or dd < b.best then
                            b.best, b.up, b.right, b.along = dd, dot3(off, up), dot3(off, rr), dot3(off, fa)
                        end
                    end
                end
                b.p, b.t = p, t
            end
        end
    end

    return G
end
