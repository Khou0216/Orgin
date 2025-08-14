local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local UI = MoPRH.UI
local Utils = MoPRH.Utils
local RE = MoPRH.RuleEngine
local Cache = MoPRH.Cache
local Tracker = MoPRH.Tracker
local Automation = MoPRH.Automation
local Macro = MoPRH.Macro

-- Rotation registry keyed by specId
MoPRH.Rotations = MoPRH.Rotations or {}

function MoPRH.RegisterRotation(specId, rotation)
  MoPRH.Rotations[specId] = rotation
end

-- Manual high-priority queue
MoPRH.state = MoPRH.state or { forcedQueue = {} }

local function resolveSpellRef(spellRef)
  if type(spellRef) == "number" then
    local name = GetSpellInfo(spellRef)
    return spellRef, name
  else
    local name, _, _, _, _, _, spellId = GetSpellInfo(spellRef)
    return spellId, name or spellRef
  end
end

function MoPRH:PushForced(spellRef, ttl, note)
  local id, name = resolveSpellRef(spellRef)
  if not id and not name then return false end
  local lifespan = tonumber(ttl or 6) or 6
  table.insert(self.state.forcedQueue, 1, {
    spellId = id,
    spellName = name,
    note = note or "手动",
    expiresAt = GetTime() + lifespan,
  })
  return true
end

function MoPRH:ClearForced()
  self.state.forcedQueue = {}
end

local function pruneForced()
  local q = MoPRH.state.forcedQueue
  if not q or #q == 0 then return end
  local t = GetTime()
  for i = #q, 1, -1 do
    if not q[i].expiresAt or q[i].expiresAt <= t then table.remove(q, i) end
  end
end

function MoPRH:GetForced()
  pruneForced()
  return self.state.forcedQueue[1]
end

local function popIfCasted(spellID)
  local top = MoPRH:GetForced()
  if not top then return end
  if top.spellId and top.spellId == spellID then
    table.remove(MoPRH.state.forcedQueue, 1)
    return
  end
  local name = GetSpellInfo(spellID)
  if name and top.spellName and top.spellName == name then
    table.remove(MoPRH.state.forcedQueue, 1)
  end
end

local function getPlayerSpecId()
  if not GetSpecialization then return nil end
  local specIndex = GetSpecialization()
  if not specIndex then return nil end
  local specId = GetSpecializationInfo(specIndex)
  return specId
end

local function buildContext()
  local specId = getPlayerSpecId()
  local inCombat = Utils.InCombat()
  local gcdRemains = Utils.GetGCDRemaining()
  local targetExists = UnitExists("target") == true
  local targetHp = targetExists and Utils.GetUnitHealthPercent("target") or 100
  local isMoving = Utils.IsMoving()

  local power = {}
  power.energy = UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
  power.maxEnergy = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
  power.mana = UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Mana or 0)
  power.chi = UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Chi or 12)
  power.maxChi = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Chi or 12)

  return {
    specId = specId,
    inCombat = inCombat,
    gcdRemains = gcdRemains,
    targetExists = targetExists,
    targetHp = targetHp,
    isMoving = isMoving,
    power = power,
    db = MoPRH:GetDB(),
  }
end

local function evaluateAndRender()
  -- start a fresh cache tick
  if Cache and Cache.BeginTick then Cache:BeginTick() end

  local ctx = buildContext()
  local rules = ctx.specId and MoPRH:GetRules(ctx.specId) or nil
  local rotation = MoPRH.Rotations[ctx.specId]

  local shouldShow = ctx.inCombat or ctx.db.showWhenOutOfCombat
  if not shouldShow then
    UI:Hide()
    if Automation and Automation.UpdateFromSuggestion then
      Automation:UpdateFromSuggestion(nil, ctx)
    end
    return
  end

  UI:Show()

  local p, s, t
  if rules and #rules > 0 and RE and RE.EvaluateRules then
    p, s, t = RE.EvaluateRules(ctx, rules)
  elseif rotation and rotation.Evaluate then
    p, s, t = rotation:Evaluate(ctx)
  end

  -- Manual forced insertion has highest priority
  local forced = MoPRH:GetForced()
  if forced then
    local primary = { spellId = forced.spellId, spellName = forced.spellName, note = forced.note or "手动" }
    UI:Update(primary, p or s, (p and s) and t or s)
    if Automation and Automation.UpdateFromSuggestion then
      Automation:UpdateFromSuggestion(primary, ctx)
    end
  else
    UI:Update(p, s, t)
    if Automation and Automation.UpdateFromSuggestion then
      Automation:UpdateFromSuggestion(p, ctx)
    end
  end

  if ctx.db.debug and (p or forced) then
    if not evaluateAndRender._dbgAt or (GetTime() - evaluateAndRender._dbgAt) > 1.5 then
      evaluateAndRender._dbgAt = GetTime()
      local nF = forced and (forced.spellName or (forced.spellId and GetSpellInfo(forced.spellId)) or forced.spellId) or nil
      local n1 = p and (GetSpellInfo(p.spellId) or p.spellId) or "-"
      local n2 = s and (GetSpellInfo(s.spellId) or s.spellId) or "-"
      local n3 = t and (GetSpellInfo(t.spellId) or t.spellId) or "-"
      if forced then
        print("MoPRH debug next (forced):", nF, "| queue=", #MoPRH.state.forcedQueue)
      else
        print("MoPRH debug next:", n1, ",", n2, ",", n3)
      end
    end
  end
end

local driver = CreateFrame("Frame")
local throttle = 0

local function onUpdate(_, elapsed)
  throttle = throttle - elapsed
  if throttle <= 0 then
    throttle = 0.05
    evaluateAndRender()
  end
end

driver:SetScript("OnUpdate", onUpdate)

driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:RegisterEvent("PLAYER_TALENT_UPDATE")
driver:RegisterEvent("UNIT_AURA")
driver:RegisterEvent("UNIT_POWER_UPDATE")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_GUID_CHANGED")
driver:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
driver:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

driver:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      MoPRH:InitDB()
      UI:Init()
      if Automation and Automation.Init then Automation:Init() end
      UI:SetLocked(MoPRH:GetDB().locked)
      UI:SetScale(MoPRH:GetDB().scale)
    end
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUID_CHANGED" then
    if Tracker and Tracker.SetPlayerGUID then Tracker:SetPlayerGUID(UnitGUID("player")) end
    C_Timer.After(1, function() evaluateAndRender() end)
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if Tracker and Tracker.OnCombatLogEvent then Tracker:OnCombatLogEvent() end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" and spellID then popIfCasted(spellID) end
  else
    -- trigger refresh on next tick
  end
end)

-- Helpers to print
local function printRules(specId)
  local rules = MoPRH:GetRules(specId)
  print("MoPRH rules (" .. tostring(#rules) .. "):")
  for i, r in ipairs(rules) do
    local name = GetSpellInfo(r.action) or tostring(r.action)
    local mark = (r.enabled == false) and "[X]" or "[ ]"
    print(string.format("%d. %s %s - %s", i, mark, name, r.note or ""))
  end
end

-- Slash commands
SLASH_MOPRH1 = "/mrh"
SlashCmdList["MOPRH"] = function(msg)
  msg = msg or ""
  local args = {}
  for token in string.gmatch(msg, "[^%s]+") do table.insert(args, token) end
  local cmd = string.lower(args[1] or "")

  if cmd == "lock" then
    MoPRH:Set("locked", true)
    UI:SetLocked(true)
    print("MoPRH: locked frame.")
  elseif cmd == "unlock" then
    MoPRH:Set("locked", false)
    UI:SetLocked(false)
    print("MoPRH: unlocked frame. Drag to move.")
  elseif cmd == "scale" then
    local s = tonumber(args[2]) or 1.0
    s = math.max(0.6, math.min(2.0, s))
    MoPRH:Set("scale", s)
    UI:SetScale(s)
    print("MoPRH: scale set to", s)
  elseif cmd == "mode" then
    local m = string.lower(args[2] or "single")
    if m ~= "single" and m ~= "aoe" then m = "single" end
    MoPRH:Set("mode", m)
    print("MoPRH: mode set to", m)
  elseif cmd == "cds" then
    local v = string.lower(args[2] or "on")
    local on = v ~= "off"
    MoPRH:Set("showCooldowns", on)
    print("MoPRH: show CDs:", on and "on" or "off")
  elseif cmd == "showooc" then
    local v = string.lower(args[2] or "off")
    local on = v == "on"
    MoPRH:Set("showWhenOutOfCombat", on)
    print("MoPRH: show out of combat:", on and "on" or "off")
  elseif cmd == "rules" then
    local sub = string.lower(args[2] or "")
    local specId = getPlayerSpecId()
    if sub == "list" then
      printRules(specId)
    elseif sub == "up" or sub == "down" then
      local idx = tonumber(args[3])
      if not idx then print("Usage: /mrh rules up|down <index>") return end
      if MoPRH:MoveRule(specId, idx, sub) then printRules(specId) else print("Move failed") end
    elseif sub == "toggle" then
      local idx = tonumber(args[3])
      if not idx then print("Usage: /mrh rules toggle <index>") return end
      if MoPRH:ToggleRule(specId, idx) then printRules(specId) else print("Toggle failed") end
    else
      print("/mrh rules list | up <i> | down <i> | toggle <i>")
    end
  elseif cmd == "profile" then
    local sub = string.lower(args[2] or "")
    local specId = getPlayerSpecId()
    if sub == "new" then
      local name = args[3] or "Custom"
      if MoPRH:NewProfile(specId, name) then print("Created and using profile:", name) else print("Profile exists:", name) end
    elseif sub == "use" then
      local name = args[3]
      if not name then print("Usage: /mrh profile use <name>") return end
      MoPRH:SetActiveProfile(specId, name)
      print("Using profile:", name)
    else
      local active, prof = MoPRH:GetActiveProfile(specId)
      print("Active profile:", active)
    end
  elseif cmd == "export" then
    local specId = getPlayerSpecId()
    local rules = MoPRH:GetRules(specId)
    if RE and RE.SerializeRules then
      local txt = RE.SerializeRules(rules)
      local chunk = 230
      print("MoPRH export begin:")
      for i = 1, #txt, chunk do
        print(string.sub(txt, i, i + chunk - 1))
      end
      print("MoPRH export end.")
    else
      print("Export not available")
    end
  elseif cmd == "debug" then
    local v = string.lower(args[2] or "off")
    local on = v == "on"
    MoPRH:Set("debug", on)
    print("MoPRH: debug:", on and "on" or "off")
  elseif cmd == "enemies" then
    local np = MoPRH.Nameplates
    local tr = MoPRH.Tracker
    local npCount = (np and np.CountEnemies) and np:CountEnemies() or 0
    local trCount = (tr and tr.EstimatedEnemyCount) and tr:EstimatedEnemyCount() or 0
    local finalCount = math.max(npCount, trCount)
    print("MoPRH enemies: nameplates=", npCount, "tracker=", trCount, "final=", finalCount)
  elseif cmd == "push" then
    local ref = args[2]
    if not ref then print("Usage: /mrh push <spellId|spellName> [ttlSeconds] [note...]") return end
    local ttl = tonumber(args[3]) or 6
    local note
    if #args >= 4 then
      note = table.concat(args, " ", 4)
    end
    local asNumber = tonumber(ref)
    local ok = MoPRH:PushForced(asNumber or ref, ttl, note)
    print(ok and "MoPRH: pushed manual skill" or "MoPRH: push failed")
  elseif cmd == "pushclear" then
    MoPRH:ClearForced()
    print("MoPRH: cleared manual queue")
  elseif cmd == "ahk" then
    if Automation and Automation.Slash then
      Automation:Slash(args, 2)
    else
      print("AHK module unavailable")
    end
  elseif cmd == "macro" then
    if Macro and Macro.Slash then
      Macro:Slash(args, 2)
    else
      print("Macro module unavailable")
    end
  else
    print("MoPRH commands:")
    print("/mrh lock | unlock")
    print("/mrh scale 1.0")
    print("/mrh mode single|aoe")
    print("/mrh cds on|off")
    print("/mrh showooc on|off")
    print("/mrh rules list | up <i> | down <i> | toggle <i>")
    print("/mrh profile new <name> | use <name>")
    print("/mrh export")
    print("/mrh debug on|off")
    print("/mrh enemies")
    print("/mrh push <spellId|spellName> [ttl] [note]")
    print("/mrh pushclear")
    print("/mrh ahk ... (on|off|pos|size|bind|unbind|col|gate|show)")
    print("/mrh macro make|update")
  end
end