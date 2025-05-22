-- wow addon/WRA/Specs/FuryWarrior.lua
-- v14: Modified GetNextAction to return {gcdAction, offGcdAction}.
--      Updated ActionManager registrations to include isOffGCD flag from Constants.SpellData.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local FuryWarrior = WRA:NewModule("FuryWarrior", "AceEvent-3.0")
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
local ACTION_ID_WAITING = 0
local ACTION_ID_IDLE = "IDLE"
local ACTION_ID_CASTING = "CASTING" -- Added for consistency, though less relevant for Fury

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
local DB = nil -- Spec-specific database profile

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
        if not C or not IsReady or not DB then return false end
        local optionKey = "use" .. spellIdKey -- e.g., "useRecklessness"
        local spellID = actionData.id -- actionData.id is the spellID passed during registration
        local success, result = pcall(function()
            -- Check the specific DB toggle for this cooldown
            if DB[optionKey] == false then return false end -- Explicitly check for false, nil/true means enabled by default or if key missing
            return IsReady(spellID, currentState)
        end)
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
local CheckShatteringThrow = CreateCheckReadyFunction("ShatteringThrow") -- Will add boss check in IsReady or GetNextAction
local CheckPotion = CreateCheckReadyFunction("Potions") -- Generic check, specific logic in IsReady if needed
local CheckRacial = CreateCheckReadyFunction("Racials")
local CheckTrinket = CreateCheckReadyFunction("Trinkets") -- Generic check for registered trinkets

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


    DB = nil -- DB reference will be set in OnEnable

    WRA:PrintDebug("FuryWarrior Module Initializing (DB assignment deferred to OnEnable)")

    if ActionMgr and C and C.Spells and C.Items and C.Auras and C.SpellData then
        -- Register Cooldowns / Utility Actions
        local actionsToRegister = {
            { id = C.Spells.RECKLESSNESS,    prio = 100, check = CheckRecklessness,    scope = "GCD" },
            { id = C.Spells.DEATH_WISH,      prio = 95,  check = CheckDeathWish,       scope = "GCD" },
            { id = C.Spells.BERSERKER_RAGE,  prio = 90,  check = CheckBerserkerRage,   scope = "GCD" },
            { id = C.Items.POTION_HASTE,     prio = 97,  check = CheckPotion,          scope = "GCD" }, -- Potions are typically on GCD in terms of usage timing
            { id = C.Spells.SHATTERING_THROW,prio = 80,  check = CheckShatteringThrow, scope = "GCD" },
            { id = C.Spells.BLOOD_FURY,      prio = 65,  check = CheckRacial,          scope = "GCD" }, -- Orc Racial
            { id = C.Spells.BERSERKING,      prio = 65,  check = CheckRacial,          scope = "GCD" }, -- Troll Racial
            -- Add other racials/trinkets here if they are to be managed by ActionManager
        }

        for _, action in ipairs(actionsToRegister) do
            if action.id then -- Ensure ID exists
                local isOffGCD = GetSpellIsOffGCD(action.id) -- Get from Constants.SpellData
                ActionMgr:RegisterAction(action.id, {
                    owner = "FuryWarrior",
                    priority = action.prio,
                    checkReady = action.check,
                    scope = action.scope,
                    isOffGCD = isOffGCD -- Pass the flag
                })
            end
        end

        -- Track spells with CooldownTracker
        local spellsToTrack = {
            C.Spells.BLOODTHIRST, C.Spells.WHIRLWIND, C.Spells.SLAM, C.Spells.EXECUTE,
            C.Spells.RECKLESSNESS, C.Spells.DEATH_WISH, C.Spells.BERSERKER_RAGE,
            C.Spells.SHATTERING_THROW, C.Spells.PUMMEL, C.Spells.HEROIC_THROW,
            C.Spells.BLOOD_FURY, C.Spells.BERSERKING, C.Spells.REND, C.Spells.OVERPOWER,
            C.Spells.BLOODRAGE, C.Spells.BATTLE_STANCE_CAST, C.Spells.BERSERKER_STANCE_CAST
        }
        if CD then
            for _, spellID in ipairs(spellsToTrack) do if spellID then CD:TrackSpell(spellID) end end
            CD:TrackItem(C.Items.POTION_HASTE) -- Example item
            WRA:PrintDebug("FuryWarrior Cooldowns/Items Registered for Tracking.")
        else WRA:PrintError("FuryWarrior Error: CooldownTracker not found. Tracking skipped.") end

        WRA:PrintDebug("FuryWarrior Actions Registered with ActionManager.")
    else WRA:PrintError("FuryWarrior Error: ActionManager or Constants (Spells, Items, Auras, SpellData) not found/valid. Actions/Tracking skipped.") end
end

function FuryWarrior:OnEnable()
    -- Ensure DB reference is set up
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
    -- ActionManager actions are typically unregistered by ActionManager itself if owner is specified,
    -- or if the addon is fully disabled. No need to manually unregister here unless specifically desired.
end

-- IsReady function: Checks if a specific actionID is usable given the current game state.
-- This function is crucial and needs to be robust.
IsReady = function(actionID, state, skipGCDCheckOverride)
    -- Basic checks for module readiness
    if not C or not C.Spells or not C.Items or not C.SpellData or not State or not CD or not Aura or not DB then
        WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Core modules or DB not ready.")
        return false
    end
    if not state or not state.player then
        WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Invalid state or player data.")
        return false
    end
    if state.player.isDead or state.player.isFeigning then
        WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Player dead or feigning.")
        return false
    end

    local spellData = C.SpellData[actionID] or {}
    local isOffGCDAction = spellData.isOffGCD or false
    local triggersLocalGCD = spellData.triggersGCD -- If this specific action triggers a GCD

    -- 1. GCD Check (Primary filter for GCD actions)
    if not skipGCDCheckOverride then -- Allow override for specific internal checks (like HS/Cleave queueing)
        if not isOffGCDAction and state.player.isGCDActive then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: On GCD and action is not Off-GCD.")
            return false
        end
    end

    -- 2. Casting/Channeling Check (Primary filter for GCD actions)
    if not isOffGCDAction and (state.player.isCasting or state.player.isChanneling) then
        -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Player casting/channeling and action is not Off-GCD.")
        return false
    end

    -- 3. Cooldown Check (Applies to all actions)
    if not CD:IsReady(actionID) then
        -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: CD:IsReady returned false. Remaining: ", string_format("%.2f", CD:GetCooldownRemaining(actionID)))
        return false
    end

    -- 4. Specific "on next swing" logic for Heroic Strike / Cleave
    if actionID == C.Spells.HEROIC_STRIKE or actionID == C.Spells.CLEAVE then
        if IsCurrentSpell(actionID) then -- Check if already queued
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Already queued (IsCurrentSpell).")
            return false
        end
    end

    -- 5. Resource Check (Rage for spells)
    local currentRage = state.player.power
    local rageCost = spellData.cost or 0
    if not isOffGCDAction or triggersLocalGCD then -- Most spells, even instant ones, have a cost if they are on GCD
        if actionID == C.Spells.SLAM and Aura:HasBuff(C.Auras.BLOODSURGE, "player") then
            rageCost = 0 -- Bloodsurge Slam is free
        end
        if currentRage < rageCost then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Insufficient Rage. Have: ", currentRage, ", Need: ", rageCost)
            return false
        end
    end
    -- For Off-GCD like HS/Cleave, rage check is often done *before* deciding to queue,
    -- but an additional check here is fine.
    if (actionID == C.Spells.HEROIC_STRIKE or actionID == C.Spells.CLEAVE) and currentRage < rageCost then
         -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Insufficient Rage for HS/Cleave. Have: ", currentRage, ", Need: ", rageCost)
        return false
    end


    -- 6. Range Check (If applicable)
    local requiredRange = spellData.range
    if requiredRange and requiredRange > 0 then
        if not state.target or not state.target.exists or not state.target.isEnemy or not UnitCanAttack("player", "target") then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Invalid target for range check.")
            return false
        end
        -- State:IsSpellInRange now uses LibRangeCheck or Blizzard API
        if not State:IsSpellInRange(actionID, "target") then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Out of Range.")
            return false
        end
    end

    -- 7. Stance Check (If applicable, e.g. Rend, Overpower)
    local currentStanceID = GetShapeshiftFormID()
    if actionID == C.Spells.REND or actionID == C.Spells.OVERPOWER then
        if currentStanceID ~= C.Stances.BATTLE then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Not in Battle Stance.")
            return false
        end
    elseif actionID == C.Spells.BERSERKER_RAGE or actionID == C.Spells.WHIRLWIND or actionID == C.Spells.INTERCEPT then
         if currentStanceID ~= C.Stances.BERSERKER then
            -- WRA:PrintDebug("IsReady (", tostring(actionID), ") fail: Not in Berserker Stance for WW/BRage/Intercept.")
            return false
         end
    end


    -- 8. Specific Spell Conditions
    if actionID == C.Spells.EXECUTE then
        if not state.target or not state.target.exists or not state.target.healthPercent or state.target.healthPercent >= 20 then
            return false
        end
    elseif actionID == C.Spells.SLAM then -- This is Bloodsurge Slam
        if not Aura:HasBuff(C.Auras.BLOODSURGE, "player") then
            return false
        end
    elseif actionID == C.Spells.WHIRLWIND then
        local useWW = DB.useWhirlwind -- Get from spec DB
        if useWW == false then -- Explicitly check for false, nil/true means enabled
            -- WRA:PrintDebug("IsReady (WW) fail: DB.useWhirlwind toggle is false.")
            return false
        end
    elseif actionID == C.Spells.REND then
        if DB.useRend == false then return false end
        if not state.target or not state.target.exists or not C.Auras then return false end
        if Aura:HasDebuff(C.Auras.REND_DEBUFF, "target", true) then return false end -- Check REND_DEBUFF
    elseif actionID == C.Spells.OVERPOWER then
        if DB.useOverpower == false then return false end
        -- Overpower readiness is complex; WoW API doesn't have a simple "IsOverpowerReady".
        -- It's usable after target dodges. This check might be better handled by RotationEngine
        -- based on combat log events or a more sophisticated AuraMonitor for dodge procs.
        -- For now, IsReady for Overpower just means CD is up and in stance. Actual proc check is in GetNextAction.
        -- if not Aura:HasBuff(C.Auras.OVERPOWER_PROC, "player") then return false end -- This was a placeholder
    elseif actionID == C.Spells.PUMMEL then
        if DB.useInterrupts == false then return false end
        if not state.target or not state.target.exists or (not state.target.isCasting and not state.target.isChanneling) then
            return false
        end
    elseif actionID == C.Spells.BLOODRAGE then
        -- Berserker Rage is handled by ActionManager, Bloodrage is for rage generation
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
    elseif actionID == C.Items.POTION_HASTE then -- Potion of Speed specific logic
        if DB.usePotions == false then return false end
        if not state.player.inCombat then return false end
        -- Only use if a major CD like Death Wish is active
        if not C.Auras.DEATH_WISH_BUFF or not Aura:HasBuff(C.Auras.DEATH_WISH_BUFF, "player") then
            return false
        end
    end

    return true
end

-- Determines if Heroic Strike or Cleave should be queued.
-- Returns the spellID of HS or Cleave if conditions met, otherwise nil.
function FuryWarrior:GetQueuedOffGCDAction(state)
    if not C or not C.Spells or not IsReady or not DB then return nil end
    if not state or not state.player or not state.target or not state.target.exists then return nil end

    local hsCleaveMinRage = C.HS_CLEAVE_MIN_RAGE or HS_CLEAVE_MIN_RAGE_DEFAULT
    if state.player.power < hsCleaveMinRage then return nil end -- Not enough rage to even consider

    local enableCleaveOverride = DB.enableCleave
    local smartAOEEnabled = DB.smartAOE
    local numTargets = State:GetNearbyEnemyCount() or 1

    local candidateAction = nil

    if enableCleaveOverride then -- User forces Cleave
        if IsReady(C.Spells.CLEAVE, state, true) then -- true to skip GCD check for queueing logic
            candidateAction = C.Spells.CLEAVE
        end
    elseif smartAOEEnabled and numTargets >= CLEAVE_HS_AOE_THRESHOLD then -- Smart AOE suggests Cleave
        if IsReady(C.Spells.CLEAVE, state, true) then
            candidateAction = C.Spells.CLEAVE
        end
    end

    -- If Cleave wasn't chosen (or wasn't ready), try Heroic Strike
    if not candidateAction then
        if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        end
    end

    -- If Cleave was chosen due to override/smartAOE but wasn't ready, fallback to HS if HS is ready
    if enableCleaveOverride and candidateAction == C.Spells.CLEAVE and not IsReady(C.Spells.CLEAVE, state, true) then
        if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        else
            candidateAction = nil -- Neither ready
        end
    end
    if smartAOEEnabled and numTargets >= CLEAVE_HS_AOE_THRESHOLD and candidateAction == C.Spells.CLEAVE and not IsReady(C.Spells.CLEAVE, state, true) then
         if IsReady(C.Spells.HEROIC_STRIKE, state, true) then
            candidateAction = C.Spells.HEROIC_STRIKE
        else
            candidateAction = nil -- Neither ready
        end
    end


    return candidateAction
end

function FuryWarrior:NeedsShoutRefresh(state)
    if not Aura or not DB or not C or not C.Spells or not C.Auras or not IsReady then return nil end
    if DB.useShouts == false then return nil end
    if not state or not state.player then return nil end

    -- Prioritize Battle Shout if talented for Commanding Presence, otherwise Commanding if tanking etc.
    -- Simplified: Just check Battle Shout for now.
    local preferredShoutBuff = C.Auras.BATTLE_SHOUT_BUFF
    local preferredShoutSpell = C.Spells.BATTLE_SHOUT

    if not Aura:HasBuff(preferredShoutBuff, "player") then
        if IsReady(preferredShoutSpell, state) then return preferredShoutSpell end
    end
    return nil
end

-- Main decision function, now returns a table { gcdAction = id, offGcdAction = id }
function FuryWarrior:GetNextAction(currentState)
    local suggestedGcdAction = nil
    local suggestedOffGcdAction = nil

    -- Ensure all necessary modules and data are available
    if not State or not ActionMgr or not DB or not C or not C.Spells or not C.Auras or not IsReady or not CD or not Swing then
        WRA:PrintDebug("FuryWarrior:GetNextAction Aborting - Missing core modules or DB")
        return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
    end
    if not currentState or not currentState.player or not currentState.player.inCombat then
        return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
    end
    if not currentState.target or not currentState.target.exists or not currentState.target.isEnemy or currentState.target.isDead then
        if not (currentState.player.isCasting or currentState.player.isChanneling) then -- Allow some actions if casting (e.g. self-buffs)
            return { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
        end
    end

    local playerState = currentState.player
    local targetState = currentState.target
    local currentStanceID = GetShapeshiftFormID()
    local isBerserkerStance = currentStanceID == C.Stances.BERSERKER
    local isBattleStance = currentStanceID == C.Stances.BATTLE

    -- 0. Off-GCD: Interrupts (Highest Priority Off-GCD)
    if DB.useInterrupts and targetState and (targetState.isCasting or targetState.isChanneling) then
        if IsReady(C.Spells.PUMMEL, currentState) then
            suggestedOffGcdAction = C.Spells.PUMMEL
            -- Pummel is off-GCD, so we can still suggest a GCD action.
            -- However, if an interrupt is critical, we might not want to suggest anything else.
            -- For now, let it be suggested alongside a GCD action.
        end
    end

    -- 1. Off-GCD: Heroic Strike / Cleave (Rage Dump)
    -- This should be checked frequently as it's an "on next swing" ability.
    -- Its readiness (IsReady) already checks rage.
    if not suggestedOffGcdAction then -- Only if Pummel wasn't suggested
        suggestedOffGcdAction = self:GetQueuedOffGCDAction(currentState)
    end

    -- 2. Off-GCD: Bloodrage (Rage Generation)
    if not suggestedOffGcdAction and IsReady(C.Spells.BLOODRAGE, currentState) then
        suggestedOffGcdAction = C.Spells.BLOODRAGE
    end

    -- Now, determine the GCD action.
    -- Player is casting or GCD is active (and not an off-GCD action that bypasses this)
    if playerState.isCasting or playerState.isChanneling then
        suggestedGcdAction = ACTION_ID_CASTING
        return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
    end
    if playerState.isGCDActive then
        suggestedGcdAction = ACTION_ID_WAITING
        return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
    end


    -- Priority list for GCD actions:
    -- This is a simplified version. ActionManager will handle major CDs based on its own priority.

    -- Stance dancing for Rend/Overpower
    local canStanceDance = CD:GetCooldownRemaining(C.Spells.BLOODTHIRST) > BT_WW_COOLDOWN_THRESHOLD and
                           CD:GetCooldownRemaining(C.Spells.WHIRLWIND) > BT_WW_COOLDOWN_THRESHOLD

    if DB.useRend and canStanceDance and not Aura:HasDebuff(C.Auras.REND_DEBUFF, "target", true) then
        if not isBattleStance then
            if IsReady(C.Spells.BATTLE_STANCE_CAST, currentState) then
                suggestedGcdAction = C.Spells.BATTLE_STANCE_CAST
                return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
            end
        else -- Already in Battle Stance
            if IsReady(C.Spells.REND, currentState) then
                suggestedGcdAction = C.Spells.REND
                return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
            end
        end
    end

    -- Overpower (requires target dodge, this logic is simplified here)
    -- A real implementation would check for a "target dodged" event or aura.
    -- Assuming IsReady(OVERPOWER) implies it's usable (e.g. proc active)
    if DB.useOverpower and canStanceDance and IsReady(C.Spells.OVERPOWER, currentState) then
        if not isBattleStance then
             if IsReady(C.Spells.BATTLE_STANCE_CAST, currentState) then
                 suggestedGcdAction = C.Spells.BATTLE_STANCE_CAST
                 return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
             end
        else -- Already in Battle Stance
            suggestedGcdAction = C.Spells.OVERPOWER
            return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
        end
    end

    -- If we were in Battle Stance for Rend/OP but didn't use them, and Berserker is preferred:
    if isBattleStance and not isBerserkerStance and (suggestedGcdAction == nil or suggestedGcdAction == ACTION_ID_IDLE) then
        if IsReady(C.Spells.BERSERKER_STANCE_CAST, currentState) then
             suggestedGcdAction = C.Spells.BERSERKER_STANCE_CAST
             return { gcdAction = suggestedGcdAction, offGcdAction = suggestedOffGcdAction }
        end
    end


    -- Core Rotational GCD Abilities (primarily in Berserker Stance)
    if IsReady(C.Spells.BLOODTHIRST, currentState) then
        suggestedGcdAction = C.Spells.BLOODTHIRST
    elseif IsReady(C.Spells.WHIRLWIND, currentState) then -- Requires Berserker Stance
        suggestedGcdAction = C.Spells.WHIRLWIND
    elseif Aura:HasBuff(C.Auras.BLOODSURGE, "player") and IsReady(C.Spells.SLAM, currentState) then -- Bloodsurge Slam
        suggestedGcdAction = C.Spells.SLAM
    elseif targetState.healthPercent and targetState.healthPercent < 20 and IsReady(C.Spells.EXECUTE, currentState) then
        suggestedGcdAction = C.Spells.EXECUTE
    end

    -- Filler GCD
    if not suggestedGcdAction then
        if IsReady(C.Spells.HEROIC_THROW, currentState) then
            suggestedGcdAction = C.Spells.HEROIC_THROW
        end
    end

    -- Low priority GCD: Shouts
    if not suggestedGcdAction then
        local shoutAction = self:NeedsShoutRefresh(currentState)
        if shoutAction then
            suggestedGcdAction = shoutAction
        end
    end

    -- Fallback Stance if nothing else to do and not in Berserker
    if not suggestedGcdAction and not isBerserkerStance then
         if IsReady(C.Spells.BERSERKER_STANCE_CAST, currentState) then
             suggestedGcdAction = C.Spells.BERSERKER_STANCE_CAST
         end
    end

    return {
        gcdAction = suggestedGcdAction or ACTION_ID_IDLE,
        offGcdAction = suggestedOffGcdAction -- This might be nil
    }
end


-- Function to provide options to the main OptionsPanel
function WRA:GetSpecOptions_FuryWarrior()
    -- This function remains largely the same as before,
    -- as it defines the available toggles in the options panel.
    -- The DB table it reads/writes to is WRA.db.profile.specs.FuryWarrior
    local function GetSpecDBValue(key)
        return (DB and DB[key])
    end
    local function SetSpecDBValue(key, value)
        if DB then
            DB[key] = value
            WRA:PrintDebug("[SpecOptions Set] Key:", key, "New Value:", tostring(value))
            -- If QuickConfig panel is visible, refresh it
            if WRA.QuickConfig and WRA.QuickConfig.RefreshPanel then
                -- Check if quickPanelFrame exists and is shown (global or from QuickConfig module)
                local qcFrame = _G.quickPanelFrame -- Assuming QuickConfig stores it globally for access
                if qcFrame and qcFrame.frame and qcFrame.frame:IsShown() then
                     WRA.QuickConfig:RefreshPanel()
                end
            end
        else
            WRA:PrintError("Cannot set spec option, DB reference is nil!")
        end
    end

    return {
        rotationHeader = {
            order = 1, type = "header", name = L["SPEC_OPTIONS_FURYWARRIOR_HEADER_ROTATION"]
        },
        useWhirlwind = {
            order = 10, type = "toggle", name = L["OPTION_USE_WHIRLWIND_NAME"], desc = L["OPTION_USE_WHIRLWIND_DESC"],
            get = function() return GetSpecDBValue("useWhirlwind") end,
            set = function(info, v) SetSpecDBValue("useWhirlwind", v) end,
        },
        useRend = {
            order = 20, type = "toggle", name = L["OPTION_USE_REND_NAME"], desc = L["OPTION_USE_REND_DESC"],
            get = function() return GetSpecDBValue("useRend") end,
            set = function(info, v) SetSpecDBValue("useRend", v) end,
        },
        useOverpower = {
            order = 30, type = "toggle", name = L["OPTION_USE_OVERPOWER_NAME"], desc = L["OPTION_USE_OVERPOWER_DESC"],
            get = function() return GetSpecDBValue("useOverpower") end,
            set = function(info, v) SetSpecDBValue("useOverpower", v) end,
        },
        smartAOE = {
            order = 40, type = "toggle", name = L["OPTION_SMART_AOE_NAME"], desc = L["OPTION_SMART_AOE_DESC"],
            get = function() return GetSpecDBValue("smartAOE") end,
            set = function(info, v) SetSpecDBValue("smartAOE", v) end,
        },
        enableCleave = { -- This is the "Force Cleave" option
            order = 50, type = "toggle", name = L["OPTION_ENABLE_CLEAVE_NAME"], desc = L["OPTION_ENABLE_CLEAVE_DESC"],
            get = function() return GetSpecDBValue("enableCleave") end,
            set = function(info, v) SetSpecDBValue("enableCleave", v) end,
        },
        cooldownHeader = {
            order = 100, type = "header", name = L["SPEC_OPTIONS_FURYWARRIOR_HEADER_COOLDOWNS"]
        },
        useRecklessness = {
            order = 110, type = "toggle", name = L["OPTION_USE_RECKLESSNESS_NAME"], desc = L["OPTION_USE_RECKLESSNESS_DESC"],
            get = function() return GetSpecDBValue("useRecklessness") end,
            set = function(info, v) SetSpecDBValue("useRecklessness", v) end,
        },
        useDeathWish = {
            order = 120, type = "toggle", name = L["OPTION_USE_DEATH_WISH_NAME"], desc = L["OPTION_USE_DEATH_WISH_DESC"],
            get = function() return GetSpecDBValue("useDeathWish") end,
            set = function(info, v) SetSpecDBValue("useDeathWish", v) end,
        },
        useBerserkerRage = {
            order = 130, type = "toggle", name = L["OPTION_USE_BERSERKER_RAGE_NAME"], desc = L["OPTION_USE_BERSERKER_RAGE_DESC"],
            get = function() return GetSpecDBValue("useBerserkerRage") end,
            set = function(info, v) SetSpecDBValue("useBerserkerRage", v) end,
        },
        utilityHeader = {
            order = 200, type = "header", name = L["SPEC_OPTIONS_FURYWARRIOR_HEADER_UTILITY"]
        },
         useShatteringThrow = {
            order = 210, type = "toggle", name = L["OPTION_USE_SHATTERING_THROW_NAME"], desc = L["OPTION_USE_SHATTERING_THROW_DESC"],
            get = function() return GetSpecDBValue("useShatteringThrow") end,
            set = function(info, v) SetSpecDBValue("useShatteringThrow", v) end,
        },
        useInterrupts = {
            order = 220, type = "toggle", name = L["OPTION_USE_INTERRUPTS_NAME"], desc = L["OPTION_USE_INTERRUPTS_DESC"],
            get = function() return GetSpecDBValue("useInterrupts") end,
            set = function(info, v) SetSpecDBValue("useInterrupts", v) end,
        },
        useShouts = {
            order = 230, type = "toggle", name = L["OPTION_USE_SHOUTS_NAME"], desc = L["OPTION_USE_SHOUTS_DESC"],
            get = function() return GetSpecDBValue("useShouts") end,
            set = function(info, v) SetSpecDBValue("useShouts", v) end,
        },
        consumableHeader = {
            order = 300, type = "header", name = L["SPEC_OPTIONS_FURYWARRIOR_HEADER_CONSUMABLES"]
        },
        useTrinkets = {
            order = 310, type = "toggle", name = L["OPTION_USE_TRINKETS_NAME"], desc = L["OPTION_USE_TRINKETS_DESC"],
            get = function() return GetSpecDBValue("useTrinkets") end,
            set = function(info, v) SetSpecDBValue("useTrinkets", v) end,
        },
        usePotions = {
            order = 320, type = "toggle", name = L["OPTION_USE_POTIONS_NAME"], desc = L["OPTION_USE_POTIONS_DESC"],
            get = function() return GetSpecDBValue("usePotions") end,
            set = function(info, v) SetSpecDBValue("usePotions", v) end,
        },
        useRacials = {
            order = 330, type = "toggle", name = L["OPTION_USE_RACIALS_NAME"], desc = L["OPTION_USE_RACIALS_DESC"],
            get = function() return GetSpecDBValue("useRacials") end,
            set = function(info, v) SetSpecDBValue("useRacials", v) end,
        },
    }
end
