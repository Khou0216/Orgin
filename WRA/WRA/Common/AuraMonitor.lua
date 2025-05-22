-- wow addon/WRA/Common/AuraMonitor.lua
local addonName, _ = ... -- Get addon name, don't rely on addonTable
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Create the AuraMonitor module *on the main addon object*
local AuraMonitor = WRA:NewModule("AuraMonitor", "AceEvent-3.0", "AceTimer-3.0")
-- Get Locale safely after WRA object is confirmed
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- Lua shortcuts
local GetTime = GetTime
local UnitAura = UnitAura
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit -- Important for comparing event unit vs monitored unit
local pairs = pairs
local wipe = wipe
local type = type -- Added type shortcut

-- Internal storage for tracked auras
-- Structure: trackedAuras[unitToken][spellID] = { expirationTime, count, casterIsPlayer, isBuff }
-- Simplified structure for faster lookups. Store only what's needed for API functions.
local trackedAuras = {
    player = {},
    target = {},
    -- focus = {}, -- Add if needed
    -- pet = {},   -- Add if needed
}

-- Units to monitor
local unitsToMonitor = { "player", "target" } -- Add "focus", "pet" if needed

-- Throttling for UNIT_AURA updates
local auraUpdateThrottle = 0.1 -- Seconds between processing aura updates for a unit
local auraUpdateScheduled = {} -- { [unitToken] = timerHandle }

function AuraMonitor:OnInitialize()
    WRA:PrintDebug("AuraMonitor Initialized.") -- Use WRA's PrintDebug
    for _, unit in pairs(unitsToMonitor) do
        trackedAuras[unit] = {}
        auraUpdateScheduled[unit] = nil
    end
end

function AuraMonitor:OnEnable()
    WRA:PrintDebug("AuraMonitor Enabled.")
    -- Register UNIT_AURA event for monitored units
    self:RegisterEvent("UNIT_AURA", "HandleUnitAuraUpdate")
    -- Register events for when monitored units change (e.g., target change)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "ScheduleUnitUpdate")
    -- self:RegisterEvent("PLAYER_FOCUS_CHANGED", "ScheduleUnitUpdate") -- If tracking focus
    -- self:RegisterEvent("UNIT_PET", "HandlePetChange") -- If tracking pet

    -- Perform initial scan for all monitored units
    for _, unit in pairs(unitsToMonitor) do
        self:ScheduleUnitUpdate(nil, unit) -- Schedule initial scan
    end
end

function AuraMonitor:OnDisable()
    WRA:PrintDebug("AuraMonitor Disabled.")
    self:UnregisterAllEvents()
    -- Cancel any pending timers
    for unit, timerHandle in pairs(auraUpdateScheduled) do
        if timerHandle then
            self:CancelTimer(timerHandle, true) -- Silent cancel
            auraUpdateScheduled[unit] = nil
        end
    end
    -- Clear tracked data
    for unit, _ in pairs(trackedAuras) do
        wipe(trackedAuras[unit])
    end
end

-- Event handler for UNIT_AURA
function AuraMonitor:HandleUnitAuraUpdate(event, unit)
    -- Check if the event is for a unit we are monitoring
    local monitoredUnitToken = nil
    for _, token in pairs(unitsToMonitor) do
        -- Important: Use UnitIsUnit to correctly map event unit to monitored token
        if UnitIsUnit(unit, token) then
            monitoredUnitToken = token
            break
        end
    end

    if monitoredUnitToken then
        -- Schedule an update for this unit using the canonical token (e.g., "player", "target")
        self:ScheduleUnitUpdate(event, monitoredUnitToken)
    end
end

-- Schedule or reschedule an aura scan for a specific unit (throttled)
function AuraMonitor:ScheduleUnitUpdate(event, unit)
     -- Ensure unit is valid before scheduling
     if not unit or not trackedAuras[unit] then return end

     -- If an update is already scheduled, don't reschedule. Let the existing one run.
     -- This prevents excessive rescheduling if UNIT_AURA fires rapidly.
     if auraUpdateScheduled[unit] then
         return
     end

     -- Schedule the actual update function after the throttle period
     auraUpdateScheduled[unit] = self:ScheduleTimer("UpdateAurasForUnit", auraUpdateThrottle, unit)
end

-- Function to actually scan and update auras for a specific unit
function AuraMonitor:UpdateAurasForUnit(unit)
    -- Clear the scheduled flag for this unit
    auraUpdateScheduled[unit] = nil

    -- Ensure unit exists and is monitored before scanning
    if not unit or not trackedAuras[unit] or not UnitExists(unit) then
        if trackedAuras[unit] then wipe(trackedAuras[unit]) end -- Wipe data if unit disappears
        return
    end

    -- Clear previous aura data for this unit
    wipe(trackedAuras[unit])
    local unitAuras = trackedAuras[unit] -- Reference the table directly
    local now = GetTime()

    -- Scan Buffs ("HELPFUL")
    local index = 1
    while true do
        -- name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, castByPlayer
        -- WotLK API indices might differ slightly, but spellID is usually late. Check isPlayer/castByPlayer.
        local name, _, count, _, _, expirationTime, caster, _, _, spellID, _, _, castByPlayer = UnitAura(unit, index, "HELPFUL")
        if not name then break end -- No more buffs

        -- Store simplified info if spellID is valid
        if spellID and spellID ~= 0 then
            unitAuras[spellID] = {
                expirationTime = expirationTime or 0,
                count = count or 1,
                -- Check if castByPlayer flag exists and is true, otherwise fallback to caster == "player" or "vehicle"
                casterIsPlayer = castByPlayer or (caster == "player" or caster == "vehicle"),
                isBuff = true,
            }
        end
        index = index + 1
    end

    -- Scan Debuffs ("HARMFUL")
    index = 1
    while true do
        local name, _, count, _, _, expirationTime, caster, _, _, spellID, _, _, castByPlayer = UnitAura(unit, index, "HARMFUL")
        if not name then break end -- No more debuffs

        if spellID and spellID ~= 0 then
             unitAuras[spellID] = {
                expirationTime = expirationTime or 0,
                count = count or 1,
                casterIsPlayer = castByPlayer or (caster == "player" or caster == "vehicle"),
                isBuff = false, -- Mark as debuff
            }
        end
        index = index + 1
    end

    -- WRA:PrintDebug("Auras updated for unit: " .. unit .. " Found: " .. (WRA.Utils and WRA.Utils:CountTable(unitAuras) or "?") ) -- Debugging if Utils exists
end


--[[-----------------------------------------------------------------------------
    Public API Functions
-------------------------------------------------------------------------------]]

-- Internal helper to get valid aura data respecting expiration
local function GetValidAuraData(spellID, unit)
    if not spellID or not unit or not trackedAuras[unit] then return nil end
    local auraData = trackedAuras[unit][spellID]
    if not auraData then return nil end

    -- Check expiration time if it's not 0 (0 means permanent or no duration)
    if auraData.expirationTime ~= 0 and auraData.expirationTime <= GetTime() then
        -- Aura is expired, treat as not present
        -- Optionally remove from cache here? No, let next update handle removal.
        return nil
    end
    return auraData
end

-- Check if a unit has a specific buff/debuff by Spell ID
-- spellID: The numeric spell ID to check for
-- unit: The unit token ("player", "target", "focus", etc.)
-- checkCasterPlayer: Optional boolean. If true, only return true if the aura was applied by the player/vehicle.
-- Returns: true if the aura exists and meets caster criteria, false otherwise
function AuraMonitor:HasAura(spellID, unit, checkCasterPlayer)
    local auraData = GetValidAuraData(spellID, unit) -- Gets non-expired data
    if not auraData then return false end -- Aura not found or expired

    -- Check caster if requested
    if checkCasterPlayer then
        return auraData.casterIsPlayer -- Check our stored boolean flag
    else
        return true -- Aura exists and isn't expired, caster doesn't matter
    end
end

-- Convenience function for checking buffs
function AuraMonitor:HasBuff(spellID, unit, checkCasterPlayer)
    local auraData = GetValidAuraData(spellID, unit)
    -- Check if auraData exists, is a buff, and meets caster criteria via HasAura
    return auraData and auraData.isBuff and self:HasAura(spellID, unit, checkCasterPlayer)
end

-- Convenience function for checking debuffs
function AuraMonitor:HasDebuff(spellID, unit, checkCasterPlayer)
     local auraData = GetValidAuraData(spellID, unit)
     -- Check if auraData exists, is NOT a buff, and meets caster criteria via HasAura
     return auraData and not auraData.isBuff and self:HasAura(spellID, unit, checkCasterPlayer)
end

-- Get the remaining duration of a buff/debuff
-- Returns: Remaining duration in seconds, or 0 if aura not found, permanent, or doesn't meet caster criteria.
function AuraMonitor:GetAuraRemaining(spellID, unit, checkCasterPlayer)
    local auraData = GetValidAuraData(spellID, unit)
    if not auraData then return 0 end -- Not found or expired

    -- Check caster if requested
    if checkCasterPlayer and not auraData.casterIsPlayer then
        return 0 -- Doesn't meet caster criteria
    end

    -- Check for permanent / no duration
    if auraData.expirationTime == 0 then return 0 end

    local remaining = auraData.expirationTime - GetTime()
    return remaining > 0 and remaining or 0
end

-- Get the stack count of a buff/debuff
-- Returns: Stack count, or 0 if aura not found or doesn't meet caster criteria.
function AuraMonitor:GetAuraStacks(spellID, unit, checkCasterPlayer)
    local auraData = GetValidAuraData(spellID, unit)
    if not auraData then return 0 end -- Not found or expired

    -- Check caster if requested
    if checkCasterPlayer and not auraData.casterIsPlayer then
        return 0 -- Doesn't meet caster criteria
    end

    return auraData.count
end

-- Get the simplified aura data table (use with caution)
function AuraMonitor:GetAuraData(spellID, unit)
    if not spellID or not unit or not trackedAuras[unit] then return nil end
    -- Return direct reference for performance.
    -- Note: This data might be for an expired aura if not checked first.
    return trackedAuras[unit][spellID]
end
