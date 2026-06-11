# Move the rank pill + status/event indicator from top-center to the LEFT

## Problem
The **rank pill** ("Rank N" / "KING") and the **status / event indicator** (the join/leave/rotation toast
feed) sit at the **top-CENTER** of the screen, obstructing the play area. Move them to the **LEFT** so the
center is clear for the court.

## What to do
- In `RankHud.client.luau`, re-anchor the **rank pill** (currently `AnchorPoint (0.5,0)`, `Position
  UDim2.new(0.5,0,0,16)` — top-centre) to the **top-LEFT**: e.g. `AnchorPoint (0,0)`, `Position
  UDim2.new(0, margin, 0, 16)` (a small left margin, clear of the CoreGui topbar / chat + mic buttons in the
  top-left — drop it a bit if it would collide with those).
- Move the **event toast feed** (currently top-centre, `toastHolder` at `UDim2.new(0.5,0,0,64)`) to the
  **LEFT** as well (left-anchored), stacked under the rank pill, so status messages read down the left edge
  instead of over the center.
- Keep them readable + consistent with the shared `GridConfig.uiStyle` (label styling from the last UI
  pass). Left-align the toast text if needed so it reads cleanly from the left edge.
- The center top is now CLEAR. The right side keeps the stats scoreboard (top-right) + the lobby buttons
  (Join/Leave/Spectating, right under the scoreboard) from the prior tasks — don't move those; just clear
  the center by moving the rank + status to the left.
- Mind the top-left CoreGui buttons (the Roblox menu / chat / mic icons live top-left) — position the rank
  pill below/clear of them so it isn't hidden behind them.

## Acceptance criteria
- The rank pill + the status/event toasts are on the **LEFT**; the top-CENTER is clear of the play area.
- They don't collide with the top-left CoreGui buttons, the right-side scoreboard, or the lobby buttons;
  readable + consistent on desktop AND a phone aspect (verify with `screen_capture` in a seated state AND
  the lobby/spectating state).
- Behaviour unchanged (rank/King display + the toast events still work) — placement only. Studio in Edit.

## Relevant files
- `src/client/RankHud.client.luau` — the rank pill position + the toast holder position (move both left).
- `src/shared/GridConfig.luau` — any left-margin / layout tunable if useful.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client UI on the Client
  datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` desktop + phone aspect to confirm left placement + clear center. Leave Studio in Edit.)

## Constraints
- UI placement ONLY — don't change behaviour, the right-side scoreboard/lobby buttons, the spectator/lobby
  flow, cameras, or gameplay. Keep the shared UI style. Don't hide the rank pill behind the top-left CoreGui
  icons.
