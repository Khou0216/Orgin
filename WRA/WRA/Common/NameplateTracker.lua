-- Common/NameplateTracker.lua
-- Uses the C_NamePlate API to count nearby, attackable, living enemy units.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local AceTimer = LibStub("AceTimer-3.0", true)
-- *** ADDED AceEvent-3.0 library reference ***
local AceEvent = LibStub("AceEvent-3.0", true)
if not AceTimer or not AceEvent then -- *** Check for AceEvent too ***
    WRA:PrintError("NameplateTracker: Missing AceTimer or AceEvent!") -- Use WRA's print
    -- Allow module to load but functions might error if timer/event is used
end

-- Create the NameplateTracker module *on the main addon object*
-- *** FIXED: Added "AceEvent-3.0" as a mixin ***
local NameplateTracker = WRA:NewModule("NameplateTracker", "AceTimer-3.0", "AceEvent-3.0")
WRA.NameplateTracker = NameplateTracker -- Make accessible via WRA.NameplateTracker

-- WoW API localization
local C_NamePlate = _G.C_NamePlate
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitPlayerControlled = _G.UnitPlayerControlled -- To ignore player/pet nameplates if needed
local UnitExists = _G.UnitExists -- Added for safety check
local GetCVarBool = _G.GetCVarBool
local pairs = pairs -- Lua shortcut

-- Module Variables
local lastEnemyCount = 0
local updateTimer = nil
-- Update slightly less frequently than core rotation checks to save CPU, unless high responsiveness is needed
local UPDATE_INTERVAL = 0.25

-- --- Internal Functions ---

-- Counts currently visible, attackable, living, non-player-controlled enemy nameplates
local function CountEnemyNameplates()
    local count = 0
    -- Ensure the C_NamePlate API is available
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates() or {} -- Ensure plates is a table
        for i = 1, #plates do
            local plate = plates[i]
            -- plateInfo contains namePlateUnitToken, which is the unitId for the nameplate
            if plate and plate.namePlateUnitToken then
                local unit = plate.namePlateUnitToken
                -- Check if the unit is an enemy, alive, and NOT a player character or their pet
                -- Add UnitExists check for safety
                if UnitExists(unit) and
                   UnitCanAttack("player", unit) and
                   not UnitIsDeadOrGhost(unit) and
                   not UnitPlayerControlled(unit) -- Exclude players and pets
                then
                    count = count + 1
                end
            end
        end
    else
        -- Fallback or warning if API is missing (shouldn't happen in WotLK+)
        WRA:PrintDebug("NameplateTracker: C_NamePlate.GetNamePlates() not found!")
        return lastEnemyCount -- Return last known count
    end
    return count
end

-- Periodic update function called by timer
local function PeriodicNameplateUpdate()
    -- Only count if nameplates are enabled by the user
    if GetCVarBool("nameplateShowEnemies") then
        local newCount = CountEnemyNameplates()
        if newCount ~= lastEnemyCount then
            -- WRA:PrintDebug("Nearby enemy count changed:", newCount) -- Can be spammy
            lastEnemyCount = newCount
            -- Send a message if the count changed, StateManager can listen for this
            -- *** This call should now work as AceEvent-3.0 is included ***
            NameplateTracker:SendMessage("WRA_NEARBY_ENEMIES_UPDATED", newCount)
        end
    elseif lastEnemyCount ~= 0 then
        -- Nameplates were turned off, reset count and notify
        lastEnemyCount = 0
        NameplateTracker:SendMessage("WRA_NEARBY_ENEMIES_UPDATED", 0)
    end
end

-- --- Module Lifecycle ---

function NameplateTracker:OnInitialize()
    -- self.WRA = WRA -- WRA is available via closure
    lastEnemyCount = 0
    WRA:PrintDebug("NameplateTracker Initialized") -- Use WRA's PrintDebug
end

function NameplateTracker:OnEnable()
    WRA:PrintDebug("NameplateTracker Enabled")
    -- Start the periodic update timer
    if not updateTimer then
        -- Get initial count only if nameplates are shown
        if GetCVarBool("nameplateShowEnemies") then
            lastEnemyCount = CountEnemyNameplates()
        else
            lastEnemyCount = 0
        end
        updateTimer = self:ScheduleRepeatingTimer(PeriodicNameplateUpdate, UPDATE_INTERVAL)
        -- Send initial count
        self:SendMessage("WRA_NEARBY_ENEMIES_UPDATED", lastEnemyCount)
    end
    -- Register for CVar updates to detect if user toggles enemy nameplates
    -- Note: CVAR_UPDATE might be restricted in combat, but checking periodically is fine.
    self:RegisterEvent("CVAR_UPDATE", "HandleCVarUpdate")
end

function NameplateTracker:OnDisable()
    WRA:PrintDebug("NameplateTracker Disabled")
    if updateTimer then
        self:CancelTimer(updateTimer)
        updateTimer = nil
    end
    self:UnregisterEvent("CVAR_UPDATE")
    lastEnemyCount = 0
end

-- --- Event Handlers ---
function NameplateTracker:HandleCVarUpdate(event, cvarName)
    -- Check common CVar names across versions for showing enemy nameplates
    -- Use exact CVar for WotLK: nameplateShowEnemies
    if cvarName == "nameplateShowEnemies" then
        WRA:PrintDebug("Enemy Nameplate CVar changed, forcing recount.")
        PeriodicNameplateUpdate() -- Force an update immediately
    end
end


-- --- Public API Functions ---

-- Get the last known count of nearby enemies
-- @return number: Count of nearby, attackable, living enemy nameplates.
function NameplateTracker:GetNearbyEnemyCount()
    -- Note: This count is based on VISIBLE nameplates, not distance filtered.
    return lastEnemyCount
end

-- Force an immediate recount and update (use sparingly)
function NameplateTracker:RecountNow()
    WRA:PrintDebug("Forcing nameplate recount.")
    PeriodicNameplateUpdate()
    return lastEnemyCount
end

-- TODO: Add function GetHostilePlatesInRange(radius) if distance filtering is needed.
-- This would require iterating plates, getting UnitPosition for each, calculating distance
-- from player's position (from StateManager), and counting those within radius.
-- This is significantly more complex and CPU intensive.

