-- wow addon/WRA/Core/WRA.lua
-- v2: Added defaults for Rend/Overpower toggles
-- v3: Added useWhirlwind default, changed enableCleave default to false
-- v4: 修正模块和库引用问题

local addonName, addonTable = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- Default database values
local defaults = {
    profile = {
        enabled = true,
        debugMode = false, -- Default debug mode to off
        displayLocked = false,
        displayPoint = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 150 },
        displayScale = 1.0,
        displayAlpha = 1.0,
        selectedDisplay = "Icons",
        specs = {
            -- Define default spec settings here if needed, e.g.:
            FuryWarrior = {
                 useRecklessness = true,
                 useDeathWish = true,
                 useBerserkerRage = true,
                 useShatteringThrow = true,
                 useInterrupts = false, -- Default Interrupts off for Fury
                 useShouts = false,     -- Default Shouts off for Fury
                 useTrinkets = true,
                 usePotions = true,
                 useRacials = true,
                 smartAOE = true,      -- Default: Check target count for AOE decisions
                 enableCleave = false, -- Default: Use normal HS/Cleave logic based on smartAOE and target count. Set to true to force Cleave over HS.
                 useRend = true,       -- Default Rend ON (UI toggle needed later)
                 useOverpower = true,  -- Default Overpower ON (UI toggle needed later)
                 useWhirlwind = true,  -- Default Whirlwind ON (Global toggle for the skill)
            }
            -- Add other specs as needed
        },
        encounters = {
            enabled = true
        }
    }
}


-- Called when the addon is initialized
function WRA:OnInitialize()
    -- Initialize the database
    self.db = LibStub("AceDB-3.0"):New("WRADB", defaults, true) -- Pass defaults here

    -- Ensure the profile structure exists (Example for FuryWarrior)
    self.db.profile.specs = self.db.profile.specs or {}
    self.db.profile.specs.FuryWarrior = self.db.profile.specs.FuryWarrior or {} -- Ensure spec table exists if defaults don't cover it
    -- Add similar checks for other specs if needed

    -- Store Library References Directly on WRA object
    self.AceGUI = LibStub("AceGUI-3.0", true)
    self.AceConfig = LibStub("AceConfig-3.0", true) -- *** 存储 AceConfig 引用 ***
    self.AceConfigDialog = LibStub("AceConfigDialog-3.0", true)

    -- Check if libs loaded correctly here
    if not self.AceGUI then self:PrintError("AceGUI-3.0 failed to load!") end
    if not self.AceConfig then self:PrintError("AceConfig-3.0 failed to load!") end -- *** 添加检查 ***
    if not self.AceConfigDialog then self:PrintError("AceConfigDialog-3.0 failed to load!") end


    -- Get module references ONCE during initialization and store them
    self.Constants = self:GetModule("Constants", true)
    self.ActionManager = self:GetModule("ActionManager", true)
    self.RotationEngine = self:GetModule("RotationEngine", true)
    self.Utils = self:GetModule("Utils", true)
    self.StateManager = self:GetModule("StateManager", true)
    self.AuraMonitor = self:GetModule("AuraMonitor", true)
    self.CooldownTracker = self:GetModule("CooldownTracker", true)
    self.TTDTracker = self:GetModule("TTDTracker", true)
    self.SwingTimer = self:GetModule("SwingTimer", true)
    self.NameplateTracker = self:GetModule("NameplateTracker", true)
    self.DisplayManager = self:GetModule("DisplayManager", true)
    self.OptionsPanel = self:GetModule("OptionsPanel", true)
    self.QuickConfig = self:GetModule("QuickConfig", true)
    self.QuickOptions = self:GetModule("QuickOptionsLogic", true) -- Use "QuickOptionsLogic"
    self.EncounterManager = self:GetModule("EncounterManager", true)
    self.SpecLoader = self:GetModule("SpecLoader", true)
    self.Display_Icons = self:GetModule("Display_Icons", true)

    -- Check if critical modules were loaded
    if not self.RotationEngine then self:PrintError("RotationEngine module failed to load!") end
    if not self.DisplayManager then self:PrintError("DisplayManager module failed to load!") end
    if not self.QuickConfig then self:PrintError("QuickConfig module failed to load!") end


    -- Register Display Backends with DisplayManager
    if self.DisplayManager then -- Use stored reference
        self:PrintDebug("[WRA:OnInitialize] Attempting to register displays...") -- DEBUG
        if self.Display_Icons then -- Use stored reference
             self:PrintDebug("[WRA:OnInitialize] Found Display_Icons module. Calling RegisterDisplay...") -- DEBUG
            self.DisplayManager:RegisterDisplay("Icons", self.Display_Icons)
        else
             self:PrintError("[WRA:OnInitialize] Error: Display_Icons module instance not found during registration attempt!")
        end
        -- Register other displays here...

        -- Trigger initial display selection AFTER registration attempts
        local selected = (self.db and self.db.profile.selectedDisplay) or "Icons"
        self:PrintDebug("[WRA:OnInitialize] Triggering initial display selection:", selected) -- DEBUG
        self.DisplayManager:SelectDisplay(selected) -- Use stored reference
        self:PrintDebug("[WRA:OnInitialize] Finished triggering display selection.") -- DEBUG

    else
        self:PrintError("[WRA:OnInitialize] Error: DisplayManager module instance not found! Cannot register or select displays.")
    end

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

    -- 1. Ensure Spec is Loaded (SpecLoader handles its own loading logic via events)
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

    -- 2. RotationEngine and DisplayManager will be enabled by AceAddon framework.
    --    Their OnEnable methods should handle their own startup.
    --    We ensure the modules are enabled if WRA itself is being enabled.

    if self.RotationEngine then
        if not self.RotationEngine:IsEnabled() then
            -- AceAddon should call OnEnable on sub-modules automatically when the parent is enabled.
            -- If we need to force it or if there are timing issues, self:EnableModule("RotationEngine") could be used.
            -- For now, rely on AceAddon's standard behavior.
            self:PrintDebug("[WRA:OnEnable] RotationEngine module is not yet enabled; AceAddon should handle this.")
        end
    else
        self:PrintError("[WRA:OnEnable] RotationEngine reference missing!")
    end

    if self.DisplayManager then
        if not self.DisplayManager:IsEnabled() then
            self:PrintDebug("[WRA:OnEnable] DisplayManager module is not yet enabled; AceAddon should handle this.")
        end
        -- DisplayManager:OnEnable will handle selecting and showing the display.
    else
        self:PrintError("[WRA:OnEnable] DisplayManager reference missing!")
    end

    -- 3. Show Config/Quick Buttons (QuickConfig also has its OnEnable)
    if self.QuickConfig then
        if not self.QuickConfig:IsEnabled() then
             self:PrintDebug("[WRA:OnEnable] QuickConfig module is not yet enabled; AceAddon should handle this.")
        end
        -- QuickConfig:OnEnable will call ShowLauncherButtons
    else
         self:PrintError("[WRA:OnEnable] QuickConfig reference missing!")
    end

    -- OptionsPanel is generally passive until config is opened.
    if self.OptionsPanel and not self.OptionsPanel:IsEnabled() and self.OptionsPanel.Enable then
        -- self.OptionsPanel:Enable() -- AceAddon handles this
         self:PrintDebug("[WRA:OnEnable] OptionsPanel module should be enabled by AceAddon.")
    end

    self:Print(L["Addon Enabled"])
end


-- Called when the addon is disabled (via toggle)
function WRA:OnDisable()
    self:PrintDebug("[WRA:OnDisable] Disabling addon components using stored references...") -- DEBUG

    -- *** AceAddon framework will call OnDisable for all enabled modules ***
    -- *** We don't need to manually call StopRotation or HideDisplay here if those modules handle it in their OnDisable ***

    -- Example: If QuickConfig needs manual hiding beyond its OnDisable:
    if self.QuickConfig and self.QuickConfig.HideLauncherButtons and self.QuickConfig.HideQuickPanel then
         self:PrintDebug("[WRA:OnDisable] Ensuring QuickConfig UI elements are hidden.")
         self.QuickConfig:HideLauncherButtons()
         self.QuickConfig:HideQuickPanel()
    end

    self:Print(L["Addon Disabled"])
end

-- ChatCommand (Use stored Lib references where appropriate, use stored module refs)
function WRA:ChatCommand(input)
    input = input:trim()
    if input == "" or input == "config" or input == L["config"] then
        -- Open main config panel using stored AceConfigDialog reference
        if self.AceConfigDialog and type(self.AceConfigDialog.Open) == "function" then
            self.AceConfigDialog:Open(addonName)
        else
            self:PrintError("AceConfigDialog-3.0 library reference is invalid or missing.")
        end
    elseif input == "quick" or input == L["quick"] then
         -- Toggle quick config panel (Use stored module ref)
         if self.QuickConfig and type(self.QuickConfig.ToggleFrame) == "function" then
             self.QuickConfig:ToggleFrame()
         else
             self:PrintError("QuickConfig module or ToggleFrame function not available.")
         end
    elseif input == "reset" or input == L["reset"] then
        -- Reset display position (Use stored module ref)
        if self.DisplayManager and type(self.DisplayManager.ResetDisplayPosition) == "function" then
            self.DisplayManager:ResetDisplayPosition()
        else
            self:Print("DisplayManager not available or doesn't support reset.")
        end
    elseif input == "toggle" or input == L["toggle"] then
        -- Toggle addon enabled state using the database value
        if not self.db or not self.db.profile then return end
        self.db.profile.enabled = not self.db.profile.enabled
        self:Print("Addon toggled via command. State:", tostring(self.db.profile.enabled))
        -- AceAddon will call WRA:Enable() or WRA:Disable() based on the new value
        if self.db.profile.enabled then
            self:Enable()
        else
            self:Disable()
        end
    else
        self:Print(L["Usage: /wra [config|quick|reset|toggle]"])
    end
end

-- PrintDebug (Check debugMode setting)
function WRA:PrintDebug(...)
    -- Check if db and profile exist before accessing debugMode
    if self.db and self.db.profile and self.db.profile.debugMode then
        print("|cff1784d1" .. addonName .. "|r [Debug]:", ...)
    end
end

-- PrintError (Keep existing)
function WRA:PrintError(...)
    print("|cffFF0000" .. addonName .. "|r [Error]:", ...)
end

