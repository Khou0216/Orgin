local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

local Utils = MoPRH.Utils

MoPRH.Automation = {}
local AHK = MoPRH.Automation

local function ensureDefaults(db)
  db.ahk = db.ahk or {}
  local a = db.ahk
  if a.enabled == nil then a.enabled = false end
  if not a.posX then a.posX = 20 end
  if not a.posY then a.posY = 20 end
  if not a.size then a.size = 6 end
  if a.gcdGate == nil then a.gcdGate = true end
  if a.combatGate == nil then a.combatGate = true end
  if a.targetGate == nil then a.targetGate = false end
  if not a.gcdThreshold then a.gcdThreshold = 0.06 end
  a.binds = a.binds or {}      -- [spellId or name] = "1".."6"..
  a.colors = a.colors or {     -- key -> {r,g,b} 0-255
    ["1"] = {255, 0, 0},
    ["2"] = {255, 128, 0},
    ["3"] = {255, 255, 0},
    ["4"] = {0, 255, 0},
    ["5"] = {0, 128, 255},
    ["6"] = {160, 32, 240},
  }
  if not a.offColor then a.offColor = {0, 0, 0} end
end

local frame, tex

function AHK:Init()
  ensureDefaults(MoPRH:GetDB())
  if frame then return end
  frame = CreateFrame("Frame", "MoPRH_AHK_Signal", UIParent)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetClampedToScreen(true)
  tex = frame:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(true)
  self:ApplyLayout()
  self:ApplyEnabled()
  self:SetColor(0, 0, 0)
end

function AHK:ApplyLayout()
  local a = MoPRH:GetDB().ahk
  if not frame then return end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", a.posX, -a.posY)
  frame:SetSize(a.size, a.size)
end

function AHK:ApplyEnabled()
  local a = MoPRH:GetDB().ahk
  if not frame then return end
  if a.enabled then frame:Show() else frame:Hide() end
end

function AHK:SetColor(r8, g8, b8)
  if not tex then return end
  tex:SetColorTexture((r8 or 0)/255, (g8 or 0)/255, (b8 or 0)/255, 1)
end

local function resolveSpellRef(spellRef)
  if type(spellRef) == "number" then
    local name = GetSpellInfo(spellRef)
    return spellRef, name
  else
    local name, _, _, _, _, _, spellId = GetSpellInfo(spellRef)
    return spellId, name or spellRef
  end
end

local function gatingAllows(ctx)
  local a = MoPRH:GetDB().ahk
  if a.combatGate and not ctx.inCombat then return false end
  if a.targetGate and not ctx.targetExists then return false end
  if a.gcdGate then
    local gcd = Utils.GetGCDRemaining()
    if gcd > (a.gcdThreshold or 0.06) then return false end
  end
  return true
end

local lastKey

function AHK:UpdateFromSuggestion(suggestion, ctx)
  if not frame then self:Init() end
  local a = MoPRH:GetDB().ahk
  if not a.enabled then
    self:SetColor(a.offColor[1], a.offColor[2], a.offColor[3])
    return
  end

  if not suggestion or not gatingAllows(ctx) then
    self:SetColor(a.offColor[1], a.offColor[2], a.offColor[3])
    lastKey = nil
    return
  end

  local id = suggestion.spellId
  local name = suggestion.spellName or (id and GetSpellInfo(id))
  local key = (id and a.binds[id]) or (name and a.binds[name])

  if not key then
    self:SetColor(a.offColor[1], a.offColor[2], a.offColor[3])
    lastKey = nil
    return
  end

  local rgb = a.colors[key]
  if not rgb then
    self:SetColor(a.offColor[1], a.offColor[2], a.offColor[3])
    lastKey = nil
    return
  end

  -- Set color for AHK
  self:SetColor(rgb[1], rgb[2], rgb[3])
  lastKey = key
end

-- Slash subcommands: /mrh ahk ...
local function printUsage()
  print("/mrh ahk on|off")
  print("/mrh ahk pos <x> <y>")
  print("/mrh ahk size <n>")
  print("/mrh ahk bind <spellId|name> <key>")
  print("/mrh ahk unbind <spellId|name>")
  print("/mrh ahk col <key> <R> <G> <B>")
  print("/mrh ahk gate gcd|combat|target on|off")
  print("/mrh ahk show")
end

function AHK:Slash(args, startIdx)
  ensureDefaults(MoPRH:GetDB())
  local a = MoPRH:GetDB().ahk
  local sub = string.lower(args[startIdx+0] or "")
  if sub == "on" or sub == "off" then
    a.enabled = (sub == "on")
    self:ApplyEnabled()
    print("MoPRH AHK:", a.enabled and "on" or "off")
  elseif sub == "pos" then
    local x = tonumber(args[startIdx+1]) or a.posX
    local y = tonumber(args[startIdx+2]) or a.posY
    a.posX, a.posY = x, y
    self:ApplyLayout()
    print("MoPRH AHK pos:", x, y)
  elseif sub == "size" then
    local n = tonumber(args[startIdx+1]) or a.size
    a.size = math.max(1, math.min(50, n))
    self:ApplyLayout()
    print("MoPRH AHK size:", a.size)
  elseif sub == "bind" then
    local ref = args[startIdx+1]
    local key = args[startIdx+2]
    if not ref or not key then print("Usage: /mrh ahk bind <spellId|name> <key>") return end
    local asNum = tonumber(ref)
    local id, name = resolveSpellRef(asNum or ref)
    if id then a.binds[id] = key end
    if name then a.binds[name] = key end
    print("MoPRH AHK bind:", name or id, "->", key)
  elseif sub == "unbind" then
    local ref = args[startIdx+1]
    if not ref then print("Usage: /mrh ahk unbind <spellId|name>") return end
    local asNum = tonumber(ref)
    local id, name = resolveSpellRef(asNum or ref)
    if id then a.binds[id] = nil end
    if name then a.binds[name] = nil end
    print("MoPRH AHK unbind:", name or id)
  elseif sub == "col" then
    local key = args[startIdx+1]
    local r = tonumber(args[startIdx+2]) or 0
    local g = tonumber(args[startIdx+3]) or 0
    local b = tonumber(args[startIdx+4]) or 0
    if not key then print("Usage: /mrh ahk col <key> <R> <G> <B>") return end
    a.colors[key] = {r, g, b}
    print("MoPRH AHK color:", key, r, g, b)
  elseif sub == "gate" then
    local which = string.lower(args[startIdx+1] or "")
    local val = string.lower(args[startIdx+2] or "on") == "on"
    if which == "gcd" then a.gcdGate = val
    elseif which == "combat" then a.combatGate = val
    elseif which == "target" then a.targetGate = val
    else print("Usage: /mrh ahk gate gcd|combat|target on|off") return end
    print("MoPRH AHK gate:", which, val and "on" or "off")
  elseif sub == "show" then
    print("AHK enabled:", a.enabled)
    print("pos:", a.posX, a.posY, " size:", a.size)
    print("gates:", "gcd="..tostring(a.gcdGate), "combat="..tostring(a.combatGate), "target="..tostring(a.targetGate))
    print("binds:")
    local c = 0
    for k, v in pairs(a.binds) do
      local name = type(k) == "number" and (GetSpellInfo(k) or k) or k
      print(" -", name, "->", v)
      c = c + 1
    end
    if c == 0 then print(" (none)") end
  else
    printUsage()
  end
end