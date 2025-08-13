local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.UI = {}
local UI = MoPRH.UI

local ICON_SIZE = 48
local GAP = 8

local function createIcon(parent, size)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(true)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  frame.icon = icon

  -- Simple background (no BackdropTemplate to keep compatibility)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(true)
  bg:SetColorTexture(0, 0, 0, 0.1)
  frame.bg = bg

  local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
  cd:SetAllPoints(true)
  frame.cooldown = cd

  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("BOTTOMRIGHT", -2, 2)
  frame.text = text

  return frame
end

local function clearCooldownSafe(cooldown)
  if cooldown.Clear then
    cooldown:Clear()
  else
    cooldown:SetCooldown(0, 0)
  end
end

function UI:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", "MoPRH_MainFrame", UIParent)
  f:SetSize((ICON_SIZE * 3) + (GAP * 2), ICON_SIZE)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function()
    if not MoPRH:GetDB().locked then f:StartMoving() end
  end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local i1 = createIcon(f, ICON_SIZE)
  i1:SetPoint("LEFT", f, "LEFT")
  local i2 = createIcon(f, ICON_SIZE)
  i2:SetPoint("LEFT", i1, "RIGHT", GAP, 0)
  local i3 = createIcon(f, ICON_SIZE)
  i3:SetPoint("LEFT", i2, "RIGHT", GAP, 0)

  self.frame = f
  self.icons = {i1, i2, i3}

  self:SetScale(MoPRH:GetDB().scale or 1.0)
  self:SetLocked(MoPRH:GetDB().locked)
  self:Show()
end

function UI:SetLocked(locked)
  if not self.frame then return end
  if locked then
    self.frame:EnableMouse(false)
  else
    self.frame:EnableMouse(true)
  end
end

function UI:SetScale(scale)
  if not self.frame then return end
  self.frame:SetScale(scale or 1.0)
end

local function setIcon(iconFrame, suggestion)
  if not suggestion then
    iconFrame.icon:SetTexture(nil)
    clearCooldownSafe(iconFrame.cooldown)
    iconFrame.text:SetText("")
    return
  end

  local _, _, _, icon = GetSpellInfo(suggestion.spellId or suggestion.spellName or 0)
  if not icon then
    icon = suggestion.icon
  end

  iconFrame.icon:SetTexture(icon)
  local start, duration = GetSpellCooldown(suggestion.spellId or suggestion.spellName)
  if start and duration and duration > 0 then
    iconFrame.cooldown:SetCooldown(start, duration)
  else
    clearCooldownSafe(iconFrame.cooldown)
  end
  iconFrame.text:SetText(suggestion.note or "")
end

function UI:Update(primary, secondary, tertiary)
  if not self.frame then return end
  setIcon(self.icons[1], primary)
  setIcon(self.icons[2], secondary)
  setIcon(self.icons[3], tertiary)
end

function UI:Show()
  if self.frame then self.frame:Show() end
end

function UI:Hide()
  if self.frame then self.frame:Hide() end
end