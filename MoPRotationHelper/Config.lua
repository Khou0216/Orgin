local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

-- SavedVariables
MoPRHDB = MoPRHDB or {}

local DEFAULTS = {
  locked = false,
  scale = 1.0,
  showWhenOutOfCombat = false,
  showCooldowns = true,
  mode = "single", -- "single" | "aoe"
}

local function applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      db[k] = v
    end
  end
end

function MoPRH:InitDB()
  MoPRHDB = MoPRHDB or {}
  applyDefaults(MoPRHDB, DEFAULTS)
  self.db = MoPRHDB
end

function MoPRH:GetDB()
  return self.db or DEFAULTS
end

function MoPRH:Set(key, value)
  self.db[key] = value
end

-- Simple slash commands (implemented in Core but documented here)
-- /mrh lock
-- /mrh unlock
-- /mrh scale 1.2
-- /mrh mode single|aoe
-- /mrh cds on|off
-- /mrh showooc on|off