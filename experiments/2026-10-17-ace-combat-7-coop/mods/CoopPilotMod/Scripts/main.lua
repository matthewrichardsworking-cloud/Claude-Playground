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
local shotInfo = {}            -- enemy name -> { kind, bounty } as known when the bot fired at it
local killTally = { n = 0 }    -- every kill credited to the bot (both ways of counting), for the fight's numbers
-- ...and per kind of target: kills, and seconds spent with one of that kind as the target
-- (killTally.kindKills, killTally.kindTime; see combatStep, 20 Oct 2026)
killTally.kindKills, killTally.kindTime = {}, {}
-- ...and what dies with a kill (20 Oct 2026, Mission 08: of 21,750 points, 9,550 came from oil
-- tanks set off by the ones the bot's missiles hit): per class of target, the kills, the other
-- targets standing within 400 m then, and the points of those that died within 1.5 s and 400 m
-- of it without the bot having fired at them. Points per neighbour times the neighbours a target
-- has now is what a missile at it is worth beyond its own points (killTally.chainValue; used
-- by the lanes once a class has three kills). Learned, so a class that sets nothing off stays 0.
-- killTally.cands: the score-phase candidates (laneCands, defined further down), with .nb.
killTally.chain, killTally.recent = {}, {}
function killTally.chainNote(name, ours)
    local cands = killTally.cands
    if not cands then return end
    local q = nil
    for _, r in ipairs(cands) do if r.name == name then q = r; break end end
    if not q or not q.x then return end
    local t = now()
    if ours then
        local cls = q.cls or "?"
        local ch = killTally.chain[cls] or { k = 0, nb = 0, pts = 0 }
        killTally.chain[cls] = ch
        ch.k, ch.nb = ch.k + 1, ch.nb + (q.nb or 0)
        local rc = killTally.recent
        rc[#rc + 1] = { t = t, x = q.x, y = q.y, cls = cls }
        if #rc > 20 then table.remove(rc, 1) end
    else
        local rc = killTally.recent
        for i = #rc, 1, -1 do
            local k = rc[i]
            if t - k.t <= 1.5 and (q.x - k.x) ^ 2 + (q.y - k.y) ^ 2 < 4000 ^ 2 then
                killTally.chain[k.cls].pts = killTally.chain[k.cls].pts + (q.bounty or 0)
                break
            end
        end
    end
end
function killTally.chainValue(q)
    local ch = killTally.chain[q.cls or "?"]
    if not ch or ch.k < 3 or ch.nb < 1 then return 0 end
    return ch.pts / ch.nb * (q.nb or 0)
end
local pointsLog = {}           -- { time, points } of every kill credited to the bot (the rate it really scores at)
local learnAgileHook           -- set further down (learnAgile): a kill of a class, for the agility measure
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

-- The modules (each file returns a function that builds it from what it needs here); one that
-- does not load is logged and left out (nil), and the pilot flies on without it
local function loadModule(name, extra)
    local envT = { log = log, event = event, now = now }
    for k, v in pairs(extra or {}) do envT[k] = v end
    local ok, m = pcall(function() return require(name)(envT) end)
    if not ok then log(name .. ".lua did not load: " .. tostring(m)); return nil end
    return m
end

-- The pilot's picture of the fight: tracks, predictions, threats (awareness.lua)
local Aware = loadModule("awareness", { call = call, objName = objName, callsign = callsign })

-- The ground and obstacles ahead: height map, path checks, steering (nav.lua)
local Nav = loadModule("nav")

-- Following a planned route (route.lua; routes come from tools\route-plan.py)
local Route = loadModule("route")

-- Seeing in 3D with fans of rays, for structures and tunnels (vision.lua, 19 Oct 2026)
local Vision = loadModule("vision")

-- The lane planner: the flight path chosen for the targets it brings into the lock cone, and
-- the chain of picks inside it (lanes.lua, 19 Oct 2026)
local Lanes = loadModule("lanes")

-- The mission's special objects: searchlights, radar areas, the altitude ceiling (gimmicks.lua)
local Gim = loadModule("gimmicks", { call = call, objName = objName })

-- The manoeuvre planner: every way the pilot wants to fly, flown ahead in this plane's model and
-- traced against the ground; a safe manoeuvre instead when it is not (maneuver.lua, 20 Oct 2026)
local Man = loadModule("maneuver")
if Man then
    -- the ground and structures for its look-ahead: the engine's own line traces (CoopPadMod)
    Man.ctx = {
        segFree = function(a, b)
            local ok, hit = pcall(CoopTrace_Line, a[1], a[2], a[3], b[1], b[2], b[3])
            return not (ok and hit)
        end,
        clearBelow = function(p, m)
            local ok, hit = pcall(CoopTrace_Line, p[1], p[2], p[3], p[1], p[2], p[3] - m * 10)
            return not (ok and hit)
        end,
        omega = function() return math.rad(38) end,      -- set to the measured turn rate in apStep
    }
end

-- Attack lines: where a ground target can be seen from, the line the plane is on soonest, and
-- the way onto it (approach.lua, 20 Oct 2026); its traces and turn rate are set in groundRun.
-- (kept in Man: the main chunk is at Lua's limit of 200 locals)
if Man then Man.approach = loadModule("approach") end

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

-- The mission's combat zone: a CombatZone actor, a box (Mission 06's: 60 x 60 km around
-- (10, 0) km). Leaving it fails the mission a few seconds after "Spare 15! Stay within the
-- operation area!" (19 Oct 2026: the bot chased a Tu-160 out of it at 1,100 km/h), and the
-- plane's own IsBeyondPulloutLine never came on. Found once per mission: of several zones,
-- the one the plane is in.
local zoneCache = { at = -100 }
local function combatZone(px, py)
    local okV, good = pcall(function() return zoneCache.actor and zoneCache.actor:IsValid() end)
    if okV and good then return zoneCache.box end
    if now() - zoneCache.at < 5 then return nil end
    zoneCache.at, zoneCache.actor, zoneCache.box = now(), nil, nil
    for _, a in ipairs(FindAllOf("CombatZone") or {}) do
        pcall(function()
            if not a:IsValid() then return end
            local o, e = {}, {}
            a:GetActorBounds(false, o, e)
            if not (e.X and e.X > 0) then return end
            local box = { x0 = o.X - e.X, x1 = o.X + e.X, y0 = o.Y - e.Y, y1 = o.Y + e.Y, cx = o.X, cy = o.Y }
            local inside = px and px > box.x0 and px < box.x1 and py > box.y0 and py < box.y1
            if not zoneCache.box or inside then zoneCache.actor, zoneCache.box = a, box end
        end)
    end
    if zoneCache.box then
        local z = zoneCache.box
        log(string.format("combat zone: %.0f x %.0f km around (%.0f, %.0f) km", (z.x1 - z.x0) / 10000, (z.y1 - z.y0) / 10000, z.cx / 10000, z.cy / 10000))
    end
    return zoneCache.box
end
-- how far inside the combat zone a point is (game units, horizontally; negative: outside)
local function zoneMargin(x, y)
    local z = combatZone(x, y)
    if not z then return math.huge end
    return math.min(x - z.x0, z.x1 - x, y - z.y0, z.y1 - y)
end

-- The HUD's score line ("SCORE 003480/024000"): a phase won on points shows its goal after
-- the slash (Mission 06 Long Day, 19 Oct 2026: 24,000 in 15 minutes; the radio never says the
-- number). The text block is looked for at most every 10 s while there is none, then read.
local scoreInfoTB, scoreInfoLookedAt = nil, -100
local function hudScoreText()
    local ok, good = pcall(function() return scoreInfoTB and scoreInfoTB:IsValid() end)
    if not (ok and good) then
        scoreInfoTB = nil
        if now() - scoreInfoLookedAt < 10 then return nil end
        scoreInfoLookedAt = now()
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            local okN, n = pcall(function() return t:GetFName():ToString() end)
            if okN and n == "ScoreInfo" then scoreInfoTB = t; break end
        end
        if not scoreInfoTB then return nil end
    end
    local okT, tx = pcall(function() return scoreInfoTB:GetText():ToString() end)
    return okT and tx or nil
end
-- The score goal the HUD shows now (a number), only while the score line is visible (a phase
-- after a score phase may keep the old text hidden), and the text itself
local function hudScoreGoal()
    local tx = hudScoreText()
    if not tx then return nil, nil end
    local okV, vis = pcall(function() return scoreInfoTB:IsVisible() end)
    if okV and vis == false then return nil, tx end
    local goal = tonumber(tx:match("/%s*(%d+)"))
    if goal and goal > 0 then return goal, tx end
    return nil, tx
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
        local hs = hudScoreText()
        s.hud_score = hs or false
        s.score_goal = hs and tonumber(hs:match("/%s*(%d+)")) or false
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
local frameErrors = {}       -- name -> { n, since, loggedAt }: errors of a per-frame function

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
            if not okf then
                -- (19 Oct 2026: one bad line removed the whole flight loop and the plane flew on
                -- uncontrolled into the ground; a test tool must keep flying through its own
                -- bugs) the keys are let go, the error logged once a second at most, and the
                -- loop kept unless it fails more than 50 times in 10 s
                if type(CoopKeys_Set) == "function" then CoopKeys_Set("") end
                local fe = frameErrors[name] or { n = 0, since = t, loggedAt = -100 }
                if t - fe.since > 10 then fe.n, fe.since = 0, t end
                fe.n = fe.n + 1
                frameErrors[name] = fe
                if t - fe.loggedAt > 1 then
                    fe.loggedAt = t
                    log("per-frame '" .. name .. "' failed (" .. fe.n .. " in the last 10 s): " .. tostring(keep))
                    event("script_error", { where = name, text = tostring(keep) })
                end
                if fe.n > 50 then log("per-frame '" .. name .. "' stopped: it keeps failing"); perFrame[name] = nil end
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
    local ours = firedAt[n] and now() - firedAt[n] < 20 and not creditedKills[n]
    pcall(killTally.chainNote, n, ours and true or false)
    -- an enemy the bot fired at in the last 20 s: its kill (the missile may land after the
    -- bot has switched to the next target, so the target-change check never sees it)
    if ours then
        creditedKills[n] = true
        -- (what it was, as known when the missile was fired: the dying unit itself is not asked)
        local si = shotInfo[n] or {}
        killTally.n = killTally.n + 1
        if si.kind then killTally.kindKills[si.kind] = (killTally.kindKills[si.kind] or 0) + 1 end
        pointsLog[#pointsLog + 1] = { now(), si.bounty or 0 }
        if si.cls and learnAgileHook then pcall(learnAgileHook, si.cls) end
        event("kill", { target = n, callsign = callsign(o), by = "missile on its way", class = si.kind or "?", bounty = si.bounty or 0 })
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
local skipState = { at = nil, tries = 0 }   -- the last skip press, and the mini-game skip tries
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
        and not lower:find("aborted", 1, true) and now() - (skipState.at or -100) > 8 then
        skipState.at = now()
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

-- What kind of enemy it is, from the game's own data (19 Oct 2026; the owner: the bot is a
-- test tool for modded games, and modded enemies will not share the vanilla names): the native
-- class the unit is built on (AIPlane, AIHeli, AIGroundVehicle, ... in the game's Nimbus code),
-- the plane's "large" flag (bombers, transports), the game's UAV component (drones), and the
-- turn limit and top speed the game gives a plane. Worked out once per object; each new
-- combination is logged once (and an event written), so a session can see how a modded unit
-- was read. Kinds: "agile" (drones), "large" (the game's large-plane flag: bombers, but in
-- Mission 06 the AV-8B carries it too), "plane", "heli", "ground".
local UAV_CLASS = nil
local kindSeen = {}
-- Classes the pilot found agile by their behaviour in this session: many missiles for each
-- kill (classStats: missiles fired and kills per class; see learnAgile)
local agileLearned, classStats = {}, {}
local function nativeClassOf(o)
    local okC, cls = pcall(function() return o:GetClass() end)
    if not okC or not cls then return nil end
    for _ = 1, 16 do
        local okN, full = pcall(function() return cls:GetFullName() end)
        if not okN or not full then return nil end
        local nm = full:match("/Script/Nimbus%.([%w_]+)$")
        if nm then return nm end
        local okS, sup = pcall(function() return cls:GetSuperStruct() end)
        if not (okS and sup and sup:IsValid()) then return nil end
        cls = sup
    end
    return nil
end
local function gameKind(o)
    local info = objInfo(o)
    if info.gkind then
        if info.gkind == "plane" and info.cls and agileLearned[info.cls] then info.gkind = "agile" end
        return info.gkind
    end
    info.cls = classOf(o)
    local native = nativeClassOf(o) or "?"
    local kind, why = "ground", native
    if native == "AIPlane" then
        kind = "plane"
        local large = false
        pcall(function() large = o.bIsLargePlane == true end)
        if large then kind, why = "large", "large plane flag" end
        if not UAV_CLASS then pcall(function() UAV_CLASS = StaticFindObject("/Script/Nimbus.AIUAVComponent") end) end
        local uav = false
        if UAV_CLASS then
            pcall(function() local comp = o:GetComponentByClass(UAV_CLASS); uav = comp ~= nil and comp:IsValid() end)
        end
        info.turnLimit = call(o, "GetTurnSpeed")
        info.maxKmh = call(o, "GetMaxSpeed")
        info.maxHp = call(o, "GetMaxHealth")
        if uav then kind, why = "agile", "UAV component"
        elseif not large and info.maxKmh and info.maxKmh < 480 and (info.maxHp or 99) <= 40 then
            -- small and slow for a plane: a drone (Mission 06's drones carry no UAV component;
            -- the game gives them a top speed of 444 against 519-667 for every fighter and
            -- bomber there, and the health of a truck). Measured behaviour can add classes
            -- later (learnAgile).
            kind, why = "agile", string.format("small and slow for a plane: top speed %.0f, health %.0f", info.maxKmh, info.maxHp or -1)
        elseif agileLearned[info.cls] then
            kind, why = "agile", "learned: many missiles for each kill"
        end
    elseif native == "AIHeli" then
        kind = "heli"
    elseif native == "?" then
        -- the class could not be read: the flag the game sets for things in the air
        local air = false
        pcall(function() air = o.bIsAir == true end)
        kind, why = air and "plane" or "ground", "bIsAir flag (class unreadable)"
    end
    info.gkind, info.native = kind, native
    local key = classOf(o) .. "|" .. kind
    if not kindSeen[key] then
        kindSeen[key] = true
        log(string.format("  kind: %s (%s) is %s (%s%s%s)", classOf(o), native, kind, why,
            info.turnLimit and string.format(", turn limit %.0f", info.turnLimit) or "",
            info.maxKmh and string.format(", top speed %.0f km/h", info.maxKmh) or ""))
        event("kind", { class = classOf(o), native = native, kind = kind, why = why, turn = info.turnLimit or -1, top_kmh = info.maxKmh or -1 })
    end
    return kind
end
-- Measured behaviour: a class of plane that needs many more missiles for each kill than its
-- health asks for dodges them (Mission 04's drones: 51 missiles for 16 kills, each needing one
-- hit). After 10 missiles at a class, more than four times the hits a kill needs (health over
-- the missile's damage) for each kill makes it agile from then on (fired at from range, in
-- pairs, no long-range special at it). Ordinary planes only: large ones (bombers) simply take
-- many hits (19 Oct 2026: a first version without the hits marked the Tu-160 agile after its
-- first LAAM salvo and barred the LAAM from it).
local function learnAgile(cls, missiles, kills, hits)
    local st = classStats[cls] or { missiles = 0, kills = 0, hits = 1 }
    st.missiles, st.kills = st.missiles + (missiles or 0), st.kills + (kills or 0)
    if hits then st.hits = hits end
    classStats[cls] = st
    -- (20 Oct 2026: from the missiles that really flew at the class, when the missile tracker is
    -- there: 8 or more followed to their end, under 35% of them hitting. Counting presses, the
    -- F-16 became "agile" after 12 presses for 2 kills, most of them LAAM presses with both rails
    -- reloading, and was then fought like a drone: opened out from, and two missile hits taken.)
    local hs = Aware and Aware.hitStats and Aware.hitStats[cls]
    local agileNow
    if Aware and Aware.hitStats then
        agileNow = hs ~= nil and hs.n >= 8 and hs.hit / hs.n < 0.35
    else
        agileNow = st.missiles >= 10 and st.missiles > 4 * math.max(st.kills, 1) * st.hits
    end
    if not agileLearned[cls] and agileNow then
        agileLearned[cls] = true
        log(string.format("  kind: %s now counts as agile (%d missiles, %d kills)", cls, st.missiles, st.kills))
        event("kind", { class = cls, kind = "agile", why = "learned: many missiles for each kill", missiles = st.missiles, kills = st.kills })
    end
end
learnAgileHook = function(cls) learnAgile(cls, 0, 1) end
if Aware then Aware.kindOf = gameKind end

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
-- How many lock seekers are locked, and how many still locking (multi-lock specials: the
-- 8AGM takes four ground targets at once; 19 Oct 2026, Mission 06: it was fired the moment
-- the first lock came, so most salvos went at one or two targets)
local function seekerCounts(ts)
    local locked, locking = 0, 0
    pcall(function()
        local arr = ts.LockonSeekers
        for i = 1, #arr do
            local sk = arr[i]
            if sk and sk:IsValid() then
                local st = type(CoopMem_Read) == "function" and CoopMem_Read(sk:GetAddress() + 0x40, 1) or nil
                if st == 3 or st == 4 then locked = locked + 1 elseif st == 1 or st == 2 or st == 5 then locking = locking + 1 end
            end
        end
    end)
    return locked, locking
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
-- Score phases, the owner's order of threats (19 Oct 2026: "neutralize the biggest threats
-- (fighters, then SAMs, attack helicopters, finally AA guns) to then allow it to be even more
-- aggressive with whatever is left", and big-point items such as bombers before AA guns, which
-- are "mostly chip damage"). Judged by what each enemy is seen doing, not by names: anything that
-- fired a missile at the plane in the last minute (fighters, SAM sites, attack helicopters) counts
-- 2.5 times its points, a gun that hit the plane 1.8 times; a gun that only sprays counts its points.
local gunMarks = {}            -- ground enemy name -> when gunfire hit the plane near it
local function threatFactor(o, n)
    if now() - shootersAt > 1 then shootersAt = now(); shooters = recentShooters() end
    local f = 1
    n = n or objName(o)
    if shooters[n] then f = 2.5 end
    if gunMarks[n] and now() - gunMarks[n] < 60 then f = math.max(f, 1.8) end
    return f
end

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
    -- An enemy chasing an ally that lost health in the last 10 s counts 4 times: it is the one
    -- shooting (20 Oct 2026, Mission 07's recon team, "not even one is to go down")
    if tr and tr.tracking and allyGround.hurt then
        local hA = allyGround.hurt[tr.tracking]
        if hA and now() - hA < 10 then w = w * 4 end
    end
    -- (tried 20 Oct 2026, Mission 07's recon team: up to 5 times more the closer it is to the
    -- ally it chases, within 1.5 km. Weights then swung with every UAV's distance to its plane
    -- and the bot switched among UAVs 10-13 km away for 104 s without a kill; taken out. The
    -- ally positions stay in allyGround.pos.)
    -- what the order says matters most in this mission ("focus AH64_00,zouen")
    if ap and ap.focus and hasAny(name, ap.focus) then w = w * 6 end
    -- Score phases ("fly attack score"): a phase won on points, not on particular targets
    -- (Mission 06 Long Day: 24,000 points in 15 minutes, the HUD's "SCORE 003480/024000"; the
    -- radio only says "You haven't done enough damage to the base!"). Each enemy counts by the
    -- points the game gives for it (GameObject.KillBountyScore: there drones 350, Tu-160 1,200,
    -- the named F-14D 1,300, fighters 220-550, ground targets 120-200), and what is not a
    -- plane a little less, since an attack run on it takes longer than a missile at a plane.
    if ap and ap.scoreMode then
        local info = objInfo(o)
        if info.bounty == nil then
            local okB, b = pcall(function() return o.KillBountyScore end)
            info.bounty = okB and tonumber(b) or 0
        end
        w = w * math.max(info.bounty, 50) / 250
        if not (Aware and Aware.trackFor(o)) then w = w * 0.6 end
    end
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
-- (Mission 14: Apaches got slow ground attack runs), so they are told by their native class
-- (AIHeli; until 19 Oct 2026 by a list of names), and anything else moving faster than a
-- ground vehicle counts as flying too.
local function airborne(o)
    if Aware and Aware.trackFor(o) then return true end
    local info = objInfo(o)
    if gameKind(o) ~= "ground" then return true end
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
-- score phases: active enemy ground targets with their points, { x, y, z, bounty }, from the
-- last target choice (for the sweep through a cluster)
local scorePts = nil
-- score phases: the lane planner's candidates (ground targets and helicopters a missile can
-- lock, with their points and health), and the best target in the air by points per second
local laneCands, laneCandsAt = {}, -100
-- the activation log (see nearestEnemy): enemies seen active so far, by name
local activeSeen, activationAt, activationStarted = {}, -100, false
local airPick, airPickRate = nil, 0
-- Score phases: how long a kill of each kind takes once it is the target (seconds), to weigh
-- targets by points per second rather than points (19 Oct 2026, Mission 06: drones worth 350
-- took 30-40 s and 8 missiles each, ground targets worth 100-200 about 10 s). Starting guesses,
-- then the average of this session's own kills of that kind.
local killTimes = { agile = 35, large = 30, plane = 20, heli = 12, ground = 10 }
-- (the kind from the game's data, gameKind; until 19 Oct 2026 from name fragments)
local function killKind(o) return gameKind(o) end
local function nearestEnemy(loc, skip, F, current, kmh)
    local best, bestScore, bestD, bestW = nil, -1, 0, 1
    local hiddenBest, hiddenD = nil, math.huge
    local curScore, curD, curW = nil, 0, 1
    local t = now()
    local objs = FindAllOf("GameObject") or {}
    local allies, names = { pos = {}, hp = allyGround.hp or {}, hurt = allyGround.hurt or {} }, {}
    -- Score phases: the points around each place (1.5 km squares of active enemies' bounty),
    -- so the bot goes where the points are thick and keeps working there instead of flying
    -- 20 km for one plane (Mission 06 phase 1, 19 Oct 2026: 28 ships in one harbour, 23 SAM
    -- and AA sites with 20 houses and helicopters around them, about 7,600 points in a few km)
    local cluster = nil
    airPick, airPickRate = nil, 0
    if ap and ap.scoreMode then
        cluster = {}
        scorePts = {}
        laneCands = {}
        for _, o in ipairs(objs) do
            pcall(function()
                -- (only what a missile can lock: Mission 06's houses carry 100 points each but
                -- have no HUD box and no permission to engage, so they pulled the sweeps toward
                -- targets that never lock, 19 Oct 07:12)
                if o.bIsActivated and o:GetFaction() == 0 and o:IsAlive() and o.bShowHUDBox ~= false and o.bPermissionToEngage ~= false then
                    local info = objInfo(o)
                    if info.bounty == nil then
                        local okB, b = pcall(function() return o.KillBountyScore end)
                        info.bounty = okB and tonumber(b) or 0
                    end
                    if info.bounty > 0 then
                        local l = o:K2_GetActorLocation()
                        local key = math.floor(l.X / 15000) .. ":" .. math.floor(l.Y / 15000)
                        cluster[key] = (cluster[key] or 0) + info.bounty
                        local akey = "A" .. math.floor(l.X / 60000) .. ":" .. math.floor(l.Y / 60000)
                        cluster[akey] = (cluster[akey] or 0) + info.bounty
                        if not (Aware and Aware.trackFor(o)) then scorePts[#scorePts + 1] = { l.X, l.Y, l.Z, info.bounty, o } end
                        -- the lane planner's targets: what is on the ground or as slow as a
                        -- helicopter (the game's own class), that a missile can lock
                        local k = gameKind(o)
                        if (k == "ground" or k == "heli") and lockInfo(o).lockable then
                            laneCands[#laneCands + 1] = { obj = o, name = objName(o), bounty = info.bounty, kind = k,
                                                          hp = call(o, "GetHealth") or 40, x = l.X, y = l.Y, z = l.Z, cls = classOf(o) }
                        end
                    end
                end
            end)
        end
        laneCandsAt = now()
        -- (each one's neighbours within 400 m, for what dies with a kill: killTally.chainValue)
        for _, q in ipairs(laneCands) do
            local nb = 0
            for _, r in ipairs(laneCands) do
                if r ~= q and (r.x - q.x) ^ 2 + (r.y - q.y) ^ 2 < 4000 ^ 2 then nb = nb + 1 end
            end
            q.nb = nb
        end
        killTally.cands = laneCands
    end
    for _, o in ipairs(objs) do
        pcall(function()
            if o.bIsActivated and o:GetFaction() == 1 and o:IsAlive() and not objInfo(o).name:find("dummy", 1, true) then
                local mk = lockInfo(o).mark
                local protect = (mk == 2 or mk == 4)
                names[objName(o)] = protect and "protect" or true
                local la = o:K2_GetActorLocation()
                local an = objName(o)
                allies.pos[an] = { la.X, la.Y, la.Z }
                -- (its health: an ally losing health is being shot at that moment)
                local hpA = call(o, "GetHealth")
                if hpA and allies.hp[an] and hpA < allies.hp[an] then allies.hurt[an] = now() end
                if hpA then allies.hp[an] = hpA end
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
    -- The activation log (general data for every report): each class of enemy the mission
    -- switches on, how many, where they are and where the plane was then (what wakes the
    -- waves: Mission 06's fighter waves come when the plane flies into spheres; a modified
    -- mission's may differ). Every 5 s at most; the first scan logs what is active at the start.
    if now() - activationAt > 5 then
        activationAt = now()
        local fresh = {}
        for _, o in ipairs(objs) do
            pcall(function()
                if o.bIsActivated and o:GetFaction() == 0 and o:IsAlive() then
                    local n = objName(o)
                    if not activeSeen[n] then
                        activeSeen[n] = true
                        local cls = classOf(o)
                        local l = o:K2_GetActorLocation()
                        local g = fresh[cls] or { n = 0, x = 0, y = 0, points = 0 }
                        g.n, g.x, g.y = g.n + 1, g.x + l.X, g.y + l.Y
                        local okB, b = pcall(function() return o.KillBountyScore end)
                        g.points = g.points + ((okB and tonumber(b)) or 0)
                        fresh[cls] = g
                    end
                end
            end)
        end
        for cls, g in pairs(fresh) do
            event("activated", { class = cls, n = g.n, x = g.x / g.n, y = g.y / g.n, points = g.points,
                                 plane_x = loc.X, plane_y = loc.Y, start = not activationStarted })
        end
        activationStarted = true
    end
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
            -- not near or past the combat zone's edge (chasing it there fails the mission)
            if zoneMargin(l.X, l.Y) < 20000 then return nil end
            local dx, dy, dz = l.X - loc.X, l.Y - loc.Y, l.Z - loc.Z
            local du = math.sqrt(dx * dx + dy * dy + dz * dz)
            local d = du / 10
            local w = enemyWeight(o, l)
            -- (ground targets only: a sweep takes them together; planes and drones move apart)
            if cluster and not (Aware and Aware.trackFor(o)) then
                local cx, cy = math.floor(l.X / 15000), math.floor(l.Y / 15000)
                local sum = 0
                for i = -1, 1 do for j = -1, 1 do sum = sum + (cluster[(cx + i) .. ":" .. (cy + j)] or 0) end end
                w = w * math.min(4, 1 + sum / 2000)
                -- and the points in the whole area (6 km squares): when one area is cleared, on to
                -- the richest one left (Mission 06: about 5,000 points in area A, 11,000 in B,
                -- 8,000 in C, and 24,000 needed; the bot had hardly been to C)
                local ax, ay = math.floor(l.X / 60000), math.floor(l.Y / 60000)
                local asum = 0
                for i = -1, 1 do for j = -1, 1 do asum = asum + (cluster["A" .. (ax + i) .. ":" .. (ay + j)] or 0) end end
                w = w * math.min(3, 1 + asum / 8000)
            end
            local ang = 0
            if F and du > 1 then ang = math.deg(math.acos(math.max(-1, math.min(1, (dx * F[1] + dy * F[2] + dz * F[3]) / du)))) end
            local tt = d / mps + ang / 30 + ((d < 1200 and ang > 60) and 8 or 0)
            -- score phases: a ground target close by and off the nose needs a loop out and back
            -- (about 25 s; 19 Oct 2026, Mission 06: after each shot the next target was often at
            -- 1.2-1.6 km and 20-40 degrees off, and the bot extended); ones further ahead chain
            if ap and ap.scoreMode and not (Aware and Aware.trackFor(o)) and d < 1600 and ang > 15 then tt = tt + 10 end
            -- ...and on a sweep through a cluster, what is ahead comes first
            if ap and ap.scoreMode and not (Aware and Aware.trackFor(o)) and ang > 30 then tt = tt + 12 end
            -- already turning for it (but not while flying away from it to turn round: then
            -- another target ahead is quicker, 19 Oct 2026, Mission 14's reinforcement waves)
            if curName and n == curName and ang < 60 then tt = d / mps + 2 end
            -- score phases: points per second, the time to get there plus the time a kill of
            -- that kind takes
            if ap and ap.scoreMode then
                local kk = killKind(o)
                if kk == "plane" or kk == "large" or kk == "agile" then
                    -- points per second for the air alternative to the lanes
                    -- (a drone at its plain points: with the threat bonus the drones that had fired
                    -- at the plane out-rated the ground passes, and fights with them over Mission
                    -- 06's third area paid about 700 points a minute against 1,000-1,400 for the
                    -- ground there; 20 Oct 2026)
                    local tf = (kk == "agile") and 1 or threatFactor(o, n)
                    -- (one already hurt takes that much less to finish, counted in hits of the
                    -- strongest weapon for the air: the hits its health now needs over the hits
                    -- its full health needs, from the game's health readings; 20 Oct 2026, a Tu-160
                    -- hit by two missiles was left for a ground group 18 km away, rated as if
                    -- untouched, 1,200 points lost. As a plain health ratio, a hurt F-16 that one
                    -- missile kills either way was rated twice as quick; with it the third bomber
                    -- fell about half a minute later on average that morning, a likely cause)
                    local hp, hpMax = call(o, "GetHealth"), call(o, "GetMaxHealth")
                    local Wa = Aware and Aware.weapons
                    local dmgA = math.max((Wa and Wa.main and Wa.main.Damage) or 40,
                        (Wa and Wa.special and Wa.special.targets ~= "ground only" and Wa.special.Damage) or 0)
                    local hf = 1
                    if type(hp) == "number" and type(hpMax) == "number" and hp > 0 and hpMax > 0 and dmgA > 0 then
                        hf = math.ceil(hp / dmgA) / math.ceil(hpMax / dmgA)
                    end
                    local pr = (objInfo(o).bounty or 0) * tf / (tt + (killTimes[kk] or 20) * hf)
                    if pr > airPickRate then airPick, airPickRate = o, pr end
                end
                return w / (tt + (killTimes[kk] or 10)), d, w, n
            end
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

-- The "guntest" order (a measurement, not a tactic; 20 Oct 2026): gun only, no missiles and no
-- lanes, attack runs carried in to 400 m; optionally at one named object, such as a building
-- the HUD gives no target box. Gun.test is nil when off. Gun.stats: the gun's effect, measured on
-- every burst at the selected target (general data for the report, and the gun's kill time for
-- the lanes): bursts, kills, damage done and seconds of firing.
-- Gun.mod: the strafing pass and when to fire (gunnery.lua; "module gunnery" loads it again).
local Gun = { test = nil, stats = { bursts = 0, kills = 0, dmg = 0, secs = 0 }, mod = loadModule("gunnery") }

-- An attack run on a ground object, the way a pilot flies one: run in from a few km out,
-- no lower than 600 m above the ground until 3.5 km, then a dive no steeper than 25
-- degrees straight at it; too close (700 m) or too low (250 m above the ground): extend,
-- flying away and climbing until 3.5 km out, then turn back in. Returns the aim and the
-- phase ("in" or "out").
-- Where a ground target can be seen from (attack geometry, 20 Oct 2026; the owner asked for
-- better pathfinding): from the target, rays outward in eight directions (the plane's side
-- first) at climbing angles of 20-80 degrees, 3 km long; on each side the lowest clear angle,
-- and the side with the lowest wins. Mission 07's radar and SAM sites sit in canyons and were
-- blocked from 3 km at 550 m above the ground, run after run. Kept 15 s. Returns { az, el
-- (degrees), at } or { at } when no side is clear.
local function attackGeometry(c, key, st, loc)
    c.geo = c.geo or {}
    local g = c.geo[key]
    if g and now() - g.at < 15 then return g end
    if type(CoopTrace_Line) ~= "function" then return nil end
    local tz = st.Z + 300
    local azPlane = math.atan(loc.Y - st.Y, loc.X - st.X)
    local best = nil
    for i = 0, 7 do
        local az = azPlane + i * math.pi / 4
        local ca, sa = math.cos(az), math.sin(az)
        for _, e in ipairs({ 20, 30, 40, 50, 60, 70, 80 }) do
            local ce, se = math.cos(math.rad(e)), math.sin(math.rad(e))
            local ok, hit = pcall(CoopTrace_Line, st.X + ca * ce * 300, st.Y + sa * ce * 300, tz + se * 300,
                st.X + ca * ce * 30000, st.Y + sa * ce * 30000, tz + se * 30000)
            if ok and not hit then
                local cost = e + ((i == 0) and 0 or 3)
                if not best or cost < best.cost then best = { az = az, el = e, cost = cost } end
                break
            end
        end
    end
    g = best and { az = best.az, el = best.el, at = now() } or { at = now() }
    c.geo[key] = g
    return g
end

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
    -- (not among obstacles: the vision safety net reported one in the last 30 s. 20 Oct 2026,
    -- Mission 07: under its 820-870 m cloud base the runs were flown among rock pillars rising
    -- into the clouds, and two attempts ended against them in under three minutes; a shorter
    -- lock range in cloud costs less than that)
    local rugged = ap.visBlockedAt and (now() - ap.t0) - ap.visBlockedAt < 30
    if cb and not rugged then
        local ground = alt - above
        local cap = cb - 80 - ground
        if cap < 650 then
            outH, inH = clamp(cap, 150, 700), clamp(cap, 150, 550)
            minAbove, maxDive = 90, -0.3
            c.underClouds = cb
        end
    end
    -- On an attack line (approach.lua): the side and angle the target can be seen from, chosen
    -- by how soon the plane is on it, flown onto from outside and down to the shot (not in score
    -- phases, whose sweeps and lanes fly their own way, nor in the gun test). 20 Oct 2026: in
    -- the wargame over Mission 07's ground, 3.1 shots a minute against 1.1 for the runs below;
    -- that day's Mission 07 runs spent four minutes on one SAM site in a canyon.
    local Appr = Man and Man.approach
    if Appr and type(CoopTrace_Line) == "function" and not (ap and ap.scoreMode) and not Gun.test then
        Appr.ctx.trace = CoopTrace_Line
        if Man and Man.ctx and Man.ctx.omega then Appr.ctx.omega = Man.ctx.omega end
        local V = ap.myV
        local u, spd = F, 200
        if V then
            local vu, vl = unit(V)
            if vl > 100 then u, spd = vu, vl / 10 end
        end
        local cloudZ = (cb and not rugged) and cb * 10 or nil
        local ok, aim, run = pcall(Appr.guide, key, { loc.X, loc.Y, loc.Z }, u, spd, above, { st.X, st.Y, st.Z + 30 }, cloudZ)
        if ok and aim then
            if run ~= c.runs[key] then event("attack_run", { target = key, phase = run == "in" and "running in" or "extending", dist_m = dm }) end
            c.runs[key] = run
            if run == "in" and dm < 2500 then c.runInAt = now() end
            return aim, run, dm
        elseif ok then
            -- seen from no usable line: set aside a minute (another target meanwhile)
            if c.skip and not (c.skip[key] and c.skip[key] > now()) then
                c.skip[key] = now() + 60
                event("skip", { target = key, why = "no attack line it can be seen along", for_s = 60 })
            end
        else
            log("approach.lua: " .. tostring(aim))
        end
    end
    -- a target whose line was blocked by terrain: the run from high, diving steeply (above)
    if c.runHigh and c.runHigh[key] then outH, inH, minAbove, maxDive = 1600, 1600, 500, -0.8 end
    -- ...and from the side and at the angle it can be seen from (attackGeometry): to an entry
    -- point on that side first, 2.4 km out and high enough for that angle, then down at it
    local geoAim = nil
    if c.runHigh and c.runHigh[key] then
        local geo = attackGeometry(c, key, st, loc)
        if geo and not geo.el then
            if c.skip then c.skip[key] = now() + 60 end      -- seen from nowhere: set aside a minute
        elseif geo then
            local el = math.rad(math.min(geo.el + 5, 80))
            maxDive = -math.tan(el)
            c.geoIn = c.geoIn or {}
            if not c.geoIn[key] then
                -- (on the ray found clear, 2.4 km along it; reached within 600 m: with the point
                -- 2.4 km out level and 1.5 km of slack, the first try's line was blocked again
                -- the moment it turned in)
                local D = 24000
                local ce = math.cos(math.rad(geo.el))
                local ex, ey = st.X + math.cos(geo.az) * D * ce, st.Y + math.sin(geo.az) * D * ce
                local ez = st.Z + 300 + math.sin(math.rad(geo.el)) * D
                local dx, dy, dz = ex - loc.X, ey - loc.Y, ez - loc.Z
                if math.sqrt(dx * dx + dy * dy + dz * dz) < 6000 then
                    c.geoIn[key] = true
                    event("attack_entry", { target = key, el_deg = geo.el, az_deg = math.deg(geo.az) })
                else
                    local hde = math.max(math.sqrt(dx * dx + dy * dy), 1)
                    geoAim = unit({ dx / hde, dy / hde, clamp(dz / hde, -0.3, 0.5) })
                end
            end
        end
    end
    local run = c.runs[key]
    if not run then
        local off = math.deg(math.acos(clamp((h[1] * F[1] + h[2] * F[2]) / math.max(math.sqrt(F[1] ^ 2 + F[2] ^ 2), 0.01), -1, 1)))
        run = (dm < 2500 and off > 30) and "out" or "in"
        c.runs[key] = run
    end
    if run == "in" and (dm < (Gun.test and 400 or 700) or above < minAbove) then run = "out" end
    -- score phases: close by and well off the nose, the plane cannot point at it without
    -- circling (19 Oct 2026, Mission 06: 31 s around one RAM launcher 1.2 km away): loop out
    if run == "in" and ap and ap.scoreMode and dm < 1600 then
        local offNow = math.deg(math.acos(clamp((h[1] * F[1] + h[2] * F[2]) / math.max(math.sqrt(F[1] ^ 2 + F[2] ^ 2), 0.01), -1, 1)))
        if offNow > 35 then run = "out" end
    end
    -- terrain between the plane and the target, more than 150 m short of it (one ray trace,
    -- five times a second, within 3 km): no running in at it; it is set aside for 20 s, so another
    -- target is taken, and this one comes back from another side later (20 Oct 2026, Mission 07:
    -- a 25-degree dive at a SAM site 1.5-2 km away behind rock, the lock "invalid" all along,
    -- ended in the rock; extending alone flip-flopped at 2.6 km with the "far enough out" rule)
    -- (inside the turn-back distance only, 2.6 km away from the run's ground: checked from 3 km,
    -- the next run "from above" was judged again before it had climbed, and set aside at once)
    local outToL = c.underClouds and 2000 or ((ap and ap.scoreMode) and 1500 or 2600)
    if run == "in" and dm < outToL and Aware and Aware.losBlocked and not geoAim then
        if now() - (c.runLosAt or -100) > 0.2 then
            c.runLosAt = now()
            c.runLosShort = Aware.losBlocked({ loc.X, loc.Y, loc.Z }, { st.X, st.Y, st.Z }, 3)
        end
        if c.runLosShort and c.runLosShort > 150 then
            run = "out"
            -- (the first time, the next run at it comes from above: a target in a canyon is seen
            -- from high, not from 550 m at 3 km; 20 Oct 2026, Mission 07's radar sites and SAMs,
            -- 10 blocked runs in 5 minutes. Set aside only when blocked from above too)
            c.runHigh = c.runHigh or {}
            local how = "from above next"
            if c.runHigh[key] then
                if c.skip then c.skip[key] = now() + 20 end
                how = "set aside 20 s"
            end
            c.runHigh[key] = true
            event("run_blocked", { target = key, dist_m = dm, short_m = c.runLosShort, next = how })
            c.runLosShort = nil
        end
    end
    if run == "in" and dm < 2500 then c.runInAt = now() end
    -- under clouds the runs are low and level: turn back at the missile's 2 km lock range
    -- (a pass is about 20 s; Mission 14's reinforcements leave about 100 s)
    -- in score phases the loop is short: about 1.5 km out, a hard turn, and back, and on the
    -- way back any target ahead will do (19 Oct 2026, Mission 06: with 2.6 km loops the bot
    -- fired 4-6 missiles a minute at ground targets; the Typhoon reloads for about 20)
    local outTo = c.underClouds and 2000 or ((ap and ap.scoreMode) and 1500 or 2600)
    if run == "out" and dm > outTo then run = "in" end
    if run ~= c.runs[key] then event("attack_run", { target = key, phase = run == "in" and "running in" or "extending", dist_m = dm }) end
    c.runs[key] = run
    if run == "out" then
        if c.geoIn then c.geoIn[key] = nil end      -- (the next run goes by the entry point again)
        return unit({ -h[1], -h[2], clamp((outH - above) / 1500, -0.3, 0.4) }), run, dm
    end
    if geoAim then return geoAim, run, dm end
    if dm > 2600 then
        return unit({ h[1], h[2], clamp((inH - above) / 1500, -0.3, 0.4) }), run, dm
    end
    return unit({ h[1], h[2], math.max((st.Z - loc.Z) / math.max(hd, 1), maxDive) }), run, dm
end

-- Score phases against ground targets: sweep through a cluster rather than circle one target
-- (19 Oct 2026, Mission 06: aiming the plane at one ground target at a time, with a loop out
-- and back after each, made 24 kills in 15 minutes; a player makes three or four times that).
-- The plane flies at the points-weighted middle of the targets within 2 km of the chosen one,
-- level at 450 m above the ground until 2.5 km out, then a shallow dive no lower than 300 m;
-- whatever comes into the cone ahead is chosen and shot (nearestEnemy prefers targets ahead);
-- past the middle it flies on 1.1 km and turns back. Only with three or more targets there.
local function sweepRun(c, loc, F, alt)
    local cx, cy, cz = c.sweepX, c.sweepY, c.sweepZ
    local hd = math.sqrt((cx - loc.X) ^ 2 + (cy - loc.Y) ^ 2)
    local h = { (cx - loc.X) / math.max(hd, 1), (cy - loc.Y) / math.max(hd, 1) }
    local above = ap.agl or alt
    local Fh = unit({ F[1], F[2], 0 })
    local off = math.deg(math.acos(clamp(h[1] * Fh[1] + h[2] * Fh[2], -1, 1)))
    c.sweepRun = c.sweepRun or "in"
    local t = now()
    -- (with time between switches: the turn back in takes about 8 s, during which the middle
    -- is still behind; without it the two switched every frame, 19 Oct 06:37)
    if c.sweepRun == "in" and (hd < 6000 or (off > 100 and hd < 20000 and t - (c.sweepT or -100) > 8)) then
        c.sweepRun, c.sweepT = "out", t
        event("sweep", { phase = "past the middle", dist_m = hd / 10, targets = c.sweepN })
    elseif c.sweepRun == "out" and hd > 11000 and t - (c.sweepT or -100) > 3 then
        c.sweepRun, c.sweepT = "in", t
        c.sweepFix = nil                     -- a new middle for the next pass
        event("sweep", { phase = "turning back in", dist_m = hd / 10, targets = c.sweepN })
    end
    if c.sweepRun == "out" then
        return unit({ Fh[1], Fh[2], clamp((4500 - above * 10) / 15000, -0.25, 0.3) }), "out", hd
    end
    local z
    if hd > 25000 then
        z = clamp((4500 - above * 10) / 15000, -0.35, 0.4)
    else
        z = math.max((cz - loc.Z) / math.max(hd, 1), -0.35)
        if above < 300 then z = math.max(z, 0.05) end
    end
    return unit({ h[1], h[2], z }), "in", hd
end

-- Score phases: the lane planner (lanes.lua). The flight path is chosen for the targets it will
-- bring into the lock cone, and the target is whatever is in the cone (the owner, 19 Oct 2026,
-- on the sweeps and attack runs: "a huge time sink in trying to get the perfect dive"). Twice a
-- second a plan from live data: the lane candidates (nearestEnemy's scan: ground targets and
-- helicopters a missile can lock, their points and health), the standard missile's cone, range
-- and damage (the game's weapon data), the reload clock (the pilot's own launches), the lock
-- time (learned from its own locks) and the plane's turn rate (measured in its own turns).
-- planeTurn: the turn rate the plane shows in hard turns (rad/s), measured in apStep; reset
-- for a new plane
local planeTurn = { est = math.rad(35), n = 0 }
local LANE_KMH = 650
-- a frame of gun fire at a target (the selected one, or a gun snap's): the burst's bookkeeping,
-- the target's health when it began and as it goes
function Gun.burstTick(c, t, obj, name, dm, off)
    local gb = c.gunBurst
    if gb and gb.name ~= name then Gun.burstEnd(c, t); gb = nil end
    if not gb then
        gb = { name = name, obj = obj, kind = gameKind(obj), hp0 = call(obj, "GetHealth"), t0 = t, d0 = dm, dmin = dm, offMax = off, frames = 0 }
        c.gunBurst = gb
    end
    gb.last, gb.frames = t, gb.frames + 1
    if dm < gb.dmin then gb.dmin = dm end
    if off > gb.offMax then gb.offMax = off end
    local hpG = call(obj, "GetHealth")
    if hpG and gb.hp0 and hpG < gb.hp0 and not gb.hitAt then gb.hitAt, gb.hitDist = t, dm end
    if hpG and gb.hp0 and hpG < gb.hp0 then c.lastGunHitName, c.lastGunHitAt = name, t end
end
-- the end of a gun burst at the selected target: what it did (Gun.stats, a "gun_burst" event)
function Gun.burstEnd(c, t)
    local gb = c.gunBurst
    if not gb then return end
    c.gunBurst = nil
    local dead = not alive(gb.obj)
    local hp1 = dead and 0 or (call(gb.obj, "GetHealth") or gb.hp1 or gb.hp0)
    local dmg = math.max(0, (gb.hp0 or 0) - (hp1 or 0))
    local dur = gb.last - gb.t0 + 0.05
    local S = Gun.stats
    S.bursts, S.dmg, S.secs = S.bursts + 1, S.dmg + dmg, S.secs + dur
    if dead then S.kills = S.kills + 1 end
    event("gun_burst", { target = gb.name, kind = gb.kind, hp0 = gb.hp0 or -1, hp1 = hp1 or -1, killed = dead, dur_s = dur,
                         frames = gb.frames, dist0_m = gb.d0, dist_min_m = gb.dmin, off_max_deg = gb.offMax,
                         first_hit_s = gb.hitAt and (gb.hitAt - gb.t0) or -1, first_hit_m = gb.hitDist or -1 })
end
local function laneWeapon(c, t)
    local W = Aware and Aware.weapons and Aware.weapons.main
    if not (W and Lanes) then return nil end
    local pending = {}
    for _, r in ipairs(c.reloadAt or {}) do if r > t then pending[#pending + 1] = r - t end end
    local maxL = W.MaxLoadedCount or 2
    -- (the range is the lock range, or nearer where the pilot's own shots at ground targets
    -- were seen to stop hitting: then the plans bring targets that close before they count)
    local rng = c.lockRange or W.LockonRange or 20000
    local capG = Aware.rangeCap and Aware.rangeCap(W.class, "ground", 0.6, 6)
    if capG and capG * 10 < rng then rng = capG * 10 end
    return { cone = math.rad(W.LockonAngle or 30), range = rng,
             minRange = Lanes.P.minRange * 10, loaded = math.max(0, maxL - #pending), reloadIn = pending,
             loadTime = c.loadTime or W.LoadTime or 5.5, lockBase = c.lockBase or 0.5, lockRate = c.lockRate or math.rad(60),
             damage = W.Damage or 40 }
end
-- the lock time model, from the pilot's own locks: seconds = base + angle / rate, fitted over
-- the last 40 locks (the seeker travels from the nose to the target; parts make it faster)
local function learnLock(c, ang, after)
    c.lockSamples = c.lockSamples or {}
    local S = c.lockSamples
    S[#S + 1] = { ang, after }
    if #S > 40 then table.remove(S, 1) end
    if #S < 6 then return end
    local n, sa, sb, saa, sab = #S, 0, 0, 0, 0
    for _, s in ipairs(S) do sa, sb, saa, sab = sa + s[1], sb + s[2], saa + s[1] * s[1], sab + s[1] * s[2] end
    local var = saa / n - (sa / n) ^ 2
    local slope = var > 1e-4 and (sab / n - (sa / n) * (sb / n)) / var or nil
    if slope and slope > 1 / math.rad(300) and slope < 1 / math.rad(10) then
        c.lockRate = 1 / slope
        c.lockBase = clamp(sb / n - slope * sa / n, 0, 2.5)
    else
        c.lockBase = clamp(sb / n - (sa / n) / (c.lockRate or math.rad(60)), 0, 2.5)
    end
end
-- Score phases: where to go next when little is left nearby. Every group of lane candidates
-- (all targets within 3 km of one, live from the scan) is rated by its points per second:
-- its points over the flight there at full throttle plus the time to clear it at the kill
-- rate measured in this fight so far (seconds per kill while engaged; 7 s until measured).
-- Nothing about any level: the groups are whatever the game has active now.
local function bestCluster(c, loc)
    local secPerKill = 7
    if c.split and (c.kills or 0) >= 4 then
        local busy = (c.split.locked or 0) + (c.split.ahead or 0) + (c.split.offnose or 0) + (c.split["break"] or 0)
        secPerKill = clamp(busy / c.kills, 3, 25)
    end
    -- (20 Oct 2026, tried and taken out again: a fresh group rated at the pace of the fight's best
    -- minute, and only groups more than 6 km away as destinations. Each moved the plane on sooner,
    -- but to small groups as well, and the attempts with them scored 14,500-21,300 against
    -- 21,900-22,000 without; see playtests\missions\m06\notes.md.)
    local cruise = 4000                              -- units/s at full throttle (about 1,450 km/h)
    local best, bestRate = nil, 0
    for _, q in ipairs(laneCands) do
        if q.x and not (c.skip[q.name] and now() < c.skip[q.name]) then
            local sum, n, sx, sy, sz = 0, 0, 0, 0, 0
            for _, r in ipairs(laneCands) do
                if r.x and (r.x - q.x) ^ 2 + (r.y - q.y) ^ 2 < 30000 ^ 2 then
                    sum, n = sum + r.bounty, n + 1
                    sx, sy, sz = sx + r.x, sy + r.y, sz + r.z
                end
            end
            local d = math.sqrt((q.x - loc.X) ^ 2 + (q.y - loc.Y) ^ 2)
            local rate = sum / (d / cruise + n * secPerKill)
            -- (only a group worth the flight is a destination: 6 targets and 1,000 points or
            -- more; a few leftovers close by rate high on points a second but are scattered,
            -- and on 20 Oct 2026 they twice called back a move between two areas after 4 s.
            -- The lanes take such leftovers in passing.)
            -- (nor a group by a place just arrived at: the lanes work it; 20 Oct 2026, a move that
            -- ended at 6 km was taken up again as soon as the plane drifted out to 6.1 km, seven
            -- times in 2.3 minutes)
            local arr = c.arrived
            local nearArrival = arr and now() - arr.t < 60 and (q.x - arr.x) ^ 2 + (q.y - arr.y) ^ 2 < 80000 ^ 2
            if rate > bestRate and n >= 6 and sum >= 1000 and zoneMargin(q.x, q.y) > 20000 and not nearArrival then
                best, bestRate = { x = sx / n, y = sy / n, z = sz / n, points = sum, n = n, dist = d, rate = rate, secPerKill = secPerKill }, rate
            end
            -- ...and the best substantial group elsewhere (2,000 points or more, its middle 8 km
            -- or more away): where to go when this place stops paying (the leaving rule in lanePlan)
            local gx, gy = sx / n, sy / n
            local gd2 = (gx - loc.X) ^ 2 + (gy - loc.Y) ^ 2
            if sum >= 2000 and gd2 > 80000 ^ 2 and zoneMargin(q.x, q.y) > 20000 and rate > (c.farRateTmp or 0) then
                c.farRateTmp = rate
                c.farTmp = { x = gx, y = gy, z = sz / n, points = sum, n = n, dist = math.sqrt(gd2), rate = rate, secPerKill = secPerKill }
            end
        end
    end
    local far = c.farTmp
    c.farTmp, c.farRateTmp = nil, nil
    return best, far
end
local function lanePlan(c, loc, F, t)
    if t - (c.lanePlanAt or -100) < 0.5 then return end
    c.lanePlanAt = t
    local wp = laneWeapon(c, t)
    if not wp then c.laneOn = false; return end
    local V = ap.myV or { F[1] * 1800, F[2] * 1800, F[3] * 1800 }
    local v = math.max(math.sqrt(V[1] ^ 2 + V[2] ^ 2 + V[3] ^ 2), 1200)
    local psi = math.atan(V[2], V[1])
    local reach = v * Lanes.P.horizon + wp.range * 3
    local tg, zs = {}, {}
    local snapList = {}
    c.laneSnap = snapList
    c.laneValue = c.laneValue or {}
    for _, q in ipairs(laneCands) do
        local n = q.name
        if not (c.skip[n] and t < c.skip[n]) and alive(q.obj) then
            local l = locOf(q.obj)
            if l then
                q.x, q.y, q.z = l.X, l.Y, l.Z
                local dx, dy = l.X - loc.X, l.Y - loc.Y
                if dx * dx + dy * dy < reach * reach and zoneMargin(l.X, l.Y) > 20000 then
                    local inc = (c.incoming[n] and t < c.incoming[n].untilT) and c.incoming[n].dmg or 0
                    local rem = (q.hp or 40) - inc
                    if rem > 0 then
                        -- a missile's value at it: its points, the share of its health one missile
                        -- takes, the threat it poses, and how often the pilot's missiles hit its
                        -- class in this fight (20 Oct 2026)
                        -- (plus what it sets off, learned: killTally.chainValue)
                        local val = (q.bounty + killTally.chainValue(q)) * math.min(1, wp.damage / rem) * threatFactor(q.obj, n)
                            * ((Aware and Aware.pHit) and Aware.pHit(q.cls) or 1)
                        c.laneValue[n] = val
                        tg[#tg + 1] = { l.X, l.Y, l.Z, val, obj = q.obj, name = n }
                        zs[#zs + 1] = l.Z
                        -- (and the gun snap's candidates: every one, the gun costs nothing)
                        local qo = q.obj
                        snapList[#snapList + 1] = { obj = qo, x = l.X, y = l.Y, z = l.Z, hp = rem, name = n, alive = function() return alive(qo) end }
                    end
                end
            end
        end
    end
    -- The missile economy (timed score phases; 20 Oct 2026: in every full 15-minute phase of
    -- Mission 06 the standard missiles ran out between minute 9.6 and 11.5 and the score
    -- stopped there). Every 2 s: at the rate of the fight so far, do the standard missiles
    -- last the phase? If not, only the best share of the shots on offer is taken, the share that
    -- makes them last: targets worth less than that share's bar (by the values above, over the
    -- targets in reach now) are left out of the plan. Toward the end of the phase the bar falls.
    if t - (c.econAt or -100) > 2 then
        c.econAt = t
        c.econSince = c.econSince or t
        local left = c.ammo and c.ammo.m
        local ms = mission()
        local T = ms and call(ms, "GetMissionPhaseTimeLeftInSeconds_S")
        local bar, keep, need = 0, 1, 0
        -- (at the rate of the whole fight so far, flights and air fights included: with the last
        -- two minutes' rate, the busiest minutes of an area, every attempt of Mission 06 on 20 Oct
        -- 2026 held fire on 100-point targets in mid-phase and ended it with 11-51 standard
        -- missiles, mostly 20-30, never fired)
        local span = t - c.econSince
        if left and left >= 0 and T and T > 20 and T < 7200 and span >= 45 and #tg >= 4 then
            local n = 0
            for _, lt in ipairs(c.launchTimes or {}) do if lt >= c.econSince then n = n + 1 end end
            need = n / span * T
            -- (and only when the forecast is 10% over what is left: the first areas are the
            -- richest, and at minute 5 the whole-fight rate forecast 81 more launches where 52
            -- came, an attempt of 20 Oct 2026 again ending with 21 missiles; 30% was used until
            -- the vertical attacks, which shoot faster: then the missiles ran out at 13.6 min)
            if need > left * 1.1 then
                keep = clamp(left / need, 0.25, 1)
                local vals = {}
                for _, q in ipairs(tg) do vals[#vals + 1] = q[4] end
                table.sort(vals)
                bar = vals[math.floor((1 - keep) * #vals) + 1] or 0
            end
        end
        -- ...and the special weapon the other way round: what is left at the end of the phase is
        -- worth nothing, so when more is left than the fight's rate would use in the time left
        -- (by 30%, and 2 more), the air shots in passing widen (below; 20 Oct 2026, an attempt of
        -- Mission 06 ended with 11 LAAMs, its 11 drones never shot at)
        local leftS = c.ammo and c.ammo.s
        c.spStart = c.spStart or leftS
        local surplus = false
        -- (judged from 5 minutes of fight on: with 90 s it switched on in the opening's bomber
        -- and F-16 fight, 20 Oct 2026, where the rate of the first minutes says little)
        if leftS and leftS > 0 and c.spStart and T and T > 20 and T < 7200 and span >= 300 then
            surplus = leftS > (c.spStart - leftS) / span * T * 1.3 + 2
        end
        if surplus ~= (c.spSurplus or false) then
            event("special_surplus", { on = surplus, left = leftS or -1, phase_left_s = T or -1 })
        end
        c.spSurplus = surplus
        c.lambda = (c.lambda or 0) * 0.5 + bar * 0.5
        if math.abs(c.lambda - (c.lambdaLogged or 0)) > 8 then
            c.lambdaLogged = c.lambda
            event("missile_economy", { left = left or -1, phase_left_s = T or -1, need = need, keep = keep, bar = c.lambda })
        end
    end
    if (c.lambda or 0) > 1 then
        local kept, zk = {}, {}
        for _, q in ipairs(tg) do
            if q[4] >= c.lambda then kept[#kept + 1] = q; zk[#zk + 1] = q[3] end
        end
        tg, zs = kept, zk
    end
    table.sort(zs)
    local zPass = (zs[math.floor(#zs / 2) + 1] or (loc.Z - (ap.agl or 300) * 10)) + Lanes.P.passAgl * 10
    -- badly hurt: passes higher, out of the guns' best reach (under 50 health 250 m higher,
    -- under 30 health 400 m; 20 Oct 2026: the fourth full phase lived five minutes on 25 health
    -- and was worn down by 40 one-point gun hits over area C's anti-aircraft sites)
    local hpNow = ap.lastHealth or 120
    if hpNow < 30 then zPass = zPass + 4000 elseif hpNow < 50 then zPass = zPass + 2500 end
    -- the target selected now: where it is in the list, and how much lock it still needs
    for i, q in ipairs(tg) do
        if q.name == c.lanePickName then
            wp.sel = i
            wp.selLeft = c.laneLocked and 0 or math.max(0, wp.lockBase + (c.pickAng0 or 0) / wp.lockRate - (t - (c.pickAt or t)))
        end
    end
    -- (and for the vertical attacks: the climb angle now, the turn rate counted on for a
    -- pull-out, and the ground under the plane)
    local pl = { x = loc.X, y = loc.Y, z = loc.Z, psi = psi, v = v, omega = planeTurn.est * (Lanes.P.omegaShare or 0.85), zPass = zPass,
                 roll = c.rollNow or 0, fz = F[3], omegaPull = planeTurn.est * Lanes.P.dive.pullShare,
                 groundZ = ap.agl and (loc.Z - ap.agl * 10) or nil }
    local plan
    if c.dive then
        -- a vertical attack is flown to its end (laneAim) without a new plan
        plan = c.lanePlan
    else
        plan = #tg > 0 and Lanes.plan(pl, wp, tg, c.lanePlan, t, function(x, y) return zoneMargin(x, y) > 30000 end) or nil
    end
    c.laneTg, c.laneWp, c.laneZPass, c.laneZNow = tg, wp, zPass, loc.Z
    -- lanes, or a plane in the air worth clearly more points per second? (the plan's shots,
    -- undiscounted, over its look-ahead: the same units as the air target's points per second;
    -- smoothed, since one plan sees two shots and the next none)
    local rate = plan and (plan.raw or plan.value) / Lanes.P.horizon or 0
    c.laneRateS = (c.laneRateS or rate) * 0.75 + rate * 0.25
    local airRate = (airPick and alive(airPick)) and airPickRate or 0
    -- ...and the planes flying with it count too, like a group on the ground: the points of
    -- every plane within 8 km of it over the flight there plus each one's kill time (Mission
    -- 06's three Tu-160s, 3,600 points together, lost against an 18 km flight to a ground group
    -- worth 5,050 when only one bomber was counted)
    if airRate > 0 and Aware then
        local al = locOf(airPick)
        local pb = objInfo(airPick).bounty or 0
        local kk = killKind(airPick)
        local kt = killTimes[kk] or 20
        if al and pb > 0 then
            local tt = math.max(pb / airRate - kt, 0)
            -- (each at its own kind's kill time: with the first one's for all, Mission 06's drone
            -- swarm counted at a Gripen's 22 s a kill instead of its own 33, 20 Oct 2026)
            local sum, n, kts = 0, 0, 0
            for _, tr in pairs(Aware.tracks) do
                if tr.kind == "plane" and tr.p and alive(tr.obj) and (tr.p[1] - al.X) ^ 2 + (tr.p[2] - al.Y) ^ 2 + (tr.p[3] - al.Z) ^ 2 < 80000 ^ 2 then
                    local b = objInfo(tr.obj).bounty or 0
                    if b > 0 then sum, n, kts = sum + b, n + 1, kts + (killTimes[killKind(tr.obj)] or kt) end
                end
            end
            if n > 1 then airRate = math.max(airRate, sum / (tt + kts)) end
        end
    end
    -- (with a special weapon that would otherwise come home unused, c.spSurplus, the air targets
    -- it takes count half again against the lanes: 20 Oct 2026, 11 LAAMs were left at the end of
    -- an attempt whose standard missiles ran out at 13.6 minutes)
    if c.spSurplus and airRate > 0 then airRate = airRate * 1.5 end
    -- Committed to an air target being engaged: locked in the last 3 s, or within reach of the
    -- weapons and within 60 degrees of the nose (19 Oct 2026, the first lanes run: the lanes took
    -- over while the LAAM had a Tu-160 locked 8 km out, worth 1,200 points)
    local engaged = false
    if c.target and c.targetName and alive(c.target) and airborne(c.target) and gameKind(c.target) ~= "heli" then
        local Wa = Aware.weapons
        local reach = math.max((Wa.main and Wa.main.LockonRange) or 20000,
            (Wa.special and Wa.special.targets ~= "ground only" and Wa.special.LockonRange) or 0) / 10
        engaged = (c.lastLockedName == c.targetName and t - (c.lastLockedAt or -100) < 3)
            or ((c.lastDist or 1e9) < reach * 1.2 and (c.lastOff or 180) < 60)
        -- (an air shot in passing is not an engagement: the lanes fly on through it; each one
        -- switched them off and on again, 20 Oct 2026, part of what looked "indecisive")
        if c.airShot and sameObj(c.target, c.airShot.obj) then engaged = false end
        -- (nor a drone: they follow the plane anyway and are taken in passing, by air shots and
        -- the gun, while the lanes and the moves go on; 20 Oct 2026, with a drone counted as an
        -- engagement the bot never weighed a move from minute 10.4 to the end of a phase and
        -- fought the swarm at about 700 points a minute, a 3,050-point ground group 7 km away)
        if killKind(c.target) == "agile" then engaged = false end
    end
    -- Fighters first (the owner, 19 Oct 2026: "neutralize the biggest threats (fighters, then
    -- SAMs, attack helicopters, finally AA guns)"): a plane or drone chasing this one within 5 km
    -- is fought before anything else (that evening four F-16s fired a missile every 5-10 s at a
    -- plane busy with ground targets, and two hits took 80 health)
    local hunter, hunterD = nil, 50000
    for _, tr in pairs(Aware.tracks) do
        if tr.kind == "plane" and tr.onMe and tr.p and alive(tr.obj) and gameKind(tr.obj) ~= "large" then
            local hdx = math.sqrt((tr.p[1] - loc.X) ^ 2 + (tr.p[2] - loc.Y) ^ 2 + (tr.p[3] - loc.Z) ^ 2)
            if hdx < hunterD then hunter, hunterD = tr.obj, hdx end
        end
    end
    if hunter and not sameObj(hunter, c.hunter) and t - (c.hunterLogAt or -100) > 5 then
        c.hunterLogAt = t
        event("hunter", { enemy = objName(hunter), dist_m = hunterD / 10 })
    end
    -- (19 Oct 2026, logged and not obeyed: forcing the fight onto every fighter chasing the plane,
    -- the seventh full phase spent four minutes in a turning fight with four F-16s for 750
    -- points; the bot then still fired a quarter of its missiles unguided and took no notice of
    -- terrain between it and the target.)
    -- The furball (20 Oct 2026, the owner watching area C: "it should be selecting a target like
    -- an enemy drone or F-16 or other fighter and aggressively committing ... prioritize kills,
    -- especially against aircraft already dogfighting it"): a plane or drone close by that is
    -- after this one, dogfighting it (one that fired a missile at it in the last 15 s from within
    -- 2.5 km) becomes the target and stays the target for at least 10 s, or until it dies or gets
    -- beyond 5 km; the nearest such one is taken. (Tried first with any plane tracking this one
    -- within 3 km: in three campaign attempts of 20 Oct 2026 the commitments to fighters and
    -- drones that were only tracking it cost area C's ground passes, 3,900 points there against
    -- 6,850 without, and 45 standard missiles came home.)
    local shot = {}
    if Aware.missileLog then
        for i = #Aware.missileLog, 1, -1 do
            local m = Aware.missileLog[i]
            if t - (m.born or 0) > 15 then break end
            if m.ownerName then shot[m.ownerName] = (shot[m.ownerName] or 0) + 1 end
        end
    end
    local fb, fbD = nil, math.huge
    for _, tr in pairs(Aware.tracks) do
        -- (not the drones: they fire too, and in one attempt 20 commitments to a swarm of them
        -- held the plane four minutes short of the area it was moving to, 20 Oct 2026; the air
        -- shots in passing and the lanes still take them)
        -- (tried and taken out, 20 Oct 2026: one sitting on the plane, two missiles or more in 15 s
        -- from within 1.5 km, as a furball target at any angle. Two drones 200-700 m behind had
        -- fired every few seconds, a missile always inbound, and the plane scored 400 points in two
        -- minutes of breaks; but in the next attempt all six such commitments to drones were
        -- dropped after 8 s without a shot, about 50 s lost)
        local kF = tr.kind == "plane" and tr.p and alive(tr.obj) and gameKind(tr.obj)
        if kF and kF ~= "large" and kF ~= "agile" then
            local d = math.sqrt((tr.p[1] - loc.X) ^ 2 + (tr.p[2] - loc.Y) ^ 2 + (tr.p[3] - loc.Z) ^ 2)
            local nm = objName(tr.obj)
            -- (in front only, within 60 degrees of the nose: in a timed score phase a quick kill is
            -- worth it, a turning fight is not; with any attacker, the fights with area C's
            -- fighters cost 12-20 s of break turns a minute and its ground passes)
            local offF = d > 1 and math.deg(math.acos(clamp(((tr.p[1] - loc.X) * F[1] + (tr.p[2] - loc.Y) * F[2] + (tr.p[3] - loc.Z) * F[3]) / d, -1, 1))) or 180
            if shot[nm] and d < 25000 and offF < 60 and d < fbD and not (c.skip[nm] and t < c.skip[nm]) then
                fb, fbD = tr.obj, d
            end
        end
    end
    local cur = c.furball
    if cur and (not alive(cur.obj) or t > cur.untilT) then cur = nil end
    -- ...but not a chase that gets nowhere: 8 s without a missile fired at it or a gun hit on
    -- it, and it is left alone for 30 s (20 Oct 2026: chases of drones over Mission 06's third
    -- area ran 30-60 s for nothing while the ground there paid 1,000 points a minute)
    if cur then
        local fired = firedAt[cur.name] and firedAt[cur.name] > cur.t0
        if fired or (c.lastGunHitName == cur.name and (c.lastGunHitAt or -100) > cur.t0) then cur.progressAt = t end
        if t - (cur.progressAt or cur.t0) > 8 then
            c.skip[cur.name] = t + 30
            event("furball_dropped", { target = cur.name, after_s = t - cur.t0 })
            cur = nil
        end
    end
    if cur then
        local cl = locOf(cur.obj)
        if not cl or (cl.X - loc.X) ^ 2 + (cl.Y - loc.Y) ^ 2 + (cl.Z - loc.Z) ^ 2 > 50000 ^ 2 then cur = nil end
    end
    if not cur and fb then
        cur = { obj = fb, name = objName(fb), untilT = t + 10, t0 = t }
        event("furball", { target = cur.name, dist_m = fbD / 10, target_kind = gameKind(fb) })
    elseif cur and fb and sameObj(fb, cur.obj) then
        cur.untilT = math.max(cur.untilT, t + 3)      -- still after us: keep at it
    end
    c.furball = cur
    c.hunter = cur and cur.obj or nil
    if cur then engaged = true end
    -- and a switch either way has to hold: on only when the lanes beat the best air target by
    -- 10%, off only when it beats them by 60%, and not again within 4 s
    local on
    if engaged then
        on = false
    elseif c.laneOn then
        on = plan ~= nil and plan.value > 1 and not (airRate > c.laneRateS * 1.6 and t - (c.laneSwitchAt or -100) > 4)
    else
        on = plan ~= nil and plan.value > 1 and c.laneRateS >= airRate * 1.1 and t - (c.laneSwitchAt or -100) > 4
    end
    -- Where next: a group elsewhere worth clearly more per second (with the flight there) than
    -- what is left here and than the best air target: fly there at full throttle; kept for at
    -- least 10 s once chosen; the lanes take over within 6 km of it
    if t - (c.clusterAt or -100) > 2 then
        c.clusterAt = t
        c.bestGroup, c.farGroup = bestCluster(c, loc)
    end
    local bg = c.bestGroup
    local go = false
    if bg and not engaged then
        local gd = math.sqrt((bg.x - loc.X) ^ 2 + (bg.y - loc.Y) ^ 2)
        if gd > 60000 then
            -- (the smoothed lane rate here, also while the lanes are off for a moment: a switch
            -- to a bomber must not send the plane 18 km away from a group still paying)
            local here = c.laneRateS or 0
            -- (the plan audit's delivered/promised ratio, 0.4-0.5, is worked out for the record;
            -- scaling this rate by it, tried on 20 Oct 2026, made every small group 6 km away
            -- worth a move and the plane hopped between them; not applied)
            if t - (c.auditRatioAt or -100) > 10 then
                c.auditRatioAt = t
                local ex, got = 0, 0
                local H = Lanes.P.horizon
                for _, a in ipairs(c.audits or {}) do
                    if t - a.t >= H and t - a.t < 180 then
                        ex = ex + a.shots
                        for _, lt in ipairs(c.launchTimes or {}) do if lt >= a.t and lt < a.t + H then got = got + 1 end end
                    end
                end
                if ex >= 10 then c.auditRatio = clamp(got / ex, 0.25, 1) end
            end
            -- ...but no more than this place really pays: the points scored in the last 90 s
            -- (19 Oct 2026, the first full phase with the lanes: four minutes in an anti-aircraft
            -- site scoring 4 points a second while the plans promised 10-25, and 6,650 points in
            -- another area never visited). Counted once the lanes have run here 60 s.
            -- (the last 60 s at 1.15 times since the sixth full phase, which stayed 10.7 minutes
            -- in one area at 765 points a minute and never reached the third: at 1.5 times the
            -- last 90 s the area still looked as good as the next)
            -- (20 Oct 2026: from 45 s of lanes here on, over the time here up to 60 s: the plans
            -- own rate is twice as optimistic as what they deliver, and with the full minute asked
            -- for, the sixth full phase of that evening stayed three minutes in a picked-over area)
            local since = c.laneSince and (t - c.laneSince) or 0
            if since > 45 then
                local win = math.min(60, since)
                local got = 0
                for i = #pointsLog, 1, -1 do
                    if t - pointsLog[i][1] > win then break end
                    got = got + pointsLog[i][2]
                end
                here = math.min(here, got / win * 1.15)
            end
            -- (once on the way, it takes a place clearly better than the group ahead to stop:
            -- 20 Oct 2026, the fifth full phase turned back three times for a few leftover
            -- targets on the 23 km move between two areas and lost about a minute and a half)
            -- (the same move taken up again within 30 s, after a fight with a plane on the way,
            -- counts as on the way too; and to start a move the group ahead need only pay more
            -- than this place, not 20% more: with the fresh-group estimate the margin is no longer
            -- needed, and on 20 Oct 2026 it kept the plane in a picked-over area to minute 8)
            local mm = c.moveMem
            local resumed = mm and t - mm.t < 30 and (bg.x - mm.x) ^ 2 + (bg.y - mm.y) ^ 2 < 100000 ^ 2
            -- (with no margin the first decision of a fight went for a ground group 20 km away
            -- instead of the bombers close by, 20 Oct 2026; the margin stays, the plans' rate is
            -- made honest instead, above)
            local factor = (c.transitTo or resumed) and 0.67 or 1.2
            go = (c.transitTo and t - (c.transitSince or t) < 10) or bg.rate > math.max(here, airRate) * factor
            -- the decision every 15 s, for the report (general data: why a place was kept or left)
            if t - (c.areaViewAt or -100) > 15 then
                c.areaViewAt = t
                event("area_view", { group_points = bg.points, group_n = bg.n, group_km = gd / 10000, group_rate = bg.rate, here_rate = here,
                                     planned_rate = c.laneRateS or 0, audit = c.auditRatio or -1, air_rate = airRate, factor = factor, go = go,
                                     lanes_s = c.laneSince and (t - c.laneSince) or -1 })
            end
        end
    elseif bg and engaged and t - (c.areaViewAt or -100) > 15 then
        c.areaViewAt = t
        event("area_view", { group_points = bg.points, group_n = bg.n, engaged = true })
    end
    -- The leaving rule (the marginal value theorem of foraging: leave a patch once it pays less
    -- than the whole has paid on average; 20 Oct 2026): after 90 s of lanes in a place and two
    -- minutes of fight, if the last minute here paid under half this fight's average points a
    -- second, go to the best substantial group elsewhere (bestCluster's second answer) and keep
    -- going there until arrived, through a short air fight on the way. In five attempts that
    -- evening Mission 06's second area paid 2,000-2,500 points a minute for two minutes and
    -- 350-1,100 for the next four or five, while the third, once reached, paid about 1,250; the
    -- "best group" rule never weighed a move because the second area's own leftovers won it.
    c.fightT0 = c.fightT0 or t
    local mv = c.mvtMove
    if not engaged and c.farGroup and not (c.transitTo and c.transitTo.mvt) then
        local leave = mv and t - mv.t < 60 and mv.group and (mv.group.x - loc.X) ^ 2 + (mv.group.y - loc.Y) ^ 2 > 60000 ^ 2
        local since = c.laneSince and (t - c.laneSince) or 0
        local fightS = t - c.fightT0
        -- (90 s in the place at least, under half the average, and never back toward a place left
        -- in the last 3 minutes: with 45 s, 60% and no such memory the first try left the third
        -- area 100 s after arriving, the first minute anywhere paying little, and flew back 25 km)
        local lf = c.leftFrom
        local backTo = lf and t - lf.t < 180 and (c.farGroup.x - lf.x) ^ 2 + (c.farGroup.y - lf.y) ^ 2 < 100000 ^ 2
        if not leave and not go and since > 90 and fightS > 120 and not backTo then
            local win = math.min(60, since)
            local got, total = 0, 0
            for i = #pointsLog, 1, -1 do
                local pt = pointsLog[i]
                if pt[1] < c.fightT0 then break end
                total = total + pt[2]
                if t - pt[1] <= win then got = got + pt[2] end
            end
            local avg = total / fightS
            -- (not when the phase ends before the flight there and a minute and a half of work)
            local ms = mission()
            local left = ms and call(ms, "GetMissionPhaseTimeLeftInSeconds_S")
            local timeOk = not left or left < 0 or left > c.farGroup.dist / 4000 + 90
            -- (nor while an air target here pays better than the group there: on 20 Oct 2026 the
            -- rule left the first area at 2.3 minutes during a fight with its F-16s, its three
            -- bombers, 3,600 points, still flying)
            -- (and with the margin a move by the best-group rule asks, 20%: at 5 am on 20 Oct
            -- 2026 it left at 2.75 minutes with a bomber worth 18.1 points a second against
            -- a group worth 18.2)
            local airHere = (airRate or 0) * 1.2 >= c.farGroup.rate
            if got / win < 0.5 * avg and timeOk and not airHere then
                leave = true
                event("leave_patch", { here_rate = got / win, fight_rate = avg, to_points = c.farGroup.points, to_n = c.farGroup.n,
                                       to_km = c.farGroup.dist / 10000 })
                mv = { group = c.farGroup, t = t }
                c.leftFrom = { x = loc.X, y = loc.Y, t = t }
            end
        end
        if leave then
            bg, go = mv.group, true
            bg.mvt = true
            c.mvtMove = { group = bg, t = mv.t }
        end
    end
    -- a move by the leaving rule goes on until it has arrived
    if c.transitTo and c.transitTo.mvt and not engaged then
        local tt = c.transitTo
        if (tt.x - loc.X) ^ 2 + (tt.y - loc.Y) ^ 2 > 60000 ^ 2 then bg, go = tt, true end
    end
    -- The return line (the owner, 20 Oct 2026: "were you aware of the return line ... that can
    -- refill ammo and flares?"). Flying over a mission's return line lands the plane; a supply
    -- menu refills the missiles, the special weapon and the flares (and lets the special weapon
    -- be changed), then it takes off again from the line. The landing, the menu and the take-off
    -- stop the phase clock (Mission 06: 758.9 s left before and after), so a resupply costs only
    -- the flight. Going when, at this fight's own launch rate, the standard missiles would run
    -- out more than that detour's time before the phase ends (or health is under 40%), with two
    -- minutes left after the detour, and the missiles under 70% of the full load. The detour:
    -- here to the line and on to where the plane goes next, less the straight way there.
    if t - (c.lineAt or -100) > 10 then
        c.lineAt = t
        c.line = (Gim and Gim.returnLine) and Gim.returnLine() or nil
    end
    if c.line and not c.resupply and not engaged and c.ammo and type(c.ammo.m) == "number" and c.ammo.m >= 0 and c.econSince
        and t - (c.resupplyAt or -100) > 60 then
        local ms = mission()
        local T = ms and call(ms, "GetMissionPhaseTimeLeftInSeconds_S")
        local span = t - c.econSince
        if T and T > 0 and T < 7200 and span > 60 then
            local n = 0
            for _, lt in ipairs(c.launchTimes or {}) do if lt >= c.econSince then n = n + 1 end end
            local rate = n / span
            local Ln = c.line
            local vT = 5000          -- units/s: the transits' speed, about 1,800 km/h
            local dl = math.sqrt((Ln.x - loc.X) ^ 2 + (Ln.y - loc.Y) ^ 2)
            local nx = c.transitTo or c.farGroup or c.bestGroup
            local X
            if nx then
                X = (dl + math.sqrt((nx.x - Ln.x) ^ 2 + (nx.y - Ln.y) ^ 2) - math.sqrt((nx.x - loc.X) ^ 2 + (nx.y - loc.Y) ^ 2)) / vT + 20
            else
                X = 2 * dl / vT + 20
            end
            local runOut = c.ammo.m / math.max(rate, 1e-3)
            local hp = ap.lastHealth or 120
            local hpMax = call(playerPlane(), "GetMaxHealth") or 120
            local hurt = hp < 0.4 * hpMax
            local cap = c.ammoCap or c.ammo.m
            -- ...and the special weapon the same way, while aircraft worth 1,500 points or more
            -- are flying (an attempt of 20 Oct 2026 spent its last LAAM at 13.5 minutes, with
            -- Mission 06's third area's fighters and drones, about 7,500 points, still about)
            local spOut = false
            local sL, s0 = c.ammo.s, c.spStart
            if type(sL) == "number" and sL >= 0 and type(s0) == "number" and s0 > 0 and sL < s0 * 0.5 then
                local spRate = (s0 - sL) / span
                local airPts = 0
                for _, tr in pairs(Aware.tracks) do
                    if tr.kind == "plane" and alive(tr.obj) then airPts = airPts + (objInfo(tr.obj).bounty or 0) end
                end
                spOut = airPts >= 1500 and T - X > sL / math.max(spRate, 1e-3) + 30
            end
            if (T - X > runOut + 30 or hurt or spOut) and T > X + 120 and (c.ammo.m < cap * 0.7 or hurt or spOut) then
                c.resupply = { x = Ln.x, y = Ln.y, z = Ln.z, t0 = t, name = Ln.name }
                c.resupplyAt = t
                event("resupply", { line = Ln.name, dist_m = dl / 10, detour_s = X, phase_left_s = T, missiles = c.ammo.m, special = c.ammo.s or -1,
                                    runs_out_s = runOut, health = hp,
                                    why = hurt and "health" or ((T - X > runOut + 30) and "missiles" or "special weapon") })
                log(string.format("  resupply: to the return line %.1f km away (detour %.0f s; %d missiles last %.0f s of the %.0f s left; health %.0f)",
                    dl / 10000, X, c.ammo.m, runOut, T, hp))
            end
        end
    end
    if c.resupply then go, on, c.transitTo, c.mvtMove = false, false, nil, nil end
    if go then
        c.moveMem = { x = bg.x, y = bg.y, t = t }
        if not c.transitTo then
            c.transitSince = t
            event("next_group", { targets = bg.n, points = bg.points, dist_m = bg.dist / 10, rate = bg.rate, here_rate = c.laneRateS,
                                  air_rate = airRate, sec_per_kill = bg.secPerKill })
        end
        c.transitTo = bg
        on = false
    else
        -- arrived (within 6 km of the group moved to): that place is the lanes' for a minute
        local tt = c.transitTo
        if tt and (tt.x - loc.X) ^ 2 + (tt.y - loc.Y) ^ 2 < 65000 ^ 2 then
            c.arrived = { x = tt.x, y = tt.y, t = t }
            c.mvtMove = nil
            event("arrived", { points = tt.points, targets = tt.n })
        end
        c.transitTo = nil
    end
    if on and not c.laneSince then c.laneSince = t end
    if c.transitTo then c.laneSince = nil end
    if on ~= (c.laneOn or false) then
        c.laneSwitchAt = t
        event("lanes", { on = on, targets = #tg, value = plan and plan.value or 0, lane_rate = c.laneRateS,
                         air = airPick and objName(airPick) or "-", air_rate = airRate, engaged = engaged })
    end
    c.laneOn = on
    c.lanePlan = on and plan or nil
    -- a vertical attack begins when the lanes fly the plan that has one (the plans are also
    -- made while the lanes are off, to weigh them against the air target)
    if on and plan and plan.dive and not c.dive and tg[plan.dive] then
        local q = tg[plan.dive]
        c.dive = { name = q.name, obj = q.obj, over = plan.over, phase = plan.over and 0 or 1, t0 = t,
                   untilT = t + Lanes.P.horizon + 4, minH = math.huge, psi0 = math.atan(F[2], F[1]) }
        event("dive", { target = q.name, over = plan.over or false, above_m = (loc.Z - q[3]) / 10,
                        dist_m = math.sqrt((q[1] - loc.X) ^ 2 + (q[2] - loc.Y) ^ 2) / 10,
                        agl_m = ap.agl or -1, shots = plan.shots, first_s = plan.first or -1 })
    end
    -- (a vertical attack ends with the lanes: an air target or a move took over)
    if not on and c.dive then
        event("dive_end", { target = c.dive.name, why = "lanes off", fired = c.dive.fired or false, after_s = t - c.dive.t0,
                            lowest_m = c.dive.minH < 1e9 and c.dive.minH or -1, over = c.dive.over or false })
        c.dive, ap.vertical = nil, false
    end
    c.laneRate = rate
    -- how far the nearest lane target is (m): the lanes fly at full throttle until it is within
    -- 5 km (the owner, 19 Oct 2026: "more willing to accelerate towards a large chunk of high
    -- value enemies"), then at the cornering speed
    local nearest = math.huge
    for _, q in ipairs(tg) do
        local d2 = (q[1] - loc.X) ^ 2 + (q[2] - loc.Y) ^ 2 + (q[3] - loc.Z) ^ 2
        if d2 < nearest then nearest = d2 end
    end
    c.laneNearest = math.sqrt(nearest) / 10
    -- the plan audit (general data): every 3 s of lanes, the shots the plan expects in its
    -- look-ahead, compared at the end with the launches that really came in that time
    if on and plan and t - (c.auditAt or -100) >= 3 then
        c.auditAt = t
        c.audits = c.audits or {}
        c.audits[#c.audits + 1] = { t = t, shots = plan.shots or 0 }
    end
end
-- the plan in words, for the log
local function laneText(c, t, F)
    local pl = c.lanePlan
    if not pl then return "no plan" end
    local d = math.deg(Lanes.wrapPi(Lanes.heading(pl, t) - math.atan(F[2], F[1])))
    local how
    if c.dive then
        how = string.format("vertical attack on %s (%s)", tostring(c.dive.name),
            ({ [0] = "up and over", [1] = "nose on it", [2] = "pulling out" })[c.dive.phase] or "?")
    elseif pl.switchAt and t < pl.switchAt then
        how = string.format("run out %.1f s more, then turn back %s", pl.switchAt - t, math.deg(Lanes.wrapPi(pl.psi2 - pl.psi1)) > 0 and "right" or "left")
    elseif math.abs(d) < 5 then
        how = "straight on"
    else
        how = string.format("turn %.0f deg %s", math.abs(d), d > 0 and "right" or "left")
    end
    return string.format("plan: %s, %d shots worth %.0f in %.0f s%s; %+.0f m from the pass height", how, pl.shots or 0, pl.value or 0, Lanes.P.horizon,
        pl.kept and " (kept)" or "", c.laneZNow and c.laneZPass and (c.laneZNow - c.laneZPass) / 10 or 0)
end
-- Out of a dive the shorter way: the level direction the plane reaches by pulling alone (toward
-- its canopy) when that is within 110 degrees of pull, otherwise level along the way it is
-- going (a roll first). F, U: the nose and the canopy. (20 Oct 2026: the first vertical attacks'
-- pull-out always aimed level ahead; from a dive entered inverted, 81 degrees nose down with the
-- canopy facing back, that meant a 140-degree roll before the pull, and the plane went into a
-- hillside in area C. A player pulls on through, the end of a split-S.)
local function pullOutAim(F, U)
    if F[3] >= -0.05 then return unit({ F[1], F[2], 0.05 }) end
    local a = math.atan(-F[3], U[3])
    if a <= math.rad(110) then
        local ca, sa = math.cos(a), math.sin(a)
        local dx, dy = F[1] * ca + U[1] * sa, F[2] * ca + U[2] * sa
        if dx * dx + dy * dy > 0.01 then return unit({ dx, dy, 0.05 }) end
    end
    return unit({ F[1], F[2], 0.05 })
end
-- a vertical attack ends: back to the plans
local function diveEnd(c, t, why)
    local dv = c.dive
    if not dv then return end
    event("dive_end", { target = dv.name, why = why, fired = dv.fired or false, after_s = t - dv.t0, lowest_m = dv.minH < 1e9 and dv.minH or -1,
                        over = dv.over or false })
    c.dive, c.lanePlan, ap.vertical = nil, nil, false
end
-- The vertical attack being flown (Lanes.simulateDive's phases, live): up and over first if
-- planned, then the nose on the target until its missile is away or the height left is what
-- the pull-out needs, then the pull-out to level flight, the shorter way round.
local function diveAim(c, loc, t, alt)
    local dv = c.dive
    local V = ap.myV or { 0, 0, 0 }
    local vl = math.sqrt(V[1] ^ 2 + V[2] ^ 2 + V[3] ^ 2)
    if vl < 100 then diveEnd(c, t, "no speed") return nil end
    local f = { V[1] / vl, V[2] / vl, V[3] / vl }
    local height = math.min(ap.agl or alt, alt)
    local live = dv.obj and alive(dv.obj)
    local tl = live and locOf(dv.obj)
    -- (and over the target: the lower of the two heights counts)
    if tl then height = math.min(height, (loc.Z - tl.Z) / 10) end
    -- ...and over the ground the pull-out will cross: traced along its way out, as far as the
    -- arc reaches and 300 m on, five times a second (20 Oct 2026: the first crash, into a hill
    -- rising 280 m above the line of the pull-out in area C)
    if ap.F and ap.U and Aware and Aware.groundAt and (ap.F[3] < -0.2) then
        if t - (dv.groundAt or -100) > 0.2 then
            dv.groundAt = t
            local d = pullOutAim(ap.F, ap.U)
            local hl = math.sqrt(d[1] ^ 2 + d[2] ^ 2)
            local reach = vl / math.max(planeTurn.est * Lanes.P.dive.pullShare, 0.05) * math.max(-ap.F[3], 0.3) + 3000
            local top = nil
            for _, s in ipairs({ 0.33, 0.66, 1.0 }) do
                local gz = Aware.groundAt(playerPlane(), loc.X + d[1] / hl * reach * s, loc.Y + d[2] / hl * reach * s, loc.Z + 5000)
                if gz and (not top or gz > top) then top = gz end
            end
            dv.aheadTop = top
        end
        if dv.aheadTop then height = math.min(height, (loc.Z - dv.aheadTop) / 10) end
    end
    dv.minH = math.min(dv.minH, height)
    if dv.phase < 2 then
        local fired = firedAt[dv.name] and firedAt[dv.name] > dv.t0
        if fired then dv.fired = true end
        if not tl or fired or (Aware and Aware.inFlight(dv.name) > 0) or t > dv.untilT then dv.phase = 2 end
    end
    if dv.phase == 0 then
        local dx, dy, dz = tl.X - loc.X, tl.Y - loc.Y, tl.Z + 30 - loc.Z
        local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
        local hl = math.max(math.sqrt(dx * dx + dy * dy), 1)
        if f[3] > 0.9 or (f[1] * dx + f[2] * dy + f[3] * dz) > -0.2 * dl then
            dv.phase = 1
        else
            return unit({ dx / hl * 0.4, dy / hl * 0.4, 1 })
        end
    end
    if dv.phase == 1 then
        local need = Lanes.pullNeed(vl, -f[3], planeTurn.est * Lanes.P.dive.pullShare) / 10 * Lanes.P.dive.margin
        if f[3] < 0 and height <= need then
            dv.phase = 2
        else
            return unit({ tl.X - loc.X, tl.Y - loc.Y, tl.Z + 30 - loc.Z })
        end
    end
    -- the pull-out: level, the shorter way
    if f[3] > -0.05 then diveEnd(c, t, dv.fired and "shot" or "pulled out") return nil end
    return pullOutAim(ap.F or f, ap.U or { 0, 0, 1 })
end
local function laneAim(c, loc, t, alt)
    if c.dive then
        local a = diveAim(c, loc, t, alt)
        if a then ap.vertical = true; return a end
    end
    ap.vertical = false
    if not c.lanePlan then
        -- (a dive just ended: level along the way the plane is going until the next plan)
        local V = ap.myV or { 1, 0, 0 }
        return unit({ V[1], V[2], 0 })
    end
    local h = Lanes.heading(c.lanePlan, t)
    local above = ap.agl or alt
    -- (down by the height still to lose: about 19 degrees from 1 km above the pass height,
    -- 6 near it, where a steep dive makes the ground check 4 s ahead call a recovery; with a
    -- fixed 11 degrees the lanes of 19 Oct 2026's sixth test were flown at a median 600 m and a
    -- third of the time above 900 m, where targets inside 1.4 km sit below the lock cone)
    local z = clamp((c.laneZPass - loc.Z) / 10000, -0.35, 0.3)
    if above < 150 then z = math.max(z, 0.08) end
    return unit({ math.cos(h), math.sin(h), z })
end
-- every frame in lanes: keep the selected target while it stays inside the cone and range,
-- otherwise select the one nearest the nose inside the cone (the chain's next link)
local function lanePick(c, loc, F, t)
    local tg, wp = c.laneTg, c.laneWp
    if not (tg and wp) then return end
    -- a missile just fired: the selection stays until it has left the rail (see the firing)
    if c.chainAt and t < c.chainAt then return end
    local keep = false
    if c.pref and c.lanePickName and alive(c.pref) and objName(c.pref) == c.lanePickName
        and not (c.skip[c.lanePickName] and t < c.skip[c.lanePickName]) then
        local pl = locOf(c.pref)
        if pl then
            local dx, dy, dz = pl.X - loc.X, pl.Y - loc.Y, pl.Z - loc.Z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            keep = d <= wp.range and (dx * F[1] + dy * F[2] + dz * F[3]) >= math.cos(wp.cone) * d
        end
    end
    if keep then return end
    local i, ang = Lanes.conePick(loc.X, loc.Y, loc.Z, F[1], F[2], F[3], wp, tg, function(k)
        local n = tg[k].name
        return (c.skip[n] and t < c.skip[n]) or not alive(tg[k].obj)
    end)
    c.laneLocked = false
    if i then
        local o = tg[i].obj
        if t - (c.lastLaunchAt or -100) < 1.5 then
            c.chains = (c.chains or 0) + 1
            event("chain", { from = c.lastLaunchName or "-", to = tg[i].name, gap_s = t - c.lastLaunchAt, ang_deg = math.deg(ang) })
        end
        c.pref, c.prefSince, c.prefLockedAt, c.prefPointed, c.prefAt, c.prefW = o, t, nil, 0, t, 1
        c.lanePickName, c.pickAt, c.pickAng0 = tg[i].name, t, ang
    else
        c.lanePickName = nil
        if c.pref and not airborne(c.pref) then c.pref = nil end
    end
end

local function combatStep(p, loc, rot, F, R, alt, dt)
    local c = ap.combat
    local t = now()
    local keys = {}
    c.gunFiring, c.gunPass = false, nil
    -- kills in this order: the tally counts both the kills seen when the selection moves on and
    -- those the game reports dying from a missile fired earlier (most of them, with the lanes)
    c.killBase = c.killBase or killTally.n
    c.kills = killTally.n - c.killBase
    c.rollNow = math.rad(wrap180(rot.Roll))
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
    -- score phases: the HUD's score every 30 s, for the report's points-per-minute line
    if ap.scoreMode and t - (c.scoreTickAt or -100) > 30 then
        c.scoreTickAt = t
        local m = mission()
        local goal, hs = hudScoreGoal()
        event("score_tick", { hud_score = hs or "-", goal = goal or -1, score = m and call(m, "GetMissionScore_S") or -1,
                              left_s = m and call(m, "GetMissionPhaseTimeLeftInSeconds_S") or -1, kills = c.kills, lanes = c.laneOn or false })
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
    local holdFor = (ap.scoreMode and 4) or 6          -- score phases: sooner (a lock needs 1-2 s of it)
    -- ...and a close drone the plane is opening out from to come back at is kept (20 Oct 2026,
    -- Mission 07: opened out from a UAV 490 m away among the recon team, re-judged it from
    -- behind and went for one 9 km off; the near one shot down a recon plane and the phase failed)
    local openingOut = curOk and c.heliOut and c.heliOut[objName(c.pref)]
    -- Score phases with the lane planner: the scan (lane candidates, the best target in the air,
    -- allies, mission targets) runs every second on its own clock, the plan twice a second, and
    -- while the lanes are flown the target is the cone pick (lanePick), not the scan's choice.
    local lanesHere = ap.scoreMode and Lanes and Aware and Aware.weapons and ap.lanes ~= false and not Gun.test
    if lanesHere then
        c.incoming = c.incoming or {}
        if t - (c.laneScanAt or -100) > 1.0 then
            c.laneScanAt = t
            local pref, prefDist, prefScore, prefW = nearestEnemy(loc, c.skip, F, (not c.laneOn) and curOk and c.pref or nil, call(p, "GetSpeedKmph"))
            c.scan = { pref = pref, dist = prefDist, score = prefScore, w = prefW, at = t }
        end
        lanePlan(c, loc, F, t)
    elseif c.laneOn or c.transitTo then
        c.laneOn, c.lanePlan, c.transitTo = false, nil, nil
    end
    -- An air shot in passing (20 Oct 2026; the gap analysis's "survive the opening": four
    -- F-16s fired at the plane every 5-10 s while it worked on the ground, and the LAAM came
    -- home half unused): while the lanes are flown, an enemy plane inside an air-only special
    -- weapon's lock cone and range is selected for a moment and gets one missile from it (the
    -- weapon choice below arms the special for anything in the air in a score phase), then the
    -- lanes go on. At most 4 s a try; not at agile drones; not while one is in the air at it.
    if c.airShot and (t > c.airShot.untilT or not alive(c.airShot.obj)) then
        event("air_shot_end", { target = c.airShot.name, fired = c.airShot.fired or false })
        -- two tries in a row at one kind of target without a missile away: no more air shots at
        -- that kind for 45 s (20 Oct 2026, the owner watching a fight over Mission 06's third
        -- area: the bot looked "indecisive"; in that minute three air shots at drones fired
        -- nothing, each one a weapon switch and back)
        local kA = c.airShot.kind or "?"
        c.airFail = c.airFail or {}
        if c.airShot.fired then c.airFail[kA] = 0 else c.airFail[kA] = (c.airFail[kA] or 0) + 1 end
        if c.airFail[kA] >= 2 then
            c.airBan = c.airBan or {}
            c.airBan[kA], c.airFail[kA] = t + 45, 0
        end
        if c.pref and sameObj(c.pref, c.airShot.obj) then c.pref = nil end
        c.airShot = nil
    end
    if c.laneOn and not c.airShot and t - (c.airShotAt or -100) > 1.0 then
        c.airShotAt = t
        local sp = Aware.weapons.special
        local leftSp = sp and sp.targets == "air only" and sp.LockonRange and call(weapons(p), "GetSpecialWeaponCount") or 0
        if leftSp > 0 then
            local best, bestOff, bestD = nil, (sp.LockonAngle or 25) - 4, 0
            -- (a plane that has fired at this one in the last 30 s may be taken from up to 50
            -- degrees off, the nose flicking onto it, and comes first: most missile hits of 20
            -- Oct 2026's attempts came from the fighters of Mission 06's third area, an F-16
            -- among them firing from 360 m)
            local shotAt = {}
            for i = #(Aware.missileLog or {}), 1, -1 do
                local m = Aware.missileLog[i]
                if t - (m.born or 0) > 30 then break end
                if m.ownerName then shotAt[m.ownerName] = true end
            end
            local bestScore = math.huge
            for _, tr in pairs(Aware.tracks) do
                if tr.kind == "plane" and tr.p and alive(tr.obj) and (objInfo(tr.obj).bounty or 0) > 0
                    and not (c.airBan and c.airBan[gameKind(tr.obj)] and t < c.airBan[gameKind(tr.obj)]) then
                    local dx, dy, dz = tr.p[1] - loc.X, tr.p[2] - loc.Y, tr.p[3] - loc.Z
                    local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
                    -- (agile ones within 6 km only, as in the weapon choice below)
                    local farA = sp.LockonRange * 0.9
                    if gameKind(tr.obj) == "agile" then farA = math.min(farA, 60000) end
                    if dl < farA and dl > 12000 then
                        local off = math.deg(math.acos(clamp((dx * F[1] + dy * F[2] + dz * F[3]) / dl, -1, 1)))
                        local nm = objName(tr.obj)
                        local cap = Aware.rangeCap and Aware.rangeCap(sp.class, gameKind(tr.obj))
                        local floorA = Aware.rangeFloor and Aware.rangeFloor(sp.class, gameKind(tr.obj))
                        local inside = not (cap and dl / 10 > cap) and not (floorA and dl / 10 < floorA + 100)
                        local thr = shotAt[nm] and gameKind(tr.obj) ~= "agile"
                        -- (and any of them when the special weapon would otherwise come home
                        -- unused: c.spSurplus, the missile economy above)
                        local lim = (thr or c.spSurplus) and 50 or ((sp.LockonAngle or 25) - 4)
                        local score = off - (thr and 40 or 0)
                        if off < lim and score < bestScore and Aware.inFlight(nm) == 0 and inside and not (c.skip[nm] and t < c.skip[nm]) then
                            best, bestOff, bestD, bestScore = tr.obj, off, dl, score
                        end
                    end
                end
            end
            if best then
                c.airShot = { obj = best, name = objName(best), untilT = t + 4, kind = gameKind(best) }
                event("air_shot", { target = c.airShot.name, dist_m = bestD / 10, off_deg = bestOff })
            end
        end
    end
    if c.airShot then
        c.pref, c.lanePickName = c.airShot.obj, nil
    elseif c.furball and alive(c.furball.obj) then
        -- the furball's target (lanePlan): taken at once and kept
        if not sameObj(c.pref, c.furball.obj) then
            c.prefSince, c.prefLockedAt, c.prefPointed = t, nil, 0
            event("priority", { target = c.furball.name, why = "furball: after us", weight = 3 })
        end
        c.pref, c.lanePickName, c.prefW, c.prefAt = c.furball.obj, nil, 3, t
    elseif c.laneOn then
        lanePick(c, loc, F, t)
    elseif t - (c.prefAt or -100) > 1 and not openingOut and not (curOk and not extending and t - (c.prefSince or -100) < holdFor) then
        c.prefAt = t
        local kmhNow = call(p, "GetSpeedKmph")
        local pref, prefDist, prefScore, prefW
        if lanesHere and c.scan and t - c.scan.at < 1.05 then
            pref, prefDist, prefScore, prefW = c.scan.pref, c.scan.dist, c.scan.score, c.scan.w
        else
            pref, prefDist, prefScore, prefW = nearestEnemy(loc, c.skip, F, curOk and c.pref or nil, kmhNow)
        end
        if lanesHere and c.hunter and alive(c.hunter) then
            local hl = locOf(c.hunter)
            pref, prefW = c.hunter, 3
            prefDist = hl and math.sqrt((hl.X - loc.X) ^ 2 + (hl.Y - loc.Y) ^ 2 + (hl.Z - loc.Z) ^ 2) / 10 or prefDist
        end
        if pref and not sameObj(pref, c.pref) then
            c.prefSince, c.prefLockedAt, c.prefPointed = t, nil, 0
            event("priority", { target = objName(pref), dist_m = prefDist, weight = prefW, score = prefScore })
        end
        c.pref, c.prefDist, c.prefW = pref, prefDist, prefW
        c.lanePickName = nil
    elseif curOk then
        local pl = locOf(c.pref)
        if pl then c.prefDist = math.sqrt((pl.X - loc.X) ^ 2 + (pl.Y - loc.Y) ^ 2 + (pl.Z - loc.Z) ^ 2) / 10 end
    end
    -- On a sweep's run in, the target is simply the one nearest the nose within 25 degrees and
    -- 0.9-1.9 km (the standard missile locks within 2.0 km and 32.5 degrees), picked again
    -- every 0.3 s: what a player takes on a pass. (Chosen by points as
    -- elsewhere, 19 Oct 06:54, the bot kept one SAM site well off its line for a minute of
    -- passes and its lock never built.)
    -- (the sweeps are only flown when the lane planner is not there)
    if not lanesHere and ap.scoreMode and c.sweepFix and c.sweepRun == "in" and scorePts and t - (c.sweepPickAt or -100) > 0.3 then
        c.sweepPickAt = t
        -- (within 40 degrees since 19 Oct 12:45: with 25, a quarter of a run's run-ins were spent
        -- on a target picked by points that sat more than 45 degrees off the nose)
        local best, bestOff = nil, 40
        -- (out to 95% of the standard missile's lock range as the game reports it: parts can
        -- lengthen it, 19 Oct 2026)
        local lr = (Aware and Aware.weapons and Aware.weapons.main and Aware.weapons.main.LockonRange) or 20000
        for _, q in ipairs(scorePts) do
            local dx, dy, dz = q[1] - loc.X, q[2] - loc.Y, q[3] - loc.Z
            local du = math.sqrt(dx * dx + dy * dy + dz * dz)
            if du > 9000 and du < lr * 0.95 then
                local off = math.deg(math.acos(clamp((dx * F[1] + dy * F[2] + dz * F[3]) / du, -1, 1)))
                if off < bestOff and alive(q[5]) then
                    local okN, n = pcall(objName, q[5])
                    if okN and not (c.skip[n] and t < c.skip[n]) then best, bestOff = q[5], off end
                end
            end
        end
        if best and not sameObj(best, c.pref) then
            c.pref, c.prefSince, c.prefLockedAt, c.prefPointed, c.prefAt = best, t, nil, 0, t
            c.prefW = c.prefW or 1
        end
    end
    -- the "guntest" order with a name: that object is the target, whatever the scan says
    if Gun.test and Gun.test.name then
        if not (c.gunTestObj and alive(c.gunTestObj)) and t - (c.gunTestFindAt or -100) > 2 then
            c.gunTestFindAt, c.gunTestObj = t, nil
            for _, o in ipairs(FindAllOf("GameObject") or {}) do
                if objName(o) == Gun.test.name and alive(o) then c.gunTestObj = o; break end
            end
            if not c.gunTestObj then log("guntest: no live object named " .. Gun.test.name) end
        end
        if c.gunTestObj and alive(c.gunTestObj) then c.pref = c.gunTestObj end
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
    -- A lock the game holds on another enemy on the ground, in reach and in sight, is taken: what
    -- a player does (20 Oct 2026, Mission 07: the game would not select a SAM site in a canyon,
    -- its lock-on mark 0, and its seeker locked the AA gun 600 m from it instead; the bot held
    -- fire through two dives at 1.4-2.4 km). Not in the lanes, which pick from the cone themselves.
    -- (only for a target the game would not select or lock, and at most once in 5 s: Mission 08's
    -- fuel trucks on split routes, 20 Oct 2026, the game's lock and the bot's choice took turns
    -- 143 times in 10 minutes and 7 of 22 trucks died)
    local prefStuck = c.pref and ((c.refused and c.refused[objName(c.pref)]) or not lockInfo(c.pref).lockable)
    if not lanesHere and not Gun.test and c.pref and tgt and ts and prefStuck and t - (c.takeLockAt or -100) > 5 then
        local lk = call(p, "GetLockedOnTarget")
        if lk and not sameObj(lk, c.pref) and alive(lk) and not airborne(lk) then
            local ll = locOf(lk)
            local du = ll and math.sqrt((ll.X - loc.X) ^ 2 + (ll.Y - loc.Y) ^ 2 + (ll.Z - loc.Z) ^ 2) / 10
            local short = du and Aware and Aware.losBlocked and Aware.losBlocked({ loc.X, loc.Y, loc.Z }, { ll.X, ll.Y, ll.Z }, 3)
            if du and du < 2200 and (short or 0) < 40 then
                c.takeLockAt = t
                event("take_lock", { target = objName(lk), instead_of = objName(c.pref), dist_m = du })
                c.pref, c.prefSince, c.prefLockedAt, c.prefPointed, c.prefAt = lk, t, t, 0, t
                pcall(function() ts.SelectedTarget = lk end)
                tgt = lk
            end
        end
    end
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
        if not c.prefLockedAt and (c.prefPointed or 0) > 8 and not Gun.test then
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
            killTally.n = killTally.n + 1
            local si = shotInfo[c.targetName] or {}
            pointsLog[#pointsLog + 1] = { t, si.bounty or 0 }
            if si.cls then learnAgile(si.cls, 0, 1) end
            event("kill", { target = c.targetName, callsign = c.targetCallsign, after_s = t - c.targetSince, missiles = c.shotsAtTarget,
                            class = si.kind or c.targetKind or "?", bounty = si.bounty or 0 })
            local kk = si.kind or c.targetKind
            if kk then killTally.kindKills[kk] = (killTally.kindKills[kk] or 0) + 1 end
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
        c.targetKind = ap.scoreMode and killKind(tgt) or nil
        local tl = locOf(tgt)
        -- the angle the lock seeker has to travel (for the lock-time model)
        c.targetAng0 = nil
        if tl then
            local du0 = math.sqrt((tl.X - loc.X) ^ 2 + (tl.Y - loc.Y) ^ 2 + (tl.Z - loc.Z) ^ 2)
            if du0 > 1 then c.targetAng0 = math.acos(clamp(((tl.X - loc.X) * F[1] + (tl.Y - loc.Y) * F[2] + (tl.Z - loc.Z) * F[3]) / du0, -1, 1)) end
        end
        c.lockEventFor = nil
        event("target", { target = c.targetName, callsign = c.targetCallsign, dist_m = tl and math.sqrt((tl.X - loc.X) ^ 2 + (tl.Y - loc.Y) ^ 2 + (tl.Z - loc.Z) ^ 2) / 10 or -1 })
    end
    -- Kill times from the whole of the engagements (20 Oct 2026): seconds with a target of each
    -- kind against the kills of that kind, the engagements that never ended in a kill included
    -- (Mission 06's drones, rated at 35 s a kill from the kills alone, took the last five
    -- minutes of a phase for two kills). The starting guess counts as two kills.
    if ap.scoreMode and c.target and c.targetKind and dt > 0 and dt < 0.5 then
        local K = killTally
        K.kindTime[c.targetKind] = (K.kindTime[c.targetKind] or 0) + dt
        if t - (K.ktAt or -100) > 2 then
            K.ktAt = t
            K.prior = K.prior or { agile = 35, large = 30, plane = 20, heli = 12, ground = 10 }
            for k, sec in pairs(K.kindTime) do
                killTimes[k] = (sec + (K.prior[k] or 15) * 2) / ((K.kindKills[k] or 0) + 2)
            end
        end
    end
    -- Score phases: a plane that will not die is a waste of the clock (19 Oct 2026, Mission
    -- 06: 1.5 minutes, 52 missiles and 500 gun frames at one F-16C dogfighting at 300-900 m,
    -- with 24,000 points wanted in 15 minutes). After 35 s and 6 missiles without the kill,
    -- and no damage done to it for 25 s, leave it alone for 45 s and take the next best. (The
    -- health check came after the rule let go of two Tu-160 bombers, 1,200 points each, that
    -- simply need many hits.)
    if ap.scoreMode and tgt and c.target then
        local hpNow = call(tgt, "GetHealth")
        if hpNow and c.tgtHpName == c.targetName and c.tgtHp and hpNow < c.tgtHp then c.tgtHpDropAt = t end
        if c.tgtHpName ~= c.targetName then c.tgtHpName, c.tgtHpDropAt = c.targetName, t end
        c.tgtHp = hpNow
    end
    if ap.scoreMode and c.target and c.targetSince and t - c.targetSince > 35 and (c.shotsAtTarget or 0) >= 6
        and t - (c.tgtHpDropAt or c.targetSince) > 25 then
        local n = c.targetName
        if n and not (c.skip[n] and t < c.skip[n]) then
            c.skip[n] = t + 45
            event("give_up", { target = n, after_s = t - c.targetSince, missiles = c.shotsAtTarget })
            log(string.format("  giving up on %s for 45 s: %.0f s and %d missiles without the kill", n, t - c.targetSince, c.shotsAtTarget))
            c.pref, c.prefAt = nil, -100
        end
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
        -- (from 3 s out since 19 Oct 2026: homing missiles' predicted miss shrinks fast in the
        -- last second, and flares at 0.9 s were too late for an F-16's missile)
        if flareMiss and (threat.tgo < 3.0 or threat.dist < vn) and t - c.lastFlare > 1.2 then
            tap(c, KEY.flare); c.lastFlare = t; c.flares = c.flares + 1; threat.flared = true
            event("flare", { reason = "tracker", missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10 })
        end
        -- break only for one predicted to pass within 350 m (200 m on the last 2.5 km of an
        -- attack run), or unknown: a break costs the attack run, and SAM sites fire every few
        -- seconds (Mission 14, 18 Oct: two minutes of breaks for missiles predicted to miss by
        -- 500-1400 m and no kills; at 23:57 a whole reinforcement wave lost to breaks; 250/120 m
        -- was tried at 00:04 and cost 117 health in under 3 minutes)
        local breakMiss = (c.runInAt and t - c.runInAt < 0.5) and 2000 or 3500
        -- score phases: a break costs the attack and the clock; with health to spare, only
        -- for a missile predicted to pass within 200 m (19 Oct 2026, Mission 06: ten breaks in
        -- five minutes for missiles predicted to miss by 290-350 m)
        -- (120 m was tried on 19 Oct 12:18 with the Onboard Self-Defense Jammer part fitted:
        -- shot down 8 minutes in, the last hit from a missile it did not break for; back to 200)
        -- (and in a furball at any health, 20 Oct 2026: under 60 health it is 350 m, and in a fight
        -- with fifteen missiles a minute coming the plane did little but break; the owner: "a
        -- bunch of high effort evasive maneuvers but it still needs to prioritize kills". At any
        -- health everywhere was tried the same evening and took more hits.)
        if ap.scoreMode and ((call(p, "GetHealth") or 0) > 60 or c.furball) then breakMiss = 2000 end
        -- (A jink for missiles passing 120-200 m, the score-race plan's fix 6, was flown in the
        -- first lanes runs; the defensive attack below replaced it the same evening.)
        -- The defensive attack (the owner, 19 Oct 2026, watching the lanes: "instead of breaking
        -- off its attack ... a 'defensive attack' where it still pursues a target but throws in
        -- some evasion to thwart attackers"): a missile that would have made the plane break is
        -- met by turning up to 35 degrees off the attack's own aim, across the missile's line,
        -- with the high-G turn and the flares the tracker fires about 2 s out, while the attack
        -- (its target, its lane, its lock) carries on. The full break is kept for the last
        -- instant (a missile still predicted within 60 m with under 1.2 s to go) and for low
        -- health (40 or less), or when there is nothing to attack; and in the last 2.5 s for a
        -- missile still predicted within 200 m.
        local hpNow = call(p, "GetHealth") or 0
        if threat.tgo < 4.0 and (not threat.miss or threat.miss < breakMiss) then
            local los = V.unit(V.sub(threat.p, { loc.X, loc.Y, loc.Z }))
            local side = V.unit(V.cross(los, { 0, 0, 1 }))
            if V.dot(side, F) < 0 then side = V.mul(side, -1) end
            -- (in the last 2.5 s a missile still predicted within 200 m gets the full break: a
            -- homing missile's predicted miss shrinks fast at the end, 199.8 m at 2.3 s and 38 m
            -- at 0.25 s for one that hit; the first evening's full phases took three 40-point hits
            -- from F-16 missiles while the plane only "defended". Further out the attack goes on.)
            local lastInstant = threat.tgo < 2.5 and (not threat.miss or threat.miss < 2000)
            -- in a committed furball with its target close and nearly on the nose, the kill comes
            -- first: only a missile still on course in its last 1.5 s gets the full break
            if c.furball and (c.lastDist or 1e9) < 2000 and (c.lastOff or 180) < 30 then
                lastInstant = threat.tgo < 1.5 and (not threat.miss or threat.miss < 1500)
            end
            -- (no last-instant break for a missile the smallest dodge was found to clear: the owner,
            -- 20 Oct 2026, the minimum change of the attack, back on it once the missile passes;
            -- if that lets hits through, the dodges widen 2.5% at a time, awareness.lua)
            if lastInstant and c.dodgeClears == threat.name then lastInstant = false end
            local attacking = (tgt ~= nil) or (c.laneOn and c.lanePlan ~= nil)
            -- (in a furball down to 20 health, elsewhere 40; 20 Oct 2026)
            if attacking and hpNow > (c.furball and 20 or 40) and not lastInstant then
                if not c.defUntil or t > c.defUntil then
                    c.defends = (c.defends or 0) + 1
                    event("defend", { missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10, miss_m = threat.miss and threat.miss / 10 or -1 })
                end
                c.defSide, c.defUntil, c.defThreat = { side[1], side[2], 0 }, t + 0.4, threat
                -- (a missile from the target itself while diving at it on its attack line, within
                -- 3 km: a side-step of 12 degrees, so the target stays in the lock cone; the 35 took
                -- the nose 64 degrees off a canyon SAM site at 2 km, run after run, 20 Oct 2026)
                local apS = Man and Man.approach and c.targetName and Man.approach.st[c.targetName]
                c.defAngle = (apS and apS.est and threat.ownerName == c.targetName and (c.lastDist or 1e9) < 3000) and 12 or 35
                c.defWhy = string.format("missile from %s, impact in %.1f s", threat.ownerName or "?", threat.tgo)
                if threat.tgo < 2.5 then keys[#keys + 1] = KEY.high_g end
            else
                c.breakAim = unit({ side[1], side[2], -0.15 })
                if not c.breakUntil or t > c.breakUntil then
                    event("evade", { missile = threat.name, tgo_s = threat.tgo, dist_m = threat.dist / 10, miss_m = threat.miss and threat.miss / 10 or -1 })
                end
                c.breakUntil = t + 0.4
                c.breakWhy = "missile, impact in " .. string.format("%.1f s", threat.tgo)
                if threat.tgo < 2.5 then keys[#keys + 1] = KEY.high_g end
            end
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
    -- where the time goes (the time split, see apStep): each branch below names its class
    c.splitClass = "other"
    if c.breakUntil and t < c.breakUntil then
        aim = c.breakAim
        text = "BREAK (" .. (c.breakWhy or "?") .. ")"
        c.splitClass = "break"
    elseif c.resupply and not c.resupply.landing then
        -- to the return line for a resupply (lanePlan): full throttle, at the line's height
        local L = c.resupply
        local hd = math.max(math.sqrt((L.x - loc.X) ^ 2 + (L.y - loc.Y) ^ 2), 1)
        aim = unit({ (L.x - loc.X) / hd, (L.y - loc.Y) / hd, clamp((L.z - loc.Z) / 15000, -0.25, 0.3) })
        c.speed = 2000
        text = string.format("to the return line for a resupply, %.1f km away", hd / 10000)
        c.splitClass = "transit"
        -- (not landing within 3 minutes: given up)
        if t - L.t0 > 180 then
            event("resupply_given_up", { after_s = t - L.t0, dist_m = hd / 10 })
            c.resupply = nil
        end
    elseif c.pursuer and not c.laneOn and (not c.lastDist or c.lastDist > 2500) then
        local P = c.pursuer.p
        aim = unit({ P[1] - loc.X, P[2] - loc.Y, P[3] - loc.Z })
        text = string.format("turning into %s, which is after us %.0f m behind (%s)", c.pursuer.name, c.pursuerDist / 10, c.pursuer.state or "?")
        if t - c.lastTab > 1.0 then tap(c, KEY.next_target); c.lastTab = t end
        c.splitClass = "pursuer"
    elseif c.transitTo and not c.laneOn then
        -- to the next group of targets: full throttle, high enough for the ground on the way,
        -- down to the pass height for the last 8 km
        local g = c.transitTo
        local hd = math.max(math.sqrt((g.x - loc.X) ^ 2 + (g.y - loc.Y) ^ 2), 1)
        local above = ap.agl or alt
        local wantAgl = hd > 80000 and 600 or ((Lanes and Lanes.P.passAgl) or 300)
        aim = unit({ (g.x - loc.X) / hd, (g.y - loc.Y) / hd, clamp((wantAgl - above) / 1500, -0.25, 0.3) })
        c.speed = 2000
        text = string.format("to the next group: %d targets, %.0f points, %.1f km away (%.0f points a second with the flight)", g.n, g.points, hd / 10000, g.rate)
        c.splitClass = "transit"
    elseif c.laneOn and c.lanePlan and not tgt then
        -- the lanes with nothing in the cone yet: fly the plan, standard missiles armed (an
        -- air-only special weapon armed hides every ground target from selection)
        aim = laneAim(c, loc, t, alt)
        if call(p, "IsSpecialWeaponArmed") == true and t - (c.lastSwitch or -100) > 1.5 then
            tap(c, KEY.weapon); c.lastSwitch = t
            event("weapon_switch", { to = "standard missiles", why = "lanes: ground targets", dist_m = -1 })
        end
        local nearest = math.huge
        for _, q in ipairs(c.laneTg or {}) do
            local d = math.sqrt((q[1] - loc.X) ^ 2 + (q[2] - loc.Y) ^ 2 + (q[3] - loc.Z) ^ 2) / 10
            if d < nearest then nearest = d end
        end
        text = "lanes: nothing in the cone yet; " .. laneText(c, t, F) .. string.format("; nearest target %.0f m", nearest)
        c.speed = (c.laneNearest or 0) > 5000 and 2000 or LANE_KMH
        c.splitClass = nearest < 3000 and "offnose" or "transit"
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
            c.splitClass = dm3 > 3000 and "transit" or (offS <= 45 and "ahead" or "offnose")
        else
            local h = unit({ F[1], F[2], 0 })
            aim = unit({ h[1] - R[1] * 0.15, h[2] - R[2] * 0.15, clamp((1500 - alt) / 1500, -0.3, 0.3) })
            text = "no targets anywhere; circling"
            c.speed = 650
            c.splitClass = "notarget"
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
                -- (a reloading special is put away for the standard missiles until it is back:
                -- the 8AGM's salvo reload is long, and armed it blocks the standard missiles)
                if want and c.specialReadyAt and t < c.specialReadyAt then want = false; why = "special weapon reloading" end
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
                -- not at agile drones: they dodge long shots (19 Oct 2026, Mission 06: seven LAAMs
                -- at one drone from 9.5 km in, one kill after 30 s)
                -- (agile ones, the drones, only from within 6 km until the pilot's own shots say
                -- more: they dodge long shots, 19 Oct 2026; 20 Oct: hit from 4-6 km twice, and the
                -- fifth full phase brought 11 LAAMs home while 11 drones worth 350 each flew on)
                local agileT = gameKind(tgt) == "agile"
                if agileT and du > 60000 then fits = false end
                want = fits and du > mainRange * 0.9 and du < sp.LockonRange * 0.95; why = "beyond standard missile range"
                -- ...and in a score phase for anything in the air it can take, near or far: the
                -- standard missiles are kept for the ground, which this weapon cannot touch (20 Oct
                -- 2026, Mission 06: a fifth of the standard missiles went at planes and helicopters
                -- while 12-16 of the 30 LAAMs came home unused, and the standard missiles ran out)
                -- (inside the distances it has been seen to hit from: not closer than 1.2 km or than
                -- the near edge its own misses showed, not beyond the far edge; LAAMs fired at planes
                -- from 460-770 m missed, 20 Oct 2026)
                local kindT = gameKind(tgt)
                local capS = Aware.rangeCap and Aware.rangeCap(sp.class, kindT)
                local floorS = Aware.rangeFloor and Aware.rangeFloor(sp.class, kindT)
                local nearS = math.max(1200, floorS and floorS + 100 or 0) * 10
                local farS = math.min(sp.LockonRange * 0.95, capS and capS * 10 or math.huge)
                if not want and ap.scoreMode and fits and sp.targets == "air only" and isPlane and du > nearS and du < farS then
                    want = true; why = "in the air: the special weapon, the standard missiles kept for the ground"
                end
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
        -- the first lock on this target: how long it took from the selection (the lock-time
        -- model the lanes plan with is fitted from these)
        if locked and c.lockEventFor ~= c.targetName then
            c.lockEventFor = c.targetName
            local after = t - (c.targetSince or t)
            if c.targetAng0 and after < 6 then learnLock(c, c.targetAng0, after) end
            c.locksN = (c.locksN or 0) + 1
            event("lock", { target = c.targetName, after_s = after, ang0_deg = c.targetAng0 and math.deg(c.targetAng0) or -1, dist_m = dm,
                            base_s = c.lockBase or -1, rate_dps = c.lockRate and math.deg(c.lockRate) or -1 })
        end
        if c.laneOn and c.lanePickName == c.targetName then c.laneLocked = locked end
        if locked then c.lastLockedName, c.lastLockedAt = c.targetName, t end
        c.lastOff = offT
        c.lockDiag = nil
        if not locked then
            c.lockDiag = string.format("not locked: the game's lock is on %s; selection put back %d times in the last second (the game had %s); target %s; seekers %s",
                lockObj and objName(lockObj) or "nothing", c.selWritesLast or 0, c.gameSel or "-", lockText(lockInfo(tgt)), seekersText(ts))
        end
        local range = c.missileRange
        if armed and sp and sp.LockonRange then range = math.max(range, sp.LockonRange / 10) end
        -- the distance this weapon was seen to stop hitting this kind of target (its own shots)
        if Aware and Aware.rangeCap then
            local wcls = armed and sp and sp.class or (W and W.main and W.main.class)
            -- (ground targets: a 60% hit rate asked for; 20 Oct 2026, see awareness.lua)
            local kindC = gameKind(tgt)
            local cap = wcls and Aware.rangeCap(wcls, kindC, kindC == "ground" and 0.6 or nil, kindC == "ground" and 6 or nil)
            if cap and cap < range then
                range = cap
                if c.capLogged ~= wcls .. gameKind(tgt) then
                    c.capLogged = wcls .. gameKind(tgt)
                    event("range_learned", { weapon = wcls, kind = gameKind(tgt), max_m = cap })
                    log(string.format("  %s at %s: holding fire beyond %.0f m (its own shots from there missed)", wcls, gameKind(tgt), cap))
                end
            end
        end
        -- Agile targets (drones; 19 Oct 2026, Mission 04's container-launched UAVs on Ace: 51
        -- missiles for 16 kills in 15 minutes, single shots from 2 km dodged): closer, nose-on,
        -- and a pair at a time rather than one.
        local agile = gameKind(tgt) == "agile" and not (armed and sp and sp.targets == "ground only")
        local maxOff, gap = 40, c.missileGap
        if agile then maxOff = 20; if c.shotsAtTarget % 2 == 1 then gap = 0.3 end end
        -- in the lanes a new target gets its missile as soon as it locks (the gap is only
        -- there so one target does not get two missiles by mistake)
        if c.laneOn and c.lastMissileName ~= c.targetName then gap = 0.25 end
        -- An agile drone outturns a missile fired close (Mission 04 on Ace, 19 Oct 2026: from
        -- 1.5 to 2.1 km 12 of 23 missiles were followed by the kill, from under 1.5 km 4 of 247):
        -- missiles from 1.3 km out to the lock range, the gun inside that
        local minRange = agile and 1300 or 0
        -- the near edge this weapon's own misses showed for this kind of target (20 Oct 2026)
        if Aware and Aware.rangeFloor then
            local wclsF = armed and sp and sp.class or (W and W.main and W.main.class)
            local fl = wclsF and Aware.rangeFloor(wclsF, gameKind(tgt))
            if fl then minRange = math.max(minRange, fl + 100) end
        end
        -- and not beyond 2.2 km (an air-only special armed for one: 6 km, see the weapon choice)
        if agile then range = math.min(range, (armed and sp and sp.targets == "air only") and 6000 or 2200) end
        -- a multi-lock ground special: hold fire while more locks are coming (at most 3 s,
        -- and not inside 2 km), so one salvo takes as many targets as it can
        local holdMulti = false
        if armed and sp and sp.multi and sp.targets == "ground only" and locked then
            local nL, nP = seekerCounts(ts)
            c.multiHoldSince = c.multiHoldSince or t
            -- (also inside 2 km since 19 Oct 2026, for 1.5 s: with the lanes the targets are mostly
            -- picked at 1-2 km, and a salvo at one lock wastes three missiles' reload)
            if nP > 0 and nL < (sp.MultipleLockOnMaxNum or 4) and ((dm > 2000 and t - c.multiHoldSince < 3) or (dm > 800 and t - c.multiHoldSince < 1.5)) then holdMulti = true end
            c.multiLocks = nL
        else
            c.multiHoldSince = nil
        end
        -- (not at a target set aside with a missile already on its way: in the lanes the game's
        -- selection can stay on it while nothing new is in the cone)
        local pendingHere = c.laneOn and c.skip[c.targetName] and t < c.skip[c.targetName]
        -- Missile discipline (20 Oct 2026): no more of the pilot's missiles in the air at one
        -- target than its health needs (one per weapon's damage; a pair at an agile one); the next
        -- only once one has ended. On 19 Oct the bot fired a LAAM every 1.2 s at bombers 5-9 km
        -- away, ten and more before the first had ended, and nearly all of them missed.
        local need, flying = 99, 0
        if Aware and Aware.inFlight then
            local dmgW = ((armed and sp) or (W and W.main) or {}).Damage or 40
            local hpT = call(tgt, "GetHealth")
            need = (hpT and hpT > 0) and math.max(1, math.ceil(hpT / math.max(dmgW, 1))) or 1
            if agile then need = need + 1 end
            flying = Aware.inFlight(c.targetName)
            -- (a press in the last 0.6 s whose missile is not seen yet counts too)
            if c.lastMissileName == c.targetName and t - c.lastMissile < 0.6 then flying = flying + 1 end
        end
        if locked and flying >= need and dm < range and offT < maxOff and not Gun.test and t - (c.disciplineAt or -100) > 2 then
            c.disciplineAt = t
            event("hold_fire", { target = c.targetName, in_flight = flying, need = need, dist_m = dm })
        end
        local fireOk = locked and dm < range and dm > minRange and offT < maxOff and t - c.lastMissile > gap and not holdMulti and not pendingHere
            and not Gun.test and flying < need
        -- ...and only with a clear line to the target (20 Oct 2026; awareness.lua's losBlocked):
        -- blocked more than 40 m short of it (60 m for one in the air, which is bigger), hold
        -- fire; in the lanes the target is set aside for a second and the next one picked
        local losShort = nil
        if fireOk and Aware and Aware.losBlocked then
            local inAir = airborne(tgt)
            losShort = Aware.losBlocked({ loc.X, loc.Y, loc.Z }, { tl.X, tl.Y, tl.Z }, inAir and 0 or 3)
            if losShort and losShort > (inAir and 60 or 40) then
                fireOk = false
                if t - (c.losAt or -100) > 1 then
                    c.losAt = t
                    c.losHolds = (c.losHolds or 0) + 1
                    event("los_blocked", { target = c.targetName, dist_m = dm, short_m = losShort, off_deg = offT, agl_m = ap.agl or -1 })
                end
                if c.laneOn and not inAir then
                    c.skip[c.targetName] = t + 1.0
                    c.pref, c.lanePickName = nil, nil
                end
            end
        end
        if fireOk then
            if c.multiHoldSince then event("salvo", { locks = c.multiLocks or 1, held_s = t - c.multiHoldSince, dist_m = dm }) end
            c.multiHoldSince = nil
            tap(c, KEY.missile); c.lastMissile = t; c.shots = c.shots + 1; c.shotsAtTarget = c.shotsAtTarget + 1
            if armed then c.specialShots = (c.specialShots or 0) + 1 end
            local elev = math.deg(math.asin(clamp((tl.Z - loc.Z) / math.max(du, 1), -1, 1)))
            event("missile", { target = c.targetName, dist_m = dm, off_deg = offT, special = armed, lanes = c.laneOn or false,
                               elev_deg = elev, agl_m = ap.agl or -1, in_flight = flying, value = c.laneValue and c.laneValue[c.targetName] or -1,
                               los_short_m = losShort or -1 })
            firedAt[objName(tgt)] = t
            shotInfo[c.targetName] = { kind = gameKind(tgt), bounty = objInfo(tgt).bounty, cls = objInfo(tgt).cls }
            if objInfo(tgt).cls and gameKind(tgt) == "plane" then
                local dmg = (armed and sp and sp.Damage) or (W and W.main and W.main.Damage) or 40
                learnAgile(objInfo(tgt).cls, 1, 0, math.max(1, math.ceil((objInfo(tgt).maxHp or 40) / math.max(dmg, 1))))
            end
            c.lastMissileName = c.targetName
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
                -- in the lanes the next target is picked at once, not when the launch is
                -- confirmed (the plan's "anticipate"); if no missile left the rail (none
                -- loaded) it comes back after 0.7 s
                local loadedNow = 2
                if c.laneOn then
                    local wpn = laneWeapon(c, t)
                    loadedNow = wpn and wpn.loaded or 2
                end
                if c.laneOn and loadedNow > 0 then
                    c.skip[c.pendingShot.name] = t + c.pendingShot.flight
                    c.unconfirmed = { name = c.pendingShot.name, t = t }
                    c.lastLaunchAt, c.lastLaunchName = t, c.pendingShot.name
                    -- (the next one is selected a quarter of a second later, not in this frame:
                    -- with the fire key still down the game launched at the newly selected,
                    -- unlocked target, and the missile flew unguided; 14 of 61 standard missiles
                    -- in the fourth full phase of 20 Oct 2026)
                    c.chainAt = t + 0.25
                end
            end
            if hp and dmgPer and c.laneOn then
                c.incoming[objName(tgt)] = { dmg = dmgPer, untilT = t + du / math.max(((spec and spec.SpeedMaximum) or 10000) * 0.6, 3000) + 1.0 }
            end
        end
        -- The game's lock is on another enemy (its seeker can stay on the previous one, or
        -- pick its own): when that one is worth at least half the chosen target, fire at it
        -- rather than hold the missiles (Mission 14, 18 Oct 23:55: four times in a minute the
        -- lock sat on a landing-zone Apache other than the bot's pick, and nothing was fired)
        if not locked and lockObj and t - c.lastMissile > c.missileGap and not Gun.test then
            local ln = objName(lockObj)
            if ln and ln ~= "invalid" and alive(lockObj) and not (c.skip[ln] and t < c.skip[ln])
                and not (Aware and Aware.inFlight and Aware.inFlight(ln) > 0) then
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
        -- In the lanes: the plan's heading at the pass height, whatever is selected.
        c.gunPass = nil
        if Gun.test and Gun.mod and not airborne(tgt) then
            -- the gun measurement: a strafing pass (gunnery.lua)
            local ph, dmG, low
            aim, ph, dmG, low = Gun.mod.run(c, c.targetName, tl, loc, F, ap.agl or alt)
            c.gunPass = low and ph == "in" or nil
            c.groundText = string.format("strafing pass, %s, %.0f m above ground", ph == "in" and "running in" or "breaking off", ap.agl or alt)
        elseif c.laneOn and c.lanePlan and c.airShot and sameObj(tgt, c.airShot.obj) then
            -- an air shot in passing: the nose flicks onto the plane for its few seconds (the aim
            -- worked out above, where it will be), then the lanes go on (20 Oct 2026: flying the
            -- lane through them, 4 of 5 air shots at drones 17-23 degrees off never fired, the
            -- drone sliding out of the LAAM's cone before the lock built)
            c.groundText = "air shot in passing: nose on " .. tostring(c.airShot.name)
        elseif c.laneOn and c.lanePlan then
            aim = laneAim(c, loc, t, alt)
            c.groundText = "lanes: " .. laneText(c, t, F)
        elseif Aware and not airborne(tgt) then
            local phase
            -- score phases: the middle of the cluster around this target, fixed for a pass
            if ap.scoreMode and scorePts and not c.sweepFix and not Gun.test then
                local sx, sy, sz, sw, n = 0, 0, 0, 0, 0
                for _, q in ipairs(scorePts) do
                    if (q[1] - tl.X) ^ 2 + (q[2] - tl.Y) ^ 2 < 20000 ^ 2 then
                        sx, sy, sz, sw, n = sx + q[1] * q[4], sy + q[2] * q[4], sz + q[3] * q[4], sw + q[4], n + 1
                    end
                end
                if n >= 3 then
                    c.sweepX, c.sweepY, c.sweepZ, c.sweepN, c.sweepFix = sx / sw, sy / sw, sz / sw, n, true
                else
                    c.sweepN = nil
                end
            end
            if ap.scoreMode and c.sweepFix and c.sweepN and not Gun.test and (c.sweepX - tl.X) ^ 2 + (c.sweepY - tl.Y) ^ 2 < 30000 ^ 2 then
                aim, phase = sweepRun(c, loc, F, alt)
                -- the nose on the chosen target while it is ahead, so its lock can build (about
                -- a second or two; steering only at the middle, 19 Oct 06:39, every lock was
                -- still "started" when the target slid off the nose)
                local onTarget = false
                if phase == "in" and dm > 900 and offT < 45 then
                    local thd = math.sqrt((tl.X - loc.X) ^ 2 + (tl.Y - loc.Y) ^ 2)
                    -- down to about 30 degrees while there is height to spare: from 600-1,100 m up the
                    -- old 19 degree limit kept a tank 1.6 km out below the 32.5 degree lock cone for a
                    -- minute and a half of passes (19 Oct 2026, 08:48)
                    local above = ap.agl or alt
                    local tz = math.max((tl.Z - loc.Z) / math.max(thd, 1), above > 450 and -0.6 or -0.35)
                    if above < 300 then tz = math.max(tz, 0.05) end
                    aim = unit({ (tl.X - loc.X) / math.max(thd, 1), (tl.Y - loc.Y) / math.max(thd, 1), tz })
                    onTarget = true
                end
                c.groundText = string.format("sweep through %d targets, %s%s, %.0f m above ground", c.sweepN,
                    phase == "in" and "running in" or "past the middle", onTarget and ", nose on the target" or "", ap.agl or alt)
            else
                c.sweepFix = nil
                aim, phase = groundRun(c, c.targetName, tl, loc, F, alt)
                -- score phases: no orbiting (the plan's fix 3): a ground target within 1.5 km
                -- and more than 45 degrees off the nose is left for 10 s; it comes back on a
                -- later pass (the lanes' run-out manoeuvres bring it into the cone)
                if ap.scoreMode and dm < 1500 and offT > 45 and not (c.skip[c.targetName] and t < c.skip[c.targetName]) then
                    c.skip[c.targetName] = t + 10
                    event("skip", { target = c.targetName, why = "orbit: close and off the nose", dist_m = dm, off_deg = offT, for_s = 10 })
                    c.pref, c.prefAt = nil, -100
                end
                c.groundText = string.format("ground attack run, %s, %.0f m above ground%s", phase == "in" and "running in" or "extending", ap.agl or alt,
                    c.underClouds and string.format(" (under the clouds at %.0f m)", c.underClouds) or "")
                local lt = Man and Man.approach and not ap.scoreMode and Man.approach.text(c.targetName)
                if lt then c.groundText = string.format("ground attack, %s, %.0f m above ground", lt, ap.agl or alt) end
            end
        else
            c.groundText = nil
            -- A helicopter close by and far off the nose: a plane cannot turn tightly enough to
            -- point at it, so circling it wastes the time (Mission 14, 18 Oct: two minutes at
            -- 200-700 m behind Apaches). Open out to 1.6 km, turn back, come in nose-on.
            local tk = gameKind(tgt)
            -- an agile drone too close for a missile and off the nose: open out the same way,
            -- to 1.8 km, and come back for a missile shot from range
            if tk == "agile" then
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
                -- (only very close and well off the nose since 20 Oct 2026: inside 900 m the gun,
                -- zeroed by the bullets the pilot has seen, finishes a 40-health drone in a second
                -- or two, and opening out to 1.8 km looked like indecision to the owner)
                if not onTail and not c.heliOut[key] and dm < 400 and offT > 60 then c.heliOut[key] = true; event("drone_open_out", { target = key, dist_m = dm }) end
                if c.heliOut[key] and dm > 1200 then c.heliOut[key] = nil end
                if c.heliOut[key] then
                    local away = unit({ loc.X - tl.X, loc.Y - tl.Y, loc.Z - tl.Z })
                    aim = unit({ away[1], away[2], clamp(away[3], -0.2, 0.3) })
                    c.groundText = "drone too close for a missile: opening out to 1.2 km"
                end
            end
            if tk == "heli" then
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
        local gunNow = dm < 1000 and offT < 5
        -- (a slow, agile target close in: a wider window, 7 degrees inside 900 m; locked drones
        -- 7-17 degrees off at 500-1,000 m got neither a missile, inside the 1.3 km minimum for
        -- drones, nor the gun; 20 Oct 2026)
        if not gunNow and dm < 900 and offT < 7 and gameKind(tgt) == "agile" then gunNow = true end
        if Gun.test and Gun.mod then gunNow = Gun.mod.fire(dm, offT) end
        c.gunFiring = gunNow
        if gunNow then
            keys[#keys + 1] = KEY.gun; c.gunFrames = c.gunFrames + 1
            Gun.burstTick(c, t, tgt, c.targetName, dm, offT)
        end
        if dm < 300 and offT < 30 then
            -- about to fly into it: pull up and away
            aim = unit({ F[1] + 0.0, F[2], F[3] + 0.8 })
        end
        text = string.format("target %s %s %.0f m, %.0f deg off nose%s%s%s", c.targetName, c.targetCallsign, dm, offT, locked and ", LOCKED" or "",
            c.predText and ("; " .. c.predText) or "", c.specialText and ("; " .. c.specialText) or "")
        if c.groundText then text = text .. "; " .. c.groundText end
        if c.lockDiag and dm < 2500 then text = text .. "; " .. c.lockDiag end
        c.speed = dm > 3000 and 1150 or (dm > 1200 and 850 or 650)   -- close the distance fast, then slow for the turn fight
        -- on an attack line (approach.lua): fast only well out, 850 km/h for the turn onto the line
        -- and 700 down it (from the measured turn rates: a turn radius of about 400 m at 850 km/h
        -- against 650 m at 1,150)
        local apSt = c.groundText and not ap.scoreMode and Man and Man.approach and Man.approach.st[c.targetName]
        if apSt and apSt.line then
            c.speed = dm > 4500 and 1150 or (dm > 2600 and 850 or 700)
            -- a steep line (35 degrees or more): 650 km/h from 6 km, before the push over (the brake
            -- only holds the speed in a 30-60 degree dive; Mission 07, 20 Oct 2026: dives at
            -- 1,050-1,150 km/h down 50-60 degree lines passed 2 km to 700 m in about 4 s)
            local el = Man.approach.lineEl(c.targetName)
            if el and el >= 35 and dm <= 6000 then c.speed = 650 end
        end
        -- any fight: full throttle to a target more than 6 km away within 30 degrees of the nose
        -- (20 Oct 2026, Mission 07: half of phase 1 was transit at 1,150 km/h; the owner had found
        -- the bot timid with the throttle over long distances, which until now only the score
        -- phases answered)
        if dm > 6000 and offT < 30 and not (c.laneOn and c.lanePlan) then c.speed = 2000 end
        -- Timed score phases: full throttle whenever the target is more than 2.5 km away
        -- (the owner, 19 Oct 2026: "timid about going full throttle even when traveling long
        -- distances ... for missions racing against the clock it is going to need to move
        -- and maneuver more aggressively"); a sweep's run in at 650 km/h, so each lock still
        -- gets a second or two with the target ahead
        -- (full throttle only with the target within 30 degrees of the nose: a turn at full
        -- throttle in a dive reached 1,980 km/h, where the plane turns at half its rate and a
        -- bomber 3.5 km away stayed 70-110 degrees off the nose; 19 Oct 2026)
        if ap.scoreMode and dm > 2500 then c.speed = (offT < 30) and 2000 or 750 end
        if ap.scoreMode and c.sweepFix and c.sweepRun == "in" and c.groundText and c.groundText:find("sweep", 1, true) then
            local sd = math.sqrt((c.sweepX - loc.X) ^ 2 + (c.sweepY - loc.Y) ^ 2)
            if sd < 35000 then c.speed = 650 end
        end
        if c.laneOn and c.lanePlan then c.speed = (c.laneNearest or 0) > 5000 and 2000 or LANE_KMH end
        -- a slow, agile target (a drone) close by: about 500 km/h, not to overshoot it (20 Oct 2026)
        if gameKind(tgt) == "agile" and dm < 2000 and not (c.laneOn and c.lanePlan) then c.speed = 500 end
        -- a strafing pass at about 600 km/h: more time with the target in reach
        if Gun.test and Gun.mod and not airborne(tgt) and dm < 3500 then c.speed = Gun.mod.P.kmh or 600 end
        c.lastDist = dm
        c.splitClass = locked and "locked" or (dm > 3000 and "transit" or (offT <= 45 and "ahead" or "offnose"))
    end

    -- A gun snap while the lanes are flown (gunnery.lua, 20 Oct 2026): a target the gun can kill
    -- nearly on the nose and within its reach gets a short burst, the nose put exactly on it
    -- (its aim corrected by where the pilot's own bullets have been seen to go), while the
    -- missiles reload or lock; the low part gets the strafing pass's lower floor.
    c.snapObj = nil
    if c.laneOn and Gun.mod and Gun.mod.snap and not (c.breakUntil and t < c.breakUntil) and not Gun.test then
        local okS, sAim, sFire, sq = pcall(Gun.mod.snap, c, t, loc, F, c.laneSnap or {}, ap.agl or alt)
        if okS and sAim then
            aim = sAim
            c.gunPass = true
            if sFire then
                keys[#keys + 1] = KEY.gun; c.gunFrames = c.gunFrames + 1; c.gunFiring = true; c.snapObj = sq.obj
                local sl = locOf(sq.obj)
                if sl then
                    local sd = math.sqrt((sl.X - loc.X) ^ 2 + (sl.Y - loc.Y) ^ 2 + (sl.Z - loc.Z) ^ 2)
                    Gun.burstTick(c, t, sq.obj, sq.name, sd / 10, 0)
                end
            end
            text = (text or "") .. " | GUN SNAP at " .. tostring(sq and sq.name or "?") .. (sFire and ", firing" or "")
        elseif not okS and not c.snapErr then
            c.snapErr = true; log("gun snap: " .. tostring(sAim))
        end
    end
    -- the defensive attack: the attack's aim, turned across the missile's line
    if aim and c.defUntil and t < c.defUntil and not (c.breakUntil and t < c.breakUntil) then
        local sd = c.defSide
        local perp = { sd[1] - aim[1] * dot(sd, aim), sd[2] - aim[2] * dot(sd, aim), sd[3] - aim[3] * dot(sd, aim) }
        local pu, pl = unit(perp)
        if pl > 0.05 then
            -- the smallest turn off the attack that the missile misses by, flown ahead for each
            -- of 0-35 degrees against the missile's own turn rate (awareness.lua's minDodge; the
            -- owner, 20 Oct 2026: the minimum alteration, so the attack is back on as soon as the
            -- missile passes); when none of them clears it 35, or 12 for a missile from the target
            -- dived at on its attack line (the full break stays for the last instant)
            if Aware and Aware.minDodge and c.defThreat and ap.myV and t - (c.dodgeAt or -100) > 0.1 then
                c.dodgeAt = t
                local om = (Man and Man.ctx and Man.ctx.omega and Man.ctx.omega()) or math.rad(38)
                local sc = Aware.dodgeScale or 1
                c.defThreat.dodged = true
                local okD, dg, pass = pcall(Aware.minDodge, c.defThreat, { loc.X, loc.Y, loc.Z }, ap.myV, aim, pu, om * 0.85, 120 * sc)
                if okD and dg then c.dodgeClears = c.defThreat.name end
                -- (none of them clears it: the fallback, 35 degrees or 12 for the target's own missile)
                if okD then dg = dg and math.min(45, dg * sc) or (c.defAngle or 35) end
                -- (for one missile the dodge only grows until it has passed: worked out ten times a
                -- second it jumped 25, 0, 35, 0 degrees within a second; a jink back and forth costs
                -- the turn twice)
                if c.dodgeMissile == c.defThreat.name and c.dodgeDeg then
                    dg = math.max(okD and dg or 0, c.dodgeDeg)
                    okD = true
                end
                c.dodgeMissile = c.defThreat.name
                c.dodgeDeg = okD and dg or nil
                if not okD and not c.dodgeErr then c.dodgeErr = true; log("minDodge: " .. tostring(dg)) end
                if okD and dg ~= c.lastDodgeDeg then
                    event("dodge", { missile = c.defThreat.name, deg = dg or -1, pass_m = pass or -1, tgo_s = c.defThreat.tgo })
                end
                c.lastDodgeDeg = okD and dg or nil
            end
            local deg = c.dodgeDeg or c.defAngle or 35
            local a = math.rad(deg)
            aim = unit({ aim[1] * math.cos(a) + pu[1] * math.sin(a), aim[2] * math.cos(a) + pu[2] * math.sin(a), aim[3] * math.cos(a) + pu[3] * math.sin(a) })
            c.defDeg = deg
        end
        text = (text or "") .. " | DEFENSIVE ATTACK (" .. (c.defWhy or "?") .. string.format(", %d deg off the attack)", c.defDeg or 35)
        c.splitClass = "defend"
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
            c.splitClass = "other"
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
                c.launchTimes = c.launchTimes or {}
                for _ = 1, c.ammo.m - m do c.launchTimes[#c.launchTimes + 1] = t end
                event("launch", { weapon = "missile", n = c.ammo.m - m, left = m, target = c.targetName })
                -- the reload clock the lanes plan with: each missile is back after the load
                -- time; a launch while the clock says none is loaded means the real load time is
                -- shorter (parts shorten it), so it is learned from that launch
                local Wm = Aware and Aware.weapons and Aware.weapons.main
                if Wm then
                    local maxL = Wm.MaxLoadedCount or 2
                    for _ = 1, c.ammo.m - m do
                        local pend = {}
                        for _, r in ipairs(c.reloadAt or {}) do if r > t then pend[#pend + 1] = r end end
                        table.sort(pend)
                        local lt = c.loadTime or Wm.LoadTime or 5.5
                        if #pend >= maxL then
                            c.loadTime = math.max(1.0, lt - (pend[1] - t))
                            table.remove(pend, 1)
                            event("reload_learned", { load_s = c.loadTime, class_load_s = Wm.LoadTime or -1 })
                        end
                        pend[#pend + 1] = t + (c.loadTime or lt)
                        c.reloadAt = pend
                    end
                end
            end
            local u = c.unconfirmed
            if u and launched then
                c.unconfirmed = nil
            elseif u and t - u.t > 0.7 then
                -- the press launched nothing (no missile loaded): the target comes back
                c.skip[u.name] = nil
                if c.incoming then c.incoming[u.name] = nil end
                c.unconfirmed = nil
                event("shot_not_launched", { target = u.name })
            end
            -- a one-missile kill on its way: set the target aside until it should have hit and
            -- choose the next at once, so the second loaded missile goes to another target
            local ps = c.pendingShot
            if ps and t - ps.t < 1.0 and ((ps.special and launchedSp) or (not ps.special and launched)) then
                c.skip[ps.name] = t + ps.flight
                -- (in the lanes the next target is already picked: keep it)
                if not c.laneOn then c.prefAt, c.pref, c.prefSince = -100, nil, -100 end
                c.oneShots = (c.oneShots or 0) + 1
                c.lastMissile = t - c.missileGap + 0.35
                event("one_shot", { target = ps.name, hp = ps.hp, damage = ps.damage, set_aside_s = ps.flight })
                c.pendingShot = nil
            elseif ps and t - ps.t >= 1.0 then
                c.pendingShot = nil
            end
            if sCount and c.ammo.s and sCount >= 0 and sCount < c.ammo.s then
                c.specialLaunches = (c.specialLaunches or 0) + (c.ammo.s - sCount)
                -- an air shot in passing is done once its missile is away
                if c.airShot then c.airShot.fired = true; c.airShot.untilT = math.min(c.airShot.untilT, t + 0.3) end
                local Wsp = Aware and Aware.weapons and Aware.weapons.special
                if Wsp and Wsp.multi then c.specialReadyAt = t + (Wsp.LoadTime or 10) end
                event("launch", { weapon = "special", n = c.ammo.s - sCount, left = sCount, target = c.targetName })
            end
        end
        c.ammo = { m = m, s = sCount }
        -- the full load (the most seen: a resupply brings it back)
        if type(m) == "number" and m > (c.ammoCap or 0) then c.ammoCap = m end
    end
    for key, untilT in pairs(c.taps) do
        if t < untilT then keys[#keys + 1] = key else c.taps[key] = nil end
    end
    -- a gun burst that has stopped: what it did
    if c.gunBurst and t - c.gunBurst.last > 0.3 then Gun.burstEnd(c, t) end
    -- the gunnery module's look at every fight frame (where the bullets go); a fault there is
    -- logged once and the pilot flies on
    if Gun.mod and Gun.mod.tick then
        local okT, errT = pcall(Gun.mod.tick, c, t, c.snapObj or tgt, loc, c.gunFiring, Aware and Aware.weapons and Aware.weapons.gun and Aware.weapons.gun.class)
        if not okT and not c.gunTickErr then c.gunTickErr = true; log("gunnery tick: " .. tostring(errT)) end
    end
    if c.threatText then text = (text or "") .. " | THREAT: " .. c.threatText end
    c.text = text
    return aim, keys
end

-- The fight's last time split and what the pilot learned (lock time, reload, turn rate), when
-- an order ends or is replaced
local function finalSplit(why)
    if not (ap and ap.combat and ap.combat.split) then return end
    local c = ap.combat
    -- the plan audit: shots the plans expected against launches in the same 12 s windows
    local expected, got, n = 0, 0, 0
    local H = (Lanes and Lanes.P.horizon) or 12
    for _, a in ipairs(c.audits or {}) do
        if now() - a.t >= H then
            n = n + 1
            expected = expected + a.shots
            for _, lt in ipairs(c.launchTimes or {}) do if lt >= a.t and lt < a.t + H then got = got + 1 end end
        end
    end
    event("time_split", { split = c.split, order_t0 = ap.t0, final = true, why = why, kills = c.kills,
                          lock_base_s = c.lockBase or -1, lock_rate_dps = c.lockRate and math.deg(c.lockRate) or -1,
                          load_s = c.loadTime or -1, turn_dps = math.deg(planeTurn.est), turn_samples = planeTurn.n,
                          chains = c.chains or 0, defends = c.defends or 0, locks = c.locksN or 0,
                          audit_plans = n, audit_expected = expected, audit_launched = got,
                          gun_bursts = Gun.stats.bursts, gun_kills = Gun.stats.kills, gun_dmg = Gun.stats.dmg, gun_s = Gun.stats.secs,
                          kill_times = killTimes, kind_kills = killTally.kindKills, kind_time = killTally.kindTime })
end

local function apStep(p, dt)
    if not ap then return false end
    -- (a vertical attack is flown only in a frame whose aim comes from it: laneAim sets it;
    -- likewise a pull-out from a steep dive in a ground recovery)
    ap.vertical, ap.pullThrough = false, false
    local t = now() - ap.t0
    if ap.duration and t >= ap.duration then
        finalSplit("time")
        CoopKeys_Set("")
        log(string.format("fly: finished after %.0f s (%d frames, %d of them in ground recovery)", t, ap.frames, ap.recoverFrames))
        event("autopilot_end", { reason = "time" })
        ap = nil
        return false
    end
    ap.frames = ap.frames + 1
    if not ap.planeClassChecked then
        -- the turn rate measured for another plane does not count for this one
        ap.planeClassChecked = true
        local pc = classOf(p)
        if planeTurn.class ~= pc then planeTurn.est, planeTurn.n, planeTurn.class = math.rad(35), 0, pc end
    end
    local loc = p:K2_GetActorLocation()
    local rot = p:K2_GetActorRotation()
    local F, R, U = axes(rot)
    ap.F, ap.U = F, U
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
    -- A resupply's landing and take-off (lanePlan, combatStep): the game takes the controls once
    -- the plane is over the return line; tools\playtest.py presses the keys that skip the landing,
    -- keep the special weapon and take off ("resupply_landing"); the pilot lets go of every key
    -- meanwhile, and when the controls come back the fight goes on with the new load
    local cR = ap.combat
    if cR and cR.resupply then
        local mv = p.bEnableMovmentInput
        if mv == false then
            if not cR.resupply.landing then
                cR.resupply.landing = now()
                local dl = math.sqrt((cR.resupply.x - loc.X) ^ 2 + (cR.resupply.y - loc.Y) ^ 2) / 10
                event("resupply_landing", { line = cR.resupply.name, dist_m = dl, after_s = now() - cR.resupply.t0 })
                log(string.format("  resupply: the landing has begun (%.0f m from the line)", dl))
            end
            CoopKeys_Set("")
            return true
        elseif mv == true and cR.resupply.landing then
            local wa = weapons(p)
            local m, sCount = call(wa, "GetMainWeaponCount"), call(wa, "GetSpecialWeaponCount")
            event("resupply_done", { missiles = m or -1, special = sCount or -1, health = call(p, "GetHealth") or -1,
                                     away_s = now() - cR.resupply.landing })
            log(string.format("  resupply: back in the air with %s missiles, %s special, health %s", tostring(m), tostring(sCount), tostring(call(p, "GetHealth"))))
            cR.resupply = nil
            cR.ammo = { m = m, s = sCount }
            if type(m) == "number" and m > (cR.ammoCap or 0) then cR.ammoCap = m end
            -- the economies start afresh with the new load
            cR.econSince, cR.spStart, cR.lambda = nil, nil, 0
            cR.lanePlan, cR.laneOn, cR.transitTo, cR.dive = nil, false, nil, nil
            ap.lastHealth = call(p, "GetHealth") or ap.lastHealth
        end
    end
    -- damage taken
    local health = call(p, "GetHealth")
    if health and ap.lastHealth and health < ap.lastHealth then
        event("damage", { amount = ap.lastHealth - health, health = health, alt_m = call(p, "GetAltitudeMeters") })
        if Aware and Aware.noteDamage then Aware.noteDamage(now(), ap.lastHealth - health, ap.agl) end
        log(string.format("  DAMAGE: -%s, health now %s", fmt(ap.lastHealth - health), fmt(health)))
        -- gunfire (a few points a hit): the ground enemies within 2.5 km are marked as the guns
        -- firing at the plane, and count as threats for a minute (threatFactor). 19 Oct 2026, the
        -- first aggressive full phase: about 30 points of chip damage in under two minutes over
        -- an anti-aircraft site, on top of two missile hits, and the plane was lost at 8:43.
        if ap.lastHealth - health <= 3 then
            local lp = p:K2_GetActorLocation()
            for _, q in ipairs(laneCands) do
                if q.x and (q.x - lp.X) ^ 2 + (q.y - lp.Y) ^ 2 + (q.z - lp.Z) ^ 2 < 25000 ^ 2 then gunMarks[q.name] = now() end
            end
        end
    end
    ap.lastHealth = health
    local alt = call(p, "GetAltitudeMeters") or (loc.Z / 10)
    local kmh = call(p, "GetSpeedKmph") or 0
    local vz = 0
    if ap.lastZ and dt > 0 then vz = (loc.Z - ap.lastZ) / 10 / dt end
    ap.lastZ = loc.Z
    ap.vz = (ap.vz or 0) * 0.8 + vz * 0.2

    -- Score phases switch on by themselves from what the game shows (the owner's generality
    -- rule, 19 Oct 2026): a score goal on the HUD ("SCORE 003480/024000", visible) means the
    -- phase is won on points, whatever the mission; when the goal goes, so does the mode. (An
    -- order's "score" word still forces it on.)
    if ap.goal.kind == "attack" and t - (ap.goalCheckAt or -100) > 2 then
        ap.goalCheckAt = t
        local goal, hs = hudScoreGoal()
        if goal and not ap.scoreMode then
            ap.scoreMode, ap.scoreAuto = true, true
            event("score_mode", { on = true, goal = goal, hud = hs, why = "the HUD shows a score goal" })
            log("  score mode ON: the HUD shows a score goal (" .. tostring(hs) .. ")")
        elseif not goal and ap.scoreMode and ap.scoreAuto then
            ap.scoreMode, ap.scoreAuto = false, false
            event("score_mode", { on = false, why = "no score goal on the HUD any more" })
            log("  score mode OFF: no score goal on the HUD any more")
        end
    end
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
            -- handed back only once clear of it: nothing close above or beside, and some height
            -- (19 Oct 2026, Mission 06's tunnel: a fixed 15 s handed over in the cutting beyond the
            -- exit, 20 m up with a hill ahead, and the fight mode scraped the ground for 24 damage)
            local W = Vision and Vision.last and Vision.last.walls
            local enclosed = W and (W.up < 120 or W.left < 60 or W.right < 60)
            local high = (ap.agl or alt) > 50
            if (away > 15000 and not enclosed and high) or now() - g.passedT > 40 then g.done = true end
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
    -- ...and the combat zone: within 4 km of its edge, back toward its middle (within 1 km on the
    -- way to a return line, which lies near the edge: Mission 06's about 3.5 km inside it)
    local zm = zoneMargin(loc.X, loc.Y)
    local zoneLim = (ap.combat and ap.combat.resupply) and 10000 or 40000
    if zm < zoneLim and not ap.wasOutside then
        local z = combatZone(loc.X, loc.Y)
        if not ap.nearZoneEdge then event("zone_edge", { margin_m = zm / 10 }); log(string.format("  fly: %.1f km from the combat zone's edge, turning back in", zm / 10000)) end
        ap.nearZoneEdge = true
        aim = unit({ z.cx - loc.X, z.cy - loc.Y, clamp(aim[3], -0.2, 0.2) })
    elseif zm > 50000 then
        ap.nearZoneEdge = false
    end
    -- Stay alive: below the floor, or heading for it within 4 s, climb away first. The floor
    -- is height above the real ground where the terrain sensor sees ground (awareness.lua:
    -- line traces below the plane and below its course 1-4 s ahead), above the sea elsewhere.
    local floor = ap.floor
    -- The lanes fly low passes (250 m over the targets: a target 2 km out is then 7 degrees
    -- below the nose, inside the lock cone), so their floor is 120 m and the ground ahead only
    -- has to stay 100 m below (the score-race plan's safety limits). With the order's floor
    -- (300 m unless given) every descent into a pass was a ground recovery (19 Oct 2026, the
    -- first lanes run: 40% of the lane time above 1 km, where close targets sit below the cone).
    local laneLow = ap.combat and ap.combat.laneOn
    if laneLow then floor = math.min(floor, 120) end
    -- the low part of a strafing pass (gunnery.lua): its own floor, and the ground ahead only
    -- needs a little clearance (the pass aims at the ground on purpose and breaks off by itself)
    local gunLow = ap.combat and ap.combat.gunPass and Gun.mod
    if gunLow then floor = math.min(floor, Gun.mod.P.floor) end
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
    -- The manoeuvre planner (maneuver.lua; the owner, 20 Oct 2026: "pathfinding, maneuvering,
    -- innate knowledge of its own aircraft's capabilities"): in a fight, four times a second the
    -- way the pilot wants is flown 5 s ahead in this plane's model (its measured turn rate, roll
    -- rate and speed changes) and traced against the ground and structures; when it is not
    -- clear with room to spare, the safe manoeuvre closest to it is flown instead, held a moment,
    -- braking when it brakes. It takes the place of the straight-ray safety net below in fights
    -- (in Mission 07's surveyed ground: 1.3% of simulated attack flights crashed against 64%).
    local manOn = ap.goal.kind == "attack" and not ap.vision and Man and ap.myV and Nav and Nav.fast and type(CoopTrace_Line) == "function"
    if manOn then
        if t - (ap.manAt or -100) >= Man.P.every then
            ap.manAt = t
            local V = ap.myV
            local vl = math.sqrt(V[1] ^ 2 + V[2] ^ 2 + V[3] ^ 2)
            if vl > 500 then
                local u = { V[1] / vl, V[2] / vl, V[3] / vl }
                local du = U[1] * u[1] + U[2] * u[2] + U[3] * u[3]
                local Lp = unit({ U[1] - du * u[1], U[2] - du * u[2], U[3] - du * u[3] })
                local want = (ap.combat and ap.combat.speed) or ap.goal.speed or 650
                local mode = (kmh < want - 25) and "throttle" or ((kmh > want + 40) and "brake" or "none")
                local est = planeTurn.est
                Man.ctx.omega = function() return est end
                local a, m, text = Man.filter({ p = { loc.X, loc.Y, loc.Z }, u = u, L = Lp, s = vl / 10, k = clamp(ap.lastPitchCmd or 0, -0.5, 1) },
                    aim, mode, t, Man.ctx)
                ap.manAim, ap.manMode, ap.manText = text and a or nil, text and m or nil, text
                ap.manOk = not (text and text:find("no clear way", 1, true))
                if text then
                    ap.visBlockedAt = t              -- (the "obstacles near" signal for the speed and cloud rules)
                    if text ~= ap.manLogged and t - (ap.manLogAt or -100) > 1.0 then
                        ap.manLogged, ap.manLogAt = text, t
                        event("maneuver", { text = text, kmh = kmh, agl_m = agl or -1 })
                    end
                end
            end
        end
        if ap.manAim then aim = ap.manAim; ap.navText = ap.manText end
    else
        ap.manAim, ap.manMode, ap.manOk = nil, nil, false
    end
    local visionSafety = ap.goal.kind == "attack" and not ap.vision and not manOn
    if (ap.vision or visionSafety) and Vision and ap.myV and Nav and Nav.fast then
        if t - (ap.visAt or -100) > 0.05 then
            ap.visAt = t
            local d, why = Vision.choose({ loc.X, loc.Y, loc.Z }, ap.myV, aim, { horizon = 4.5, need = 3.0, centre = not visionSafety, wide = visionSafety })
            if visionSafety then
                local L = Vision.last
                local sp = math.sqrt(ap.myV[1] ^ 2 + ap.myV[2] ^ 2 + ap.myV[3] ^ 2) / 10
                local need = math.max(sp, 120) * 3.0
                local blocked = L and ((L.wantedFree and L.wantedFree < need) or (L.velFree and L.velFree < need * 0.8))
                if not blocked then d, why = nil, nil
                elseif why then why = "obstacle: " .. why end
            end
            ap.visAim, ap.visWhy = d, why
            if why then ap.visBlockedAt = t end
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
        -- the clearance wanted over the ground ahead: 150 m in a fight; on a "fly to" or a
        -- heading order the order's own floor decides (19 Oct 2026: with a fixed 150 m the
        -- plane could not come down to 115 m for the tunnel, it stayed 280-450 m too high)
        local aheadMin = ap.ceiling and 60 or 150
        if ap.goal.kind == "point" or ap.goal.kind == "heading" then aheadMin = math.max(floor * 1.2, 40) end
        if laneLow then aheadMin = 100 end
        if gunLow then aheadMin = Gun.mod.P.aheadMin end
        recovering = height < floor or alt + ap.vz * 4 < floor * 0.7 or (ahead ~= nil and ahead < aheadMin)
        -- (with the manoeuvre planner flying a way it found clear, the straight lines ahead are
        -- not the test: they cross every wall it is turning away from; only a real emergency,
        -- 60 m over the ground, takes over)
        if manOn and ap.manOk then recovering = height < 60 end
        -- a vertical attack (lanes.lua) points the nose at the ground on purpose: the straight
        -- lines 1-4 s ahead always end in it; the pull-out arc the attack was planned with is
        -- the check instead (the floor stays)
        -- (only for a real dive, nose 30 degrees down or more: shallower, the straight lines are
        -- right, and without them a shallow attack flew into a hill, 20 Oct 2026)
        if ap.vertical and ap.combat and ap.combat.dive and rot.Pitch < -30 then
            local vms = kmh / 3.6 * 10
            local sinDive = math.sin(math.rad(math.max(-rot.Pitch, 0)))
            recovering = height < floor or (rot.Pitch < -5 and height < Lanes.pullNeed(vms, sinDive, planeTurn.est * Lanes.P.dive.pullShare) / 10)
        -- a dive needs room to pull out of: the arc of a 5 g pull from this dive angle at this
        -- speed, plus a second to react, plus the floor (the measured climb rate lags a dive
        -- that is getting steeper)
        elseif not recovering and rot.Pitch < -10 then
            local v = kmh / 3.6
            local need = v * v / (9.81 * 5) * (1 - math.cos(math.rad(-rot.Pitch))) + v * 1.0 + floor * 0.5
            if height < need then recovering = true end
        end
    end
    ap.agl, ap.ahead = agl, ahead
    if recovering then
        local h = unit({ F[1], F[2], 0 })
        -- (score phases, from a dive steeper than 30 degrees: out the shorter way, pulling on
        -- through if the canopy already faces that way; flown with the roll-and-pull mode below)
        if ap.scoreMode and F[3] < -0.5 then
            local d = pullOutAim(F, U)
            h = unit({ d[1], d[2], 0 })
            ap.pullThrough = true
        end
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
    -- Where the time goes (general data for every report): each frame of a fight is put in one
    -- class (combatStep names it; climbing away from the ground overrides it) and its seconds
    -- added up; a "time_split" event every 60 s and when the order ends (tools\run-stats.py)
    if ap.combat then
        local c = ap.combat
        local cls = recovering and "recovery" or (c.splitClass or "other")
        c.split = c.split or {}
        c.split[cls] = (c.split[cls] or 0) + dt
        if t - (c.splitAt or 0) >= 60 then
            c.splitAt = t
            event("time_split", { split = c.split, order_t0 = ap.t0, lanes = c.laneOn or false, kills = c.kills })
        end
    end
    -- The plane's turn rate in hard turns (for the lanes' plans): the velocity's change of
    -- direction while the big-turn mode pulls hard, averaged; started again for another plane
    if ap.myV and ap.prevVturn and dt > 0 and ap.big and (ap.lastPitchCmd or 0) > 0.8 and not recovering then
        local a, b = ap.prevVturn, ap.myV
        local la, lb = math.sqrt(dot(a, a)), math.sqrt(dot(b, b))
        if la > 500 and lb > 500 then
            local rate = math.acos(clamp(dot(a, b) / (la * lb), -1, 1)) / dt
            if rate > planeTurn.est * 0.5 and rate < math.rad(120) then
                planeTurn.est = planeTurn.est + 0.02 * (rate - planeTurn.est)
                planeTurn.n = planeTurn.n + 1
            end
        end
    end
    ap.prevVturn = ap.myV and { ap.myV[1], ap.myV[2], ap.myV[3] } or nil
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

    -- An aim more than 90 degrees off to the side or behind (a turn-back) is flown as a level
    -- turn the shorter way round: toward a point 90 degrees round from the nose, keeping the
    -- aim's climb or descent. Behind and a little below, the aim asked for an inverted pull (a
    -- split-S), the "no split-S near the ground" rule refused it, and the roll flipped from side
    -- to side without pulling: the plane hung at 90 degrees of bank and climbed instead of
    -- turning (19 Oct 2026, the first lanes run: 100 s of turn-backs that never came round).
    local precise0 = ap.goal.kind == "route" or ap.vision
    -- (not in a vertical attack: its aim behind and below or above is meant as it is)
    if not precise0 and not recovering and not ap.vertical then
        local fh = unit({ F[1], F[2], 0 })
        local ah, al = unit({ aim[1], aim[2], 0 })
        if al > 0.05 and fh[1] * ah[1] + fh[2] * ah[2] < 0 then
            local crossZ = fh[1] * ah[2] - fh[2] * ah[1]          -- > 0: the aim's heading is to the right
            if math.abs(crossZ) > 0.08 or not ap.turnSign then ap.turnSign = crossZ >= 0 and 1 or -1 end
            local s = ap.turnSign
            aim = unit({ -fh[2] * s, fh[1] * s, clamp(aim[3], -0.15, 0.15) })
            ap.turnBack = true
        else
            ap.turnBack = false
        end
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
    -- score phases turn harder (the owner, 19 Oct 2026: "move and maneuver more aggressively";
    -- the score-race plan's fix 5): the big turn from 8 degrees off (otherwise 12), full
    -- aileron to the bank, a full pull sooner, and stiffer small corrections near the targets
    local hard = ap.scoreMode and ap.goal.kind == "attack"
    local bigOn, bigOff = 12, 6
    if hard then bigOn, bigOff = 8, 4 end
    -- the heading still to turn (+ = right): the big turn is for changing heading; a climb or a
    -- dive straight ahead is the small-corrections mode's (it pitches the nose up or down)
    local fhx, fhy = F[1], F[2]
    local fhl = math.sqrt(fhx * fhx + fhy * fhy)
    local ahx, ahy = aim[1], aim[2]
    local ahl = math.sqrt(ahx * ahx + ahy * ahy)
    local dpsi = 0
    if fhl > 0.05 and ahl > 0.05 then
        dpsi = math.deg(math.atan(fhx * ahy - fhy * ahx, fhx * ahx + fhy * ahy))
    end
    -- high up (over 1,500 m) a big change of pitch is a big turn too (rolled and pulled, a split-S
    -- if need be); near the ground the small-corrections mode pitches the nose up or down
    local highUp = math.min(agl or alt, alt) >= 1500
    -- a vertical attack (lanes.lua, planned with the pull-out's height): rolled and pulled like
    -- high up, at any height
    local vertical = (ap.vertical and not recovering) or (recovering and ap.pullThrough)
    if vertical then highUp = true end
    if precise then
        ap.big = false
    elseif vertical then
        ap.big = off > 4
    elseif ap.big then
        if math.abs(dpsi) < bigOff and (not highUp or off < bigOff + 6) then ap.big = false end
    elseif math.abs(dpsi) > bigOn or (highUp and off > 25) then
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
    elseif ap.big and highUp then
        -- High up: roll the aim above the canopy and pull (any direction, a split-S included)
        rollCmd = hard and pd("bank", bankErr, dt, 1 / 22, 1 / 110) or pd("bank", bankErr, dt, 1 / 35, 1 / 160)
        -- (pulling already while the roll is still 50-70 degrees out: the owner, watching on
        -- 19 Oct 2026, "very wide turns even when high up ... take the tightest possible turn")
        if math.abs(bankErr) < 50 and elev > 0 then pitchCmd = clamp(elev / (hard and 4 or 8), -1, 1)
        elseif math.abs(bankErr) < 70 and elev > 0 then pitchCmd = 0.6 else pitchCmd = 0 end
        yawCmd = 0
        ap.prevErr.level, ap.prevErr.elev, ap.prevErr.side = nil, nil, nil
    elseif ap.big then
        -- Bank-to-turn (19 Oct 2026): the bank comes from the heading still to turn, at most
        -- 80 degrees (85 when the aim is below the flight path, so the nose slices down; less,
        -- down to 55, when it is above), and the pull comes once the bank is within 30 degrees
        -- of that. Until then the bank was whatever put the aim above the canopy: for an aim a
        -- little below the nose that meant rolling past vertical, which the "no split-S near the
        -- ground" rule below undid, so the plane flipped from wing to wing without pulling (the
        -- third lanes run: a minute at 1,000 m, never turning onto the targets). With the bank
        -- held under 90 degrees the two rules no longer fight.
        local dg = math.deg(math.asin(clamp(aim[3], -1, 1)) - math.asin(clamp(F[3], -1, 1)))
        local mag = hard and 80 or 72
        -- (wanting lower with 400 m of air or more: a slicing turn, banked past vertical up to
        -- 110 degrees, so the pull carries the nose down; 19 Oct 2026, the seventh lanes test:
        -- every kind of hard turn climbed 2-19 m/s on average, only straight flight came down,
        -- and the lanes were flown a median 570 m above the pass height)
        local roomy = math.min(agl or alt, alt) > 400
        if dg < 0 then mag = math.min(mag + clamp(-dg * 1.5, 0, 30), roomy and 110 or 88)
        else mag = math.max(mag - clamp(dg * 1.5, 0, 25), 55) end
        local bankCmd = (dpsi >= 0 and 1 or -1) * math.min(mag, math.abs(dpsi) * 3.2)
        local rollErr = wrap180(bankCmd - rot.Roll)
        rollCmd = hard and pd("bank", rollErr, dt, 1 / 22, 1 / 110) or pd("bank", rollErr, dt, 1 / 30, 1 / 140)
        -- the pull: full from 8 degrees of heading still to turn once the bank is within 30
        -- degrees of the wanted one, and already 0.7 while rolling in on the right side (the
        -- owner, 19 Oct 2026: "take the tightest possible turn towards a given target basically
        -- all the time"; the plane pulled in only 55% of its hard-turn time)
        if math.abs(rollErr) < 30 then pitchCmd = clamp(math.abs(dpsi) / 8, 0.4, 1)
        elseif math.abs(rollErr) < 60 and rot.Roll * bankCmd > 0 and math.abs(rot.Roll) > 15 then pitchCmd = 0.7
        else pitchCmd = 0 end
        yawCmd = 0
        ap.bankCmd = bankCmd
        ap.prevErr.level, ap.prevErr.elev, ap.prevErr.side = nil, nil, nil
        -- No split-S near the ground (19 Oct 2026, Mission 04: upside down at 1,080 m after a
        -- missile break, the turn logic pulled through the bottom and the plane hit the ground
        -- in a 60 degree dive at 880 km/h): with the lift pointing below the horizon and less
        -- than 1,500 m of air, roll upright first and pull afterwards.
        -- (past vertical as far as the slicing turn's 110 degrees while there are 400 m of air)
        local splitLim = (math.min(agl or alt, alt) > 400) and -0.4 or -0.1
        if U[3] < splitLim and math.min(agl or alt, alt) < 1500 then
            pitchCmd = 0
            rollCmd = clamp(-rot.Roll / 25, -1, 1)
        end
    else
        local g = (hard and ap.combat and (ap.combat.lastDist or 99999) < 3000) and 1.4 or 1.0
        rollCmd = pd("level", -rot.Roll + clamp(side * 3, -35, 35), dt, g / 30, g / 140)
        pitchCmd = pd("elev", elev, dt, g / 6, g / 25)
        yawCmd = pd("side", side, dt, g / 3, g / 20)
        ap.prevErr.bank = nil
    end
    -- upside down near the ground: roll first (not in a steep dive's pull-through: the canopy
    -- already faces the way out there)
    if recovering and math.abs(rot.Roll) > 90 and not ap.pullThrough then pitchCmd = 0 end

    -- Energy floor (every mode): below 450 km/h a hard pull or the high-G turn stalls the
    -- plane (18 Oct 2026, Mission 14 base attack: down to 146 km/h, then into the ground)
    -- (in a vertical attack 380: the top of a loop is slow by nature, and the owner, 20 Oct
    -- 2026: "let it be more aggressive and risky with turning")
    local slow = kmh < (vertical and 380 or 450)
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
    ap.lastPitchCmd = pitchCmd
    -- ...and the high-G turn for any big turn over 25 degrees above 420 km/h, in every fight
    -- (the owner, 19 Oct 2026: "aggressively hunt down that lock at maximum speed and
    -- ferocity"; until then score phases only, over 45 degrees above 450 km/h)
    if ap.goal.kind == "attack" and ap.big and (math.abs(dpsi) > 25 or (vertical and off > 20)) and kmh > (vertical and 380 or 420) and not recovering then
        local has = false
        for _, k in ipairs(extraKeys or {}) do if k == KEY.high_g then has = true end end
        if not has then extraKeys = extraKeys or {}; extraKeys[#extraKeys + 1] = KEY.high_g end
    end
    local speed = (ap.combat and ap.combat.speed) or ap.goal.speed or 650
    -- the manoeuvre planner braking (its plan flies slower: tighter turns, more time)
    if ap.manMode == "brake" then speed = math.min(speed, 380) end
    -- a vertical attack: full power up and over, braking to 450 km/h on the way down so the
    -- pull-out stays tight (20 Oct 2026: unbraked, the first dives gathered speed, the pull-out
    -- came at 480-660 m, before the planned shot, two times in three)
    if vertical and ap.combat and ap.combat.dive then speed = (ap.combat.dive.phase == 0) and 2000 or 450 end
    -- Obstacles close ahead (the vision safety net in a fight): slow to 500 km/h for 3 s after the
    -- last one, braking, so the turns away are tighter and come in time (20 Oct 2026, Mission 07's
    -- first attempt: 75 s in, flying 540-830 km/h under an 817 m cloud base among cliffs that
    -- rise into the clouds, the net reported a blocked way six times in 13 s and the plane hit a
    -- rock face anyway)
    -- (the next attempt still went in at 830 km/h between reports and hit a pillar 3 minutes in:
    -- terrain like that is all around, so the caution lasts 20 s after the last report, at 550)
    -- (with the manoeuvre planner on, 4 s: it flies its own brake when its look-ahead needs it,
    -- and its every adjustment counts as a report, so in rugged ground the 20 s cap held the
    -- plane at 550 km/h nearly all the time; the owner, 20 Oct 2026: safety at about the
    -- minimum plus 10%, more skill and less timidity)
    if ap.goal.kind == "attack" and ap.visBlockedAt and t - ap.visBlockedAt < (manOn and 4 or 20) then speed = math.min(speed, 550) end
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
    elseif ap.goal.kind == "attack" and ap.big and math.abs(dpsi) > 45 and kmh > 850 then
        keys[#keys + 1] = KEY.brake                   -- into a hard turn too fast: brake, the turn tightens
    elseif kmh < speed - 25 then keys[#keys + 1] = KEY.throttle elseif kmh > speed + 40 then keys[#keys + 1] = KEY.brake end
    for _, k in ipairs(extraKeys or {}) do keys[#keys + 1] = k end
    -- this plane's speed changes, learned in flight for the manoeuvre planner: what was pressed
    -- in the frame before and what the speed did since, by climb angle
    if Man and ap.myV and ap.prevKmhAt and t > ap.prevKmhAt then
        local V = ap.myV
        local vl = math.sqrt(V[1] ^ 2 + V[2] ^ 2 + V[3] ^ 2)
        if vl > 500 then
            Man.learn(ap.prevSpeedMode or "none", math.asin(clamp(V[3] / vl, -1, 1)), (kmh - ap.prevKmh) / 3.6 / (t - ap.prevKmhAt), t - ap.prevKmhAt, ap.prevKmh / 3.6)
        end
    end
    ap.prevKmh, ap.prevKmhAt = kmh, t
    ap.prevSpeedMode = "none"
    for _, k in ipairs(keys) do
        if k == KEY.high_g then ap.prevSpeedMode = "high-G"; break end
        if k == KEY.throttle then ap.prevSpeedMode = "throttle" elseif k == KEY.brake then ap.prevSpeedMode = "brake" end
    end
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
    -- fly heading 90 alt 1500 [speed 650] [for 30] [floor 300]; fly attack [score] [focus a,b]
    -- fly to <x> <y> <z>   (game units)         fly stop
    if args[1] == "stop" then
        finalSplit("stop")
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
        elseif k == "score" then opts.scoreMode = true; i = i + 1
        elseif k == "lanes" then opts.lanes = args[i + 1] ~= "off"; i = i + 2
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
    finalSplit("replaced by a new order")
    local p0 = playerPlane()
    local home = p0 and p0:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
    ap = { goal = goal, t0 = now(), frames = 0, recoverFrames = 0, lastLog = -1, prevErr = {}, rate = {},
           floor = opts.floor, duration = opts.duration, big = false, home = { X = home.X, Y = home.Y, Z = home.Z },
           ceiling = opts.ceiling or (Gim and Gim.ceiling) or nil, navFloor = opts.navFloor,
           cloudBase = opts.cloudBase, focus = opts.focus, vision = opts.vision, scoreMode = opts.scoreMode, lanes = opts.lanes,
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
        -- a new fight: kills are counted afresh (an enemy of the same name may come back after
        -- a retry; see forgetWorld)
        for k in pairs(creditedKills) do creditedKills[k] = nil end
        for k in pairs(firedAt) do firedAt[k] = nil end
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
    laneCands, airPick, scorePts = {}, nil, nil
    activeSeen, activationStarted = {}, false
    for k in pairs(infoCache) do infoCache[k] = nil end
    for k in pairs(lockCache) do lockCache[k] = nil end
    -- (and the kills already counted, by name: after a restart from a checkpoint the enemies come
    -- back under the same names, and on 20 Oct 2026 a second attempt counted almost none of its
    -- kills, so the rates the moves are judged by read zero)
    for k in pairs(creditedKills) do creditedKills[k] = nil end
    for k in pairs(firedAt) do firedAt[k] = nil end
    if Aware then Aware.reset(); Aware.fastReady = false end
    if Gim then Gim.reset() end
    if Nav then Nav.fast = false end
    if ap then
        if ap.combat then
            local c = ap.combat
            c.target, c.pref, c.scanTarget, c.lastPursuer, c.pursuer, c.prevTL, c.tv = nil, nil, nil, nil, nil, nil, nil
            c.prefAt, c.scanAt = -100, -100
            c.laneTg, c.lanePlan, c.laneOn, c.lanePickName, c.scan, c.reloadAt = nil, nil, false, nil, nil, nil
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
        if name ~= "vision" and name ~= "route" and name ~= "lanes" and name ~= "gunnery" then log("module: give 'vision', 'route', 'lanes' or 'gunnery'") return end
        package.loaded[name] = nil
        local ok, m = pcall(function() return require(name)({ log = log, event = event, now = now }) end)
        if not ok then log("module: " .. name .. ".lua did not load: " .. tostring(m)) return end
        if name == "vision" then Vision = m elseif name == "lanes" then Lanes = m elseif name == "gunnery" then Gun.mod = m else Route = m end
        log("module: " .. name .. ".lua loaded again")
    end,
    -- "targets [all]": every enemy game object (active ones unless "all") with what the bot reads
    -- from the game about it: native class and kind, position, points (KillBountyScore), health,
    -- HUD box, permission to engage, mission target, lock-on mark; plus the plane, and the
    -- standard missile's numbers both from its class and live (parts change them). Written as
    -- JSON to the pilot folder: a test case for tools\lane-sim.py, and a record of the mission's
    -- targets for anyone testing a modified mission.
    targets = function(args)
        local p = playerPlane()
        local me = p and p:K2_GetActorLocation()
        local rows = {}
        for _, o in ipairs(FindAllOf("GameObject") or {}) do
            pcall(function()
                if o:GetFaction() ~= 0 or not o:IsAlive() then return end
                local act = o.bIsActivated == true
                if not act and args[1] ~= "all" then return end
                local l = o:K2_GetActorLocation()
                local info = objInfo(o)
                if info.bounty == nil then
                    local okB, b = pcall(function() return o.KillBountyScore end)
                    info.bounty = okB and tonumber(b) or 0
                end
                local tg = false
                pcall(function() tg = o:IsTGT() end)
                local li = lockInfo(o)
                local k = gameKind(o)
                rows[#rows + 1] = { name = objName(o), class = classOf(o), native = info.native or "?", kind = k,
                                    air = k == "plane" or k == "large" or k == "agile", x = l.X, y = l.Y, z = l.Z,
                                    bounty = info.bounty, hp = call(o, "GetHealth") or -1, max_hp = call(o, "GetMaxHealth") or -1,
                                    active = act, hud_box = o.bShowHUDBox ~= false, engage = o.bPermissionToEngage ~= false,
                                    tgt = tg == true, lockable = li.lockable == true, mark = li.mark or -1,
                                    turn = info.turnLimit or -1, top_kmh = info.maxKmh or -1 }
            end)
        end
        local W = {}
        local wa = p and weapons(p)
        if wa then
            pcall(Aware.readWeapons, wa)
            local m = Aware and Aware.weapons and Aware.weapons.main
            if m then
                W = { class = m.class, cone_deg = m.LockonAngle, range = m.LockonRange, load_s = m.LoadTime, loaded = m.MaxLoadedCount,
                      damage = m.Damage, mspeed = m.SpeedMaximum }
            end
            -- the armed weapon's live numbers (parts change lock range, reload, lock speed)
            pcall(function()
                local wp = wa:GetArmedWeaponParameters()
                if wp and wp:IsValid() then
                    W.live_class = objName(wp)
                    for _, f in ipairs({ "LockonRange", "LockonAngle", "LoadTime", "MaxLoadedCount", "Damage", "LockonInitialSpeed",
                                         "LockonMaximumSpeed", "LockonAccelerationTime", "LockonDelayBetweenSeekers", "SelectionAssistLockOnTime" }) do
                        local okF, v = pcall(function() return wp[f] end)
                        if okF and type(v) == "number" then W["live_" .. f] = v end
                    end
                end
            end)
        end
        local path = OUT .. "\\targets-" .. os.date("%H%M%S") .. ".json"
        local f = io.open(path, "w")
        if f then
            f:write(json({ level = missionLevel() or "?", plane = me and { x = me.X, y = me.Y, z = me.Z } or {}, weapon = W, targets = rows }), "\n")
            f:close()
        end
        local wparts = {}
        for k2, v in pairs(W) do wparts[#wparts + 1] = k2 .. "=" .. tostring(v) end
        table.sort(wparts)
        log(string.format("targets: %d enemies into %s; weapon: %s", #rows, path, table.concat(wparts, ", ")))
    end,
    -- "lanes set horizon 10 passAgl 250": change the lane planner's parameters in flight
    lanes = function(args)
        if not Lanes then log("lanes: lanes.lua is not loaded") return end
        if args[1] == "set" then
            for i = 2, #args - 1, 2 do
                local k, v = args[i], tonumber(args[i + 1])
                if Lanes.P[k] ~= nil and v then Lanes.P[k] = v; log(string.format("lanes: %s = %s", k, tostring(v))) end
            end
        end
        local parts = {}
        for k, v in pairs(Lanes.P) do if type(v) == "number" then parts[#parts + 1] = k .. "=" .. tostring(v) end end
        table.sort(parts)
        log("lanes: " .. table.concat(parts, ", "))
    end,
    -- "guntest on [object name]" / "guntest off": the gun measurement (gun only, no lanes,
    -- attack runs carried in to 400 m; with a name, that object is the target even without a
    -- HUD box); "guntest" alone reports what the gun has done so far
    guntest = function(args)
        if args[1] == "on" then Gun.test = { name = args[2] }
        elseif args[1] == "off" then Gun.test = nil end
        local S = Gun.stats
        log(string.format("guntest: %s; %d bursts, %d kills, %.0f damage in %.1f s of firing (%.1f a second)",
            Gun.test and ("on" .. (Gun.test.name and (", at " .. Gun.test.name) or "")) or "off",
            S.bursts, S.kills, S.dmg, S.secs, S.dmg / math.max(S.secs, 0.01)))
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
local function miniGameWatch()
    if not skipMiniGames or not phaseName then return end
    local pl = phaseName:lower()
    if not (pl:find("landing", 1, true) or pl:find("refuel", 1, true) or pl:find("supply", 1, true)) then skipState.tries = 0; return end
    if skipState.tries >= 20 or now() - (skipState.at or -100) < 6 then return end
    skipState.tries = skipState.tries + 1
    skipState.at = now()
    local m = mission()
    local ok = m and pcall(function() m:SkipMiniGame() end)
    log(string.format("  %s: asking the game to skip the mini-game (try %d, %s)", phaseName, skipState.tries, ok and "sent" or "failed"))
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
