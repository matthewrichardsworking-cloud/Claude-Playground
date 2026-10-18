-- CoopFlightLabMod  (Ace Combat 7 co-op workbench, 18 Oct 2026)
--
-- Small toolbox for working on the co-op idea inside ONE copy of the game:
--   F7  start / stop recording the player's plane (position, heading, speed) about
--       twenty times a second into a text file in the copy's own user folder
--       (C:\AC7-Coop-Game\UserProfile\flight-<date>.csv)
--   F8  print a status line to the UE4SS log: where the player plane is, how many AI
--       planes exist, what the current map is
--   F9  write the UE4SS object dump (the game's catalogue of classes and functions)
--
-- Never touches save files. Active in every copy that loads it.

local TAG = "[CoopFlightLab] "
local profile = os.getenv("USERPROFILE") or "C:\\AC7-Coop-Game"
local function log(msg) print(TAG .. msg .. "\n") end

local UEHelpers = require("UEHelpers")

local function gameTime()
    local ok, t = pcall(function()
        return UEHelpers.GetGameplayStatics():GetTimeSeconds(UEHelpers.GetWorldContextObject())
    end)
    if ok and type(t) == "number" then return t end
    ok, t = pcall(function() return UEHelpers.GetWorld().TimeSeconds end)
    if ok and type(t) == "number" then return t end
    return os.time()
end

-- Missions can hold several PlayerPlane objects (cutscene planes among them). Prefer the
-- one a player controller is flying; otherwise the fastest one.
local function playerPlane()
    local all = FindAllOf("PlayerPlane") or {}
    local best, bestSpeed = nil, -1
    for _, p in ipairs(all) do
        if p:IsValid() then
            local ok, owned = pcall(function()
                local c = p.Controller
                return c:IsValid() and string.find(c:GetFullName(), "PlayerController", 1, true) ~= nil
            end)
            if ok and owned then return p end
            local ok2, v = pcall(function() return p:GetVelocity() end)
            local speed = (ok2 and v) and (v.X * v.X + v.Y * v.Y + v.Z * v.Z) or 0
            if speed > bestSpeed then best, bestSpeed = p, speed end
        end
    end
    return best
end

-- Recording -----------------------------------------------------------------------
local recording = nil
local samples = 0
local recordPath = nil

local function sample()
    if not recording then return end
    local p = playerPlane()
    if not p then return end
    local ok, err = pcall(function()
        local loc = p:K2_GetActorLocation()
        local rot = p:K2_GetActorRotation()
        local vel = p:GetVelocity()
        recording:write(string.format("%.3f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.1f,%.1f,%.1f\n",
            gameTime(), loc.X, loc.Y, loc.Z, rot.Pitch, rot.Yaw, rot.Roll, vel.X, vel.Y, vel.Z))
        samples = samples + 1
        if samples % 200 == 0 then recording:flush(); log(string.format("recording: %d samples", samples)) end
    end)
    if not ok then log("sample failed: " .. tostring(err)) end
end

local function toggleRecording()
    if recording then
        recording:close(); recording = nil
        log(string.format("recording stopped: %d samples in %s", samples, recordPath))
        return
    end
    local p = playerPlane()
    if not p then log("no player plane exists right now (not in a mission?); recording not started") return end
    recordPath = string.format("%s\\flight-%s.csv", profile, os.date("%Y-%m-%d_%H%M%S"))
    recording = io.open(recordPath, "w")
    if not recording then log("could not open " .. recordPath) return end
    recording:write("time,x,y,z,pitch,yaw,roll,vx,vy,vz\n")
    samples = 0
    log("recording started: " .. recordPath .. " (plane " .. p:GetFullName() .. ")")
end

LoopAsync(50, function()
    if recording then ExecuteInGameThread(sample) end
    return false
end)

-- Status ---------------------------------------------------------------------------
local function status()
    local ok, err = pcall(function()
        local world = UEHelpers.GetWorld()
        local mapName = world:IsValid() and world:GetFullName() or "?"
        local p = playerPlane()
        local ai = FindAllOf("AIPlane") or {}
        local line = string.format("map %s | AI planes: %d", mapName, #ai)
        local px, py, pz = 0, 0, 0
        if p then
            local loc = p:K2_GetActorLocation()
            local rot = p:K2_GetActorRotation()
            local vel = p:GetVelocity()
            px, py, pz = loc.X, loc.Y, loc.Z
            local speed = math.sqrt(vel.X * vel.X + vel.Y * vel.Y + vel.Z * vel.Z)
            line = line .. string.format(" | player %s at (%.0f, %.0f, %.0f), heading %.0f deg, %.0f units/s",
                p:GetFullName(), loc.X, loc.Y, loc.Z, rot.Yaw, speed)
        else
            line = line .. " | no player plane"
        end
        log(line)
        -- the twelve AI planes nearest the player, with how fast they move (0 = parked/unspawned)
        local rows = {}
        for _, a in ipairs(ai) do
            local ok2, row = pcall(function()
                local l = a:K2_GetActorLocation()
                local v = a:GetVelocity()
                local d = math.sqrt((l.X - px) ^ 2 + (l.Y - py) ^ 2 + (l.Z - pz) ^ 2)
                local s = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
                local act = a.bIsActivated
                local fac = "?"
                pcall(function() fac = tostring(a.OwningParent.Faction) end)
                local cs = "?"
                pcall(function() cs = a.CallsignID:ToString() end)
                return { d = d, s = s, name = a:GetFullName(), hidden = a.bHidden, act = act, fac = fac, cs = cs }
            end)
            if ok2 then rows[#rows + 1] = row end
        end
        table.sort(rows, function(a, b) return a.d < b.d end)
        for i, r in ipairs(rows) do
            if i > 12 then log(string.format("  ... and %d more AI planes", #rows - 12)) break end
            log(string.format("  AI %2d  %8.0f units away  active=%s faction=%s callsign=%s  %s", i, r.d, tostring(r.act), r.fac, r.cs, r.name))
        end
    end)
    if not ok then log("status failed: " .. tostring(err)) end
end

-- Puppet test (F6): take the nearest active AI plane and put it 600 units to the
-- player's right, facing the same way, through the plane's own flight-engine setter.
-- This also tells us whether a Lua table is accepted where the game wants a
-- position (FVector) or a rotation (FRotator).
local puppet = nil

local function nearestAIPlane(loc, needActive)
    local best, bestD = nil, math.huge
    for _, a in ipairs(FindAllOf("AIPlane") or {}) do
        local ok, d = pcall(function()
            if needActive and not a.bIsActivated then return nil end
            local l = a:K2_GetActorLocation()
            return (l.X - loc.X) ^ 2 + (l.Y - loc.Y) ^ 2 + (l.Z - loc.Z) ^ 2
        end)
        if ok and d and d < bestD then best, bestD = a, d end
    end
    return best, math.sqrt(bestD)
end

local stopBehaviourFirst = false
local function puppetTeleportTest()
    local ok, err = pcall(function()
        local p = playerPlane()
        if not p then log("no player plane") return end
        local loc = p:K2_GetActorLocation()
        local rot = p:K2_GetActorRotation()
        local best, dist = nearestAIPlane(loc, true)
        if not best then best, dist = nearestAIPlane(loc, false) end
        if not best then log("no AI plane found") return end
        puppet = best
        local before = best:K2_GetActorLocation()
        log(string.format("puppet candidate %s, active=%s, at (%.0f, %.0f, %.0f), %.0f units from player",
            best:GetFullName(), tostring(best.bIsActivated), before.X, before.Y, before.Z, dist))
        local target = { X = loc.X + 600, Y = loc.Y, Z = loc.Z }
        local trot = { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }
        if stopBehaviourFirst then
            local okB, errB = pcall(function() best:SetBehaviorActive(false) end)
            log("SetBehaviorActive(false): " .. (okB and "no error" or tostring(errB)))
        end
        local ok1, r1 = pcall(function() return best:K2_TeleportTo(target, trot) end)
        log("K2_TeleportTo(table, table): " .. (ok1 and ("no error, returned " .. tostring(r1)) or tostring(r1)))
        ExecuteWithDelay(100, function()
            ExecuteInGameThread(function()
                pcall(function()
                    local a = best:K2_GetActorLocation()
                    log(string.format("0.1 s later: puppet at (%.0f, %.0f, %.0f)", a.X, a.Y, a.Z))
                end)
            end)
        end)
        ExecuteWithDelay(1000, function()
            ExecuteInGameThread(function()
                pcall(function()
                    local after = best:K2_GetActorLocation()
                    local pl = p:K2_GetActorLocation()
                    log(string.format("1 s later: puppet at (%.0f, %.0f, %.0f), player at (%.0f, %.0f, %.0f), apart %.0f units",
                        after.X, after.Y, after.Z, pl.X, pl.Y, pl.Z,
                        math.sqrt((after.X - pl.X) ^ 2 + (after.Y - pl.Y) ^ 2 + (after.Z - pl.Z) ^ 2)))
                end)
            end)
        end)
    end)
    if not ok then log("puppet test failed: " .. tostring(err)) end
end

-- Puppet replay (F4): fly the nearest active AI plane along the newest recorded flight,
-- shifted so it starts 600 units to the player's right, by teleporting it every 50 ms
-- with its own AI switched off. Logs how far the plane strays from where it was put,
-- which shows whether the game's flight engine fights the teleports.
local replay = nil

local function newestFlightFile()
    if recordPath and not recording then return recordPath end
    local ok, name = pcall(function()
        local h = io.popen('dir /b /o:d "' .. profile .. '\\flight-*.csv" 2>nul')
        local last = nil
        for line in h:lines() do if line ~= "" then last = line end end
        h:close()
        return last
    end)
    if ok and name then return profile .. "\\" .. name end
    return nil
end

local function loadFlight(path)
    local rows = {}
    local f = io.open(path, "r")
    if not f then return nil end
    local header = f:read("l")
    for line in f:lines() do
        local t, x, y, z, pitch, yaw, roll = line:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
        if t then
            rows[#rows + 1] = { t = tonumber(t), x = tonumber(x), y = tonumber(y), z = tonumber(z),
                                pitch = tonumber(pitch), yaw = tonumber(yaw), roll = tonumber(roll) }
        end
    end
    f:close()
    return rows
end

local function replayStep()
    if not replay then return end
    local ok, err = pcall(function()
        local r = replay
        local t = gameTime() - r.t0 + r.rows[1].t
        while r.i < #r.rows and r.rows[r.i + 1].t <= t do r.i = r.i + 1 end
        if r.i >= #r.rows then
            log(string.format("replay finished: %d steps, own motion per frame %.1f units (worst %.1f), jump per update %.1f units (worst %.1f)",
                r.steps, r.strayTotal / math.max(1, r.steps), r.strayMax, (r.jumpTotal or 0) / math.max(1, r.steps), r.jumpMax or 0))
            replay = nil
            return
        end
        local a, b = r.rows[r.i], r.rows[r.i + 1]
        local f = (b.t > a.t) and ((t - a.t) / (b.t - a.t)) or 0
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        -- where the plane actually is now, compared with where it was last put
        if r.lastPut then
            local now = r.plane:K2_GetActorLocation()
            local stray = math.sqrt((now.X - r.lastPut.X) ^ 2 + (now.Y - r.lastPut.Y) ^ 2 + (now.Z - r.lastPut.Z) ^ 2)
            r.strayTotal = r.strayTotal + stray
            if stray > r.strayMax then r.strayMax = stray end
        end
        local target = { X = a.x + (b.x - a.x) * f + r.off.X, Y = a.y + (b.y - a.y) * f + r.off.Y, Z = a.z + (b.z - a.z) * f + r.off.Z }
        local rot = { Pitch = a.pitch, Yaw = a.yaw, Roll = a.roll }
        -- how far this update actually moves the plane (small = its own motion already follows the path)
        local here = r.plane:K2_GetActorLocation()
        local jump = math.sqrt((here.X - target.X) ^ 2 + (here.Y - target.Y) ^ 2 + (here.Z - target.Z) ^ 2)
        r.jumpTotal = (r.jumpTotal or 0) + jump
        if jump > (r.jumpMax or 0) then r.jumpMax = jump end
        r.plane:K2_TeleportTo(target, rot)
        r.lastPut = target
        r.steps = r.steps + 1
        if r.steps % 200 == 0 then
            local spd = "?"
            pcall(function() spd = string.format("%.0f km/h", r.plane:GetSpeedKmph()) end)
            -- where the puppet sits as seen from the player's plane: ahead / to the right / above
            local rel = "?"
            pcall(function()
                local p = playerPlane()
                local pl = p:K2_GetActorLocation()
                local pr = p:K2_GetActorRotation()
                local yaw = math.rad(pr.Yaw)
                local dx, dy, dz = target.X - pl.X, target.Y - pl.Y, target.Z - pl.Z
                local ahead = dx * math.cos(yaw) + dy * math.sin(yaw)
                local right = -dx * math.sin(yaw) + dy * math.cos(yaw)
                rel = string.format("ahead %.0f, right %.0f, above %.0f", ahead, right, dz)
            end)
            log(string.format("replay: step %d, t=%.1f s, own motion per frame %.1f units (worst %.1f), jump per update %.1f units (worst %.1f), puppet speed %s, relative to player: %s",
                r.steps, t - r.rows[1].t, r.strayTotal / r.steps, r.strayMax, r.jumpTotal / r.steps, r.jumpMax, spd, rel))
        end
    end)
    if not ok then log("replay step failed: " .. tostring(err)); replay = nil end
end

-- Every 10 ms, so that every frame gets a step (ExecuteInGameThread runs it on the next tick).
LoopAsync(10, function()
    if replay then ExecuteInGameThread(replayStep) end
    return false
end)

local function toggleReplay()
    if replay then
        log(string.format("replay stopped by key after %d steps", replay.steps)); replay = nil; return
    end
    local ok, err = pcall(function()
        local path = newestFlightFile()
        if not path then log("no recorded flight found in " .. profile) return end
        local rows = loadFlight(path)
        if not rows or #rows < 2 then log("could not read a flight from " .. tostring(path)) return end
        local p = playerPlane()
        if not p then log("no player plane") return end
        local loc = p:K2_GetActorLocation()
        local rot = p:K2_GetActorRotation()
        local plane = nearestAIPlane(loc, true) or nearestAIPlane(loc, false)
        if not plane then log("no AI plane to use as puppet") return end
        pcall(function() plane:SetBehaviorActive(false) end)
        pcall(function() plane:SetIsInvincible(true) end)
        -- Start the puppet ahead and to the right of the player, where the chase camera can
        -- see it (straight abeam would be outside the view).
        local AHEAD, RIGHT, UP = 2500, 800, 0
        local yaw = math.rad(rot.Yaw)
        local fwdX, fwdY = math.cos(yaw), math.sin(yaw)
        local rightX, rightY = -math.sin(yaw), math.cos(yaw)
        local off = { X = loc.X + fwdX * AHEAD + rightX * RIGHT - rows[1].x,
                      Y = loc.Y + fwdY * AHEAD + rightY * RIGHT - rows[1].y,
                      Z = loc.Z + UP - rows[1].z }
        replay = { rows = rows, i = 1, t0 = gameTime(), plane = plane, off = off, steps = 0, strayTotal = 0, strayMax = 0, lastPut = nil }
        log(string.format("replay started: %d samples (%.1f s) from %s, puppet %s, shifted by (%.0f, %.0f, %.0f)",
            #rows, rows[#rows].t - rows[1].t, path, plane:GetFullName(), off.X, off.Y, off.Z))
    end)
    if not ok then log("replay start failed: " .. tostring(err)) end
end

-- Keys -----------------------------------------------------------------------------
RegisterKeyBind(Key.F4, toggleReplay)
RegisterKeyBind(Key.F6, function() stopBehaviourFirst = false; puppetTeleportTest() end)
RegisterKeyBind(Key.F5, function() stopBehaviourFirst = true; puppetTeleportTest() end)
RegisterKeyBind(Key.F7, toggleRecording)
RegisterKeyBind(Key.F8, status)
RegisterKeyBind(Key.F9, function() log("writing object dump"); DumpAllObjects(); log("object dump written") end)

log("ready: F4 puppet replay, F5/F6 puppet teleport test, F7 record, F8 status, F9 object dump; files go to " .. profile)
