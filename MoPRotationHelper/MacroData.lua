local addonName = ...
_G.MoPRH = _G.MoPRH or {}
local MoPRH = _G.MoPRH

MoPRH.MacroData = MoPRH.MacroData or {}
local DATA = MoPRH.MacroData

-- Monk - Windwalker (269)
DATA[269] = {
  name = "Monk-Windwalker",
  keys = {
    ["1"] = 100780,   -- Jab
    ["2"] = 100787,   -- Tiger Palm
    ["3"] = 100784,   -- Blackout Kick
    ["4"] = 107428,   -- Rising Sun Kick
    ["5"] = 113656,   -- Fists of Fury
    ["6"] = 101546,   -- Spinning Crane Kick
  }
}

-- Rogue - Assassination (259)
DATA[259] = {
  name = "Rogue-Assassination",
  keys = {
    ["1"] = 1752,     -- Sinister Strike (MoP: Mutilate is 1329 but builder differs by spec; adjust in real data)
    ["2"] = 1329,     -- Mutilate
    ["3"] = 32645,    -- Envenom
    ["4"] = 1943,     -- Rupture
    ["5"] = 51723,    -- Fan of Knives
    ["6"] = 2098,     -- Eviscerate (fallback)
  }
}

-- Druid - Feral (103)
DATA[103] = {
  name = "Druid-Feral",
  keys = {
    ["1"] = 5221,     -- Shred
    ["2"] = 33876,    -- Mangle (Cat) legacy id may vary in MoP; use Shred/Rake/Rip
    ["3"] = 1822,     -- Rake
    ["4"] = 1079,     -- Rip
    ["5"] = 22568,    -- Ferocious Bite
    ["6"] = 106785,   -- Swipe (Cat)
  }
}