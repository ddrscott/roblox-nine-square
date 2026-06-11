# Move the stamina meter above the scoreboard + make it shorter

## Problem
The stamina meter currently sits at the bottom-center (the "STAMINA" bar), taking space / drawing the eye
there. Move it up to sit **above the scoreboard** (the stats panel is top-right) and make it **shorter**
(narrower/smaller), so the HUD is tidy and the bottom-center is clear.

## What to do
- Reposition the stamina bar to the **top-RIGHT, directly ABOVE the scoreboard / stats panel** (right-
  anchored, just above the stats panel's top edge — mind the CoreGui topbar so it isn't clipped).
- Make it **shorter** — reduce its width/length (and keep the height slim); roughly match the scoreboard's
  width so it reads as part of that right-side cluster. Keep it readable as a fill bar.
- Keep it consistent with the shared `GridConfig.uiStyle` (label/panel look) and don't overlap the stats
  panel, the lobby buttons, the rank pill (now top-left), the mobile camera toggle, or the jump button.
- It's a player-movement HUD element (only relevant while seated/playing) — keep its existing show/hide
  behaviour; just move + resize.

## Acceptance criteria
- The stamina meter sits above the scoreboard (top-right), shorter than before, not at bottom-center; it
  still fills/drains correctly with stamina and doesn't overlap other HUD elements. Readable on desktop AND
  a phone aspect (verify with `screen_capture`). Behaviour unchanged. Studio left in Edit.

## Relevant files
- `src/client/Movement.client.luau` — the stamina bar UI (position + size). (If the stamina HUD lives
  elsewhere, find it via a grep for the stamina bar / "STAMINA".)
- `src/shared/GridConfig.luau` — any stamina-bar size/position tunables (+ reference the scoreboard's
  width/position so it aligns above it).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client UI on the Client
  datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` to confirm placement above the scoreboard + no overlaps. Leave Studio in Edit.)

## Constraints
- UI placement/size ONLY — don't change the stamina/dash/flip behaviour or values, gameplay, or other HUD
  elements' positions. Keep consistent with the shared UI style; no overlaps. Tunables in `GridConfig`.
