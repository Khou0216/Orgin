# MoP Rotation Helper (MoPRH)

Data-driven, suggestions-only rotation helper for WoW MoP Classic. Shows up to 3 next actions. No automation.

## Install

1. Copy the `MoPRotationHelper` folder into your WoW `_classic_era_` (or MoP Classic) AddOns folder, e.g.:
   - Windows: `World of Warcraft/_classic_/Interface/AddOns/MoPRotationHelper`
   - macOS: `World of Warcraft/_classic_/Interface/AddOns/MoPRotationHelper`
2. Restart the game and enable the addon on the character select screen.

If the addon does not load, you may need to adjust the `## Interface` number in `MoPRotationHelper.toc` to match your MoP Classic client build (e.g., `50402`).

## Commands

- /mrh lock | unlock — lock/unlock frame
- /mrh scale 1.2 — set UI scale (0.6–2.0)
- /mrh mode single|aoe — toggle single-target vs AoE hinting
- /mrh cds on|off — toggle showing cooldown recommendations
- /mrh showooc on|off — show suggestions out of combat
- /mrh rules list | up <i> | down <i> | toggle <i>
- /mrh export — export rules as Lua table
- /mrh import <rules_table> — import rules
- /mrh enemies — print nameplates/tracker enemy counts
- /mrh debug on|off — print debug suggestions
- /mrh pool energy|rage on|off | thresh <n> | win <sec> | buffer <n>
- /mrh macro make|update — generate per-key macros (MRH_1..MRH_6) for current spec

## Pooling (resource forecasting)
- Energy forecast: `Utils.ForecastEnergy(seconds)` uses regen estimate (haste-aware fallback)
- Rage forecast: conservative placeholder returns current value
- Default energy pooling: threshold 50, window 0.6s, overcap buffer 5 (configurable via `/mrh pool`)

## Macros
- Macro data in `MacroData.lua` defines per-spec key→spell maps
- `/mrh macro make` generates `MRH_1..MRH_6` macros and updates Automation binds accordingly

## Extending

- Add new spec files under `Rotations/` and register with `MoPRH.RegisterRotation(specId, rotationTable)`. The table must implement `Evaluate(ctx)` and return up to three suggestions: `{ spellId = 12345, note = "reason" }`.
- Use `Utils.IsSpellReady(spellId)`, `Utils.GetAura(unit, spellId)`, `Utils.GetGCDRemaining()` for logic.
- RuleEngine supports conditions including `whenAny/whenAll`, auras, charges, cooldown windows, enemy counts, and resource forecast.

## Disclaimer
Guidance only. The addon never presses keys or automates actions.