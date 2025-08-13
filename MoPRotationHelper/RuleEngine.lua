local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local Utils = MoPRH.Utils

MoPRH.RuleEngine = {}
local RE = MoPRH.RuleEngine

-- Supported condition types:
-- - spellReady { spellId }
-- - auraMissing { unit, spellId }
-- - auraRemainingLTE { unit, spellId, seconds }
-- - powerGTE { power = "chi"|"energy", value }
-- - targetHpLTE { percent }
-- - playerHpLTE { percent }
-- - isMoving { value = true|false }
-- - modeIs { value = "single"|"aoe" }
-- - inCombat { value = true|false }
-- - cdsRequired { value = true }  -- passes only if showCooldowns is ON when value is true

local function evalCondition(ctx, cond)
  local t = cond.type
  if t == "spellReady" then
    local ready = Utils.IsSpellReady(cond.spellId)
    return ready == true
  elseif t == "auraMissing" then
    local aura = Utils.GetAura(cond.unit or "target", cond.spellId, cond.filter)
    return aura == nil
  elseif t == "auraRemainingLTE" then
    local aura = Utils.GetAura(cond.unit or "target", cond.spellId, cond.filter)
    local s = tonumber(cond.seconds) or 0
    if not aura then return true end
    return (aura.expiresIn or 0) <= s
  elseif t == "powerGTE" then
    local p = string.lower(cond.power or "")
    local v = tonumber(cond.value or 0) or 0
    if p == "chi" then return (ctx.power.chi or 0) >= v end
    if p == "energy" then return (ctx.power.energy or 0) >= v end
    return false
  elseif t == "targetHpLTE" then
    local p = tonumber(cond.percent or 0) or 0
    return (ctx.targetHp or 100) <= p
  elseif t == "playerHpLTE" then
    local hp = Utils.GetUnitHealthPercent("player")
    local p = tonumber(cond.percent or 0) or 0
    return hp <= p
  elseif t == "isMoving" then
    local v = cond.value == true
    return (ctx.isMoving == true) == v
  elseif t == "modeIs" then
    return (ctx.db.mode or "single") == (cond.value or "single")
  elseif t == "inCombat" then
    local v = cond.value == true
    return (ctx.inCombat == true) == v
  elseif t == "cdsRequired" then
    if cond.value == true then
      return ctx.db.showCooldowns == true
    else
      return true
    end
  end
  return false
end

local function allConditionsPass(ctx, rule)
  if rule.enabled == false then return false end
  if not rule.when or #rule.when == 0 then return true end
  for _, cond in ipairs(rule.when) do
    if not evalCondition(ctx, cond) then return false end
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

-- Simple serializer: outputs a compact Lua literal table for rules
local function serializeCond(c)
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