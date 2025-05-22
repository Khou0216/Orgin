-- UI/QuickOptions.lua
-- Defines and registers the options table for the Quick Settings panel.

local addonName, _ = ... -- Get addon name, don't need addonTable
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0") -- Get AceAddon library first
local WRA = AceAddon:GetAddon(addonName) -- *** Correctly get the main addon object ***

-- *** REMOVED: LibStub call for AceConfig at top level ***

-- Create the QuickOptions module with a new name
local QuickOptionsLogic = WRA:NewModule("QuickOptionsLogic")
-- We still might want to access its functions via WRA.QuickOptions for simplicity elsewhere
WRA.QuickOptions = QuickOptionsLogic -- Assign the renamed module instance to WRA.QuickOptions

-- Name used for registration and opening the panel
WRA.QUICK_OPTIONS_NAME = "WRA_QuickOptions"

-- *** Variable to store the AceConfig instance used for registration ***
QuickOptionsLogic.AceConfigInstance = nil

-- Function to build and register the options
function QuickOptionsLogic:BuildAndRegisterQuickOptions()
    -- Prevent duplicate registration
    if WRA.quickOptionsRegistered then
        WRA:PrintDebug("[QuickOptions:Build] Already registered.") -- DEBUG
        return
    end

    WRA:PrintDebug("[QuickOptions:Build] Starting BuildAndRegisterQuickOptions...") -- DEBUG

    -- *** Get AceConfig instance HERE ***
    local AceConfig = LibStub("AceConfig-3.0", true)
    if not AceConfig or type(AceConfig.RegisterOptionsTable) ~= "function" then
        WRA:PrintError("[QuickOptions:Build] Could not get a valid AceConfig instance!")
        return -- Cannot proceed without AceConfig
    end
    -- *** Store the valid instance ***
    self.AceConfigInstance = AceConfig
    WRA:PrintDebug("[QuickOptions:Build] Stored AceConfig instance. Type:", type(self.AceConfigInstance), "Has RegisterOptionsTable:", type(self.AceConfigInstance.RegisterOptionsTable))

    -- Ensure the database is initialized
    if not WRA.db or not WRA.db.profile then
        WRA:PrintError("[QuickOptions:Build] Database not initialized, cannot build quick options.") -- DEBUG with prefix
        return
    end

    local _, playerClass = UnitClass("player")
    local profile = WRA.db.profile -- Global profile reference
    local args = {} -- Arguments for the quick options group

    WRA:PrintDebug("[QuickOptions:Build] Player Class:", playerClass or "Unknown") -- DEBUG

    -- Define options based on class dynamically (Keep existing logic)
    if playerClass == "WARRIOR" then
        WRA:PrintDebug("[QuickOptions:Build] Building options for WARRIOR...") -- DEBUG
        local specDB = WRA.db.profile.specs and WRA.db.profile.specs.FuryWarrior or {}
        WRA:PrintDebug("[QuickOptions:Build] SpecDB type:", type(specDB)) -- DEBUG
        local specKeys = {
            { key = "useRecklessness",    label = "Use Reck" },
            { key = "useDeathWish",       label = "Use DW" },
            { key = "useBerserkerRage",   label = "Use BRage" },
            { key = "useShatteringThrow", label = "Use Shatter" },
            { key = "usePotions",         label = "Use Potions" },
            { key = "useRacials",         label = "Use Racials" },
            -- New toggles:
            { key = "smartAOE",           label = "Smart AOE" },
            { key = "enableCleave",       label = "Enable Cleave" },
        }
        WRA:PrintDebug("[QuickOptions:Build] Defined", #specKeys, "specKeys for Warrior.") -- DEBUG
        for i, opt in ipairs(specKeys) do
            WRA:PrintDebug("[QuickOptions:Build] Adding arg:", opt.key) -- DEBUG
            args[opt.key] = {
                order = i * 10, type = "toggle", name = opt.label,
                get = function() return specDB[opt.key] end,
                set = function(_, v)
                    WRA:PrintDebug("[QuickOptions Set] Key:", opt.key, "New Value:", v) -- DEBUG
                    specDB[opt.key] = v
                    -- Refresh QuickConfig panel if it exists and is shown
                    if WRA.QuickConfig and WRA.QuickConfig.RefreshPanel and quickPanelFrame and quickPanelFrame.frame:IsShown() then
                         WRA.QuickConfig:RefreshPanel()
                    end
                end,
            }
        end
    elseif playerClass == "DRUID" then
        WRA:PrintDebug("[QuickOptions:Build] Building options for DRUID...") -- DEBUG
        local specDB = WRA.db.profile.specs and WRA.db.profile.specs.FeralDruid or {} -- Example
        local specKeys = { } -- Define Druid keys here
        WRA:PrintDebug("[QuickOptions:Build] Defined", #specKeys, "specKeys for Druid.") -- DEBUG
        for i, opt in ipairs(specKeys) do
            WRA:PrintDebug("[QuickOptions:Build] Adding arg:", opt.key) -- DEBUG
            args[opt.key] = {
                order = i * 10, type = "toggle", name = opt.label,
                get = function() return specDB[opt.key] end,
                set = function(_, v)
                   specDB[opt.key] = v
                   if WRA.QuickConfig and WRA.QuickConfig.RefreshPanel and quickPanelFrame and quickPanelFrame.frame:IsShown() then
                        WRA.QuickConfig:RefreshPanel()
                   end
                end,
            }
        end
    else
        WRA:PrintDebug("[QuickOptions:Build] No specific quick options defined for class:", playerClass or "Unknown") -- DEBUG
    end

    local argCount = 0; for _ in pairs(args) do argCount = argCount + 1 end
    WRA:PrintDebug("[QuickOptions:Build] Final arg count:", argCount)

    if argCount > 0 then
        WRA:PrintDebug("[QuickOptions:Build] Attempting registration with key:", WRA.QUICK_OPTIONS_NAME)
        -- *** Use the stored AceConfig instance for registration ***
        self.AceConfigInstance:RegisterOptionsTable(WRA.QUICK_OPTIONS_NAME, { type = "group", name = "WRA Quick Settings", args = args })
        WRA.quickOptionsRegistered = true
        WRA:PrintDebug("[QuickOptions:Build] Quick options registration call completed.")
    else
        WRA:PrintDebug("[QuickOptions:Build] No args generated, skipping registration.")
        WRA.quickOptionsRegistered = false
    end
end

-- Module Lifecycle methods
function QuickOptionsLogic:OnInitialize()
    WRA:PrintDebug("[QuickOptionsLogic:OnInitialize] Initialized.")
end

function QuickOptionsLogic:OnEnable() end

function QuickOptionsLogic:OnDisable()
    WRA.quickOptionsRegistered = nil
    self.AceConfigInstance = nil -- Clear stored instance on disable
    WRA:PrintDebug("[QuickOptionsLogic:OnDisable] Disabled and cleared AceConfig instance.")
end
