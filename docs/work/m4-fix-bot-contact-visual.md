# Make bot contact read — leap to the ball on a volley (not a robotic floor hop)

## Problem
Bots don't look like they're making contact with the ball, and the motion reads fake/robotic. Cause:
when `BotController` resolves a bot volley it calls `RotationService.hopOccupant(id)`, which pivots the
bot body up a small `botHopHeight` **in place on the floor** — but the ball is volleyed (`bc:launch`)
from the contact point at **~`frameHeight` (≈11 studs up)** over the square. The bot never rises to the
ball, so there's an obvious gap (ball way up, bot bobbing on the floor) and the rigid linear pivot looks
robotic.

## Fix
Make the bot **leap up to the ball and strike it** on a volley, timed with the launch:
1. **Pass the contact point.** In `BotController`, when it resolves a hit it already knows the ball's
   contact position (the ball's current pos at the contact window, ~frameHeight at the ball's XZ). Pass
   that to the hop: `rotation:hopOccupant(id, contactPos)`.
2. **Leap to the ball.** `hopOccupant` should move the bot body from its stand position **up toward
   `contactPos`** — reaching roughly the ball's height (~`frameHeight`) and leaning toward the ball's XZ
   within the square — at the moment of the volley, then arc back down to its square. So the body visibly
   meets the ball where it's struck.
3. **Natural, not robotic.** Use an **eased arc** (quick ease-out up to the apex, a brief hold at the
   strike, ease-in back down) rather than a constant-speed pivot. Add a **reach** — raise/extend an arm
   (or lean the torso) toward the ball at the apex so it reads as a strike, not just a jump. A touch of
   anticipation/overshoot or squash-stretch helps it feel alive.
4. **Sync to the strike.** The apex (the bot meeting the ball) should coincide with the volley `bc:launch`
   — since both fire in the same resolve, drive the leap so the bot is at/near the contact point on that
   frame (a very short pre-wind is fine if it still reads as one motion).
5. Optional, if cheap: swap the blocky stylised body (cube head + stick arms) for a **real Roblox
   character rig** (clone the default R15/R6 dummy or a `HumanoidDescription` NPC) for a less-robotic
   look — leverage Roblox's avatar system. Prioritise the leap-to-ball + reach first; the body upgrade is
   secondary and can be skipped if it gets heavy.

Add `GridConfig` tunables for the leap (e.g. reach fraction toward the ball, up/hold/down times) and tune
so it looks like a believable strike.

## Acceptance criteria
- On a bot volley, the bot **visibly leaps up and meets the ball** at the contact point (~frame height,
  toward the ball's XZ) and appears to strike it — not a small hop on the floor with the ball detached.
- The motion reads as a **natural strike** (eased arc + reach), not a rigid robotic pivot.
- The bot returns cleanly to its square afterward; the leap is synced to the volley (apex ≈ the launch).
- Verified in Play: a screenshot of a bot mid-volley showing the body up near the ball (or, if timing a
  capture is hard, confirm via the leap target reaching ~`frameHeight` at the ball's XZ) + the loop still
  runs (rallies, misses → rotation) unaffected.

## Relevant files
- `src/server/BotController.luau` — pass the contact point into the hop on a hit.
- `src/server/RotationService.luau` — rework `hopOccupant` into a leap-to-contact-point + reach (it owns
  the bot bodies / `hopOccupant`).
- `src/shared/GridConfig.luau` — leap tunables (reuse/extend the `botHop*` ones).
- (optional) wherever bot bodies are built, if upgrading to a real rig.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a stale module — use `script_read`/`get_console_output`/screenshots; leave Studio in
  **Edit**).

## Constraints
- Server-driven (bots are server-side); keep bot bodies `CanCollide = false` and OUT of
  `BallController._surfaces` (the hit stays server-resolved). Do NOT change the volley logic/physics,
  the aim rule, the miss rate, or the rotation loop — this is a VISUAL fix only.
- Tunables in `GridConfig`. Don't break the human's physical volley, the rank HUD, camera, or no-trip fix.
