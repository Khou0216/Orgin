local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.Tracker = {}
local Tracker = MoPRH.Tracker

local recentHitsByGuid = {}
local WINDOW_SEC = 6
local playerGUID = nil

function Tracker:SetPlayerGUID(guid)
  playerGUID = guid
end

local damageEvents = {
  SWING_DAMAGE = true,
  RANGE_DAMAGE = true,
  SPELL_DAMAGE = true,
  SPELL_PERIODIC_DAMAGE = true,
}

local function now()
  return GetTime()
end

local function prune()
  local cutoff = now() - WINDOW_SEC
  for guid, t in pairs(recentHitsByGuid) do
    if t < cutoff then
      recentHitsByGuid[guid] = nil
    end
  end
end

function Tracker:OnCombatLogEvent()
  local timestamp, subevent, _, srcGUID, _, _, _, destGUID, _, _, _ = CombatLogGetCurrentEventInfo()
  if not playerGUID or not damageEvents[subevent] then return end
  if srcGUID ~= playerGUID or not destGUID then return end
  recentHitsByGuid[destGUID] = now()
end

function Tracker:EstimatedEnemyCount()
  prune()
  local n = 0
  for _ in pairs(recentHitsByGuid) do n = n + 1 end
  return n
end