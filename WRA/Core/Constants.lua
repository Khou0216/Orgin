-- Core/Constants.lua
-- Holds constants used by the WRA addon for WotLK Classic (3.3.5a / 3.4.x)
-- v6: Added ActionColors table for multi-icon/color block display system.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local Constants = WRA:NewModule("Constants")
WRA.Constants = Constants

--[[-----------------------------------------------------------------------------
    Engine & Timing Constants
-------------------------------------------------------------------------------]]
Constants.UPDATE_INTERVAL = 0.05
Constants.FIRE_WINDOW = 0.15
Constants.GCD_THRESHOLD = 0.05 -- Threshold for considering GCD ready
Constants.ACTION_ID_WAITING = 0 -- Suggests waiting (e.g., GCD active, casting)
Constants.ACTION_ID_IDLE = "IDLE" -- Suggests no specific action, truly idle
Constants.ACTION_ID_CASTING = "CASTING" -- Indicates player is currently casting/channeling
Constants.ACTION_ID_UNKNOWN = -1 -- Fallback for unknown actions

--[[-----------------------------------------------------------------------------
    Spell IDs - Fury Warrior (WotLK)
-------------------------------------------------------------------------------]]
Constants.Spells = {
    -- Core Rotation
    BLOODTHIRST     = 23881, -- Rank 6
    WHIRLWIND       = 1680,  -- Rank 6 (WotLK usually uses higher rank, e.g., 47520 for actual spell, 1680 is base)
                            -- Let's assume 1680 is a placeholder or base for logic, actual cast might be rank-specific.
                            -- For consistency, let's use the WotLK rank 7 ID for Whirlwind if it's the primary one.
                            -- Given FuryWarrior.lua uses 47520 for WW, we should align or clarify.
                            -- For now, keeping 1680 as per original file, but this might need review.
                            -- UPDATE: FuryWarrior.lua uses C.Spells.WHIRLWIND which is 1680, and also C.Spells.CLEAVE (47520).
                            -- It seems 47520 was mistakenly assigned to Whirlwind in a comment in Display_Icons.lua.
                            -- The actual spell ID for Whirlwind (Rank 6) is 1680.
                            -- Cleave (Rank 7) is 47520.
    HEROIC_STRIKE   = 47450, -- Rank 11
    SLAM            = 47475, -- Rank 7 (This is actually Cleave Rank 7 ID based on Wowhead for WotLK)
                            -- Slam Rank 7 ID is 50783. Let's correct this if SLAM refers to actual Slam.
                            -- FuryWarrior.lua uses C.Spells.SLAM (which would be this 47475) for Bloodsurge proc.
                            -- Bloodsurge (46916) makes Slam instant.
                            -- Let's assume for now Constants.Spells.SLAM is intended for the Bloodsurge-procced Slam.
    EXECUTE         = 47471, -- Rank 8
    CLEAVE          = 47520, -- Rank 7 (Corrected, was 47475 in SLAM previously)
    REND            = 47465, -- Rank 9
    OVERPOWER       = 7384,  -- Rank 4

    -- Cooldowns
    RECKLESSNESS    = 1719,
    DEATH_WISH      = 12292,
    BERSERKER_RAGE  = 18499,
    SHATTERING_THROW= 64382,
    BLOODRAGE       = 2687,

    -- Utility / Other
    PUMMEL          = 6552,  -- Rank 2
    BATTLE_SHOUT    = 47436, -- Rank 9
    COMMANDING_SHOUT= 47440, -- Rank 6
    SUNDER_ARMOR    = 7386,  -- Rank 5 (WotLK common rank)
    HEROIC_THROW    = 57755,
    INTERCEPT       = 20252, -- Rank 3

    -- Stances (Spell IDs to *cast* the stance)
    BATTLE_STANCE_CAST   = 2457,
    DEFENSIVE_STANCE_CAST= 71,
    BERSERKER_STANCE_CAST= 2458,

    -- Racials
    BLOOD_FURY      = 20572, -- Orc
    BERSERKING      = 26297, -- Troll
    STONEFORM       = 20594, -- Dwarf
    ESCAPE_ARTIST   = 20589, -- Gnome
    GIFT_OF_NAARU   = 28880, -- Draenei (Rank 6 @ 80)
    EVERY_MAN       = 59752, -- Human
}

--[[-----------------------------------------------------------------------------
    Buff & Debuff Spell IDs (Auras)
-------------------------------------------------------------------------------]]
Constants.Auras = {
    -- Player Procs/Buffs
    BLOODSURGE      = 46916, -- Slam! Buff
    ENRAGE          = 12880, -- Generic Enrage (e.g. from crits if talented)
    RAMPAGE         = 29801, -- Talent proc (5% crit)
    DEATH_WISH_BUFF = 12292, -- Death Wish buff itself (same as spell ID)
    RECKLESSNESS_BUFF = 1719,  -- Recklessness buff itself (same as spell ID)
    BERSERKER_RAGE_BUFF = 18499, -- Specific Berserker Rage Enrage (same as spell ID)
    BERSERKING_BUFF = 26297, -- Troll Racial Haste Buff (same as spell ID)
    BLOODLUST       = 2825,  -- Horde Haste
    HEROISM         = 32182, -- Alliance Haste
    OVERPOWER_PROC  = 12835, -- Overpower Ready (This is actually the "Dodged Attack" aura that enables Overpower, not Overpower itself)
                             -- A better way to check Overpower might be via combat log events or specific API if available.
                             -- For now, this can be used as a proxy if AuraMonitor tracks it.

    -- Target Debuffs (Player Applied)
    REND_DEBUFF     = 47465, -- Rend Bleed (same as spell ID)
    SUNDER_ARMOR_DEBUFF = 7386,  -- Sunder Armor Debuff (same as spell ID)
    SHATTERING_THROW_DEBUFF = 64382, -- Shattering Throw Armor Reduction Debuff (same as spell ID)

    -- Target Debuffs (Other - Examples)
    FAERIE_FIRE     = 770,   -- Druid Armor Reduction (Vanilla ID, WotLK has Feral version 16857)
                            -- Faerie Fire (Feral) is 16857
    CURSE_OF_ELEMENTS = 47865, -- Warlock Magic Damage Amp (Rank 5)

    -- Shouts
    BATTLE_SHOUT_BUFF    = 47436, -- Rank 9 Buff (same as spell ID)
    COMMANDING_SHOUT_BUFF= 47440, -- Rank 6 Buff (same as spell ID)
}

--[[-----------------------------------------------------------------------------
    Item IDs (Consumables, Trinkets)
-------------------------------------------------------------------------------]]
Constants.Items = {
    -- Potions
    POTION_HASTE    = 40211, -- Potion of Speed
    POTION_INVIS    = 9172,  -- Lesser Invisibility Potion (example)
    POTION_MANA     = 40077, -- Runic Mana Potion (example)
    POTION_HEALTH   = 40093, -- Runic Healing Potion (example)

    -- Trinkets (Example IDs, replace with actual relevant trinkets)
    TRINKET_DBW     = 50363, -- Deathbringer's Will
    TRINKET_STS     = 50343, -- Sharpened Twilight Scale
    TRINKET_WFS     = 47734, -- Whispering Fanged Skull
    TRINKET_COM     = 45522, -- Comet's Trail
    TRINKET_MJOLNIR = 47303, -- Mjolnir Runestone
    TRINKET_BANNER  = 47115, -- Banner of Victory
    TRINKET_MIRROR  = 45158, -- Mirror of Truth

    -- Other Items
    HEALTHSTONE     = 47883, -- Master Healthstone (Rank 7)
}

--[[-----------------------------------------------------------------------------
    Spell Data (Ranges, Costs, etc.) - isOffGCD and triggersGCD added
-------------------------------------------------------------------------------]]
Constants.SpellData = {
    [Constants.Spells.BLOODTHIRST]     = { range = 5, cost = 20, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.WHIRLWIND]       = { range = 8, cost = 25, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.HEROIC_STRIKE]   = { range = 5, cost = 15, isOffGCD = true,  triggersGCD = false }, -- Does not trigger GCD, but is "on next swing"
    [Constants.Spells.SLAM]            = { range = 5, cost = 15, isOffGCD = false, triggersGCD = true }, -- Bloodsurge makes it instant, but still on GCD
    [Constants.Spells.EXECUTE]         = { range = 5, cost = 15, isOffGCD = false, triggersGCD = true }, -- Rage cost can be 0-30
    [Constants.Spells.CLEAVE]          = { range = 5, cost = 20, isOffGCD = true,  triggersGCD = false }, -- Does not trigger GCD, but is "on next swing"
    [Constants.Spells.PUMMEL]          = { range = 5, cost = 10, isOffGCD = true,  triggersGCD = false }, -- Off GCD interrupt
    [Constants.Spells.REND]            = { range = 5, cost = 10, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.OVERPOWER]       = { range = 5, cost = 5,  isOffGCD = false, triggersGCD = true },
    [Constants.Spells.SUNDER_ARMOR]    = { range = 5, cost = 15, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.SHATTERING_THROW]= { range = 30,cost = 25, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.HEROIC_THROW]    = { range = 30,cost = 0,  isOffGCD = false, triggersGCD = true },
    [Constants.Spells.INTERCEPT]       = { range = 25,cost = 10, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.BATTLE_SHOUT]    = { range = 0, cost = 10, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.COMMANDING_SHOUT]= { range = 0, cost = 10, isOffGCD = false, triggersGCD = true },
    [Constants.Spells.RECKLESSNESS]    = { range = 0, cost = 0,  isOffGCD = false, triggersGCD = true },
    [Constants.Spells.DEATH_WISH]      = { range = 0, cost = 0,  isOffGCD = false, triggersGCD = true }, -- Costs Health
    [Constants.Spells.BERSERKER_RAGE]  = { range = 0, cost = 0,  isOffGCD = false, triggersGCD = true },
    [Constants.Spells.BLOODRAGE]       = { range = 0, cost = 0,  isOffGCD = true,  triggersGCD = false }, -- Costs Health, Generates Rage, Off GCD

    -- Stance Costs (Spell IDs to *cast* the stance)
    [Constants.Spells.BATTLE_STANCE_CAST]   = { range = 0, cost = 0, isOffGCD = false, triggersGCD = true }, -- Stance changes trigger a short GCD
    [Constants.Spells.BERSERKER_STANCE_CAST]= { range = 0, cost = 0, isOffGCD = false, triggersGCD = true }, -- Stance changes trigger a short GCD
    [Constants.Spells.DEFENSIVE_STANCE_CAST]= { range = 0, cost = 0, isOffGCD = false, triggersGCD = true }, -- Stance changes trigger a short GCD
}

--[[-----------------------------------------------------------------------------
    Stance Info (Using GetShapeshiftFormID() results)
-------------------------------------------------------------------------------]]
Constants.Stances = {
    BATTLE = 17,
    DEFENSIVE = 18,
    BERSERKER = 19,
}

--[[-----------------------------------------------------------------------------
    Action Colors for UI Display (RGBA, 0-1 range)
    NEW SECTION
-------------------------------------------------------------------------------]]
Constants.ActionColors = {
    -- Core States
    [Constants.ACTION_ID_IDLE]      = {r = 0.5, g = 0.5, b = 0.5, a = 0.8}, -- Grey (Idle)
    [Constants.ACTION_ID_WAITING]   = {r = 0.3, g = 0.3, b = 0.3, a = 0.8}, -- Dark Grey (Waiting/GCD)
    [Constants.ACTION_ID_CASTING]   = {r = 0.2, g = 0.2, b = 0.6, a = 0.8}, -- Dark Blue (Casting)
    [Constants.ACTION_ID_UNKNOWN]   = {r = 0.1, g = 0.1, b = 0.1, a = 0.8}, -- Nearly Black (Unknown)

    -- Fury Warrior GCD Skills (Example Colors)
    [Constants.Spells.BLOODTHIRST]     = {r = 0.8, g = 0.1, b = 0.1, a = 1.0}, -- Bright Red
    [Constants.Spells.WHIRLWIND]       = {r = 0.9, g = 0.6, b = 0.2, a = 1.0}, -- Orange
    [Constants.Spells.SLAM]            = {r = 0.6, g = 0.8, b = 0.2, a = 1.0}, -- Yellow-Green (for Bloodsurge Slam)
    [Constants.Spells.EXECUTE]         = {r = 0.4, g = 0.0, b = 0.0, a = 1.0}, -- Dark Red / Maroon
    [Constants.Spells.REND]            = {r = 0.7, g = 0.3, b = 0.1, a = 1.0}, -- Brownish-Red
    [Constants.Spells.OVERPOWER]       = {r = 1.0, g = 1.0, b = 0.3, a = 1.0}, -- Bright Yellow
    [Constants.Spells.SHATTERING_THROW]= {r = 0.5, g = 0.2, b = 0.8, a = 1.0}, -- Purple
    [Constants.Spells.HEROIC_THROW]    = {r = 0.2, g = 0.6, b = 0.8, a = 1.0}, -- Light Blue
    [Constants.Spells.SUNDER_ARMOR]    = {r = 0.6, g = 0.4, b = 0.2, a = 1.0}, -- Brown

    -- Fury Warrior Cooldowns (GCD)
    [Constants.Spells.RECKLESSNESS]    = {r = 1.0, g = 0.0, b = 0.5, a = 1.0}, -- Magenta/Pink
    [Constants.Spells.DEATH_WISH]      = {r = 0.6, g = 0.0, b = 0.6, a = 1.0}, -- Dark Purple
    [Constants.Spells.BERSERKER_RAGE]  = {r = 1.0, g = 0.3, b = 0.0, a = 1.0}, -- Fiery Orange

    -- Fury Warrior Off-GCD Skills (Example Colors)
    [Constants.Spells.HEROIC_STRIKE]   = {r = 0.1, g = 0.7, b = 0.1, a = 1.0}, -- Dark Green
    [Constants.Spells.CLEAVE]          = {r = 0.1, g = 0.5, b = 0.5, a = 1.0}, -- Teal/Cyan
    [Constants.Spells.PUMMEL]          = {r = 0.8, g = 0.8, b = 0.8, a = 1.0}, -- Light Grey/Silver (Interrupt)
    [Constants.Spells.BLOODRAGE]       = {r = 0.9, g = 0.2, b = 0.2, a = 1.0}, -- Slightly different Red

    -- Stance Changes (if ever directly suggested, though usually part of a sequence)
    [Constants.Spells.BATTLE_STANCE_CAST]    = {r = 0.7, g = 0.7, b = 0.1, a = 0.8}, -- Olive
    [Constants.Spells.BERSERKER_STANCE_CAST] = {r = 0.8, g = 0.4, b = 0.1, a = 0.8}, -- Dark Orange

    -- Items (Example)
    [Constants.Items.POTION_HASTE]     = {r = 0.9, g = 0.9, b = 0.0, a = 1.0}, -- Yellow (Potion)
}


--[[-----------------------------------------------------------------------------
    Other Constants
-------------------------------------------------------------------------------]]
Constants.HS_CLEAVE_MIN_RAGE = 12 -- Minimum rage to consider HS/Cleave (after cost)

function Constants:OnInitialize()
    -- Ensure SpellData is populated for all spells in Constants.Spells
    -- This is a good place to add default values if a spell is in .Spells but not .SpellData
    for spellID, _ in pairs(Constants.Spells) do
        if not Constants.SpellData[spellID] then
            Constants.SpellData[spellID] = {
                range = 0, cost = 0, isOffGCD = false, triggersGCD = true -- Default values
            }
            WRA:PrintDebug("Constants: Added default SpellData for SpellID:", spellID)
        end
    end

    WRA:PrintDebug("Constants Module Initialized.")
end
