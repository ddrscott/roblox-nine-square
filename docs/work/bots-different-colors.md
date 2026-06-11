# Give the bots different colors (variety)

## Problem
All bot rigs share one body color (violet), so they look identical. Give each bot a different color for
visual variety so they read as distinct characters.

## What to do
- In `RotationService` (where the R15 bot rigs are built/colored — currently applies `botBodyColor` to the
  rig body parts, `botKingColor` for the King), assign each bot a **distinct color from a palette** so the
  bots are visibly different from each other.
  - Add `GridConfig.botColors = { ... }` — a set of ~8 tasteful, distinct colors (enough for all bot slots).
    Assign deterministically per bot (e.g. cycle the palette by the bot's creation index / slot) so each bot
    has its own colour and it's stable while that bot is on the board.
  - Color the visible R15 body parts (torso/arms/legs) — not the jersey label.
- **Keep the King clearly readable.** The King already has the gold jersey + 👑 crown (jersey task) + the
  gold King floor square. Preferred: keep the existing **gold body treatment while a bot is at rank 1**
  (King), reverting to the bot's own palette colour when it's not King — so the King still pops AND non-King
  bots are varied. (If keeping the King-gold body is awkward with per-bot colours, it's acceptable to drop it
  and rely on the gold jersey/crown for King ID — but the King must stay obvious.)
- Humans are unaffected (they use their own avatars; only the R15 BOT rigs are recolored).

## Acceptance criteria
- The 8 bots are visibly DIFFERENT colors from each other (not all violet) — verified via `screen_capture`.
- The King is still clearly identifiable (gold body and/or the gold jersey + crown + King floor square).
- Colors are stable per bot while it's on the board and travel with the bot through rotations; no
  gameplay/collision/animation change (cosmetic body color only). Studio left in Edit.

## Relevant files
- `src/server/RotationService.luau` — bot rig body coloring (apply per-bot palette color; King treatment).
- `src/shared/GridConfig.luau` — `botColors` palette (+ keep `botKingColor`).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output` + `screen_capture` showing the varied bot colors +
  the King still marked. Leave Studio in Edit.)

## Constraints
- Cosmetic body-color only — don't change bot behaviour, the hit collider, animations, rotation, or the
  deterministic physics. Keep the King obvious. Palette in `GridConfig`.
