local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.Cache = {}
local Cache = MoPRH.Cache

local currentTick = 0
local store = {}

function Cache:BeginTick()
  currentTick = currentTick + 1
  store = {}
end

function Cache:Key(parts)
  return table.concat(parts, "|")
end

function Cache:Get(key)
  return store[key]
end

function Cache:Set(key, value)
  store[key] = value
  return value
end

function Cache:Remember(key, producer)
  local v = store[key]
  if v ~= nil then return v end
  v = producer()
  store[key] = v
  return v
end