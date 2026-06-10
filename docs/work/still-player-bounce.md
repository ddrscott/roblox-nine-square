# Fix still-player bounce: a motionless player must not add ball energy

## Problem
When the ball lands on a **non-moving** player it still gains bounce velocity (flies up faster than it
came down). A stationary player should behave like a surface — the ball rebounds with restitution and
**never gains energy**. Only a player *moving into* the ball should add power.

## Root cause
`BallController:strike` uses a single super-elastic restitution and an unconditional floor:
```lua
local closing = (vBall - playerVel):Dot(n)
local vOut = vBall - (1 + G.hitRestitution) * closing * n   -- hitRestitution = 1.5  (>1 !)
local along = vOut:Dot(n)
if along < G.hitMinPop then vOut = vOut + (G.hitMinPop - along) * n end  -- always applied
```
Two bugs for a still player (`playerVel = 0`):
1. `hitRestitution = 1.5 > 1` makes the bounce **super-elastic** — the ball's own velocity is
   reflected and amplified (e.g. down-40 → up-60), so energy is gained from nothing.
2. `hitMinPop` (55) is applied unconditionally, so even a slow/passive contact is boosted to ≥55.

## The fix (separate passive bounce from active power)
Split the impulse so the ball's own rebound uses a restitution ≤ 1 (no gain), and the player's
*motion* is what adds power:
```lua
-- n = unit(ball - playerCentre); vBall = self:currentVelocity()
local ballPart = vBall - (1 + G.ballRestitution) * (vBall:Dot(n)) * n   -- ballRestitution <= 1: no passive gain
local into = math.max(0, playerVel:Dot(n))                              -- player's approach speed toward the ball
local vOut = ballPart + G.hitGain * into * n                            -- active power, proportional to motion
if into > G.strikeMoveThreshold then                                    -- only an ACTIVE strike gets the guaranteed pop
    local along = vOut:Dot(n)
    if along < G.hitMinPop then vOut = vOut + (G.hitMinPop - along) * n end
end
self:launch(point, vOut)
```
- A **still** player → `into = 0`, no min-pop → `vOut = vBall` reflected with `ballRestitution ≤ 1`
  → bounces up *slower* than it fell. No free energy.
- A **moving** player → adds `hitGain * approachSpeed` along the normal (proportional to their velocity,
  as designed), and the min-pop floor guarantees a usable pop on intentional strikes.

Suggested tunables (in `GridConfig`, replacing the single `hitRestitution`):
- `ballRestitution = 0.6` (passive bounce; ≤ 1 so the ball never gains energy off a still player)
- `hitGain = 2.5` (player-velocity power; tune so a rising jump-serve pops the ball returnably)
- `strikeMoveThreshold = 8` (min approach speed to count as an active strike → gets the floor)
- keep `hitMinPop` (now applies to active strikes only)

## Serve consequence (intended, per the user)
Serving now needs **upward motion** — you pop the ball by hitting it on the rise, not at the dead apex
(where your velocity is ~0). Verify a rising jump still serves/volleys returnably; a perfectly-timed
dead-apex contact giving little is acceptable. If serving becomes impossible, tune `hitGain` up or
nudge `frameHeight` down slightly so contact lands while still rising — but keep the still-player
behaviour (no energy gain) intact.

## Acceptance criteria
- A ball dropped onto a **perfectly still** player rebounds with outgoing speed **≤ incoming speed**
  (never gains). Verify deterministically: e.g. `strike` with `vBall=(0,-40,0)`, `playerVel=0`
  → `vOut.Y` is upward but **≤ 40**.
- A player moving into the ball still imparts a velocity-proportional, harder hit (faster → harder).
- Serving/volleying still works by hitting on the rise — confirmed live.
- Tunables live in `GridConfig`; change deployed to Studio and verified.

## Relevant files
- `src/server/BallController.luau` — `:strike` (and `currentVelocity`).
- `src/shared/GridConfig.luau` — add `ballRestitution`, `hitGain`, `strikeMoveThreshold`; keep
  `hitMinPop`; remove/repurpose `hitRestitution`.
- `src/server/HitResolver.luau` — unchanged (still returns normal + playerVel).
- Deploy via the `robloxstudio` MCP and verify in Play (mode flip-flops — check `get_studio_state`
  first; leave Studio in Edit when done).

## Constraints
- Don't break dead-ball batting (Settling/Rest still hittable): a moving player can still bat a dead
  ball; a still player just lets it bounce off naturally. Keep the clean BallController contracts.
- Keep all tunables in `GridConfig`.
