# Rework player contact as a proper moving-sphere collision (kill the clip/pull-down bug)

## Problem (root cause)
The player contact is NOT a real collision — it's a per-frame proximity trigger with a TIME debounce:
`NineSquareServer`'s Heartbeat calls `HitResolver.checkContact(ball)` (is the ball inside the player's
hit-sphere?) gated by a `hitCooldown` timer, then calls `BallController:strike`. Two failures:
1. **Multi-hit:** the sphere stays overlapping for many frames; once the time cooldown lapses it fires
   AGAIN during the same encounter.
2. **Pull-down:** `:strike`'s passive term `vBall - (1+ballRestitution)*(vBall·n)*n` resolves regardless
   of whether the two are actually approaching. So when a player jumps, strikes the ball up, then
   DESCENDS back onto the still-rising ball, the contact re-fires and reverses the ball's *upward*
   velocity → it gets driven DOWN. Feels broken/disconnected.

The pipe/wall/floor collisions feel great because they ARE proper collisions: resolve only on
penetration, reposition the ball to the surface, reflect once (`BallController:_collide` / the floor
ground-plane in `:step`). **Make the player contact work the same way.**

## Approach (decided): treat the player hit-sphere as a MOVING sphere collider
Fold the player contact into the ball's collision step, alongside the pipes/walls, as a sphere-vs-
moving-sphere collision. Keep the deterministic, server-authoritative, anchored ball (do NOT switch to
Roblox engine physics — that's a separate M5-scale change).

Requirements for the resolution (per player hit-sphere: centre = `HRP + hitZoneYOffset`, radius =
`hitZoneRadius`, velocity = `HRP.AssemblyLinearVelocity`):
- **Resolve only when penetrating AND approaching.** Penetration: `|ball - centre| < hitZoneRadius +
  ballRadius`. Approaching: the relative velocity along the contact normal is closing,
  `(vBall - vPlayer):Dot(n) < 0` where `n = unit(ball - centre)`. If they're separating (e.g. a
  descending player over a rising ball), DO NOT resolve — this is what kills the pull-down bug.
- **Reposition the ball to the sphere surface** on contact: `ball = centre + n*(hitZoneRadius +
  ballRadius + eps)`. This pushes the ball out so the same approach can't re-trigger next frame →
  exactly one hit per approach (same trick `_collide` uses for the pipes). The per-frame penetration +
  reposition makes the time `hitCooldown` largely unnecessary (keep a tiny one only as a safety, or drop it).
- **Impart the player's velocity (moving-collider bounce).** Reuse the existing velocity-proportional
  model so feel is preserved: the ball's own normal velocity rebounds with `ballRestitution` (<=1, a
  still player adds no energy) and the player's approach speed adds `hitGain * into` along `n`, with the
  `hitMinPop` floor on an intentional (approaching, above `strikeMoveThreshold`) strike. Keep the
  upward `minLift` bias on `n` so a clean bump arcs up.
- **Serving:** the ball hovers (phase "Live"); `:step` currently just pins it. The player-sphere
  collision must also run in Live so jumping into the hovering ball serves it (Live → Flight) via the
  same collision. (A rising player imparts upward velocity; a dead-apex contact stays weak, as before.)
- Works for the dead-ball batting too (Settling/Rest): a moving player re-collides and bats it; a still
  one doesn't — falls out naturally from the approaching-only rule.

## Suggested structure (keep clean contracts)
- Keep `HitResolver` as the geometry/state provider: e.g. `HitResolver.playerColliders()` returns a list
  of `{ center: Vector3, radius: number, vel: Vector3, player: Player }` for all players with a character.
- Have `BallController:step` collide the ball against those moving spheres in the same place it collides
  with `_collide` (pipes/walls) and the floor. Pass the colliders in (e.g. `bc:step(playerColliders)` set
  each Heartbeat by `NineSquareServer`) so `BallController` stays decoupled from the Players service.
- Remove the old Heartbeat `checkContact` → `:strike` proximity path (and the time-cooldown re-fire).
  The `onLand`/`onRest` events and pipe/floor collision stay exactly as they are.
- The `HitSphereView` debug orb must keep matching the real collider (same centre/radius) — it already
  reads `hitZoneRadius`/`hitZoneYOffset`, so leave it.

## Acceptance criteria
- A jump into the ball strikes it **exactly once per approach**; the same jump cannot re-hit it (ball
  is repositioned out of the sphere).
- A **descending player never pulls a rising/receding ball down** — contact resolves only when the ball
  and player sphere are approaching. (This is the headline bug; verify explicitly.)
- The strike still imparts the player's velocity (faster approach = harder hit); a still player adds no
  energy; serving by jumping into the hovering ball still works.
- The player contact feels **consistent with the pipe bounce** (resolve-on-penetration + reposition +
  reflect), not a disconnected trigger.
- Deterministic + server-authoritative preserved; pipe/wall/floor collision behaviour unchanged.
- Verified in a Play test (jump into the ball repeatedly, including descending onto it — confirm a
  single clean hit and no downward pull) plus a deterministic probe of the resolution.

## Relevant files
- `src/server/BallController.luau` — `:step`, `_collide`/`_surfaces`, `currentVelocity`; add the
  player-sphere (moving collider) resolution here. Reuse `:strike`'s math or inline equivalent.
- `src/server/HitResolver.luau` — provide the player colliders (centre/radius/vel) instead of
  one-shot `checkContact`.
- `src/server/NineSquareServer.server.luau` — gather colliders + pass to `:step`; remove the old
  proximity trigger.
- `src/shared/GridConfig.luau` — reuse `hitZoneRadius`, `hitZoneYOffset`, `ballRestitution`, `hitGain`,
  `strikeMoveThreshold`, `hitMinPop`, `minLift`, `hitCooldown`. Add a tunable only if needed.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done). Whole-file rewrites deploy via chunked `script.Source` in Edit.

## Constraints
- Keep the deterministic, server-authoritative, anchored ball — do NOT move it onto Roblox engine
  physics. Do NOT touch the pipe/wall/floor collision (it works well).
- Keep the clean BallController contracts (physics + events; game owns rules). Tunables in `GridConfig`.
