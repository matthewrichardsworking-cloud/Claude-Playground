-- awareness.lua: the pilot's picture of the fight (CoopPilotMod, phase 2, 18 Oct 2026)
--
-- Tracks every enemy plane and every missile in the air, with their recent history, and
-- turns it into predictions the pilot acts on:
--   * each enemy's flight limits and behaviour, read from the game itself: top and lowest
--     speed, turn speed and acceleration (AIPlane:GetMaxSpeed/GetMinSpeed/GetTurnSpeed/
--     GetAccelerationMpss), its AI state (EAIState: pursuing, evading, escaping a pursuer,
--     following its formation...), who it is tracking, and for planes that fly a scripted
--     route the route itself (AIPathComp > SplineComponent);
--   * where an enemy will be in t seconds: along its scripted route if it is on one,
--     otherwise a steady turn at the turn rate it is showing now, capped at its turn limit;
--   * every missile homing on the player: its speed, turn limit, fuse and warning radii
--     (the Missile class: SpeedMaximum, Acceleration, MaxRotationAngle, ...), time to
--     impact, predicted miss distance, and whether it can still turn enough to hit;
--   * the player's own weapons: lock-on range and angle, multi-lock count, damage and
--     reload time of the main and special weapon, from their class defaults (the values
--     the game loaded from its data files; nothing is unpacked from the game files).
-- Units: game units are 10 cm; speeds here are in game units per second unless the name
-- says km/h or m/s.

return function(env)
    local log, event, now, call, objName, callsign = env.log, env.event, env.now, env.call, env.objName, env.callsign
    local A = {}

    local AI_STATE = { [0] = "ReturnToWorld", "AvoidObstacle", "ReturnToUnit", "SpecialAction", "AttackAvoidance",
                       "EscapeFromPursuer", "Provoke", "MoveAwayFromTarget", "PursueTarget", "FollowFormation", "Patrol", "Idle" }
    local HOMING = { [0] = "active radar", "infrared", "semi-active" }
    local TARGET_TYPE = { [0] = "air and ground", "air only", "ground only", "special only" }
    A.AI_STATE = AI_STATE

    -- small vector helpers (tables {x, y, z})
    local function v3(l) return { l.X, l.Y, l.Z } end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
    local function mul(a, k) return { a[1] * k, a[2] * k, a[3] * k } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function unit(a) local l = len(a); if l < 1e-9 then return { 0, 0, 0 }, 0 end; return mul(a, 1 / l), l end
    A.vec = { v3 = v3, sub = sub, add = add, mul = mul, dot = dot, cross = cross, len = len, unit = unit }

    local function valid(o)
        local ok, v = pcall(function() return o and o:IsValid() end)
        return ok and v
    end
    local function prop(o, name)
        -- IsValid first (safe on a freed object; reading a freed object crashes the game)
        local ok, v = pcall(function() if not o:IsValid() then return nil end; return o[name] end)
        if ok then return v end
        return nil
    end
    local function num(o, name)
        local v = prop(o, name)
        return type(v) == "number" and v or nil
    end
    local function fullName(o)
        local ok, n = pcall(function() return o:GetFullName() end)
        return ok and n or nil
    end

    -- Class defaults: the values a weapon or plane class carries before anything changes them.
    local function defaults(cls)
        if not valid(cls) then return nil end
        local ok, cdo = pcall(function() return cls:GetCDO() end)
        if ok and valid(cdo) then return cdo end
        return nil
    end

    -- ---- the player's weapons -----------------------------------------------------
    local WEAPON_FIELDS = { "LockonRange", "LockonAngle", "MultipleLockOnMaxNum", "Damage", "LoadTime", "LifeTime",
                            "SpeedMaximum", "Acceleration", "MaxRotationAngle", "MaxHomingAngle", "HomingDelayFromStart",
                            "ProximityFuseRadiusSquared", "MaxLoadedCount" }
    local function weaponInfo(cls)
        local d = defaults(cls)
        if not d then return nil end
        local w = { class = objName(cls) }
        for _, f in ipairs(WEAPON_FIELDS) do w[f] = num(d, f) end
        w.multi = prop(d, "bMultipleLockOn") == true
        local tt = num(d, "LockOnTargetType")
        w.targets = tt and TARGET_TYPE[tt] or "?"
        w.homing = prop(d, "bIsHoming") == true
        return w
    end

    A.weapons = nil
    function A.readWeapons(wa)
        if not valid(wa) then return nil end
        A.weapons = {
            main = weaponInfo(prop(wa, "MainWeaponClass")),
            special = weaponInfo(prop(wa, "SpecialWeaponClass")),
            gun = weaponInfo(prop(wa, "MachineGunClass")),
        }
        return A.weapons
    end

    -- ---- tracks -----------------------------------------------------------------------
    -- A track keeps a short history of positions and works out velocity and turn rate.
    local tracks = {}          -- full name -> track
    A.tracks = tracks
    -- Forget every game object (a restart from a checkpoint replaces them all; the old ones
    -- are freed about a minute later, and touching one then crashes the game).
    function A.reset()
        for k in pairs(tracks) do tracks[k] = nil end
        A.threats = {}
        for _, tr in ipairs(A.missileLog or {}) do tr.obj = nil end
    end
    local HISTORY = 12

    local function newTrack(o, kind)
        return { obj = o, kind = kind, name = objName(o), hist = {}, v = nil, w = { 0, 0, 0 }, seenAt = now(), info = nil }
    end

    local function addSample(tr, t, p)
        local h = tr.hist
        local last = h[#h]
        if last and t - last.t < 0.02 then return end
        h[#h + 1] = { t = t, p = p }
        if #h > HISTORY then table.remove(h, 1) end
        if #h >= 2 then
            local a, b = h[#h - 1], h[#h]
            local dt = b.t - a.t
            if dt > 0 then
                local v = mul(sub(b.p, a.p), 1 / dt)
                if tr.v then
                    -- turn rate (rad/s, as a vector along the turn axis) from the change in direction
                    local u1, s1 = unit(tr.v)
                    local u2, s2 = unit(v)
                    if s1 > 50 and s2 > 50 then
                        local c = cross(u1, u2)
                        local sinA = len(c)
                        local cosA = dot(u1, u2)
                        local ang = math.atan(sinA, cosA)
                        local w = sinA > 1e-6 and mul(c, ang / sinA / dt) or { 0, 0, 0 }
                        tr.w = mul(add(mul(tr.w, 0.7), mul(w, 0.3)), 1)
                    end
                    tr.v = add(mul(tr.v, 0.5), mul(v, 0.5))
                else
                    tr.v = v
                end
            end
        end
        tr.p = p
        tr.t = t
    end

    -- Where a track will be in dt seconds if it keeps turning as it is now (turn capped at
    -- maxTurn rad/s). Closed form for a steady turn: p + sin(a)/w * v + (1-cos(a))/w * (w^ x v).
    local function predictTurn(p, v, w, dt, maxTurn)
        local wu, wl = unit(w)
        if maxTurn and wl > maxTurn then wl = maxTurn end
        if wl < 1e-4 then return add(p, mul(v, dt)) end
        local a = wl * dt
        local wxv = cross(wu, v)
        return add(p, add(mul(v, math.sin(a) / wl), mul(wxv, (1 - math.cos(a)) / wl)))
    end
    A.predictTurn = predictTurn

    -- ---- enemies ----------------------------------------------------------------------
    local function enemyInfo(o)
        local info = {
            maxKmh = call(o, "GetMaxSpeed"), minKmh = call(o, "GetMinSpeed"),
            turn = call(o, "GetTurnSpeed"), accel = call(o, "GetAccelerationMpss"),
            large = prop(o, "bIsLargePlane") == true, aiLevel = num(o, "AILevel"),
            tgt = call(o, "IsTGT") == true,
        }
        -- the scripted route, if the plane has one
        local pc = prop(o, "AIPathComp")
        local spline = valid(pc) and prop(pc, "SplineComponent") or nil
        if valid(spline) then
            info.spline = spline
            info.splineLength = call(spline, "GetSplineLength")
        end
        return info
    end

    local function enemyState(tr)
        local o = tr.obj
        local s = num(o, "CurrentRunningState")
        tr.state = s and AI_STATE[s] or "?"
        local tt = call(o, "GetTrackingTarget")
        tr.tracking = tt and objName(tt) or nil
    end

    -- Position along the scripted route dt seconds ahead, at the plane's current speed.
    local function predictOnSpline(tr, dt)
        local sp = tr.info and tr.info.spline
        if not valid(sp) or not tr.info.splineLength or tr.info.splineLength <= 0 then return nil end
        local okK, key = pcall(function() return sp:FindInputKeyClosestToWorldLocation({ X = tr.p[1], Y = tr.p[2], Z = tr.p[3] }) end)
        if not okK or type(key) ~= "number" then return nil end
        local i0 = math.floor(key)
        local d0 = call(sp, "GetDistanceAlongSplineAtSplinePoint", i0)
        local d1 = call(sp, "GetDistanceAlongSplineAtSplinePoint", i0 + 1)
        if not d0 then return nil end
        local here = d0 + ((d1 or d0) - d0) * (key - i0)
        -- how far off the route the plane is: if it has left the route, the route says nothing
        local okL, onRoute = pcall(function() return sp:GetLocationAtDistanceAlongSpline(here, 1) end)   -- 1 = world space
        if not okL or not onRoute then return nil end
        local off = len(sub(v3(onRoute), tr.p))
        if off > 3000 then return nil end                        -- more than 300 m away from it
        local speed = tr.v and len(tr.v) or 0
        local okP, at = pcall(function() return sp:GetLocationAtDistanceAlongSpline(math.min(here + speed * dt, tr.info.splineLength), 1) end)
        if not okP or not at then return nil end
        return add(v3(at), sub(tr.p, v3(onRoute))), off
    end

    -- The best guess of where an enemy will be in dt seconds, and how it was made.
    -- The ways of guessing, by the kind of flying: a plane on its scripted route, a plane
    -- turning (more than about 1 degree a second), a plane flying steadily. Every guess is
    -- scored when it falls due (see updateEnemies) and the one with the smallest running
    -- error is used: the predictor picks its own method from what the enemies actually do.
    local VARIANTS = { route = { "route", "straight" }, turning = { "straight", "half turn", "full turn" },
                       steady = { "straight", "half turn", "full turn" } }
    A.ema = {}                -- running error per kind of flying and way of guessing (game units)
    local function flyingKind(tr)
        if tr.info and tr.info.spline and (tr.state == "FollowFormation" or tr.state == "Patrol"
            or tr.state == "ReturnToUnit" or tr.state == "Idle") then return "route" end
        return len(tr.w) > 0.02 and "turning" or "steady"
    end
    local function guess(tr, dt, how)
        if how == "straight" then return add(tr.p, mul(tr.v, dt)) end
        if how == "route" then return predictOnSpline(tr, dt) end
        local k = how == "half turn" and 0.5 or 1.0
        local maxTurn = tr.info and tr.info.turn and math.rad(tr.info.turn) or nil
        return predictTurn(tr.p, tr.v, mul(tr.w, k), dt, maxTurn)
    end
    local function bestWay(kind)
        local e = A.ema[kind]
        local default = kind == "route" and "route" or "straight"
        if not e then return default end
        local best, bestErr = default, e[default] or math.huge
        for how, err in pairs(e) do
            if err < bestErr then best, bestErr = how, err end
        end
        return best
    end
    A.bestWay = bestWay

    function A.predict(tr, dt)
        if not tr or not tr.p then return nil, "no data" end
        if not tr.v then return tr.p, "still" end
        local kind = flyingKind(tr)
        local how = bestWay(kind)
        local p = guess(tr, dt, how)
        if not p then how = "straight"; p = add(tr.p, mul(tr.v, dt)) end
        return p, kind .. ": " .. how
    end

    -- When a projectile leaving 'from' at 'speed' (units/s) would meet the target, and where.
    function A.intercept(tr, from, speed, maxT)
        local t = len(sub(tr.p, from)) / math.max(speed, 1)
        local p = tr.p
        for _ = 1, 4 do
            p = A.predict(tr, t) or tr.p
            local nt = len(sub(p, from)) / math.max(speed, 1)
            if math.abs(nt - t) < 0.01 then t = nt; break end
            t = nt
            if maxT and t > maxT then break end
        end
        return p, t
    end

    local enemyScanAt = -100
    function A.updateEnemies(player, playerName)
        local t = now()
        if t - enemyScanAt > 2.0 then
            enemyScanAt = t
            local seen = {}
            for _, o in ipairs(FindAllOf("AIPlane") or {}) do
                local ok, isEnemy = pcall(function() return o.bIsActivated and o:GetFaction() == 0 and o:IsAlive() end)
                if ok and isEnemy then
                    local n = fullName(o)
                    if n then
                        seen[n] = true
                        if not tracks[n] then
                            tracks[n] = newTrack(o, "plane")
                            tracks[n].info = enemyInfo(o)
                        end
                    end
                end
            end
            for n, tr in pairs(tracks) do
                if tr.kind == "plane" and not seen[n] then tracks[n] = nil end
            end
        end
        for n, tr in pairs(tracks) do
            -- IsValid first, every time: it only looks the object up in UE4SS's list, while
            -- reading anything from an object the engine has freed crashes the game (the
            -- tracker kept destroyed planes from before a checkpoint restart; 18 Oct 2026)
            if tr.kind == "plane" and not valid(tr.obj) then
                tracks[n] = nil
            elseif tr.kind == "plane" then
                local ok, l = pcall(function() return tr.obj:K2_GetActorLocation() end)
                if ok and l then addSample(tr, t, v3(l)) end
                if not tr.stateAt or t - tr.stateAt > 0.5 then
                    tr.stateAt = t
                    pcall(enemyState, tr)
                    local prev = tr.lastState
                    if prev and prev ~= tr.state then tr.stateChanges = (tr.stateChanges or 0) + 1 end
                    tr.lastState = tr.state
                end
                tr.onMe = tr.tracking ~= nil and playerName ~= nil and tr.tracking == playerName
                -- Score the predictions: every 0.5 s guess where it will be in 2 s; when the
                -- 2 s are up, compare with where it is (per method: route, turning, straight).
                if tr.p and tr.v then
                    tr.checks = tr.checks or {}
                    if not tr.guessAt or t - tr.guessAt > 0.5 then
                        tr.guessAt = t
                        local kind = flyingKind(tr)
                        local guesses = {}
                        for _, how in ipairs(VARIANTS[kind]) do guesses[how] = guess(tr, 2.0, how) end
                        tr.checks[#tr.checks + 1] = { due = t + 2.0, kind = kind, guesses = guesses, used = bestWay(kind) }
                    end
                    while tr.checks[1] and tr.checks[1].due <= t do
                        local c = table.remove(tr.checks, 1)
                        if t - c.due < 0.3 then
                            A.ema[c.kind] = A.ema[c.kind] or {}
                            local st = A.predStats[c.kind] or { n = 0, err = {}, usedErr = 0 }
                            st.n = st.n + 1
                            for how, g in pairs(c.guesses) do
                                local err = len(sub(g, tr.p))
                                local old = A.ema[c.kind][how]
                                A.ema[c.kind][how] = old and (old * 0.97 + err * 0.03) or err
                                st.err[how] = (st.err[how] or 0) + err
                                if how == c.used then st.usedErr = st.usedErr + err end
                            end
                            A.predStats[c.kind] = st
                        end
                    end
                end
            end
        end
    end

    -- How good the 2-second predictions were, per method, against a plain straight line.
    A.predStats = {}
    function A.describePredictions()
        local parts = {}
        for kind, st in pairs(A.predStats) do
            if st.n > 0 then
                local ways = {}
                for how, sum in pairs(st.err) do ways[#ways + 1] = string.format("%s %.0f m", how, sum / st.n / 10) end
                table.sort(ways)
                parts[#parts + 1] = string.format("%s planes: %d checks, the guess used was off by %.0f m on average (each way: %s; now using %s)",
                    kind, st.n, st.usedErr / st.n / 10, table.concat(ways, ", "), bestWay(kind))
            end
        end
        table.sort(parts)
        return #parts > 0 and table.concat(parts, "; ") or "no checks yet"
    end

    function A.trackFor(o)
        local n = fullName(o)
        return n and tracks[n] or nil
    end

    -- ---- missiles -----------------------------------------------------------------------
    local MISSILE_FIELDS = { "SpeedMaximum", "Acceleration", "MaxRotationAngle", "MaxHomingAngle", "HomingDelayFromStart",
                             "ProximityFuseRadiusSquared", "NearWarningRadiusSquared", "VeryNearWarningRadiusSquared", "LifeTime" }
    local missileScanAt = -100
    A.threats = {}             -- missiles homing on the player, nearest impact first
    A.missileLog = {}          -- every missile seen homing on the player, for the report

    function A.updateMissiles(player, playerName, myP, myV)
        local t = now()
        if t - missileScanAt > 0.2 then
            missileScanAt = t
            local seen = {}
            for _, m in ipairs(FindAllOf("Missile") or {}) do
                local n = fullName(m)
                local ok, live = pcall(function() return m:IsValid() and not m:IsDestroyed() end)
                if n and ok and live then
                    seen[n] = true
                    if not tracks[n] then
                        local tr = newTrack(m, "missile")
                        local tgt = prop(m, "TargetToHome")
                        tr.targetName = tgt and valid(tgt) and fullName(tgt) or nil
                        local owner = prop(m, "OwningGameObject")
                        tr.ownerName = owner and valid(owner) and objName(owner) or "?"
                        tr.ownerCallsign = owner and valid(owner) and callsign(owner) or ""
                        tr.info = {}
                        for _, f in ipairs(MISSILE_FIELDS) do tr.info[f] = num(m, f) end
                        local ht = num(m, "HomingType")
                        tr.info.homing = ht and HOMING[ht] or "?"
                        tr.born = t
                        tr.minDist = math.huge
                        tracks[n] = tr
                    end
                end
            end
            for n, tr in pairs(tracks) do
                if tr.kind == "missile" and not seen[n] then
                    if tr.atMe then
                        tr.gone = t
                        event("missile_gone", { missile = tr.name, from = tr.ownerName, closest_m = tr.minDist / 10,
                                                flew_s = t - tr.born, flares_while_near = tr.flared or false })
                    end
                    tracks[n] = nil
                end
            end
        end
        local threats = {}
        for n, tr in pairs(tracks) do
            if tr.kind == "missile" and not valid(tr.obj) then
                tracks[n] = nil
            elseif tr.kind == "missile" then
                local ok, l = pcall(function() return tr.obj:K2_GetActorLocation() end)
                if ok and l then addSample(tr, t, v3(l)) end
                -- re-read its target: a missile can lose its lock (flares) and the target goes nil
                local tgt = prop(tr.obj, "TargetToHome")
                tr.targetName = tgt and valid(tgt) and fullName(tgt) or nil
                local atMe = playerName ~= nil and tr.targetName == playerName
                if atMe and not tr.atMe then
                    tr.atMe = true
                    A.missileLog[#A.missileLog + 1] = tr
                    event("missile_at_me", { missile = tr.name, from = tr.ownerName, callsign = tr.ownerCallsign,
                                             dist_m = tr.p and len(sub(tr.p, myP)) / 10 or -1, homing = tr.info.homing,
                                             top_kmh = tr.info.SpeedMaximum, turn = tr.info.MaxRotationAngle })
                elseif tr.atMe and not atMe and not tr.lostLock then
                    tr.lostLock = t
                    event("missile_lost_lock", { missile = tr.name, from = tr.ownerName, dist_m = tr.p and len(sub(tr.p, myP)) / 10 or -1 })
                end
                if atMe and tr.p and tr.v then
                    local r = sub(tr.p, myP)
                    local vr = sub(tr.v, myV)
                    local d = len(r)
                    if d < tr.minDist then tr.minDist = d end
                    local closing = -dot(r, vr) / math.max(d, 1)
                    local tgo = closing > 1 and d / closing or math.huge
                    local vv = dot(vr, vr)
                    local tStar = vv > 1 and -dot(r, vr) / vv or 0
                    if tStar < 0 then tStar = 0 end
                    local miss = len(add(r, mul(vr, tStar)))
                    -- how fast the line of sight turns (rad/s): what the missile must turn to keep up
                    local losRate = len(cross(r, vr)) / math.max(d * d, 1)
                    tr.tgo, tr.miss, tr.closing, tr.dist, tr.losRate = tgo, miss, closing, d, losRate
                    threats[#threats + 1] = tr
                end
            end
        end
        table.sort(threats, function(a, b) return a.tgo < b.tgo end)
        A.threats = threats
        return threats
    end

    -- ---- the ground -------------------------------------------------------------------
    -- The altitude the game reports is height above the sea; over hills the ground is much
    -- higher (Mission 02, 18 Oct: four terrain scrapes at 190-340 m "altitude"). So the
    -- ground is measured with line traces (UE4SS's LineTraceMod shows the call): straight
    -- down from the plane, and down from where the plane will be in 1 to 4 seconds on its
    -- present course. Result: clearance in metres now and the lowest one ahead.
    local UEHelpers = require("UEHelpers")
    local KSL = nil
    local NOCOLOR = { R = 0, G = 0, B = 0, A = 0 }
    A.fastReady = false        -- set by main.lua once CoopPadMod's fast traces are set up
    local function groundZ(ctx, x, y, zTop, zBottom)
        if A.fastReady and type(CoopTrace_Ground) == "function" then
            local z = CoopTrace_Ground(x, y, zTop, zBottom)
            return z
        end
        if not KSL or not valid(KSL) then KSL = UEHelpers.GetKismetSystemLibrary() end
        local hit = {}
        local ok, wasHit = pcall(function()
            return KSL:LineTraceSingle(ctx, { X = x, Y = y, Z = zTop }, { X = x, Y = y, Z = zBottom }, 0, false, {}, 0, hit, true, NOCOLOR, NOCOLOR, 0.0)
        end)
        if not ok then A.terrainError = tostring(wasHit); return nil end
        if not wasHit then return nil end
        local loc = hit.ImpactPoint or hit.Location
        local okz, z = pcall(function() return loc.Z end)
        if okz and type(z) == "number" then return z end
        return nil
    end

    A.ground = { below = nil, ahead = nil, aheadT = nil, at = -100 }
    function A.updateGround(plane, myP, myV)
        local t = now()
        if t - A.ground.at < 0.15 then return A.ground end
        A.ground.at = t
        local gz = groundZ(plane, myP[1], myP[2], myP[3] - 50, myP[3] - 60000)
        A.ground.below = gz and (myP[3] - gz) / 10 or nil          -- metres above the ground (nil: sea or nothing below)
        local worst, worstT = nil, nil
        A.ground.overhang = nil
        for _, s in ipairs({ 1.0, 2.0, 3.0, 4.0 }) do
            local q = add(myP, mul(myV, s))
            local qz = groundZ(plane, q[1], q[2], q[3] + 30000, q[3] - 60000)
            -- Something solid above where the plane will be: a mountain it would fly into, or
            -- an overhang it will pass under (a bridge deck, the Space Elevator's ring; 19 Oct
            -- 2026 the bot passed under the ring and the pull-up for "ground ahead" took it
            -- straight into the ring). A second trace from just above that point tells them
            -- apart: with open space and ground below, it is an overhang, not ground.
            if qz and qz > q[3] then
                local under = groundZ(plane, q[1], q[2], q[3] + 200, q[3] - 60000)
                if under and under < q[3] - 50 then
                    A.ground.overhang = (qz - q[3]) / 10
                    qz = under
                end
            end
            if qz then
                local clear = (q[3] - qz) / 10
                if not worst or clear < worst then worst, worstT = clear, s end
            end
        end
        A.ground.ahead, A.ground.aheadT = worst, worstT
        return A.ground
    end

    -- ---- reading it out ---------------------------------------------------------------
    function A.describeEnemies(myP, limit)
        local rows = {}
        for _, tr in pairs(tracks) do
            if tr.kind == "plane" and tr.p then rows[#rows + 1] = tr end
        end
        table.sort(rows, function(a, b) return len(sub(a.p, myP)) < len(sub(b.p, myP)) end)
        local out = {}
        for i = 1, math.min(limit or 8, #rows) do
            local tr = rows[i]
            local p5, how = A.predict(tr, 5)
            local turnDeg = math.deg(len(tr.w))
            out[#out + 1] = string.format("%s %s: %.0f m, %.0f km/h, turning %.0f deg/s (limit %s), state %s%s, %s%s; in 5 s by %s %.0f m from now",
                tr.name, callsign(tr.obj), len(sub(tr.p, myP)) / 10, tr.v and len(tr.v) / 2.78 or 0, turnDeg,
                tr.info and tr.info.turn and string.format("%.0f", tr.info.turn) or "?", tr.state or "?",
                tr.onMe and " (TRACKING ME)" or "", tr.info and tr.info.tgt and "TGT" or "not TGT",
                tr.info and tr.info.spline and string.format(", scripted route %.0f m", (tr.info.splineLength or 0) / 10) or "",
                how, p5 and len(sub(p5, tr.p)) / 10 or -1)
        end
        return out
    end

    return A
end
