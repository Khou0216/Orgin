-- wow addon/WRA/Specs/FuryWarrior.lua
-- v14 structure with v15 options table and GetSpecOptions_FuryWarrior function.
-- Ensures 'name' and 'desc' fields in furyOptions use direct localization keys.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local FuryWarrior = WRA:NewModule("FuryWarrior", "AceEvent-3.0")
-- L is not strictly needed here if we only use keys for name/desc in furyOptions,
-- but can be kept if other parts of this file use it.
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

-- Lua shortcuts
local GetTime = GetTime
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local pairs = pairs
local type = type
local UnitCanAttack = UnitCanAttack
local string_format = string.format
local tostring = tostring
local GetShapeshiftFormID = GetShapeshiftFormID
local pcall = pcall
local IsCurrentSpell = IsCurrentSpell
local GetSpellCooldown = GetSpellCooldown

-- Constants
local C = nil -- Populated in OnInitialize
local ACTION_ID_WAITING = 0 -- Populated in OnInitialize from WRA.Constants
local ACTION_ID_IDLE = "IDLE" -- Populated in OnInitialize from WRA.Constants
local ACTION_ID_CASTING = "CASTING" -- Populated in OnInitialize from WRA.Constants

-- Configurable values (can be moved to DB defaults later)
local HS_CLEAVE_MIN_RAGE_DEFAULT = 12 -- Default, will be overridden by Constants if available
local LOW_RAGE_THRESHOLD_BLOODRAGE = 20
local AOE_THRESHOLD = 2 -- Number of targets for AOE consideration (e.g. for Whirlwind focus)
local CLEAVE_HS_AOE_THRESHOLD = 2 -- Number of targets to prefer Cleave over HS
local BT_WW_COOLDOWN_THRESHOLD = 1.5 -- Time remaining on BT/WW to consider other fillers
local HEROIC_THROW_SWING_THRESHOLD = 1.0 -- Min time on swing timer to use Heroic Throw

-- Module references
local State = nil
local CD = nil
local Aura = nil
local ActionMgr = nil
local Utils = nil
local Swing = nil
local DB = nil -- Spec-specific database profile, will be initialized in OnEnable and GetSpecOptions

local IsReady -- Forward declaration

-- Helper to get isOffGCD from Constants.SpellData
local function GetSpellIsOffGCD(spellID)
    if C and C.SpellData and C.SpellData[spellID] then
        return C.SpellData[spellID].isOffGCD or false
    end
    return false -- Default to false if not found
end

-- ActionManager Check Functions
local function CreateCheckReadyFunction(spellIdKey)
    return function(currentState, actionData)
        if not C or not IsReady or not DB then
            -- WRA:PrintDebug("CreateCheckReadyFunction for "..tostring(spellIdKey).." returning false due to missing C, IsReady, or DB")
            return false
        end
        local optionKey = "use" .. spellIdKey -- e.g., "useRecklessness"
        local spellID = actionData.id -- actionData.id is the spellID passed during registration
        local success, result = pcall(function()
            -- Check the specific DB toggle for this cooldown
            if DB[optionKey] == false then return false end -- Explicitly check for false, nil/true means enabled by default or if key missing
            return IsReady(spellID, currentState)
        end)
        if not success then
            -- WRA:PrintError("Error in pcall for CreateCheckReadyFunction ("..tostring(spellIdKey).."): "..tostring(result))
        end
        return success and result or false
    end
end

local CheckRecklessness = CreateCheckReadyFunction("Recklessness")
local CheckDeathWish = CreateCheckReadyFunction("DeathWish")
local CheckBerserkerRage = function(currentState, actionData)
    if not C or not IsReady or not Aura or not C.Auras or not DB then return false end
    if DB.useBerserkerRage == false then return false end
    local spellID = actionData.id
    local hasEnrage = Aura:HasBuff(C.Auras.ENRAGE, "player") or
                      Aura:HasBuff(C.Auras.BERSERKER_RAGE_BUFF, "player") or
                      (C.Auras.DEATH_WISH_BUFF and Aura:HasBuff(C.Auras.DEATH_WISH_BUFF, "player")) -- Death Wish also provides enrage

    local success, result = pcall(function() return IsReady(spellID, currentState) and not hasEnrage end)
    return success and result or false
end
local CheckShatteringThrow = CreateCheckReadyFunction("ShatteringThrow")
local CheckPotion = CreateCheckReadyFunction("Potions")
local CheckRacial = CreateCheckReadyFunction("Racials")
local CheckTrinket = CreateCheckReadyFunction("Trinkets")

function FuryWarrior:OnInitialize()
    State = WRA.StateManager
    CD = WRA.CooldownTracker
    Aura = WRA.AuraMonitor
    ActionMgr = WRA.ActionManager
    Utils = WRA.Utils
    Swing = WRA.SwingTimer
    C = WRA.Constants

    if not C then
        WRA:PrintError("FuryWarrior Error: Constants module not loaded before FuryWarrior!")
        return
    end
    ACTION_ID_WAITING = C.ACTION_ID_WAITING or 0
    ACTION_ID_IDLE = C.ACTION_ID_IDLE or "IDLE"
    ACTION_ID_CASTING = C.ACTION_ID_CASTING or "CASTING"
    HS_CLEAVE_MIN_RAGE_DEFAULT = C.HS_CLEAVE_MIN_RAGE or 12

    DB = nil -- DB reference will be set in OnEnable or GetSpecOptions_FuryWarrior

    WRA:PrintDebug("FuryWarrior Module Initializing (DB assignment deferred)")

    if ActionMgr and C and C.Spells and C.Items and C.Auras and C.SpellData then
        local actionsToRegister = {
            { id = C.Spells.RECKLESSNESS,    prio = 100, check = CheckRecklessness,    scope = "GCD" },
            { id = C.Spells.DEATH_WISH,      prio = 95,  check = CheckDeathWish,       scope = "GCD" },
            { id = C.Spells.BERSERKER_RAGE,  prio = 90,  check = CheckBerserkerRage,   scope = "GCD" },
            { id = C.Items.POTION_HASTE,     prio = 97,  check = CheckPotion,          scope = "GCD" },
            { id = C.Spells.SHATTERING_THROW,prio = 80,  check = CheckShatteringThrow, scope = "GCD" },
            { id = C.Spells.BLOOD_FURY,      prio = 65,  check = CheckRacial,          scope = "GCD" },
            { id = C.Spells.BERSERKING,      prio = 65,  check = CheckRacial,          scope = "GCD" },
        }

        for _, action in ipairs(actionsToRegister) do
            if action.id then
                local isOffGCD = GetSpellIsOffGCD(action.id)
                ActionMgr:RegisterAction(action.id, {
                    owner = "FuryWarrior",
                    priority = action.prio,
                    checkReady = action.check,
                    scope = action.scope,
                    isOffGCD = isOffGCD
                })
            end
        end

        local spellsToTrack = {
            C.Spells.BLOODTHIRST, C.Spells.WHIRLWIND, C.Spells.SLAM, C.Spells.EXECUTE,
            C.Spells.RECKLESSNESS, C.Spells.DEATH_WISH, C.Spells.BERSERKER_RAGE,
            C.Spells.SHATTERING_THROW, C.Spells.PUMMEL, C.Spells.HEROIC_THROW,
            C.Spells.BLOOD_FURY, C.Spells.BERSERKING, C.Spells.REND, C.Spells.OVERPOWER,
            C.Spells.BLOODRAGE, C.Spells.BATTLE_STANCE_CAST, C.Spells.BERSERKER_STANCE_CAST
        }
        if CD then
            for _, spellID in ipairs(spellsToTrack) do if spellID then CD:TrackSpell(spellID) end end
            CD:TrackItem(C.Items.POTION_HASTE)
            WRA:PrintDebug("FuryWarrior Cooldowns/Items Registered for Tracking.")
        else WRA:PrintError("FuryWarrior Error: CooldownTracker not found. Tracking skipped.") end

        WRA:PrintDebug("FuryWarrior Actions Registered with ActionManager.")
    else WRA:PrintError("FuryWarrior Error: ActionManager or Constants (Spells, Items, Auras, SpellData) not found/valid. Actions/Tracking skipped.") end
end

function FuryWarrior:OnEnable()
    if not DB then
        if WRA.db and type(WRA.db.profile) == "table" then
            if type(WRA.db.profile.specs) ~= "table" then WRA.db.profile.specs = {} end
            if type(WRA.db.profile.specs.FuryWarrior) ~= "table" then WRA.db.profile.specs.FuryWarrior = {} end
            DB = WRA.db.profile.specs.FuryWarrior
            WRA:PrintDebug("FuryWarrior DB reference acquired on enable.")
        else
             WRA:PrintError("FuryWarrior Error: WRA.db or WRA.db.profile is not correctly initialized during OnEnable!")
        end
    end

    if not C then C = WRA.Constants end
    if not Swing then Swing = WRA.SwingTimer end
    if not State then State = WRA.StateManager end
    if not CD then CD = WRA.CooldownTracker end
    if not Aura then Aura = WRA.AuraMonitor end
    if not ActionMgr then ActionMgr = WRA.ActionManager end
    if not Utils then Utils = WRA.Utils end

    if not DB then WRA:PrintError("FuryWarrior CRITICAL ERROR: DB reference is NIL in OnEnable!") end
    if not C then WRA:PrintError("FuryWarrior Error: Constants module still not available on Enable!") end

    WRA:PrintDebug("FuryWarrior Module Enabled.")
end

function FuryWarrior:OnDisable()
    WRA:PrintDebug("FuryWarrior Module Disabled.")
end

IsReady = function(actionID, state, skipGCDCheckOverride)
    if not C or not C.Spells or not C.Items or not C.SpellData or not State or not CD or not Aura or not DB then
        return false
    end
    if not state or not state.player then return false end
    if state.player.isDead or state.player.isFeigning then return false end

    local spellData = C.SpellData[actionID] or {}
    local isOffGCDAction = spellData.isOffGCD or false
    local triggersLocalGCD = spellData.triggersGCD

    if not skipGCDCheckOverride then
        if not isOffGCDAction and state.player.isGCDActive then
            return false
        end
    end

    if not isOffGCDAction and (state.player.isCasting or state.player.isChanneling) then
        return false
    end
    if not CD:IsReady(actionID) then
        return false
    end

    if actionID == C.Spells.HEROIC_STRIKE or actionID == C.Spells.CLEAVE then
        if IsCurrentSpell(actionID) then
            return false
        end
    end

    local currentRage = state.player.power
    local rageCost = spellData.cost or 0
    if not isOffGCDAction or triggersLocalGCD then
        if actionID == C.Spells.SLAM and Aura:HasBuff(C.Auras.BLOODSURGE, "player") then
            rageCost = 0
        end
        if currentRage < rageCost then
            return false
        end
    end
    if (actionID == C.Spells.HEROIC_STRIKE or actionID == C.Spells.CLEAVE) and currentRage < rageCost then
        return false
    end

    local requiredRange = spellData.range
    if requiredRange and requiredRange > 0 then
        if not state.target or not state.target.exists or not state.target.isEnemy or not UnitCanAttack("player", "target") then
            return false
        end
        if not State:IsSpellInRange(actionID, "target") then return false end
    end

    local currentStanceID = GetShapeshiftFormID()
    if actionID == C.Spells.REND or actionID == C.Spells.OVERPOWER then
        if currentStanceID ~= C.Stances.BATTLE then
            return false
        end
    elseif actionID == C.Spells.BERSERKER_RAGE or actionID == C.Spells.WHIRLWIND or actionID == C.Spells.INTERCEPT then
         if currentStanceID ~= C.Stances.BERSERKER then
            return false
         end
    end

    if actionID == C.Spells.EXECUTE then
        if not state.target or not state.target.exists or not state.target.healthPercent or state.target.healthPercent >= 20 then
            return false
        end
    elseif actionID == C.Spells.SLAM then
        if not Aura:HasBuff(C.Auras.BLOODSURGE, "player") then return false end
    elseif actionID == C.Spells.WHIRLWIND then
        local useWW = DB.useWhirlwind
        if useWW == false then
            return false
        end
    elseif actionID == C.Spells.REND then
        if DB.useRend == false then return false end
        if not state.target or not state.target.exists or not C.Auras then return false end
        if Aura:HasDebuff(C.Auras.REND_DEBUFF, "target", true) then return false end
    elseif actionID == C.Spells.OVERPOWER then
        if DB.useOverpower == false then return false end
    elseif actionID == C.Spells.PUMMEL then
        if DB.useInterrupts == false then return false end
        if not state.target or not state.target.exists or (not state.target.isCasting and not state.target.isChanneling) then
            return false
        end
    elseif actionID == C.Spells.BLOODRAGE then
        if state.player.power > LOW_RAGE_THRESHOLD_BLOODRAGE then
            return false
        end
    elseif actionID == C.Spells.HEROIC_THROW then
        if not Swing or not CD then return false end
        local mainHandRem = Swing:GetMainHandRemaining()
        local btRem = CD:GetCooldownRemaining(C.Spells.BLOODTHIRST)
        local wwRem = CD:GetCooldownRemaining(C.Spells.WHIRLWIND)
        if mainHandRem <= HEROIC_THROW_SWING_THRESHOLD then return false end
        if btRem <= BT_WW_COOLDOWN_THRESHOLD then return false end
        if wwRem <= BT_WW_COOLDOWN_THRESHOLD then return false end
    elseif actionID == C.Items.POTION_HASTE then
        if DB.usePotions == false then return false end
        if not state.player.inCombat then return false end
        if not C.Auras.DEATH_WISH_BUFF or not Aura:HasBuff(C.Auras.DEATH_WISH_BUFF, "player") then
            return false
        end
    end
    return true
end

function FuryWarrior:GetQueuedOffGCDAction(state)
    if not C or not C.Spells or not IsReady or not DB then return nil end
    if not state or not state.player or not state.target or not state.target.exists then return nil end

    local hsCleaveMinRage = C.HS_CLEAVE_MIN_RAGE or HS_CLEAVE_MIN_RAGE_DEFAULT
    if state.player.power < hsCleaveMinRage then return nil end

    local enableCleaveOverride = DB.enableCleave
    local smartAOEEnabled = DB.smartAOE
    local numTargets = State:GetNearbyEnemyCount() or 1
    local candidateAction = nil

    if enableCleaveOverride then
        if IsReady(C.Spells.CLEAVE, state, true) then
            candidateAction = C.Spells.CLEAVE
        end
    elseif smartAOEEnabled and numTargets >= CLEAVE_HS_AOE_THRESHOLD then
        if IsReady(C.Spells.CLEAVE, state, true) then
            candidateAction = C.Spells.CLEAVE
        end
    end

    if not candidateAction then
        if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        end
    end

    if enableCleaveOverride and candidateAction == C.Spells.CLEAVE and not IsReady(C.Spells.CLEAVE, state, true) then
        if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        else
            candidateAction = nil
        end
    end
    if smartAOEEnabled and numTargets >= CLEAVE_HS_AOE_THRESHOLD and candidateAction == C.Spells.CLEAVE and not IsReady(C.Spells.CLEAVE, state, true) then
         if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        else
            candidateAction = nil
        end
    end
    return candidateAction
end

function FuryWarrior:NeedsShoutRefresh(state)
    if not Aura or not DB or not C or not C.Spells or not C.Auras or not IsReady then return nil end
    if DB.useShouts == false then return nil end
    if not state or not state.player then return nil end

    local preferredShoutBuff = C.Auras.BATTLE_SHOUT_BUFF
    local preferredShoutSpell = C.Spells.BATTLE_SHOUT

    if not Aura:HasBuff(preferredShoutBuff, "player") then
        if IsReady(preferredShoutSpell, state) then return preferredShoutSpell end
    end
    return nil
end

function FuryWarrior:GetNextAction(currentState)
    local suggestedGcdAction = nil
    local suggestedOffGcdAction = nil

    if not State or not ActionMgr or not DB or not C or not C.Spells or not C.Auras or not IsReady or not CD or not Swing then
        return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
    end
    if not currentState or not currentState.player or not currentState.player.inCombat then
        return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
    end
    if not currentState.target or not currentState.target.exists or not currentState.target.isEnemy or currentState.target.isDead then
        if not (currentState.player.isCasting or currentState.player.isChanneling) then
            return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
        end
    end

    local playerState = currentState.player
    local targetState = currentState.target
    local currentStanceID = GetShapeshiftFormID()
    local isBerserkerStance = currentStanceID == C.Stances.BERSERKER
    local isBattleStance = currentStanceID == C.Stances.BATTLE

    if DB.useInterrupts and targetState and (targetState.isCasting or targetState.isChanneling) then
        if IsReady(C.Spells.PUMMEL, currentState) then
            suggestedOffGcdAction = C.Spells.PUMMEL
        end
    end

    if not suggestedOffGcdAction then
        suggestedOffGcdAction = self:GetQueuedOffGCDAction(currentState)
    end

    if not suggestedOffGcdAction and IsReady(C.Spells.BLOODRAGE, currentState) then
        suggestedOffGcdAction = C.Spells.BLOODRAGE
    end

    if playerState.isCasting or playerState.isChanneling then
        suggestedGcdAction = ACTION_ID_CASTING
        return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
    end
    if playerState.isGCDActive then
        suggestedGcdAction = ACTION_ID_WAITING
        return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
    end

    local canStanceDance = CD:GetCooldownRemaining(C.Spells.BLOODTHIRST) > BT_WW_COOLDOWN_THRESHOLD and
                           CD:GetCooldownRemaining(C.Spells.WHIRLWIND) > BT_WW_COOLDOWN_THRESHOLD

    if DB.useRend and canStanceDance and not Aura:HasDebuff(C.Auras.REND_DEBUFF, "target", true) then
        if not isBattleStance then
            if IsReady(C.Spells.BATTLE_STANCE_CAST, currentState) then
                suggestedGcdAction = C.Spells.BATTLE_STANCE_CAST
                return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
            end
        else
            if IsReady(C.Spells.REND, currentState) then
                suggestedGcdAction = C.Spells.REND
                return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
            end
        end
    end

    if DB.useOverpower and canStanceDance and IsReady(C.Spells.OVERPOWER, currentState) then
        if not isBattleStance then
             if IsReady(C.Spells.BATTLE_STANCE_CAST, currentState) then
                 suggestedGcdAction = C.Spells.BATTLE_STANCE_CAST
                 return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
             end
        else
            suggestedGcdAction = C.Spells.OVERPOWER
            return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
        end
    end

    if isBattleStance and not isBerserkerStance and (suggestedGcdAction == nil or suggestedGcdAction == ACTION_ID_IDLE) then
        if IsReady(C.Spells.BERSERKER_STANCE_CAST, currentState) then
             suggestedGcdAction = C.Spells.BERSERKER_STANCE_CAST
             return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
        end
    end

    if IsReady(C.Spells.BLOODTHIRST, currentState) then
        suggestedGcdAction = C.Spells.BLOODTHIRST
    elseif IsReady(C.Spells.WHIRLWIND, currentState) then
        suggestedGcdAction = C.Spells.WHIRLWIND
    elseif Aura:HasBuff(C.Auras.BLOODSURGE, "player") and IsReady(C.Spells.SLAM, currentState) then
        suggestedGcdAction = C.Spells.SLAM
    elseif targetState.healthPercent and targetState.healthPercent < 20 and IsReady(C.Spells.EXECUTE, currentState) then
        suggestedGcdAction = C.Spells.EXECUTE
    end

    if not suggestedGcdAction then
        if IsReady(C.Spells.HEROIC_THROW, currentState) then
            suggestedGcdAction = C.Spells.HEROIC_THROW
        end
    end

    if not suggestedGcdAction then
        local shoutAction = self:NeedsShoutRefresh(currentState)
        if shoutAction then
            suggestedGcdAction = shoutAction
        end
    end

    if not suggestedGcdAction and not isBerserkerStance then
         if IsReady(C.Spells.BERSERKER_STANCE_CAST, currentState) then
             suggestedGcdAction = C.Spells.BERSERKER_STANCE_CAST
         end
    end

    return {
        gcdAction = suggestedGcdAction or ACTION_ID_IDLE,
        offGcdAction = suggestedOffGcdAction
    }
end

-- This is the options table for Fury Warrior
-- IMPORTANT: 'name' and 'desc' fields should be KEY STRINGS that exist in your locale files.
local furyOptions = {
    header_rotation = {
        order = 1, type = "header", name = "SPEC_OPTIONS_FURYWARRIOR_HEADER_ROTATION"
    },
    useWhirlwind = {
        order = 10, type = "toggle", name = "OPTION_USE_WHIRLWIND_NAME", desc = "OPTION_USE_WHIRLWIND_DESC",
        get = function(info) return DB and DB.useWhirlwind end,
        set = function(info, v) if DB then DB.useWhirlwind = v end end,
    },
    useRend = {
        order = 20, type = "toggle", name = "OPTION_USE_REND_NAME", desc = "OPTION_USE_REND_DESC",
        get = function(info) return DB and DB.useRend end,
        set = function(info, v) if DB then DB.useRend = v end end,
    },
    useOverpower = {
        order = 30, type = "toggle", name = "OPTION_USE_OVERPOWER_NAME", desc = "OPTION_USE_OVERPOWER_DESC",
        get = function(info) return DB and DB.useOverpower end,
        set = function(info, v) if DB then DB.useOverpower = v end end,
    },
    smartAOE = {
        order = 40, type = "toggle", name = "OPTION_SMART_AOE_NAME", desc = "OPTION_SMART_AOE_DESC",
        get = function(info) return DB and DB.smartAOE end,
        set = function(info, v) if DB then DB.smartAOE = v end end,
    },
    enableCleave = {
        order = 50, type = "toggle", name = "OPTION_ENABLE_CLEAVE_NAME", desc = "OPTION_ENABLE_CLEAVE_DESC",
        get = function(info) return DB and DB.enableCleave end,
        set = function(info, v) if DB then DB.enableCleave = v end end,
    },
    header_cooldowns = {
        order = 100, type = "header", name = "SPEC_OPTIONS_FURYWARRIOR_HEADER_COOLDOWNS"
    },
    useRecklessness = {
        order = 110, type = "toggle", name = "OPTION_USE_RECKLESSNESS_NAME", desc = "OPTION_USE_RECKLESSNESS_DESC",
        get = function(info) return DB and DB.useRecklessness end,
        set = function(info, v) if DB then DB.useRecklessness = v end end,
    },
    useDeathWish = {
        order = 120, type = "toggle", name = "OPTION_USE_DEATH_WISH_NAME", desc = "OPTION_USE_DEATH_WISH_DESC",
        get = function(info) return DB and DB.useDeathWish end,
        set = function(info, v) if DB then DB.useDeathWish = v end end,
    },
    useBerserkerRage = {
        order = 130, type = "toggle", name = "OPTION_USE_BERSERKER_RAGE_NAME", desc = "OPTION_USE_BERSERKER_RAGE_DESC",
        get = function(info) return DB and DB.useBerserkerRage end,
        set = function(info, v) if DB then DB.useBerserkerRage = v end end,
    },
    header_utility = {
        order = 200, type = "header", name = "SPEC_OPTIONS_FURYWARRIOR_HEADER_UTILITY"
    },
     useShatteringThrow = {
        order = 210, type = "toggle", name = "OPTION_USE_SHATTERING_THROW_NAME", desc = "OPTION_USE_SHATTERING_THROW_DESC",
        get = function(info) return DB and DB.useShatteringThrow end,
        set = function(info, v) if DB then DB.useShatteringThrow = v end end,
    },
    useInterrupts = {
        order = 220, type = "toggle", name = "OPTION_USE_INTERRUPTS_NAME", desc = "OPTION_USE_INTERRUPTS_DESC",
        get = function(info) return DB and DB.useInterrupts end,
        set = function(info, v) if DB then DB.useInterrupts = v end end,
    },
    useShouts = {
        order = 230, type = "toggle", name = "OPTION_USE_SHOUTS_NAME", desc = "OPTION_USE_SHOUTS_DESC",
        get = function(info) return DB and DB.useShouts end,
        set = function(info, v) if DB then DB.useShouts = v end end,
    },
    header_consumables = {
        order = 300, type = "header", name = "SPEC_OPTIONS_FURYWARRIOR_HEADER_CONSUMABLES"
    },
    useTrinkets = {
        order = 310, type = "toggle", name = "OPTION_USE_TRINKETS_NAME", desc = "OPTION_USE_TRINKETS_DESC",
        get = function(info) return DB and DB.useTrinkets end,
        set = function(info, v) if DB then DB.useTrinkets = v end end,
    },
    usePotions = {
        order = 320, type = "toggle", name = "OPTION_USE_POTIONS_NAME", desc = "OPTION_USE_POTIONS_DESC",
        get = function(info) return DB and DB.usePotions end,
        set = function(info, v) if DB then DB.usePotions = v end end,
    },
    useRacials = {
        order = 330, type = "toggle", name = "OPTION_USE_RACIALS_NAME", desc = "OPTION_USE_RACIALS_DESC",
        get = function(info) return DB and DB.useRacials end,
        set = function(info, v) if DB then DB.useRacials = v end end,
    },
}

-- Function for SpecLoader to retrieve this options table
function WRA:GetSpecOptions_FuryWarrior()
    -- Ensure the spec DB table exists when options are first requested for this spec
    if WRA.db and WRA.db.profile and WRA.db.profile.specs and not WRA.db.profile.specs.FuryWarrior then
        WRA.db.profile.specs.FuryWarrior = {}
        -- Populate with defaults if necessary, though AceDB should handle this if defaults are structured correctly
         WRA:PrintDebug("Created missing FuryWarrior spec table in DB profile during GetSpecOptions.")
    end
    -- Assign DB to the local DB variable if it's not already set (e.g., if OnEnable hasn't fired yet but options are needed)
    -- This ensures that the 'get' and 'set' functions in furyOptions can access the correct DB table.
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.specs and WRA.db.profile.specs.FuryWarrior then
            DB = WRA.db.profile.specs.FuryWarrior
            if not DB then
                 WRA:PrintError("FuryWarrior:GetSpecOptions_FuryWarrior - Failed to assign DB reference even after check!")
            end
        else
            WRA:PrintError("FuryWarrior:GetSpecOptions_FuryWarrior - WRA.db.profile.specs.FuryWarrior not available for DB assignment!")
        end
    end
    return furyOptions
end

WRA:PrintDebug("Specs/FuryWarrior.lua loaded, options defined with localization keys.")
