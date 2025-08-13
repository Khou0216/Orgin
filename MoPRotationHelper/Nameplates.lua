local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.Nameplates = {}
local NP = MoPRH.Nameplates

local function hasNameplateUnits()
  -- Probe a small range; tokens don't exist if nameplates disabled or API missing
  for i = 1, 3 do
    if UnitExists("nameplate" .. i) then return true end
  end
  return false
end

local function countByUnitTokens()
  local count = 0
  for i = 1, 60 do
    local unit = "nameplate" .. i
    if UnitExists(unit) then
      if UnitCanAttack("player", unit) and not UnitIsDead(unit) then
        count = count + 1
      end
    end
  end
  return count
end

local function countByFrames()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return 0 end
  local plates = C_NamePlate.GetNamePlates()
  if not plates then return 0 end
  local count = 0
  for _, frame in ipairs(plates) do
    local unit = frame and (frame.namePlateUnitToken or frame.unitToken)
    if unit and UnitExists(unit) then
      if UnitCanAttack("player", unit) and not UnitIsDead(unit) then
        count = count + 1
      end
    else
      -- Fallback: count it, but this may include friendlies if shown
      count = count + 1
    end
  end
  return count
end

function NP:CountEnemies()
  if hasNameplateUnits() then
    return countByUnitTokens()
  end
  return countByFrames()
end