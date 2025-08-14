local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local DATA = MoPRH.MacroData

MoPRH.Macro = {}
local Macro = MoPRH.Macro

local function getSpecId()
  if not GetSpecialization then return nil end
  local idx = GetSpecialization()
  if not idx then return nil end
  return GetSpecializationInfo(idx)
end

local function ensureAutomationBinds(specId)
  local a = MoPRH:GetDB().ahk
  a.binds = a.binds or {}
  local spec = DATA[specId]
  if not spec then return end
  for key, spell in pairs(spec.keys or {}) do
    local name = GetSpellInfo(spell)
    if name then
      a.binds[spell] = key
      a.binds[name] = key
    end
  end
end

local function macroNameFor(key)
  return ("MRH_" .. key)
end

local function macroBodyFor(spellId)
  local name = GetSpellInfo(spellId) or ("spell:" .. tostring(spellId))
  return "#showtooltip\n/cast " .. name
end

function Macro:GenerateForSpec(specId)
  local spec = DATA[specId]
  if not spec then print("Macro: no data for spec", specId) return end

  ensureAutomationBinds(specId)

  local numGlobal, numPerChar = GetNumMacros()
  for key, spell in pairs(spec.keys or {}) do
    local mName = macroNameFor(key)
    local body = macroBodyFor(spell)
    local existingIndex = GetMacroIndexByName(mName)
    if existingIndex and existingIndex > 0 then
      EditMacro(existingIndex, mName, nil, body)
    else
      CreateMacro(mName, "INV_MISC_QUESTIONMARK", body, true) -- per-character macro
    end
  end

  print("MoPRH macro: generated", spec.name)
end

-- Slash integration: /mrh macro make
function Macro:Slash(args, startIdx)
  local sub = string.lower(args[startIdx+0] or "")
  if sub == "make" or sub == "update" then
    local specId = getSpecId()
    if not specId then print("Macro: cannot detect spec") return end
    self:GenerateForSpec(specId)
  else
    print("/mrh macro make|update")
  end
end