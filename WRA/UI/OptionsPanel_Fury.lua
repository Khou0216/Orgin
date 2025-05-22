-- wow addon/WRA/UI/OptionsPanel_Fury.lua
-- v2: Added useRend and useOverpower toggles

local addonName, _ = ... -- Get addon name, don't need addonTable
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0") -- Get AceAddon library first
local WRA = AceAddon:GetAddon(addonName) -- *** FIXED: Correctly get the main addon object ***
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- This table defines the AceConfig options specific to Fury Warrior
-- It will be retrieved and added to the main options panel by SpecLoader/OptionsPanel
local furyOptions = {
    -- Cooldown Usage Toggles
    header_cooldowns = {
        order = 1,
        type = "header",
        name = L["Cooldowns"],
    },
    useRecklessness = {
        order = 2,
        type = "toggle",
        name = L["Use Recklessness"],
        desc = L["Allow the addon to suggest using Recklessness automatically."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useRecklessness end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useRecklessness = value end,
    },
    useDeathWish = {
        order = 3,
        type = "toggle",
        name = L["Use Death Wish"],
        desc = L["Allow the addon to suggest using Death Wish automatically."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useDeathWish end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useDeathWish = value end,
    },
    useBerserkerRage = {
        order = 4,
        type = "toggle",
        name = L["Use Berserker Rage (Offensive)"],
        desc = L["Allow the addon to suggest using Berserker Rage for extra rage/damage when appropriate."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useBerserkerRage end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useBerserkerRage = value end,
    },
    useShatteringThrow = {
        order = 5,
        type = "toggle",
        name = L["Use Shattering Throw"],
        desc = L["Allow the addon to suggest using Shattering Throw (e.g., during execute or for armor reduction)."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useShatteringThrow end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useShatteringThrow = value end,
    },

    -- Utility Toggles
    header_utility = {
        order = 10,
        type = "header",
        name = L["Utility"],
    },
    useInterrupts = {
        order = 11,
        type = "toggle",
        name = L["Suggest Pummel"],
        desc = L["Allow the addon to suggest using Pummel to interrupt enemy casts."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useInterrupts end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useInterrupts = value end,
    },
    useShouts = {
        order = 12,
        type = "toggle",
        name = L["Maintain Shouts"],
        desc = L["Suggest Battle Shout or Commanding Shout if the buff is missing."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useShouts end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useShouts = value end,
    },
    -- *** NEW: Rend Toggle ***
    useRend = {
        order = 13, -- Adjust order as needed
        type = "toggle",
        name = L["Maintain Rend"], -- Need localization
        desc = L["Suggest applying Rend via stance dancing if conditions are met."], -- Need localization
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useRend end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useRend = value end,
    },
    -- *** NEW: Overpower Toggle ***
     useOverpower = {
        order = 14, -- Adjust order as needed
        type = "toggle",
        name = L["Use Overpower"], -- Need localization
        desc = L["Suggest using Overpower via stance dancing when available."], -- Need localization
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useOverpower end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useOverpower = value end,
    },

    -- Consumables / Other Items
    header_items = {
        order = 20,
        type = "header",
        name = L["Items & Consumables"],
    },
    useTrinkets = {
        order = 21,
        type = "toggle",
        name = L["Use Trinkets"],
        desc = L["Allow the addon to suggest using on-use offensive trinkets."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useTrinkets end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useTrinkets = value end,
    },
    usePotions = {
        order = 22,
        type = "toggle",
        name = L["Use Potions"],
        desc = L["Allow the addon to suggest using potions (e.g., Haste Potion during cooldowns)."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.usePotions end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.usePotions = value end,
    },
    useRacials = {
        order = 23,
        type = "toggle",
        name = L["Use Racials"],
        desc = L["Allow the addon to suggest using offensive racial abilities (e.g., Blood Fury)."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.useRacials end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.useRacials = value end,
    },

    -- AOE and Cleave Toggles
    header_aoe = {
        order = 30,
        type = "header",
        name = L["AOE Settings"],
    },
    smartAOE = {
        order = 31,
        type = "toggle",
        name = L["Smart AOE"],
        desc = L["When OFF, forces single-target rotation regardless of enemy count."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.smartAOE end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.smartAOE = value end,
    },
    enableCleave = {
        order = 32,
        type = "toggle",
        name = L["Enable Cleave"],
        desc = L["When OFF, never recommend Cleave even in AOE mode."],
        get = function(info) return WRA.db.profile.specs.FuryWarrior.enableCleave end,
        set = function(info, value) WRA.db.profile.specs.FuryWarrior.enableCleave = value end,
    },

    -- Add more Fury specific options here if needed
}

-- Function for SpecLoader to retrieve this options table
function WRA:GetSpecOptions_FuryWarrior()
    -- Ensure the spec table exists before returning options
    if WRA.db and WRA.db.profile and WRA.db.profile.specs and not WRA.db.profile.specs.FuryWarrior then
        WRA.db.profile.specs.FuryWarrior = {} -- Create if missing
        WRA:PrintDebug("Created missing FuryWarrior spec table in DB profile.")
    end
    return furyOptions
end

WRA:PrintDebug("OptionsPanel_Fury.lua loaded, options defined.")
