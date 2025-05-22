-- Specs/SpecLoader.lua
-- Detects player class/spec and loads the appropriate spec logic module.
-- v2 (Range Fix): Added GetRangeCheckSpell method.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local AceEvent = LibStub("AceEvent-3.0", true)
local AceTimer = LibStub("AceTimer-3.0", true)
if not AceEvent or not AceTimer then
    WRA:PrintError("SpecLoader: Missing AceEvent or AceTimer!") -- Use WRA's print
    return
end

-- Create the SpecLoader module *on the main addon object*
local SpecLoader = WRA:NewModule("SpecLoader", "AceEvent-3.0", "AceTimer-3.0")
WRA.SpecLoader = SpecLoader -- Make accessible via WRA.SpecLoader

-- WoW API & Lua shortcuts
local UnitClass = UnitClass
local GetNumTalentTabs = GetNumTalentTabs
local GetTalentTabInfo = GetTalentTabInfo
local IsLoggedIn = IsLoggedIn
local pairs = pairs

-- Module Variables
local activeSpecModule = nil
local activeSpecKey = nil -- Store the key (e.g., "FuryWarrior") of the active spec
local playerClass = nil
local C = nil -- To store WRA.Constants

-- Mapping from detected spec info to module names
local specToModuleName = {
    ["WARRIOR_ARMS"] = "ArmsWarrior",
    ["WARRIOR_FURY"] = "FuryWarrior",
    ["WARRIOR_PROTECTION"] = "ProtectionWarrior",
    ["DRUID_BALANCE"] = "BalanceDruid",
    ["DRUID_FERAL"] = "FeralDruid",
    ["DRUID_RESTORATION"] = "RestorationDruid",
    ["MAGE_ARCANE"] = "ArcaneMage",
    ["MAGE_FIRE"] = "FireMage",
    ["MAGE_FROST"] = "FrostMage",
    -- Add mappings for all classes and specs you intend to support
}

-- --- Internal Functions ---
local function GetPrimarySpecIdentifier()
    if not playerClass then return nil end
    local highestPoints = -1
    local primaryTabIndex = 0
    local specName = nil
    local numTabs = GetNumTalentTabs()
    if numTabs == 0 then return nil end
    for i = 1, numTabs do
        local name, _, _, _, pointsSpent = GetTalentTabInfo(i)
        if pointsSpent > highestPoints then
            highestPoints = pointsSpent
            primaryTabIndex = i
            specName = name
        end
    end
    if highestPoints <= 0 then return nil end

    if playerClass == "WARRIOR" then
        if primaryTabIndex == 1 then return "ARMS"
        elseif primaryTabIndex == 2 then return "FURY"
        elseif primaryTabIndex == 3 then return "PROTECTION" end
    elseif playerClass == "DRUID" then
        if primaryTabIndex == 1 then return "BALANCE"
        elseif primaryTabIndex == 2 then return "FERAL"
        elseif primaryTabIndex == 3 then return "RESTORATION" end
    elseif playerClass == "MAGE" then
         if primaryTabIndex == 1 then return "ARCANE"
         elseif primaryTabIndex == 2 then return "FIRE"
         elseif primaryTabIndex == 3 then return "FROST" end
    end
    WRA:PrintDebug("Could not determine primary spec identifier for", playerClass, "Tab Index:", primaryTabIndex, "Name:", specName or "N/A")
    return nil
end


-- --- Module Lifecycle ---
function SpecLoader:OnInitialize()
    _, playerClass = UnitClass("player")
    activeSpecModule = nil
    activeSpecKey = nil
    C = WRA.Constants -- Cache constants module
    WRA:PrintDebug("[SpecLoader:OnInitialize] Initialized for class:", playerClass or "UNKNOWN")
end

function SpecLoader:OnEnable()
    WRA:PrintDebug("[SpecLoader:OnEnable] Enabled")
    self:RegisterEvent("PLAYER_LOGIN", "LoadSpecModule")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ScheduleLoadSpecModule")
    self:RegisterEvent("PLAYER_TALENT_UPDATE", "LoadSpecModule")
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "LoadSpecModule")

    if IsLoggedIn() then
        self:ScheduleLoadSpecModule()
    end
end

function SpecLoader:OnDisable()
    WRA:PrintDebug("[SpecLoader:OnDisable] Disabled")
    self:UnregisterAllEvents()
    if activeSpecModule and activeSpecModule.Disable then
        activeSpecModule:Disable()
    end
    self:CancelAllTimers()
    activeSpecModule = nil
    activeSpecKey = nil
end

-- --- Core Logic ---
function SpecLoader:ScheduleLoadSpecModule()
     if self.loadTimer then self:CancelTimer(self.loadTimer, true) end
     self.loadTimer = self:ScheduleTimer("LoadSpecModule", 0.5)
end

function SpecLoader:LoadSpecModule()
    self.loadTimer = nil

    local specIdentifier = GetPrimarySpecIdentifier()
    if not specIdentifier then
        WRA:Print("[SpecLoader:LoadSpecModule] Could not determine player spec.")
        return
    end

    local moduleKey = playerClass .. "_" .. specIdentifier
    local moduleName = specToModuleName[moduleKey]
    local newSpecKey = moduleName -- Use the module name as the spec key for consistency

    if not moduleName then
        WRA:Print("[SpecLoader:LoadSpecModule] No rotation module defined for spec:", moduleKey)
        if activeSpecModule then
             WRA:PrintDebug("[SpecLoader:LoadSpecModule] Disabling previous spec module:", activeSpecKey)
             if activeSpecModule.Disable then activeSpecModule:Disable() end
             activeSpecModule = nil
             activeSpecKey = nil
        end
        return
    end

    if activeSpecModule and activeSpecKey == newSpecKey then
        WRA:PrintDebug("[SpecLoader:LoadSpecModule] Spec module", moduleName, "already active.")
        return
    end

    if activeSpecModule then
        WRA:PrintDebug("[SpecLoader:LoadSpecModule] Disabling previous spec module:", activeSpecKey)
        if activeSpecModule.Disable then activeSpecModule:Disable() end
        activeSpecModule = nil
        activeSpecKey = nil
    end

    local newModule = WRA:GetModule(moduleName, true) -- true to silence "module not found" if it's not yet loaded by AceAddon
    if newModule then
        WRA:Print("[SpecLoader:LoadSpecModule] Loading spec module:", moduleName)
        activeSpecModule = newModule
        activeSpecKey = newSpecKey -- Set activeSpecKey HERE

        if activeSpecModule.Enable then
            activeSpecModule:Enable()
            WRA:PrintDebug("[SpecLoader:LoadSpecModule] Calling AddSpecOptionsToPanel for active key:", activeSpecKey or "nil")
            self:AddSpecOptionsToPanel()
        else
             WRA:Print("Warning: Spec module", moduleName, "has no Enable method.")
        end
        self:SendMessage("WRA_SPEC_CHANGED", activeSpecModule, activeSpecKey)
    else
        WRA:Print("[SpecLoader:LoadSpecModule] Spec module not found or loaded yet (this might be normal during initial load order):", moduleName)
    end
end

function SpecLoader:AddSpecOptionsToPanel()
    if not activeSpecKey or not WRA.OptionsPanel then
        WRA:PrintDebug("[SpecLoader:AddSpecOptionsToPanel] Cannot add spec options: No current spec key or OptionsPanel module not found.")
        return
    end

    local getOptionsFuncName = "GetSpecOptions_" .. activeSpecKey
    local getOptionsFunc = WRA[getOptionsFuncName]

    if type(getOptionsFunc) ~= "function" then
        WRA:Print("Error: Function " .. getOptionsFuncName .. " not found on WRA object. Cannot retrieve options for " .. activeSpecKey)
        return
    end

    local specOptionsTable = getOptionsFunc(WRA)

    if type(specOptionsTable) ~= "table" then
        WRA:Print("Error: " .. getOptionsFuncName .. " did not return a table for " .. activeSpecKey)
        return
    end

    if WRA.OptionsPanel.AddSpecOptions then
        WRA.OptionsPanel:AddSpecOptions(activeSpecKey, specOptionsTable)
        WRA:PrintDebug("[SpecLoader:AddSpecOptionsToPanel] Successfully called OptionsPanel:AddSpecOptions for " .. activeSpecKey)
    else
        WRA:Print("Error: OptionsPanel does not have AddSpecOptions function.")
    end
end


-- --- Public API ---
function SpecLoader:GetActiveSpecModule()
    return activeSpecModule
end

function SpecLoader:GetCurrentSpecKey()
    WRA:PrintDebug("[SpecLoader:GetCurrentSpecKey] Called. Returning:", activeSpecKey or "nil")
    return activeSpecKey
end

function SpecLoader:GetPlayerClass()
    return playerClass
end

-- ** NEW FUNCTION TO PROVIDE A SPELL FOR RANGE CHECKING **
function SpecLoader:GetRangeCheckSpell()
    if not C or not C.Spells then
        WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] Constants or C.Spells not available.")
        return false -- Return false or a very default ID if constants aren't loaded
    end

    if playerClass == "WARRIOR" then
        -- For Warriors, Auto Attack (ID 6603) is a good generic melee range check.
        -- Or a very common, always available melee ability.
        -- Using Bloodthirst as an example if available, otherwise fallback.
        -- However, for LibRange, a spell that LibRange itself knows is best.
        -- LibRangeCheck-3.0 typically uses its own internal logic based on class
        -- and doesn't strictly need a spell ID from us *if* it can determine the class.
        -- But StateManager's IsSpellInRange uses it to get a yardage from Constants.SpellRanges
        -- and then converts that to a LibRange enum.
        -- So, we need a spell ID that *has a defined range in Constants.SpellRanges*.
        -- Let's use Bloodthirst if Fury, or a general melee otherwise.
        if activeSpecKey == "FuryWarrior" and C.Spells.BLOODTHIRST then
            WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] Returning BLOODTHIRST (", C.Spells.BLOODTHIRST, ") for FuryWarrior.")
            return C.Spells.BLOODTHIRST
        elseif C.Spells.HEROIC_STRIKE then -- Fallback for any warrior spec if BT not suitable
            WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] Returning HEROIC_STRIKE (", C.Spells.HEROIC_STRIKE, ") for WARRIOR.")
            return C.Spells.HEROIC_STRIKE
        else
            -- Absolute fallback for Warrior if specific spells aren't in constants for some reason
            WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] WARRIOR fallback, returning 6603 (Auto Attack).")
            return 6603 -- Auto Attack
        end
    elseif playerClass == "MAGE" then
        -- For Mages, Fireball or Frostbolt might be appropriate.
        if C.Spells.FIREBALL then -- Assuming Fireball is a common spell in your constants
            WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] Returning FIREBALL for MAGE.")
            return C.Spells.FIREBALL
        end
    -- Add other classes here
    -- elseif playerClass == "ROGUE" then
    --     return C.Spells.SINISTER_STRIKE or 6603
    end

    WRA:PrintDebug("[SpecLoader:GetRangeCheckSpell] No specific range check spell found for class:", playerClass, "Falling back to false.")
    return false -- Default if no suitable spell found for the class/spec
end
