-- Common/SwingTimer.lua
-- Integrates LibClassicSwingTimerAPI to provide swing timer data.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local SwingTimerLib = LibStub("LibClassicSwingTimerAPI", true)

-- Create the SwingTimer module *on the main addon object*
local SwingTimer = WRA:NewModule("SwingTimer")
WRA.SwingTimer = SwingTimer -- Make accessible via WRA.SwingTimer

-- WoW API & Lua shortcuts
local GetTime = GetTime
local UnitAttackSpeed = UnitAttackSpeed
local tostring = tostring -- Added shortcut

-- Check if the library loaded and create dummy functions if not
local isLibAvailable = SwingTimerLib ~= nil
if not isLibAvailable then
    -- Use WRA's print function now that WRA object is available
    WRA:PrintError("Warning: LibClassicSwingTimerAPI not found! Swing timer functions will return default values.")
end

-- --- Public API Functions ---

-- Get remaining time until the next main-hand swing
-- @return number: Seconds remaining, or 999 if unavailable/off
function SwingTimer:GetMainHandRemaining()
    if not isLibAvailable then return 999 end
    local speed, expirationTime = SwingTimerLib:SwingTimerInfo("mainhand")
    if speed and speed > 0 and expirationTime and expirationTime > 0 then
        local remaining = expirationTime - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 999 -- Return large value if timer isn't active or lib missing
end

-- Get remaining time until the next off-hand swing
-- @return number: Seconds remaining, or 999 if unavailable/off
function SwingTimer:GetOffHandRemaining()
     if not isLibAvailable then return 999 end
    local speed, expirationTime = SwingTimerLib:SwingTimerInfo("offhand")
     if speed and speed > 0 and expirationTime and expirationTime > 0 then
        local remaining = expirationTime - GetTime()
        return remaining > 0 and remaining or 0
    end
    return 999 -- Return large value if timer isn't active or lib missing
end

-- Get main-hand swing timer duration (speed)
function SwingTimer:GetMainHandSpeed()
     if not isLibAvailable then return 0 end
    local speed = SwingTimerLib:SwingTimerInfo("mainhand")
    return speed or 0
end

-- Get off-hand swing timer duration (speed)
function SwingTimer:GetOffHandSpeed()
     if not isLibAvailable then return 0 end
    -- LibClassicSwingTimerAPI doesn't seem to expose offhand speed directly via SwingTimerInfo
    -- Fallback to WoW API UnitAttackSpeed
    local _, _, _, offSpeed = UnitAttackSpeed("player")
    return offSpeed or 0
end


-- --- Module Lifecycle ---
function SwingTimer:OnInitialize()
    -- self.WRA = WRA -- WRA is available via closure
    WRA:PrintDebug("SwingTimer Initialized (Lib Available: " .. tostring(isLibAvailable) .. ")")
end

function SwingTimer:OnEnable()
    WRA:PrintDebug("SwingTimer Enabled")
    -- LibClassicSwingTimerAPI handles its own events, nothing needed here usually
end

function SwingTimer:OnDisable()
    WRA:PrintDebug("SwingTimer Disabled")
end
