# Ball escapes the building → rally never resets (contain the ball + guarantee recovery)

## Problem
The ball can **exit the building**, and when it does the **rally never resets** (the loop hangs — no
fault/rotation/re-serve). Two things to fix: (1) stop the ball escaping, and (2) make the rally ALWAYS
recover even if it somehow does.

## Likely cause (investigate + confirm)
- **Escape path:** the side windows were recently CUT OUT into real openings (`WallE`/`WallW` are now frames
  of panels around a gap + a glass pane — commit `46b755b`). The ball bounces off the gym walls (the early
  "extend bounce to gym walls + ceiling" work), but the new **window gap** likely isn't covered by the
  ball's wall collision, so the ball flies straight out the window into the outdoors. Reproduce: rally until
  a hit sends the ball through a side window. Also check the ceiling/gallery opening as a possible leak
  (ball peak is ~24, ceiling ~50, so unlikely — but verify).
- **Why the rally doesn't recover:** there's already an escape/non-settle WATCHDOG (`91e16ab`:
  `G.ballOutOfPlayVolume` + `G.ballSettleTimeout` force-resolve in the Heartbeat). It's NOT catching this
  case — find out why: e.g. the play volume is too large / shaped so a ball that left the GYM is still
  "in volume"; or the escaped ball settles to Rest outside (or falls forever) in a phase/`rallyArmed` state
  the watchdog guard misses (`rallyArmed and phase==Flight/Settling`); or it force-resolves but immediately
  re-escapes (a loop that looks like "never resets").

## Fix
### A. Contain the ball — it must NOT leave the gym
- Make the ball bounce off the FULL wall extent, including across the window openings: add an **invisible,
  ball-collidable barrier** spanning each window gap (kept `Transparency=1` / no cast shadow so light + the
  view still pass through the open window), in whatever set the ball's wall-bounce uses — OR make the
  ball↔gym-wall collision PLANE-based (reflect off the wall's plane over its full span) so a gap can't leak.
  Verify the ball bounces off the windowed walls exactly like the solid ones.
- Audit for ANY other gap the ball can leave through (window openings E/W, the ceiling/gallery opening, wall
  seams) and seal them to the BALL while keeping them visually open. Keep these ball-barriers OUT of the
  PLAYER collision where it'd matter and out of anything that changes ball FEEL on legit in-court bounces.

### B. Guarantee the rally always recovers (harden the watchdog)
- Ensure that if the ball EVER leaves the gym interior or fails to settle, the rally force-resolves + re-
  serves. Tighten `G.ballOutOfPlayVolume` to the GYM INTERIOR bounds (leaving the gym = out of volume →
  immediate force-resolve), and make the watchdog fire regardless of the exact phase/`rallyArmed` quirk
  (a ball that escaped should always be treated as OOB on the hitter → deferred rotation → re-serve).
- Confirm no re-escape loop: after a force-resolve the ball is re-served at C (inside), so with fix A it
  stays contained.

## Acceptance criteria
- The ball CANNOT leave the gym — hard-hit it toward/through a side window (and the corners/ceiling): it
  bounces back in, never exits into the outdoors. The windows still look open (light + view through them).
- If the ball ever does escape / fails to settle, the rally **force-resolves within the timeout** (fault →
  rotation → re-serve) — the loop NEVER hangs. Reproduce the original escape and confirm it now recovers.
- No regression to in-court ball feel (legit bounces off walls/floor/pipes unchanged), gameplay, the
  windows' look, or the gallery. Verified in Play via the MCP. Studio left in Edit.

## Relevant files
- `src/server/BallController.luau` — the ball↔surface collision (walls/ceiling); ensure full-wall coverage
  over the window gaps (plane-based or invisible barriers). Don't change the in-court strike/bounce feel.
- `src/server/MatchService.luau` — `buildGym` windowed walls (`WallE`/`WallW` panels + glass): add the
  invisible ball-collision barrier across each window opening if that's the chosen approach (build-once +
  one-time pass on the current place). Keep barriers out of the player/court collision sets.
- `src/server/NineSquareServer.server.luau` — the escape/non-settle WATCHDOG + `G.ballOutOfPlayVolume`
  usage: make it reliably catch a ball that left the gym (force-resolve → re-serve).
- `src/shared/GridConfig.luau` — `ballOutOfPlayVolume` bounds (tighten to gym interior), `ballSettleTimeout`,
  any barrier tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play, inject/hit the ball toward a window and
  confirm it bounces back + the loop keeps serving; also inject an escaped position and confirm the watchdog
  force-resolves. `screen_capture` works. Leave Studio in Edit.)

## Constraints
- Don't change the in-court ball physics/strike/bounce FEEL or the deterministic, server-authoritative model
  — this CONTAINS the ball (seal escape gaps) and HARDENS recovery. Keep the windows visually open (barriers
  invisible). Keep ball-barriers out of the player/court collision sets. Tunables in `GridConfig`.
