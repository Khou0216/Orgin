local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local Utils = MoPRH.Utils

MoPRH.RuleEngine = MoPRH.RuleEngine or {}
local RE = MoPRH.RuleEngine

RE.Conditions = RE.Conditions or {}

function RE.RegisterCondition(name, evaluator)
  RE.Conditions[name] = evaluator
end

local function evalByType(ctx, cond)
  if cond.type == "whenAll" then
    if not cond.list or #cond.list == 0 then return true end
    for _, c in ipairs(cond.list) do if not evalByType(ctx, c) then return false end end
    return true
  elseif cond.type == "whenAny" then
    if not cond.list or #cond.list == 0 then return true end
    for _, c in ipairs(cond.list) do if evalByType(ctx, c) then return true end end
    return false
  end
  local fn = RE.Conditions[cond.type]
  if not fn then return false end
  local ok = false
  local success, result = pcall(fn, ctx, cond)
  if success then ok = result == true else ok = false end
  return ok
end

local function allConditionsPass(ctx, rule)
  if rule.enabled == false then return false end
  if not rule.when or #rule.when == 0 then return true end
  for _, cond in ipairs(rule.when) do
    if not evalByType(ctx, cond) then return false end
  end
  return true
end

function RE.EvaluateRules(ctx, rules)
  if not rules or #rules == 0 then return nil, nil, nil end
  local suggestions = {}
  for _, rule in ipairs(rules) do
    if allConditionsPass(ctx, rule) then
      local ready = Utils.IsSpellReady(rule.action)
      if ready then
        table.insert(suggestions, { spellId = rule.action, note = rule.note })
        if #suggestions >= 3 then break end
      end
    end
  end
  return suggestions[1], suggestions[2], suggestions[3]
end

-- Register built-in conditions
RE.RegisterCondition("spellReady", function(ctx, cond)
  return Utils.IsSpellReady(cond.spellId) == true
end)

RE.RegisterCondition("auraMissing", function(ctx, cond)
  local aura = Utils.GetAura(cond.unit or "target", cond.spellId, cond.filter)
  return aura == nil
end)

RE.RegisterCondition("auraRemainingLTE", function(ctx, cond)
  local aura = Utils.GetAura(cond.unit or "target", cond.spellId, cond.filter)
  local s = tonumber(cond.seconds) or 0
  if not aura then return true end
  return (aura.expiresIn or 0) <= s
end)

RE.RegisterCondition("powerGTE", function(ctx, cond)
  local p = string.lower(cond.power or "")
  local v = tonumber(cond.value or 0) or 0
  if p == "chi" then return (ctx.power.chi or 0) >= v end
  if p == "energy" then return (ctx.power.energy or 0) >= v end
  return false
end)

RE.RegisterCondition("targetHpLTE", function(ctx, cond)
  local p = tonumber(cond.percent or 0) or 0
  return (ctx.targetHp or 100) <= p
end)

RE.RegisterCondition("playerHpLTE", function(ctx, cond)
  local hp = Utils.GetUnitHealthPercent("player")
  local p = tonumber(cond.percent or 0) or 0
  return hp <= p
end)

RE.RegisterCondition("isMoving", function(ctx, cond)
  local v = cond.value == true
  return (ctx.isMoving == true) == v
end)

RE.RegisterCondition("modeIs", function(ctx, cond)
  return (ctx.db.mode or "single") == (cond.value or "single")
end)

RE.RegisterCondition("inCombat", function(ctx, cond)
  local v = cond.value == true
  return (ctx.inCombat == true) == v
end)

RE.RegisterCondition("cdsRequired", function(ctx, cond)
  if cond.value == true then
    return ctx.db.showCooldowns == true
  else
    return true
  end
end)

RE.RegisterCondition("enemyCountGTE", function(ctx, cond)
  local tracker = MoPRH.Tracker
  if not tracker or not tracker.EstimatedEnemyCount then return false end
  local need = tonumber(cond.value or 0) or 0
  return tracker:EstimatedEnemyCount() >= need
end)

RE.RegisterCondition("nameplateEnemyCountGTE", function(ctx, cond)
  local np = MoPRH.Nameplates
  if not np or not np.CountEnemies then return false end
  local need = tonumber(cond.value or 0) or 0
  return np:CountEnemies() >= need
end)

RE.RegisterCondition("auraStacksGTE", function(ctx, cond)
  local aura = Utils.GetAura(cond.unit or "player", cond.spellId, cond.filter)
  local need = tonumber(cond.value or cond.stacks or 0) or 0
  if not aura then return false end
  return (aura.count or 0) >= need
end)

RE.RegisterCondition("chargesGTE", function(ctx, cond)
  local info = Utils.GetCharges(cond.spellId)
  local need = tonumber(cond.value or 1) or 1
  return (info.max > 0) and (info.charges or 0) >= need
end)

RE.RegisterCondition("spellCooldownLTE", function(ctx, cond)
  local ready, cd = Utils.IsSpellReady(cond.spellId)
  if ready then return true end
  local sec = tonumber(cond.value or 0) or 0
  return cd <= sec
end)

RE.RegisterCondition("resourceForecastGTE", function(ctx, cond)
  local res = string.lower(cond.power or "energy")
  local sec = tonumber(cond.seconds or cond.time or 0) or 0
  local want = tonumber(cond.value or 0) or 0
  if res == "energy" then
    local val = MoPRH.Utils.ForecastEnergy(sec)
    return (val or 0) >= want
  elseif res == "rage" then
    local val = MoPRH.Utils.ForecastRage(sec)
    return (val or 0) >= want
  end
  return false
end)

-- Serializer remains the same
local function serializeCond(c)
  if c.type == "whenAll" or c.type == "whenAny" then
    local list = {}
    for _, sub in ipairs(c.list or {}) do table.insert(list, serializeCond(sub)) end
    return string.format("{type=\"%s\",list={%s}}", c.type, table.concat(list, ","))
  end
  local parts = { string.format("type=\"%s\"", c.type or "") }
  if c.spellId then table.insert(parts, string.format("spellId=%d", c.spellId)) end
  if c.unit then table.insert(parts, string.format("unit=\"%s\"", c.unit)) end
  if c.seconds then table.insert(parts, string.format("seconds=%g", c.seconds)) end
  if c.filter then table.insert(parts, string.format("filter=\"%s\"", c.filter)) end
  if c.power then table.insert(parts, string.format("power=\"%s\"", c.power)) end
  if c.value ~= nil then
    if type(c.value) == "string" then table.insert(parts, string.format("value=\"%s\"", c.value))
    else table.insert(parts, string.format("value=%s", tostring(c.value))) end
  end
  if c.percent then table.insert(parts, string.format("percent=%g", c.percent)) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function RE.SerializeRules(rules)
  if not rules then return "{}" end
  local out = {}
  for _, r in ipairs(rules) do
    local fields = { string.format("action=%d", r.action or 0) }
    if r.note then table.insert(fields, string.format("note=\"%s\"", r.note)) end
    if r.enabled == false then table.insert(fields, "enabled=false") end
    if r.when and #r.when > 0 then
      local conds = {}
      for _, c in ipairs(r.when) do table.insert(conds, serializeCond(c)) end
      table.insert(fields, "when={" .. table.concat(conds, ",") .. "}")
    end
    table.insert(out, "{" .. table.concat(fields, ",") .. "}")
  end
  return "{" .. table.concat(out, ",") .. "}"
end