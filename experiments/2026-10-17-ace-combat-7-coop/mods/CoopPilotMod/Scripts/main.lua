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

local firedAt = {}             -- enemy name -> when the bot last fired at it
local cloudBase, cloudMission = nil, nil   -- the lowest cloud met in this mission (m), see watchAreas
local creditedKills = {}       -- enemy names whose death was already counted

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
    -- IsValid first: it is safe on an object the engine has freed (UE4SS only looks it up in
    -- its own list); calling anything else on one crashes the game, past any pcall
    local okV, isValid = pcall(function() return obj:IsValid() end)
    if not okV or not isValid then return nil end
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

-- The pilot's picture of the fight: tracks, predictions, threats (awareness.lua)
local okAware, Aware = pcall(function()
    return require("awareness")({ log = log, event = event, now = now, call = call, objName = objName, callsign = callsign })
end)
if not okAware then log("awareness.lua did not load: " .. tostring(Aware)); Aware = nil end

-- The ground and obstacles ahead: height map, path checks, steering (nav.lua)
local okNav, Nav = pcall(function()
    return require("nav")({ log = log, event = event, now = now })
end)
if not okNav then log("nav.lua did not load: " .. tostring(Nav)); Nav = nil end

-- Following a planned route (route.lua; routes come from tools\route-plan.py)
local okRoute, Route = pcall(function()
    return require("route")({ log = log, event = event, now = now })
end)
if not okRoute then log("route.lua did not load: " .. tostring(Route)); Route = nil end

-- Seeing in 3D with fans of rays, for structures and tunnels (vision.lua, 19 Oct 2026)
local okVis, Vision = pcall(function()
    return require("vision")({ log = log, event = event, now = now })
end)
if not okVis then log("vision.lua did not load: " .. tostring(Vision)); Vision = nil end

-- The mission's special objects: searchlights, radar areas, the altitude ceiling (gimmicks.lua)
local okGim, Gim = pcall(function()
    return require("gimmicks")({ log = log, event = event, now = now, call = call, objName = objName })
end)
if not okGim then log("gimmicks.lua did not load: " .. tostring(Gim)); Gim = nil end

-- The plane's own area checks: which of the mission's special areas it is in right now.
local AREA_CHECKS = { { "over_ceiling", "IsOverRestrictedAltitude" }, { "in_radar", "IsInRadarArea" },
                      { "in_searchlight", "IsInSearchLight" }, { "in_jamming", "IsInJammingArea" },
                      { "in_tunnel", "IsInTunnel" }, { "in_cloud", "IsInCloud" }, { "in_impact", "IsInImpactArea" },
                      { "beyond_pullout", "IsBeyondPulloutLine" } }

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
    -- in a mission: the retry menu after a failure, the pause menu, the replay after success
    "CampaignRetry_C", "CampaignHudPause_C", "ReplayWidget_C",
    -- after a story mission: the results (with the debriefing replay) and the "mission complete" menu
    "CampaignDebriefing_C", "CampaignMenuNext_C",
    "CampaignHangarReview_C", "CampaignHangarWeapon_C", "CampaignHangarAircraft_C", "CampaignMenuActionSelect_C",
    "CampaignBriefingMenu_C", "CampaignMissionTitle_C", "CampaignBriefingMV_C", "CampaignMV_C",
    "CampaignFreeMission_C", "CampaignFreeMissionDifficulty_C", "CampaignMenuDifficulty_C", "CampaignMenuMain_C", "MainMenu_C", "MainTitle_C",
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
    -- a page not in the list yet (the story has many: CampaignMvNews_C, ...): any visible
    -- Campaign... widget, so the runner at least knows its name
    if not pageCache then
        local names = {}
        for n in pairs(visible) do if n:find("^Campaign") then names[#names + 1] = n end end
        table.sort(names)
        pageCache = names[1]
    end
    return pageCache
end

-- On the mission list: which mission the cursor is on (the list shows its picture,
-- missionThum_cpNN); in a mission: which mission it is (its level, /Game/Maps/Mission/msNN).
local function menuMission()
    local n = nil
    pcall(function()
        for _, w in ipairs(FindAllOf("CampaignFreeMission_C") or {}) do
            if w:IsVisible() then
                -- the picture shown for the selected mission (the widget's own ThumbnailTexture
                -- property does not follow the cursor; the Thumbnail image's brush does)
                local tex = w.Thumbnail.Brush.ResourceObject
                local name = tex and tex:IsValid() and tex:GetFName():ToString() or ""
                n = tonumber(name:match("cp(%d+)"))
                if n then break end
            end
        end
    end)
    return n
end
local levelCache, levelAt = nil, -100
local function missionLevel()
    if now() - levelAt < 2 then return levelCache end
    levelAt = now()
    levelCache = nil
    local m = mission()
    if m then
        local ok, full = pcall(function() return m:GetFullName() end)
        if ok and full then levelCache = full:match("/Mission/([%w_]+)/") end
    end
    return levelCache
end

-- The menu page's title and the description of the item the cursor is on (most menu pages
-- are MenuBaseWidgets with UmgTitleText / UmgDescriptionText): tells the runner which item
-- is selected without pictures (19 Oct 2026).
local function textOf(w)
    local ok, s = pcall(function() return w:GetText():ToString() end)
    return ok and s or nil
end
local function menuTexts(pageName)
    if not pageName then return nil end
    local out = nil
    pcall(function()
        for _, w in ipairs(FindAllOf(pageName) or {}) do
            if w:IsVisible() then
                out = {}
                pcall(function() out.title = textOf(w.UmgTitleText) end)
                pcall(function() out.desc = textOf(w.UmgDescriptionText) end)
                pcall(function() out.button = textOf(w.UmgButtonText) end)
                -- the story's mission title page: "MISSION 01" / "Charge Assault"
                pcall(function() out.missionNo = textOf(w.MissionNumberText) end)
                pcall(function() out.missionTitle = textOf(w.MissionTitleText) end)
                break
            end
        end
    end)
    return out
end

-- A yes/no dialog on screen (DialogWidget_C: "Do you want to reset your campaign mode
-- progress...?"): its text, its options, and which one the cursor is on (the selected option
-- is drawn at full opacity, the others at 0.4).
local function dialogInfo()
    local d = nil
    pcall(function()
        for _, w in ipairs(FindAllOf("DialogWidget_C") or {}) do
            if w:IsVisible() then
                d = { text = textOf(w.DescriptionText) or "", options = {}, selected = false }
                for i, key in ipairs({ "ItemText0", "ItemText1", "ItemText2" }) do
                    pcall(function()
                        local t = w[key]
                        if t:IsVisible() then
                            d.options[#d.options + 1] = textOf(t) or "?"
                            if t.ColorAndOpacity.SpecifiedColor.A > 0.7 then d.selected = #d.options end
                        end
                    end)
                end
                break
            end
        end
    end)
    return d
end

local function snapshot()
    local s = { time = now() }
    local p = playerPlane()
    s.screens = screens()
    s.page = currentPage() or false
    local mt = menuTexts(s.page or nil)
    if mt then
        s.menu_title, s.menu_desc = mt.title or false, mt.desc or false
        if mt.missionNo then s.story_mission, s.story_title = mt.missionNo, mt.missionTitle or false end
    end
    local dg = dialogInfo()
    if dg then s.dialog = dg end
    -- MISSION RESULTS: every visible text on the page, in order (rank, times, rewards,
    -- targets destroyed), for the mission's report
    if s.page == "CampaignDebriefing_C" then
        pcall(function()
            local texts = {}
            for _, t in ipairs(FindAllOf("TextBlock") or {}) do
                if #texts >= 120 then break end
                local n = t:GetFullName()
                if n:find("CampaignDebriefing_C", 1, true) and t:IsVisible() then
                    local x = textOf(t)
                    if x and x ~= "" then texts[#texts + 1] = x end
                end
            end
            s.results_texts = texts
        end)
    end
    -- In the hangar: the plane and special weapon under the cursor (the game instance's
    -- selection follows the cursor: Typhoon 123, Rafale M 117, Mirage 2000-5 115; weapon 0, 1, 2
    -- in the list's order), the plane's name and the weapon list (19 Oct 2026)
    if s.page == "CampaignHangarAircraft_C" or s.page == "CampaignHangarWeapon_C" or s.page == "CampaignHangarReview_C" then
        pcall(function()
            local gi = FindFirstOf("NimbusGameInstance")
            s.hangar_plane_id = gi:GetSelectedPlaneID()
            s.hangar_swp = gi:GetSelectedPlaneSWP()
        end)
        pcall(function()
            local weaponsList = {}
            for _, t in ipairs(FindAllOf("TextBlock") or {}) do
                local n = t:GetFullName()
                if n:find(s.page, 1, true) and t:IsVisible() then
                    if n:find("HangarAircraftSkinNo", 1, true) and n:sub(-5) == ".Name" then s.hangar_plane = textOf(t) end
                    local k = n:match("LightMenuBaseWidget%.WidgetTree_%d+%.ItemText(%d+)$")
                    if k and s.page == "CampaignHangarWeapon_C" then weaponsList[tonumber(k) + 1] = textOf(t) end
                end
            end
            if next(weaponsList) then s.hangar_weapons = weaponsList end
        end)
    end
    if s.page == "CampaignFreeMission_C" then s.menu_mission = menuMission() or false end
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
    for _, a in ipairs(AREA_CHECKS) do s[a[1]] = call(p, a[2]) end
    s.over_altitude = s.over_ceiling
    if Gim and Gim.ceiling then s.ceiling_m = Gim.ceiling end
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
        s.mission_level = missionLevel() or false
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

-- A restart from a checkpoint (or the mission restarting a phase) replaces the plane, the
-- enemies and the searchlights with new objects and frees the old ones about a minute later.
-- Anything still pointing at an old one then crashes the game (three crashes on 18 Oct
-- 2026, each 30-70 s after a checkpoint retry). So when the plane's address changes, or a
-- phase restarts, every remembered object is dropped (forgetWorld, defined further down).
local forgetWorld
local lastPlaneAddr = nil

local function step()
    local p = playerPlane()
    if not p then return end
    local okA, addr = pcall(function() return p:GetAddress() end)
    if okA and addr and addr ~= lastPlaneAddr then
        if lastPlaneAddr and forgetWorld then forgetWorld("a new plane", p) end
        lastPlaneAddr = addr
    end
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
local phaseName, phaseAt = nil, -100     -- the phase the mission is in, and since when
tryHook("/Script/Nimbus.Mission:OnStartNextPhaseHandler", function(self, phase, restart)
    local again = restart:get()
    phaseName, phaseAt = objName(phase:get()), now()
    event("phase_start", { phase = phaseName, restart = again })
    if again and forgetWorld then forgetWorld("the phase restarted", nil) end
end)
tryHook("/Script/Nimbus.Mission:OnSuccessCurrentPhaseHandler", function(self, phase)
    event("phase_cleared", { phase = objName(phase:get()) })
end)
local spottedReport                    -- defined further down (needs the plane and the lights)
tryHook("/Script/Nimbus.Mission:OnFailCurrentPhaseHandler", function(self, phase, reason)
    event("phase_failed", { phase = objName(phase:get()), reason = reason:get() })
    if spottedReport then pcall(spottedReport) end
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
    local n = objName(o)
    event("death", { who = n, callsign = callsign(o) })
    -- an enemy the bot fired at in the last 20 s: its kill (the missile may land after the
    -- bot has switched to the next target, so the target-change check never sees it)
    if firedAt[n] and now() - firedAt[n] < 20 and not creditedKills[n] then
        creditedKills[n] = true
        event("kill", { target = n, callsign = callsign(o), by = "missile on its way" })
        log("  KILL: " .. n .. " (a missile fired earlier)")
    end
end)
-- The altitude ceiling: the mission script hands it to the plane (no property holds it).
tryHook("/Script/Nimbus.PlayerPlane:SetRestrictedAltitude", function(self, alt)
    local v = alt:get()
    if Gim then Gim.ceiling = v; Gim.ceilingSet = true end
    if ap and v and v > 0 then ap.ceiling = v end
    event("ceiling_set", { alt_m = v })
    log("the mission set an altitude ceiling: " .. tostring(v) .. " m")
end)
-- Targets the mission marks "cannot be locked" (or as a fake box): the mission script calls
-- SetHudBoxAttribute (EHudBoxAttribute: 0 None, 1 LockonImpossible, 2 Highlight, 3 Fake,
-- 4 LockonImpossibleAndHighlight) on a single object or on a whole unit, and the game keeps
-- the mark where scripts cannot read it, so the calls are caught as they happen (a mission
-- makes them when a phase starts or changes, so they are caught from the next phase or
-- checkpoint on). Mission 14 suspect: SAM sites and reinforcements that never locked.
local HUD_ATTR = { [0] = "none", [1] = "cannot be locked", [2] = "highlighted", [3] = "fake", [4] = "cannot be locked, highlighted" }
local hudAttr = {}             -- object name -> the mark's number
local function markHud(o, v, via)
    local n = objName(o)
    hudAttr[n] = v
    event("hud_mark", { who = n, mark = HUD_ATTR[v] or tostring(v), via = via })
    log(string.format("  the mission marked %s: %s%s", n, HUD_ATTR[v] or tostring(v), via and (" (" .. via .. ")") or ""))
end
tryHook("/Script/Nimbus.GameObject:SetHudBoxAttribute", function(self, typ)
    local okV, v = pcall(function() return typ:get() end)
    markHud(self:get(), okV and v or -1)
end)
tryHook("/Script/Nimbus.Unit:SetHudBoxAttribute", function(self, attr)
    local okV, v = pcall(function() return attr:get() end)
    v = okV and v or -1
    local u = self:get()
    local okM, members = pcall(function() return u:GetAIGameObjectsCopy() end)
    local count = 0
    if okM and members then
        pcall(function()
            for i = 1, #members do
                local m = members[i]
                if m and m:IsValid() then markHud(m, v, "unit " .. objName(u)); count = count + 1 end
            end
        end)
    end
    if count == 0 then markHud(u, v, "a unit, members not read") end
end)
-- Radio lines: the subtitle widget receives each one (speaker and message). The mission's
-- instructions ("stay low", "the searchlights are on") come this way.
local radioLog = {}            -- the most recent lines, newest last
local skipMiniGames = true     -- "minigames play" turns this off
local lastSkipAt = nil
local lastRadioKey, lastRadioAt = nil, -100
local function onRadio(self, rt)
    local okR, speaker, text = pcall(function()
        local r = rt:get()
        return r.Speaker:ToString(), r.Message:ToString()
    end)
    if not okR or not text or text == "" then return end
    local k = (speaker or "") .. "|" .. (text or "")
    if k == lastRadioKey and now() - lastRadioAt < 2 then return end   -- the same line from two widgets
    lastRadioKey, lastRadioAt = k, now()
    radioLog[#radioLog + 1] = { t = now(), speaker = speaker, text = text }
    if #radioLog > 60 then table.remove(radioLog, 1) end
    event("radio", { speaker = speaker, text = text })
    log("  RADIO " .. tostring(speaker) .. ": " .. tostring(text))
    -- Mini-games (aerial refuelling, landing): the game's own skip, Mission:SkipMiniGame,
    -- as soon as one begins (they are scored side tasks, not the mission's objective).
    local lower = (speaker .. " " .. text):lower()
    if skipMiniGames and (lower:find("tanker", 1, true) or lower:find("refuel", 1, true) or lower:find("landing approach", 1, true)
        or lower:find("cleared for approach", 1, true) or lower:find("to runway", 1, true) or lower:find("land immediately", 1, true))
        and not lower:find("aborted", 1, true) and now() - (lastSkipAt or -100) > 8 then
        lastSkipAt = now()
        local m = mission()
        local ok = m and pcall(function() m:SkipMiniGame() end)
        event("minigame_skip", { why = text, ok = ok and true or false })
        log("  mini-game started (" .. text .. "): skipped it with Mission:SkipMiniGame " .. (ok and "(done)" or "(failed)"))
    end
    -- an altitude restriction given over the radio ("Keep altitude below 600 meters.")
    local lim = text:match("[Bb]elow ([%d,]+) ?m") or text:match("[Bb]elow ([%d,]+) meters")
    if lim then
        local m = tonumber((lim:gsub(",", "")))
        -- the radio's figure is only used when the game has not set one itself (Mission 14
        -- says 600 m on the radio and sets 550 m with SetRestrictedAltitude)
        if m and m > 50 and m < 20000 and not (Gim and Gim.ceilingSet) then
            if Gim then Gim.ceiling = m end
            if ap then ap.ceiling = m end
            event("ceiling_heard", { alt_m = m, text = text })
            log(string.format("  heard an altitude ceiling on the radio: %.0f m", m))
        end
    end
end
tryHook("/Script/Nimbus.SubtitleWidget:RadioMessageReceived", onRadio)
tryHook("/Script/Nimbus.HUDMessageWidget:RadioMessageReceived", onRadio)
tryHook("/Script/Nimbus.Mission:SkipMiniGame", function() event("minigame_skipped") end)
tryHook("/Script/Nimbus.Mission:OnStartSupplyPhaseHandler", function() event("supply_phase_start") end)
tryHook("/Script/Nimbus.Mission:OnSuccessSupplyPhaseHandler", function() event("supply_phase_done") end)
tryHook("/Script/Nimbus.Mission:OnPreStartReplayHandler", function() event("replay_start") end)
tryHook("/Script/Nimbus.Mission:OnStoppedReplayHandler", function() event("replay_stopped") end)
tryHook("/Script/Nimbus.Mission:OnCooldownFinishedHandler", function() event("cooldown_finished") end)

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
    elseif g.kind == "route" then
        local sp = ap.myV and math.sqrt(ap.myV[1] ^ 2 + ap.myV[2] ^ 2 + ap.myV[3] ^ 2) or 1600
        local a, kmh = Route.steer(g.route, { loc.X, loc.Y, loc.Z }, sp)
        ap.routeKmh = kmh
        return a
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
    local ok, l = pcall(function() return o:IsValid() and o:K2_GetActorLocation() or nil end)
    if ok and l then return l end
    return nil
end

local function sameObj(a, b)
    if not a or not b then return false end
    local ok, same = pcall(function() return a:IsValid() and b:IsValid() and a:GetFullName() == b:GetFullName() end)
    return ok and same
end

-- How much an enemy matters, as a pilot would judge it (18 Oct 2026, after Mission 14's
-- base attack was lost while the bot shot searchlights and the landing team was overrun):
--   * enemies near our own ground forces or helicopters (within 3 km) first: they are
--     what the mission is usually about when it says "protect" or "support";
--   * then anything that shoots: AA guns, SAMs, helicopters, planes, tanks and APCs;
--   * mission targets (IsTGT) count extra;
--   * searchlights, fuel tanks, dummies and the like last.
-- The class names are the game's own (common_seli_C = searchlight, common_vads_C = AA gun,
-- ms14_rams_Child_C = SAM, zouen = reinforcements).
local LOW_VALUE = { "seli", "searchlight", "oiltank", "oil_tank", "dummy", "container", "crate", "lamp", "radartower", "b52" }
-- what overruns a landing party: reinforcements, armour, attack helicopters
local PARTY_THREAT = { "zouen", "tank", "t072", "t90", "apc", "tung", "bmp", "btr", "ah64", "mi24", "mi-24", "ka50", "heli" }
local SHOOTER = { "vads", "aagun", "rams", "sam", "ah64", "mi24", "mi-24", "ka50", "heli", "apc", "tank", "zouen",
                  "m1a", "t90", "bmp", "btr", "gun", "lav", "_en_" }
local allyGround = {}          -- positions of our slow allies (ground units, helicopters), refreshed with each scan
local allyNames = {}           -- names of every ally alive (any speed), refreshed with each scan
local tgtAliveCount = 0        -- mission targets (IsTGT) still alive, refreshed with each scan
local function classOf(o)
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or ""
end
-- What kind of thing an object is, worked out ONCE (the first time it is seen alive) and
-- kept by its name: asking a unit for its class while the game is tearing it down after a
-- kill is the prime suspect for two crashes on 18 Oct 2026, both right after a kill.
local infoCache = {}
local function objInfo(o)
    local key = objName(o)
    local info = infoCache[key]
    if info then return info end
    local name = (classOf(o) .. " " .. key):lower()
    info = { name = name }
    infoCache[key] = info
    return info
end
local function hasAny(name, list)
    for _, w in ipairs(list) do if name:find(w, 1, true) then return true end end
    return false
end

-- Can the game lock onto it at all? Read from the game's own code (19 Oct 2026, workbench
-- section 15): a lock "seeker" is only given to a selected target whose lock-on mark (the
-- EHudBoxAttribute byte a mission sets with SetHudBoxAttribute; no script property, so read
-- from memory at +0x6C0 through CoopPadMod) is not 1 LockonImpossible, 3 Fake or
-- 4 LockonImpossibleAndHighlight, that is not a "mission special object"
-- (bIsMissionSpecialObject), and whose kind (bIsAir) the armed weapon can lock. The game's own
-- SelectTarget also refuses marks 1 and 4 and targets in stealth. Kept for a second.
local HUD_MARK_OFFSET = 0x6C0
local lockCache = {}
local function lockInfo(o)
    local key = objName(o)
    local li = lockCache[key]
    local t = now()
    if li and t - li.at < 1.0 then return li end
    li = { at = t }
    local okA, addr = pcall(function() return o:IsValid() and o:GetAddress() or nil end)
    if okA and addr and type(CoopMem_Read) == "function" then li.mark = CoopMem_Read(addr + HUD_MARK_OFFSET, 1) end
    pcall(function()
        if not o:IsValid() then return end
        li.special = o.bIsMissionSpecialObject == true
        li.air = o.bIsAir == true
        li.needsDetection = o.bNeedsDetection == true
    end)
    li.lockable = not (li.mark == 1 or li.mark == 3 or li.mark == 4) and not li.special
    -- Where the game aims its lock cone: unless a flag (+0x4F4) says "the actor itself", a
    -- lock-point component (+0x878) whose world position is at +0x190 (the game's target-point
    -- function, exe+0x7f6ce0 in this build). How far that is from the actor (m) is logged,
    -- in case a target's lock point sits somewhere else than the vehicle.
    if okA and addr and type(CoopMem_Read) == "function" and CoopMem_Read(addr + 0x4F4, 1) == 0 then
        local comp = CoopMem_Read(addr + 0x878, 8)
        if comp and comp ~= 0 and (CoopMem_Read(comp + 0x84, 1) or 1) & 1 == 0 then
            local x, y, z = CoopMem_ReadFloat(comp + 0x190), CoopMem_ReadFloat(comp + 0x194), CoopMem_ReadFloat(comp + 0x198)
            local okL, l = pcall(function() return o:K2_GetActorLocation() end)
            if x and okL and l then
                li.lockPointOff = math.sqrt((x - l.X) ^ 2 + (y - l.Y) ^ 2 + (z - l.Z) ^ 2) / 10
                li.lockPoint = { x, y, z }
            end
        end
    end
    lockCache[key] = li
    return li
end
-- The lock seekers (one per loaded missile): whom each one is on and its state
-- (ELockonState at +0x40: 0 no target, 1 detecting, 2 started, 3 locked, 4 locked but in a
-- cloud, 5 locking in a cloud, 6 jammed).
local SEEKER_STATE = { [0] = "none", "detecting", "started", "LOCKED", "locked-in-cloud", "locking-in-cloud", "jammed" }
local function seekersText(ts)
    local parts = {}
    pcall(function()
        local arr = ts.LockonSeekers
        for i = 1, #arr do
            local s = arr[i]
            if s and s:IsValid() then
                local tgtName = "-"
                pcall(function() local lt = s.LockonTarget; if lt and lt:IsValid() then tgtName = objName(lt) end end)
                local st = type(CoopMem_Read) == "function" and CoopMem_Read(s:GetAddress() + 0x40, 1) or nil
                parts[#parts + 1] = tgtName .. ":" .. (st and (SEEKER_STATE[st] or tostring(st)) or "?")
            end
        end
    end)
    return #parts > 0 and table.concat(parts, ",") or "none"
end
local function lockText(li)
    if not li then return "?" end
    return string.format("mark %s%s%s%s", li.mark and (HUD_ATTR and HUD_ATTR[li.mark] or tostring(li.mark)) or "unread",
        li.special and ", mission special object" or "",
        li.lockPointOff and li.lockPointOff > 3 and string.format(", lock point %.0f m from it", li.lockPointOff) or "",
        li.lockable and "" or " -> NO LOCK POSSIBLE")
end
-- Who fired at us in the last minute (awareness.lua's log of missiles homing on the plane):
-- a pilot deals with what is shooting at him (Mission 14 Hard: three SAM sites firing up to
-- five missiles at once shot the bot down while it went for the helicopters).
local function recentShooters()
    local set = {}
    if Aware and Aware.missileLog then
        local t = now()
        for i = #Aware.missileLog, 1, -1 do
            local tr = Aware.missileLog[i]
            if t - (tr.born or 0) > 60 then break end
            if tr.ownerName then set[tr.ownerName] = true end
        end
    end
    return set
end
local shooters, shootersAt = {}, -100

local function enemyWeight(o, l)
    local name = objInfo(o).name
    local w = 1.0
    if now() - shootersAt > 1 then shootersAt = now(); shooters = recentShooters() end
    if shooters[objName(o)] then
        -- a SAM or gun that fires at us cannot be outflown: deal with it; a fighter that did
        -- is worth less of a detour (it moves, and the party matters more)
        w = w * ((Aware and Aware.trackFor(o)) and 2 or 5)
    end
    -- reinforcements ("zouen", the game's own word for them, 増援): when a wave comes the
    -- mission is usually lost unless it is stopped quickly (Mission 14: "We've been
    -- surrounded by the enemy reinforcements"), wherever it is
    if name:find("zouen", 1, true) then w = w * 4 end
    -- an enemy chasing one of our own planes or helicopters (its AI is tracking an ally):
    -- "protect the retreating squadron" (Mission 03 phase 3, 19 Oct 2026: a retreating ally
    -- was shot down by drones while the bot fought elsewhere and the phase failed)
    -- An ally the mission highlights (lock-on mark 2 or 4: the escort/protect marker; Mission
    -- 03's retreating Gargoyle squadron, Mission 14's landing team) counts double again.
    local tr = Aware and Aware.trackFor(o)
    local chasesProtected = tr and tr.tracking and allyNames[tr.tracking] == "protect"
    if tr and tr.tracking and allyNames[tr.tracking] then w = w * (chasesProtected and 7 or 2) end
    -- what the order says matters most in this mission ("focus AH64_00,zouen")
    if ap and ap.focus and hasAny(name, ap.focus) then w = w * 6 end
    local okT, tgtFlag = pcall(function() return o:IsTGT() end)
    local isTgt = okT and tgtFlag
    -- Mission targets (the game's TGT flag) are what a phase is won with (19 Oct 2026, Mission
    -- 05: "Shoot down everything carrying bombs!" while the bot fought escorts chasing our
    -- squadron, worth 5-20 times the bombers, and the base was bombed): 4 times, and while any
    -- are alive, other enemies count a third unless they shot at us or chase an ally the
    -- mission says to protect
    if isTgt then w = w * 4
    elseif tgtAliveCount > 0 and not shooters[objName(o)] and not chasesProtected then w = w * 0.35 end
    -- The last few mission targets (19 Oct 2026, Mission 04: two drones that counted were
    -- 21 km away while the bot attacked launch containers below it, and the phase ran out of
    -- time): with four or fewer left, everything else counts almost nothing
    if tgtAliveCount > 0 and tgtAliveCount <= 4 and not isTgt then w = w * 0.03 end
    if hasAny(name, LOW_VALUE) then w = w * 0.35
    elseif hasAny(name, PARTY_THREAT) then w = w * 1.6
    elseif hasAny(name, SHOOTER) or (Aware and Aware.trackFor(o)) then w = w * 1.4 end
    -- the closer to our own ground units and transports, the more it matters: six times at
    -- 0 m, nothing extra beyond 2 km (Mission 14: six enemy Apaches hovered 100-440 m from
    -- the landed transports while the bot fought elsewhere, and the landing failed)
    if l then
        local nearest, nearestP = math.huge, math.huge
        for _, a in ipairs(allyGround) do
            local d2 = (a[1] - l.X) ^ 2 + (a[2] - l.Y) ^ 2
            if d2 < nearest then nearest = d2 end
            if a.protect then
                local d3 = d2 + (a[3] - l.Z) ^ 2
                if d3 < nearestP then nearestP = d3 end
            end
        end
        if nearestP < math.huge then
            -- near an ally the mission says to protect: up to 9 times, out to 5 km
            w = w * (1 + 8 * math.max(0, 1 - math.sqrt(nearestP) / 50000))
        elseif nearest < math.huge then
            w = w * (1 + 6 * math.max(0, 1 - math.sqrt(nearest) / 25000))
        end
    end
    return w, name
end

-- In the air? Planes are followed by the tracker; helicopters are not planes to the game
-- (Mission 14: Apaches got slow ground attack runs), so they are told by name, and anything
-- else moving faster than a ground vehicle counts as flying too.
local HELI = { "ah64", "ah-64", "mi24", "mi-24", "mi28", "ka50", "ka52", "uh60", "ch47", "mh60", "sh60", "nh90", "heli", "chopper", "tiger" }
local function airborne(o)
    if Aware and Aware.trackFor(o) then return true end
    local info = objInfo(o)
    if info.heli == nil then info.heli = hasAny(info.name, HELI) end
    if info.heli then return true end
    -- moving faster than a ground vehicle: asked at most once a second per object
    if not info.speedAt or now() - info.speedAt > 1 then
        info.speedAt = now()
        info.fast = (call(o, "GetSpeedKmph") or 0) > 120
    end
    return info.fast
end

-- The enemy to go after (slow: the whole object list, so about once a second). Each enemy's
-- value (enemyWeight: how much it threatens our own ground units, what it is, whether it
-- fired at us) is divided by the time it would take to get it: the flight there, turning the
-- nose onto it, and a detour when it is too close and too far off the nose to shoot. The
-- one being worked on is kept unless another one is clearly better (a target switch
-- costs a turn). Returns the enemy, its distance (m), its score (higher = better), its weight.
local function nearestEnemy(loc, skip, F, current, kmh)
    local best, bestScore, bestD, bestW = nil, -1, 0, 1
    local hiddenBest, hiddenD = nil, math.huge
    local curScore, curD, curW = nil, 0, 1
    local t = now()
    local objs = FindAllOf("GameObject") or {}
    local allies, names = {}, {}
    for _, o in ipairs(objs) do
        pcall(function()
            if o.bIsActivated and o:GetFaction() == 1 and o:IsAlive() and not objInfo(o).name:find("dummy", 1, true) then
                local mk = lockInfo(o).mark
                local protect = (mk == 2 or mk == 4)
                names[objName(o)] = protect and "protect" or true
                -- slow allies (ground units, helicopters), and any ally the mission highlights
                -- as one to protect, at any speed (Mission 04's transport, 19 Oct 2026)
                if protect or (o:GetSpeedKmph() or 0) < 350 then
                    local l = o:K2_GetActorLocation()
                    allies[#allies + 1] = { l.X, l.Y, l.Z, protect = protect }
                end
            end
        end)
    end
    allyGround, allyNames = allies, names
    local nT = 0
    for _, o in ipairs(objs) do
        pcall(function() if o.bIsActivated and o:GetFaction() == 0 and o:IsAlive() and o:IsTGT() then nT = nT + 1 end end)
    end
    tgtAliveCount = nT
    local mps = math.max((kmh or 700) / 3.6, 150)
    local curName = current and objName(current)
    for _, o in ipairs(objs) do
        local ok, sc, dm, wt, name = pcall(function()
            -- AIGameObject:GetFaction(): 0 = enemy, 1 = ally; IsTGT(): a target the mission counts
            if not o.bIsActivated or o:GetFaction() ~= 0 or not o:IsAlive() then return nil end
            -- only what the game offers the player as a target: units without a HUD box or
            -- marked as an exception are scenery for now (Mission 14's reinforcement tanks:
            -- no lock however long the bot pointed at them)
            -- (bIsAttackTargetsException is NOT a reason to skip: Mission 04's drone
            -- containers are mission targets with it set, 19 Oct 2026)
            if o.bShowHUDBox == false then
                -- hidden for now (a drone still in its container): remembered as a place to go
                -- to when nothing attackable is left
                local okT2, tg2 = pcall(function() return o:IsTGT() end)
                if okT2 and tg2 then
                    local l2 = o:K2_GetActorLocation()
                    local d2 = math.sqrt((l2.X - loc.X) ^ 2 + (l2.Y - loc.Y) ^ 2 + (l2.Z - loc.Z) ^ 2)
                    if not hiddenBest or d2 < hiddenD then hiddenBest, hiddenD = o, d2 end
                end
                return nil
            end
            -- marked by the mission as impossible to lock, or a fake box, or a mission special
            -- object: the game never gives those a lock (lockInfo; read from its code)
            local mark = hudAttr[objName(o)]
            if mark == 1 or mark == 3 or mark == 4 then return nil end
            local li = lockInfo(o)
            if not li.lockable and not (ap and ap.gunUnlockable) then return nil end
            local n = objName(o)
            if skip then
                local until_ = skip[n]
                if until_ and t < until_ then return nil end
            end
            local l = o:K2_GetActorLocation()
            local dx, dy, dz = l.X - loc.X, l.Y - loc.Y, l.Z - loc.Z
            local du = math.sqrt(dx * dx + dy * dy + dz * dz)
            local d = du / 10
            local w = enemyWeight(o, l)
            local ang = 0
            if F and du > 1 then ang = math.deg(math.acos(math.max(-1, math.min(1, (dx * F[1] + dy * F[2] + dz * F[3]) / du)))) end
            local tt = d / mps + ang / 30 + ((d < 1200 and ang > 60) and 8 or 0)
            -- already turning for it (but not while flying away from it to turn round: then
            -- another target ahead is quicker, 19 Oct 2026, Mission 14's reinforcement waves)
            if curName and n == curName and ang < 60 then tt = d / mps + 2 end
            return w / (tt + 4), d, w, n
        end)
        if ok and sc then
            if sc > bestScore then best, bestScore, bestD, bestW = o, sc, dm, wt end
            if curName and name == curName then curScore, curD, curW = sc, dm, wt end
        end
    end
    if curScore and curScore >= bestScore * 0.5 then
        return current, curD, curScore, curW
    end
    if not best and hiddenBest then
        -- nothing attackable, but mission targets hidden somewhere (drones in their launch
        -- containers): fly there, which is where they come out
        return hiddenBest, hiddenD / 10, 0.001, 0.1
    end
    return best, bestD, bestScore, bestW
end

local function tap(c, key, seconds)
    c.taps[key] = now() + (seconds or 0.08)   -- hold a few frames so the game sees the press
end

-- Missile defence when not fighting (flying to a point, along a route, a stunt): flares
-- only, no break turn (that would throw a stunt or a canyon route off its line). 19 Oct
-- 2026, Mission 06: two missiles took 80 health in the first 20 s of a "fly to" toward the
-- tunnel, with 78 flares left unused.
local function transitDefence(p, loc)
    local d = ap.transit
    if not d then d = { taps = {}, lastFlare = -100, flares = 0 }; ap.transit = d end
    local t = now()
    if Aware then
        d.myName = d.myName or p:GetFullName()
        if t - (d.enemyAt or -1) > 0.2 then d.enemyAt = t; pcall(Aware.updateEnemies, p, d.myName) end
        pcall(Aware.updateMissiles, p, d.myName, { loc.X, loc.Y, loc.Z }, ap.myV or { 0, 0, 0 })
    end
    local alert = 0
    pcall(function() alert = p.MissileAlert end)
    alert = tonumber(alert) or 0
    local threat = Aware and Aware.threats[1] or nil
    if threat then
        local vn = threat.info and threat.info.VeryNearWarningRadiusSquared and math.sqrt(threat.info.VeryNearWarningRadiusSquared) or 8000
        if ((threat.miss == nil) or threat.miss < 2000) and (threat.tgo < 2.0 or threat.dist < vn) and t - d.lastFlare > 1.2 then
            tap(d, KEY.flare); d.lastFlare = t; d.flares = d.flares + 1
            event("flare", { reason = "tracker, not fighting", missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10 })
        end
    elseif alert >= 2 and t - d.lastFlare > 1.5 then
        tap(d, KEY.flare); d.lastFlare = t; d.flares = d.flares + 1
        event("flare", { reason = "warning, not fighting" })
    end
    local keys = {}
    for key, untilT in pairs(d.taps) do
        if t < untilT then keys[#keys + 1] = key else d.taps[key] = nil end
    end
    return keys
end

-- An attack run on a ground object, the way a pilot flies one: run in from a few km out,
-- no lower than 600 m above the ground until 3.5 km, then a dive no steeper than 25
-- degrees straight at it; too close (700 m) or too low (250 m above the ground): extend,
-- flying away and climbing until 3.5 km out, then turn back in. Returns the aim and the
-- phase ("in" or "out").
local function groundRun(c, key, st, loc, F, alt)
    c.runs = c.runs or {}
    local hd = math.sqrt((st.X - loc.X) ^ 2 + (st.Y - loc.Y) ^ 2)
    local dm = math.sqrt(hd ^ 2 + (st.Z - loc.Z) ^ 2) / 10
    local h = { (st.X - loc.X) / math.max(hd, 1), (st.Y - loc.Y) / math.max(hd, 1) }
    local above = ap.agl or alt
    -- Under a cloud layer (learned, or given in the order: "cloudbase M"), the whole run stays
    -- 80 m below it: run in level and low, shallow dive, pull out low.
    local cb = ap.cloudBase
    if cloudBase and cloudMission == (missionLevel() or "?") and (not cb or cloudBase < cb) then cb = cloudBase end
    local outH, inH, minAbove, maxDive = 700, 550, 250, -0.47
    c.underClouds = nil
    if cb then
        local ground = alt - above
        local cap = cb - 80 - ground
        if cap < 650 then
            outH, inH = clamp(cap, 150, 700), clamp(cap, 150, 550)
            minAbove, maxDive = 90, -0.3
            c.underClouds = cb
        end
    end
    local run = c.runs[key]
    if not run then
        local off = math.deg(math.acos(clamp((h[1] * F[1] + h[2] * F[2]) / math.max(math.sqrt(F[1] ^ 2 + F[2] ^ 2), 0.01), -1, 1)))
        run = (dm < 2500 and off > 30) and "out" or "in"
        c.runs[key] = run
    end
    if run == "in" and (dm < 700 or above < minAbove) then run = "out" end
    if run == "in" and dm < 2500 then c.runInAt = now() end
    -- under clouds the runs are low and level: turn back at the missile's 2 km lock range
    -- (a pass is about 20 s; Mission 14's reinforcements leave about 100 s)
    if run == "out" and dm > (c.underClouds and 2000 or 2600) then run = "in" end
    if run ~= c.runs[key] then event("attack_run", { target = key, phase = run == "in" and "running in" or "extending", dist_m = dm }) end
    c.runs[key] = run
    if run == "out" then
        return unit({ -h[1], -h[2], clamp((outH - above) / 1500, -0.3, 0.4) }), run, dm
    end
    if dm > 2600 then
        return unit({ h[1], h[2], clamp((inH - above) / 1500, -0.3, 0.4) }), run, dm
    end
    return unit({ h[1], h[2], math.max((st.Z - loc.Z) / math.max(hd, 1), maxDive) }), run, dm
end

local function combatStep(p, loc, rot, F, R, alt, dt)
    local c = ap.combat
    local t = now()
    local keys = {}
    if Aware then
        local myP = { loc.X, loc.Y, loc.Z }
        local myV = { 0, 0, 0 }
        if c.prevMe and dt > 0 then myV = { (loc.X - c.prevMe[1]) / dt, (loc.Y - c.prevMe[2]) / dt, (loc.Z - c.prevMe[3]) / dt } end
        c.prevMe = myP
        c.myV = c.myV and { c.myV[1] * 0.6 + myV[1] * 0.4, c.myV[2] * 0.6 + myV[2] * 0.4, c.myV[3] * 0.6 + myV[3] * 0.4 } or myV
        c.myName = c.myName or p:GetFullName()
        if not c.weaponsRead then c.weaponsRead = true; pcall(Aware.readWeapons, weapons(p)) end
        if t - (c.enemyAt or -1) > 0.1 then c.enemyAt = t; Aware.updateEnemies(p, c.myName) end
        Aware.updateMissiles(p, c.myName, myP, c.myV)
    end
    local ts = targetSelection(p)
    local tgt = ts and call(ts, "GetSelectedTarget")
    if tgt and not alive(tgt) then tgt = nil end
    -- Is the game's selection worth it? Every 2 s the most important enemy is worked out
    -- (nearestEnemy); when the game has something much less important selected, press Tab
    -- to look for the important one, and if Tab cannot find it, fly toward it (the game
    -- offers what is close and in front of the nose).
    c.skip = c.skip or {}
    if tgt and c.skip[objName(tgt)] and t < c.skip[objName(tgt)] then c.prefAt = -100 end
    -- a chosen target is kept at least 6 s (an attack run needs time; switching every
    -- second, as on 18 Oct 23:10, kills nothing), then re-judged once a second
    local curOk = c.pref and alive(c.pref) and not (c.skip[objName(c.pref)] and t < c.skip[objName(c.pref)])
    -- while extending away from a ground target the choice is open again (see nearestEnemy)
    local extending = curOk and c.runs and c.runs[objName(c.pref)] == "out"
    if t - (c.prefAt or -100) > 1 and not (curOk and not extending and t - (c.prefSince or -100) < 6) then
        c.prefAt = t
        local kmhNow = call(p, "GetSpeedKmph")
        local pref, prefDist, prefScore, prefW = nearestEnemy(loc, c.skip, F, curOk and c.pref or nil, kmhNow)
        if pref and not sameObj(pref, c.pref) then
            c.prefSince, c.prefLockedAt, c.prefPointed = t, nil, 0
            event("priority", { target = objName(pref), dist_m = prefDist, weight = prefW, score = prefScore })
        end
        c.pref, c.prefDist, c.prefW = pref, prefDist, prefW
    elseif curOk then
        local pl = locOf(c.pref)
        if pl then c.prefDist = math.sqrt((pl.X - loc.X) ^ 2 + (pl.Y - loc.Y) ^ 2 + (pl.Z - loc.Z) ^ 2) / 10 end
    end
    c.overriding = false
    -- The chosen enemy is selected directly: what a player does by pressing Tab until it
    -- comes up, without the luck of the game's cycle order (which in Mission 14 never offered
    -- the SAM site the bot circled for 20 s). The game's own lock-on does the rest.
    if ts and c.pref and alive(c.pref) and not sameObj(tgt, c.pref) then
        -- (counted: if the game keeps putting its own choice back, the lock never builds)
        c.selWrites = (c.selWrites or 0) + 1
        c.gameSel = tgt and objName(tgt) or "nothing"
        -- Through the game's own SelectTarget (19 Oct 2026): it is what Tab calls. Given the
        -- next target and "forced", it checks the target can be selected (lock-on mark, stealth,
        -- health), marks it as the player's target, and hands it to the first lock seeker.
        -- Writing SelectedTarget directly (as until 19 Oct) skipped all of that, so targets the
        -- game's own cycle never offered got no seeker and never locked.
        local okS = pcall(function()
            ts.NextTarget = c.pref
            ts:SelectTarget(true)
        end)
        local now_ = call(ts, "GetSelectedTarget")
        if okS and sameObj(now_, c.pref) then
            tgt = c.pref
        else
            -- the game refused it: write it directly so the pilot can still aim at it, and say why
            c.refused = c.refused or {}
            local n = objName(c.pref)
            if not c.refused[n] then
                c.refused[n] = true
                local li = lockInfo(c.pref)
                event("select_refused", { target = n, mark = li.mark or -1, special = li.special or false })
                log("  the game would not select " .. n .. " (" .. lockText(li) .. "); aiming at it anyway")
            end
            local okW = pcall(function() ts.SelectedTarget = c.pref end)
            if okW then tgt = c.pref end
        end
    end
    if t - (c.selWinAt or -100) >= 1 then
        c.selWinAt, c.selWritesLast, c.selWrites = t, c.selWrites or 0, 0
    end
    -- a target that never locks (the game will not let it be attacked, or it hides) is left
    -- alone for a minute after 6 s of pointing at it within 2.5 km without a lock (only the
    -- time it is in front counts: an attack run spends half its time flying away)
    if tgt and c.pref and sameObj(tgt, c.pref) then
        if sameObj(call(p, "GetLockedOnTarget"), tgt) then c.prefLockedAt = t end
        local pl = locOf(tgt)
        if pl and not c.prefLockedAt then
            local du0 = math.sqrt((pl.X - loc.X) ^ 2 + (pl.Y - loc.Y) ^ 2 + (pl.Z - loc.Z) ^ 2)
            local cosA = ((pl.X - loc.X) * F[1] + (pl.Y - loc.Y) * F[2] + (pl.Z - loc.Z) * F[3]) / math.max(du0, 1)
            -- only inside the armed weapon's own lock range (85% of it) and within 20 degrees:
            -- time spent closing in from further out is not a failed lock (it falsely ruled out
            -- half the reinforcement wave on 18 Oct 23:24)
            local Wl = Aware and Aware.weapons
            local armedNow = call(p, "IsSpecialWeaponArmed") == true
            local lr = (armedNow and Wl and Wl.special and Wl.special.LockonRange) or (Wl and Wl.main and Wl.main.LockonRange) or 20000
            if du0 < lr * 0.85 and cosA > 0.94 then c.prefPointed = (c.prefPointed or 0) + dt end
        end
        if not c.prefLockedAt and (c.prefPointed or 0) > 8 then
            local n = objName(c.pref)
            c.lockFails = c.lockFails or {}
            c.lockFails[n] = (c.lockFails[n] or 0) + 1
            local away = c.lockFails[n] >= 2 and 300 or 60      -- twice: five minutes
            c.skip[n] = t + away
            event("unselectable", { target = n, dist_m = c.prefDist, why = "no lock after 8 s pointed at it in range", away_s = away })
            c.pref, c.prefAt = nil, -100
        end
    end

    -- the previous target: did it die?
    if c.target and not sameObj(c.target, tgt) then
        local died = not alive(c.target)
        if died and creditedKills[c.targetName] then
            died = true                         -- counted already (OnDeath)
        elseif died then
            creditedKills[c.targetName] = true
            c.kills = c.kills + 1
            event("kill", { target = c.targetName, callsign = c.targetCallsign, after_s = t - c.targetSince, missiles = c.shotsAtTarget })
            log(string.format("  KILL: %s %s after %.0f s, %d missiles", c.targetName, c.targetCallsign, t - c.targetSince, c.shotsAtTarget))
        end
        c.target = nil
        if died then
            c.pref, c.scanTarget = nil, nil
            -- the frame a unit dies the game is tearing it down: touch nothing more this
            -- frame (fly straight on), pick the next target from the next frame on
            c.prefAt = t - 1.5
            return nil, {}
        end
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
    -- The missile homing on us that arrives first (awareness.lua): flare about two seconds
    -- before it would arrive, and from four seconds out break across its line of approach,
    -- the turn it has to match hardest, with the high-G turn for the last two and a half.
    local threat = Aware and Aware.threats[1] or nil
    c.threatText = nil
    if threat then
        local V = Aware.vec
        local vn = threat.info.VeryNearWarningRadiusSquared and math.sqrt(threat.info.VeryNearWarningRadiusSquared) or 8000
        c.threatText = string.format("missile from %s: %.0f m, impact in %.1f s, would miss by %.0f m", threat.ownerName or "?",
            threat.dist / 10, math.min(threat.tgo, 99), threat.miss / 10)
        -- flares are few (Hard: all gone 90 s into Mission 14's base attack, 19 Oct 00:00):
        -- only for a missile predicted to pass within 200 m (or not yet predicted)
        local flareMiss = (threat.miss == nil) or threat.miss < 2000
        if flareMiss and (threat.tgo < 2.0 or threat.dist < vn) and t - c.lastFlare > 1.2 then
            tap(c, KEY.flare); c.lastFlare = t; c.flares = c.flares + 1; threat.flared = true
            event("flare", { reason = "tracker", missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10 })
        end
        -- break only for one predicted to pass within 350 m (200 m on the last 2.5 km of an
        -- attack run), or unknown: a break costs the attack run, and SAM sites fire every few
        -- seconds (Mission 14, 18 Oct: two minutes of breaks for missiles predicted to miss by
        -- 500-1400 m and no kills; at 23:57 a whole reinforcement wave lost to breaks; 250/120 m
        -- was tried at 00:04 and cost 117 health in under 3 minutes)
        local breakMiss = (c.runInAt and t - c.runInAt < 0.5) and 2000 or 3500
        if threat.tgo < 4.0 and (not threat.miss or threat.miss < breakMiss) then
            local los = V.unit(V.sub(threat.p, { loc.X, loc.Y, loc.Z }))
            local side = V.unit(V.cross(los, { 0, 0, 1 }))
            if V.dot(side, F) < 0 then side = V.mul(side, -1) end
            c.breakAim = unit({ side[1], side[2], -0.15 })
            if not c.breakUntil or t > c.breakUntil then
                event("evade", { missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10, miss_m = threat.miss / 10 })
            end
            c.breakUntil = t + 0.4
            c.breakWhy = "missile, impact in " .. string.format("%.1f s", threat.tgo)
            if threat.tgo < 2.5 then keys[#keys + 1] = KEY.high_g end
        end
    elseif alert >= 2 and t - c.lastFlare > 1.5 then
        -- the game warns but the tracker has nothing (a missile it has not picked up yet)
        tap(c, KEY.flare); c.lastFlare = t; c.flares = c.flares + 1
        event("flare", { reason = "warning" })
        c.breakDir = (c.breakDir or 1) * -1
        c.breakAim = unit({ R[1] * c.breakDir + F[1] * 0.2, R[2] * c.breakDir + F[2] * 0.2, 0.15 })
        c.breakUntil = t + 2.0
        c.breakWhy = "missile warning"
    end

    -- An enemy that is after us (its AI is tracking us) and sits behind within 2 km: turn
    -- into it rather than let it settle on our tail, unless our own target is close.
    c.pursuer = nil
    if Aware and not threat then
        local V = Aware.vec
        local me = { loc.X, loc.Y, loc.Z }
        for _, tr in pairs(Aware.tracks) do
            if tr.kind == "plane" and tr.onMe and tr.p then
                local d = V.sub(tr.p, me)
                local dl = V.len(d)
                if dl < 20000 and V.dot(V.unit(d), F) < -0.3 and (not c.pursuer or dl < c.pursuerDist) then
                    c.pursuer, c.pursuerDist = tr, dl
                end
            end
        end
        if c.pursuer and c.pursuer ~= c.lastPursuer then
            event("pursuer", { enemy = c.pursuer.name, dist_m = c.pursuerDist / 10, state = c.pursuer.state })
        end
        c.lastPursuer = c.pursuer
    end

    local aim, text
    if c.breakUntil and t < c.breakUntil then
        aim = c.breakAim
        text = "BREAK (" .. (c.breakWhy or "?") .. ")"
    elseif c.pursuer and (not c.lastDist or c.lastDist > 2500) then
        local P = c.pursuer.p
        aim = unit({ P[1] - loc.X, P[2] - loc.Y, P[3] - loc.Z })
        text = string.format("turning into %s, which is after us %.0f m behind (%s)", c.pursuer.name, c.pursuerDist / 10, c.pursuer.state or "?")
        if t - c.lastTab > 1.0 then tap(c, KEY.next_target); c.lastTab = t end
    elseif not tgt then
        if t - c.lastTab > 0.7 then tap(c, KEY.next_target); c.lastTab = t end
        -- With nothing selected, go back to the standard missiles: an air-only special
        -- weapon (the LAAM) armed hides every ground target from selection (Mission 02,
        -- 18 Oct: the bot circled an airbase for minutes with the LAAM still armed).
        if call(p, "IsSpecialWeaponArmed") == true and t - (c.lastSwitch or -100) > 1.5 then
            tap(c, KEY.weapon); c.lastSwitch = t
            event("weapon_switch", { to = "standard missiles", why = "nothing selected; the special weapon hides some targets", dist_m = -1 })
        end
        c.skip = c.skip or {}
        if t - c.scanAt > 2 then
            c.scanAt = t
            local cand, candDist, candScore = nearestEnemy(loc, c.skip, F, c.scanTarget and alive(c.scanTarget) and c.scanTarget or nil, call(p, "GetSpeedKmph"))
            -- (nearestEnemy keeps the one being worked on unless another is clearly better)
            local keep = false
            if not keep then
                if not sameObj(c.scanTarget, cand) then c.pointedFor = 0 end
                c.scanTarget, c.scanDist, c.scanScore = cand, candDist, candScore
            end
        end
        local st = c.scanTarget and alive(c.scanTarget) and locOf(c.scanTarget)
        if st then
            local d3, du3 = unit({ st.X - loc.X, st.Y - loc.Y, st.Z - loc.Z })
            local dm3 = du3 / 10
            local hd = math.sqrt((st.X - loc.X) ^ 2 + (st.Y - loc.Y) ^ 2)
            local h = { (st.X - loc.X) / math.max(hd, 1), (st.Y - loc.Y) / math.max(hd, 1) }
            local isPlane = airborne(c.scanTarget)
            if isPlane or not Aware then
                aim = unit({ st.X - loc.X, st.Y - loc.Y, clamp(st.Z - loc.Z, -0.3 * hd, 0.3 * hd) })
            else
                -- a ground object: the game selects what the nose points at, so fly a proper
                -- attack run at it
                aim = groundRun(c, objName(c.scanTarget), st, loc, F, alt)
            end
            -- nose on it: ask the game to select it (Tab), and count how long we have
            -- pointed at it without the game offering it as a target
            local offS = math.deg(math.acos(clamp(dot(d3, F), -1, 1)))
            if offS < 20 and t - c.lastTab > 0.4 then tap(c, KEY.next_target); c.lastTab = t end
            if offS < 15 and dm3 < 3000 then c.pointedFor = (c.pointedFor or 0) + dt end
            if (c.pointedFor or 0) > 4 then
                local n = objName(c.scanTarget)
                c.skip[n] = t + 60
                event("unselectable", { target = n, dist_m = dm3 })
                c.scanTarget, c.pointedFor, c.scanAt = nil, 0, -100
            end
            text = string.format("no target selected; flying toward %s %s %.0f m away (%.0f deg off the nose, pointed at it %.1f s)",
                objName(c.scanTarget), callsign(c.scanTarget), dm3, offS, c.pointedFor or 0)
            c.speed = (dm3 > 3500) and 1150 or 750
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
        -- With a track: aim where the target will be (its route, or its present turn), at
        -- the meeting time for our own speed when far, the gun's when close.
        local tr = Aware and Aware.trackFor(tgt)
        c.predText = nil
        if tr and tr.p and tr.v then
            local V = Aware.vec
            local mySpeed = c.myV and V.len(c.myV) or 1700
            local speed = dm < 1500 and 10000 or math.max(mySpeed, 1000)
            local ip, it = Aware.intercept(tr, { loc.X, loc.Y, loc.Z }, speed, 8)
            if it and it < 8 then
                aim = unit({ ip[1] - loc.X, ip[2] - loc.Y, ip[3] - loc.Z })
                local _, how = Aware.predict(tr, it)
                c.predText = string.format("aiming where it will be in %.1f s (%s), state %s%s", it, how, tr.state or "?", tr.onMe and ", tracking us" or "")
            end
        end
        local offT = math.deg(math.acos(clamp(dot(dir, F), -1, 1)))
        -- Special weapon: arm it when it fits the moment, put it away when it doesn't.
        --  * long-range kind (lock range well beyond the standard missile's): for a target
        --    beyond the standard missile's lock range and inside the special's;
        --  * multi-lock kind: when two or more enemies sit inside its range and cone;
        --  * ground-only kind: for a ground target.
        local W = Aware and Aware.weapons
        local sp = W and W.special
        local armed = call(p, "IsSpecialWeaponArmed") == true
        local want = false
        local why = nil
        if sp and sp.LockonRange then
            local mainRange = (W.main and W.main.LockonRange) or 20000
            local isPlane = airborne(tgt)
            if sp.targets == "ground only" then
                want = not isPlane and du < sp.LockonRange; why = "ground target"
            elseif sp.multi then
                local n = 0
                for _, tr2 in pairs(Aware.tracks) do
                    if tr2.kind == "plane" and tr2.p then
                        local d2, l2 = Aware.vec.unit(Aware.vec.sub(tr2.p, { loc.X, loc.Y, loc.Z }))
                        if l2 < sp.LockonRange and math.deg(math.acos(clamp(dot(d2, F), -1, 1))) < (sp.LockonAngle or 30) then n = n + 1 end
                    end
                end
                want = n >= 2; why = n .. " enemies in its cone"
            elseif sp.LockonRange > mainRange * 1.3 then
                -- an air-only special (the LAAM) for planes only: armed, it hides ground targets
                local fits = sp.targets ~= "air only" or isPlane
                want = fits and du > mainRange * 0.9 and du < sp.LockonRange * 0.95; why = "beyond standard missile range"
            elseif sp.targets == "air only" and ((sp.Damage or 0) > ((W.main and W.main.Damage) or 0)
                    or (sp.MaxRotationAngle or 0) > ((W.main and W.main.MaxRotationAngle) or 0)) then
                -- simply a better air-to-air missile (the HCAA: 60 damage against 40, turns
                -- harder, reloads faster; 19 Oct 2026): armed for anything in the air within its
                -- range, put away for ground targets (armed, it hides them)
                want = isPlane and du < sp.LockonRange * 0.95; why = "better air-to-air missile"
            end
            local left = call(weapons(p), "GetSpecialWeaponCount")
            if left and left == 0 then want = false; why = "special weapon empty" end
        end
        if want ~= armed and t - (c.lastSwitch or -100) > 1.5 then
            tap(c, KEY.weapon); c.lastSwitch = t
            event("weapon_switch", { to = want and (sp and sp.class or "special") or "standard missiles",
                                     why = want and (why or "-") or ("no longer: " .. (why or "-")), dist_m = dm })
        end
        c.specialText = armed and ("special weapon armed (" .. (why or "") .. ")") or nil
        local lockObj = call(p, "GetLockedOnTarget")
        local locked = sameObj(lockObj, tgt)
        c.lockDiag = nil
        if not locked then
            c.lockDiag = string.format("not locked: the game's lock is on %s; selection put back %d times in the last second (the game had %s); target %s; seekers %s",
                lockObj and objName(lockObj) or "nothing", c.selWritesLast or 0, c.gameSel or "-", lockText(lockInfo(tgt)), seekersText(ts))
        end
        local range = c.missileRange
        if armed and sp and sp.LockonRange then range = math.max(range, sp.LockonRange / 10) end
        -- Agile targets (drones; 19 Oct 2026, Mission 04's container-launched UAVs on Ace: 51
        -- missiles for 16 kills in 15 minutes, single shots from 2 km dodged): closer, nose-on,
        -- and a pair at a time rather than one.
        local agileInfo = objInfo(tgt)
        if agileInfo.agile == nil then agileInfo.agile = agileInfo.name:find("uav", 1, true) ~= nil or agileInfo.name:find("drone", 1, true) ~= nil end
        local agile = agileInfo.agile and not (armed and sp and sp.targets == "ground only")
        local maxOff, gap = 40, c.missileGap
        if agile then maxOff = 20; if c.shotsAtTarget % 2 == 1 then gap = 0.3 end end
        -- An agile drone outturns a missile fired close (Mission 04 on Ace, 19 Oct 2026: from
        -- 1.5 to 2.1 km 12 of 23 missiles were followed by the kill, from under 1.5 km 4 of 247):
        -- missiles from 1.3 km out to the lock range, the gun inside that
        local minRange = agile and 1300 or 0
        if locked and dm < range and dm > minRange and offT < maxOff and t - c.lastMissile > gap then
            tap(c, KEY.missile); c.lastMissile = t; c.shots = c.shots + 1; c.shotsAtTarget = c.shotsAtTarget + 1
            if armed then c.specialShots = (c.specialShots or 0) + 1 end
            event("missile", { target = c.targetName, dist_m = dm, off_deg = offT, special = armed })
            firedAt[objName(tgt)] = t
            -- One missile enough? (your idea, 18 Oct 2026: the plane carries two at a time, so
            -- one each at two targets saves time and ammunition.) If the target's health is no
            -- more than the missile's damage, it is set aside until the missile should have
            -- arrived and the next target is chosen at once for the second missile; if it is
            -- still alive afterwards it comes back into the choice.
            local hp = call(tgt, "GetHealth")
            local spec = armed and sp or (W and W.main)
            local dmgPer = spec and spec.Damage
            if hp and dmgPer and hp > 0 and hp <= dmgPer and not agile then
                local mspeed = (spec and spec.SpeedMaximum) or 10000
                -- confirmed below when the missile count drops (a press with no missile
                -- loaded launches nothing); unlimited counts (Casual) cannot confirm, so no
                c.pendingShot = { name = objName(tgt), hp = hp, damage = dmgPer, t = t,
                                  flight = du / math.max(mspeed * 0.6, 3000) + 1.0, special = armed }
            end
        end
        -- The game's lock is on another enemy (its seeker can stay on the previous one, or
        -- pick its own): when that one is worth at least half the chosen target, fire at it
        -- rather than hold the missiles (Mission 14, 18 Oct 23:55: four times in a minute the
        -- lock sat on a landing-zone Apache other than the bot's pick, and nothing was fired)
        if not locked and lockObj and t - c.lastMissile > c.missileGap then
            local ln = objName(lockObj)
            if ln and ln ~= "invalid" and alive(lockObj) and not (c.skip[ln] and t < c.skip[ln]) then
                local ll = locOf(lockObj)
                if ll then
                    local dl3, du3 = unit({ ll.X - loc.X, ll.Y - loc.Y, ll.Z - loc.Z })
                    local offL = math.deg(math.acos(clamp(dot(dl3, F), -1, 1)))
                    local wL = enemyWeight(lockObj, ll)
                    if du3 / 10 < range and offL < 40 and wL >= 0.5 * (c.prefW or 0) then
                        tap(c, KEY.missile); c.lastMissile = t; c.shots = c.shots + 1
                        if armed then c.specialShots = (c.specialShots or 0) + 1 end
                        event("missile", { target = ln, dist_m = du3 / 10, off_deg = offL, special = armed, why = "the game's lock, not the chosen target" })
                        firedAt[ln] = t
                        local hp = call(lockObj, "GetHealth")
                        local spec = armed and sp or (W and W.main)
                        local dmgPer = spec and spec.Damage
                        if hp and dmgPer and hp > 0 and hp <= dmgPer then
                            local mspeed = (spec and spec.SpeedMaximum) or 10000
                            c.pendingShot = { name = ln, hp = hp, damage = dmgPer, t = t,
                                              flight = du3 / math.max(mspeed * 0.6, 3000) + 1.0, special = armed }
                        end
                    end
                end
            end
        end
        -- A ground target (one the tracker does not follow as a plane): come in no lower
        -- than 600 m above the ground, dive no steeper than 25 degrees, pull out by 900 m.
        if Aware and not airborne(tgt) then
            local phase
            aim, phase = groundRun(c, c.targetName, tl, loc, F, alt)
            c.groundText = string.format("ground attack run, %s, %.0f m above ground%s", phase == "in" and "running in" or "extending", ap.agl or alt,
                c.underClouds and string.format(" (under the clouds at %.0f m)", c.underClouds) or "")
        else
            c.groundText = nil
            -- A helicopter close by and far off the nose: a plane cannot turn tightly enough to
            -- point at it, so circling it wastes the time (Mission 14, 18 Oct: two minutes at
            -- 200-700 m behind Apaches). Open out to 1.6 km, turn back, come in nose-on.
            local info = objInfo(tgt)
            if info.heli == nil then info.heli = hasAny(info.name, HELI) end
            -- an agile drone too close for a missile and off the nose: open out the same way,
            -- to 1.8 km, and come back for a missile shot from range
            if info.agile and not info.heli then
                c.heliOut = c.heliOut or {}
                local key = c.targetName
                -- ...but never with the drone on our tail: flying straight away from a drone
                -- that is chasing us hands it a gun shot (19 Oct 2026, Mission 06: shot down
                -- from 200 m behind, 31 health gone in one second, while "opening out").
                -- Then turn hard into it instead, so it overshoots.
                local dtr = Aware and Aware.trackFor(tgt)
                local onTail = dtr and dtr.onMe and offT > 90 and dm < 1500
                if onTail then
                    c.heliOut[key] = nil
                    aim = unit({ tl.X - loc.X, tl.Y - loc.Y, tl.Z - loc.Z })
                    keys[#keys + 1] = KEY.high_g
                    c.groundText = string.format("drone on our tail %.0f m behind: turning hard into it", dm)
                    if t - (c.onTailAt or -100) > 5 then c.onTailAt = t; event("drone_on_tail", { target = key, dist_m = dm, off_deg = offT }) end
                end
                if not onTail and not c.heliOut[key] and dm < 900 and offT > 25 then c.heliOut[key] = true; event("drone_open_out", { target = key, dist_m = dm }) end
                if c.heliOut[key] and dm > 1800 then c.heliOut[key] = nil end
                if c.heliOut[key] then
                    local away = unit({ loc.X - tl.X, loc.Y - tl.Y, loc.Z - tl.Z })
                    aim = unit({ away[1], away[2], clamp(away[3], -0.2, 0.3) })
                    c.groundText = "drone too close for a missile: opening out to 1.8 km"
                end
            end
            if info.heli then
                c.heliOut = c.heliOut or {}
                local key = c.targetName
                if not c.heliOut[key] and dm < 700 and offT > 50 then
                    c.heliOut[key] = true
                    event("heli_open_out", { target = key, dist_m = dm, off_deg = offT })
                end
                if c.heliOut[key] and dm > 1600 then c.heliOut[key] = nil end
                if c.heliOut[key] then
                    local away = unit({ loc.X - tl.X, loc.Y - tl.Y, 0 })
                    aim = unit({ away[1], away[2], clamp((250 - (ap.agl or alt)) / 1500, -0.2, 0.3) })
                    c.groundText = "helicopter too close to turn onto: opening out to 1.6 km"
                end
            end
        end
        if dm < 1000 and offT < 5 then keys[#keys + 1] = KEY.gun; c.gunFrames = c.gunFrames + 1 end
        if dm < 300 and offT < 30 then
            -- about to fly into it: pull up and away
            aim = unit({ F[1] + 0.0, F[2], F[3] + 0.8 })
        end
        text = string.format("target %s %s %.0f m, %.0f deg off nose%s%s%s", c.targetName, c.targetCallsign, dm, offT, locked and ", LOCKED" or "",
            c.predText and ("; " .. c.predText) or "", c.specialText and ("; " .. c.specialText) or "")
        if c.groundText then text = text .. "; " .. c.groundText end
        if c.lockDiag and dm < 2500 then text = text .. "; " .. c.lockDiag end
        c.speed = dm > 3000 and 1150 or (dm > 1200 and 850 or 650)   -- close the distance fast, then slow for the turn fight
        c.lastDist = dm
    end

    -- Escort (19 Oct 2026, Mission 04's transport "Mother Goose One", marked by the mission as
    -- the one to protect: the drones that kill it appear 80 s into the phase and need only 15
    -- to 35 s, while the bot was 20 km away chasing an unrelated drone). With an ally to protect
    -- and nothing within 8 km of it, the bot stays with it instead of hunting far away.
    local guard, guardD = nil, math.huge
    for _, a in ipairs(allyGround) do
        if a.protect then
            local d2 = math.sqrt((a[1] - loc.X) ^ 2 + (a[2] - loc.Y) ^ 2 + (a[3] - loc.Z) ^ 2)
            if d2 < guardD then guard, guardD = a, d2 end
        end
    end
    c.escortText = nil
    if guard and not (c.breakUntil and t < c.breakUntil) then
        local tl2 = tgt and locOf(tgt)
        local tgtNear = tl2 and math.sqrt((tl2.X - guard[1]) ^ 2 + (tl2.Y - guard[2]) ^ 2 + (tl2.Z - guard[3]) ^ 2) < 80000
        if not tgtNear and guardD > 25000 then
            aim = unit({ guard[1] - loc.X, guard[2] - loc.Y, (guard[3] + 3000) - loc.Z })
            c.speed = guardD > 60000 and 1150 or 800
            c.escortText = string.format("escorting the ally to protect, %.0f m away", guardD / 10)
            text = c.escortText .. ((text and ("; was: " .. text)) or "")
        end
    end

    -- Real launches: the ammunition going down (Casual's unlimited counts read -1).
    if t - (c.ammoAt or -100) > 0.25 then
        c.ammoAt = t
        local wa = weapons(p)
        local m, sCount = call(wa, "GetMainWeaponCount"), call(wa, "GetSpecialWeaponCount")
        if c.ammo then
            local launched = (m and c.ammo.m and m >= 0 and m < c.ammo.m) or false
            local launchedSp = (sCount and c.ammo.s and sCount >= 0 and sCount < c.ammo.s) or false
            if launched then
                c.launches = (c.launches or 0) + (c.ammo.m - m)
                event("launch", { weapon = "missile", n = c.ammo.m - m, left = m, target = c.targetName })
            end
            -- a one-missile kill on its way: set the target aside until it should have hit and
            -- choose the next at once, so the second loaded missile goes to another target
            local ps = c.pendingShot
            if ps and t - ps.t < 1.0 and ((ps.special and launchedSp) or (not ps.special and launched)) then
                c.skip[ps.name] = t + ps.flight
                c.prefAt, c.pref, c.prefSince = -100, nil, -100
                c.oneShots = (c.oneShots or 0) + 1
                c.lastMissile = t - c.missileGap + 0.35
                event("one_shot", { target = ps.name, hp = ps.hp, damage = ps.damage, set_aside_s = ps.flight })
                c.pendingShot = nil
            elseif ps and t - ps.t >= 1.0 then
                c.pendingShot = nil
            end
            if sCount and c.ammo.s and sCount >= 0 and sCount < c.ammo.s then
                c.specialLaunches = (c.specialLaunches or 0) + (c.ammo.s - sCount)
                event("launch", { weapon = "special", n = c.ammo.s - sCount, left = sCount, target = c.targetName })
            end
        end
        c.ammo = { m = m, s = sCount }
    end
    for key, untilT in pairs(c.taps) do
        if t < untilT then keys[#keys + 1] = key else c.taps[key] = nil end
    end
    if c.threatText then text = (text or "") .. " | THREAT: " .. c.threatText end
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
    -- Not moving at all = paused or in a menu: never press a key then (W and S also move a
    -- menu's cursor; 18 Oct 2026 a held W moved the pause menu to "Flight Option").
    if not ap.lastLoc or (loc.X == ap.lastLoc.X and loc.Y == ap.lastLoc.Y and loc.Z == ap.lastLoc.Z) then
        CoopKeys_Set("")
        ap.lastLoc = ap.lastLoc or { X = loc.X, Y = loc.Y, Z = loc.Z }
        ap.stillFor = (ap.stillFor or 0) + dt
        if ap.stillFor > 1.5 and not ap.frozen then
            ap.frozen = true
            CoopKeys_Set("")
            log("  fly: the plane has stopped moving (game paused, a menu, or the mission is over); keys let go")
            event("frozen", {})
        end
        return true
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
        extraKeys = transitDefence(p, loc)
    end
    if not aim then aim = F end
    -- "fly to X Y Z through": a point to fly THROUGH (a gap under a bridge, between towers;
    -- the owner's vision test, 19 Oct 2026). Passed when it is behind the plane along the line
    -- of approach; then the order's "then" goal (attack) or the heading it had.
    if ap.goal.kind == "point" and ap.goal.through then
        local g = ap.goal
        local d = { g.x - loc.X, g.y - loc.Y, g.z - loc.Z }
        if not g.dir then g.dir = unit(d); g.closest = math.huge; g.health0 = call(p, "GetHealth") end
        local dl = math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
        if dl < g.closest then g.closest = dl end
        if not g.passed and dot(d, g.dir) < 0 then
            local hp = call(p, "GetHealth")
            event("stunt_done", { closest_m = g.closest / 10, damage = (g.health0 or 0) - (hp or 0), x = g.x, y = g.y, z = g.z })
            log(string.format("  fly: through the point (closest %.0f m, damage %s); straight on with vision for 1.5 km", g.closest / 10, tostring((g.health0 or 0) - (hp or 0))))
            -- carry straight on, still seeing, until clear of the structure (19 Oct 2026: the
            -- switch to the fight mode right inside the Space Elevator's base took the plane
            -- into its ring 3 s after it had passed through cleanly)
            g.passed, g.passedAt = true, { loc.X, loc.Y, loc.Z }
        end
        if g.passed then
            -- straight on, level-ish; the vision block below bends it round what is in the way.
            -- (Until 19 Oct 05:05 the vision's own last choice was fed back in here as the
            -- wanted direction, and in Mission 06 the plane drifted into a vertical climb to
            -- 11.7 km; the end check counted only horizontal distance, so it never ended.)
            -- Wanted: a 17 degree climb away (the vision keeps it level while a roof is
            -- overhead). Simulated through Mission 06's tunnel with the real rays (tools\
            -- vision-sim.lua): wanting level flight, the plane cleared the hill beyond the exit
            -- by 8 m; wanting this climb, by 40 m and more.
            local h = unit({ g.dir[1], g.dir[2], 0 })
            aim = unit({ h[1], h[2], 0.3 })
            local away = math.sqrt((loc.X - g.passedAt[1]) ^ 2 + (loc.Y - g.passedAt[2]) ^ 2 + (loc.Z - g.passedAt[3]) ^ 2)
            g.passedT = g.passedT or now()
            if away > 15000 or now() - g.passedT > 15 then g.done = true end
        end
    end
    if (ap.goal.kind == "route" and ap.goal.route.done) or (ap.goal.kind == "point" and ap.goal.done) then
        local nextGoal = ap.goal["then"]
        local what = ap.goal.route and ap.goal.route.name or "the point"
        event("route_done", { route = what, next = nextGoal or "hold heading" })
        log("  fly: end of " .. what .. (nextGoal and (", now: " .. nextGoal) or ", holding the heading"))
        ap.vision = ap.visionAfter or false
        if nextGoal == "attack" then
            -- the route was the low-level approach; the fight after it has no ceiling and no
            -- searchlights to hide from (Mission 14: "Radio silence has been lifted!")
            ap.ceiling, ap.avoidBeams = nil, false
            if Gim then Gim.ceiling, Gim.ceilingSet = nil, false end
            ap.goal = { kind = "attack", text = "attack (after route)", speed = 700 }
            ap.combat = { kills = 0, shots = 0, shotsAtTarget = 0, gunFrames = 0, flares = 0, lastMissile = -100, lastTab = -100,
                          lastFlare = -100, scanAt = -100, taps = {}, lastAlert = 0, missileRange = 3000, missileGap = 1.2 }
        else
            local h = math.deg(math.atan(F[2], F[1]))
            ap.goal = { kind = "heading", heading = h, alt = math.min(alt, (ap.ceiling or 99999) - 60), speed = 600, text = "heading after route" }
        end
    end
    -- Keep inside the mission area: past the pull-out line, head back to where the order began.
    if call(p, "IsBeyondPulloutLine") then
        if not ap.wasOutside then event("beyond_pullout", {}); log("  fly: past the mission area's edge, turning back") end
        ap.wasOutside = true
        aim = unit({ ap.home.X - loc.X, ap.home.Y - loc.Y, 0 })
    else
        ap.wasOutside = false
    end
    -- Stay alive: below the floor, or heading for it within 4 s, climb away first. The floor
    -- is height above the real ground where the terrain sensor sees ground (awareness.lua:
    -- line traces below the plane and below its course 1-4 s ahead), above the sea elsewhere.
    local floor = ap.floor
    local agl, ahead = nil, nil
    if Aware then
        local gv = ap.myV or { 0, 0, 0 }
        if ap.prevLoc and dt > 0 then
            local v = { (loc.X - ap.prevLoc[1]) / dt, (loc.Y - ap.prevLoc[2]) / dt, (loc.Z - ap.prevLoc[3]) / dt }
            gv = { gv[1] * 0.6 + v[1] * 0.4, gv[2] * 0.6 + v[2] * 0.4, gv[3] * 0.6 + v[3] * 0.4 }
        end
        ap.prevLoc = { loc.X, loc.Y, loc.Z }
        ap.myV = gv
        local g = Aware.updateGround(p, { loc.X, loc.Y, loc.Z }, gv)
        agl, ahead = g.below, g.ahead
    end
    -- Look ahead (nav.lua): is the way the pilot wants to go clear of the ground, the
    -- ceiling and the searchlight beams for the next few seconds? If not, the nearest
    -- clear direction instead.
    ap.navText = nil
    -- the searchlights: found once per order, their beams followed ten times a second
    if Gim and ap.avoidBeams then
        if not ap.lightsScanned then ap.lightsScanned = true; pcall(Gim.scan) end
        if t - (ap.lightsRefreshAt or -100) > 3 then ap.lightsRefreshAt = t; pcall(Gim.refreshLights) end
        if next(Gim.lights) and t - (ap.lightsAt or -100) > 0.1 then
            ap.lightsAt = t
            pcall(Gim.updateLights, { loc.X, loc.Y, loc.Z }, 15000)
        end
    end
    if Nav and Nav.cells > 0 and ap.myV and not ap.vision then
        local myP = { loc.X, loc.Y, loc.Z }
        if t - (ap.navAt or -100) > 0.1 then
            ap.navAt = t
            -- on a route the beams are timed by speed (below), never dodged by steering:
            -- in a canyon, swerving away from a beam is swerving toward a wall
            local beams = nil
            if Gim and ap.avoidBeams and next(Gim.lights) and ap.goal.kind ~= "route" then
                beams = Gim.beamChecker(myP, 40000, 5, 0.5, 1.0)
            end
            local onRoute = ap.goal.kind == "route"
            local rules = { floor = ap.navFloor or 40, ceiling = ap.ceiling and (ap.ceiling - 15) * 10 or nil, beams = beams,
                            horizon = onRoute and 3.5 or 5, rate = math.rad(24), step = 0.5, minBadT = onRoute and 1.6 or nil }
            local d, why = Nav.choose(p, myP, ap.myV, aim, rules)
            ap.navAim, ap.navWhy = d, why
        end
        if ap.navWhy then aim = ap.navAim; ap.navText = ap.navWhy end
    end
    -- Vision (fans of rays, no survey): twenty times a second the free direction closest to
    -- the wanted one, and the walls around the plane (vision.lua)
    -- In a fight it is a safety net (19 Oct 2026, Mission 04: two crashes into the Space
    -- Elevator's structure during attack runs on the SAM sites around it): the free direction
    -- is only taken when the wanted one is blocked within the next 3 seconds, and the normal
    -- controller keeps flying.
    local visionSafety = ap.goal.kind == "attack" and not ap.vision
    if (ap.vision or visionSafety) and Vision and ap.myV and Nav and Nav.fast then
        if t - (ap.visAt or -100) > 0.05 then
            ap.visAt = t
            local d, why = Vision.choose({ loc.X, loc.Y, loc.Z }, ap.myV, aim, { horizon = 4.5, need = 3.0, centre = not visionSafety })
            if visionSafety then
                local L = Vision.last
                local sp = math.sqrt(ap.myV[1] ^ 2 + ap.myV[2] ^ 2 + ap.myV[3] ^ 2) / 10
                local need = math.max(sp, 120) * 3.0
                local blocked = L and ((L.wantedFree and L.wantedFree < need) or (L.velFree and L.velFree < need * 0.8))
                if not blocked then d, why = nil, nil
                elseif why then why = "obstacle: " .. why end
            end
            ap.visAim, ap.visWhy = d, why
            if why and why ~= ap.visLogged and t - (ap.visLogAt or -100) > 0.5 then
                ap.visLogged, ap.visLogAt = why, t
                local W = Vision.last and Vision.last.walls
                event("vision", { text = why, free_m = Vision.last and Vision.last.free or -1,
                                  left = W and W.left or -1, right = W and W.right or -1, up = W and W.up or -1, down = W and W.down or -1 })
            end
        end
        if ap.visAim then aim = ap.visAim; ap.navText = ap.visWhy end
    else
        ap.visAim, ap.visWhy = nil, nil
    end
    local height = agl and math.min(agl, alt) or alt
    local recovering
    if ap.goal.kind == "route" or ap.vision then
        -- on a planned route the straight-ahead ground check is wrong in every bend (it sees
        -- the canyon wall the route turns away from); only real low clearance counts. With
        -- vision on the same: the checks ahead look down from 3 km up and would take a bridge
        -- deck the plane is about to pass under for the ground.
        recovering = (agl ~= nil and agl < floor * 0.6) or (agl ~= nil and agl + ap.vz * 1.5 < floor * 0.4)
    else
        recovering = height < floor or alt + ap.vz * 4 < floor * 0.7 or (ahead ~= nil and ahead < (ap.ceiling and 60 or 150))
        -- a dive needs room to pull out of: the arc of a 5 g pull from this dive angle at this
        -- speed, plus a second to react, plus the floor (the measured climb rate lags a dive
        -- that is getting steeper)
        if not recovering and rot.Pitch < -10 then
            local v = kmh / 3.6
            local need = v * v / (9.81 * 5) * (1 - math.cos(math.rad(-rot.Pitch))) + v * 1.0 + floor * 0.5
            if height < need then recovering = true end
        end
    end
    ap.agl, ap.ahead = agl, ahead
    if recovering then
        local h = unit({ F[1], F[2], 0 })
        -- under a ceiling, climb only as far as it allows
        local up = 0.6
        if ap.ceiling then up = clamp((ap.ceiling - 50 - alt) / 250, 0.0, 0.6) end
        aim = unit({ h[1], h[2], up })
        ap.recoverFrames = ap.recoverFrames + 1
        if not ap.wasRecovering and now() - (ap.recoveryLoggedAt or -100) > 5 then
            ap.recoveryLoggedAt = now()
            event("ground_recovery", { alt_m = alt, above_ground_m = agl or -1, lowest_ahead_m = ahead or -1, vz = ap.vz })
        end
    end
    ap.wasRecovering = recovering
    -- The ceiling (a mission's altitude restriction): never let the plane rise through it.
    -- Where it will be in 2.5 s at its present climb must stay 25 m under it; if not, the
    -- aim tips down, harder the further over it would go.
    if ap.ceiling then
        local lim = ap.ceiling - 25
        local soon = alt + ap.vz * 2.5
        if soon > lim then
            local push = clamp((soon - lim) / 150, 0.05, 0.5)
            aim = unit({ aim[1], aim[2], math.min(aim[3], -push) })
            ap.ceilingFrames = (ap.ceilingFrames or 0) + 1
        end
        if alt > ap.ceiling and not ap.overCeiling then
            event("over_ceiling", { alt_m = alt, ceiling_m = ap.ceiling })
            log(string.format("  fly: ABOVE THE CEILING (%.0f m > %.0f m)", alt, ap.ceiling))
        end
        ap.overCeiling = alt > ap.ceiling
    end

    local f, r, u = dot(aim, F), dot(aim, R), dot(aim, U)
    local off = math.deg(math.acos(clamp(f, -1, 1)))
    local bankErr = math.deg(math.atan(r, u))     -- roll this far (+ = right) to put the aim above the canopy
    local elev = math.deg(math.atan(u, f))        -- aim above (+) or below the nose, in the plane's own frame
    local side = math.deg(math.atan(r, f))        -- aim right (+) or left of the nose

    -- Two ways of steering: a big turn banks toward the aim and pulls; small corrections
    -- keep the wings level with the horizon and nudge the nose with pitch and rudder.
    -- Low-level route flying (a canyon) never uses the big-turn mode: rolling until the aim
    -- is above the canopy can put the plane on its back near the walls (18 Oct 2026, 17 km
    -- into Mission 14: roll 170 degrees on a climbing bend, then into the wall). Instead the
    -- bank follows the sideways error, up to 72 degrees, and pitch follows the height.
    local precise = ap.goal.kind == "route" or ap.vision
    if precise then
        ap.big = false
    elseif ap.big then
        if off < 6 then ap.big = false end
    elseif off > 12 then
        ap.big = true
    end
    local rollCmd, pitchCmd, yawCmd
    if precise then
        rollCmd = pd("level", -rot.Roll + clamp(side * 2.5, -72, 72), dt, 1 / 30, 1 / 140)
        pitchCmd = pd("elev", elev, dt, 1 / 6, 1 / 25)
        yawCmd = pd("side", side, dt, 1 / 3, 1 / 20)
        ap.prevErr.bank = nil
        -- Stall guard (18 Oct 2026, 38.7 km into Mission 14: a full pull for four seconds at
        -- 450-485 km/h in a 55 degree bank, and the nose fell to -59 degrees while still
        -- pulling): below 520 km/h a hard pull is capped at three quarters.
        -- (A "nose falling while pulling" test was tried and removed the same evening: the
        -- nose's height above the horizon also falls in an ordinary banked turn, so it fired
        -- all the time and its boost drove the plane to 990 km/h.) Low speed itself is the
        -- signal: below 470 km/h boost and keep the pull gentle.
        if kmh < 520 and pitchCmd > 0.75 then pitchCmd = 0.75 end
        ap.stallPower = kmh < 470
        if ap.stallPower and pitchCmd > 0.5 then pitchCmd = 0.5 end
    elseif ap.big then
        rollCmd = pd("bank", bankErr, dt, 1 / 35, 1 / 160)
        if math.abs(bankErr) < 50 then pitchCmd = clamp(elev / 12, -1, 1) else pitchCmd = 0 end
        if elev < 0 and math.abs(bankErr) < 50 then pitchCmd = 0 end   -- never push hard in a turn; roll and pull instead
        yawCmd = 0
        ap.prevErr.level, ap.prevErr.elev, ap.prevErr.side = nil, nil, nil
        -- No split-S near the ground (19 Oct 2026, Mission 04: upside down at 1,080 m after a
        -- missile break, the turn logic pulled through the bottom and the plane hit the ground
        -- in a 60 degree dive at 880 km/h): with the lift pointing below the horizon and less
        -- than 1,500 m of air, roll upright first and pull afterwards.
        if U[3] < -0.1 and math.min(agl or alt, alt) < 1500 then
            pitchCmd = 0
            rollCmd = clamp(-rot.Roll / 25, -1, 1)
        end
    else
        rollCmd = pd("level", -rot.Roll + clamp(side * 3, -35, 35), dt, 1 / 30, 1 / 140)
        pitchCmd = pd("elev", elev, dt, 1 / 6, 1 / 25)
        yawCmd = pd("side", side, dt, 1 / 3, 1 / 20)
        ap.prevErr.bank = nil
    end
    if recovering and math.abs(rot.Roll) > 90 then pitchCmd = 0 end   -- upside down near the ground: roll first

    -- Energy floor (every mode): below 450 km/h a hard pull or the high-G turn stalls the
    -- plane (18 Oct 2026, Mission 14 base attack: down to 146 km/h, then into the ground)
    local slow = kmh < 450
    if slow then
        if pitchCmd > 0.5 then pitchCmd = 0.5 end
        if extraKeys then
            for i = #extraKeys, 1, -1 do if extraKeys[i] == KEY.high_g then table.remove(extraKeys, i) end end
        end
    end
    local keys = {}
    local v = pulse("roll", rollCmd)
    if v > 0 then keys[#keys + 1] = KEY.roll_right elseif v < 0 then keys[#keys + 1] = KEY.roll_left end
    v = pulse("pitch", pitchCmd)
    if v > 0 then keys[#keys + 1] = KEY.pitch_up elseif v < 0 then keys[#keys + 1] = KEY.pitch_down end
    v = pulse("yaw", yawCmd)
    if v > 0 then keys[#keys + 1] = KEY.yaw_right elseif v < 0 then keys[#keys + 1] = KEY.yaw_left end
    local speed = (ap.combat and ap.combat.speed) or ap.goal.speed or 650
    if ap.goal.kind == "route" and ap.routeKmh then speed = math.min(ap.routeKmh, ap.goal.maxspeed or 9999) end
    -- The beams as moving obstacles, four times a second: for the next 2 km of route, where
    -- every nearby beam will point at the moment the plane reaches each point (each beam's
    -- recorded sweep, its live place in it). Several speeds and height offsets are tried;
    -- the smallest change that keeps every point dark is flown, and if none does, the one
    -- that meets a beam latest. A beam that touches the plane locks on and the mission fails
    -- (Mission 14), so dark means: outside the cone by its half-angle, a margin and the
    -- plane's own size.
    if ap.goal.kind == "route" and Gim and next(Gim.lights) and ap.avoidBeams then
        if t - (ap.timingAt or -100) > 0.25 then
            ap.timingAt = t
            local rt = ap.goal.route
            local s0 = rt.s or 0
            local pts = {}
            for j = rt.idx, #rt.pts do
                local q = rt.pts[j]
                if q.s > s0 + 20000 then break end
                if q.s >= s0 + 300 then pts[#pts + 1] = q end
            end
            local myP = { loc.X, loc.Y, loc.Z }
            local near = {}
            for _, L in pairs(Gim.lights) do
                if L.on and L.beamP then
                    local dx, dy = L.beamP[1] - myP[1], L.beamP[2] - myP[2]
                    if dx * dx + dy * dy < (Gim.reach(L) + 21000) ^ 2 then
                        near[#near + 1] = { L = L, dirs = Gim.predictDirs(L, 16, 0.25), half = Gim.halfAngle(L) + 2.0, reach = Gim.reach(L) }
                    end
                end
            end
            ap.beamsNear = #near
            ap.timingKmh, ap.timingText = nil, nil
            local dzWas, dyWas = rt.dz or 0, rt.dy or 0
            -- where the plane really is against the route now: it does not jump onto a shifted
            -- line; its sideways and height errors fade out over about 1.5 s
            local sideNow = rt.side or 0
            local here = Route.at(rt, s0)
            local zErrNow = loc.Z - here[3]
            if #near > 0 and #pts > 0 then
                local best, bestCost, bestLit = nil, math.huge, nil
                for _, dy in ipairs({ 0, 800, -800 }) do
                for _, dz in ipairs({ 0, -400, 200 }) do
                    for _, dv in ipairs({ 0, -50, 50, -100, 100, -150, -200 }) do
                        local v = clamp(speed + dv, 470, 720)       -- slower stalls in the canyon's bends
                        -- the speed changes at about 25 km/h a second: arrival times use that
                        -- minClear: the least distance (m) the path keeps from any beam's real
                        -- cone, for choosing the least bad option when none stays dark
                        local litAt, bad, minClear = nil, false, math.huge
                        for _, q in ipairs(pts) do
                            local fade = math.exp(-((q.s - s0) / math.max(kmh / 3.6 * 10, 1000)) / 1.5)
                            local z = q[3] + dz + (zErrNow - dz) * fade
                            local lat = dy + (sideNow - dy) * fade
                            local qx, qy = q[1], q[2]
                            if q.px then qx, qy = qx + q.px * lat, qy + q.py * lat end
                            if ap.ceiling and z > (ap.ceiling - 20) * 10 then bad = true; break end
                            if Nav and Nav.cells > 0 then
                                local g = Nav.groundAt(qx, qy)
                                if g and z - g < 300 then bad = true; break end
                                -- lower or shifted sideways only where the walls 70 m either
                                -- side are below the plane too (a canyon narrows downward)
                                if (dz < 0 or dy ~= 0) and q.px then
                                    local gl = Nav.groundAt(qx + q.px * 700, qy + q.py * 700)
                                    local gr = Nav.groundAt(qx - q.px * 700, qy - q.py * 700)
                                    if (gl and z - gl < 300) or (gr and z - gr < 300) then bad = true; break end
                                end
                            end
                            local dist = q.s - s0
                            local v0 = kmh / 3.6 * 10
                            local v1 = v / 3.6 * 10
                            local tc = math.abs(v1 - v0) / 69     -- 25 km/h per s = 69 units/s per s
                            local dc = (v0 + v1) / 2 * tc
                            local tq = dist <= dc and dist / math.max((v0 + v1) / 2, 1) or tc + (dist - dc) / math.max(v1, 1)
                            local idx = math.floor(tq / 0.25 + 0.5)
                            if idx > 64 then break end
                            for _, b in ipairs(near) do
                                local L = b.L
                                local d1, d2, d3 = qx - L.beamP[1], qy - L.beamP[2], z - L.beamP[3]
                                local dl = math.sqrt(d1 * d1 + d2 * d2 + d3 * d3)
                                if dl < b.reach and dl > 1 then
                                    local f = b.dirs[idx] or b.dirs[#b.dirs]
                                    local c = (d1 * f[1] + d2 * f[2] + d3 * f[3]) / dl
                                    if c > 0.5 then
                                        local ang = math.deg(math.acos(math.min(1, c)))
                                        local clr = math.rad(ang - b.half) * dl / 10
                                        if clr < minClear then minClear = clr end
                                        if not litAt and ang <= b.half + math.deg(math.atan(250, dl)) then litAt = tq; ap.litBy = L.name end
                                    end
                                end
                            end
                        end
                        if not bad then
                            local cost = math.abs(dv) + math.abs(dz) / 10 * 2 + math.abs(dz - dzWas) / 10 * 0.5
                                + math.abs(dy) / 10 * 1.5 + math.abs(dy - dyWas) / 10 * 0.5
                            -- None dark (the safety margin grows near a lamp): the most real
                            -- clearance wins, not the smallest change (Mission 14, 23:49: every
                            -- option "lit" 280 m from searchlight 01, the cheapest was no dip, and
                            -- the plane climbed back into the beam it was passing 30 m under)
                            if litAt then cost = 10000 - math.min(minClear, 100) * 50 + cost * 0.1 end
                            if cost < bestCost then best, bestCost, bestLit = { v = v, dz = dz, dv = dv, dy = dy }, cost, litAt end
                        end
                    end
                end
                end
                if best then
                    rt.dz, rt.dy = best.dz, best.dy
                    if best.dv ~= 0 or bestLit then ap.timingKmh = best.v end
                    if best.dv ~= 0 or best.dz ~= 0 or best.dy ~= 0 or bestLit then
                        ap.timingText = string.format("beams: %s%s%s%s", best.dv ~= 0 and string.format("%.0f km/h ", best.v) or "",
                            best.dz ~= 0 and string.format("%+.0f m ", best.dz / 10) or "",
                            best.dy ~= 0 and string.format("%s %.0f m ", best.dy > 0 and "left" or "right", math.abs(best.dy) / 10) or "",
                            bestLit and string.format("(still lit in %.1f s by %s)", bestLit, ap.litBy or "?") or "(dark)")
                        if bestLit and not ap.litWarned then
                            ap.litWarned = true
                            event("beam_unavoidable", { light = ap.litBy, in_s = bestLit })
                        end
                    else
                        ap.litWarned = false
                    end
                end
            else
                rt.dz, rt.dy = 0, 0
            end
        end
        if ap.timingKmh then speed = ap.timingKmh end
    end
    if (precise and ap.stallPower and kmh < speed) or slow then
        keys[#keys + 1] = KEY.throttle                -- too slow: boost, never brake
    elseif kmh < speed - 25 then keys[#keys + 1] = KEY.throttle elseif kmh > speed + 40 then keys[#keys + 1] = KEY.brake end
    for _, k in ipairs(extraKeys or {}) do keys[#keys + 1] = k end
    local list = table.concat(keys, ",")
    local inFront = CoopKeys_Set(list)

    if t - ap.lastLog >= 1.0 then
        ap.lastLog = t
        log(string.format("  fly %.0f s: %s | alt %.0f m (above ground %s, lowest ahead %s; vz %+.0f m/s), %.0f km/h, pitch %.0f, heading %.0f, roll %.0f | aim off %.0f deg (bank err %+.0f, elev %+.0f, side %+.0f) %s | roll %+.2f pitch %+.2f yaw %+.2f keys [%s]%s",
            t, ap.goal.text, alt, agl and string.format("%.0f", agl) or "sea", ahead and string.format("%.0f m", ahead) or "-", ap.vz, kmh, rot.Pitch, rot.Yaw, rot.Roll, off, bankErr, elev, side,
            ap.big and "TURN" or "fine", rollCmd, pitchCmd, yawCmd, list,
            recovering and " GROUND RECOVERY" or (inFront == false and " (game not in front: no keys)" or "")))
        if ap.goal.kind == "route" then
            local rt = ap.goal.route
            log(string.format("    route %s: %.1f of %.1f km (%.0f%%), %.0f m %s of the line, wanted %.0f m; %s%s", rt.name, (rt.s or 0) / 10000,
                rt.length / 10000, 100 * (rt.s or 0) / rt.length, math.abs((rt.side or 0) / 10), (rt.side or 0) >= 0 and "right" or "left",
                (rt.zWanted or 0) / 10, (ap.navText and ("NAV: " .. ap.navText) or "path clear") .. (ap.timingText and ("; " .. ap.timingText) or ""),
                Nav and Nav.last and Nav.last.clear and string.format(", least clearance ahead %.0f m", Nav.last.clear) or ""))
            if Gim and next(Gim.lights) then
                local on, nearest, nearName = 0, math.huge, nil
                for _, L in pairs(Gim.lights) do
                    if L.on and L.beamP then
                        local d = math.sqrt((L.beamP[1] - loc.X) ^ 2 + (L.beamP[2] - loc.Y) ^ 2 + (L.beamP[3] - loc.Z) ^ 2) / 10
                        if d < 5000 then on = on + 1 end
                        if d < nearest then nearest, nearName = d, L.name end
                    end
                end
                if on > 0 or nearest < 99999 then
                    log(string.format("    searchlights: %d on within 5 km, nearest lit %s %.0f m away", on, tostring(nearName), nearest))
                end
            end
        end
        if ap.combat and ap.combat.text then
            local c = ap.combat
            log(string.format("    combat: %s | kills %d, missiles %d, gun frames %d, flares %d", c.text, c.kills, c.shots, c.gunFrames, c.flares))
            if Aware and t - (c.predLogAt or -100) > 30 then
                c.predLogAt = t
                log("    predictions (2 s ahead): " .. Aware.describePredictions())
            end
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
        if ap and ap.combat and Aware then event("prediction_stats", { text = Aware.describePredictions() }) end
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
        elseif k == "through" then goal.through = true; i = i + 1
        elseif k == "route" then
            if not Route then log("fly: route.lua is not loaded") return end
            local rt, err = Route.load(args[i + 1] or "")
            if not rt then log("fly route: " .. tostring(err)) return end
            goal.kind = "route"; goal.route = rt; i = i + 2
            log(string.format("fly route: %s, %d way points, %.1f km", rt.name, #rt.pts, rt.length / 10000))
        elseif k == "ceiling" then opts.ceiling = tonumber(args[i + 1]); i = i + 2
        elseif k == "maxspeed" then goal.maxspeed = tonumber(args[i + 1]); i = i + 2
        elseif k == "then" then goal["then"] = args[i + 1]; i = i + 2
        elseif k == "beams" then opts.avoidBeams = args[i + 1] ~= "off"; i = i + 2
        elseif k == "navfloor" then opts.navFloor = tonumber(args[i + 1]); i = i + 2
        elseif k == "cloudbase" then opts.cloudBase = tonumber(args[i + 1]); i = i + 2
        elseif k == "vision" then opts.vision = args[i + 1] ~= "off"; i = i + 2
        elseif k == "focus" then
            -- "focus a,b": enemies whose name (or class) contains one of these come first (x6)
            opts.focus = {}
            for pat in string.gmatch(args[i + 1] or "", "[^,]+") do opts.focus[#opts.focus + 1] = pat:lower() end
            i = i + 2
        else log("fly: did not understand '" .. tostring(k) .. "'") return end
    end
    if goal.kind == "heading" then goal.alt = goal.alt or 1500 end
    if not goal.kind then log("fly: give 'heading H alt A', 'to X Y Z' or 'attack'") return end
    goal.text = table.concat(args, " ")
    local p0 = playerPlane()
    local home = p0 and p0:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
    ap = { goal = goal, t0 = now(), frames = 0, recoverFrames = 0, lastLog = -1, prevErr = {}, rate = {},
           floor = opts.floor, duration = opts.duration, big = false, home = { X = home.X, Y = home.Y, Z = home.Z },
           ceiling = opts.ceiling or (Gim and Gim.ceiling) or nil, navFloor = opts.navFloor,
           cloudBase = opts.cloudBase, focus = opts.focus, vision = opts.vision,
           -- beams are watched on a route (low-level infiltration), or when asked
           avoidBeams = (opts.avoidBeams == true) or (opts.avoidBeams == nil and goal.kind == "route") }
    -- (a cloud base does NOT become a ceiling for a fight: tried 19 Oct 00:00-00:17, and the
    -- ceiling governor, made for level canyon flight, pushed a rolling plane into the ground
    -- at Mission 14's base; "cloudbase" only shapes ground attack runs, above the ground)
    if ap.ceiling then log(string.format("fly: keeping under the %.0f m ceiling", ap.ceiling)) end
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
    if Nav and p0 then
        local okF, why = Nav.setupFast(p0)
        if Aware then Aware.fastReady = okF end
        if not okF then log("fly: fast traces not available (" .. tostring(why) .. "); using the script's own") end
    end
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

local function probeAware()
    if not Aware then log("probe aware: awareness.lua is not loaded") return end
    local p = playerPlane()
    if not p then log("probe aware: no player plane") return end
    local myL = p:K2_GetActorLocation()
    local myP = { myL.X, myL.Y, myL.Z }
    local w = Aware.readWeapons(weapons(p))
    for _, k in ipairs({ "main", "special", "gun" }) do
        local x = w and w[k]
        if x then
            local parts = {}
            for f, v in pairs(x) do parts[#parts + 1] = f .. "=" .. fmt(v) end
            table.sort(parts)
            log("  weapon " .. k .. ": " .. table.concat(parts, ", "))
        else
            log("  weapon " .. k .. ": not readable")
        end
    end
    Aware.updateEnemies(p, p:GetFullName())
    local lines = Aware.describeEnemies(myP, 12)
    log(string.format("  %d enemy planes tracked; nearest:", #lines))
    for _, l in ipairs(lines) do log("    " .. l) end
    local n = 0
    for _, tr in pairs(Aware.tracks) do
        if tr.kind == "missile" then
            n = n + 1
            local parts = {}
            for f, v in pairs(tr.info or {}) do parts[#parts + 1] = f .. "=" .. fmt(v) end
            table.sort(parts)
            log(string.format("    missile %s from %s, homing on %s: %s", tr.name, tr.ownerName or "?", objName(tr.obj.TargetToHome), table.concat(parts, ", ")))
        end
    end
    log("  missiles in the air: " .. n)
end

-- When a phase fails: what was near the plane (which lights were on and tracking, which
-- enemies were close), so a session can tell who saw it.
spottedReport = function()
    local p = playerPlane()
    if not p then return end
    local l = p:K2_GetActorLocation()
    local me = { l.X, l.Y, l.Z }
    log(string.format("  failure report: plane at (%.0f, %.0f) %.0f m", l.X, l.Y, l.Z / 10))
    if Gim then
        pcall(Gim.refreshLights)
        Gim.updateLights(me, 99999999)
        for _, L in pairs(Gim.lights) do
            if L.beamP then
                local d = math.sqrt((L.beamP[1] - me[1]) ^ 2 + (L.beamP[2] - me[2]) ^ 2 + (L.beamP[3] - me[3]) ^ 2) / 10
                if d < 4000 then
                    local inside, edge = Gim.inBeam(L, me)
                    local tt = call(L.obj, "GetTrackingTarget")
                    local line = string.format("    light %s %.0f m away (at %.0f m): on %s, tracking %s (%s), beam pitch %.1f yaw %.1f, plane %s the cone (%.1f deg from its edge)",
                        L.name, d, L.beamP[3] / 10, tostring(L.on), tostring(L.tracking), tt and objName(tt) or "-", L.beamR[1], L.beamR[2],
                        inside and "INSIDE" or "outside", edge)
                    log(line)
                    event("failure_light", { light = L.name, dist_m = d, tracking = L.tracking or false, inside = inside or false, edge_deg = edge })
                end
            end
        end
    end
    for _, o in ipairs(FindAllOf("GameObject") or {}) do
        pcall(function()
            if o.bIsActivated and o:GetFaction() == 0 and o:IsAlive() then
                local ol = o:K2_GetActorLocation()
                local d = math.sqrt((ol.X - me[1]) ^ 2 + (ol.Y - me[2]) ^ 2 + (ol.Z - me[3]) ^ 2) / 10
                if d < 3000 then
                    log(string.format("    enemy %s (%s) %.0f m away at %.0f m", objName(o), classOf(o), d, ol.Z / 10))
                    event("failure_enemy", { enemy = objName(o), class = classOf(o), dist_m = d, alt_m = ol.Z / 10 })
                end
            end
        end)
    end
end

forgetWorld = function(why, p)
    cachedTS, cachedTSPlane = nil, nil
    for k in pairs(infoCache) do infoCache[k] = nil end
    for k in pairs(lockCache) do lockCache[k] = nil end
    if Aware then Aware.reset(); Aware.fastReady = false end
    if Gim then Gim.reset() end
    if Nav then Nav.fast = false end
    if ap then
        if ap.combat then
            local c = ap.combat
            c.target, c.pref, c.scanTarget, c.lastPursuer, c.pursuer, c.prevTL, c.tv = nil, nil, nil, nil, nil, nil, nil
            c.prefAt, c.scanAt = -100, -100
        end
        ap.lightsScanned, ap.lightsRefreshAt = false, -100
    end
    if p and Nav then
        local okF = Nav.setupFast(p)
        if Aware then Aware.fastReady = okF end
    end
    event("world_changed", { why = why })
    log("  " .. why .. ": every remembered game object dropped" .. (p and ", fast traces set to the new plane" or ""))
end

-- "probe gimmicks": every special object of the mission and what the plane's area checks say.
local function probeGimmicks()
    if not Gim then log("probe gimmicks: gimmicks.lua is not loaded") return end
    local p = playerPlane()
    local myP = nil
    if p then local l = p:K2_GetActorLocation(); myP = { l.X, l.Y, l.Z } end
    local t0 = now()
    log("probe gimmicks: " .. Gim.scan() .. string.format(" (%.0f ms)", (now() - t0) * 1000))
    Gim.updateLights()
    for _, line in ipairs(Gim.describe(myP)) do log("  " .. line) end
    if p then
        local parts = {}
        for _, a in ipairs(AREA_CHECKS) do parts[#parts + 1] = a[1] .. "=" .. tostring(call(p, a[2])) end
        log("  plane: alt " .. fmt(call(p, "GetAltitudeMeters")) .. " m, " .. table.concat(parts, ", "))
    end
end

-- "probe trace 200": how long line traces (and sphere traces) take from a script, and
-- what they hit: straight down, and ahead along the nose.
local function probeTrace(args)
    local n = tonumber(args[1]) or 100
    local p = playerPlane()
    if not p then log("probe trace: no player plane") return end
    local KSL = UEHelpers.GetKismetSystemLibrary()
    local l = p:K2_GetActorLocation()
    local F = axes(p:K2_GetActorRotation())
    local NO = { R = 0, G = 0, B = 0, A = 0 }
    local hits, t0 = 0, now()
    local hit = {}
    for i = 1, n do
        local x, y = l.X + (i % 10) * 2000, l.Y + math.floor(i / 10) * 2000
        local ok, h = pcall(function()
            return KSL:LineTraceSingle(p, { X = x, Y = y, Z = l.Z + 30000 }, { X = x, Y = y, Z = l.Z - 80000 }, 0, false, {}, 0, hit, true, NO, NO, 0.0)
        end)
        if ok and h then hits = hits + 1 end
    end
    local t1 = now()
    log(string.format("probe trace: %d downward line traces in %.1f ms (%.3f ms each), %d hit", n, (t1 - t0) * 1000, (t1 - t0) * 1000 / n, hits))
    -- one trace ahead along the nose, 20 km: what does it hit, and how far?
    local ahead = {}
    local okA, hA = pcall(function()
        return KSL:LineTraceSingle(p, { X = l.X + F[1] * 300, Y = l.Y + F[2] * 300, Z = l.Z + F[3] * 300 },
            { X = l.X + F[1] * 200000, Y = l.Y + F[2] * 200000, Z = l.Z + F[3] * 200000 }, 0, false, {}, 0, ahead, true, NO, NO, 0.0)
    end)
    local what = "nothing"
    if okA and hA then
        local okW, w = pcall(function()
            local ip = ahead.ImpactPoint
            local actor = ahead.Actor and ahead.Actor:Get() or nil
            local comp = ahead.Component and ahead.Component:Get() or nil
            return string.format("%s / %s at %.0f m", actor and objName(actor) or "?", comp and objName(comp) or "?",
                math.sqrt((ip.X - l.X) ^ 2 + (ip.Y - l.Y) ^ 2 + (ip.Z - l.Z) ^ 2) / 10)
        end)
        what = okW and w or ("a hit (details unreadable: " .. tostring(w) .. ")")
    elseif not okA then what = "error " .. tostring(hA) end
    log("  ahead along the nose (20 km): " .. what)
    -- sphere traces (a fat ray, radius 30 m)
    local t2 = now()
    local sh = 0
    for i = 1, math.min(n, 50) do
        local x, y = l.X + (i % 10) * 2000, l.Y + math.floor(i / 10) * 2000
        local ok, h = pcall(function()
            return KSL:SphereTraceSingle(p, { X = x, Y = y, Z = l.Z + 30000 }, { X = x, Y = y, Z = l.Z - 80000 }, 300, 0, false, {}, 0, hit, true, NO, NO, 0.0)
        end)
        if ok and h then sh = sh + 1 end
        if not ok and i == 1 then log("  sphere trace error: " .. tostring(h)) end
    end
    local t3 = now()
    log(string.format("  %d sphere traces (30 m) in %.1f ms (%.3f ms each), %d hit", math.min(n, 50), (t3 - t2) * 1000, (t3 - t2) * 1000 / math.min(n, 50), sh))
end

-- "lights 30": follow every searchlight beam for 30 s, writing its direction ten times a
-- second to lights-<time>.csv along with whether the plane is in a beam (the game's own
-- check) and whether the model in gimmicks.lua thinks so.
local function recordLights(args)
    if not Gim then log("lights: gimmicks.lua is not loaded") return end
    local dur = tonumber(args[1]) or 30
    Gim.scan()
    local n = 0
    for _ in pairs(Gim.lights) do n = n + 1 end
    if n == 0 then log("lights: no searchlights in this mission") return end
    local path = OUT .. "\\lights-" .. os.date("%H%M%S") .. ".csv"
    local f = io.open(path, "w")
    if f then f:write("t,light,on,tracking,pitch,yaw,bx,by,bz,plane_in_searchlight,model_inside,model_edge_deg,dist_m,pred2_pitch,pred2_yaw\n") end
    local t0, last = now(), -1
    log(string.format("lights: following %d searchlights for %.0f s into %s", n, dur, path))
    perFrame.lights = function(p, dt)
        local t = now() - t0
        Gim.updateLights()
        if t - last >= 0.1 then
            last = t
            local l = p:K2_GetActorLocation()
            local q = { l.X, l.Y, l.Z }
            local inS = call(p, "IsInSearchLight")
            for _, L in pairs(Gim.lights) do
                if L.beamR and f then
                    local inside, edge, dl = Gim.inBeam(L, q)
                    local pp, py = Gim.beamIn(L, 2.0)
                    f:write(string.format("%.2f,%s,%s,%s,%.2f,%.2f,%.0f,%.0f,%.0f,%s,%s,%.1f,%.0f,%.2f,%.2f\n", t, L.name, tostring(L.on), tostring(L.tracking),
                        L.beamR[1], L.beamR[2], L.beamP[1], L.beamP[2], L.beamP[3], tostring(inS), tostring(inside), edge, dl / 10, pp or 0, py or 0))
                end
            end
        end
        if t >= dur then
            if f then f:close() end
            log("lights: done; sweeps seen:")
            for _, line in ipairs(Gim.describe(nil)) do if line:find("^searchlight") then log("  " .. line) end end
            return false
        end
        return true
    end
end

-- "survey x0 y0 x1 y1 step [per]": measure the ground on a grid (game units), 'per' traces
-- per frame, into survey-<time>.csv (x, y, z of the highest solid thing, empty = nothing).
-- Works while the game is paused (a menu): the level is still there.
local function survey(args)
    local x0, y0, x1, y1, stepU = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    local per = tonumber(args[6]) or 60
    if not (x0 and y0 and x1 and y1 and stepU) then log("survey: give x0 y0 x1 y1 step [per]") return end
    if not Nav then log("survey: nav.lua is not loaded") return end
    local p0 = playerPlane()
    if not p0 then log("survey: no player plane (needed as the world context)") return end
    if not Nav.fast then Nav.setupFast(p0) end
    local path = OUT .. "\\survey-" .. os.date("%H%M%S") .. ".csv"
    local f = io.open(path, "w")
    if not f then log("survey: cannot write " .. path) return end
    f:write("x,y,z\n")
    local nx = math.floor((x1 - x0) / stepU) + 1
    local ny = math.floor((y1 - y0) / stepU) + 1
    local i, total, hits, t0 = 0, nx * ny, 0, now()
    log(string.format("survey: %d x %d = %d points, %d per frame, into %s", nx, ny, total, per, path))
    perFrame.survey = function(p, dt)
        for _ = 1, per do
            if i >= total then
                f:close()
                log(string.format("survey: done, %d points, %d hit, %.0f s; %s", total, hits, now() - t0, Nav.describe()))
                event("survey_done", { points = total, hits = hits, file = path })
                return false
            end
            local ix, iy = i % nx, math.floor(i / nx)
            local x, y = x0 + ix * stepU, y0 + iy * stepU
            local hp = Nav.trace(p, { x, y, Nav.TOP }, { x, y, -20000 })
            if hp then hits = hits + 1; f:write(string.format("%.0f,%.0f,%.0f\n", x, y, hp[3])) else f:write(string.format("%.0f,%.0f,\n", x, y)) end
            i = i + 1
        end
        return true
    end
end

-- "dumpgimmicks": the mission's special objects as JSON (gimmicks-<time>.json), for the
-- route planner and the terrain picture (tools\terrain-map.py --gimmicks).
local function dumpGimmicks()
    if not Gim then log("dumpgimmicks: gimmicks.lua is not loaded") return end
    Gim.scan()
    Gim.updateLights()
    local lights, others = {}, {}
    for _, L in pairs(Gim.lights) do
        lights[#lights + 1] = { name = L.name, p = L.p, beam_p = L.beamP, beam_pitch = L.beamR and L.beamR[1], beam_yaw = L.beamR and L.beamR[2],
            mode = L.modeText, sweep_deg = L.sweepDeg, sweep_speed = L.sweepSpeed, wait_s = L.waitS, offset = L.offset,
            sees_approaching = L.seesApproach, approach_speed = L.approachSpeed, track_speed = L.trackSpeed,
            collision_deg = L.collisionDeg, radiation_deg = L.radiationDeg, reach = Gim.reach(L), half_deg = Gim.halfAngle(L),
            priority = L.priority, on = L.on, mesh_scale = L.meshScale, mesh_rot = L.meshRot }
    end
    for cls, list in pairs(Gim.objects) do
        if cls ~= "SystemObjectSearchLight" then
            for _, e in ipairs(list) do others[#others + 1] = { class = cls, name = e.name, p = e.p } end
        end
    end
    local path = OUT .. "\\gimmicks-" .. os.date("%H%M%S") .. ".json"
    local f = io.open(path, "w")
    if f then f:write(json({ lights = lights, others = others, ceiling = Gim.ceiling or false }), "\n"); f:close() end
    log("dumpgimmicks: " .. #lights .. " searchlights, " .. #others .. " other objects into " .. path)
end

-- "eval <lua>": run one line of Lua inside the game and log what it returns (for exploring
-- the game's objects from a session; orders only come from this PC, see CoopNetMod).
local function evalOrder(args)
    local code = table.concat(args, " ")
    local fn, err = load("return " .. code, "eval", "t", setmetatable({ playerPlane = playerPlane, mission = mission,
        objName = objName, call = call, FindFirstOf = FindFirstOf, FindAllOf = FindAllOf, StaticFindObject = StaticFindObject,
        Nav = Nav, Gim = Gim, Aware = Aware, ap = function() return ap end, vision = function() return Vision end }, { __index = _G }))
    if not fn then
        fn, err = load(code, "eval", "t", setmetatable({ playerPlane = playerPlane, mission = mission, objName = objName,
            call = call, Nav = Nav, Gim = Gim, Aware = Aware }, { __index = _G }))
    end
    if not fn then log("eval: " .. tostring(err)) return end
    local res = { pcall(fn) }
    local parts = {}
    for i = 2, #res do
        local v = res[i]
        if type(v) == "userdata" then
            local ok, n = pcall(function() return v:GetFullName() end)
            if ok then v = n else local ok2, s2 = pcall(function() return v:ToString() end); v = ok2 and s2 or tostring(v) end
        end
        parts[#parts + 1] = tostring(v)
    end
    log("eval " .. (res[1] and "-> " or "error: ") .. table.concat(parts, ", "))
end

local commands = {
    ping = function(args) log("pong " .. table.concat(args, " ")) end,
    eval = evalOrder,
    -- "nav load <survey.csv> [square size in game units]" / "nav status"
    nav = function(args)
        if not Nav then log("nav: nav.lua is not loaded") return end
        if args[1] == "load" then
            local t0 = now()
            local n, err = Nav.loadSurvey(args[2] or "", tonumber(args[3]))
            if not n then log("nav load: " .. tostring(err)) return end
            Nav.precise = (tonumber(args[3]) or Nav.CELL) <= 600     -- a fine survey: trust each square
            log(string.format("nav load: %d survey points in %.1f s; %s", n, now() - t0, Nav.describe()))
        else
            log("nav: " .. Nav.describe())
        end
    end,
    -- "fans <fans.csv>": the recorded sweeps of a mission's searchlights (tools\beam-fans.py --csv)
    fans = function(args)
        if not Gim then log("fans: gimmicks.lua is not loaded") return end
        local n, err = Gim.loadFans(args[1] or "")
        log(n and string.format("fans: %d recorded sweeps loaded", n) or ("fans: " .. tostring(err)))
    end,
    lights = recordLights,
    survey = survey,
    dumpgimmicks = dumpGimmicks,
    mark = function(args) local text = table.concat(args, " "); log("== " .. text); event("mark", { text = text }) end,
    -- "module vision" / "module route": load that file again from the mod folder, without
    -- UE4SS's restart of all mods (Ctrl+P), which crashed the game mid-mission on 19 Oct
    -- 04:53. Only these two: they keep no state worth losing (nav and awareness do).
    module = function(args)
        local name = args[1]
        if name ~= "vision" and name ~= "route" then log("module: give 'vision' or 'route'") return end
        package.loaded[name] = nil
        local ok, m = pcall(function() return require(name)({ log = log, event = event, now = now }) end)
        if not ok then log("module: " .. name .. ".lua did not load: " .. tostring(m)) return end
        if name == "vision" then Vision = m else Route = m end
        log("module: " .. name .. ".lua loaded again")
    end,
    -- "actors <text> [max]": every actor whose class or name contains the text (case
    -- ignored), with its position and the size of its bounding box: for finding structures
    -- to fly through (the Space Elevator, bridges, tunnels; the owner's vision tests)
    actors = function(args)
        local want = (args[1] or ""):lower()
        local maxN = tonumber(args[2]) or 40
        local p = playerPlane()
        local me = p and p:K2_GetActorLocation()
        local rows = {}
        for _, a in ipairs(FindAllOf("Actor") or {}) do
            pcall(function()
                local n = a:GetFullName():lower()
                if not n:find(want, 1, true) then return end
                local l = a:K2_GetActorLocation()
                local ext = nil
                pcall(function()
                    local o, e = {}, {}
                    a:GetActorBounds(false, o, e)
                    if e.X then ext = string.format("box %.0f x %.0f x %.0f m centred (%.0f, %.0f, %.0f)", e.X / 5, e.Y / 5, e.Z / 5, o.X, o.Y, o.Z) end
                end)
                local d = me and math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 10 or -1
                rows[#rows + 1] = { d = d, text = string.format("%7.0f m  %s at (%.0f, %.0f, %.0f) %s", d, objName(a) .. " [" .. classOf(a) .. "]", l.X, l.Y, l.Z, ext or "") }
            end)
        end
        table.sort(rows, function(x, y) return x.d < y.d end)
        log(string.format("actors '%s': %d found", want, #rows))
        for i = 1, math.min(maxN, #rows) do log("  " .. rows[i].text) end
    end,
    -- "locks [all]": every enemy game object (only the active ones unless "all") with what
    -- decides whether the game can lock it (lockInfo): its lock-on mark, mission-special flag,
    -- air or ground, mission target, and its distance
    locks = function(args)
        local p = playerPlane()
        local me = p and p:K2_GetActorLocation()
        local rows, nNo = {}, 0
        for _, o in ipairs(FindAllOf("GameObject") or {}) do
            pcall(function()
                if o:GetFaction() ~= 0 or not o:IsAlive() then return end
                local act = o.bIsActivated == true
                if not act and args[1] ~= "all" then return end
                local li = lockInfo(o)
                if not li.lockable then nNo = nNo + 1 end
                local l = o:K2_GetActorLocation()
                local d = me and math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2 + (l.Z - me.Z) ^ 2) / 10 or -1
                local tg = false
                pcall(function() tg = o:IsTGT() end)
                rows[#rows + 1] = { d = d, text = string.format("%6.0f m  %-34s %-26s %s%s%s%s", d, objName(o), classOf(o), lockText(li),
                    li.air and ", air" or ", ground", tg and ", TGT" or "", act and "" or ", not active yet") }
            end)
        end
        table.sort(rows, function(a, b) return a.d < b.d end)
        log(string.format("locks: %d enemies, %d of them cannot be locked", #rows, nNo))
        for _, r in ipairs(rows) do log("  " .. r.text) end
    end,
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
    -- "object GroundTarget1_8_Radar": the targeting flags of one game object, found by name
    object = function(args)
        local want = args[1] or ""
        local found = nil
        for _, o in ipairs(FindAllOf("GameObject") or {}) do
            if objName(o) == want then found = o; break end
        end
        if not found then log("object: none named " .. want) return end
        local function g(f) local ok, v = pcall(function() return found[f] end); return ok and tostring(v) or "?" end
        local function c(f) local ok, v = pcall(function() return found[f](found) end); return ok and tostring(v) or "?" end
        log(string.format("object %s (%s): activated %s, alive %s, faction %s, TGT %s, unidentified %s (%s), detected %s, show HUD box %s, permission to engage %s, attack-targets exception %s, needs detection %s, hidden %s, health %s/%s",
            want, found:GetClass():GetFName():ToString(), g("bIsActivated"), c("IsAlive"), c("GetFaction"), c("IsTGT"),
            g("bIsUnidentified"), c("GetIsUnidentified"), c("GetIsDetected"), g("bShowHUDBox"), g("bPermissionToEngage"),
            g("bIsAttackTargetsException"), g("bNeedsDetection"), g("bHidden"), c("GetHealth"), c("GetMaxHealth")))
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
        elseif what == "aware" then probeAware()
        elseif what == "gimmicks" then probeGimmicks()
        elseif what == "trace" then probeTrace({ table.unpack(args, 2) })
        elseif what == "fasttrace" then
            local p = playerPlane()
            if not (Nav and p) then log("probe fasttrace: no plane or no nav") return end
            local okF, why = Nav.setupFast(p)
            log("probe fasttrace: setup " .. tostring(okF) .. " (" .. tostring(why) .. ")")
            if not okF then return end
            if Aware then Aware.fastReady = true end
            local l = p:K2_GetActorLocation()
            local n = tonumber(args[2]) or 500
            local hits, usSum, t0 = 0, 0, now()
            for i = 1, n do
                local x, y = l.X + (i % 20) * 1000, l.Y + math.floor(i / 20) * 1000
                local hit, hx, hy, hz, dist, nz, actor, us = CoopTrace_Line(x, y, 120000, x, y, -20000)
                if hit then hits = hits + 1 end
                usSum = usSum + (us or 0)
            end
            local wall = (now() - t0) * 1000
            log(string.format("probe fasttrace: %d downward traces, %d hit, %.1f ms in all (%.3f ms each from the script; the engine call itself %.1f microseconds on average)",
                n, hits, wall, wall / n, usSum / n))
            local hit, hx, hy, hz = CoopTrace_Line(l.X, l.Y, l.Z - 100, l.X, l.Y, l.Z - 100000)
            log(string.format("  check under the plane: hit %s at z %s, %s m below the plane", tostring(hit), tostring(hz),
                hz and string.format("%.0f", (l.Z - hz) / 10) or "?"))
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

-- The plane's area checks, watched all the time: an event whenever one changes, with the
-- altitude (so a ceiling the mission never announces is learned from where it starts).
local areaState = {}
local function watchAreas()
    local p = playerPlane()
    if not p then areaState = {} return end
    for _, a in ipairs(AREA_CHECKS) do
        local v = call(p, a[2])
        if v ~= nil and areaState[a[1]] ~= nil and v ~= areaState[a[1]] then
            local alt = call(p, "GetAltitudeMeters")
            event("area", { what = a[1], now = v, alt_m = alt })
            log(string.format("  area: %s is now %s (altitude %s m)", a[1], tostring(v), fmt(alt)))
            -- Clouds: a target below a cloud layer cannot be locked from above it (Mission 14,
            -- 18 Oct: SAM sites never locked on attack runs from 900-1300 m, and locked at
            -- once from 200-430 m). Remember the lowest cloud met; ground attacks fly under it.
            if a[1] == "in_cloud" and alt and alt > 30 then
                local lvl = missionLevel() or "?"
                if cloudMission ~= lvl then cloudBase, cloudMission = nil, lvl end
                if not cloudBase or alt < cloudBase then
                    cloudBase = alt
                    log(string.format("  clouds: the lowest cloud met so far is at %.0f m; ground attacks stay under it", alt))
                    event("cloud_base", { alt_m = alt })
                end
            end
            if a[1] == "over_ceiling" and v == true and alt then
                -- the game says we are over its restricted altitude: that is the real ceiling
                -- (Mission 14 announces 600 m, the flag comes on at 550 m)
                if Gim then Gim.learnedCeiling = alt end
                if ap and (not ap.ceiling or alt - 5 < ap.ceiling) then
                    ap.ceiling = alt - 5
                    log(string.format("  the real ceiling is lower than announced: flying under %.0f m from now", ap.ceiling))
                    event("ceiling_learned", { alt_m = ap.ceiling })
                end
            end
        end
        areaState[a[1]] = v
    end
end

-- A landing or refuelling phase (Mission 03's "MissionPhaseBP_Landing", 19 Oct 2026): the
-- game's skip only takes once the approach itself has begun ("cleared for approach"), so it
-- is asked for every 6 s while such a phase lasts (at most 20 times).
local skipTries = 0
local function miniGameWatch()
    if not skipMiniGames or not phaseName then return end
    local pl = phaseName:lower()
    if not (pl:find("landing", 1, true) or pl:find("refuel", 1, true) or pl:find("supply", 1, true)) then skipTries = 0; return end
    if skipTries >= 20 or now() - (lastSkipAt or -100) < 6 then return end
    skipTries = skipTries + 1
    lastSkipAt = now()
    local m = mission()
    local ok = m and pcall(function() m:SkipMiniGame() end)
    log(string.format("  %s: asking the game to skip the mini-game (try %d, %s)", phaseName, skipTries, ok and "sent" or "failed"))
end

local statusTick = 0
LoopInGameThreadWithDelay(100, function()
    statusTick = statusTick + 1
    pcall(pollOrders)
    if statusTick % 10 == 0 then pcall(miniGameWatch) end
    if statusTick % 5 == 0 then writeStatus() end
    if statusTick % 3 == 0 then pcall(watchAreas) end
end)

log("ready (" .. (type(CoopNet_Since) == "function" and "orders by UDP through CoopNetMod" or "CoopNetMod missing: no way to take orders") ..
    "); files go to " .. OUT)
