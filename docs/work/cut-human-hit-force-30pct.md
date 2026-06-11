# Cut the human player's ball-impact force 30% (too easy to launch OOB)

## Problem
A human player's strike sends the ball out of bounds too easily. Cut the **human** player's ball-impact
force by **~30%** so hard hits stay in play.

## Implementation (HUMAN ONLY — don't nerf the bots)
The strike is velocity-proportional: `strikeVelocity(vBall, n, playerVel)` = passive rebound (the ball's own
incoming reflected) + active power `hitGain * (playerVel·n)` along `n`, floored by `hitMinPop` for an
intentional strike. The OOB launches come from the ACTIVE term on a hard human hit.

- **Do NOT change the shared `hitGain` / `hitMinPop`** — those also drive the BOTS, which are already
  tuned (their `botJumpVelocity` + the in-bounds landing forecast keep them in-court). Changing the shared
  formula would re-break bot accuracy.
- Instead add `GridConfig.humanHitForceMult = 0.7` and apply it to the HUMAN collider's velocity (the `vel`
  fed into `bc:step`) in `HitResolver.playerColliders()` — i.e. scale the seated human's contributed
  velocity by 0.7 **after** the M5.4 anti-cheat validation/clamp. That cuts `playerVel·n` (the approach
  speed) ~30%, so the active `hitGain*approach` term drops ~30% → ~30% less outgoing force on a human
  strike. The passive rebound and the `hitMinPop` floor stay, so gentle returns still pop enough to stay in
  play; only the hard, OOB-causing hits get tamed.
- **Bots are unaffected:** they feed their OWN colliders via `bots:update(dt)` in `NineSquareServer`
  (not through `HitResolver`), so this human-only multiplier doesn't touch them.

## Acceptance criteria
- A human's hard hit launches the ball OOB **noticeably less** — the human's active strike outgoing is ~30%
  lower than before (verify: a given human approach produces ~0.7× the active force / the ball lands
  in-court where it used to sail out). Gentle returns still clear the pipe + stay alive (the floor holds).
- BOTS are unchanged — their accuracy / in-bounds behaviour is identical (don't touch `hitGain`/`hitMinPop`/
  `botJumpVelocity` or the bot forecast).
- Deterministic + server-authoritative; the strike formula + ball physics are otherwise unchanged (this is
  an input scaling on the human's contributed velocity). Verified in Play via the MCP. Studio left in Edit.

## Relevant files
- `src/server/HitResolver.luau` — `playerColliders()`: multiply each seated human collider's `vel` by
  `G.humanHitForceMult` (after the existing M5.4 clamp/validation).
- `src/shared/GridConfig.luau` — `humanHitForceMult = 0.7` (tunable; 1.0 = no change).
- `src/server/BallController.luau` — reused only (no physics change); the strike reads the (now-scaled)
  human collider velocity.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play, compare a human strike's outgoing/landing
  before vs after, or assert the human collider vel fed to bc:step is 0.7× the validated input. Leave Studio
  in Edit.)

## Constraints
- HUMAN strike force only (~30% cut) — do NOT change the shared `hitGain`/`hitMinPop` or anything bot-side
  (bots stay tuned). Keep the passive rebound + `hitMinPop` floor so returns still stay alive. Deterministic
  + server-authoritative; tunable in `GridConfig`. Don't break the M5.4 anti-cheat clamp (apply the mult
  after it).
