local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.MacroData = MoPRH.MacroData or {}
local DATA = MoPRH.MacroData

-- Standardized key slots (string): "1".."6" initially
-- Per specId, define key -> spellId

DATA[269] = {
  name = "Monk-Windwalker",
  keys = {
    ["1"] = 100780,   -- Jab (Builder)
    ["2"] = 100787,   -- Tiger Palm
    ["3"] = 100784,   -- Blackout Kick
    ["4"] = 107428,   -- Rising Sun Kick
    ["5"] = 113656,   -- Fists of Fury
    ["6"] = 101546,   -- Spinning Crane Kick (AoE)
  }
}