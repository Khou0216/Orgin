-- WRA/Locales/enUS.lua
-- English localization file

local L = LibStub("AceLocale-3.0"):NewLocale("WRA", "enUS", true, true) -- true for default, true for silent
if not L then return end

-- General
L["WRA_ADDON_NAME"] = "WRA Helper"
L["WRA_ADDON_DESCRIPTION"] = "A powerful rotation and combat helper."
L["CONFIGURATION_FOR_WRA"] = "WRA Settings"
L["DISPLAY_POSITION_RESET"] = "Display position has been reset."
L["QUICK_CONFIG_TITLE"] = "WRA Quick Settings"


-- Main Options Panel Tabs
L["TAB_GENERAL"] = "General"
L["TAB_FURY_WARRIOR"] = "Fury Warrior"
L["TAB_SOME_OTHER_SPEC"] = "Other Spec" -- Example for future

-- General Settings
L["GENERAL_SETTINGS_HEADER"] = "General Settings"
L["ENABLE_ADDON_NAME"] = "Enable WRA Helper"
L["ENABLE_ADDON_DESC"] = "Completely enable or disable this addon."
L["LOCK_DISPLAY_NAME"] = "Lock Display Frame"
L["LOCK_DISPLAY_DESC"] = "Locks the position of the suggestion frame to prevent accidental dragging."
L["DISPLAY_SCALE_NAME"] = "Display Scale"
L["DISPLAY_SCALE_DESC"] = "Adjusts the size of the suggestion frame."
L["DISPLAY_ALPHA_NAME"] = "Display Alpha"
L["DISPLAY_ALPHA_DESC"] = "Adjusts the transparency of the suggestion frame."
L["RESET_DISPLAY_POSITION_NAME"] = "Reset Display Position"
L["RESET_DISPLAY_POSITION_DESC"] = "Resets the suggestion frame's position to default."
L["DEBUG_MODE_NAME"] = "Debug Mode"
L["DEBUG_MODE_DESC"] = "Enables detailed debug message output to the chat frame (mainly for developers)."


-- Fury Warrior Options
L["SPEC_OPTIONS_FURYWARRIOR_HEADER_ROTATION"] = "Rotation Options"
L["OPTION_USE_WHIRLWIND_NAME"] = "Use Whirlwind"
L["OPTION_USE_WHIRLWIND_DESC"] = "Enable/disable Whirlwind in the rotation."
L["OPTION_USE_REND_NAME"] = "Use Rend"
L["OPTION_USE_REND_DESC"] = "Enable/disable Rend usage (requires stance dancing)."
L["OPTION_USE_OVERPOWER_NAME"] = "Use Overpower"
L["OPTION_USE_OVERPOWER_DESC"] = "Enable/disable Overpower usage (requires stance dancing and proc)."
L["OPTION_SMART_AOE_NAME"] = "Smart AOE"
L["OPTION_SMART_AOE_DESC"] = "Automatically detect nearby enemies to switch between Heroic Strike and Cleave (if Force Cleave is off)."
L["OPTION_ENABLE_CLEAVE_NAME"] = "Force Cleave"
L["OPTION_ENABLE_CLEAVE_DESC"] = "Force the use of Cleave over Heroic Strike, regardless of target count or Smart AOE setting."

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_COOLDOWNS"] = "Cooldown Usage"
L["OPTION_USE_RECKLESSNESS_NAME"] = "Use Recklessness"
L["OPTION_USE_RECKLESSNESS_DESC"] = "Allow automatic use of Recklessness."
L["OPTION_USE_DEATH_WISH_NAME"] = "Use Death Wish"
L["OPTION_USE_DEATH_WISH_DESC"] = "Allow automatic use of Death Wish."
L["OPTION_USE_BERSERKER_RAGE_NAME"] = "Use Berserker Rage"
L["OPTION_USE_BERSERKER_RAGE_DESC"] = "Allow automatic use of Berserker Rage (primarily for Enrage uptime)."

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_UTILITY"] = "Utility"
L["OPTION_USE_SHATTERING_THROW_NAME"] = "Use Shattering Throw"
L["OPTION_USE_SHATTERING_THROW_DESC"] = "Allow automatic use of Shattering Throw on bosses."
L["OPTION_USE_INTERRUPTS_NAME"] = "Use Pummel"
L["OPTION_USE_INTERRUPTS_DESC"] = "Allow automatic use of Pummel to interrupt targets."
L["OPTION_USE_SHOUTS_NAME"] = "Use Shouts"
L["OPTION_USE_SHOUTS_DESC"] = "Allow automatic refresh of Battle Shout."

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_CONSUMABLES"] = "Consumables & Racials"
L["OPTION_USE_TRINKETS_NAME"] = "Use Trinkets"
L["OPTION_USE_TRINKETS_DESC"] = "Allow automatic use of tracked On-Use trinkets."
L["OPTION_USE_POTIONS_NAME"] = "Use Potions"
L["OPTION_USE_POTIONS_DESC"] = "Allow automatic use of Haste Potions (with Death Wish)."
L["OPTION_USE_RACIALS_NAME"] = "Use Racials"
L["OPTION_USE_RACIALS_DESC"] = "Allow automatic use of offensive racial abilities (e.g., Blood Fury, Berserking)."

-- DisplayManager related (example)
L["DISPLAY_TYPE_ICONS_NAME"] = "Icon Mode"
L["DISPLAY_TYPE_ICONS_DESC"] = "Display suggestions using icons."
-- L["DISPLAY_TYPE_TEXT_NAME"] = "Text Mode"
-- L["DISPLAY_TYPE_TEXT_DESC"] = "Display suggestions using text."

