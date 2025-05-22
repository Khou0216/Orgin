-- Encounters/EncounterBase.lua
-- Base structure and methods for specific encounter modules.

local addonName, WRA = ...
local LibStub = _G.LibStub

local EncounterBase = {}
WRA.EncounterBase = EncounterBase -- Make accessible if needed for direct use

-- --- Base Methods (Specific modules can override these) ---

-- Called when the specific encounter starts
function EncounterBase:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    WRA:PrintDebug(self:GetName(), "started. ID:", encounterID, "Name:", encounterName)
    -- Register encounter-specific actions, hooks, modify state flags, etc.
    -- Example: WRA.ActionManager:RegisterAction(...)
    -- Example: WRA.StateManager:SetUnitFlag(bossGuid, "customFlag", true)
end

-- Called when the specific encounter ends (wipe, kill, or player leaves zone)
function EncounterBase:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    WRA:PrintDebug(self:GetName(), "ended. Success:", tostring(success))
    -- Unregister actions, hooks, clean up state flags
    -- Example: WRA.ActionManager:UnregisterActionsByOwner(self:GetName())
    -- Example: WRA.StateManager:ClearUnitFlag(bossGuid, "customFlag")
end

-- Called when the player enters the zone containing this encounter (even if not engaged)
function EncounterBase:OnZoneEnter(zoneID, instanceID)
    WRA:PrintDebug(self:GetName(), "zone entered.")
    -- Can be used for pre-setting zone-wide configurations if needed
end

-- Called when the player leaves the zone
function EncounterBase:OnZoneLeave(zoneID, instanceID)
     WRA:PrintDebug(self:GetName(), "zone left.")
     -- Clean up zone-wide settings
end

-- --- DBM/BigWigs Callback Handlers (Optional) ---
-- Specific modules implement these if they need to react to boss mod events.
-- EncounterManager will forward calls to the active module.

function EncounterBase:OnDBMAnnounce(message, type, spellId)
    -- WRA:PrintDebug(self:GetName(), "DBM Announce:", message, type or "", spellId or "")
end

function EncounterBase:OnDBMTimerStart(timerId, msg, duration, timerType, spellId, dbmType)
     -- WRA:PrintDebug(self:GetName(), "DBM Timer Start:", msg, duration)
end

function EncounterBase:OnDBMTimerStop(timerId)
     -- WRA:PrintDebug(self:GetName(), "DBM Timer Stop:", timerId)
end

function EncounterBase:OnDBMStage(stage)
     -- WRA:PrintDebug(self:GetName(), "DBM Stage:", stage)
end

-- Add handlers for other boss mod events if needed (e.g., BW timer start/stop)

-- --- Helper Methods (Optional) ---
-- Add common helper functions specific encounter modules might use

-- Example: function EncounterBase:IsHeroic() return difficultyID == 2 or difficultyID == 4 end

-- Note: Specific encounter modules will be created using WRA:NewModule(EncounterModuleName, "AceEvent-3.0")
-- and can then have their metatable set to { __index = EncounterBase } if desired,
-- or simply implement the methods they need directly.
