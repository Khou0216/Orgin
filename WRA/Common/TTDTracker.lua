-- Common/TTDTracker.lua
-- Estimates Time-To-Die for units based on health changes.
-- Inspired by FireMageAssist's approach.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local AceEvent = LibStub("AceEvent-3.0", true)
local AceTimer = LibStub("AceTimer-3.0", true)
if not AceEvent or not AceTimer then
    WRA:PrintError("TTDTracker: Missing AceEvent or AceTimer!") -- Use WRA's print
    return
end

-- Create the TTDTracker module *on the main addon object*
local TTDTracker = WRA:NewModule("TTDTracker", "AceEvent-3.0", "AceTimer-3.0")
WRA.TTDTracker = TTDTracker -- Make accessible via WRA.TTDTracker

-- Lua shortcuts
local GetTime = GetTime
local pairs = pairs
local wipe = wipe
local type = type
local string = string -- Added string library reference

-- Module Variables
local guidTimeToDie = {}     -- Stores TTD data keyed by UnitGUID: { [guid] = { initTime, initHealth, midTime, midHealth, time, oldHealth } }
local nameTtdOverrides = {}  -- Stores { [unitName] = function(unitState) } for boss-specific logic
local updateTimer = nil
local UPDATE_INTERVAL = 0.15 -- How often to run the TTD update calculations (adjust as needed)
local cleanupTimer = nil -- Timer handle for cleanup
local CLEANUP_INTERVAL = 5.0 -- How often to clean up old GUIDs

-- Module references (assigned later if needed, WRA is available via closure)
local StateManager = nil

-- --- Internal Functions ---

-- Calculates TTD for a single unit based on its current state
-- unitState should be the table for that unit from StateManager
local function CalculateTTDForUnit(unitState)
    if not unitState or not unitState.exists or unitState.isDead or not unitState.guid or not unitState.health or not unitState.healthMax then
        return -- Cannot calculate for invalid/dead units
    end

    local guid = unitState.guid
    local health = unitState.health
    local healthMax = unitState.healthMax

    -- Initialize TTD data for this GUID if it doesn't exist
    if not guidTimeToDie[guid] then
        guidTimeToDie[guid] = {}
    end
    local ttdData = guidTimeToDie[guid]

    -- Check if health has changed since last check
    if ttdData.oldHealth == health then
        return -- No health change, no update needed
    end

    local currentTime = GetTime()
    ttdData.oldHealth = health -- Update last known health

    -- Reset TTD calculation if unit is at full health or healed significantly
    if health == healthMax or (ttdData.midHealth and health > ttdData.midHealth + (healthMax * 0.01)) then -- Healed > 1%
        -- WRA:PrintDebug("TTD Reset for", guid, "(Full Health or Healed)")
        wipe(ttdData) -- Clear previous data
        ttdData.oldHealth = health -- Keep current health for next check
        return
    end

    -- Initialize tracking points if needed
    if not ttdData.initHealth then
        -- WRA:PrintDebug("TTD Init for", guid)
        ttdData.initHealth = health
        ttdData.initTime = currentTime
        ttdData.midHealth = health -- Start midpoints same as init
        ttdData.midTime = currentTime
        ttdData.time = nil -- No estimate yet
        return
    end

    -- Update midpoint averages (simple moving average)
    -- Using 0.5 weight for new data vs old average
    ttdData.midHealth = (ttdData.midHealth + health) * 0.5
    ttdData.midTime = (ttdData.midTime + currentTime) * 0.5

    -- Check if health is still decreasing relative to the initial point
    if ttdData.midHealth >= ttdData.initHealth then
        -- Health trend reversed or stalled, reset calculation points but keep estimate
        -- WRA:PrintDebug("TTD Stalled/Reversed for", guid, "- Resetting points")
        ttdData.initHealth = health
        ttdData.initTime = currentTime
        ttdData.midHealth = health
        ttdData.midTime = currentTime
        -- Keep the old ttdData.time estimate until a new trend is established
    else
        -- Calculate projected TTD based on the trend from init to mid points
        local healthDiff = ttdData.initHealth - ttdData.midHealth
        local timeDiff = ttdData.midTime - ttdData.initTime

        if timeDiff > 0.05 then -- Avoid division by zero or tiny intervals
            local rate = healthDiff / timeDiff
            if rate > 0 then
                ttdData.time = health / rate -- Projected time remaining
                -- WRA:PrintDebug("TTD Update for", guid, ":", string.format("%.2f", ttdData.time))
            else
                 ttdData.time = nil -- Rate is zero or negative, cannot estimate
            end
        else
            -- Time difference too small, keep previous estimate if available
            -- WRA:PrintDebug("TTD Update for", guid, "- TimeDiff too small")
        end
    end
end

-- Periodic update called by AceTimer
local function PeriodicTTDUpdate()
    -- Ensure StateManager is available
    if not StateManager then StateManager = WRA.StateManager end
    if not StateManager then return end -- Still not available, exit

    local state = StateManager:GetCurrentState() -- Use GetCurrentState
    if not state then return end -- StateManager not ready

    -- Update Target
    if state.target then CalculateTTDForUnit(state.target) end
    -- Update Focus
    -- if state.focus then CalculateTTDForUnit(state.focus) end -- Uncomment if focus tracking added
    -- Update Pet
    -- if state.pet then CalculateTTDForUnit(state.pet) end -- Uncomment if pet tracking added

    -- Update Nameplates (Can be resource intensive - consider options)
    --[[
    if WRA.NameplateTracker then -- Check if module exists
        for unitId, unitState in WRA.NameplateTracker:IteratePlates() do -- Assumes NameplateTracker provides an iterator
             CalculateTTDForUnit(unitState)
        end
    end
    ]]

    -- Optionally fire an event
    -- TTDTracker:SendMessage("WRA_TTD_UPDATED")
end

-- Clears TTD data for units that no longer exist in the StateManager's view
local function CleanupOldGUIDs()
    -- Ensure StateManager is available
    if not StateManager then StateManager = WRA.StateManager end
    if not StateManager then return end

    local state = StateManager:GetCurrentState()
    if not state then return end

    local activeGUIDs = {}
    -- Collect GUIDs currently known by StateManager
    if state.target and state.target.guid then activeGUIDs[state.target.guid] = true end
    -- if state.focus and state.focus.guid then activeGUIDs[state.focus.guid] = true end -- Uncomment if focus tracking added
    -- if state.pet and state.pet.guid then activeGUIDs[state.pet.guid] = true end -- Uncomment if pet tracking added
    -- Add nameplate GUIDs if tracked

    -- Remove TTD data for GUIDs no longer active
    for guid in pairs(guidTimeToDie) do
        if not activeGUIDs[guid] then
            -- WRA:PrintDebug("TTD Cleanup for GUID:", guid)
            guidTimeToDie[guid] = nil
        end
    end
end

-- --- Module Lifecycle ---

function TTDTracker:OnInitialize()
    -- self.WRA = WRA -- WRA is available via closure
    guidTimeToDie = {}
    nameTtdOverrides = {}
    -- Get StateManager reference safely
    StateManager = WRA.StateManager
    if not StateManager then WRA:PrintError("TTDTracker: StateManager not found during Initialize!") end

    WRA:PrintDebug("TTDTracker Initialized")
end

function TTDTracker:OnEnable()
    WRA:PrintDebug("TTDTracker Enabled")
    -- Ensure StateManager is available
    if not StateManager then StateManager = WRA.StateManager end
    if not StateManager then
        WRA:PrintError("Error: StateManager not available for TTDTracker!")
        return
    end

    -- Start the periodic update timer
    if not updateTimer then
        updateTimer = self:ScheduleRepeatingTimer(PeriodicTTDUpdate, UPDATE_INTERVAL)
    end
    -- Start cleanup timer
    if not cleanupTimer then
        cleanupTimer = self:ScheduleRepeatingTimer(CleanupOldGUIDs, CLEANUP_INTERVAL)
    end
end

function TTDTracker:OnDisable()
    WRA:PrintDebug("TTDTracker Disabled")
    if updateTimer then
        self:CancelTimer(updateTimer)
        updateTimer = nil
    end
    if cleanupTimer then
        self:CancelTimer(cleanupTimer)
        cleanupTimer = nil
    end
    -- self:CancelAllTimers() -- Alternative if more timers added
    wipe(guidTimeToDie)
    wipe(nameTtdOverrides)
end

-- --- Public API Functions ---

-- Get the estimated Time To Die for a specific GUID
-- @param guid (string): The UnitGUID of the unit.
-- @return number: Estimated seconds remaining, or a default value if unknown.
function TTDTracker:GetTTD(guid)
    if not guid then return 30 end -- Default TTD if no GUID

    -- Ensure StateManager is available
    if not StateManager then StateManager = WRA.StateManager end

    -- Check for boss overrides first (requires unit name, get from StateManager)
    local unitName = nil
    local isBoss = false
    if StateManager then
        local state = StateManager:GetCurrentState()
        if state then
            -- Check target and focus (add others if needed)
            if state.target and state.target.guid == guid then
                unitName = state.target.name -- Assuming StateManager stores name
                isBoss = state.target.isBoss
            -- elseif state.focus and state.focus.guid == guid then -- Uncomment if focus tracked
            --     unitName = state.focus.name
            --     isBoss = state.focus.isBoss
            end

            if unitName and nameTtdOverrides[unitName] then
                local overrideFunc = nameTtdOverrides[unitName]
                local unitState = (state.target and state.target.guid == guid) and state.target -- or state.focus etc.
                if unitState then
                    local overrideTTD = overrideFunc(unitState)
                    if overrideTTD then return overrideTTD end
                    -- If override returns nil, fall through to standard calculation
                end
            end
        end
    end

    local ttdData = guidTimeToDie[guid]
    -- Return calculated time, or a default value based on boss status
    if ttdData and ttdData.time then
        return ttdData.time
    elseif isBoss then
        return 180 -- Default TTD for bosses if calculation failed
    end
    return 30 -- Default TTD for non-boss mobs if calculation failed
end

-- Get TTD adjusted for a specific health percentage
-- @param guid (string): The UnitGUID of the unit.
-- @param percent (number): The target health percent (0 to 100).
-- @return number: Estimated seconds until the unit reaches the target percent.
function TTDTracker:GetTTDByPercent(guid, percent)
    if not guid or not percent or percent < 0 or percent > 100 then return 0 end

    local currentTTD = self:GetTTD(guid)
    if not currentTTD or currentTTD <= 0 then return 0 end -- Already dead or invalid TTD

    -- Ensure StateManager is available
    if not StateManager then StateManager = WRA.StateManager end
    if not StateManager then return currentTTD end -- Cannot calculate without state

    local state = StateManager:GetCurrentState()
    local unitState = nil
    if state then -- Find the unit state to get current health %
         -- Check target and focus (add others if needed)
         if state.target and state.target.guid == guid then
             unitState = state.target
         -- elseif state.focus and state.focus.guid == guid then -- Uncomment if focus tracked
         --     unitState = state.focus
         end
    end

    if not unitState or not unitState.healthPercent then return currentTTD end -- Cannot calculate without current %

    local currentPercent = unitState.healthPercent
    if currentPercent <= percent then return 0 end -- Already below target %

    -- Linear scaling: TTD_to_target% = CurrentTTD * (Current% - Target%) / Current%
    local ttdToPercent = currentTTD * (currentPercent - percent) / currentPercent
    return ttdToPercent > 0 and ttdToPercent or 0
end

-- Register a custom TTD function for a specific unit name (e.g., boss)
-- @param unitName (string): The exact name of the unit.
-- @param ttdFunc (function): Function that takes unitState table and returns TTD number.
function TTDTracker:RegisterNameTTDOverride(unitName, ttdFunc)
    if type(unitName) == "string" and unitName ~= "" and type(ttdFunc) == "function" then
        WRA:PrintDebug("Registering TTD override for:", unitName)
        nameTtdOverrides[unitName] = ttdFunc
    else
        WRA:Print("Error: Invalid arguments for RegisterNameTTDOverride.")
    end
end

-- Remove a custom TTD function
function TTDTracker:UnregisterNameTTDOverride(unitName)
     if type(unitName) == "string" and nameTtdOverrides[unitName] then
         WRA:PrintDebug("Unregistering TTD override for:", unitName)
         nameTtdOverrides[unitName] = nil
     end
end

-- Reset all TTD data (e.g., on wipe or encounter end)
function TTDTracker:ResetAllTTD()
    WRA:PrintDebug("Resetting all TTD data.")
    wipe(guidTimeToDie)
end
