-- CoopNetCheckMod (Ace Combat 7 co-op workbench, 18 Oct 2026)
--
-- Tiny check for the CoopNetMod C++ add-on: once a second, print how many UDP packets the
-- add-on has received and what the newest one says. Works at the title screen; nothing
-- in the game is touched. Start tools\coop-net-sender.py on this PC to feed it packets.

local TAG = "[CoopNetCheck] "
local function log(msg) print(TAG .. msg .. "\n") end

if type(CoopNet_Count) ~= "function" then
    log("CoopNet_Count is missing: the CoopNetMod C++ add-on did not register its functions in this Lua mod")
    return
end

log("CoopNet functions are present; " .. tostring(CoopNet_Status()))

local last = 0
local ticks = 0
LoopAsync(1000, function()
    ticks = ticks + 1
    local ok, err = pcall(function()
        local n = CoopNet_Count()
        local line, seq, age = CoopNet_Latest()
        if line then
            log(string.format("tick %d: %d packets so far (+%d in the last second); newest #%d is %.0f ms old: %s",
                ticks, n, n - last, seq, age, line))
        elseif ticks % 10 == 1 then
            log(string.format("tick %d: no packets yet (%s)", ticks, tostring(CoopNet_Status())))
        end
        last = n
    end)
    if not ok then log("check failed: " .. tostring(err)) end
    return false
end)
