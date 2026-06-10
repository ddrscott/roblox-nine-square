# Highlight the grid pipes of the last saved ball

## Problem
There's no indicator of where the last good **save** happened. Add a persistent highlight on the
overhead frame **pipes of the last-saved square**, so players can see who just made a save.

## Definition of a "save" (per the user)
A **save** = a ball comes into a player's square and they **knock it out of their square** (clear it
with a contact). It still counts **even if the ball ultimately goes out of bounds**. It is NOT:
- the **King's serve** (no ball came into the King's square — they initiate), or
- a **self-fault** (the ball returns to the same square it was struck from — they did not clear it).

So a save is credited to the occupant of the **struck square** whenever a (non-serve) contact sends the
ball **out of that square**, regardless of where it eventually lands.

## Build
- **Detect saves:**
  - **Bot volley** (`BotController`): a bot only volleys a ball descending INTO its square and aims it
    out (toward C, or the King toward an outer square) — so a successful bot volley is a save for that
    bot's cell. Credit `lastSavedCell = <bot's cell>` on the volley.
  - **Human volley** (`NineSquareServer` / where the human's contact is observed): when the human strikes
    a ball that was descending into the human's square (a return, not the human's own King serve) and it
    leaves that square → save for the human's cell.
  - **Exclude** the King serve and self-faults (ball returns to the struck cell — detectable at `onLand`
    via `struck == landed`; don't credit / clear the save for that case).
  - Simplest signal: credit the save to `struckCell` when the outgoing launch sends the ball out of
    `struckCell` (predicted landing cell `~= struckCell`, including OOB). The serve path doesn't go
    through this.
- **Highlight the saved square's pipes:** the overhead `Frame` beams are continuous lines (not per-cell),
  so add a separate **`SaveHighlight`** overlay — 4 glowing neon edge-segments outlining the saved cell's
  border at `frameHeight` (over that square), in a distinct colour (e.g. green/gold). On each save,
  **reposition + show** the overlay on `lastSavedCell`; it **persists** until the next save updates it.
  Keep it `CanCollide = false` and OUT of `BallController._surfaces` (it must not affect the ball).

## Acceptance criteria
- When a player or bot successfully volleys a ball **out of their square**, that square's overhead
  **pipes light up** and stay lit, moving to the newest save each time a new save happens.
- A volley that then goes **out of bounds** STILL highlights (counts as saved); the **King serve** and a
  **self-fault** do NOT highlight.
- Visual only — the loop, physics, faults, and rotation are unchanged.
- Verified in Play (watch a few rallies: the highlight tracks the last square that cleared the ball,
  including a save that goes OOB; serve/self-fault don't light it).

## Relevant files
- `src/server/BotController.luau` — credit a save on a bot volley.
- `src/server/NineSquareServer.server.luau` — credit a save on the human's volley; own/update the
  `SaveHighlight` overlay (set `lastSavedCell`).
- `src/server/MatchService.luau` — build the `SaveHighlight` edge-segment overlay (it builds the Frame /
  arena), exposing a `highlightSavedCell(cell)` it can reposition.
- `src/shared/GridConfig.luau` — highlight colour / segment size tunables.
- `src/server/RotationService.luau` — cell↔occupant if you need who saved.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first;
  standalone `require` reads a stale module — use `script_read`/`get_console_output`/screenshots; leave
  Studio in **Edit**).

## Constraints
- Visual only; do NOT change the contact/physics, fault attribution, serve, or rotation logic.
- The overlay must not collide with the ball (`CanCollide = false`, not under `NineSquare.Frame` /
  `_surfaces`). Server-authoritative is fine (the server knows saves). Tunables in `GridConfig`.
