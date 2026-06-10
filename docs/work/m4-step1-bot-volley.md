# M4 step 1: BotController — volley + aim + miss, wired into the loop (the core)

See the M4 design spec `docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md` (§3, §6 step 1).
This is the CORE of M4: make the bot-occupied squares actually **volley** incoming balls (with the simple
aim rule) and **miss** sometimes, so real rallies happen, faults rotate the grid, and the solo human can
climb. (Bodies/juice/difficulty tuning are step 2.)

## Context (already built, M3)
- `RotationService` owns occupancy: `byRank`, `placeAll`, `rotateOnFault`, `occupantAtCell(cell)`,
  `kingOccupant`, `isHumanKing`, `rankForCell`/`cellForRank`. Occupants have `isDummy` (the 8 non-humans).
- `NineSquareServer` runs the loop: King serve (human = M1 physical hover; dummy/bot King = auto-serve to a
  random outer square via `serveToTarget`), and `BallController.onLand` → fault attribution (PRD §6) →
  `rotateOnFault` → `onRest` re-serves the new King. The ball is `bc` (a `BallController`); launch with
  `bc:launch(point, v0)`.
- The HUMAN volleys via the physical swept collision in `BallController:step(dt, playerColliders)` — leave
  that untouched. Bots are server-resolved (no hit-sphere).

## Build
Add a server-side **`BotController`** (new `src/server/BotController.luau`, Studio
`ServerScriptService.NineSquare.BotController`) — or a focused function in `NineSquareServer` — run **each
Heartbeat after `bc:step`**:
1. Only when `bc.phase == "Flight"`. Compute the ball's current velocity (descending = vY < 0) and XZ cell
   (`GridConfig.cellAtPosition(ballXZ)`); the predicted landing cell is `bc.targetCell`.
2. If the ball is **descending through the contact window** — at/just below `frameHeight` (use a small
   band, e.g. `|ballY - frameHeight| < botContactBand` while descending) — AND its cell (or `bc.targetCell`)
   is occupied by a **bot** (`occupantAtCell(cell)` exists and `.isDummy`), resolve the bot's turn ONCE per
   descent (debounce: track the last resolved descent / arm on each new Flight launch):
   - **Aim:** `aimCell = (cell == "C") and <random outer cell> or "C"`. (Outer bot → center; King bot →
     random outer.)
   - **Hit (with probability `1 - GridConfig.botMissChance`):** `bc:launch(contactPoint, v0)` where
     `contactPoint` is the ball's current pos clamped to the cell's frame point and `v0` arcs toward
     `cellFramePoint(aimCell)` — reuse the M3 `serveToTarget` ballistic computation (horizontal toward the
     target + an upward pop, `serveArcApex`/a `botVolleySpeed` tunable). This sends the ball on toward the
     aim square; that square's occupant must then volley.
   - **Miss (probability `botMissChance`):** do nothing — let the ball fall to the floor in the bot's
     square → existing `onLand` floor-fault → `rotateOnFault` (already wired).
3. Don't resolve the **human's** square here (only `.isDummy` occupants).

New `GridConfig` tunables: `botMissChance` (start ~0.25 — tune in step 2), `botContactBand` (~3),
`botVolleySpeed` (or reuse the serve speed). Keep the King auto-serve from M3 as-is (it IS the King bot's
"hit toward the outside").

## Acceptance criteria
- A ball descending into a bot square is **volleyed** toward the aim (outer→C, King→outer) most of the
  time, producing a real rally (ball goes bot → center → bot …) instead of an instant fault.
- Bots **miss** ~`botMissChance` of the time → floor fault → the grid **rotates** (so rallies end and ranks
  move). The solo human can **climb** as bots ahead of them miss, and can reach **King**.
- One bot volley per descent (no double/again-and-again on the same drop). Server-authoritative,
  deterministic; the human's physical volley still works.
- Verified in a Play test: watch several rallies via console + screenshots — confirm multi-touch rallies,
  periodic bot misses → rotation, and the human's rank advancing over time.

## Relevant files
- `src/server/BotController.luau` (new) — the per-Heartbeat volley/miss resolver. (Or a function in
  `NineSquareServer`.)
- `src/server/NineSquareServer.server.luau` — call the bot resolver each Heartbeat after `bc:step`; reuse
  its `serveToTarget`/launch helper for the bot volley.
- `src/server/RotationService.luau` — `occupantAtCell`, `cellForRank`/`rankForCell` (exist).
- `src/server/BallController.luau` — reused (`bc:launch`, `bc.phase`, `bc.targetCell`, `currentVelocity`);
  do NOT change the physics/collision.
- `src/shared/GridConfig.luau` — `botMissChance`, `botContactBand`, `botVolleySpeed`.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; new
  ModuleScript via `multi_edit` create or chunked `script.Source`; standalone `require` reads a stale
  module — use `script_read`/`get_console_output`/screenshots; leave Studio in **Edit**).

## Constraints
- Server-authoritative; bots never touch the ball physically (no hit-sphere) — the volley is computed.
  Don't change `BallController`'s contact/collision/floor physics or the human's swept player collision.
- Single-touch per descent (debounce). Reuse the M3 serve/launch math. Tunables in `GridConfig`.
- Bodies / animation / difficulty tuning are STEP 2 — keep this step to the volley logic + loop wiring.
