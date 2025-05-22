-- wow addon/WRA/Common/StateManager.lua
-- v13 (Range Fix 강화): Added stricter internal check for LibRange before method call and refined LibRange path logic.
-- v14 (LibRange Usage Fix): Correctly use LibRange:GetRange() and compare yardages.
-- v15 (Final Range Logic Fix): Corrected yardage comparison logic in LibRange Path.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local StateManager = WRA:NewModule("StateManager", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

-- Lua shortcuts
local GetTime = GetTime
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetSpellInfo = GetSpellInfo
local pairs = pairs
local type = type
local string_format = string.format
local pcall = pcall
local rawget = rawget
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local IsFeigningDeath = IsFeigningDeath
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitGUID = UnitGUID
local GetUnitSpeed = GetUnitSpeed
local GetSpellCooldown = GetSpellCooldown
local Nameplates = nil -- Forward declare
local Aura = nil
local CD = nil
local Swing = nil
local TTD = nil
local LibRange = nil
local Utils = nil
local SpecLoader = nil


-- currentState table structure (remains the same)
local currentState = {
    player = { guid = nil, inCombat = false, isDead = false, isMoving = false, isCasting = false, isChanneling = false, castSpellID = nil, castStartTime = 0, castEndTime = 0, channelEndTime = 0, gcdEndTime = 0, isGCDActive = false, health = 0, healthMax = 0, healthPercent = 100, power = 0, powerMax = 0, powerPercent = 100, powerType = "RAGE", isFeigning = false, threatSituation = 0, auras = {}, cooldowns = {}, swingTimer = { mainHand = 0, offHand = 0, ranged = 0 } },
    target = { guid = nil, exists = false, isEnemy = false, isFriend = false, isPlayer = false, isBoss = false, isDead = false, health = 0, healthMax = 0, healthPercent = 100, timeToDie = 0, inRange = {}, isCasting = false, castSpellID = nil, castStartTime = 0, castEndTime = 0, isChanneling = false, channelEndTime = 0, classification = "unknown", auras = {} },
    targettarget = { guid = nil, exists = false, isPlayer = false, isEnemy = false, isFriendly = false, healthPercent = 0, auras = {} },
    focus = { guid = nil, exists = false, healthPercent = 0, auras = {} },
    pet = { guid = nil, exists = false, healthPercent = 0, auras = {} },
    environment = { zoneID = 0, instanceType = "none", difficultyID = 0, numNearbyEnemies = 0, isPvP = false },
    lastUpdateTime = 0,
}

local updateInterval = 0.08
local rangeCheckInterval = 0.25

function StateManager:OnInitialize()
    Aura = WRA:GetModule("AuraMonitor")
    CD = WRA:GetModule("CooldownTracker")
    Swing = WRA:GetModule("SwingTimer")
    TTD = WRA:GetModule("TTDTracker")
    Nameplates = WRA:GetModule("NameplateTracker")
    Utils = WRA:GetModule("Utils")
    SpecLoader = WRA:GetModule("SpecLoader")

    LibRange = LibStub("LibRangeCheck-3.0", true)
    if not LibRange then
        WRA:PrintDebug("Warning: LibRangeCheck-3.0 not found or failed to load. LibRange will be nil.")
    else
        WRA:PrintDebug("LibRangeCheck-3.0 appears to be loaded/stubbed. Type: ", type(LibRange))
        if type(LibRange) == "table" then
            WRA:PrintDebug("  LibRange.GetRange type: ", type(LibRange.GetRange))
        end
    end

    if not SpecLoader then WRA:PrintError("StateManager Initialize: SpecLoader module not found!") end
    self:UpdateState()
    WRA:PrintDebug("StateManager Initialized.")
end

function StateManager:OnEnable()
    if not SpecLoader then SpecLoader = WRA:GetModule("SpecLoader") end
    if not TTD then TTD = WRA:GetModule("TTDTracker") end

    self.updateTimer = self:ScheduleRepeatingTimer("UpdateState", updateInterval)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "HandleCombatChange")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "HandleCombatChange")
    self:RegisterEvent("UNIT_HEALTH", "HandleUnitEvent")
    self:RegisterEvent("UNIT_MAXHEALTH", "HandleUnitEvent")
    self:RegisterEvent("UNIT_POWER_UPDATE", "HandleUnitEvent")
    self:RegisterEvent("UNIT_MAXPOWER", "HandleUnitEvent")
    self:RegisterEvent("UNIT_DISPLAYPOWER", "HandleUnitEvent")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "HandleTargetChange")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", "HandleUnitEvent")
    self:RegisterEvent("UNIT_SPELLCAST_START", "HandleCastStart")
    self:RegisterEvent("UNIT_SPELLCAST_STOP", "HandleCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "HandleCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_FAILED", "HandleCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", "HandleCastStop")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "HandleChannelStart")
    self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "HandleChannelStop")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateEnvironment")
    self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UpdateEnvironment")
    self:RegisterEvent("PLAYER_UNGHOST", "HandlePlayerAlive")
    self:RegisterEvent("PLAYER_ALIVE", "HandlePlayerAlive")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "HandleCooldownUpdate")
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", "HandleThreatUpdate")
    self:RegisterEvent("UNIT_AURA", "HandleUnitAura")

    WRA:PrintDebug("StateManager Enabled.")
    self:HandleCombatChange()
    self:HandleTargetChange()
    self:UpdateEnvironment()
    self:HandlePlayerAlive()
end

function StateManager:OnDisable()
    if self.updateTimer then self:CancelTimer(self.updateTimer); self.updateTimer = nil end
    self:UnregisterAllEvents()
    WRA:PrintDebug("StateManager Disabled.")
end

function StateManager:UpdateState()
    local now = GetTime()
    currentState.lastUpdateTime = now
    local player = currentState.player
    player.isDead = UnitIsDeadOrGhost("player")
    player.isFeigning = IsFeigningDeath and IsFeigningDeath() or false

    if not player.isDead and not player.isFeigning then
        player.health = UnitHealth("player")
        player.healthMax = UnitHealthMax("player")
        player.healthPercent = player.healthMax > 0 and (player.health / player.healthMax * 100) or 0
        player.power = UnitPower("player")
        player.powerMax = UnitPowerMax("player")
        player.powerPercent = player.powerMax > 0 and (player.power / player.powerMax * 100) or 0
        player.guid = player.guid or UnitGUID("player")
        player.isMoving = GetUnitSpeed("player") > 0
    else
        player.health, player.healthPercent, player.power, player.powerPercent, player.isMoving = 0, 0, 0, 0, false
    end

    local gcdStart, gcdDuration = GetSpellCooldown(0)
    if gcdStart and gcdDuration and gcdDuration > 0 then
        player.gcdEndTime = gcdStart + gcdDuration
        player.isGCDActive = player.gcdEndTime > now
    else
        player.isGCDActive, player.gcdEndTime = false, 0
    end

    if player.isCasting and now >= player.castEndTime then player.isCasting, player.castSpellID = false, nil end
    if player.isChanneling and now >= player.channelEndTime then player.isChanneling, player.castSpellID = false, nil end

    local target = currentState.target
    if UnitExists("target") then
        local targetGUID = UnitGUID("target")
        if target.guid ~= targetGUID then
            self:HandleTargetChange()
        else
            self:UpdateUnitState("target", target)
        end
    else
        if target.exists then
             wipe(target)
             target.exists, target.healthPercent, target.timeToDie, target.guid = false, 0, 0, nil
             target.inRange = {}
             target.auras = {}
        end
    end

    if Nameplates and Nameplates.GetNearbyEnemyCount then
        currentState.environment.numNearbyEnemies = Nameplates:GetNearbyEnemyCount()
    else
        currentState.environment.numNearbyEnemies = target.exists and target.isEnemy and 1 or 0
    end
end

function StateManager:HandleCombatChange()
    currentState.player.inCombat = UnitAffectingCombat("player")
    if not currentState.player.inCombat then
        if TTD and TTD.ResetAllTTD then TTD:ResetAllTTD() end
        currentState.player.isCasting, currentState.player.isChanneling, currentState.player.castSpellID = false, false, nil
        if currentState.target then currentState.target.isCasting, currentState.target.isChanneling, currentState.target.castSpellID = false, false, nil end
    end
    self:UpdateState()
end

function StateManager:HandleUnitEvent(event, unit)
    if unit == "player" or (unit == "target" and currentState.target.exists and UnitIsUnit(unit, "target")) then
        self:UpdateState()
    end
    if event == "UNIT_DISPLAYPOWER" and unit == "player" then
        local _, powerToken = UnitPowerType("player")
        currentState.player.powerType = powerToken or "UNKNOWN"
    end
end

function StateManager:HandleTargetChange()
    local target = currentState.target
    local oldGuid = target.guid
    local newGuid = UnitExists("target") and UnitGUID("target") or nil

    if oldGuid ~= newGuid then
        wipe(target)
        target.exists = UnitExists("target")
        target.guid = newGuid
        if target.exists then
            target.inRange = {}
            target.auras = {}
            target.timeToDie = 0
            target.healthPercent = 0
            target.isCasting = false
            target.isChanneling = false
            target.castSpellID = nil
            self:UpdateUnitState("target", target)
        else
            target.inRange = {}
            target.auras = {}
            target.timeToDie = 0
            target.healthPercent = 0
            target.isCasting = false
            target.isChanneling = false
            target.castSpellID = nil
        end
        WRA:PrintDebug("StateManager: Target Changed from", oldGuid or "nil", "to", newGuid or "nil")
    end
end

function StateManager:HandleCastStart(event, unit, castName, castRank, castGUID)
    local now = GetTime()
    if not castName then return end
    local spellName, _, _, _, _, _, castTimeMs, _, spellID = GetSpellInfo(castName)
    if not spellID then spellID = 0 end
    local castTime = (castTimeMs or 0) / 1000

    if unit == "player" then
        local p = currentState.player
        p.isCasting, p.isChanneling, p.castSpellID, p.castStartTime, p.castEndTime = true, false, spellID, now, now + castTime
    elseif unit == "target" and currentState.target.exists and UnitIsUnit(unit, "target") then
         local t = currentState.target
         t.isCasting, t.isChanneling, t.castSpellID, t.castStartTime, t.castEndTime = true, false, spellID, now, now + castTime
    end
end

function StateManager:HandleCastStop(event, unit, castName, castRank, castGUID)
     if not castName then return end
     local spellName, _, _, _, _, _, _, _, spellID = GetSpellInfo(castName)
     if not spellID then spellID = 0 end

     if unit == "player" then
        if currentState.player.isCasting and currentState.player.castSpellID == spellID then
             currentState.player.isCasting, currentState.player.castSpellID = false, nil
        end
    elseif unit == "target" and currentState.target.exists and UnitIsUnit(unit, "target") then
         if currentState.target.isCasting and currentState.target.castSpellID == spellID then
             currentState.target.isCasting, currentState.target.castSpellID = false, nil
         end
    end
end

function StateManager:HandleChannelStart(event, unit, castName, castRank, castGUID)
    local now = GetTime()
    if not castName then return end
    local spellName, _, _, _, _, _, _, _, spellID = GetSpellInfo(castName)
    if not spellID then spellID = 0 end
    local channelDuration = WRA.Constants and WRA.Constants.ChannelDurations and WRA.Constants.ChannelDurations[spellID] or 3

    if unit == "player" then
        local p = currentState.player
        p.isChanneling, p.isCasting, p.castSpellID, p.castStartTime, p.channelEndTime = true, false, spellID, now, now + channelDuration
    elseif unit == "target" and currentState.target.exists and UnitIsUnit(unit, "target") then
         local t = currentState.target
         t.isChanneling, t.isCasting, t.castSpellID, t.castStartTime, t.channelEndTime = true, false, spellID, now, now + channelDuration
    end
end

function StateManager:HandleChannelStop(event, unit, castName, castRank, castGUID)
     if not castName then return end
     local spellName, _, _, _, _, _, _, _, spellID = GetSpellInfo(castName)
     if not spellID then spellID = 0 end

     if unit == "player" then
        if currentState.player.isChanneling and currentState.player.castSpellID == spellID then
             currentState.player.isChanneling, currentState.player.castSpellID = false, nil
        end
    elseif unit == "target" and currentState.target.exists and UnitIsUnit(unit, "target") then
         if currentState.target.isChanneling and currentState.target.castSpellID == spellID then
             currentState.target.isChanneling, currentState.target.castSpellID = false, nil
         end
    end
end

function StateManager:HandlePlayerAlive()
    if currentState.player.isDead then
        currentState.player.isDead = false
        self:UpdateState()
    end
end

function StateManager:HandleCooldownUpdate() end

function StateManager:UpdateEnvironment()
    local _, type, difficultyIndex = GetInstanceInfo()
    currentState.environment.instanceType = type or "none"
    currentState.environment.difficultyID = difficultyIndex or 0
end

function StateManager:IsUnitBoss(unit)
    if not UnitExists(unit) then return false end
    local classification = UnitClassification(unit)
    if classification == "worldboss" or classification == "rareelite" or classification == "elite" then
        if UnitLevel(unit) == -1 then return true end
    end
    if WRA.EncounterManager and WRA.EncounterManager.IsKnownBossName then
        return WRA.EncounterManager:IsKnownBossName(UnitName(unit))
    end
    return false
end

function StateManager:UpdateUnitState(unit, unitStateTable)
    if UnitExists(unit) then
        unitStateTable.exists = true
        unitStateTable.guid = UnitGUID(unit)
        unitStateTable.health = UnitHealth(unit)
        unitStateTable.healthMax = UnitHealthMax(unit)
        unitStateTable.healthPercent = (unitStateTable.healthMax > 0) and (unitStateTable.health / unitStateTable.healthMax * 100) or 0
        unitStateTable.isPlayer = UnitIsPlayer(unit)

        if UnitExists(unit) then
            local canAttackSuccess, canAttackResult = pcall(UnitCanAttack, "player", unit)
            local isFriendSuccess, isFriendResult = pcall(UnitIsFriend, "player", unit)
            local canAttack = canAttackSuccess and canAttackResult or false
            local isFriend = isFriendSuccess and isFriendResult or false
            if not canAttackSuccess then WRA:PrintError("Error calling UnitCanAttack for unit", unit, ":", canAttackResult) end
            if not isFriendSuccess then WRA:PrintError("Error calling UnitIsFriend for unit", unit, ":", isFriendResult) end
            unitStateTable.isEnemy = canAttack and not isFriend
            unitStateTable.isFriendly = isFriend
        else
             WRA:PrintDebug("StateManager: Unit", unit, "became invalid before CanAttack/IsFriend check.")
             unitStateTable.isEnemy = false
             unitStateTable.isFriendly = false
        end

        unitStateTable.classification = UnitClassification(unit) or "unknown"
        unitStateTable.isDead = UnitIsDeadOrGhost(unit)
        unitStateTable.isBoss = self:IsUnitBoss(unit)

        if unit == "target" then
            if not unitStateTable.inRange then unitStateTable.inRange = {} end

            if TTD and TTD.GetTimeToDie then
                if unitStateTable.guid then
                    unitStateTable.timeToDie = TTD:GetTimeToDie(unitStateTable.guid) or -1
                else
                    unitStateTable.timeToDie = -1
                end
            else
                unitStateTable.timeToDie = -1
            end

            local now = GetTime()
            if unitStateTable.isCasting and now >= unitStateTable.castEndTime then unitStateTable.isCasting, unitStateTable.castSpellID = false, nil end
            if unitStateTable.isChanneling and now >= unitStateTable.channelEndTime then unitStateTable.isChanneling, unitStateTable.castSpellID = false, nil end
        end
    else
        if unitStateTable.exists then
            wipe(unitStateTable)
            unitStateTable.exists = false
            unitStateTable.guid = nil
            unitStateTable.auras = {}
            if unit == "target" then
                unitStateTable.timeToDie = -1
                unitStateTable.inRange = {}
            end
            WRA:PrintDebug("StateManager: Unit", unit, "no longer exists, state cleared.")
        end
    end
end

function StateManager:HandleThreatUpdate(event, unit)
    if unit == "player" and currentState.player and UnitExists("target") then
        currentState.player.threatSituation = UnitThreatSituation("player", "target") or 0
    end
end

local lastAuraUpdateTime = 0
local AURA_UPDATE_THROTTLE = 0.05
function StateManager:HandleUnitAura(event, unit)
    if not UnitExists(unit) or not Aura or not Aura.GetUnitAuras then return end
    local now = GetTime()
    if now - lastAuraUpdateTime < AURA_UPDATE_THROTTLE then return end

    local unitTable = nil
    if unit == "player" then unitTable = currentState.player
    elseif unit == "target" then unitTable = currentState.target
    elseif unit == "focus" then unitTable = currentState.focus
    elseif unit == "pet" then unitTable = currentState.pet
    elseif unit == "targettarget" then unitTable = currentState.targettarget
    end

    if unitTable then
         unitTable.auras = Aura:GetUnitAuras(unit)
         lastAuraUpdateTime = now
    end
end

function StateManager:GetCurrentState()
    local now = GetTime()
    local player = currentState.player
    local gcdStart, gcdDuration = GetSpellCooldown(0)
    if gcdStart and gcdDuration and gcdDuration > 0 then
        player.gcdEndTime = gcdStart + gcdDuration
        player.isGCDActive = player.gcdEndTime > now
    else
        player.isGCDActive, player.gcdEndTime = false, 0
    end
    if player.isCasting and now >= player.castEndTime then player.isCasting, player.castSpellID = false, nil end
    if player.isChanneling and now >= player.channelEndTime then player.isChanneling, player.castSpellID = false, nil end
    return currentState
end

function StateManager:IsSpellInRange(spellID, unit)
    unit = unit or "target"
    if not spellID then
        WRA:PrintDebug(string_format("[IsSpellInRange(%s, %s) ABORT EARLY]: spellID is nil", tostring(spellID), unit))
        return false
    end
    if unit == "target" and (not currentState.target or not currentState.target.exists) then
        WRA:PrintDebug(string_format("[IsSpellInRange(%s, '%s') ABORT EARLY]: Target does not exist or currentState.target is nil", tostring(spellID), unit))
        return false
    end
    if not UnitExists(unit) then
        WRA:PrintDebug(string_format("[IsSpellInRange(%s, '%s') ABORT EARLY]: UnitExists(%s) is false", tostring(spellID), unit, unit))
        return false
    end

    local now = GetTime()
    if not currentState[unit] then currentState[unit] = { inRange = {} } end
    if not currentState[unit].inRange then currentState[unit].inRange = {} end
    local cache = currentState[unit].inRange

    if rawget(cache, spellID) ~= nil and (now - (cache[spellID].timestamp or 0) < rangeCheckInterval) then
        WRA:PrintDebug(string_format("[IsSpellInRange CACHE HIT] spellID %s, unit %s. Cached: %s.", tostring(spellID), unit, tostring(cache[spellID].value)))
        return cache[spellID].value
    end

    local result = false -- Default to false
    local spellNameForDebug = GetSpellInfo(spellID) or "UnknownSpell("..tostring(spellID)..")"
    WRA:PrintDebug(string_format("  [IsSpellInRange CALC START] spellID %s (%s), unit %s. Initial default result: false", tostring(spellID), spellNameForDebug, unit))

    local libRangeSucceeded = false

    -- Attempt to use LibRangeCheck-3.0
    if LibRange and type(LibRange.GetRange) == "function" and WRA.Constants and WRA.Constants.SpellRanges then
        local spellRequiredYards = WRA.Constants.SpellRanges[spellID]
        if spellRequiredYards then
            local targetMinYards, targetMaxYards = LibRange:GetRange(unit, true) -- checkVisible = true
            WRA:PrintDebug(string_format("    LibRange Path: For spellID %s (req: %s yd), Target '%s' LibRange:GetRange() result: min=%s, max=%s",
                tostring(spellID), tostring(spellRequiredYards), unit, tostring(targetMinYards), tostring(targetMaxYards)))

            if targetMinYards ~= nil then -- LibRange could determine at least a minimum distance
                -- Target is in range if its closest estimated point (targetMinYards)
                -- is less than or equal to the spell's maximum effective range (spellRequiredYards).
                if targetMinYards <= spellRequiredYards then
                    result = true
                else
                    result = false -- Closest target could be is already further than spell's max range
                end
                libRangeSucceeded = true
                WRA:PrintDebug(string_format("    LibRange Path Decision: spellReq=%s, targetMin=%s. Result set to: %s",
                    tostring(spellRequiredYards), tostring(targetMinYards), tostring(result)))
            else
                -- LibRange:GetRange(unit) returned nil for min (and thus likely max), couldn't determine.
                WRA:PrintDebug("    LibRange Path: LibRange:GetRange(unit) returned nil for min yards. Could not determine range.")
                libRangeSucceeded = false
            end
        else
            WRA:PrintDebug(string_format("    LibRange Path: Skipped for spellID %s. No range defined in Constants.SpellRanges.", tostring(spellID)))
            libRangeSucceeded = false
        end
    else
        WRA:PrintDebug(string_format("    LibRange Path: Skipped for spellID %s. Conditions not met. LibRange type: %s, GetRange type: %s, Constants valid: %s, SpellRanges valid: %s",
            tostring(spellID), type(LibRange), type(LibRange and LibRange.GetRange), tostring(WRA.Constants ~= nil), tostring(WRA.Constants and WRA.Constants.SpellRanges ~= nil)))
        libRangeSucceeded = false
    end

    -- Fallback to Blizzard's IsSpellInRange API if LibRangeCheck didn't succeed
    if not libRangeSucceeded then
        WRA:PrintDebug(string_format("  Fallback Path: Trying Blizzard API for spellID %s because LibRange did not succeed (current result from init: %s).", tostring(spellID), tostring(result)))
        local name = GetSpellInfo(spellID)
        WRA:PrintDebug(string_format("    Fallback Path: GetSpellInfo(%s) is '%s'", tostring(spellID), tostring(name)))
        if name then
            if UnitExists(unit) then -- Re-check unit existence
                local success, apiReturn = pcall(IsSpellInRange, name, unit)
                WRA:PrintDebug(string_format("    Fallback Path: pcall(IsSpellInRange, '%s', '%s') success: %s, apiReturn: %s", name, unit, tostring(success), tostring(apiReturn)))
                if success then
                    if apiReturn == 1 then
                        result = true
                    elseif apiReturn == 0 then
                        result = false
                    else
                        WRA:PrintDebug(string_format("    Fallback Path: Blizzard API returned unexpected value %s. Result remains based on initialization (false).", tostring(apiReturn)))
                        result = false -- Ensure result is explicitly false for nil or other returns
                    end
                else
                    WRA:PrintDebug(string_format("    Fallback Path: pcall to Blizzard API FAILED: %s. Result remains based on initialization (false).", tostring(apiReturn)))
                    result = false -- pcall failed
                end
            else
                 WRA:PrintDebug(string_format("    Fallback Path: Unit '%s' invalid for Blizzard API call for spellID %s. Result remains based on initialization (false).", unit, tostring(spellID)))
                 result = false -- Unit became invalid
            end
        else
            WRA:PrintDebug(string_format("    Fallback Path: GetSpellInfo(%s) nil. Result remains based on initialization (false).", tostring(spellID)))
            result = false -- GetSpellInfo failed
        end
    end

    WRA:PrintDebug(string_format("[IsSpellInRange CALC END] spellID %s (%s), unit %s. Final result: %s. Caching this value.", tostring(spellID), spellNameForDebug, unit, tostring(result)))
    cache[spellID] = { value = result, timestamp = now }
    return result
end

function StateManager:GetNearbyEnemyCount(radius)
    radius = radius or 8
    if Nameplates and Nameplates.GetNearbyEnemyCount then
        return Nameplates:GetNearbyEnemyCount()
    end
    return currentState.target.exists and currentState.target.isEnemy and 1 or 0
end

function StateManager:IsItemReady(itemID)
    if not itemID then return false end
    if CD and CD.IsItemReady then return CD:IsItemReady(itemID) end
    local start = _G.GetItemCooldown(itemID)
    return start == 0
end

function StateManager:GetItemCooldown(itemID)
     if not itemID then return 0, 0 end
     if CD and CD.GetCooldownRemaining then
         local remaining = CD:GetCooldownRemaining(itemID)
         local duration = CD:GetCooldownDuration(itemID) or 0
         local startTime = (remaining > 0 and duration > 0) and (GetTime() - (duration - remaining)) or 0
         return startTime, duration
     end
     return _G.GetItemCooldown(itemID)
end
