-- wow addon/WRA/Core/WRA.lua
-- v5: Further strengthened library initialization checks.

local addonName, addonTable = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- Default database values
local defaults = {
    profile = {
        enabled = true,
        debugMode = false,
        displayLocked = false,
        displayPoint = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 150 },
        displayScale = 1.0,
        displayAlpha = 1.0,
        selectedDisplay = "Icons",
        specs = {
            FuryWarrior = {
                 useRecklessness = true,
                 useDeathWish = true,
                 useBerserkerRage = true,
                 useShatteringThrow = true,
                 useInterrupts = false,
                 useShouts = false,
                 useTrinkets = true,
                 usePotions = true,
                 useRacials = true,
                 smartAOE = true,
                 enableCleave = false,
                 useRend = true,
                 useOverpower = true,
                 useWhirlwind = true,
            }
        },
        encounters = {
            enabled = true
        },
        displayIcons = { -- Ensure displayIcons defaults exist
            displayScale = 1.0,
            displayAlpha = 1.0,
            showOffGCDSlot = true,
            iconSize = 40,
            showColorBlocks = true,
            colorBlockBelowIcon = false,
            colorBlockHeight = 10,
            locked = false,
        }
    }
}


-- Called when the addon is initialized
function WRA:OnInitialize()
    -- Initialize the database
    self.db = LibStub("AceDB-3.0"):New("WRADB", defaults, true)

    self.db.profile.specs = self.db.profile.specs or {}
    self.db.profile.specs.FuryWarrior = self.db.profile.specs.FuryWarrior or {}
    self.db.profile.displayIcons = self.db.profile.displayIcons or {} -- Ensure this sub-table exists

    -- Store Library References Directly on WRA object
    self.AceGUI = LibStub("AceGUI-3.0", true)
    self.AceConfig = LibStub("AceConfig-3.0", true)
    self.AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    self.AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)

    -- Check if libs loaded correctly here
    if not self.AceGUI then self:PrintError("AceGUI-3.0 failed to load!") end
    if not self.AceConfig then self:PrintError("AceConfig-3.0 failed to load!") end
    if not self.AceConfigDialog then self:PrintError("AceConfigDialog-3.0 failed to load!") end
    if not self.AceConfigRegistry then
        self:PrintError("AceConfigRegistry-3.0 failed to load or was not assigned to WRA!")
    else
        self:PrintDebug("AceConfigRegistry successfully loaded and assigned. Type:", type(self.AceConfigRegistry))
    end

    -- Get module references ONCE during initialization and store them
    -- Order matters for dependencies: Constants first, then utilities, then managers, then UI
    self.Constants = self:GetModule("Constants", true)
    self.Utils = self:GetModule("Utils", true)
    self.SpecLoader = self:GetModule("SpecLoader", true) -- SpecLoader might be needed by StateManager or others
    self.StateManager = self:GetModule("StateManager", true)
    self.AuraMonitor = self:GetModule("AuraMonitor", true)
    self.CooldownTracker = self:GetModule("CooldownTracker", true)
    self.TTDTracker = self:GetModule("TTDTracker", true)
    self.SwingTimer = self:GetModule("SwingTimer", true)
    self.NameplateTracker = self:GetModule("NameplateTracker", true)
    self.ActionManager = self:GetModule("ActionManager", true)
    self.RotationEngine = self:GetModule("RotationEngine", true)
    self.DisplayManager = self:GetModule("DisplayManager", true)
    self.Display_Icons = self:GetModule("Display_Icons", true) -- Display_Icons needs DisplayManager
    self.OptionsPanel = self:GetModule("OptionsPanel", true) -- OptionsPanel needs many other modules
    self.QuickConfig = self:GetModule("QuickConfig", true)
    self.QuickOptions = self:GetModule("QuickOptionsLogic", true)
    self.EncounterManager = self:GetModule("EncounterManager", true)


    -- Check if critical modules were loaded
    if not self.RotationEngine then self:PrintError("RotationEngine module failed to load!") end
    if not self.DisplayManager then self:PrintError("DisplayManager module failed to load!") end
    if not self.QuickConfig then self:PrintError("QuickConfig module failed to load!") end
    if not self.Display_Icons then self:PrintError("Display_Icons module failed to load!") end


    -- Register slash command
    self:RegisterChatCommand("wra", "ChatCommand")

    self:Print(L["Addon Loaded"])

    if not self.SpecLoader then
        self:PrintError("Error: SpecLoader module instance not found after GetModule!")
    end
end

-- Called when the addon is enabled (either initially or via toggle)
function WRA:OnEnable()
    if not self.db or not self.db.profile then
         self:PrintError("Cannot enable WRA: Database not initialized.")
         return
    end
    if not self.db.profile.enabled then
        self:PrintDebug("[WRA:OnEnable] Aborting enable because db.profile.enabled is false.")
        return
    end

    self:PrintDebug("[WRA:OnEnable] Enabling addon components...")

    if not self.SpecLoader then
        self:PrintError("Cannot enable WRA fully: SpecLoader module reference is missing!")
    else
        if IsLoggedIn() and type(self.SpecLoader.LoadSpecModule) == "function" then
            self:PrintDebug("[WRA:OnEnable] Ensuring spec module is loaded...")
            self.SpecLoader:LoadSpecModule()
        elseif type(self.SpecLoader.LoadSpecModule) ~= "function" then
             self:PrintError("[WRA:OnEnable] SpecLoader.LoadSpecModule is not a function!")
        end
    end

    if self.RotationEngine then
        if not self.RotationEngine:IsEnabled() then
            self:PrintDebug("[WRA:OnEnable] RotationEngine module is not yet enabled; AceAddon should handle this.")
        end
    else
        self:PrintError("[WRA:OnEnable] RotationEngine reference missing!")
    end

    if self.DisplayManager then
        if not self.DisplayManager:IsEnabled() then
            self:PrintDebug("[WRA:OnEnable] DisplayManager module is not yet enabled; AceAddon should handle this.")
        end
         -- Explicitly try to select display if DisplayManager is now enabled
        if self.DisplayManager:IsEnabled() and self.DisplayManager.AttemptInitialDisplaySelection then
            self:PrintDebug("[WRA:OnEnable] Manually calling DisplayManager:AttemptInitialDisplaySelection()")
            self.DisplayManager:AttemptInitialDisplaySelection()
        end
    else
        self:PrintError("[WRA:OnEnable] DisplayManager reference missing!")
    end

    if self.QuickConfig then
        if not self.QuickConfig:IsEnabled() then
             self:PrintDebug("[WRA:OnEnable] QuickConfig module is not yet enabled; AceAddon should handle this.")
        end
    else
         self:PrintError("[WRA:OnEnable] QuickConfig reference missing!")
    end

    if self.OptionsPanel and not self.OptionsPanel:IsEnabled() and self.OptionsPanel.Enable then
         self:PrintDebug("[WRA:OnEnable] OptionsPanel module should be enabled by AceAddon.")
    end

    self:Print(L["Addon Enabled"])
end


-- Called when the addon is disabled (via toggle)
function WRA:OnDisable()
    self:PrintDebug("[WRA:OnDisable] Disabling addon components using stored references...")

    if self.QuickConfig and self.QuickConfig.HideLauncherButtons and self.QuickConfig.HideQuickPanel then
         self:PrintDebug("[WRA:OnDisable] Ensuring QuickConfig UI elements are hidden.")
         self.QuickConfig:HideLauncherButtons()
         self.QuickConfig:HideQuickPanel()
    end

    self:Print(L["Addon Disabled"])
end

function WRA:EnableAddonFeatures()
    self:PrintDebug("[WRA] EnableAddonFeatures called. Calling WRA:Enable().")
    self:Enable()
end

function WRA:DisableAddonFeatures()
    self:PrintDebug("[WRA] DisableAddonFeatures called. Calling WRA:Disable().")
    self:Disable()
end

function WRA:ChatCommand(input)
    input = input:trim()
    if input == "" or input == "config" or input == L["config"] then
        if self.AceConfigDialog and type(self.AceConfigDialog.Open) == "function" then
            self.AceConfigDialog:Open(addonName)
        else
            self:PrintError("AceConfigDialog-3.0 library reference is invalid or missing.")
        end
    elseif input == "quick" or input == L["quick"] then
         if self.QuickConfig and type(self.QuickConfig.ToggleFrame) == "function" then
             self.QuickConfig:ToggleFrame()
         else
             self:PrintError("QuickConfig module or ToggleFrame function not available.")
         end
    elseif input == "reset" or input == L["reset"] then
        if self.DisplayManager and type(self.DisplayManager.ResetDisplayPosition) == "function" then
            self.DisplayManager:ResetDisplayPosition()
        else
            self:Print("DisplayManager not available or doesn't support reset.")
        end
    elseif input == "toggle" or input == L["toggle"] then
        if not self.db or not self.db.profile then return end
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print("Addon toggled via command. State:", tostring(self.db.profile.enabled))
        if self.db.profile.enabled then
            self:EnableAddonFeatures()
        else
            self:DisableAddonFeatures()
        end
    else
        self:Print(L["Usage: /wra [config|quick|reset|toggle]"])
    end
end

function WRA:PrintDebug(...)
    if self.db and self.db.profile and self.db.profile.debugMode then
        print("|cff1784d1" .. addonName .. "|r [Debug]:", ...)
    end
end

function WRA:PrintError(...)
    print("|cffFF0000" .. addonName .. "|r [Error]:", ...)
end
