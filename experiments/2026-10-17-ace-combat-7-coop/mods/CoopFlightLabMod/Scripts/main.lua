-- CoopFlightLabMod  (Ace Combat 7 co-op workbench, 18 Oct 2026)
--
-- Small toolbox for working on the co-op idea inside ONE copy of the game:
--   F7  start / stop recording the player's plane (position, heading, speed) about
--       twenty times a second into a text file in the copy's own user folder
--       (C:\AC7-Coop-Game\UserProfile\flight-<date>.csv)
--   F8  print a status line to the UE4SS log: where the player plane is, how many AI
--       planes exist, what the current map is
--   F9  write the UE4SS object dump (the game's catalogue of classes and functions)
--   F4  puppet: fly the nearest active AI plane along the newest recording (F3/F2: an
--       unactivated plane), its own AI off, speed matched, teleported every frame
--   F11 live puppet: the same, but from UDP packets arriving through the CoopNetMod C++
--       add-on (tools\coop-net-sender.py sends a recording as packets), 18 Oct 2026
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
        -- clocks: which time sources work right now and how long each takes to read
        local c0 = os.clock()
        local ok1, t1 = pcall(function() return UEHelpers.GetGameplayStatics():GetTimeSeconds(UEHelpers.GetWorldContextObject()) end)
        local c1 = os.clock()
        local ok2, t2 = pcall(function() return UEHelpers.GetWorld().TimeSeconds end)
        local c2 = os.clock()
        local wname = "?"
        pcall(function() wname = UEHelpers.GetWorld():GetFullName() end)
        local ctxname = "?"
        pcall(function() ctxname = UEHelpers.GetWorldContextObject():GetFullName() end)
        log(string.format("clocks: GetTimeSeconds -> %s %s (%.1f ms); World.TimeSeconds -> %s %s (%.1f ms); os.clock %.3f; os.time %d; world %s; context %s",
            tostring(ok1), tostring(t1), (c1 - c0) * 1000, tostring(ok2), tostring(t2), (c2 - c1) * 1000, os.clock(), os.time(), wname, ctxname))
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
        r.jumpWindow = (r.jumpWindow or 0) + jump
        if r.steps > 0 and jump > (r.jumpMax or 0) then r.jumpMax = jump end   -- the very first move is the big one
        r.plane:K2_TeleportTo(target, rot)
        r.lastPut = target
        r.steps = r.steps + 1
        if r.matchSpeed and r.steps % 40 == 0 then
            pcall(function() r.plane:AutopilotAdjustSpeed(r.pathKmph, 1.0) end)
        end
        if r.steps % 200 == 0 then
            local spd = "?"
            pcall(function() spd = string.format("%.0f km/h", r.plane:GetSpeedKmph()) end)
            local windowMean = r.jumpWindow / 200
            r.jumpWindow = 0
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
            log(string.format("replay: step %d, t=%.1f s, own motion per frame %.1f units, correction per update over the last 200: %.1f units (worst since start %.1f), puppet speed %s, path speed %.0f km/h, relative to player: %s",
                r.steps, t - r.rows[1].t, r.strayTotal / r.steps, windowMean, r.jumpMax or 0, spd, r.pathKmph or 0, rel))
        end
    end)
    if not ok then log("replay step failed: " .. tostring(err)); replay = nil end
end

-- Every 10 ms, so that every frame gets a step (ExecuteInGameThread runs it on the next tick).
LoopAsync(10, function()
    if replay then ExecuteInGameThread(replayStep) end
    return false
end)

-- F3: same as F4, but the puppet is a plane the mission has NOT activated yet (parked
-- somewhere, waiting for its cue). It is switched on with SetActive(true, false) first.
-- Co-op will need a plane that is not part of the mission's own cast, so this matters.
local useInactivePlane = false
local matchSpeed = false

local function nearestInactiveAIPlane(loc)
    local best, bestD = nil, math.huge
    for _, a in ipairs(FindAllOf("AIPlane") or {}) do
        local ok, d = pcall(function()
            if a.bIsActivated then return nil end
            local l = a:K2_GetActorLocation()
            return (l.X - loc.X) ^ 2 + (l.Y - loc.Y) ^ 2 + (l.Z - loc.Z) ^ 2
        end)
        if ok and d and d < bestD then best, bestD = a, d end
    end
    return best, math.sqrt(bestD)
end

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
        local plane
        if useInactivePlane then
            plane = nearestInactiveAIPlane(loc)
            if not plane then log("no inactive AI plane found") return end
            local wasHidden = plane.bHidden
            local okA, errA = pcall(function() plane:SetActive(true, false) end)
            log(string.format("inactive puppet %s: hidden=%s, SetActive(true,false): %s, now active=%s hidden=%s",
                plane:GetFullName(), tostring(wasHidden), okA and "no error" or tostring(errA),
                tostring(plane.bIsActivated), tostring(plane.bHidden)))
            pcall(function() plane:SetActorHiddenInGame(false) end)
        else
            plane = nearestAIPlane(loc, true) or nearestAIPlane(loc, false)
        end
        if not plane then log("no AI plane to use as puppet") return end
        pcall(function() plane:SetBehaviorActive(false) end)
        pcall(function() plane:SetIsInvincible(true) end)
        -- Average speed of the recording, in the game's km/h (about 2.78 units/s per km/h,
        -- from the HUD's 600 km/h against the measured 1,640 units/s).
        local first, last = rows[1], rows[#rows]
        local dist = math.sqrt((last.x - first.x) ^ 2 + (last.y - first.y) ^ 2 + (last.z - first.z) ^ 2)
        local pathKmph = (last.t > first.t) and (dist / (last.t - first.t) / 2.78) or 600
        if matchSpeed then
            pcall(function() plane.OverrideNormalSpeed = pathKmph end)
            pcall(function() plane.OverrideMaxSpeed = pathKmph end)
            local okS, errS = pcall(function() plane:AutopilotAdjustSpeed(pathKmph, 1.0) end)
            log(string.format("speed matching on: path %.0f km/h; AutopilotAdjustSpeed: %s", pathKmph, okS and "no error" or tostring(errS)))
        end
        -- Start the puppet ahead and to the right of the player, where the chase camera can
        -- see it (straight abeam would be outside the view).
        local AHEAD, RIGHT, UP = 2500, 800, 0
        local yaw = math.rad(rot.Yaw)
        local fwdX, fwdY = math.cos(yaw), math.sin(yaw)
        local rightX, rightY = -math.sin(yaw), math.cos(yaw)
        local off = { X = loc.X + fwdX * AHEAD + rightX * RIGHT - rows[1].x,
                      Y = loc.Y + fwdY * AHEAD + rightY * RIGHT - rows[1].y,
                      Z = loc.Z + UP - rows[1].z }
        replay = { rows = rows, i = 1, t0 = gameTime(), plane = plane, off = off, steps = 0, strayTotal = 0, strayMax = 0, lastPut = nil,
                   matchSpeed = matchSpeed, pathKmph = pathKmph }
        log(string.format("replay started: %d samples (%.1f s) from %s, puppet %s, shifted by (%.0f, %.0f, %.0f)",
            #rows, rows[#rows].t - rows[1].t, path, plane:GetFullName(), off.X, off.Y, off.Z))
    end)
    if not ok then log("replay start failed: " .. tostring(err)) end
end

-- Live puppet (F11): the same takeover as F4, but the positions come in over the network
-- as UDP packets through the CoopNetMod C++ add-on (one text line per packet:
-- time,x,y,z,pitch,yaw,roll; tools\coop-net-sender.py sends them). The script plays a
-- little behind the newest packet (LIVE_DELAY) so there is always a next sample to
-- interpolate towards, and logs the correction per frame and the delay, like F4 does.
local live = nil
local liveLoopTicks = 0        -- how often the 10 ms loop below fired (diagnostic)
-- The live puppet is paced with os.clock() (real seconds, fine resolution), not with the
-- game's own clock: GetTimeSeconds turned out to cost about 20 ms per call from a Lua
-- script and to stand still after a script reload in a mission (18 Oct, run 4). The
-- packets' own times come from the sender's clock, which is real time too.
local function liveClock() return os.clock() end
local LIVE_DELAY = 0.10        -- seconds behind the newest packet
local LIVE_EXTRAP_MAX = 0.25   -- how far past the newest packet to extrapolate before holding still
local UNITS_PER_S_PER_KMPH = 2.78

local function parsePacket(line)
    local t, x, y, z, pitch, yaw, roll = line:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
    if not t then return nil end
    local row = { t = tonumber(t), x = tonumber(x), y = tonumber(y), z = tonumber(z),
                  pitch = tonumber(pitch), yaw = tonumber(yaw), roll = tonumber(roll) }
    if not (row.t and row.x and row.y and row.z and row.pitch and row.yaw and row.roll) then return nil end
    return row
end

local function lerpAngle(a, b, f)
    local d = (b - a + 180) % 360 - 180
    return a + d * f
end

-- Pull every packet the script has not seen yet into the buffer; drop rows well behind the playback point.
local function liveDrain(r)
    local got = 0
    while true do
        local line, seq, age = CoopNet_Since(r.lastSeq)
        if not line then break end
        r.lastSeq = seq
        local row = parsePacket(line)
        if row then
            row.seq = seq
            row.arrivedAt = liveClock() - age / 1000
            local last = r.rows[#r.rows]
            if last and row.t < last.t - 0.5 then
                -- the feed's clock jumped back (a recording started again): begin afresh
                log(string.format("live: feed time jumped from %.1f back to %.1f, restarting the playback clock", last.t, row.t))
                r.rows = {}
                r.offset = nil
                r.playT = nil
                r.restarts = (r.restarts or 0) + 1
            end
            r.rows[#r.rows + 1] = row
            got = got + 1
        else
            r.badPackets = r.badPackets + 1
        end
    end
    if r.playT then
        while #r.rows > 2 and r.rows[2].t < r.playT - 1.0 do table.remove(r.rows, 1) end
    end
    return got
end

local function liveSummary(r)
    local n = math.max(1, r.lagFrames or 0)
    return string.format("%d frames in %.1f s, %d packets used (%d unreadable), correction per frame %.1f units (worst %.1f); while the feed ran (%d frames): delay behind newest packet %.0f ms on average (%.0f min, %.0f max), packet age when used %.0f ms; %d frames past the end of the feed, %d feed restarts, speed set %s km/h",
        r.steps, r.offset and (liveClock() - r.startedAt) or 0, r.packets, r.badPackets, r.jumpTotal / math.max(1, r.steps), r.jumpMax,
        r.lagFrames or 0, 1000 * r.lagTotal / n, 1000 * (r.lagMin or 0), 1000 * r.lagMax, 1000 * r.ageTotal / n,
        r.extrap, r.restarts or 0, r.kmph and string.format("%.0f", r.kmph) or "not yet")
end

local function liveStep()
    if not live then return end
    local ok, err = pcall(function()
        local r = live
        -- timing of the parts of a step (CPU clock), to find where the time goes
        r.tm = r.tm or { drain = 0, clock = 0, loc = 0, tp = 0, all = 0, n = 0 }
        local c0 = os.clock()
        r.packets = r.packets + liveDrain(r)
        local c1 = os.clock(); r.tm.drain = r.tm.drain + (c1 - c0)
        if #r.rows < 2 then return end                       -- waiting for the feed
        local now = liveClock()
        local c2 = os.clock(); r.tm.clock = r.tm.clock + (c2 - c1)
        if not r.offset then
            -- first data: start the playback clock LIVE_DELAY behind the newest packet, and
            -- shift the path so the puppet starts ahead-right of the player (as F4 does)
            local first, newest = r.rows[1], r.rows[#r.rows]
            r.offset = now - (newest.t - LIVE_DELAY)
            pcall(function()
                local p = playerPlane()
                if p then r.playerLoc = p:K2_GetActorLocation(); r.playerRot = p:K2_GetActorRotation() end
            end)
            local AHEAD, RIGHT, UP = 2500, 800, 0
            local yaw = math.rad(r.playerRot.Yaw)
            local fwdX, fwdY = math.cos(yaw), math.sin(yaw)
            local rightX, rightY = -math.sin(yaw), math.cos(yaw)
            r.off = { X = r.playerLoc.X + fwdX * AHEAD + rightX * RIGHT - first.x,
                      Y = r.playerLoc.Y + fwdY * AHEAD + rightY * RIGHT - first.y,
                      Z = r.playerLoc.Z + UP - first.z }
            log(string.format("live puppet: first packets in (%d buffered), playing %.0f ms behind the feed, path shifted by (%.0f, %.0f, %.0f)",
                #r.rows, LIVE_DELAY * 1000, r.off.X, r.off.Y, r.off.Z))
        end
        r.playT = now - r.offset
        local newest = r.rows[#r.rows]
        local lag = newest.t - r.playT
        -- keep the playback point LIVE_DELAY behind the feed even if the two clocks drift apart
        r.offset = r.offset + (LIVE_DELAY - lag) * 0.02
        -- find the two samples around the playback point (search from the newest end)
        local a, b = r.rows[#r.rows - 1], r.rows[#r.rows]
        for k = #r.rows - 1, 1, -1 do
            if r.rows[k].t <= r.playT then a, b = r.rows[k], r.rows[k + 1]; break end
        end
        local f = (b.t > a.t) and ((r.playT - a.t) / (b.t - a.t)) or 0
        if f < 0 then f = 0 end
        if f > 1 then
            -- past the newest packet: carry on along the last segment for a short while, then hold
            local maxF = (b.t > a.t) and (1 + LIVE_EXTRAP_MAX / (b.t - a.t)) or 1
            if f > maxF then f = maxF end
            r.extrap = r.extrap + 1
        end
        local target = { X = a.x + (b.x - a.x) * f + r.off.X, Y = a.y + (b.y - a.y) * f + r.off.Y, Z = a.z + (b.z - a.z) * f + r.off.Z }
        local rot = { Pitch = lerpAngle(a.pitch, b.pitch, f), Yaw = lerpAngle(a.yaw, b.yaw, f), Roll = lerpAngle(a.roll, b.roll, f) }
        local c3 = os.clock()
        local here = r.plane:K2_GetActorLocation()
        local c4 = os.clock(); r.tm.loc = r.tm.loc + (c4 - c3)
        -- One step per rendered frame: if the plane is exactly where the last step put it,
        -- the game has not ticked since, so wait for the next loop pass.
        if r.lastPut and here.X == r.lastPut.X and here.Y == r.lastPut.Y and here.Z == r.lastPut.Z then
            r.sameFrame = (r.sameFrame or 0) + 1
            return
        end
        local jump = math.sqrt((here.X - target.X) ^ 2 + (here.Y - target.Y) ^ 2 + (here.Z - target.Z) ^ 2)
        r.plane:K2_TeleportTo(target, rot)
        r.lastPut = target
        local c5 = os.clock(); r.tm.tp = r.tm.tp + (c5 - c4); r.tm.all = r.tm.all + (c5 - c0); r.tm.n = r.tm.n + 1
        r.steps = r.steps + 1
        if r.steps <= 6 or jump > 500 then
            log(string.format("live detail: frame %d, playT %.3f, segment %.3f..%.3f (f=%.2f), lag %.0f ms, target (%.0f, %.0f, %.0f), plane was at (%.0f, %.0f, %.0f), jump %.0f",
                r.steps, r.playT, a.t, b.t, f, lag * 1000, target.X, target.Y, target.Z, here.X, here.Y, here.Z, jump))
        end
        if r.steps > 1 then
            r.jumpTotal = r.jumpTotal + jump
            r.jumpWindow = r.jumpWindow + jump
            if jump > r.jumpMax then r.jumpMax = jump end
        end
        if f <= 1 then
            -- delay statistics only for frames inside the feed (after it ends, lag just grows)
            r.lagFrames = (r.lagFrames or 0) + 1
            r.lagTotal = r.lagTotal + lag
            if lag > r.lagMax then r.lagMax = lag end
            if not r.lagMin or lag < r.lagMin then r.lagMin = lag end
            r.ageTotal = r.ageTotal + (now - b.arrivedAt)
        end
        if not r.windowT0 then r.windowT0 = now end
        -- speed matching from the last second of packets (length of the path flown, so a
        -- turn does not read as slow), refreshed every 40 frames
        if r.steps % 40 == 1 then
            local k0 = 1
            for k = #r.rows, 1, -1 do
                if newest.t - r.rows[k].t >= 1.0 then k0 = k; break end
            end
            local old = r.rows[k0]
            local dt = newest.t - old.t
            if dt > 0.3 then
                local d = 0
                for k = k0 + 1, #r.rows do
                    local p0, p1 = r.rows[k - 1], r.rows[k]
                    d = d + math.sqrt((p1.x - p0.x) ^ 2 + (p1.y - p0.y) ^ 2 + (p1.z - p0.z) ^ 2)
                end
                local kmph = d / dt / UNITS_PER_S_PER_KMPH
                if not r.kmph or math.abs(kmph - r.kmph) > r.kmph * 0.05 then
                    pcall(function() r.plane.OverrideNormalSpeed = kmph end)
                    pcall(function() r.plane.OverrideMaxSpeed = kmph end)
                    r.kmph = kmph
                end
                pcall(function() r.plane:AutopilotAdjustSpeed(kmph, 1.0) end)
            end
        end
        if r.steps % 200 == 0 then
            local windowMean = r.jumpWindow / 200
            r.jumpWindow = 0
            local spd = "?"
            pcall(function() spd = string.format("%.0f km/h", r.plane:GetSpeedKmph()) end)
            local fps = 200 / math.max(0.001, now - r.windowT0)
            r.windowT0 = now
            local tm = r.tm
            log(string.format("live timing per step (ms of CPU): drain %.2f, clock %.2f, get location %.2f, teleport %.2f, whole step %.2f; loop ticks since last report %d",
                1000 * tm.drain / tm.n, 1000 * tm.clock / tm.n, 1000 * tm.loc / tm.n, 1000 * tm.tp / tm.n, 1000 * tm.all / tm.n, liveLoopTicks))
            liveLoopTicks = 0
            r.tm = { drain = 0, clock = 0, loc = 0, tp = 0, all = 0, n = 0 }
            log(string.format("live: frame %d (%.1f frames/s, %d loop passes skipped as same frame), %d packets used, %d buffered, correction per frame over the last 200: %.1f units (worst since start %.1f), delay behind feed %.0f ms, newest packet %.0f ms old, %d frames extrapolated, puppet speed %s, feed speed %s km/h",
                r.steps, fps, r.sameFrame or 0, r.packets, #r.rows, windowMean, r.jumpMax, lag * 1000, (now - newest.arrivedAt) * 1000, r.extrap, spd,
                r.kmph and string.format("%.0f", r.kmph) or "?"))
            r.sameFrame = 0
        end
    end)
    if not ok then log("live step failed: " .. tostring(err)); live = nil end
end

LoopAsync(10, function()
    if live then liveLoopTicks = liveLoopTicks + 1; ExecuteInGameThread(liveStep) end
    return false
end)

local function toggleLive()
    if live then
        log("live puppet stopped by key: " .. liveSummary(live))
        live = nil
        return
    end
    local ok, err = pcall(function()
        if type(CoopNet_Since) ~= "function" then log("CoopNetMod is not loaded: no CoopNet_Since function") return end
        local p = playerPlane()
        if not p then log("no player plane") return end
        local loc = p:K2_GetActorLocation()
        local rot = p:K2_GetActorRotation()
        local plane = nearestAIPlane(loc, true) or nearestAIPlane(loc, false)
        if not plane then log("no AI plane to use as puppet") return end
        pcall(function() plane:SetBehaviorActive(false) end)
        pcall(function() plane:SetIsInvincible(true) end)
        -- start from the newest packet; whatever arrived before the key was pressed is ignored
        local _, seq = CoopNet_Latest()
        live = { plane = plane, rows = {}, lastSeq = (seq or 1) - 1, steps = 0, packets = 0, badPackets = 0,
                 jumpTotal = 0, jumpWindow = 0, jumpMax = 0, lagTotal = 0, lagMax = 0, ageTotal = 0, extrap = 0,
                 playerLoc = loc, playerRot = rot, kmph = nil, offset = nil, playT = nil, startedAt = liveClock() }
        log(string.format("live puppet started: %s; %s", plane:GetFullName(), tostring(CoopNet_Status())))
    end)
    if not ok then log("live puppet start failed: " .. tostring(err)) end
end

-- Keys -----------------------------------------------------------------------------
-- Speed matching proved itself (correction per frame 0.2 units instead of 50), so every
-- replay key uses it now. F4 = nearest active plane, F3 = nearest unactivated plane.
RegisterKeyBind(Key.F4, function() useInactivePlane = false; matchSpeed = true; toggleReplay() end)
RegisterKeyBind(Key.F3, function() useInactivePlane = true; matchSpeed = true; toggleReplay() end)
RegisterKeyBind(Key.F2, function() useInactivePlane = true; matchSpeed = true; toggleReplay() end)
RegisterKeyBind(Key.F6, function() stopBehaviourFirst = false; puppetTeleportTest() end)
RegisterKeyBind(Key.F5, function() stopBehaviourFirst = true; puppetTeleportTest() end)
RegisterKeyBind(Key.F7, toggleRecording)
RegisterKeyBind(Key.F8, status)
RegisterKeyBind(Key.F9, function() log("writing object dump"); DumpAllObjects(); log("object dump written") end)
RegisterKeyBind(Key.F11, toggleLive)

log("ready: F4 puppet replay, F11 live puppet from CoopNetMod packets, F5/F6 puppet teleport test, F7 record, F8 status, F9 object dump; files go to " .. profile)
