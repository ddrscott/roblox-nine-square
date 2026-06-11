# Make the green active-grid highlight tighter to the grid + dimmer (subtle)

## Problem
The green highlight on the active/King grid square is too bright and sits proud of the regular grid, drawing
attention. Make it **tighter to the regular grid lines** and **dimmer / subtle** — it shouldn't grab the eye.

## What to do
- Find the green active-cell highlight in the client (grep for the green `SelectionBox`/highlight box around
  the active / King / current cell — likely `NineSquareClient.client.luau` or `RankHud.client.luau`; the
  predicted-landing highlight is a separate GOLD one — this is the GREEN one).
- **Tighter to the grid:** size/position it so it ALIGNS with the actual grid line / cell border (the
  `squareSize` edge at the grid height) instead of a separate inset/proud box — it should hug the regular
  grid lines, not float inside/around them. Use a thinner line.
- **Dimmer / subtle:** darken/desaturate the green and raise its transparency (and/or thin the line) so it's
  a quiet hint of which square is active, not a bright attention-grabber. Keep it just visible enough to read
  the active/King square.
- Put the colour / thickness / transparency in `GridConfig` tunables so it's adjustable.

## Acceptance criteria
- The green active-square highlight reads as SUBTLE — dim, thin, and aligned tight to the regular grid lines
  (no bright proud box). It still indicates the active/King square but doesn't draw attention. Verified via
  `screen_capture`.
- No other highlight affected (the gold predicted-landing highlight + gold King floor square unchanged
  unless they ARE the element in question — only the green one). No gameplay change. Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` / `src/client/RankHud.client.luau` — the green active-cell
  highlight (SelectionBox color/thickness/transparency + its size/position to align with the grid).
- `src/shared/GridConfig.luau` — green-highlight tunables (color/thickness/transparency) if useful.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client visuals on the
  Client datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output` +
  `screen_capture`. Leave Studio in Edit.)

## Constraints
- Cosmetic only — don't change gameplay or the other highlights (gold landing / King square). Keep the green
  highlight just readable as "active square" but subtle + aligned to the grid. Tunables in `GridConfig`.
