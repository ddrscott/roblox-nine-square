# Lifelike bot movement — idle ready-stance + anticipatory ball tracking

## Problem
The bots look dead. Measured over 8 s of live play: **6 of 8 bot bodies had `totalTravel = 0.0`** —
only the one or two bots actually receiving the ball slid to intercept; every other bot stood frozen
in its square. Real players are never still — they bounce on their toes, shift weight, take small
ready steps, and track the ball with their body/feet even when it isn't coming to them. The bots
need that constant low-level life.

## Goal
Make all 8 bots **visibly move and look alive at all times**, not just the ball's current target —
while keeping the existing physical strike, the swept collision, fault/save attribution, and the
rotation placement unchanged.

## What to add (two layers)
1. **Idle ready-stance (every bot, every frame it isn't striking):** a continuous, cheap "alive"
   motion centered on the bot's home spot in its square:
   - subtle bob / weight-shift / sway (small vertical + lateral oscillation), and
   - occasional small **ready steps** — short shuffles to a new spot a stud or two from home and back,
     so feet actually move (not just a hover-bob). Vary phase per bot (use the rank index as a seed —
     `Math.random` is unavailable in deterministic contexts; derive an offset from the rank/cell) so
     they don't move in lockstep.
   - keep the bot **inside its own square** (clamp to the cell bounds minus a margin) and return toward
     home between shuffles so it never drifts out of position for the next rally.
2. **Anticipatory ball-tracking (all bots, when the ball is live):** every bot subtly **faces / leans /
   side-steps toward the ball's current XZ** as it travels — a small lean or a step in the ball's
   direction (a fraction of the idle step budget), so the whole grid reacts to the rally, not just the
   receiver. The actual interception slide (the receiver moving to its off-center launch point) is the
   existing behavior and stays as the dominant motion for the target bot.

## Constraints
- **Don't change the hit:** the physical strike (`strikeVelocity`), the swept collision, `botJumpVelocity`
  and the off-center aim are unchanged. This is body/idle motion only — when a bot becomes the receiver,
  the existing interception + jump takes over (idle motion yields to it cleanly, no snap/teleport).
- **Stay in-square & in-position:** idle wandering must keep each bot within its cell and settle back
  home so it's ready to receive; never let idle drift cause a missed intercept or push a bot over a pipe.
- **Cheap & server-authoritative:** the server already drives the bot bodies (`RotationService`
  `driveOccupant`/`restOccupant`, bodies tracking colliders). Drive the idle motion there / in
  `BotController` on the existing step; no per-bot Humanoid pathfinding storms. Keep it deterministic
  (no reliance on `Math.random`/`os.time` in the hot loop — seed phase from rank/cell).
- Don't disturb the rotation **placement** (bots must still land on their rank cell after a rotation) or
  the King/serve logic.
- Put magnitudes/speeds in `GridConfig` as tunables (e.g. `botIdleBobHeight`, `botIdleSwayRadius`,
  `botIdleStepInterval`, `botIdleStepDist`, `botTrackLeanFrac`).

## Acceptance criteria
- During live play, **all 8 bots move continuously** (re-run the 8 s travel probe: every bot should show
  clear non-zero `totalTravel`, not just the receiver) — bobbing/shifting + occasional ready steps.
- Bots **lean/step toward the ball** as a rally develops (the grid visibly reacts), then the targeted
  bot transitions cleanly into its existing intercept + jump.
- No bot drifts out of its square, misses intercepts it used to make, or breaks the strike, save/fault,
  or rotation. Verified in Play (watch a few rallies + a rotation; confirm placement still correct).

## Relevant files
- `src/server/RotationService.luau` — bot bodies + `driveOccupant`/`restOccupant`; home positions per rank.
- `src/server/BotController.luau` — per-step bot update; add idle/track motion when not the active receiver.
- `src/server/NineSquareServer.server.luau` — the Heartbeat step that drives bots (wire idle motion into it).
- `src/shared/GridConfig.luau` — new idle/track tunables; cell bounds helpers (`cellCenter`, `squareSize`).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a stale module — verify via `script_read`/`get_console_output`/the travel probe; leave
  Studio in **Edit**).
