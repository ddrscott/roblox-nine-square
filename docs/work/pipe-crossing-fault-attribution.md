# Fault attribution by over-the-pipe crossings (fix wrong knock-outs)

## Problem (severe)
A player is wrongly knocked out when the ball is **deflected low into a neighboring square without going
over the pipes**. Fault attribution currently uses the ball's **floor-landing XZ cell**
(`cellAtPosition(landing)`), so if a hit slides the ball *under* the dividing pipe into a neighbor's
column and it lands there, the **neighbor** gets the floor fault — even though the ball never legally
entered their square (it never came down into their square from over the pipe).

Real 9-square rule: a ball only **legally enters** a square by travelling **up and over the dividing
pipe** and descending into it. A ball that crosses a square boundary **below** the pipe (a low deflect)
has NOT entered that square — it's still the **hitter's** responsibility (they failed to clear it over
the pipe). We must **track pipe entry/exit (over-pipe boundary crossings)** to decide who owns the ball
and therefore who gets knocked out.

## Fix: track the ball's "owner cell" via over-pipe crossings
- The ball has an **`ownerCell`** — the square it legally belongs to (whose occupant owes the next hit).
- On a **launch/hit**, reset `ownerCell = struckCell` (the hitter owns it until it legally leaves).
- Each step, detect a **cell-boundary crossing** (the ball's XZ `cellAtPosition` changes). At the crossing
  check the ball's height:
  - **Over the pipe** (ball center Y above ~`frameHeight + ballRadius`, i.e. it cleared the pipe top): a
    legal transfer → set `ownerCell = the new cell`.
  - **Under the pipe** (crossing below that height): an illegal low deflection → **do NOT change
    `ownerCell`** (the ball is still owned by the previous square even though its XZ moved).
- Expose `ownerCell` to the fault path (e.g. extend `BallController.onLand(landedCell, struckCell,
  ownerCell)` or read `self.ownerCell`).

## Fault attribution (use `ownerCell`, not the raw landing XZ) — PRD §6, corrected
On a floor landing:
- **`landedCell == nil` (out of bounds)** → fault the **hitter** (`struckCell`). (OOB is always on the hitter.)
- **`ownerCell == struckCell`** (the ball never legally left the hitter's square — it landed back in it OR
  deflected low into a neighbor) → **self/clear fault on the hitter** (`struckCell`). *This is the bug fix:
  the neighbor is NOT knocked out.*
- **`ownerCell ~= struckCell`** (the ball legally went over a pipe into `ownerCell`) → **floor fault on
  `ownerCell`'s occupant** (they failed to return a legally-delivered ball).

## Align the "save" highlight with this
A **save** = the hitter legally **cleared their square over a pipe** (`ownerCell` left `struckCell`). A low
deflection is NOT a save. Update the save detection (from the last task) to credit a save only when the
ball legally clears the struck square over the pipe (use the same over-pipe `ownerCell` signal), so the
pipe highlight and the fault logic agree.

## Acceptance criteria
- A ball deflected **low** into a neighbor's square (crossing the boundary below the pipe) faults the
  **hitter**, NOT the neighbor — the neighbor is no longer wrongly knocked out.
- A ball legally sent **over a pipe** into another square that the occupant **fails to return** faults
  **that occupant** (unchanged correct behaviour). OOB still faults the hitter.
- The save-pipe highlight only lights when the ball legally clears the struck square over the pipe.
- Deterministic, server-authoritative; verified in Play (reproduce: hit the ball low so it deflects under
  a pipe into a neighbor → confirm the HITTER faults, not the neighbor; and a normal over-pipe rally still
  faults the failing occupant).

## Relevant files
- `src/server/BallController.luau` — track `ownerCell` via over-pipe boundary crossings in `step` (reset
  on `launch`); pass it to `onLand`. (Physics/collision unchanged — this is tracking only.)
- `src/server/NineSquareServer.server.luau` — rewrite the `onLand` fault attribution to use `ownerCell`
  (self/clear fault on the hitter when `ownerCell == struckCell`).
- `src/server/BotController.luau` / save-credit logic — align the "save" to the over-pipe clear.
- `src/shared/GridConfig.luau` — an over-pipe height threshold tunable (e.g. `pipeClearHeight` ≈
  `frameHeight + ballRadius`).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a stale module — use `script_read`/`get_console_output`/screenshots; leave Studio in
  **Edit**).

## Constraints
- Don't change the ball physics/contact/collision or the rotation timing (rotation still applies at rest);
  this changes WHO is attributed the fault. Tunables in `GridConfig`.
- Keep it server-authoritative and deterministic. Make sure the bot loop, human volley, and dethrone all
  still work with the corrected attribution.
