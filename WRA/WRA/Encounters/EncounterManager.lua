-- Encounters/EncounterManager.lua
-- Detects encounter starts/ends and loads/unloads specific encounter modules.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local AceEvent = LibStub("AceEvent-3.0", true)
-- *** REMOVED: AceTimer no longer needed here ***
-- local AceTimer = LibStub("AceTimer-3.0", true)
-- if not AceEvent or not AceTimer then
if not AceEvent then -- *** Check only AceEvent ***
    WRA:PrintError("EncounterManager: Missing AceEvent!") -- Use WRA's print
    return
end

-- Create the EncounterManager module *on the main addon object*
-- *** REMOVED: AceTimer mixin no longer needed ***
local EncounterManager = WRA:NewModule("EncounterManager", "AceEvent-3.0")
WRA.EncounterManager = EncounterManager -- Make accessible via WRA.EncounterManager

-- WoW API & Lua shortcuts
local pairs = pairs
local type = type
local tostring = tostring
local select = select
-- Localize GetCurrentMapAreaID safely
local GetCurrentMapAreaID = _G.GetCurrentMapAreaID
local GetInstanceInfo = GetInstanceInfo
local xpcall = xpcall
local geterrorhandler = geterrorhandler -- Use default error handler

-- Module Variables
local currentEncounterModule = nil -- Reference to the active encounter logic module
local currentEncounterID = nil
local currentZoneID = nil -- Initialize to nil
local dbmRegistered = false
-- *** REMOVED: Timer/Retry variables ***
-- local zoneCheckTimer = nil
-- local zoneCheckRetries = 0
-- local MAX_ZONE_CHECK_RETRIES = 5

-- Mapping from Encounter ID (number) to the AceModule name
local encounterIDToModuleName = {
    -- Example: Naxxramas
    [1114] = "Encounter_Naxx_KelThuzad", -- Kel'Thuzad
    -- Example: Ulduar
    [745] = "Encounter_Uld_Ignis", -- Ignis
    [749] = "Encounter_Uld_Kologarn", -- Kologarn
    -- Example: ICC
    [856] = "Encounter_ICC_LichKing", -- The Lich King
    -- Add more mappings...
}

-- --- DBM Integration ---
local function DBMEventHandler(event, ...)
    if not currentEncounterModule then return end
    if event == "DBM_Announce" and currentEncounterModule.OnDBMAnnounce then
        currentEncounterModule:OnDBMAnnounce(...)
    elseif event == "DBM_TimerStart" and currentEncounterModule.OnDBMTimerStart then
        currentEncounterModule:OnDBMTimerStart(...)
    elseif event == "DBM_TimerStop" and currentEncounterModule.OnDBMTimerStop then
        currentEncounterModule:OnDBMTimerStop(...)
    elseif event == "DBM_SetStage" and currentEncounterModule.OnDBMStage then
        local _, _, stage = ...
        currentEncounterModule:OnDBMStage(stage)
    elseif (event == "DBM_Kill" or event == "DBM_Wipe") and currentEncounterModule.OnEncounterEnd then
        -- Optional end logic trigger
    end
end

local function RegisterWithDBM()
    if dbmRegistered or not _G.DBM then return end
    WRA:PrintDebug("Registering DBM callbacks...")
    local DBM = _G.DBM
    DBM:RegisterCallback("DBM_Announce", DBMEventHandler)
    DBM:RegisterCallback("DBM_TimerStart", DBMEventHandler)
    DBM:RegisterCallback("DBM_TimerStop", DBMEventHandler)
    DBM:RegisterCallback("DBM_SetStage", DBMEventHandler)
    DBM:RegisterCallback("DBM_Kill", DBMEventHandler)
    DBM:RegisterCallback("DBM_Wipe", DBMEventHandler)
    dbmRegistered = true
end

-- --- Module Lifecycle ---

function EncounterManager:OnInitialize()
    currentEncounterModule = nil
    currentEncounterID = nil
    currentZoneID = nil
    WRA:PrintDebug("EncounterManager Initialized")
end

function EncounterManager:OnEnable()
    WRA:PrintDebug("EncounterManager Enabled")
    self:RegisterEvent("ENCOUNTER_START", "HandleEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "HandleEncounterEnd")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "HandleZoneChange")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "HandleZoneChange")

    RegisterWithDBM()
    -- Call HandleZoneChange directly on enable as a first attempt
    -- It now has safety checks for the API function.
    self:HandleZoneChange()
end

function EncounterManager:OnDisable()
    WRA:PrintDebug("EncounterManager Disabled")
    self:UnregisterAllEvents()
    -- *** REMOVED: Timer cancellation ***
    self:StopCurrentEncounter()
end

-- --- Event Handlers ---

function EncounterManager:HandleEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    WRA:PrintDebug("ENCOUNTER_START:", encounterID, encounterName)
    currentEncounterID = encounterID
    self:StopCurrentEncounter() -- Safety stop

    local moduleName = encounterIDToModuleName[encounterID]
    if moduleName then
        local module = WRA:GetModule(moduleName, true)
        if module then
            WRA:Print("Loading encounter module:", moduleName)
            currentEncounterModule = module
            if currentEncounterModule.Enable then currentEncounterModule:Enable() end
            if currentEncounterModule.OnEncounterStart then
                local success, err = xpcall(currentEncounterModule.OnEncounterStart, geterrorhandler(), currentEncounterModule, encounterID, encounterName, difficultyID, groupSize)
                if not success then WRA:PrintError("Error in", moduleName, "OnEncounterStart:", err) end
            end
        else
            WRA:PrintDebug("No module found or loaded for encounter ID:", encounterID, "(Expected:", moduleName, ")")
        end
    else
        WRA:PrintDebug("No module name mapped for encounter ID:", encounterID)
    end
end

function EncounterManager:HandleEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    WRA:PrintDebug("ENCOUNTER_END:", encounterID, encounterName, "Success:", tostring(success))
    if currentEncounterID == encounterID then
        self:StopCurrentEncounter(encounterID, encounterName, difficultyID, groupSize, success)
    else
        WRA:PrintDebug("Encounter end received for", encounterID, "but current encounter is", currentEncounterID or "nil")
    end
    currentEncounterID = nil
end

-- *** REMOVED: ScheduleZoneCheck function ***

-- Handle zone change, called by events, includes API check
function EncounterManager:HandleZoneChange(event)
    -- Check if the API function exists *now*
    -- *** FIX: Check _G directly as localization might fail early ***
    if not _G.GetCurrentMapAreaID then
        -- API not ready yet, likely PLAYER_ENTERING_WORLD fired too early.
        -- ZONE_CHANGED_NEW_AREA should fire later when it's ready.
        WRA:PrintDebug("EncounterManager: GetCurrentMapAreaID API not available during event:", event or "OnEnable")
        return
    end

    -- API is available, proceed with the check
    local newZoneID = _G.GetCurrentMapAreaID() -- Call global directly
    local newInstanceID = select(8, GetInstanceInfo())
    local effectiveZoneID = newInstanceID or newZoneID

    if effectiveZoneID ~= currentZoneID then
        WRA:PrintDebug("Zone Changed. Old:", currentZoneID or "nil", "New:", effectiveZoneID)
        if currentEncounterModule and currentEncounterModule.OnZoneLeave then
             local success, err = xpcall(currentEncounterModule.OnZoneLeave, geterrorhandler(), currentEncounterModule, currentZoneID, nil)
             if not success then WRA:PrintError("Error in", currentEncounterModule:GetName(), "OnZoneLeave:", err) end
        end
        self:StopCurrentEncounter()
        currentZoneID = effectiveZoneID
    end
end

-- --- Helper Functions ---
function EncounterManager:StopCurrentEncounter(...)
    if currentEncounterModule then
        local moduleName = currentEncounterModule:GetName()
        WRA:PrintDebug("Stopping encounter module:", moduleName)
        if currentEncounterModule.OnEncounterEnd then
             local success, err = xpcall(currentEncounterModule.OnEncounterEnd, geterrorhandler(), currentEncounterModule, ...)
             if not success then WRA:PrintError("Error in", moduleName, "OnEncounterEnd:", err) end
        end
        if currentEncounterModule.Disable then currentEncounterModule:Disable() end
        currentEncounterModule = nil
    end
    currentEncounterID = nil
end

-- --- Public API ---
function EncounterManager:GetActiveEncounterModule()
    return currentEncounterModule
end

function EncounterManager:GetCurrentEncounterID()
    return currentEncounterID
end

function EncounterManager:IsKnownBossName(unitName)
    if not unitName then return false end
    for id, moduleName in pairs(encounterIDToModuleName) do
        -- Needs better implementation
    end
    return false
end
