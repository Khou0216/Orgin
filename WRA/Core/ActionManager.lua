-- Core/ActionManager.lua
-- Manages registration and evaluation of "Insert Actions" (cooldowns, utility, etc.)
-- v3: Removed goto statement, fixed syntax for Lua 5.1 compatibility.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local ActionManager = WRA:NewModule("ActionManager")

-- Lua function shortcuts
local tinsert = table.insert
local wipe = table.wipe
local pairs = pairs
local type = type
local tonumber = tonumber
local table_sort = table.sort
local pcall = pcall
local geterrorhandler = geterrorhandler

-- Module Variables
local registeredActions = {}
local sortedActions = {}

-- --- Internal Functions ---

local function SortActions()
    wipe(sortedActions)
    for id, actionData in pairs(registeredActions) do
        actionData.priority = tonumber(actionData.priority) or 0
        tinsert(sortedActions, actionData)
    end
    table_sort(sortedActions, function(a, b)
        return a.priority > b.priority
    end)
end

-- --- Module Lifecycle ---

function ActionManager:OnInitialize()
    registeredActions = {}
    wipe(sortedActions)
    WRA:PrintDebug("ActionManager Initialized")
end

function ActionManager:OnEnable()
    WRA:PrintDebug("ActionManager Enabled")
    SortActions()
end

function ActionManager:OnDisable()
    WRA:PrintDebug("ActionManager Disabled")
end

-- --- Public API Functions ---

function ActionManager:RegisterAction(actionID, actionData)
    if not actionID then
        WRA:PrintError("ActionManager Error: RegisterAction requires an actionID.")
        return
    end
    if not actionData or type(actionData) ~= "table" then
        WRA:PrintError("ActionManager Error: RegisterAction requires actionData table for ID:", tostring(actionID))
        return
    end
    if type(actionData.checkReady) ~= "function" then
         WRA:PrintError("ActionManager Error: RegisterAction requires a checkReady function for ID:", tostring(actionID))
        return
    end
    if type(actionData.priority) ~= "number" then
         WRA:PrintError("ActionManager Error: RegisterAction requires a numeric priority for ID:", tostring(actionID))
        return
    end

    actionData.id = actionID
    actionData.scope = actionData.scope or "GCD"
    actionData.isOffGCD = actionData.isOffGCD or false

    if registeredActions[actionID] then
        WRA:PrintDebug("ActionManager Warning: Overwriting previously registered action:", actionID)
    end

    registeredActions[actionID] = actionData
    WRA:PrintDebug("ActionManager: Registered action:", actionID, "Prio:", actionData.priority, "Scope:", actionData.scope, "OffGCD:", tostring(actionData.isOffGCD))

    SortActions()
end

function ActionManager:UnregisterAction(actionID)
    if registeredActions[actionID] then
        WRA:PrintDebug("ActionManager: Unregistering action:", actionID)
        registeredActions[actionID] = nil
        SortActions()
        return true
    end
    return false
end

function ActionManager:UnregisterActionsByOwner(owner)
    if not owner then return end
    WRA:PrintDebug("ActionManager: Unregistering all actions for owner:", owner)
    local changed = false
    for id, actionData in pairs(registeredActions) do
        if actionData.owner == owner then
            registeredActions[id] = nil
            changed = true
        end
    end
    if changed then
        SortActions()
    end
end

function ActionManager:GetHighestPriorityAction(currentState, currentScope, requestedActionType)
    if not currentState or not currentScope then return nil end

    for i = 1, #sortedActions do
        local actionData = sortedActions[i]
        local processThisAction = true -- Flag to decide if we process this action

        -- 1. Filter by requestedActionType (GCD/OffGCD)
        if requestedActionType then
            local actionIsOffGCD = actionData.isOffGCD
            if requestedActionType == "GCD" and actionIsOffGCD then
                processThisAction = false -- Skip if we want GCD but action is OffGCD
            end
            if requestedActionType == "OffGCD" and not actionIsOffGCD then
                processThisAction = false -- Skip if we want OffGCD but action is GCD
            end
        end

        if processThisAction then
            -- 2. Filter by scope
            local scopeMatch = false
            if actionData.scope == "GLOBAL" then
                 scopeMatch = true
            elseif actionData.scope == "ALL" then
                 scopeMatch = (currentScope == "GCD" or currentScope == "ACTIVE" or currentScope == "CASTING")
            else
                 scopeMatch = (actionData.scope == currentScope)
            end

            if scopeMatch then
                local isReady = false
                local success, result = pcall(actionData.checkReady, currentState, actionData)
                if success then
                    isReady = result
                else
                    WRA:PrintError("ActionManager Error in checkReady for action", actionData.id, ":", result)
                end

                if isReady then
                    return actionData.id
                end
            end
        end
        -- If processThisAction was false, or scope didn't match, or not ready, loop continues
    end
    return nil
end
