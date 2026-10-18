-- CoopPilotMod  (Ace Combat 7 playtest bot: the pilot inside the game), 18 Oct 2026
--
-- Lives in the game copy only (C:\AC7-Coop-Game). Takes orders as one-line UDP text
-- packets "PILOT <command> ..." through the CoopNetMod C++ add-on (tools\pilot.py sends
-- them to 127.0.0.1:27777), so no game window has to be in front. Writes what it sees
-- and does into C:\AC7-Coop-Game\UserProfile\pilot:
--   pilot.log     what the pilot did and found, in words
--   status.json   the latest snapshot of the plane and the mission (about twice a second)
--   events.jsonl  one line per event (see the design, playtest-bot.md)
--   probe-*.csv   frame-by-frame data from the probes
--
-- Stage 1 of the design (control test): "probe controls", "probe weapons",
-- "probe targets", "probe mission". Never touches save files.

local TAG = "[CoopPilot] "
local OUT = "C:\\AC7-Coop-Game\\UserProfile\\pilot"
local UEHelpers = require("UEHelpers")

local logFile = io.open(OUT .. "\\pilot.log", "a")
local function log(msg)
    print(TAG .. msg .. "\n")
    if logFile then logFile:write(os.date("%H:%M:%S "), msg, "\n"); logFile:flush() end
end

-- os.clock() is real seconds since the game started (the game's own clock costs about
-- 20 ms per call from a script; workbench section 9).
local now = os.clock

local function fmt(v)
    if type(v) == "number" then return string.format("%.3f", v) end
    return tostring(v)
end

-- Small JSON writer for flat tables (numbers, strings, booleans, nested flat tables).
local function json(v)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if math.type and math.type(v) == "integer" then return tostring(v) end
        return string.format("%.4g", v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "table" then
        if #v > 0 then
            local parts = {}
            for i = 1, #v do parts[i] = json(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = json(tostring(k)) .. ":" .. json(x) end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local eventsFile = io.open(OUT .. "\\events.jsonl", "a")
local function event(kind, fields)
    fields = fields or {}
    fields.t = now()
    fields.kind = kind
    fields.clock = os.date("%H:%M:%S")
    if eventsFile then eventsFile:write(json(fields), "\n"); eventsFile:flush() end
end

-- Finding things ---------------------------------------------------------------------

-- Missions hold several PlayerPlane objects (cutscene copies among them). The one a
-- player controller flies is the real one (workbench section 7).
local cachedPlane, checkedAt = nil, 0
local function playerPlane()
    if cachedPlane then
        local ok, good = pcall(function()
            if not cachedPlane:IsValid() then return false end
            if now() - checkedAt < 2 then return true end
            checkedAt = now()
            return cachedPlane.Controller:IsValid()
                and string.find(cachedPlane.Controller:GetFullName(), "PlayerController", 1, true) ~= nil
        end)
        if ok and good then return cachedPlane end
        cachedPlane = nil
    end
    checkedAt = now()
    for _, p in ipairs(FindAllOf("PlayerPlane") or {}) do
        local ok, owned = pcall(function()
            local c = p.Controller
            return p:IsValid() and c:IsValid() and string.find(c:GetFullName(), "PlayerController", 1, true) ~= nil
        end)
        if ok and owned then cachedPlane = p; return p end
    end
    return nil
end

local function weapons(p)
    local ok, w = pcall(function() return p.PlayerWeaponActivator end)
    if ok and w and w:IsValid() then return w end
    return nil
end

local cachedTS, cachedTSPlane = nil, nil
local function targetSelection(p)
    if cachedTS and cachedTSPlane == p then
        local ok, good = pcall(function() return cachedTS:IsValid() end)
        if ok and good then return cachedTS end
    end
    cachedTS, cachedTSPlane = nil, p
    local ok, ts = pcall(function() return p.TargetSelection end)
    if ok and ts and ts:IsValid() then cachedTS = ts; return ts end
    local want = p:GetFullName():match("^%S+%s+(.+)$") or ""
    for _, c in ipairs(FindAllOf("TargetSelectionComponent") or {}) do
        local okc, name = pcall(function() return c:GetFullName() end)
        if okc and name:find(want .. ".TargetSelection", 1, true) then cachedTS = c; return c end
    end
    return nil
end

local missionCDO, cachedMission, missionLookedAt = nil, nil, -100
local function mission()
    local ok, m = pcall(function()
        if not (missionCDO and missionCDO:IsValid()) then missionCDO = StaticFindObject("/Script/Nimbus.Default__Mission") end
        return missionCDO:GetCurrentMission(false)
    end)
    if ok and m and m:IsValid() then return m end
    -- fallback: search the object list, but not more often than every 3 s (it is slow)
    local okc, good = pcall(function() return cachedMission and cachedMission:IsValid() end)
    if okc and good then return cachedMission end
    cachedMission = nil
    if now() - missionLookedAt < 3 then return nil end
    missionLookedAt = now()
    local okf, f = pcall(function() return FindFirstOf("Mission") end)
    if okf and f and f:IsValid() then cachedMission = f; return f end
    return nil
end

local function call(obj, fn, ...)
    local args = { ... }
    local ok, r = pcall(function() return obj[fn](obj, table.unpack(args)) end)
    if ok then return r end
    return nil
end

local function objName(o)
    if not o then return "none" end
    local ok, s = pcall(function()
        if not o:IsValid() then return "invalid" end
        local full = o:GetFullName()
        return full:match("([^%.:]+)$") or full
    end)
    return ok and s or "?"
end

local function callsign(o)
    local ok, s = pcall(function() return o.CallsignID:ToString() end)
    return ok and s or ""
end

local function dist(a, b)
    return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2)
end

local function wrap180(d) return (d + 180) % 360 - 180 end

-- Snapshot -------------------------------------------------------------------------

-- Which menu screens are showing: the class names of the game's UI widgets that are on
-- screen right now (so the test runner knows where it is without reading pictures).
local uiCache, uiAt = {}, -100
local function screens()
    if now() - uiAt < 1 then return uiCache end
    uiAt = now()
    local names, seen = {}, {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        pcall(function()
            if w:IsInViewport() then
                local n = w:GetClass():GetFName():ToString()
                if not seen[n] then seen[n] = true; names[#names + 1] = n end
            end
        end)
    end
    table.sort(names)
    uiCache = names
    return names
end

-- Which menu page is showing. The menus live inside one front-screen widget, so a page
-- is recognised by its own widget being visible (mapped 18 Oct 2026, workbench section 10).
local PAGES = {   -- most specific first
    "CampaignHangarReview_C", "CampaignHangarWeapon_C", "CampaignHangarAircraft_C", "CampaignMenuActionSelect_C",
    "CampaignBriefingMenu_C", "CampaignMissionTitle_C", "CampaignBriefingMV_C", "CampaignMV_C",
    "CampaignFreeMission_C", "CampaignFreeMissionDifficulty_C", "CampaignMenuMain_C", "MainMenu_C", "MainTitle_C",
}
local pageCache, pageAt = nil, -100
local function currentPage()
    if now() - pageAt < 0.5 then return pageCache end
    pageAt = now()
    local visible = {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        pcall(function()
            if w:IsVisible() then visible[w:GetClass():GetFName():ToString()] = true end
        end)
    end
    pageCache = nil
    for _, name in ipairs(PAGES) do
        if visible[name] then pageCache = name; break end
    end
    return pageCache
end

local function snapshot()
    local s = { time = now() }
    local p = playerPlane()
    s.screens = screens()
    s.page = currentPage() or false
    if not p then s.plane = false; return s end
    pcall(function()
        local l = p:K2_GetActorLocation()
        local r = p:K2_GetActorRotation()
        s.x, s.y, s.z = l.X, l.Y, l.Z
        s.pitch, s.yaw, s.roll = r.Pitch, r.Yaw, r.Roll
    end)
    s.plane = objName(p)
    s.kmh = call(p, "GetSpeedKmph")
    s.alt_m = call(p, "GetAltitudeMeters")
    s.health = call(p, "GetHealth")
    s.max_health = call(p, "GetMaxHealth")
    s.damage_pct = call(p, "GetDamagePercentage")
    pcall(function() s.missile_alert = p.MissileAlert end)
    pcall(function()
        s.in_input = { pitch = p.InputPitch, roll = p.InputRoll, throttle = p.InputThrottle, brake = p.InputBrake,
                       lyaw = p.InputLeftYaw, ryaw = p.InputRightYaw }
        s.input_enabled = { move = p.bEnableMovmentInput, weapon = p.bEnableWeaponInput }
    end)
    s.beyond_pullout = call(p, "IsBeyondPulloutLine")
    s.over_altitude = call(p, "IsOverRestrictedAltitude")
    local w = weapons(p)
    if w then
        s.missiles = call(w, "GetMainWeaponCount")
        s.gun = call(w, "GetGunCount")
        s.flares = call(w, "GetFlareCount")
        s.special = call(w, "GetSpecialWeaponCount")
    end
    local ts = targetSelection(p)
    if ts then
        local sel = call(ts, "GetSelectedTarget")
        s.target = objName(sel)
        if sel then
            s.target_callsign = callsign(sel)
            pcall(function() s.target_m = dist(sel:K2_GetActorLocation(), p:K2_GetActorLocation()) / 10 end)
        end
    end
    local m = mission()
    if m then
        s.mission = objName(m)
        s.started = call(m, "IsMissionStarted")
        s.completed = call(m, "IsMissionCompleted")
        s.failed = call(m, "IsMissionFailed")
        s.in_igc = call(m, "IsInIGC")
        s.score = call(m, "GetMissionScore_S")
        s.elapsed_s = call(m, "GetMissionElapsedTimeInSeconds_S")
        s.phase_left_s = call(m, "GetMissionPhaseTimeLeftInSeconds_S")
        s.kills = call(m, "GetKillStatCount")
    end
    return s
end

local function writeStatus()
    local ok, err = pcall(function()
        local s = snapshot()
        local f = io.open(OUT .. "\\status.json.tmp", "w")
        if not f then return end
        f:write(json(s), "\n"); f:close()
        os.remove(OUT .. "\\status.json")
        os.rename(OUT .. "\\status.json.tmp", OUT .. "\\status.json")
    end)
    if not ok then log("status failed: " .. tostring(err)) end
end

-- Frame loop -------------------------------------------------------------------------
-- UE4SS's per-frame hook is not available in this game (UE4SS.log: "Failed to find
-- GameEngineTick"), so a 5 ms loop asks the game thread to run 'step', and step works
-- once per rendered frame: when the plane has moved since last time.

local frame = { n = 0, last = nil, t = nil }
local perFrame = {}          -- name -> function(p, dt) ; return false to remove

local function step()
    local p = playerPlane()
    if not p then return end
    local ok, err = pcall(function()
        local l = p:K2_GetActorLocation()
        local t = now()
        -- a new frame when the plane has moved; a parked plane (runway) gets a step every 30 ms
        if frame.last and l.X == frame.last.X and l.Y == frame.last.Y and l.Z == frame.last.Z
            and frame.t and t - frame.t < 0.03 then return end
        frame.last = l
        local dt = frame.t and (t - frame.t) or 0
        frame.t = t
        frame.n = frame.n + 1
        for name, fn in pairs(perFrame) do
            local okf, keep = pcall(fn, p, dt)
            if not okf then log("per-frame '" .. name .. "' failed: " .. tostring(keep)); perFrame[name] = nil
            elseif keep == false then perFrame[name] = nil end
        end
    end)
    if not ok then log("step failed: " .. tostring(err)) end
end

-- Everything this script does runs on the game's own thread. UE4SS runs LoopAsync and
-- ExecuteWithDelay callbacks on a second thread, and its game hooks on the game thread,
-- both in the same Lua state without a lock between them; on 18 Oct 11:34 that clash
-- crashed the game. The *InGameThread* timers below run on the game thread only.
LoopInGameThreadWithDelay(5, function()
    if next(perFrame) then step() end
end)

-- Hooks ------------------------------------------------------------------------------
-- Counts how often each hook fires, and lets the controls probe write inputs from
-- inside the plane's own FrameUpdate call (if the game calls it through the script
-- system every frame).

local hookCount = {}
local hookWrite = nil        -- { roll = x } or { pitch = x } while the probe uses the hook
local function tryHook(path, fn)
    local ok, err = pcall(function()
        RegisterHook(path, function(...)
            hookCount[path] = (hookCount[path] or 0) + 1
            if fn then pcall(fn, ...) end
        end)
    end)
    log("hook " .. path .. ": " .. (ok and "registered" or ("not registered: " .. tostring(err))))
end

tryHook("/Script/Nimbus.PlayerPlane:FrameUpdate", function(self, dt)
    if hookWrite then
        local p = self:get()
        if hookWrite.roll then p.InputRoll = hookWrite.roll end
        if hookWrite.pitch then p.InputPitch = hookWrite.pitch end
    end
end)
tryHook("/Script/Nimbus.Mission:OnStartNextPhaseHandler", function(self, phase, restart)
    event("phase_start", { phase = objName(phase:get()), restart = restart:get() })
end)
tryHook("/Script/Nimbus.Mission:OnSuccessCurrentPhaseHandler", function(self, phase)
    event("phase_cleared", { phase = objName(phase:get()) })
end)
tryHook("/Script/Nimbus.Mission:OnFailCurrentPhaseHandler", function(self, phase, reason)
    event("phase_failed", { phase = objName(phase:get()), reason = reason:get() })
end)
tryHook("/Script/Nimbus.Mission:OnCooldownStartDeadHandler", function() event("player_dead") end)
tryHook("/Script/Nimbus.Mission:OnCooldownStartOutOfZoneHandler", function() event("out_of_zone") end)
tryHook("/Script/Nimbus.Mission:OnCooldownStartTimeOutHandler", function() event("time_out") end)
tryHook("/Script/Nimbus.Mission:OnCooldownStartSuccessfulHandler", function() event("mission_accomplished") end)
tryHook("/Script/Nimbus.Mission:OnCooldownStartFailObjectiveHandler", function() event("objective_failed") end)
tryHook("/Script/Nimbus.Mission:OnBeginIGCHandler", function() event("cutscene_start") end)
tryHook("/Script/Nimbus.Mission:OnEndIGCHandler", function() event("cutscene_end") end)
tryHook("/Script/Nimbus.GameObject:OnDeath", function(self, dead)
    local o = self:get()
    event("death", { who = objName(o), callsign = callsign(o) })
end)

-- Probe 1: controls ------------------------------------------------------------------
-- Writes the plane's own control values (InputRoll, InputPitch, InputThrottle,
-- InputBrake) in several ways and measures whether the plane answers, compared with a
-- stretch where nothing is written.

local probe = nil

local function probeControls()
    if probe then log("a probe is already running") return end
    local p = playerPlane()
    if not p then log("probe controls: no player plane (not in a mission?)") return end
    local csvPath = OUT .. "\\probe-controls-" .. os.date("%H%M%S") .. ".csv"
    local csv = io.open(csvPath, "w")
    if csv then csv:write("t,phase,pitch,yaw,roll,kmh,read_pitch,read_roll,read_throttle,read_brake\n") end
    local function setMove(v) pcall(function() playerPlane().bEnableMovmentInput = v end) end
    local phases = {
        { name = "nothing written",                  dur = 2.0 },
        { name = "InputRoll=+1 every frame",         dur = 1.0, roll = 1 },
        { name = "InputRoll=-1 every frame",         dur = 1.0, roll = -1 },
        { name = "nothing written (2)",              dur = 1.0 },
        { name = "InputPitch=+1 every frame",        dur = 0.7, pitch = 1 },
        { name = "InputPitch=-1 every frame",        dur = 0.7, pitch = -1 },
        { name = "nothing written (3)",              dur = 1.0 },
        { name = "movement input off, InputRoll=+1", dur = 1.0, roll = 1, moveOff = true },
        { name = "movement input off, InputRoll=-1", dur = 1.0, roll = -1, moveOff = true },
        { name = "nothing written (4)",              dur = 1.0 },
        { name = "InputRoll=+1 from FrameUpdate hook", dur = 1.0, hookRoll = 1 },
        { name = "InputRoll=-1 from FrameUpdate hook", dur = 1.0, hookRoll = -1 },
        { name = "nothing written (5)",              dur = 1.0 },
        { name = "InputThrottle=1 every frame",      dur = 2.0, throttle = 1 },
        { name = "InputBrake=1 every frame",         dur = 2.0, brake = 1 },
        { name = "nothing written (6)",              dur = 1.0 },
    }
    probe = { i = 1, t0 = now(), prev = nil, phases = phases, csv = csv, hook0 = {} }
    for k, v in pairs(hookCount) do probe.hook0[k] = v end
    for _, ph in ipairs(phases) do
        ph.frames, ph.dPitch, ph.dYaw, ph.dRoll, ph.kept, ph.checked, ph.time = 0, 0, 0, 0, 0, 0, 0
    end
    log("probe controls started (" .. #phases .. " phases), frame data to " .. csvPath)
    event("probe_start", { probe = "controls" })

    perFrame.probe = function(pl, dt)
        local pr = probe
        if not pr then return false end
        local ph = pr.phases[pr.i]
        local t = now()
        if not ph.start then
            ph.start = t
            setMove(not ph.moveOff)
            hookWrite = ph.hookRoll and { roll = ph.hookRoll } or nil
            ph.kmh0 = call(pl, "GetSpeedKmph")
        end
        local r = pl:K2_GetActorRotation()
        local rp, rr, rt, rb = pl.InputPitch, pl.InputRoll, pl.InputThrottle, pl.InputBrake
        -- did the value we wrote last frame survive until now?
        if pr.wrote then
            ph.checked = ph.checked + 1
            local w = pr.wrote
            if (w.roll == nil or rr == w.roll) and (w.pitch == nil or rp == w.pitch)
                and (w.throttle == nil or rt == w.throttle) and (w.brake == nil or rb == w.brake) then
                ph.kept = ph.kept + 1
            end
        end
        if pr.prev and dt > 0 then
            ph.frames = ph.frames + 1
            ph.time = ph.time + dt
            ph.dPitch = ph.dPitch + wrap180(r.Pitch - pr.prev.Pitch)
            ph.dYaw = ph.dYaw + wrap180(r.Yaw - pr.prev.Yaw)
            ph.dRoll = ph.dRoll + wrap180(r.Roll - pr.prev.Roll)
        end
        pr.prev = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll }
        if pr.csv then
            pr.csv:write(string.format("%.4f,%d,%.3f,%.3f,%.3f,%.1f,%.3f,%.3f,%.3f,%.3f\n",
                t - pr.t0, pr.i, r.Pitch, r.Yaw, r.Roll, call(pl, "GetSpeedKmph") or -1, rp, rr, rt, rb))
        end
        -- write this frame's values
        local w = {}
        if ph.roll then pl.InputRoll = ph.roll; w.roll = ph.roll end
        if ph.pitch then pl.InputPitch = ph.pitch; w.pitch = ph.pitch end
        if ph.throttle then pl.InputThrottle = ph.throttle; w.throttle = ph.throttle end
        if ph.brake then pl.InputBrake = ph.brake; w.brake = ph.brake end
        pr.wrote = next(w) and w or nil
        if t - ph.start >= ph.dur then
            ph.kmh1 = call(pl, "GetSpeedKmph")
            pr.i = pr.i + 1
            pr.prev = nil
            pr.wrote = nil
            if pr.i > #pr.phases then
                setMove(true)
                hookWrite = nil
                pcall(function() pl.InputRoll = 0; pl.InputPitch = 0; pl.InputThrottle = 0; pl.InputBrake = 0 end)
                if pr.csv then pr.csv:close() end
                log("probe controls finished. Per phase: rotation per second (pitch, heading, roll), speed change, and how often a written value was still there next frame:")
                for k, x in ipairs(pr.phases) do
                    local T = math.max(x.time, 0.001)
                    log(string.format("  %2d %-36s %3d frames  pitch %+7.1f/s  heading %+7.1f/s  roll %+7.1f/s  speed %s -> %s km/h  kept %d of %d",
                        k, x.name, x.frames, x.dPitch / T, x.dYaw / T, x.dRoll / T, fmt(x.kmh0), fmt(x.kmh1), x.kept, x.checked))
                end
                local hooks = {}
                for k, v in pairs(hookCount) do
                    hooks[#hooks + 1] = string.format("%s +%d", k:match("[^:]+$"), v - (pr.hook0[k] or 0))
                end
                log("  hook calls during the probe: " .. (#hooks > 0 and table.concat(hooks, ", ") or "none"))
                event("probe_end", { probe = "controls" })
                probe = nil
                return false
            end
        end
        return true
    end
end

-- Probe 2: weapons -------------------------------------------------------------------
-- Presses missile, gun and flare through the plane's weapon component and reads the
-- counts before and after.

local function later(ms, fn)
    ExecuteInGameThreadWithDelay(ms, function()
        local ok, err = pcall(fn)
        if not ok then log("delayed step failed: " .. tostring(err)) end
    end)
end

local function counts(w)
    return string.format("missiles %s, gun %s, flares %s, special %s, armed %s",
        fmt(call(w, "GetMainWeaponCount")), fmt(call(w, "GetGunCount")), fmt(call(w, "GetFlareCount")),
        fmt(call(w, "GetSpecialWeaponCount")), objName(call(w, "GetArmedWeapon")))
end

local function probeWeapons()
    local p = playerPlane()
    if not p then log("probe weapons: no player plane") return end
    local w = weapons(p)
    if not w then log("probe weapons: no PlayerWeaponActivator on " .. objName(p)) return end
    log("probe weapons: before: " .. counts(w) .. "; special armed " .. tostring(call(p, "IsSpecialWeaponArmed")))
    local okP, errP = pcall(function() w:MainWeaponPressed() end)
    log("  MainWeaponPressed: " .. (okP and "no error" or tostring(errP)))
    later(150, function()
        pcall(function() w:MainWeaponReleased() end)
        log("  0.15 s later, MainWeaponReleased: " .. counts(w))
    end)
    later(1500, function()
        log("  1.5 s after the missile press: " .. counts(w))
        local ok2, e2 = pcall(function() w:MachineGunPressed() end)
        log("  MachineGunPressed: " .. (ok2 and "no error" or tostring(e2)))
    end)
    later(2500, function()
        pcall(function() w:MachineGunReleased() end)
        log("  after 1 s of gun, MachineGunReleased: " .. counts(w))
        local ok3, e3 = pcall(function() w:FlarePressed() end)
        log("  FlarePressed: " .. (ok3 and "no error" or tostring(e3)))
    end)
    later(2700, function()
        pcall(function() w:FlareReleased() end)
        log("  0.2 s later, FlareReleased: " .. counts(w))
    end)
    later(3500, function()
        log("  after flares: " .. counts(w))
        local ok4, e4 = pcall(function() w:ToggleSpecial() end)
        log("  ToggleSpecial: " .. (ok4 and "no error" or tostring(e4)) .. "; special armed now " .. tostring(call(p, "IsSpecialWeaponArmed")))
    end)
    later(4500, function()
        log("  1 s later: " .. counts(w) .. "; special armed " .. tostring(call(p, "IsSpecialWeaponArmed")))
        pcall(function() w:ToggleSpecial() end)
        log("  ToggleSpecial again: special armed " .. tostring(call(p, "IsSpecialWeaponArmed")))
    end)
end

-- Probe 3: targets -------------------------------------------------------------------

local function describeTarget(p, o)
    if not o then return "none" end
    local d = "?"
    pcall(function() d = string.format("%.0f m", dist(o:K2_GetActorLocation(), p:K2_GetActorLocation()) / 10) end)
    return string.format("%s (%s, %s, health %s)", objName(o), callsign(o), d, fmt(call(o, "GetHealth")))
end

local function probeTargets()
    local p = playerPlane()
    if not p then log("probe targets: no player plane") return end
    local ts = targetSelection(p)
    log("probe targets: target selection component " .. objName(ts))
    log("  plane:GetSelectedTarget " .. describeTarget(p, call(p, "GetSelectedTarget")) ..
        "; plane:GetLockedOnTarget " .. describeTarget(p, call(p, "GetLockedOnTarget")))
    if ts then
        log("  ts:GetSelectedTarget " .. describeTarget(p, call(ts, "GetSelectedTarget")))
        local locked = call(ts, "GetAllLockedOnTargets")
        local n = 0
        pcall(function() locked:ForEach(function(i, e) n = n + 1 end) end)
        log("  ts:GetAllLockedOnTargets: " .. n .. " targets")
        for k = 1, 3 do
            local okS, r = pcall(function() return ts:SelectTarget(false) end)
            log(string.format("  SelectTarget(false) #%d: %s -> now selected %s", k, okS and objName(r) or tostring(r),
                describeTarget(p, call(ts, "GetSelectedTarget"))))
        end
    end
    -- what is around: active, living game objects the player is meant to attack
    local rows = {}
    for _, o in ipairs(FindAllOf("GameObject") or {}) do
        local okR, row = pcall(function()
            if not o.bIsActivated then return nil end
            if not o:IsAlive() then return nil end
            local cls = o:GetClass():GetFName():ToString()
            local fac, tg = -1, false
            pcall(function() fac = o:GetFaction() end)
            pcall(function() tg = o:IsTGT() end)
            return { cls = cls, tgt = tg, fac = fac, d = dist(o:K2_GetActorLocation(), p:K2_GetActorLocation()) / 10,
                     name = objName(o), cs = callsign(o) }
        end)
        if okR and row then rows[#rows + 1] = row end
    end
    table.sort(rows, function(a, b) return a.d < b.d end)
    local nT = 0
    for _, r in ipairs(rows) do if r.tgt then nT = nT + 1 end end
    local nE = 0
    for _, r in ipairs(rows) do if r.fac == 0 then nE = nE + 1 end end
    log(string.format("  %d active living game objects, %d enemies, %d mission targets (TGT); enemies and the nearest others:", #rows, nE, nT))
    local shown = 0
    for i, r in ipairs(rows) do
        if r.fac == 0 or i <= 6 then
            shown = shown + 1
            if shown > 25 then break end
            log(string.format("    %6.0f m  %s TGT=%-5s %-28s %-20s %s", r.d, r.fac == 0 and "ENEMY" or (r.fac == 1 and "ally " or "?    "), tostring(r.tgt), r.cls, r.cs, r.name))
        end
    end
end

-- Probe 4: mission -------------------------------------------------------------------

local function probeMission()
    local s = snapshot()
    log("probe mission: " .. json(s))
    local hooks = {}
    for k, v in pairs(hookCount) do hooks[#hooks + 1] = string.format("%s %d", k:match("[^:]+$"), v) end
    log("  hook calls so far: " .. (#hooks > 0 and table.concat(hooks, ", ") or "none"))
    local m = mission()
    if m then
        local n = call(m, "GetKillStatCount") or 0
        log("  kill stats: " .. tostring(n))
    end
end

-- Autopilot (stage 3) ----------------------------------------------------------------
-- The pilot flies with the keyboard, as a person would: the game takes no notice of
-- control values a script writes into the plane, and Steam's overlay keeps a virtual
-- gamepad from reaching it (workbench section 10). Keys go through CoopPadMod, only while
-- the game window is in front. The owner's key bindings (Options > Keyboard, 18 Oct 2026):
local KEY = { pitch_up = "3", pitch_down = "1", roll_left = "A", roll_right = "D", yaw_left = "Q", yaw_right = "E",
              throttle = "W", brake = "S", missile = "Space", gun = "Ctrl", flare = "G", next_target = "Tab",
              weapon = "C", high_g = "2", autopilot = "Z" }
-- Measured in Free Flight (Typhoon): A/D roll up to ~160 deg/s and keep rolling (no bank
-- limit); 3/1 pitch up to ~36 deg/s; both build up over about half a second after the key
-- goes down and fade out over a similar time after it comes up. One game unit = 10 cm.

local function axes(rot)
    local p, y, r = math.rad(rot.Pitch), math.rad(rot.Yaw), math.rad(rot.Roll)
    local SP, CP, SY, CY, SR, CR = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    -- Unreal's rotation matrix: X forward, Y right, Z up
    return { CP * CY, CP * SY, SP },
           { SR * SP * CY - CR * SY, SR * SP * SY + CR * CY, -SR * CP },
           { -(CR * SP * CY + SR * SY), CY * SR - CR * SP * SY, CR * CP }
end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function unit(v)
    local l = math.sqrt(dot(v, v))
    if l < 1e-9 then return { 1, 0, 0 }, 0 end
    return { v[1] / l, v[2] / l, v[3] / l }, l
end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- Keys are on or off, so a gentle input is made by pressing in a share of the frames,
-- spread evenly (a sigma-delta pulse): 0.3 = pressed in 3 frames out of 10.
local pulseAcc = {}
local function pulse(axis, u)
    local s = (pulseAcc[axis] or 0) + math.abs(u)
    if s >= 1 then pulseAcc[axis] = s - 1; return u > 0 and 1 or -1 end
    pulseAcc[axis] = s
    return 0
end

local ap = nil                -- the autopilot's goal and memory while it flies
local flightFile, flightAt = nil, -1

local function pd(name, e, dt, kp, kd)
    local prev = ap.prevErr[name]
    ap.prevErr[name] = e
    local de = 0
    if prev and dt > 0 then de = wrap180(e - prev) / dt end
    ap.rate[name] = (ap.rate[name] or 0) * 0.7 + de * 0.3   -- smoothed: per-frame differences are noisy
    return clamp(kp * e + kd * ap.rate[name], -1, 1)
end

-- Where the nose should point this frame (a unit vector in the world), for the goal.
local function aimFor(p, loc, rot, alt)
    local g = ap.goal
    if g.kind == "heading" then
        local h = math.rad(g.heading)
        local climb = clamp((g.alt - alt) / 1500, -0.45, 0.45)
        return unit({ math.cos(h), math.sin(h), climb })
    elseif g.kind == "point" then
        local d = { g.x - loc.X, g.y - loc.Y, 0 }
        local _, horiz = unit(d)
        local h = unit(d)
        local climb = clamp((g.z - loc.Z) / math.max(horiz, 1), -0.6, 0.6)
        return unit({ h[1], h[2], climb })
    elseif g.kind == "object" then
        local ok, tl = pcall(function() return g.obj:K2_GetActorLocation() end)
        if not ok then return nil end
        return unit({ tl.X - loc.X, tl.Y - loc.Y, tl.Z - loc.Z })
    end
    return nil
end

-- Combat (stage 4) --------------------------------------------------------------------
-- Picks targets the way a player does (Tab cycles through them; the game's own selection
-- is read back), flies at a point a little ahead of the target, fires a missile when the
-- game shows a lock, the gun when close and on the nose, and on a missile warning drops
-- flares and breaks hard. Kills, shots, damage and warnings go to the event log.

local function alive(o)
    local ok, a = pcall(function() return o:IsValid() and o:IsAlive() end)
    return ok and a
end

local function locOf(o)
    local ok, l = pcall(function() return o:K2_GetActorLocation() end)
    if ok and l then return l end
    return nil
end

local function sameObj(a, b)
    if not a or not b then return false end
    local ok, same = pcall(function() return a:IsValid() and b:IsValid() and a:GetFullName() == b:GetFullName() end)
    return ok and same
end

-- The nearest living enemy the mission wants destroyed (slow: the whole object list, so
-- at most every 2 s), used when Tab finds nothing on the radar yet.
local function nearestEnemy(loc)
    local best, bestD = nil, math.huge
    for _, o in ipairs(FindAllOf("GameObject") or {}) do
        local ok, d = pcall(function()
            -- AIGameObject:GetFaction(): 0 = enemy, 1 = ally; IsTGT(): a target the mission counts
            if not o.bIsActivated or o:GetFaction() ~= 0 or not o:IsAlive() then return nil end
            local l = o:K2_GetActorLocation()
            local d2 = (l.X - loc.X) ^ 2 + (l.Y - loc.Y) ^ 2 + (l.Z - loc.Z) ^ 2
            if not o:IsTGT() then d2 = d2 * 2.25 end      -- mission targets first
            return d2
        end)
        if ok and d and d < bestD then best, bestD = o, d end
    end
    return best, math.sqrt(bestD) / 10
end

local function tap(c, key, seconds)
    c.taps[key] = now() + (seconds or 0.08)   -- hold a few frames so the game sees the press
end

local function combatStep(p, loc, rot, F, R, alt, dt)
    local c = ap.combat
    local t = now()
    local keys = {}
    local ts = targetSelection(p)
    local tgt = ts and call(ts, "GetSelectedTarget")
    if tgt and not alive(tgt) then tgt = nil end

    -- the previous target: did it die?
    if c.target and not sameObj(c.target, tgt) then
        if not alive(c.target) then
            c.kills = c.kills + 1
            event("kill", { target = c.targetName, callsign = c.targetCallsign, after_s = t - c.targetSince, missiles = c.shotsAtTarget })
            log(string.format("  KILL: %s %s after %.0f s, %d missiles", c.targetName, c.targetCallsign, t - c.targetSince, c.shotsAtTarget))
        end
        c.target = nil
    end
    if tgt and not c.target then
        c.target, c.targetSince, c.shotsAtTarget, c.prevTL, c.tv = tgt, t, 0, nil, nil
        c.targetName, c.targetCallsign = objName(tgt), callsign(tgt)
        local tl = locOf(tgt)
        event("target", { target = c.targetName, callsign = c.targetCallsign, dist_m = tl and math.sqrt((tl.X - loc.X) ^ 2 + (tl.Y - loc.Y) ^ 2 + (tl.Z - loc.Z) ^ 2) / 10 or -1 })
    end

    -- defence: missile warning -> flares and a hard break for two seconds
    local alert = 0
    pcall(function() alert = p.MissileAlert end)
    alert = tonumber(alert) or 0
    if alert ~= c.lastAlert then
        if alert > 0 then event("missile_warning", { level = alert == 2 and "very near" or "near" }) end
        c.lastAlert = alert
    end
    if alert >= 2 and t - c.lastFlare > 1.5 then
        tap(c, KEY.flare); c.lastFlare = t; c.flares = c.flares + 1
        event("flare", {})
        c.breakUntil = t + 2.0
        c.breakDir = (c.breakDir or 1) * -1
    end

    local aim, text
    if c.breakUntil and t < c.breakUntil then
        -- break turn: put a wing toward the ground side and pull
        aim = unit({ R[1] * c.breakDir + F[1] * 0.2, R[2] * c.breakDir + F[2] * 0.2, 0.15 })
        text = "BREAK (missile warning)"
    elseif not tgt then
        if t - c.lastTab > 0.7 then tap(c, KEY.next_target); c.lastTab = t end
        if t - c.scanAt > 2 then
            c.scanAt = t
            c.scanTarget, c.scanDist = nearestEnemy(loc)
        end
        local st = c.scanTarget and alive(c.scanTarget) and locOf(c.scanTarget)
        if st then
            local hd = math.sqrt((st.X - loc.X) ^ 2 + (st.Y - loc.Y) ^ 2)
            aim = unit({ st.X - loc.X, st.Y - loc.Y, clamp(st.Z - loc.Z, -0.3 * hd, 0.3 * hd) })
            text = string.format("no target selected; flying toward %s %s %.0f m away", objName(c.scanTarget), callsign(c.scanTarget), c.scanDist or -1)
            c.speed = 1150
        else
            local h = unit({ F[1], F[2], 0 })
            aim = unit({ h[1] - R[1] * 0.15, h[2] - R[2] * 0.15, clamp((1500 - alt) / 1500, -0.3, 0.3) })
            text = "no targets anywhere; circling"
            c.speed = 650
        end
    else
        local tl = locOf(tgt)
        if c.prevTL and dt > 0 then
            local v = { (tl.X - c.prevTL.X) / dt, (tl.Y - c.prevTL.Y) / dt, (tl.Z - c.prevTL.Z) / dt }
            if c.tv then c.tv = { c.tv[1] * 0.85 + v[1] * 0.15, c.tv[2] * 0.85 + v[2] * 0.15, c.tv[3] * 0.85 + v[3] * 0.15 }
            else c.tv = v end
        end
        c.prevTL = { X = tl.X, Y = tl.Y, Z = tl.Z }
        local dir, du = unit({ tl.X - loc.X, tl.Y - loc.Y, tl.Z - loc.Z })
        local dm = du / 10
        local tv = c.tv or { 0, 0, 0 }
        local lead = clamp(dm / 900, 0, 1.2)            -- about the gun's flight time
        aim = unit({ tl.X + tv[1] * lead - loc.X, tl.Y + tv[2] * lead - loc.Y, tl.Z + tv[3] * lead - loc.Z })
        local offT = math.deg(math.acos(clamp(dot(dir, F), -1, 1)))
        local locked = sameObj(call(p, "GetLockedOnTarget"), tgt)
        if locked and dm < c.missileRange and offT < 40 and t - c.lastMissile > c.missileGap then
            tap(c, KEY.missile); c.lastMissile = t; c.shots = c.shots + 1; c.shotsAtTarget = c.shotsAtTarget + 1
            event("missile", { target = c.targetName, dist_m = dm, off_deg = offT })
        end
        if dm < 1000 and offT < 5 then keys[#keys + 1] = KEY.gun; c.gunFrames = c.gunFrames + 1 end
        if dm < 300 and offT < 30 then
            -- about to fly into it: pull up and away
            aim = unit({ F[1] + 0.0, F[2], F[3] + 0.8 })
        end
        text = string.format("target %s %s %.0f m, %.0f deg off nose%s", c.targetName, c.targetCallsign, dm, offT, locked and ", LOCKED" or "")
        c.speed = dm > 3000 and 1150 or (dm > 1200 and 850 or 650)   -- close the distance fast, then slow for the turn fight
        c.lastDist = dm
    end

    for key, untilT in pairs(c.taps) do
        if t < untilT then keys[#keys + 1] = key else c.taps[key] = nil end
    end
    c.text = text
    return aim, keys
end

local function apStep(p, dt)
    if not ap then return false end
    local t = now() - ap.t0
    if ap.duration and t >= ap.duration then
        CoopKeys_Set("")
        log(string.format("fly: finished after %.0f s (%d frames, %d of them in ground recovery)", t, ap.frames, ap.recoverFrames))
        event("autopilot_end", { reason = "time" })
        ap = nil
        return false
    end
    ap.frames = ap.frames + 1
    local loc = p:K2_GetActorLocation()
    local rot = p:K2_GetActorRotation()
    local F, R, U = axes(rot)
    -- The game paused (focus lost, a menu) or the mission ended: the plane stops moving.
    if ap.lastLoc and loc.X == ap.lastLoc.X and loc.Y == ap.lastLoc.Y and loc.Z == ap.lastLoc.Z then
        ap.stillFor = (ap.stillFor or 0) + dt
        if ap.stillFor > 1.5 and not ap.frozen then
            ap.frozen = true
            CoopKeys_Set("")
            log("  fly: the plane has stopped moving (game paused, a menu, or the mission is over); keys let go")
            event("frozen", {})
        end
        if ap.frozen then return true end
    else
        if ap.frozen then log("  fly: moving again"); event("unfrozen", {}) end
        ap.stillFor, ap.frozen = 0, false
    end
    ap.lastLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }
    -- damage taken
    local health = call(p, "GetHealth")
    if health and ap.lastHealth and health < ap.lastHealth then
        event("damage", { amount = ap.lastHealth - health, health = health, alt_m = call(p, "GetAltitudeMeters") })
        log(string.format("  DAMAGE: -%s, health now %s", fmt(ap.lastHealth - health), fmt(health)))
    end
    ap.lastHealth = health
    local alt = call(p, "GetAltitudeMeters") or (loc.Z / 10)
    local kmh = call(p, "GetSpeedKmph") or 0
    local vz = 0
    if ap.lastZ and dt > 0 then vz = (loc.Z - ap.lastZ) / 10 / dt end
    ap.lastZ = loc.Z
    ap.vz = (ap.vz or 0) * 0.8 + vz * 0.2

    local aim, extraKeys
    if ap.goal.kind == "attack" then
        aim, extraKeys = combatStep(p, loc, rot, F, R, alt, dt)
    else
        aim = aimFor(p, loc, rot, alt)
    end
    if not aim then aim = F end
    -- Keep inside the mission area: past the pull-out line, head back to where the order began.
    if call(p, "IsBeyondPulloutLine") then
        if not ap.wasOutside then event("beyond_pullout", {}); log("  fly: past the mission area's edge, turning back") end
        ap.wasOutside = true
        aim = unit({ ap.home.X - loc.X, ap.home.Y - loc.Y, 0 })
    else
        ap.wasOutside = false
    end
    -- Stay alive: below the floor, or heading for it within 4 s, climb away first.
    local floor = ap.floor
    local recovering = alt < floor or alt + ap.vz * 4 < floor * 0.7
    if recovering then
        local h = unit({ F[1], F[2], 0 })
        aim = unit({ h[1], h[2], 0.6 })
        ap.recoverFrames = ap.recoverFrames + 1
        if not ap.wasRecovering and now() - (ap.recoveryLoggedAt or -100) > 5 then
            ap.recoveryLoggedAt = now()
            event("ground_recovery", { alt_m = alt, vz = ap.vz })
        end
    end
    ap.wasRecovering = recovering

    local f, r, u = dot(aim, F), dot(aim, R), dot(aim, U)
    local off = math.deg(math.acos(clamp(f, -1, 1)))
    local bankErr = math.deg(math.atan(r, u))     -- roll this far (+ = right) to put the aim above the canopy
    local elev = math.deg(math.atan(u, f))        -- aim above (+) or below the nose, in the plane's own frame
    local side = math.deg(math.atan(r, f))        -- aim right (+) or left of the nose

    -- Two ways of steering: a big turn banks toward the aim and pulls; small corrections
    -- keep the wings level with the horizon and nudge the nose with pitch and rudder.
    if ap.big then
        if off < 6 then ap.big = false end
    elseif off > 12 then
        ap.big = true
    end
    local rollCmd, pitchCmd, yawCmd
    if ap.big then
        rollCmd = pd("bank", bankErr, dt, 1 / 35, 1 / 160)
        if math.abs(bankErr) < 50 then pitchCmd = clamp(elev / 12, -1, 1) else pitchCmd = 0 end
        if elev < 0 and math.abs(bankErr) < 50 then pitchCmd = 0 end   -- never push hard in a turn; roll and pull instead
        yawCmd = 0
        ap.prevErr.level, ap.prevErr.elev, ap.prevErr.side = nil, nil, nil
    else
        rollCmd = pd("level", -rot.Roll + clamp(side * 3, -35, 35), dt, 1 / 30, 1 / 140)
        pitchCmd = pd("elev", elev, dt, 1 / 6, 1 / 25)
        yawCmd = pd("side", side, dt, 1 / 3, 1 / 20)
        ap.prevErr.bank = nil
    end
    if recovering and math.abs(rot.Roll) > 90 then pitchCmd = 0 end   -- upside down near the ground: roll first

    local keys = {}
    local v = pulse("roll", rollCmd)
    if v > 0 then keys[#keys + 1] = KEY.roll_right elseif v < 0 then keys[#keys + 1] = KEY.roll_left end
    v = pulse("pitch", pitchCmd)
    if v > 0 then keys[#keys + 1] = KEY.pitch_up elseif v < 0 then keys[#keys + 1] = KEY.pitch_down end
    v = pulse("yaw", yawCmd)
    if v > 0 then keys[#keys + 1] = KEY.yaw_right elseif v < 0 then keys[#keys + 1] = KEY.yaw_left end
    local speed = (ap.combat and ap.combat.speed) or ap.goal.speed or 650
    if kmh < speed - 25 then keys[#keys + 1] = KEY.throttle elseif kmh > speed + 40 then keys[#keys + 1] = KEY.brake end
    for _, k in ipairs(extraKeys or {}) do keys[#keys + 1] = k end
    local list = table.concat(keys, ",")
    local inFront = CoopKeys_Set(list)

    if t - ap.lastLog >= 1.0 then
        ap.lastLog = t
        log(string.format("  fly %.0f s: %s | alt %.0f m (vz %+.0f m/s), %.0f km/h, pitch %.0f, heading %.0f, roll %.0f | aim off %.0f deg (bank err %+.0f, elev %+.0f, side %+.0f) %s | roll %+.2f pitch %+.2f yaw %+.2f keys [%s]%s",
            t, ap.goal.text, alt, ap.vz, kmh, rot.Pitch, rot.Yaw, rot.Roll, off, bankErr, elev, side,
            ap.big and "TURN" or "fine", rollCmd, pitchCmd, yawCmd, list,
            recovering and " GROUND RECOVERY" or (inFront == false and " (game not in front: no keys)" or "")))
        if ap.combat and ap.combat.text then
            local c = ap.combat
            log(string.format("    combat: %s | kills %d, missiles %d, gun frames %d, flares %d", c.text, c.kills, c.shots, c.gunFrames, c.flares))
        end
    end
    if flightFile and t - flightAt >= 0.1 then
        flightAt = t
        flightFile:write(string.format("%.3f,%.1f,%.1f,%.1f,%.2f,%.2f,%.2f,%.1f,%.1f,%.1f,%s,%.1f,%s,%s\n",
            now(), loc.X, loc.Y, loc.Z, rot.Pitch, rot.Yaw, rot.Roll, kmh, alt, call(p, "GetHealth") or -1,
            ap.big and "turn" or "fine", off, recovering and 1 or 0, list))
    end
    return true
end

-- "takeoff": full throttle down the runway, a gentle pull once fast enough, done above
-- 80 m. Then whatever order comes next takes over.
local function takeoffOrder(args)
    if type(CoopKeys_Set) ~= "function" then log("takeoff: CoopPadMod is not loaded (no keys)") return end
    local t0 = now()
    log("takeoff: full throttle")
    event("takeoff_start", {})
    perFrame.takeoff = function(p, dt)
        local t = now() - t0
        local kmh = call(p, "GetSpeedKmph") or 0
        local alt = call(p, "GetAltitudeMeters") or 0
        if alt > 80 or t > 40 then
            CoopKeys_Set("")
            log(string.format("takeoff: %s after %.0f s (%.0f m, %.0f km/h)", alt > 80 and "airborne" or "gave up", t, alt, kmh))
            event("takeoff_end", { ok = alt > 80, after_s = t })
            return false
        end
        local keys = KEY.throttle
        if kmh > 260 and pulse("pitch", 0.35) > 0 then keys = keys .. "," .. KEY.pitch_up end
        CoopKeys_Set(keys)
        return true
    end
end

local function flyOrder(args)
    -- fly heading 90 alt 1500 [speed 650] [for 30] [floor 300]
    -- fly to <x> <y> <z>   (game units)         fly stop
    if args[1] == "stop" then
        ap = nil; perFrame.fly = nil
        if type(CoopKeys_Set) == "function" then CoopKeys_Set("") end
        log("fly: stopped"); return
    end
    if type(CoopKeys_Set) ~= "function" then log("fly: CoopPadMod is not loaded (no keys)") return end
    local goal, i = {}, 1
    local opts = { floor = 300 }
    while i <= #args do
        local k = args[i]
        if k == "heading" then goal.kind = "heading"; goal.heading = tonumber(args[i + 1]); i = i + 2
        elseif k == "alt" then goal.alt = tonumber(args[i + 1]); i = i + 2
        elseif k == "speed" then goal.speed = tonumber(args[i + 1]); i = i + 2
        elseif k == "for" then opts.duration = tonumber(args[i + 1]); i = i + 2
        elseif k == "floor" then opts.floor = tonumber(args[i + 1]); i = i + 2
        elseif k == "attack" then goal.kind = "attack"; i = i + 1
        elseif k == "range" then opts.range = tonumber(args[i + 1]); i = i + 2
        elseif k == "to" then
            goal.kind = "point"; goal.x, goal.y, goal.z = tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3]); i = i + 4
        else log("fly: did not understand '" .. tostring(k) .. "'") return end
    end
    if goal.kind == "heading" then goal.alt = goal.alt or 1500 end
    if not goal.kind then log("fly: give 'heading H alt A', 'to X Y Z' or 'attack'") return end
    goal.text = table.concat(args, " ")
    local p0 = playerPlane()
    local home = p0 and p0:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
    ap = { goal = goal, t0 = now(), frames = 0, recoverFrames = 0, lastLog = -1, prevErr = {}, rate = {},
           floor = opts.floor, duration = opts.duration, big = false, home = { X = home.X, Y = home.Y, Z = home.Z } }
    if goal.kind == "attack" then
        ap.combat = { kills = 0, shots = 0, shotsAtTarget = 0, gunFrames = 0, flares = 0, lastMissile = -100, lastTab = -100,
                      lastFlare = -100, scanAt = -100, taps = {}, lastAlert = 0,
                      missileRange = opts.range or 3000, missileGap = 1.2 }
        goal.speed = goal.speed or 700
    end
    -- a new flight log for every order, so the test runner can file each attempt's own
    if flightFile then flightFile:close() end
    flightFile = io.open(OUT .. "\\flight-" .. os.date("%Y%m%d-%H%M%S") .. ".csv", "w")
    if flightFile then flightFile:write("clock,x,y,z,pitch,yaw,roll,kmh,alt_m,health,mode,aim_off_deg,recovering,keys\n") end
    log("fly: " .. goal.text)
    event("autopilot_start", { goal = goal.text })
    perFrame.fly = apStep
end

-- Orders -----------------------------------------------------------------------------

local function stopAll()
    probe = nil
    ap = nil
    hookWrite = nil
    for k in pairs(perFrame) do perFrame[k] = nil end
    pcall(function()
        local p = playerPlane()
        if p then p.bEnableMovmentInput = true; p.InputRoll = 0; p.InputPitch = 0; p.InputThrottle = 0; p.InputBrake = 0 end
    end)
    if type(CoopPad_Release) == "function" then CoopPad_Release() end
    if type(CoopKeys_Set) == "function" then CoopKeys_Set("") end
    log("stopped: no probe, nothing written any more, gamepad and keys let go")
end

-- "hold throttle 1 pitch 0.3 for 8": write these control values every frame for a while,
-- logging speed, height and attitude every half second. Names: pitch, roll, throttle,
-- brake, lyaw, ryaw (the plane's InputPitch, InputRoll, ...).
local INPUT_FIELDS = { pitch = "InputPitch", roll = "InputRoll", throttle = "InputThrottle", brake = "InputBrake",
                       lyaw = "InputLeftYaw", ryaw = "InputRightYaw" }
local function holdInputs(args)
    local vals, dur = {}, 5
    local i = 1
    while i <= #args do
        local k, v = args[i], tonumber(args[i + 1])
        if k == "for" and v then dur = v
        elseif INPUT_FIELDS[k] and v then vals[INPUT_FIELDS[k]] = v
        else log("hold: did not understand '" .. tostring(k) .. " " .. tostring(args[i + 1]) .. "'") return end
        i = i + 2
    end
    local t0, lastLog, frames = now(), -1, 0
    log("hold started for " .. dur .. " s: " .. json(vals))
    perFrame.hold = function(p, dt)
        local t = now() - t0
        if t >= dur then
            for f in pairs(vals) do pcall(function() p[f] = 0 end) end
            log(string.format("hold finished after %d frames", frames))
            return false
        end
        frames = frames + 1
        for f, v in pairs(vals) do p[f] = v end
        if t - lastLog >= 0.5 then
            lastLog = t
            local r = p:K2_GetActorRotation()
            log(string.format("  %.1f s: %s km/h, %s m, pitch %.1f, heading %.1f, roll %.1f, read back pitch %s roll %s throttle %s",
                t, fmt(call(p, "GetSpeedKmph")), fmt(call(p, "GetAltitudeMeters")), r.Pitch, r.Yaw, r.Roll,
                fmt(p.InputPitch), fmt(p.InputRoll), fmt(p.InputThrottle)))
        end
        return true
    end
end

-- The virtual gamepad (cpp\CoopPad + CoopPadMod): sticks -1..1, triggers 0..1, buttons.
local PAD_BUTTONS = { up = 0x0001, down = 0x0002, left = 0x0004, right = 0x0008, start = 0x0010, back = 0x0020,
                      ls = 0x0040, rs = 0x0080, lb = 0x0100, rb = 0x0200, a = 0x1000, b = 0x2000, x = 0x4000, y = 0x8000 }
local pad = { lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, rt = 0, buttons = 0 }
local function padSend()
    if type(CoopPad_Set) ~= "function" then return false end
    return CoopPad_Set(pad.lx, pad.ly, pad.rx, pad.ry, pad.lt, pad.rt, pad.buttons)
end
local function padNeutral()
    pad.lx, pad.ly, pad.rx, pad.ry, pad.lt, pad.rt, pad.buttons = 0, 0, 0, 0, 0, 0, 0
    if type(CoopPad_Release) == "function" then CoopPad_Release() end
end

-- "pad lx 1 for 2" / "pad ly -0.5 rt 1 buttons a,lb for 3": hold the virtual pad in that
-- position every frame for a while, logging attitude, speed and height every 0.25 s.
local function padHold(args)
    local want, dur = { lx = 0, ly = 0, rx = 0, ry = 0, lt = 0, rt = 0, buttons = 0 }, 2
    local i = 1
    while i <= #args do
        local k, v = args[i], args[i + 1]
        if k == "for" and tonumber(v) then dur = tonumber(v)
        elseif k == "buttons" and v then
            for b in v:gmatch("[^,]+") do want.buttons = want.buttons | (PAD_BUTTONS[b] or 0) end
        elseif want[k] ~= nil and tonumber(v) then want[k] = tonumber(v)
        else log("pad: did not understand '" .. tostring(k) .. " " .. tostring(v) .. "'") return end
        i = i + 2
    end
    if type(CoopPad_Set) ~= "function" then log("pad: CoopPadMod is not loaded") return end
    local t0, lastLog, frames, prev = now(), -1, 0, nil
    log("pad started for " .. dur .. " s: " .. json(want) .. "; " .. tostring(CoopPad_Status()))
    perFrame.pad = function(p, dt)
        local t = now() - t0
        local r = p:K2_GetActorRotation()
        if t >= dur then
            padNeutral()
            log(string.format("pad finished after %d frames; %s", frames, tostring(CoopPad_Status())))
            return false
        end
        frames = frames + 1
        for k, v in pairs(want) do pad[k] = v end
        padSend()
        if t - lastLog >= 0.25 then
            local rate = ""
            if prev then
                local d = t - prev.t
                rate = string.format(" (per second: pitch %+.0f, heading %+.0f, roll %+.0f)",
                    wrap180(r.Pitch - prev.pitch) / d, wrap180(r.Yaw - prev.yaw) / d, wrap180(r.Roll - prev.roll) / d)
            end
            prev = { t = t, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
            lastLog = t
            log(string.format("  %.2f s: %s km/h, %s m, pitch %.1f, heading %.1f, roll %.1f%s",
                t, fmt(call(p, "GetSpeedKmph")), fmt(call(p, "GetAltitudeMeters")), r.Pitch, r.Yaw, r.Roll, rate))
        end
        return true
    end
end

-- "keys D for 1" / "keys W,S for 2" / "keys D duty 0.3 for 2": hold keyboard keys every
-- frame (through CoopPadMod, only while the game is in front), logging the plane's
-- attitude every 0.25 s. "duty 0.3" presses the keys in 30% of the frames, spread evenly.
local function keysHold(args)
    local names, dur, duty = args[1] or "", 1, 1
    local i = 2
    while i <= #args do
        local k, v = args[i], tonumber(args[i + 1])
        if k == "for" and v then dur = v elseif k == "duty" and v then duty = v
        else log("keys: did not understand '" .. tostring(args[i]) .. "'") return end
        i = i + 2
    end
    if type(CoopKeys_Set) ~= "function" then log("keys: CoopPadMod is not loaded") return end
    local t0, lastLog, frames, on, acc, prev = now(), -1, 0, 0, 0, nil
    log("keys started for " .. dur .. " s: " .. names .. " (duty " .. duty .. ")")
    perFrame.keys = function(p, dt)
        local t = now() - t0
        local r = p:K2_GetActorRotation()
        if t >= dur then
            CoopKeys_Set("")
            log(string.format("keys finished after %d frames (%d pressed); %s", frames, on, CoopKeys_Status()))
            return false
        end
        frames = frames + 1
        acc = acc + duty
        local press = acc >= 1
        if press then acc = acc - 1; on = on + 1 end
        CoopKeys_Set(press and names or "")
        if t - lastLog >= 0.25 then
            local rate = ""
            if prev then
                local d = t - prev.t
                rate = string.format(" (per second: pitch %+.0f, heading %+.0f, roll %+.0f)",
                    wrap180(r.Pitch - prev.pitch) / d, wrap180(r.Yaw - prev.yaw) / d, wrap180(r.Roll - prev.roll) / d)
            end
            prev = { t = t, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
            lastLog = t
            log(string.format("  %.2f s: %s km/h, %s m, pitch %.1f, heading %.1f, roll %.1f%s",
                t, fmt(call(p, "GetSpeedKmph")), fmt(call(p, "GetAltitudeMeters")), r.Pitch, r.Yaw, r.Roll, rate))
        end
        return true
    end
end

-- "set bEnableMovmentInput true": set one property of the player's plane once.
local function setProperty(args)
    local p = playerPlane()
    if not p then log("set: no player plane") return end
    local k, v = args[1], args[2]
    local val = (v == "true") and true or (v == "false") and false or tonumber(v) or v
    local ok, err = pcall(function() p[k] = val end)
    log("set " .. tostring(k) .. " = " .. tostring(val) .. ": " .. (ok and ("now " .. tostring(p[k])) or tostring(err)))
end

-- "call plane EnablePlayerInput true" / "call mission SkipMiniGame": call one function.
local function callFunction(args)
    local who, fn = args[1], args[2]
    local obj
    if who == "plane" then obj = playerPlane()
    elseif who == "mission" then obj = mission()
    elseif who == "weapons" then local p = playerPlane(); obj = p and weapons(p)
    elseif who == "targets" then local p = playerPlane(); obj = p and targetSelection(p)
    end
    if not obj then log("call: no object '" .. tostring(who) .. "'") return end
    local rest = {}
    for k = 3, #args do
        local v = args[k]
        rest[#rest + 1] = (v == "true") and true or (v == "false") and false or tonumber(v) or v
    end
    local ok, r = pcall(function() return obj[fn](obj, table.unpack(rest)) end)
    log(string.format("call %s:%s(%s): %s", who, fn, table.concat(args, " ", 3), ok and ("returned " .. fmt(r)) or ("error " .. tostring(r))))
end

local commands = {
    ping = function(args) log("pong " .. table.concat(args, " ")) end,
    mark = function(args) local text = table.concat(args, " "); log("== " .. text); event("mark", { text = text }) end,
    -- "inspect ReplaySkipButton_C": the functions and properties of the first live object of that class
    -- "uilist": every kind of UI widget that is visible right now (menu pages live inside
    -- the front screen, so they are not "in the viewport" themselves)
    uilist = function()
        local seen, names = {}, {}
        for _, w in ipairs(FindAllOf("UserWidget") or {}) do
            pcall(function()
                if w:IsVisible() then
                    local n = w:GetClass():GetFName():ToString()
                    if not seen[n] then seen[n] = 0; names[#names + 1] = n end
                    seen[n] = seen[n] + 1
                end
            end)
        end
        table.sort(names)
        local parts = {}
        for _, n in ipairs(names) do parts[#parts + 1] = n .. (seen[n] > 1 and ("x" .. seen[n]) or "") end
        log("uilist (" .. #names .. "): " .. table.concat(parts, " "))
    end,
    -- "inspect FrontScreenWidget_C UIManagerActor": follow properties from that object first
    inspect = function(args)
        local o = FindFirstOf(args[1] or "")
        if not o or not o:IsValid() then log("inspect: no live " .. tostring(args[1])) return end
        for k = 2, #args do
            local okP, nxt = pcall(function() return o[args[k]] end)
            if not okP or not nxt or type(nxt) ~= "userdata" or not nxt:IsValid() then log("inspect: no object in " .. args[k]) return end
            o = nxt
        end
        log("inspect " .. o:GetFullName())
        local cls = o:GetClass()
        while cls and cls:IsValid() do
            local fns, props = {}, {}
            pcall(function() cls:ForEachFunction(function(f) fns[#fns + 1] = f:GetFName():ToString() end) end)
            pcall(function() cls:ForEachProperty(function(p)
                local n = p:GetFName():ToString()
                local okV, v = pcall(function() return o[n] end)
                local shown = ""
                if okV and (type(v) == "number" or type(v) == "boolean" or type(v) == "string") then shown = "=" .. tostring(v)
                elseif okV and type(v) == "userdata" then
                    local okN, nm = pcall(function() return v:IsValid() and v:GetFName():ToString() end)
                    if okN and nm then shown = "=" .. tostring(nm) end
                    local okS, str = pcall(function() return v:ToString() end)
                    if okS and type(str) == "string" then shown = "=" .. str end
                end
                props[#props + 1] = n .. shown
            end) end)
            log(string.format("  %s: functions [%s]; properties [%s]", cls:GetFName():ToString(), table.concat(fns, ", "), table.concat(props, ", ")))
            local name = cls:GetFName():ToString()
            if name == "UserWidget" or name == "Actor" or name == "Object" then break end
            local okS, sup = pcall(function() return cls:GetSuperStruct() end)
            if not okS then break end
            cls = sup
        end
    end,
    hold = holdInputs,
    pad = padHold,
    keys = keysHold,
    fly = flyOrder,
    takeoff = takeoffOrder,
    padstatus = function() log(type(CoopPad_Status) == "function" and tostring(CoopPad_Status()) or "CoopPadMod is not loaded") end,
    set = setProperty,
    call = callFunction,
    stop = function() stopAll() end,
    status = function() writeStatus(); log("status written") end,
    probe = function(args)
        local what = args[1] or "controls"
        if what == "controls" then probeControls()
        elseif what == "weapons" then probeWeapons()
        elseif what == "targets" then probeTargets()
        elseif what == "mission" then probeMission()
        else log("unknown probe '" .. what .. "'") end
    end,
}

local lastSeq = nil
local function pollOrders()
    if type(CoopNet_Since) ~= "function" then return end
    if lastSeq == nil then
        local _, seq = CoopNet_Latest()
        lastSeq = seq or 0
        return
    end
    while true do
        local line, seq = CoopNet_Since(lastSeq)
        if not line then break end
        lastSeq = seq
        local words = {}
        for w in line:gmatch("%S+") do words[#words + 1] = w end
        if words[1] == "PILOT" and words[2] then
            local cmd = words[2]
            local args = { table.unpack(words, 3) }
            log("order #" .. seq .. ": " .. line)
            local fn = commands[cmd]
            if fn then
                local ok, err = pcall(fn, args)
                if not ok then log("order failed: " .. tostring(err)) end
            else
                log("unknown order '" .. cmd .. "'")
            end
        end
    end
end

local statusTick = 0
LoopInGameThreadWithDelay(100, function()
    statusTick = statusTick + 1
    pcall(pollOrders)
    if statusTick % 5 == 0 then writeStatus() end
end)

log("ready (" .. (type(CoopNet_Since) == "function" and "orders by UDP through CoopNetMod" or "CoopNetMod missing: no way to take orders") ..
    "); files go to " .. OUT)
