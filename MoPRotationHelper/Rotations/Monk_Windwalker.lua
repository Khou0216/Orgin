local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local Utils = MoPRH.Utils

local WW = {}
WW.__index = WW

-- Spell IDs (MoP-era)
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

-- Auras
local AURA = {
  TigerPower = 125359, -- Tiger Palm buff
  RisingSunKickDebuff = 130320,
  TigereyeBrewBuff = 125195,
}

local function suggest(spellId, note)
  return { spellId = spellId, note = note }
end

local function isSpellReady(spellId)
  local ready = Utils.IsSpellReady(spellId)
  return ready
end

function WW:Evaluate(ctx)
  local mode = ctx.db.mode or "single"
  local showCDs = ctx.db.showCooldowns

  local tigerPower = Utils.GetAura("player", AURA.TigerPower, "HELPFUL")
  local rskDebuff = Utils.GetAura("target", AURA.RisingSunKickDebuff, "HARMFUL")

  local suggestions = {}

  -- Defensive/self-heal consideration
  if ctx.inCombat and Utils.GetUnitHealthPercent("player") < 70 then
    local usable = Utils.IsSpellReady(SPELL.ExpelHarm)
    if usable then table.insert(suggestions, suggest(SPELL.ExpelHarm, "自保")) end
  end

  -- Execute: Touch of Death
  if ctx.targetExists and ctx.targetHp <= 10 then
    local usable = Utils.IsSpellReady(SPELL.TouchOfDeath)
    if usable then table.insert(suggestions, suggest(SPELL.TouchOfDeath, "斩杀")) end
  end

  -- Maintain Tiger Power via Tiger Palm
  if (not tigerPower) or (tigerPower.expiresIn < 3) then
    local usable = Utils.IsSpellReady(SPELL.TigerPalm)
    if usable then table.insert(suggestions, suggest(SPELL.TigerPalm, "破甲")) end
  end

  -- Keep Rising Sun Kick debuff up
  if ctx.targetExists and ((not rskDebuff) or (rskDebuff.expiresIn < 3)) then
    local usable = Utils.IsSpellReady(SPELL.RisingSunKick)
    if usable then table.insert(suggestions, suggest(SPELL.RisingSunKick, "日落踢减益")) end
  end

  -- Fists of Fury: when not moving, GCD free, have chi, and RSK up
  if showCDs and not ctx.isMoving and ctx.power.chi >= 3 and rskDebuff then
    local usable = Utils.IsSpellReady(SPELL.FistsOfFury)
    if usable then table.insert(suggestions, suggest(SPELL.FistsOfFury, "风火雷电")) end
  end

  -- Tigereye Brew at 10 stacks or execute window
  if showCDs then
    local teb = Utils.GetAura("player", AURA.TigereyeBrewBuff, "HELPFUL")
    if teb and teb.count and teb.count >= 10 then
      local usable = Utils.IsSpellReady(SPELL.TigereyeBrew)
      if usable then table.insert(suggestions, suggest(SPELL.TigereyeBrew, "10层猛虎之眼")) end
    end
  end

  -- AoE: Spinning Crane Kick if 3+ targets (we cannot count targets reliably; use mode toggle)
  if mode == "aoe" then
    local usable = Utils.IsSpellReady(SPELL.SpinningCraneKick)
    if usable then table.insert(suggestions, suggest(SPELL.SpinningCraneKick, "顺劈")) end
  end

  -- Blackout Kick as chi spender
  if ctx.power.chi >= 3 then
    local usable = Utils.IsSpellReady(SPELL.BlackoutKick)
    if usable then table.insert(suggestions, suggest(SPELL.BlackoutKick, "消耗真气")) end
  end

  -- Chi Wave on cooldown as filler/off-GCD-ish
  if showCDs then
    local usable = Utils.IsSpellReady(SPELL.ChiWave)
    if usable then table.insert(suggestions, suggest(SPELL.ChiWave, "天赋")) end
  end

  -- Jab as builder if energy allows
  if ctx.power.energy >= 50 then
    local usable = Utils.IsSpellReady(SPELL.Jab)
    if usable then table.insert(suggestions, suggest(SPELL.Jab, "回真气")) end
  end

  -- Return up to 3
  return suggestions[1], suggestions[2], suggestions[3]
end

MoPRH.RegisterRotation(269, setmetatable({}, WW))