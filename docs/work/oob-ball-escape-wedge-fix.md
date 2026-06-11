# Fix the OOB ball-escape wedge (ball rockets to huge Y, rotation never resolves)

## Problem (would freeze a live game)
On certain hits (observed from an outer-bot OOB strike, and tied to the documented pipe-collision known
issue), the ball gets a runaway velocity and **rockets to a huge Y (~13,072 studs observed)**. Because the
fault rotation is **deferred until the ball is at rest** (`bc.onRest`), and a ball flung that high never
settles in any reasonable time, **`onRest` never fires → the deferred rotation never applies → the game
WEDGES** (no rotation, no re-serve, rally loop stuck). This must not happen during the friends playtest.

## Root cause to investigate (fix if found) + guaranteed safety net
- **Cause:** a degenerate collision/reflection produces an absurd ball velocity — likely a pipe/corner/
  overlapping-surface case (the ball stuck inside a surface re-reflecting, a near-zero/NaN contact normal,
  or repeated reflections in one step). Investigate `BallController` collision/reflection + the frame-pipe
  surfaces; harden the degenerate case (guard zero/NaN normals; prevent the ball getting trapped inside a
  surface and re-reflecting to runaway speed).
- **Guaranteed no-wedge (do this regardless of whether the exact cause is pinned down):**
  1. **Clamp the ball speed.** After any launch / strike / reflection, clamp the ball's velocity magnitude
     to a sane max (`GridConfig.ballMaxSpeed`) so no interaction can send it to Y~13k. Pick a max well above
     normal play (normal rally outgoing is ~55–130 studs/s; cap ~250–300 so legit play is untouched but a
     runaway is caught). Also guard against NaN/inf velocity (reset to a safe state if detected).
  2. **Play-volume + settle watchdog (the real wedge fix).** If the ball leaves a sane play volume (Y above
     gym ceiling + margin, Y below the floor, or |XZ| beyond the court + margin), OR a fault is pending and
     the ball has not reached rest within a timeout (`GridConfig.ballSettleTimeout`, e.g. ~6–8s), then
     **force-resolve:** treat it as the appropriate fault (attribute to the hitter / `ownerCell` exactly as
     the normal OOB path does), **apply the deferred rotation, and re-serve.** The rally loop must always
     recover — never wait forever on an `onRest` that won't come.

## Acceptance criteria
- Reproduce the escape (or inject a runaway/huge ball velocity and an out-of-volume position via a
  Server-side test): the ball speed is clamped to `ballMaxSpeed` (no Y~13k flight), AND/OR the watchdog
  detects the escape / non-settle and **forces a fault → deferred rotation → re-serve within the timeout**.
  The game CONTINUES — no wedge.
- A normal rally is completely unaffected: the clamp never bites in legit play, the watchdog never
  false-triggers (its volume + timeout are generous), faults/saves/rotation/serve all behave as before.
- Deterministic + server-authoritative preserved. Verified via the MCP. Studio left in Edit.

## Relevant files
- `src/server/BallController.luau` — clamp the ball velocity to `ballMaxSpeed` after launch/strike/reflection
  + NaN/inf guard; harden the degenerate pipe/corner/overlap reflection; expose what the watchdog needs
  (e.g. current speed / out-of-volume / a "stuck" signal), or handle the volume check here and fire a
  force-fault callback.
- `src/server/NineSquareServer.server.luau` — the watchdog: track the pending-fault + ball state each
  Heartbeat; if out-of-volume or not-at-rest-past-timeout, force the OOB fault attribution (hitter/
  `ownerCell` like the normal path) → apply the deferred rotation → re-serve. Don't double-resolve.
- `src/shared/GridConfig.luau` — `ballMaxSpeed`, play-volume margins (ceiling/floor/XZ), `ballSettleTimeout`.
- `README.md` — update the "Known issues" pipe-collision note (now mitigated: clamp + watchdog guarantee no
  wedge even if a degenerate reflection occurs).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output`; inject a runaway velocity / OOB position on the
  Server and assert clamp + watchdog recovery + a clean re-serve; confirm a normal rally is unaffected.
  screen_capture has been flaky — rely on log/numeric assertions. Leave Studio in Edit.)

## Constraints
- Don't change normal ball physics feel — the clamp/watchdog are SAFETY guards that only trigger on the
  runaway/escape (generous thresholds). Keep fault attribution consistent with the existing over-pipe
  `ownerCell` model. Deterministic + server-authoritative. The game must be impossible to wedge from a
  ball escape.
