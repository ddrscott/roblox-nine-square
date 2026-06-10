# Defer rotation until the ball is at rest (keep the red fault panel at landing)

## Problem
Right now the grid rotates the instant the ball faults (first floor contact, `onLand`) — players snap
to new squares while the ball is still bouncing, which feels abrupt. Instead, **rotate only once the
ball comes to rest**. The **red floor panel still flashes at the landing** so everyone immediately sees
*who is out* while the ball settles; the actual rank shift + re-serve happens at rest.

## Current flow
`NineSquareServer`: `BallController.onLand(landed, struck)` → attribute the fault (PRD §6) + flash the
red marker (`MatchService.flashCell`) + **immediately** `RotationService.rotateOnFault(...)`. `onRest`
→ serve the next rally.

## Change
- **`onLand`:** attribute the fault per PRD §6 and **flash the red panel** to mark the out square — but
  DO NOT rotate. Record a **pending fault** (the rank to rotate) instead.
- **`onRest`:** if there is a pending fault, run `rotateOnFault(pendingRank)` (the shift + `placeAll`),
  then serve the next rally; clear the pending fault. So: ball lands → red panel shows who's out → ball
  finishes bouncing/settling → at rest, players rotate and the new King serves.
- Make sure the red flash stays readable through the land→rest window (extend the flash duration to
  cover it, or re-assert it, so the out square is clearly red until the rotation happens).

## Acceptance criteria
- On a fault, the faulting square **flashes red immediately** and the ball keeps bouncing; the rank
  rotation + re-serve happen only when the ball **comes to rest** (not at the landing).
- The red panel clearly marks the out player during the settle.
- No double-rotation; the loop continues correctly (dethrone still fires when the King is the out player).
  If the human bats the resting/dead ball before it settles, the pending fault still stands and rotation
  happens once it finally rests.
- Server-authoritative; verified in Play (watch: land → red flash + bounce → rest → rotate + serve).

## Relevant files
- `src/server/NineSquareServer.server.luau` — `onLand` (record pending fault + flash) / `onRest`
  (rotate + serve). This is the main change.
- `src/server/RotationService.luau` — `rotateOnFault` (called from `onRest` now).
- `src/server/MatchService.luau` — `flashCell` (extend/re-assert the red flash to cover the settle).
- `src/shared/GridConfig.luau` — a flash-duration tunable if you add one.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first;
  standalone `require` reads a stale module — use `script_read`/`get_console_output`; leave Studio in
  **Edit**).

## Constraints
- Don't change the fault ATTRIBUTION (PRD §6) or the rotation math — only WHEN the rotation runs.
- Keep the bot loop (`BotController`), the human physical volley, and the dethrone working. Tunables in
  `GridConfig`.
