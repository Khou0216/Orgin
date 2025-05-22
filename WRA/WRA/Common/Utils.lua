-- Common/Utils.lua
-- Common utility functions for the WRA addon.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Lua function shortcuts
local string_match = string.match
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pairs = pairs
local type = type
local tonumber = tonumber -- Added tonumber shortcut

-- Create the Utils module *on the main addon object*
local Utils = WRA:NewModule("Utils")
WRA.Utils = Utils -- Make accessible via WRA.Utils

-- WoW API localization
local GetSpellCooldown = _G.GetSpellCooldown
local GetTime = _G.GetTime

-- Constants (Fetch from main addon object - ensure Constants loaded first)
-- Get Constants reference safely after WRA object is retrieved
local Constants = WRA.Constants
-- Use a default if Constants module isn't ready during init phase
local GCD_THRESHOLD = (Constants and Constants.GCD_THRESHOLD) or 0.1

-- --- Utility Functions ---

-- Get the remaining global cooldown (using a reference spell)
-- @param refSpellID (Optional number): Spell ID known to trigger the standard 1.0/1.5s GCD. Defaults to 61304 (Spell Reflection).
function Utils:GetGCDRemaining(refSpellID)
    refSpellID = refSpellID or 61304 -- Default reference: Spell Reflection (Warrior)

    local start, duration, enabled = GetSpellCooldown(refSpellID)

    -- Check if the spell is known and has a cooldown start time and is enabled
    if not start or start == 0 or enabled == 0 then return 0 end
    -- Check if the spell actually incurred a GCD (duration is usually 1.0 or 1.5)
    if duration == 0 then return 0 end
    -- Ensure we're looking at a GCD, not the spell's actual cooldown if it's longer
    -- Adjust threshold slightly for potential haste effects on GCD display for *some* spells
    if duration > 1.6 then return 0 end

    local elapsed = GetTime() - start
    local remaining = duration - elapsed

    -- Clamp remaining time to 0 if it's negative
    return remaining < 0 and 0 or remaining
end

-- Checks if the GCD is ready (less than threshold remaining)
-- @param refSpellID (Optional number): Spell ID to check GCD against.
function Utils:IsGCDReady(refSpellID)
    -- Note: StateManager now tracks GCD more directly. This can be a fallback.
    return (WRA.StateManager and WRA.StateManager:GetCurrentState().player.isGCDActive == false) or (self:GetGCDRemaining(refSpellID) < GCD_THRESHOLD)
end

-- Get the remaining cooldown for a given spell by its SpellID
-- NOTE: This is primarily for ad-hoc checks. Use CooldownTracker for actively monitored spells.
function Utils:GetTimeToSpell(spellId)
    if not spellId then return 999 end -- Return large number if no ID provided
    local start, duration, enabled = GetSpellCooldown(spellId)

    if not start or start == 0 or enabled == 0 then return 0 end -- Not on CD or not usable
    if duration == 0 then return 0 end -- No cooldown duration

    local elapsed = GetTime() - start
    local remaining = duration - elapsed

    return remaining < 0 and 0 or remaining
end

-- Check if a spell is ready (cooldown finished) using the ad-hoc check.
-- NOTE: Prefer CooldownTracker:IsReady for spells actively tracked by it.
function Utils:IsSpellReady(spellId)
    -- Use CooldownTracker if available, otherwise fallback
    return (WRA.CooldownTracker and WRA.CooldownTracker:IsReady(spellId)) or (self:GetTimeToSpell(spellId) < GCD_THRESHOLD)
end

-- Clamp number between min/max
function Utils:Clamp(value, minVal, maxVal)
    return math_max(minVal, math_min(value, maxVal))
end

-- Round number to specified decimals
function Utils:Round(value, decimals)
    if not decimals then decimals = 0 end
    local mult = 10^decimals
    return math_floor(value * mult + 0.5) / mult
end

-- Extract Spell ID from a Spell GUID (Combat Log Event format)
-- Example GUID: "Spell_Nature_HealingTouch_Rank11" or "Spell_Shadow_PainSuppression" (older formats)
-- Example GUID (Modern): "Spell:12345:..." or "Player-123-ABC:Spell:12345:..."
-- This function specifically looks for the numeric ID part.
-- @param guidString (string): The GUID string from the combat log event.
-- @return spellID (number): The extracted numeric Spell ID, or 0 if not found/invalid.
function Utils:GetSpellIdFromGUID(guidString)
    if not guidString or type(guidString) ~= "string" then return 0 end
    -- Try to match the modern format "Spell:ID:" or ":Spell:ID:"
    local spellId = string_match(guidString, ":Spell:(%d+):")
    if spellId then return tonumber(spellId) or 0 end

    -- Try to match older formats (less common now but good fallback)
    -- Example: "Spell_Nature_HealingTouch_Rank11" -> No ID here
    -- Example: Sometimes the ID is embedded differently, e.g., UnitGUID format might include it
    -- Let's try a more general pattern for a number potentially preceded by "Spell" or similar markers
    spellId = string_match(guidString, "Spell_*(%d+)") -- Match number after Spell_
    if spellId then return tonumber(spellId) or 0 end

    -- If no specific pattern matches, try finding any sequence of digits that looks like a plausible spell ID
    -- This is less reliable but might catch edge cases. Look for 3+ digits.
    spellId = string_match(guidString, "(%d%d%d+)")
    if spellId then return tonumber(spellId) or 0 end

    return 0 -- Return 0 if no numeric ID could be extracted
end

-- Count the number of key-value pairs in a table
-- @param tbl (table): The table to count.
-- @return count (number): The number of pairs.
function Utils:CountTable(tbl)
    if type(tbl) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end


-- Add other general utility functions here...


-- --- Module Lifecycle ---
function Utils:OnInitialize()
    -- self.WRA = WRA -- Store reference to main addon if needed by funcs (WRA is available via closure anyway)
    -- Update Constants reference safely
    if not Constants and WRA.Constants then Constants = WRA.Constants end
    if Constants and Constants.GCD_THRESHOLD then GCD_THRESHOLD = Constants.GCD_THRESHOLD end

    WRA:PrintDebug("Utils Initialized")
end

function Utils:OnEnable()
    WRA:PrintDebug("Utils Enabled")
    -- No events needed for basic utils
end

function Utils:OnDisable()
    WRA:PrintDebug("Utils Disabled")
end
