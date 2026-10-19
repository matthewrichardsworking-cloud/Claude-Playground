-- gimmicks.lua: the mission's own special objects, read at runtime (CoopPilotMod, phase 3,
-- 18 Oct 2026)
--
-- Missions build their special rules out of "system objects" the game places in the level:
--   * SystemObjectSearchLight: a searchlight with a beam that sweeps (yaw or pitch, between
--     two ends, waiting at each end) and swings onto planes that come close; a plane inside
--     the beam is "in the searchlight" (PlayerPlane:IsInSearchLight);
--   * SystemObjectRadarArea / SystemObjectJammingArea / SystemObjectImpactArea: spheres
--     (Radius) where radar sees you, where your radar is jammed, where something will hit;
--   * SystemObjectLine: the combat zone's return line and pull-out line;
--   * SystemObjectLightning, CloudVolume, AirCurrentVolume, TunnelEventVolume: weather,
--     clouds, wind, tunnels;
--   * NimbusTriggerBase (and its children): the mission script's trigger volumes.
-- The altitude ceiling some missions set is not a property anyone can read; the mission
-- script hands it to the plane with PlayerPlane:SetRestrictedAltitude(metres), so main.lua
-- hooks that call and passes the value here (A.ceiling).
--
-- This module finds them, reads what they are, follows the searchlight beams frame by
-- frame (their direction now, their sweep, and a prediction of where each beam will
-- point in t seconds) and answers "is this point inside a beam (now / in t seconds)?".

return function(env)
    local log, event, now, call, objName = env.log, env.event, env.now, env.call, env.objName
    local G = {}

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
    local function vec(l) if not l then return nil end; local ok, v = pcall(function() return { l.X, l.Y, l.Z } end); return ok and v or nil end
    local function rot(r) if not r then return nil end; local ok, v = pcall(function() return { r.Pitch, r.Yaw, r.Roll } end); return ok and v or nil end
    local function fwd(pitch, yaw)
        local p, y = math.rad(pitch), math.rad(yaw)
        return { math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), math.sin(p) }
    end
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local function len(a) return math.sqrt(dot(a, a)) end
    local function wrap180(d) return (d + 180) % 360 - 180 end

    local CLASSES = {
        "SystemObjectSearchLight", "SystemObjectRadarArea", "SystemObjectJammingArea", "SystemObjectImpactArea",
        "SystemObjectLine", "SystemObjectLightning", "SystemObjectSubmarineSearchArea", "SystemObjectWayPointMarker",
        "SystemObjectDummyTarget", "CloudVolume", "SandCloudVolume", "AirCurrentVolume", "TunnelEventVolume",
        "TunnelMoveForcedVolume", "PlayerBlockingVolume", "NimbusTriggerBase", "MiniGameVolumeSet",
    }
    local MOVE_MODE = { [0] = "yaw sweep", "pitch sweep", "stopped" }
    local PRIORITY = { [0] = "all", "player", "ally" }

    G.objects = {}            -- class -> list of { obj, name, p }
    G.lights = {}             -- full name -> searchlight record
    G.ceiling = nil           -- metres above the sea, from SetRestrictedAltitude
    G.scanAt = -100

    local function fullName(o) local ok, n = pcall(function() return o:GetFullName() end); return ok and n or nil end

    -- The searchlight's beam right now: where it starts and which way it points. The beam is
    -- the light's "SearchLightRoot" component (the part that turns); the spot light inside it
    -- carries the cone.
    local function beamNow(L)
        local o = L.obj
        local root = prop(o, "SearchLightRoot")
        local spot = prop(o, "SpotLightComponent")
        local src = valid(spot) and spot or (valid(root) and root or nil)
        if not src then return nil end
        local okL, l = pcall(function() return src:K2_GetComponentLocation() end)
        local okR, r = pcall(function() return src:K2_GetComponentRotation() end)
        if not okL or not okR then return nil end
        local p, rr = vec(l), rot(r)
        if not p or not rr then return nil end
        return p, rr
    end

    local function readLight(o)
        local L = { obj = o, name = objName(o), hist = {} }
        if G.fans then local F = G.fans[L.name]; if F then L.pendingFan = true end end
        L.p = vec(call(o, "K2_GetActorLocation"))
        L.mode = num(o, "SearchMoveMode")
        L.modeText = L.mode and MOVE_MODE[L.mode] or "?"
        L.sweepDeg = num(o, "SearchTargetDeg")
        L.waitS = num(o, "SearchWaitTime")
        L.sweepSpeed = num(o, "SearchingRotateSpeedNew")
        L.trackPitch = num(o, "TrackingPitch")
        L.trackYaw = num(o, "TrackingYaw")
        L.trackSpeed = num(o, "TrackingRotateSpeedNew")
        L.seesApproach = prop(o, "bSeeingAproaching") == true
        L.approachDist = num(o, "SeeingAproachingDistance")
        L.approachDistUU = num(o, "SeeingAproachingDistanceUU")
        L.approachSpeed = num(o, "SeeingAproachingSpeed")
        local pr = num(o, "TargetPriority")
        L.priority = pr and PRIORITY[pr] or "?"
        L.radiationDeg = num(o, "RadiationAngle")
        L.collisionDeg = num(o, "CollisionAngle")
        L.radius = num(o, "Radius")
        L.thickness = num(o, "ThicknessRete")
        local off = prop(o, "OffsetRotate")
        L.offset = rot(off)
        local spot = prop(o, "SpotLightComponent")
        if valid(spot) then
            L.outerCone = num(spot, "OuterConeAngle")
            L.innerCone = num(spot, "InnerConeAngle")
            L.attenuation = num(spot, "AttenuationRadius")
        end
        local mesh = prop(o, "SearchLightCollisionMesh")
        if valid(mesh) then
            local mn, mx = {}, {}
            local ok = pcall(function() mesh:GetLocalBounds(mn, mx) end)
            if ok then L.meshMin, L.meshMax = vec(mn), vec(mx) end
            L.meshScale = vec(call(mesh, "K2_GetComponentScale"))
            L.meshRot = rot(call(mesh, "K2_GetComponentRotation"))
        end
        return L
    end

    function G.reset()
        G.lights, G.objects, G.scanAt = {}, {}, -100
    end

    -- Re-find the searchlights alone (one class, quick): fresh object references every few
    -- seconds, so a light the game has destroyed is never touched again (a reference kept for
    -- minutes can outlive its object; 18 Oct 2026 the game crashed in the base attack, right
    -- after the bot destroyed searchlights it was still polling).
    function G.refreshLights()
        local seen = {}
        for _, o in ipairs(FindAllOf("SystemObjectSearchLight") or {}) do
            local n = fullName(o)
            if n and not n:find("Default__", 1, true) then
                seen[n] = true
                local L = G.lights[n]
                if L then L.obj = o else L = readLight(o); G.lights[n] = L end
                if L.pendingFan then L.pendingFan = nil; G.applyFan(L) end
            end
        end
        for n in pairs(G.lights) do if not seen[n] then G.lights[n] = nil end end
        G.refreshedAt = now()
    end

    -- Find every special object of the mission (slow: the whole object list per class).
    function G.scan()
        G.scanAt = now()
        local counts = {}
        for _, cls in ipairs(CLASSES) do
            local list = {}
            for _, o in ipairs(FindAllOf(cls) or {}) do
                local ok, good = pcall(function()
                    if not o:IsValid() then return false end
                    local n = o:GetFullName()
                    return not n:find("Default__", 1, true)
                end)
                if ok and good then
                    list[#list + 1] = { obj = o, name = objName(o), full = fullName(o), p = vec(call(o, "K2_GetActorLocation")) }
                end
            end
            G.objects[cls] = list
            counts[#counts + 1] = cls .. " " .. #list
        end
        local seen = {}
        for _, e in ipairs(G.objects.SystemObjectSearchLight or {}) do
            seen[e.full] = true
            if not G.lights[e.full] then G.lights[e.full] = readLight(e.obj) end
        end
        for n in pairs(G.lights) do if not seen[n] then G.lights[n] = nil end end
        return table.concat(counts, ", ")
    end

    -- Follow every beam: called often (main.lua's frame loop). Keeps a short history of the
    -- beam's direction and works out its sweep: the two ends, the speed, the waits.
    function G.updateLights(myP, nearRange)
        local t = now()
        for _, L in pairs(G.lights) do
            -- far lights (beyond nearRange + their reach) only every 2 s
            local far = myP and L.p and nearRange and len(sub(L.p, myP)) > nearRange + G.reach(L)
            if far and L.beamAt and t - L.beamAt < 2 then
                -- skip this time
            elseif valid(L.obj) then
                local p, r = beamNow(L)
                if p then
                    L.beamP, L.beamR, L.beamAt = p, r, t
                    L.on = call(L.obj, "IsTurnOn")
                    L.tracking = call(L.obj, "IsTracking")
                    local h = L.hist
                    local last = h[#h]
                    if not last or t - last.t > 0.05 then
                        h[#h + 1] = { t = t, pitch = r[1], yaw = r[2] }
                        if #h > 400 then table.remove(h, 1) end
                    end
                    -- the sweep's ends: the extreme yaw (or pitch) seen while not tracking
                    if L.on and not L.tracking then
                        local a = (L.mode == 1) and r[1] or r[2]
                        if not L.ref then L.ref = a end
                        local rel = wrap180(a - L.ref)
                        if not L.fanLo then              -- the recorded sweep (loadFans) wins
                            L.lo = L.lo and math.min(L.lo, rel) or rel
                            L.hi = L.hi and math.max(L.hi, rel) or rel
                        end
                        -- angular speed, smoothed (deg/s), and the direction it is moving
                        if L.prevA and L.prevT and t > L.prevT then
                            local w = wrap180(a - L.prevA) / (t - L.prevT)
                            L.w = L.w and (L.w * 0.8 + w * 0.2) or w
                            if math.abs(w) > 0.5 then L.dir = w > 0 and 1 or -1 end
                        end
                        L.prevA, L.prevT = a, t
                    end
                end
            end
        end
    end

    -- Where a beam will point in dt seconds (pitch, yaw), assuming it keeps sweeping as
    -- measured: at its speed toward the end it is heading for, waiting there, and back.
    function G.beamIn(L, dt)
        if not L.beamR then return nil end
        local pitch, yaw = L.beamR[1], L.beamR[2]
        if L.tracking or not L.lo or not L.hi or (L.hi - L.lo) < 1 or not L.dir then return pitch, yaw end
        local speed = math.abs(L.sweepSpeed or 0)
        if speed < 0.1 then speed = math.abs(L.w or 0) end
        if speed < 0.1 then return pitch, yaw end
        local a = wrap180(((L.mode == 1) and pitch or yaw) - L.ref)
        local dir, left, wait = L.dir, dt, L.waitS or 0
        local guard = 0
        while left > 0 and guard < 20 do
            guard = guard + 1
            local goal = dir > 0 and L.hi or L.lo
            local need = math.abs(goal - a) / speed
            if need >= left then a = a + dir * speed * left; left = 0
            else a = goal; left = left - need - wait; dir = -dir end
        end
        if L.mode == 1 then return L.ref + a, yaw end
        return pitch, L.ref + a
    end

    -- Is point q (game units) inside light L's beam, with the beam pointing (pitch, yaw)?
    -- The beam is a cone from the light: half-angle from the game's collision angle (or the
    -- spot light's outer cone), length from its radius (or the spot light's reach).
    -- Returns inside (bool), how far outside the cone edge in degrees (negative inside), and
    -- the distance along the beam.
    function G.inBeam(L, q, pitch, yaw, marginDeg)
        if not L.beamP then return false, 999, 0 end
        local d = sub(q, L.beamP)
        local dl = len(d)
        local reach = G.reach(L)
        if dl > reach then return false, 999, dl end
        local f = fwd(pitch or L.beamR[1], yaw or L.beamR[2])
        local c = dot(d, f) / math.max(dl, 1)
        if c <= 0 then return false, 999, dl end
        local ang = math.deg(math.acos(math.min(1, c)))
        local half = G.halfAngle(L) + (marginDeg or 0)
        return ang <= half, ang - half, dl
    end

    -- The detection volume is the light's collision mesh: a cone along the beam whose base
    -- (at the beam's reach) is as wide as the mesh is scaled; Mission 14's canyon lights:
    -- scale 15.72 on a 100-unit cone over 3 km, i.e. 1.5 degrees either side, which is the
    -- "CollisionAngle" (3 degrees) as a full angle.
    function G.halfAngle(L)
        if L.learnedHalf then return L.learnedHalf end
        if L.collisionDeg and L.collisionDeg > 0 then return L.collisionDeg / 2 end
        if L.outerCone and L.outerCone > 0 then return L.outerCone end
        return 8
    end

    function G.reach(L)
        if L.learnedReach then return L.learnedReach end
        if L.radius and L.radius > 0 then return L.radius end
        if L.attenuation and L.attenuation > 0 then return L.attenuation end
        return 60000
    end

    -- Any active beam that point q will be inside dt seconds from now (with a margin).
    function G.beamHit(q, dt, marginDeg)
        for _, L in pairs(G.lights) do
            if L.on ~= false and L.beamP then
                local pitch, yaw = G.beamIn(L, dt or 0)
                local inside, edge = G.inBeam(L, q, pitch, yaw, marginDeg)
                if inside then return L, edge end
            end
        end
        return nil
    end

    -- The sweeps as recorded (tools\beam-fans.py --csv): each light's two ends on its sweep
    -- axis and its speed, exact from a long recording; the live readings then only give
    -- where in its sweep a light is and which way it is going.
    G.fans = {}
    function G.loadFans(path)
        local f = io.open(path, "r")
        if not f then return nil, "cannot open " .. tostring(path) end
        f:read("l")
        local n = 0
        for line in f:lines() do
            local name, mode, lo, hi, speed = line:match("^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)")
            lo, hi, speed = tonumber(lo), tonumber(hi), tonumber(speed)
            if name and lo and hi then G.fans[name] = { mode = mode, lo = lo, hi = hi, speed = speed }; n = n + 1 end
        end
        f:close()
        for _, L in pairs(G.lights) do G.applyFan(L) end
        return n
    end
    function G.applyFan(L)
        local F = G.fans[L.name]
        if not F or F.mode == "ring" or F.mode == "stopped" then return end
        L.fanLo = F.lo
        L.ref, L.lo, L.hi = F.lo, 0, F.hi - F.lo
        if F.speed and F.speed > 0.1 then L.sweepSpeed = F.speed end
    end

    -- Where light L will point every 'step' seconds for 'horizon' seconds: unit vectors,
    -- index 0 = now.
    function G.predictDirs(L, horizon, step)
        local dirs = {}
        local n = math.floor(horizon / step + 0.5)
        for i = 0, n do
            local pitch, yaw = G.beamIn(L, i * step)
            dirs[i] = fwd(pitch or 0, yaw or 0)
        end
        return dirs
    end

    -- A fast checker for the path planner: the beams that can matter near 'center' (within
    -- their reach plus 'radius'), with their predicted direction worked out once for every
    -- 'step' seconds up to 'horizon'. Returns function(q, t) -> light or nil, or nil when no
    -- beam is near.
    function G.beamChecker(center, radius, horizon, step, marginDeg)
        local near = {}
        for _, L in pairs(G.lights) do
            if L.on ~= false and L.beamP and len(sub(L.beamP, center)) < G.reach(L) + radius then
                local dirs = {}
                local n = math.floor(horizon / step + 0.5)
                for i = 0, n do
                    local pitch, yaw = G.beamIn(L, i * step)
                    dirs[i] = fwd(pitch, yaw)
                end
                near[#near + 1] = { L = L, dirs = dirs, cosHalf = math.cos(math.rad(G.halfAngle(L) + (marginDeg or 0))), reach = G.reach(L) }
            end
        end
        if #near == 0 then return nil end
        return function(q, t)
            local i = math.floor(t / step + 0.5)
            for _, b in ipairs(near) do
                local f = b.dirs[i] or b.dirs[#b.dirs]
                local d = sub(q, b.L.beamP)
                local dl = len(d)
                if dl < b.reach and dl > 1 and dot(d, f) / dl >= b.cosHalf then return b.L end
            end
            return nil
        end, #near
    end

    -- Will any beam light point q (game units) at time dt from now? Like beamHit, but only
    -- the lights within reach of q are looked at.
    function G.litAt(q, dt, marginDeg)
        for _, L in pairs(G.lights) do
            if L.on ~= false and L.beamP and len(sub(L.beamP, q)) < G.reach(L) then
                local pitch, yaw = G.beamIn(L, dt)
                local inside = G.inBeam(L, q, pitch, yaw, marginDeg)
                if inside then return L end
            end
        end
        return nil
    end

    -- The areas (spheres) of a kind that contain q, e.g. G.areasAt("SystemObjectRadarArea", q)
    function G.areasAt(cls, q)
        local out = {}
        for _, e in ipairs(G.objects[cls] or {}) do
            local r = num(e.obj, "Radius")
            if e.p and r and len(sub(q, e.p)) < r then out[#out + 1] = e end
        end
        return out
    end

    -- ---- reading it out -------------------------------------------------------------------
    local function f0(x) return x and string.format("%.0f", x) or "?" end
    local function f1(x) return x and string.format("%.1f", x) or "?" end
    local function v0(v) return v and string.format("(%.0f, %.0f, %.0f)", v[1], v[2], v[3]) or "?" end

    function G.describe(myP)
        local lines = {}
        for cls, list in pairs(G.objects) do
            if #list > 0 then
                local parts = {}
                for i = 1, math.min(#list, 12) do
                    local e = list[i]
                    local extra = ""
                    local r = num(e.obj, "Radius")
                    if r then extra = extra .. " radius " .. f0(r / 10) .. " m" end
                    local lt = num(e.obj, "LineType")
                    if lt then extra = extra .. (lt == 1 and " pull-out line" or " return line") end
                    local act = prop(e.obj, "bIsActivated")
                    if act ~= nil then extra = extra .. (act and " active" or " inactive") end
                    local hid = prop(e.obj, "bHidden")
                    if hid then extra = extra .. " hidden" end
                    local d = (myP and e.p) and string.format(" %.0f m away", len(sub(e.p, myP)) / 10) or ""
                    parts[#parts + 1] = e.name .. " at " .. v0(e.p) .. d .. extra
                end
                lines[#lines + 1] = string.format("%s (%d): %s%s", cls, #list, table.concat(parts, "; "), #list > 12 and "; ..." or "")
            end
        end
        table.sort(lines)
        for _, L in pairs(G.lights) do
            lines[#lines + 1] = string.format("searchlight %s at %s: %s, sweep %s deg at %s deg/s, wait %s s, offset %s; tracking pitch %s yaw %s at %s deg/s; sees approaching %s (%s / %s UU at %s); priority %s; radiation %s deg, collision %s deg, radius %s (%s m), thickness %s; spot cone %s/%s deg, reach %s; mesh bounds %s..%s scale %s rot %s; on %s, tracking %s, beam %s from %s; sweep seen %s..%s (dir %s, %s deg/s)",
                L.name, v0(L.p), L.modeText, f1(L.sweepDeg), f1(L.sweepSpeed), f1(L.waitS), L.offset and v0(L.offset) or "?",
                f1(L.trackPitch), f1(L.trackYaw), f1(L.trackSpeed), tostring(L.seesApproach), f1(L.approachDist), f1(L.approachDistUU), f1(L.approachSpeed),
                L.priority, f1(L.radiationDeg), f1(L.collisionDeg), f1(L.radius), f0(L.radius and L.radius / 10), f1(L.thickness),
                f1(L.innerCone), f1(L.outerCone), f1(L.attenuation), v0(L.meshMin), v0(L.meshMax), v0(L.meshScale), v0(L.meshRot),
                tostring(L.on), tostring(L.tracking), L.beamR and string.format("pitch %.1f yaw %.1f", L.beamR[1], L.beamR[2]) or "?", v0(L.beamP),
                f1(L.lo), f1(L.hi), tostring(L.dir), f1(L.w))
        end
        lines[#lines + 1] = "altitude ceiling: " .. (G.ceiling and (f0(G.ceiling) .. " m (from SetRestrictedAltitude)") or "none set this mission (or set before this script loaded)")
        return lines
    end

    return G
end
