# Dim the save-pipe highlight + reset it when the ball resets

## Problem
The "last save" pipe highlight (the glowing overlay on the saved square's overhead pipes) is **too
bright** and it **persists across rallies** — it should be a subtler hint and should clear when the
ball resets for a new serve.

## Change
1. **Dimmer:** the `SaveHighlight` overlay (built in `MatchService.buildArena`, Neon, coloured
   `GridConfig.saveHighlightColor`) is too intense. Make it noticeably dimmer — soften the colour and/or
   add transparency (a non-glowing material or a partially-transparent neon). Keep it readable as a
   "last save here" hint, just not a bright bar. Tunable in `GridConfig`.
2. **Reset on ball reset:** when the ball **resets for a new serve / new rally** (the re-serve path),
   clear the highlight (hide the overlay + set `lastSavedCell = nil`), so it only shows the last save of
   the CURRENT rally and doesn't linger into the next one. Wire the clear where the next rally is served
   (`NineSquareServer` — the `onRest`→re-serve / `serveNextRally` / `resetToServe` path). Expose a
   `MatchService.clearSaveHighlight()` (or `highlightSavedCell(nil)`) and call it on reset.

## Acceptance criteria
- The save highlight is clearly **dimmer/softer** than before (not a bright neon bar).
- When the ball **resets/re-serves** (a new rally), the highlight **clears** — no leftover highlight from
  the previous rally; it only reappears on the next save.
- Visual only; the loop, fault/save logic, rotation, etc. are unchanged. Verified in Play.

## Relevant files
- `src/shared/GridConfig.luau` — dim `saveHighlightColor` and/or add a transparency tunable.
- `src/server/MatchService.luau` — the `SaveHighlight` overlay build (apply dimmer look) + a
  `clearSaveHighlight()` / `highlightSavedCell(nil)` hide path.
- `src/server/NineSquareServer.server.luau` — call the clear on the re-serve/reset (where `lastSavedCell`
  lives), and null `lastSavedCell`.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a stale module — use `script_read`/`get_console_output`/screenshots; leave Studio in
  **Edit**).

## Constraints
- Visual only — don't change the save DETECTION (over-pipe clear), the loop, or rotation. Tunables in
  `GridConfig`.
