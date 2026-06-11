# Improve bot accuracy — keep returns in-bounds (stop spraying it out)

## Problem
Bots are bad at keeping the ball in play. When a bot DOES connect, its return too often **flies out of
bounds** (lands outside the court / off the grid) instead of landing in a valid target square. The rally
dies on the bot's own hit. The user wants bots **as reliable as possible** — minimize intentional misses
and make genuine returns land in-bounds.

## Decisions (from the user)
- **Failure mode:** the issue is **hits flying OUT OF BOUNDS**, not whiffing. Focus on the AIM/LANDING of a
  connected hit so it reliably lands inside the intended target cell (clears the dividing pipe, stays in
  the court).
- **Difficulty:** make bots **as reliable as possible** — drive the **intentional miss rate to ~0** (or a
  very small value). Rotation will come mainly from the HUMAN's own faults plus the rare unavoidable miss,
  which is acceptable. (Don't worry that long bot↔bot rallies result — the human is always in the loop and
  faults to drive rotation.)

## What's likely going wrong (investigate + tune)
The bot aims by standing **off-center** (`botOffCenterFrac`) so the line-of-centres `n = unit(ball-center)`
points at its aim cell, then drives the collider up at `botJumpVelocity` with a horizontal lead
(`botStandoff`) — the strike is `strikeVelocity` (passive rebound + `hitGain*approach` along `n`). Two
overshoot sources:
- **Too much horizontal/flat power:** `botStandoff` adds horizontal travel to the collider velocity → the
  comment notes "higher = flatter/longer → more OOB." A flat, fast strike overshoots the target cell and
  sails out. (`botJumpVelocity` was just lowered to 20 to fix the CEILING — keep that; the OOB is the
  horizontal/aim component, not vertical. Don't undo the ceiling fix.)
- **Aiming at too far a point:** if the bot aims at the far edge of the target cell (or the geometry sends
  it past), small errors land it OOB. Aim at the target cell's CENTER with an in-bounds margin so the
  landing has slack to the court edge.

## Fix (deterministic, server-authoritative; do NOT change the strike formula/collision/physics)
1. **Make `botMissChance` ~0** (e.g. `0.02`, or `0` — keep the tunable so we can re-add difficulty later).
   Keep the miss mechanic in code, just set the rate near zero.
2. **Land it in the target cell reliably.** The bot already picks an aim cell (outer→`C`, King→a random
   outer cell). Tighten so the predicted landing falls INSIDE that cell with margin to the court boundary:
   - Aim at the cell CENTER (or a point pulled slightly toward court-center), not the far edge.
   - Reduce overshoot: lower `botStandoff` (steeper, shorter strike that lands nearer / in the cell) and/or
     adjust `botOffCenterFrac` so the resolved direction points at the aim-cell center. Tune so a clean bot
     return clears the pipe (`pipeClearHeight`) AND lands within the court (`|x|,|z| <= 1.5*squareSize`).
   - Optional (better): PREDICT the landing point from the resolved strike velocity (ballistic: solve where
     the arc returns to the contact plane / floor) and, if it'd be OOB, steepen the strike (trade horizontal
     for a tighter arc) so it lands in-bounds. A small deterministic correction loop, no `Math.random`.
3. Keep all magnitudes as **`GridConfig` tunables**.

## Acceptance criteria
- Over many consecutive bot returns (measure in Play), the **out-of-bounds rate drops sharply** — bot hits
  reliably land inside a valid square (clear the pipe, stay in the court). Quantify before/after: e.g. count
  bot strikes vs. OOB faults attributed to a bot over ~30 returns; OOB on bot hits should become rare.
- Bots almost never miss intentionally (`botMissChance` ≈ 0); rallies sustain and the ball stays in play
  until the human (or a genuine edge-case) faults.
- The CEILING fix holds (ball peak stays well under 49.5; `botJumpVelocity` stays ~20) and the strike
  physics, swept collision, aim mechanic, save/fault attribution, and rotation are unchanged — this is
  TUNING of the bot's aim/landing + miss rate, not a physics change.
- Verified in Play: watch several rallies — bot returns land in-grid, the ball stays in, rotation still
  occurs when the human faults; no console errors.

## Relevant files
- `src/server/BotController.luau` — the aim/landing logic: aim-cell selection, off-center stand, standoff,
  jump drive, and `botMissChance` gate. Tighten the landing here (aim at cell center + in-bounds margin;
  optional ballistic landing prediction/correction).
- `src/shared/GridConfig.luau` — `botMissChance` (→ ~0), `botStandoff`, `botOffCenterFrac`, `botJumpVelocity`
  (keep ~20), and any new aim-margin / landing-target tunables; `squareSize`/`pipeClearHeight`/`cellCenter`
  for the in-bounds + pipe-clear checks.
- `src/server/BallController.luau` — reused only (the strike/landing model the prediction would mirror); do
  NOT change the physics.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a STALE module — verify via `script_read`/`get_console_output`/a server probe that counts
  bot strikes vs OOB; leave Studio in **Edit**).

## Constraints
- TUNING + aim logic only — don't change the strike formula, swept collision, `botJumpVelocity` ceiling fix,
  save/fault attribution, the rotation, or the R15 rigs. Keep it deterministic + server-authoritative.
- Keep the `botMissChance` mechanic in place (just near zero) so difficulty can be re-tuned later.
