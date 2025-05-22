-- Core/RotationEngine.lua
-- The main engine that drives rotation decisions.
-- v13: Overhauled EngineUpdate to support separate GCD and Off-GCD action slots.

local addonName, _ = ...
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local RotationEngine = WRA:NewModule("RotationEngine", "AceEvent-3.0", "AceTimer-3.0")

-- Lua shortcuts
local math_max = math.max
local GetTime = GetTime
local pcall = pcall
local geterrorhandler = geterrorhandler
local string_format = string.format
local pairs = pairs -- Added for iterating action manager results

-- Constants from WRA.Constants
local UPDATE_INTERVAL = 0.05
local FIRE_WINDOW = 0.15
local ACTION_ID_WAITING = 0
local ACTION_ID_IDLE = "IDLE"
local ACTION_ID_CASTING = "CASTING"
local ACTION_ID_UNKNOWN = -1 -- Fallback

-- Module Variables
local updateTimer = nil
local lastActionsDisplayed = { gcdAction = nil, offGcdAction = nil } -- Track last displayed actions
local isEngineRunning = false
local initialTimer = nil

-- Initialize constants after WRA.Constants is available
local function InitConstants()
    if WRA.Constants then
        UPDATE_INTERVAL = WRA.Constants.UPDATE_INTERVAL or 0.05
        FIRE_WINDOW = WRA.Constants.FIRE_WINDOW or 0.15
        ACTION_ID_WAITING = WRA.Constants.ACTION_ID_WAITING or 0
        ACTION_ID_IDLE = WRA.Constants.ACTION_ID_IDLE or "IDLE"
        ACTION_ID_CASTING = WRA.Constants.ACTION_ID_CASTING or "CASTING"
        ACTION_ID_UNKNOWN = WRA.Constants.ACTION_ID_UNKNOWN or -1
    end
end


-- --- Core Engine Update Function ---
local function EngineUpdate()
    if not isEngineRunning then return end

    if not WRA.StateManager or not WRA.ActionManager or not WRA.DisplayManager or not WRA.SpecLoader then
        return
    end

    local activeSpec = WRA.SpecLoader:GetActiveSpecModule()
    if not activeSpec then
        if lastActionsDisplayed.gcdAction ~= ACTION_ID_WAITING or lastActionsDisplayed.offGcdAction ~= nil then
            WRA.DisplayManager:UpdateAction({ gcdAction = ACTION_ID_WAITING, offGcdAction = nil })
            lastActionsDisplayed = { gcdAction = ACTION_ID_WAITING, offGcdAction = nil }
        end
        return
    end

    local currentState = WRA.StateManager:GetCurrentState()
    if not currentState or not currentState.player then return end

    local playerState = currentState.player
    local finalGcdAction = nil
    local finalOffGcdAction = nil

    if playerState.isDead or playerState.isFeigning then
        finalGcdAction = ACTION_ID_WAITING
        finalOffGcdAction = nil
        if finalGcdAction ~= lastActionsDisplayed.gcdAction or finalOffGcdAction ~= lastActionsDisplayed.offGcdAction then
            WRA.DisplayManager:UpdateAction({ gcdAction = finalGcdAction, offGcdAction = finalOffGcdAction })
            lastActionsDisplayed = { gcdAction = finalGcdAction, offGcdAction = finalOffGcdAction }
        end
        return
    end

    -- 1. Get Spec Module Suggestions (now returns a table)
    local specSuggestions = { gcdAction = nil, offGcdAction = nil }
    if activeSpec.GetNextAction then
        local success, result = pcall(activeSpec.GetNextAction, activeSpec, currentState)
        if success and type(result) == "table" then
            specSuggestions = result
        elseif not success then
            local specKey = WRA.SpecLoader:GetCurrentSpecKey() or "Unknown"
            WRA:PrintError("Error in GetNextAction for spec", specKey, ":", result)
            specSuggestions.gcdAction = ACTION_ID_WAITING -- Fallback on error
        end
    else
        WRA:PrintError("Error: Active spec module has no GetNextAction method!")
        specSuggestions.gcdAction = ACTION_ID_WAITING -- Fallback
    end

    -- Initialize final actions with spec suggestions or IDLE/nil
    finalGcdAction = specSuggestions.gcdAction or ACTION_ID_IDLE
    finalOffGcdAction = specSuggestions.offGcdAction -- Can be nil

    -- 2. Evaluate ActionManager Insert Actions
    -- ActionManager needs to be adapted to return { gcdAction, offGcdAction } or be called twice.
    -- Assuming ActionManager:GetPrioritizedActions(currentState, scope) returns { gcd, offgcd }
    -- Or, call it per type:
    --    amGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, scope, "GCD")
    --    amOffGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, scope, "OffGCD")

    -- Simplified logic for now: ActionManager can override spec suggestions if an action is found.
    -- This part needs careful integration with how ActionManager will be modified.
    -- For now, let's assume ActionManager primarily provides "insert" style actions that might
    -- take precedence or fill gaps.

    local amGlobalGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "GLOBAL", "GCD")
    local amGlobalOffGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "GLOBAL", "OffGCD")

    if amGlobalGcdAction then finalGcdAction = amGlobalGcdAction end
    if amGlobalOffGcdAction then finalOffGcdAction = amGlobalOffGcdAction end


    local isCasting = playerState.isCasting
    local isChanneling = playerState.isChanneling
    local nextActionTimeRemaining = 0
    local now = GetTime()

    if playerState.isGCDActive then
        nextActionTimeRemaining = math_max(nextActionTimeRemaining, (playerState.gcdEndTime or 0) - now)
    end
    if isCasting and (playerState.castEndTime or 0) > now then
        nextActionTimeRemaining = math_max(nextActionTimeRemaining, (playerState.castEndTime or 0) - now)
    elseif isChanneling and (playerState.channelEndTime or 0) > now then
        nextActionTimeRemaining = math_max(nextActionTimeRemaining, (playerState.channelEndTime or 0) - now)
    end
    if nextActionTimeRemaining < 0 then nextActionTimeRemaining = 0 end


    if isCasting or isChanneling then
        local amCastingGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "CASTING", "GCD")
        local amCastingOffGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "CASTING", "OffGCD")
        if amCastingGcdAction then finalGcdAction = amCastingGcdAction
        else finalGcdAction = ACTION_ID_CASTING -- Default GCD action while casting
        end
        if amCastingOffGcdAction then finalOffGcdAction = amCastingOffGcdAction end

    elseif nextActionTimeRemaining <= FIRE_WINDOW then
        -- Within fire window, prioritize GCD actions
        local amGcdScopedAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "GCD", "GCD")
        if amGcdScopedAction then
            finalGcdAction = amGcdScopedAction
        else
            -- If no AM GCD action, use the spec's GCD suggestion (already in finalGcdAction)
            -- If spec also suggested nothing, it defaults to IDLE
             finalGcdAction = specSuggestions.gcdAction or ACTION_ID_IDLE
        end

        -- OffGCD actions can also be considered here
        local amActiveOffGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "ACTIVE", "OffGCD")
        if amActiveOffGcdAction then
            finalOffGcdAction = amActiveOffGcdAction
        else
            finalOffGcdAction = specSuggestions.offGcdAction -- Use spec's OffGCD if no AM override
        end

    else -- Outside fire window, but not casting/channeling (i.e. GCD is active and longer than firewindow)
        finalGcdAction = ACTION_ID_WAITING -- Waiting for GCD primarily

        -- Still check for OffGCD actions from ActionManager (e.g. long CD scope) or spec
        local amCdOffGcdAction = WRA.ActionManager:GetHighestPriorityAction(currentState, "CD", "OffGCD")
        if amCdOffGcdAction then
            finalOffGcdAction = amCdOffGcdAction
        else
            finalOffGcdAction = specSuggestions.offGcdAction -- Or from spec
        end
    end

    -- Ensure finalGcdAction is not nil if nothing else was set (should be IDLE or WAITING)
    finalGcdAction = finalGcdAction or ACTION_ID_IDLE


    -- Send the final actions to the Display Manager only if they changed
    if finalGcdAction ~= lastActionsDisplayed.gcdAction or finalOffGcdAction ~= lastActionsDisplayed.offGcdAction then
        if WRA.DisplayManager and WRA.DisplayManager.UpdateAction then
            local actionsToDisplay = { gcdAction = finalGcdAction, offGcdAction = finalOffGcdAction }
            WRA.DisplayManager:UpdateAction(actionsToDisplay)
            lastActionsDisplayed = actionsToDisplay
        else
             WRA:PrintError("RotationEngine: DisplayManager or UpdateAction method not found!")
        end
    end
end

-- --- Module Lifecycle ---

function RotationEngine:OnInitialize()
    InitConstants() -- Initialize constants after WRA.Constants is expected to be ready
    lastActionsDisplayed = { gcdAction = nil, offGcdAction = nil }
    isEngineRunning = false
    WRA:PrintDebug("RotationEngine Initialized")
end

function RotationEngine:OnEnable()
    if not WRA.StateManager or not WRA.ActionManager or not WRA.DisplayManager or not WRA.SpecLoader then
        WRA:PrintError("Cannot enable RotationEngine: Critical modules missing.")
        return
    end
    InitConstants() -- Re-initialize constants in case they were updated by other modules loading

    WRA:PrintDebug("RotationEngine Enabled, scheduling timer...")
    isEngineRunning = true
    lastActionsDisplayed = { gcdAction = nil, offGcdAction = nil } -- Reset suggestions

    if not updateTimer and not initialTimer then
        initialTimer = self:ScheduleTimer(function()
             initialTimer = nil
             if isEngineRunning and not updateTimer then
                 EngineUpdate()
                 updateTimer = self:ScheduleRepeatingTimer(EngineUpdate, UPDATE_INTERVAL)
                 WRA:PrintDebug("RotationEngine repeating timer started.")
             end
        end, 0.6)
    end
end

function RotationEngine:OnDisable()
    WRA:PrintDebug("RotationEngine Disabled")
    isEngineRunning = false

    if updateTimer then
        self:CancelTimer(updateTimer); updateTimer = nil
    end
    if initialTimer then
        self:CancelTimer(initialTimer); initialTimer = nil
    end

    if WRA.DisplayManager and WRA.DisplayManager.UpdateAction then
        WRA.DisplayManager:UpdateAction({ gcdAction = nil, offGcdAction = nil }) -- Clear display
    end
    lastActionsDisplayed = { gcdAction = nil, offGcdAction = nil }
end

-- --- Public API ---
function RotationEngine:ForceUpdate()
    WRA:PrintDebug("ForceUpdate called on RotationEngine")
    EngineUpdate()
end

function RotationEngine:Pause()
    WRA:PrintDebug("RotationEngine Paused")
    isEngineRunning = false
end

function RotationEngine:Resume()
    WRA:PrintDebug("RotationEngine Resumed")
    isEngineRunning = true
    -- Consider if a ForceUpdate is needed on resume or if timer will pick it up.
end
