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

## Extending

- Add new spec files under `Rotations/` and register with `MoPRH.RegisterRotation(specId, rotationTable)`. The table must implement `Evaluate(ctx)` and return up to three suggestions: `{ spellId = 12345, note = "reason" }`.
- Use `Utils.IsSpellReady(spellId)`, `Utils.GetAura(unit, spellId)`, and `Utils.GetGCDRemaining()` for logic.

## Disclaimer
Guidance only. The addon never presses keys or automates actions.