-- CoopSecondCopyMod  (Ace Combat 7 co-op workbench, 17 Oct 2026)
--
-- Question it helps answer: can the SECOND copy of the game, which gets no Steam
-- identity, be nudged past the title screen without touching save data?
--
-- Both copies of the game share this ue4ss\Mods folder, so the first thing the mod does
-- is work out which copy it is running in. tools\start-copy.ps1 gives the second copy the
-- user folder C:\AC7-Coop-Game\UserProfile2; in any other copy (first copy, or the real
-- profile) the mod logs one line and does nothing else.
--
-- In the second copy it:
--   1. writes down every call to the game's save and load functions (name, time, values
--      passed, value returned), so the steps right before the crash are on record. The
--      lines go to UE4SS.log (shared by both copies) and to the second copy's own file
--      C:\AC7-Coop-Game\UserProfile2\coop-second-copy.log;
--   2. once the title screen widget exists, calls the game's own developer save switches
--      (ToggleSaveLoadSimulatedMode, ToggleSaveLoadUIIgnore, SetSaveLoadSimulatedStatus)
--      and records whether they could be called at all.
--
-- The mod never reads, writes, moves or deletes a save file itself.

local TAG = "[CoopSecondCopy] "
local profile = os.getenv("USERPROFILE") or ""
local isSecondCopy = string.find(string.lower(profile), "userprofile2", 1, true) ~= nil

local logFile = nil
local function log(msg)
    print(TAG .. msg .. "\n")
    if logFile then
        logFile:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. msg .. "\n")
        logFile:flush()
    end
end

log("user folder for this copy: " .. profile)
if not isSecondCopy then
    log("this is the FIRST copy (or the real profile): mod inactive")
    return
end

logFile = io.open(profile .. "\\coop-second-copy.log", "a")
log("this is the SECOND copy: watching save and load calls")

-- Turn a hook parameter into readable text without ever throwing.
local function show(param)
    local ok, v = pcall(function() return param:get() end)
    if not ok then return "?" end
    if type(v) ~= "userdata" then return tostring(v) end
    local ok2, s = pcall(function() return v:ToString() end)
    if ok2 and type(s) == "string" then return s end
    ok2, s = pcall(function() return v:GetFullName() end)
    if ok2 and type(s) == "string" then return s end
    return "<" .. tostring(v) .. ">"
end

local function describe(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = show((select(i, ...))) end
    return table.concat(parts, ", ")
end

local lineBudget = {}
local function watch(fn, limit)
    local ok, err = pcall(function()
        RegisterHook(fn, function(self, ...)
            lineBudget[fn] = (lineBudget[fn] or 0) + 1
            if lineBudget[fn] <= (limit or 50) then
                log("call  " .. fn .. "  (" .. describe(...) .. ")")
            end
        end, function(self, ...)
            if (lineBudget[fn] or 0) <= (limit or 50) then
                log("done  " .. fn .. "  (" .. describe(...) .. ")")
            end
        end)
    end)
    if ok then log("hooked " .. fn) else log("could not hook " .. fn .. ": " .. tostring(err)) end
    return ok
end

-- Native functions: these exist from the start.
local nativeFunctions = {
    "/Script/Nimbus.NimbusGameInstance:AsyncLoadAccountSettings",
    "/Script/Nimbus.NimbusGameInstance:AsyncLoadGameplaySettings",
    "/Script/Nimbus.NimbusGameInstance:AsyncLoadOnlineData",
    "/Script/Nimbus.NimbusGameInstance:AsyncSaveAccountSettings",
    "/Script/Nimbus.NimbusGameInstance:AsyncSaveGameplaySettings",
    "/Script/Nimbus.NimbusGameInstance:AsyncSaveOnlineData",
    "/Script/Nimbus.NimbusGameInstance:SetCurrentGameSaveSlot",
    "/Script/Engine.GameplayStatics:SaveGameToSlot",
    "/Script/Engine.GameplayStatics:LoadGameFromSlot",
    "/Script/Engine.GameplayStatics:DoesSaveGameExist",
    "/Script/Engine.GameplayStatics:DeleteGameInSlot",
    "/Script/Engine.GameplayStatics:CreateSaveGameObject",
}
for _, fn in ipairs(nativeFunctions) do watch(fn) end

-- Blueprint functions of the title screen: they only exist once the title screen has
-- loaded, so keep looking every two seconds until they do.
-- (The title screen's event graph itself cannot be hooked: UE4SS reports it has no
-- function pointer. Its Construct event can.)
local pendingBlueprint = {
    ["/Game/UI/Menu/Boot/MainTitle.MainTitle_C:Construct"] = true,
    ["/Game/UI/Menu/CommonWidget/animation/SaveLoad.SaveLoad_C:Construct"] = true,
}
local titleClass = "/Game/UI/Menu/Boot/MainTitle.MainTitle_C"

-- The developer save switches, tried once, a few seconds after the title screen is up.
-- Must run on the game thread.
local function tryDeveloperSwitches()
    local cm = FindFirstOf("NimbusCheatManager")
    if not cm or not cm:IsValid() then
        cm = FindFirstOf("CheatManager")
        if not cm or not cm:IsValid() then
            log("no cheat manager object exists at the title screen; switches not tried")
            return
        end
    end
    log("cheat manager object: " .. cm:GetFullName())
    local calls = {
        { "ToggleSaveLoadSimulatedMode",   function() return cm:ToggleSaveLoadSimulatedMode() end },
        { "ToggleSaveLoadUIIgnore",        function() return cm:ToggleSaveLoadUIIgnore() end },
        { "SetSaveLoadSimulatedStatus(0)", function() return cm:SetSaveLoadSimulatedStatus(0) end },
    }
    for _, c in ipairs(calls) do
        local ok, err = pcall(c[2])
        if ok then log("called " .. c[1] .. " (no error)") else log("could not call " .. c[1] .. ": " .. tostring(err)) end
    end
end

local titleSeenAt = nil
local switchesTried = false
LoopAsync(2000, function()
    ExecuteInGameThread(function()
        for fn, pending in pairs(pendingBlueprint) do
            if pending then
                local obj = StaticFindObject(fn)
                if obj and obj:IsValid() then
                    pendingBlueprint[fn] = false
                    watch(fn, 200)
                end
            end
        end
        if not titleSeenAt then
            local cls = StaticFindObject(titleClass)
            if cls and cls:IsValid() then
                titleSeenAt = os.clock()
                log("title screen class is loaded; developer switches will be tried in a few seconds")
            end
        end
        if titleSeenAt and not switchesTried and os.clock() - titleSeenAt > 3 then
            switchesTried = true
            tryDeveloperSwitches()
        end
    end)
    local allDone = switchesTried
    for _, pending in pairs(pendingBlueprint) do if pending then allDone = false end end
    return allDone
end)

log("ready")
