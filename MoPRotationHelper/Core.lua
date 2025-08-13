local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local UI = MoPRH.UI
local Utils = MoPRH.Utils

-- Rotation registry keyed by specId
MoPRH.Rotations = {}

function MoPRH.RegisterRotation(specId, rotation)
  MoPRH.Rotations[specId] = rotation
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
  local ctx = buildContext()
  local rotation = MoPRH.Rotations[ctx.specId]

  local shouldShow = ctx.inCombat or ctx.db.showWhenOutOfCombat
  if not shouldShow then
    UI:Hide()
    return
  end

  UI:Show()

  if not rotation or not rotation.Evaluate then
    UI:Update(nil, nil, nil)
    return
  end

  local p, s, t = rotation:Evaluate(ctx)
  UI:Update(p, s, t)
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

driver:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      MoPRH:InitDB()
      UI:Init()
      UI:SetLocked(MoPRH:GetDB().locked)
      UI:SetScale(MoPRH:GetDB().scale)
    end
  elseif event == "PLAYER_LOGIN" then
    C_Timer.After(1, function() evaluateAndRender() end)
  else
    -- All other events simply trigger a refresh next tick
  end
end)

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
  else
    print("MoPRH commands:")
    print("/mrh lock | unlock")
    print("/mrh scale 1.0")
    print("/mrh mode single|aoe")
    print("/mrh cds on|off")
    print("/mrh showooc on|off")
  end
end