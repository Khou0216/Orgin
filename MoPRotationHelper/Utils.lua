local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.Utils = MoPRH.Utils or {}
local Utils = MoPRH.Utils
local Cache = MoPRH.Cache

local GCD_SPELL_ID = 61304

local function now()
  return GetTime()
end

function Utils.GetSpellName(spellIdOrName)
  if type(spellIdOrName) == "number" then
    local name = GetSpellInfo(spellIdOrName)
    return name
  end
  return spellIdOrName
end

function Utils.IsSpellReady(spellIdOrName)
  local ref = spellIdOrName
  local name = Utils.GetSpellName(ref)
  if not name then return false, math.huge, 0, nil, nil end

  local key = Cache:Key({"cooldown", tostring(ref)})
  local data = Cache:Remember(key, function()
    local start, duration = GetSpellCooldown(ref)
    local charges, maxCharges = GetSpellCharges and GetSpellCharges(ref) or nil, nil
    local usable, noMana = IsUsableSpell(ref)
    local icon = GetSpellTexture(name)

    local cdRemains = 0
    if start and duration then
      local finish = start + duration
      cdRemains = math.max(0, finish - now())
    end

    local ready = usable and cdRemains == 0
    if maxCharges and maxCharges > 0 then
      ready = (charges or 0) > 0 and usable
    end

    return { ready = ready, cdRemains = cdRemains, charges = charges or 0, icon = icon, name = name }
  end)

  return data.ready, data.cdRemains, data.charges, data.icon, data.name
end

function Utils.GetGCDRemaining()
  local key = Cache:Key({"gcd"})
  return Cache:Remember(key, function()
    local start, duration = GetSpellCooldown(GCD_SPELL_ID)
    if not start or not duration then return 0 end
    local remaining = (start + duration) - now()
    if remaining < 0 then remaining = 0 end
    return remaining
  end)
end

function Utils.GetAura(unit, spellIdOrName, filter)
  local key = Cache:Key({"aura", unit or "", tostring(spellIdOrName or ""), filter or ""})
  return Cache:Remember(key, function()
    local nameOrId = Utils.GetSpellName(spellIdOrName) or spellIdOrName
    local i = 1
    while true do
      local name, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, i, filter)
      if not name then break end
      if (spellIdOrName and spellId == spellIdOrName) or (nameOrId and name == nameOrId) then
        local timeRemaining = expirationTime and (expirationTime - now()) or 0
        return {
          name = name,
          icon = icon,
          count = count or 0,
          duration = duration or 0,
          expiresIn = timeRemaining,
          source = source,
          spellId = spellId,
        }
      end
      i = i + 1
    end
    return nil
  end)
end

function Utils.GetUnitHealthPercent(unit)
  local hp = UnitHealth(unit)
  local hpMax = UnitHealthMax(unit)
  if hpMax == 0 then return 0 end
  return (hp / hpMax) * 100
end

function Utils.IsMoving()
  return GetUnitSpeed("player") > 0
end

function Utils.Power(playerUnit, powerType)
  local cur = UnitPower(playerUnit, powerType)
  local max = UnitPowerMax(playerUnit, powerType)
  return cur, max
end

function Utils.InCombat()
  return UnitAffectingCombat("player") == true
end

function Utils.IsChanneling()
  local name = UnitChannelInfo and UnitChannelInfo("player")
  return name ~= nil
end

function Utils.GetCharges(spellIdOrName)
  local ref = spellIdOrName
  local key = Cache:Key({"charges", tostring(ref)})
  return Cache:Remember(key, function()
    local charges, maxCharges, start, duration
    if GetSpellCharges then
      charges, maxCharges, start, duration = GetSpellCharges(ref)
    end
    local rechargeRemains = 0
    if start and duration then
      rechargeRemains = math.max(0, (start + duration) - now())
    end
    return { charges = charges or 0, max = maxCharges or 0, recharge = rechargeRemains }
  end)
end

function Utils.GetEnergyRegenPerSec()
  local key = Cache:Key({"energyRegen"})
  return Cache:Remember(key, function()
    -- Try API if available (retail has GetPowerRegenForPowerType; fallback to haste formula)
    local regen
    if GetPowerRegenForPowerType then
      local r = GetPowerRegenForPowerType(Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
      regen = r
    end
    if not regen then
      local haste = GetHaste and (GetHaste() or 0) or 0
      regen = 10 * (1 + haste / 100)
    end
    return regen or 10
  end)
end

function Utils.ForecastEnergy(seconds)
  local cur = UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
  local max = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Energy or 3)
  local regen = Utils.GetEnergyRegenPerSec()
  local val = cur + (regen * math.max(0, seconds or 0))
  if val > max then val = max end
  if val < 0 then val = 0 end
  return val, max, regen
end

function Utils.ForecastRage(seconds)
  -- Rage forecast is highly situational; use current rage as conservative estimate
  local cur = UnitPower("player", Enum and Enum.PowerType and Enum.PowerType.Rage or 1)
  local max = UnitPowerMax("player", Enum and Enum.PowerType and Enum.PowerType.Rage or 1)
  return cur, max, 0
end