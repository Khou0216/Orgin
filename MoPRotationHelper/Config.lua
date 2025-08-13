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
  profiles = {}, -- [specId] = { active = "Default", sets = { [name] = { rules = {...} } } }
  debug = false,
}

local function applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then db[k] = {} else db[k] = v end
    end
  end
end

function MoPRH:InitDB()
  MoPRHDB = MoPRHDB or {}
  applyDefaults(MoPRHDB, DEFAULTS)
  self.db = MoPRHDB
  self:EnsureDefaultProfiles()
end

function MoPRH:GetDB()
  return self.db or DEFAULTS
end

function MoPRH:Set(key, value)
  self.db[key] = value
end

local function ensureSpecProfile(db, specId)
  db.profiles[specId] = db.profiles[specId] or { active = "Default", sets = {} }
  db.profiles[specId].sets["Default"] = db.profiles[specId].sets["Default"] or { rules = {} }
end

function MoPRH:GetActiveProfile(specId)
  ensureSpecProfile(self.db, specId)
  local spec = self.db.profiles[specId]
  return spec.active, spec.sets[spec.active]
end

function MoPRH:SetActiveProfile(specId, name)
  ensureSpecProfile(self.db, specId)
  local spec = self.db.profiles[specId]
  if spec.sets[name] then spec.active = name end
end

function MoPRH:NewProfile(specId, name, copyFromName)
  ensureSpecProfile(self.db, specId)
  local spec = self.db.profiles[specId]
  if spec.sets[name] then return false end
  local src = spec.sets[copyFromName or spec.active]
  local rulesCopy = {}
  if src and src.rules then
    for i, r in ipairs(src.rules) do
      local rc = { action = r.action, note = r.note, enabled = (r.enabled ~= false), when = {} }
      if r.when then for _, c in ipairs(r.when) do table.insert(rc.when, { type = c.type, spellId = c.spellId, unit = c.unit, seconds = c.seconds, filter = c.filter, power = c.power, value = c.value, percent = c.percent }) end end
      table.insert(rulesCopy, rc)
    end
  end
  spec.sets[name] = { rules = rulesCopy }
  spec.active = name
  return true
end

function MoPRH:GetRules(specId)
  local _, prof = self:GetActiveProfile(specId)
  if not prof then return {} end
  prof.rules = prof.rules or {}
  return prof.rules
end

function MoPRH:SetRules(specId, rules)
  local _, prof = self:GetActiveProfile(specId)
  if not prof then return end
  prof.rules = rules or {}
end

function MoPRH:MoveRule(specId, index, direction)
  local rules = self:GetRules(specId)
  local i = tonumber(index or 0)
  if not rules[i] then return false end
  local j = direction == "up" and (i - 1) or (i + 1)
  if j < 1 or j > #rules then return false end
  rules[i], rules[j] = rules[j], rules[i]
  return true
end

function MoPRH:ToggleRule(specId, index)
  local rules = self:GetRules(specId)
  local i = tonumber(index or 0)
  if not rules[i] then return false end
  rules[i].enabled = not (rules[i].enabled == false)
  return true
end

-- Default rules for Windwalker (269) roughly matching the code rotation
function MoPRH:EnsureDefaultProfiles()
  local specId = 269
  ensureSpecProfile(self.db, specId)
  local spec = self.db.profiles[specId]
  local rules = spec.sets["Default"].rules
  if rules and #rules > 0 then return end

  local SPELL = {
    RisingSunKick = 107428,
    TigerPalm = 100787,
    BlackoutKick = 100784,
    Jab = 100780,
    FistsOfFury = 113656,
    TigereyeBrew = 116740,
    TouchOfDeath = 115080,
    ExpelHarm = 115072,
    ChiWave = 115098,
    SpinningCraneKick = 101546,
  }
  local AURA = {
    TigerPower = 125359,
    RSKDebuff = 130320,
    TigereyeBrewBuff = 125195,
  }

  spec.sets["Default"].rules = {
    { action = SPELL.ExpelHarm, note = "自保", enabled = true, when = {
      { type = "inCombat", value = true },
      { type = "playerHpLTE", percent = 70 },
      { type = "spellReady", spellId = SPELL.ExpelHarm },
    }},
    { action = SPELL.TouchOfDeath, note = "斩杀", enabled = true, when = {
      { type = "targetHpLTE", percent = 10 },
      { type = "spellReady", spellId = SPELL.TouchOfDeath },
    }},
    { action = SPELL.TigerPalm, note = "破甲", enabled = true, when = {
      { type = "auraRemainingLTE", unit = "player", spellId = AURA.TigerPower, seconds = 3, filter = "HELPFUL" },
      { type = "spellReady", spellId = SPELL.TigerPalm },
    }},
    { action = SPELL.RisingSunKick, note = "日落踢减益", enabled = true, when = {
      { type = "auraRemainingLTE", unit = "target", spellId = AURA.RSKDebuff, seconds = 3, filter = "HARMFUL" },
      { type = "spellReady", spellId = SPELL.RisingSunKick },
    }},
    { action = SPELL.FistsOfFury, note = "风火雷电", enabled = true, when = {
      { type = "cdsRequired", value = true },
      { type = "isMoving", value = false },
      { type = "powerGTE", power = "chi", value = 3 },
      { type = "auraRemainingLTE", unit = "target", spellId = AURA.RSKDebuff, seconds = 999, filter = "HARMFUL" },
      { type = "spellReady", spellId = SPELL.FistsOfFury },
    }},
    { action = SPELL.TigereyeBrew, note = "10层猛虎之眼", enabled = true, when = {
      { type = "cdsRequired", value = true },
      -- manual window; keep enabled
      { type = "spellReady", spellId = SPELL.TigereyeBrew },
    }},
    { action = SPELL.SpinningCraneKick, note = "顺劈(3+)\n姓名板/命中估算/或手动AoE模式", enabled = true, when = {
      { type = "whenAny", list = {
        { type = "nameplateEnemyCountGTE", value = 3 },
        { type = "enemyCountGTE", value = 3 },
        { type = "modeIs", value = "aoe" },
      }},
      { type = "spellReady", spellId = SPELL.SpinningCraneKick },
    }},
    { action = SPELL.BlackoutKick, note = "消耗真气", enabled = true, when = {
      { type = "powerGTE", power = "chi", value = 3 },
      { type = "spellReady", spellId = SPELL.BlackoutKick },
    }},
    { action = SPELL.ChiWave, note = "天赋", enabled = true, when = {
      { type = "cdsRequired", value = true },
      { type = "spellReady", spellId = SPELL.ChiWave },
    }},
    { action = SPELL.Jab, note = "回真气", enabled = true, when = {
      { type = "powerGTE", power = "energy", value = 50 },
      { type = "spellReady", spellId = SPELL.Jab },
    }},
  }
end

-- Simple slash commands (implemented in Core but documented here)
-- /mrh lock
-- /mrh unlock
-- /mrh scale 1.2
-- /mrh mode single|aoe
-- /mrh cds on|off
-- /mrh showooc on|off