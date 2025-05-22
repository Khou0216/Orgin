-- Common/CooldownTracker.lua
-- Tracks cooldowns for registered spells and items.
-- v2: Added logic to UpdateSpellCooldown to differentiate GCD from actual spell CD.
-- v3: Modified IsReady to rely on StateManager's GCD status for GCD-like cached durations.

local addonName, _ = ... -- Get addon name, don't rely on WRA from here
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")

-- Get the main addon object instance (must be created in WRA.lua first)
local WRA = AceAddon:GetAddon(addonName)

-- Get required libraries safely after getting WRA instance
local AceEvent = LibStub("AceEvent-3.0", true)
if not AceEvent then
    WRA:PrintError("CooldownTracker: Missing AceEvent!") -- Use WRA's print function
    return
end

-- Create the CooldownTracker module *on the main addon object*
local CooldownTracker = WRA:NewModule("CooldownTracker", "AceEvent-3.0")
WRA.CooldownTracker = CooldownTracker -- Make accessible via WRA.CooldownTracker

-- WoW API & Lua shortcuts
local GetSpellCooldown = _G.GetSpellCooldown
local GetItemCooldownFunc = _G.GetItemCooldown or (_G.C_Container and _G.C_Container.GetItemCooldown) or function() return 0, 0, 0 end -- Safe GetItemCooldown
local GetTime = _G.GetTime
local pairs = pairs
local wipe = wipe
local type = type
local math_max = math.max -- Lua math shortcut
local string_format = string.format -- For debug

-- Module Variables
local trackedSpells = {} -- Stores { [spellId] = true } for spells to track
local trackedItems = {}  -- Stores { [itemId] = true } for items to track
local cooldowns = {}     -- Stores { [id] = { startTime = t, duration = d, isItem = bool } } - Internal cache
local GCD_MAX_DURATION = 1.51 -- Threshold to differentiate GCD from real cooldowns (slightly above 1.5s)
local READY_THRESHOLD = 0.1 -- Threshold for comparing remaining time

-- --- Internal Functions ---

-- Updates the cooldown status for a specific spell ID from the WoW API
local function UpdateSpellCooldown(spellId)
    if not trackedSpells[spellId] then return end
    if not _G.GetSpellCooldown then return end

    local startTime, duration, enabled = GetSpellCooldown(spellId)
    local cache = cooldowns[spellId]

    if enabled == 0 then
        if cache then cooldowns[spellId] = nil end
        return
    end

    if startTime and startTime > 0 and duration and duration > 0 then
        if duration > GCD_MAX_DURATION then -- Likely a real cooldown
            if not cache or cache.startTime ~= startTime or cache.duration ~= duration then
                cooldowns[spellId] = cache or {}
                cooldowns[spellId].startTime = startTime
                cooldowns[spellId].duration = duration
                cooldowns[spellId].isItem = false
            end
        else -- Likely GCD or very short CD
            -- Don't cache GCD info itself.
            -- If a real CD was cached, check if it has expired based on cache.
            if cache and cache.duration > GCD_MAX_DURATION then
                 local elapsed = GetTime() - cache.startTime
                 if elapsed >= cache.duration then
                     cooldowns[spellId] = nil -- Real CD expired
                 end
            -- If no real CD was cached, or the current update is GCD,
            -- ensure any potentially stale short CD cache is cleared if appropriate.
            -- However, simply not caching the GCD info is usually sufficient.
            -- If a short CD *was* cached previously and now API returns 0/0, the 'elseif' below handles clearing.
            end
        end
    elseif cache then -- Cooldown finished or spell has no CD (startTime=0 or duration=0)
        cooldowns[spellId] = nil -- Clear the cache
    end
end


-- Updates the cooldown status for a specific item ID from the WoW API
local function UpdateItemCooldown(itemId)
    if not trackedItems[itemId] then return end
    local startTime, duration, enabled = GetItemCooldownFunc(itemId)
    local cache = cooldowns[itemId]

    if enabled == 0 then
        if cache then cooldowns[itemId] = nil end
        return
    end

    if startTime and startTime > 0 and duration and duration > 0 then
        if not cache or cache.startTime ~= startTime or cache.duration ~= duration then
            cooldowns[itemId] = cache or {}
            cooldowns[itemId].startTime = startTime
            cooldowns[itemId].duration = duration
            cooldowns[itemId].isItem = true
        end
    elseif cache then
        cooldowns[itemId] = nil
    end
end


-- --- Module Lifecycle ---

function CooldownTracker:OnInitialize()
    trackedSpells = {}
    trackedItems = {}
    wipe(cooldowns)
    WRA:PrintDebug("CooldownTracker Initialized")
end

function CooldownTracker:OnEnable()
    WRA:PrintDebug("CooldownTracker Enabled")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "EventHandler")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "EventHandler")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "EventHandler")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "FullCooldownScan")

    self:FullCooldownScan()
end

function CooldownTracker:OnDisable()
    WRA:PrintDebug("CooldownTracker Disabled")
    self:UnregisterAllEvents()
    wipe(trackedSpells)
    wipe(trackedItems)
    wipe(cooldowns)
end

-- --- Event Handler ---

function CooldownTracker:EventHandler(event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" then
        for spellId in pairs(trackedSpells) do UpdateSpellCooldown(spellId) end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for itemId in pairs(trackedItems) do UpdateItemCooldown(itemId) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitId, _, spellId = ...
        if unitId == "player" and spellId and trackedSpells[spellId] then
            UpdateSpellCooldown(spellId)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:FullCooldownScan()
    end
end

-- Perform a full scan of all tracked cooldowns
function CooldownTracker:FullCooldownScan()
    WRA:PrintDebug("Performing full cooldown scan...")
    for spellId in pairs(trackedSpells) do UpdateSpellCooldown(spellId) end
    for itemId in pairs(trackedItems) do UpdateItemCooldown(itemId) end
    WRA:PrintDebug("Full cooldown scan complete. Cache size:", (WRA.Utils and WRA.Utils.CountTable and WRA.Utils:CountTable(cooldowns) or "?"))
end


-- --- Public API Functions ---

-- Start tracking a spell's cooldown
function CooldownTracker:TrackSpell(spellId)
    if not spellId or type(spellId) ~= "number" or spellId == 0 then return end
    if not trackedSpells[spellId] then
        WRA:PrintDebug("Now tracking spell ID:", spellId)
        trackedSpells[spellId] = true
        UpdateSpellCooldown(spellId) -- Get initial state immediately
    end
end

-- Stop tracking a spell's cooldown
function CooldownTracker:UntrackSpell(spellId)
     if not spellId or type(spellId) ~= "number" then return end
     if trackedSpells[spellId] then
        WRA:PrintDebug("Stopped tracking spell ID:", spellId)
        trackedSpells[spellId] = nil
        cooldowns[spellId] = nil -- Remove stored data
     end
end

-- Start tracking an item's cooldown
function CooldownTracker:TrackItem(itemId)
    if not itemId or type(itemId) ~= "number" or itemId == 0 then return end
    if not trackedItems[itemId] then
        WRA:PrintDebug("Now tracking item ID:", itemId)
        trackedItems[itemId] = true
        UpdateItemCooldown(itemId) -- Get initial state immediately
    end
end

-- Stop tracking an item's cooldown
function CooldownTracker:UntrackItem(itemId)
    if not itemId or type(itemId) ~= "number" then return end
    if trackedItems[itemId] then
        WRA:PrintDebug("Stopped tracking item ID:", itemId)
        trackedItems[itemId] = nil
        cooldowns[itemId] = nil -- Remove stored data
    end
end

-- Get the remaining cooldown time for a spell or item ID from the cache
function CooldownTracker:GetCooldownRemaining(id)
    if not id then return 0 end
    local cd = cooldowns[id] -- Get cached data
    if cd and cd.startTime and cd.duration then
        -- If the cached duration is GCD-like, we cannot reliably determine remaining time from cache.
        -- Return a small non-zero value if it *was* cached recently, otherwise 0.
        -- Rely on IsReady to use StateManager for GCD checks.
        if cd.duration <= GCD_MAX_DURATION then
             local timeSinceStart = GetTime() - cd.startTime
             -- If the cache entry is very fresh (e.g., within the last GCD duration), return a placeholder > 0
             return (timeSinceStart < GCD_MAX_DURATION) and 0.1 or 0 -- Return 0.1 if likely still on GCD based on cache time, else 0
        end
        -- It's a real cooldown cache entry
        local elapsed = GetTime() - cd.startTime
        local remaining = cd.duration - elapsed
        return remaining > 0 and remaining or 0
    end
    return 0 -- Not cached, assume ready
end

-- Check if a spell or item is ready (cooldown finished) based on the cache
-- *** THIS IS THE MODIFIED FUNCTION ***
function CooldownTracker:IsReady(id)
    if not id then return true end

    local cd = cooldowns[id] -- Get cached data

    if cd and cd.duration and cd.duration <= GCD_MAX_DURATION then
        -- If the cached duration is GCD-like, readiness depends ONLY on the actual GCD status.
        -- Ignore the cached start/duration for readiness check.
        -- WRA:PrintDebug("IsReady Check (ID:", id, "): Cached duration is GCD-like (", cd.duration, "). Checking StateManager GCD.")
        local state = WRA.StateManager and WRA.StateManager:GetCurrentState()
        -- Return true (ready) only if StateManager exists AND player GCD is NOT active.
        return (state and state.player and not state.player.isGCDActive) or false
    elseif cd and cd.duration and cd.duration > GCD_MAX_DURATION then
        -- If it's a real cooldown cached, check remaining time against threshold.
        local remaining = self:GetCooldownRemaining(id) -- Use the function which already calculates remaining
        -- WRA:PrintDebug("IsReady Check (ID:", id, "): Real CD cached. Remaining:", string_format("%.2f", remaining), "Threshold:", READY_THRESHOLD)
        return remaining < READY_THRESHOLD
    else
        -- Not cached, or invalid cache entry. Assume ready.
        -- Also check the global GCD just in case this is an untracked spell/item being checked.
        -- WRA:PrintDebug("IsReady Check (ID:", id, "): Not cached or invalid cache. Assuming ready if GCD is ready.")
        local state = WRA.StateManager and WRA.StateManager:GetCurrentState()
        return (state and state.player and not state.player.isGCDActive) or false
    end
end


-- Check if a spell is ready (convenience function)
function CooldownTracker:IsSpellReady(spellId)
    return self:IsReady(spellId)
end

-- Check if an item is ready (convenience function)
function CooldownTracker:IsItemReady(itemId)
    return self:IsReady(itemId)
end


-- Get the full duration of a cooldown (returns 0 if not tracked or no CD)
function CooldownTracker:GetCooldownDuration(id)
     if not id then return 0 end
     local cd = cooldowns[id] -- Get cached data
     -- Return duration only if it's likely a real CD, not a GCD
     return (cd and cd.duration and cd.duration > GCD_MAX_DURATION) and cd.duration or 0
end
