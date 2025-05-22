-- UI/OptionsPanel_Feral.lua
-- Defines and registers the Feral Druid specific options panel.

local addonName, WRA = ... -- WRA is the main addon object passed by AceAddon
local LibStub = _G.LibStub

-- Get required libraries
local AceConfig = LibStub("AceConfig-3.0", true)
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
if not AceConfig or not AceConfigDialog then
    print(addonName .. " OptionsPanel_Feral: Missing AceConfig or AceConfigDialog!")
    return
end

-- Unique name for this options table
local FERAL_OPTIONS_NAME = "WRA_Options_Feral"
-- Display name for the options panel category
local FERAL_DISPLAY_NAME = "WRA - Feral" -- Change if you prefer a different display name

-- Function to load and register Feral options
function WRA:LoadFeralOptions()
    -- Ensure the Feral module and its DB are ready
    local FeralModule = WRA:GetModule("FeralDruid") -- Get module instance
    if not FeralModule or not FeralModule.db or not FeralModule.db.profile then
        WRA:PrintDebug("Feral module or DB not ready for options.")
        -- Optionally schedule a retry if needed
        -- WRA:ScheduleTimer("LoadFeralOptions", 0.5)
        return
    end
    local p = FeralModule.db.profile -- Local reference to the profile

    local options = {
        name = FERAL_DISPLAY_NAME, -- Name shown in the options panel
        type = "group",
        -- handler = FeralModule, -- Can set handler if needed
        args = {
            header_feral = {
                order = 1,
                type = "header",
                name = "Feral Druid Settings",
            },
            enableAOE = {
                type = "toggle", order = 10,
                name = "Enable AOE Rotation",
                desc = "Switch to AOE logic (e.g., Swipe) on 3+ targets.",
                get = function(info) return p.enableAOE end,
                set = function(info, v) p.enableAOE = v; WRA:Print("Enable AOE set to:", v) end,
            },
            enableRake = {
                type = "toggle", order = 20,
                name = "Maintain Rake",
                desc = "Keep Rake applied to the target.",
                get = function(info) return p.enableRake end,
                set = function(info, v) p.enableRake = v; WRA:Print("Maintain Rake set to:", v) end,
            },
            enableBerserk = {
                type = "toggle", order = 30,
                name = "Use Berserk",
                desc = "Automatically use Berserk when available and conditions met.",
                get = function(info) return p.enableBerserk end,
                set = function(info, v) p.enableBerserk = v; WRA:Print("Use Berserk set to:", v) end,
            },
            -- Add other Feral-specific options from your original file...
            energyPool = {
                type = "range", order = 40, name = "Energy Pool Threshold",
                desc = "Allow energy pooling for finishers when above this value.",
                min = 40, max = 95, step = 5,
                get = function(info) return p.energyPool end,
                set = function(info, v) p.energyPool = v end,
            },
            ripThreshold = {
                type = "range", order = 50, name = "Rip Threshold (sec)",
                desc = "Only use Ferocious Bite if Rip has at least this much time remaining.",
                min = 1, max = 10, step = 1,
                get = function(info) return p.ripThreshold end,
                set = function(info, v) p.ripThreshold = v end,
            },
            srThreshold = {
                type = "range", order = 60, name = "Savage Roar Threshold (sec)",
                desc = "Only use Ferocious Bite if Savage Roar has at least this much time remaining.",
                min = 0.5, max = 5, step = 0.5,
                get = function(info) return p.srThreshold end,
                set = function(info, v) p.srThreshold = v end,
            },
            -- Add ripLeeway, srOffset etc. if needed
        },
    }

    -- Register the options table
    AceConfig:RegisterOptionsTable(FERAL_OPTIONS_NAME, options)

    -- Add it to the Blizzard options panel under the main "WRA" category
    local categoryFrame = AceConfigDialog:AddToBlizOptions(FERAL_OPTIONS_NAME, FERAL_DISPLAY_NAME, addonName)

    -- Store the category name for the QuickConfig button
    WRA.optionsCategoryFeral = FERAL_DISPLAY_NAME -- Store the name used

    WRA:PrintDebug("Feral Druid options registered and added to Bliz panel.")
end
