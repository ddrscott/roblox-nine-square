# Bots hit physically — move feet to aim off-center + jump into the ball (no artificial launch)

## Problem
Bots currently "artificially" hit the ball: `BotController` resolves the volley by calling `bc:launch`
with a computed velocity (server-resolved). It looks/feels fake, and the aim isn't produced the way a
real hit is. In this game the **only way to aim is to hit the ball OFF-CENTER** — the outgoing direction
is the line of centres `unit(ball - hitSphereCenter)`. So **bots should move their feet** to position
their hit-sphere off-center relative to the ball and **jump into it**, letting the **same physical
collision** the human uses (`BallController:step` → `strikeVelocity`) resolve the hit. The aim then comes
from *where* the bot stands, and the force from the bot's jump velocity — exactly like a player.

## Approach: give bots a real hit-sphere collider, driven by the server
- Each bot gets a **hit-sphere collider** like the human's: `{ center, radius = hitZoneRadius, vel }`.
  Combine bot colliders with the human colliders in the list passed to `bc:step(dt, colliders)` (see
  `HitResolver.playerColliders`) so the existing physical, swept, velocity-proportional collision
  resolves bot hits too. **Remove the artificial `bc:launch` volley** from `BotController`.
- **Bot AI per incoming ball** (when the ball is in Flight descending toward a bot's square = its
  `targetCell`):
  1. Predict the **contact point** — where the ball crosses the contact window (~`frameHeight`) over the
     square (from the ball's arc, or its descent path).
  2. Compute the **aim** target cell: outer bot → `C`; King bot (`C`) → a random outer cell. `aimDir` =
     direction from the contact point toward the aim cell's frame point (flattened).
  3. **Position off-center:** to send the ball toward the aim, the bot's hit-sphere centre must be on the
     **far side of the ball from the aim** so `n = unit(ball - centre)` points toward the aim. Target
     centre ≈ `contactPoint - aimDir * offset` (offset a fraction of `hitZoneRadius + ballRadius`, tuned
     so contact is clearly off-centre but still overlaps).
  4. **Move the feet:** drive the bot body + its hit-sphere **laterally** toward that XZ across the descent
     (visible repositioning — Humanoid `MoveTo` or a server-driven slide, your call), then **jump**: move
     the hit-sphere **up to the contact point** at the contact window with an upward + lateral **jump
     velocity** (`botJumpVelocity`). The collider's `vel` = its actual per-frame velocity, so the
     velocity-proportional strike transfers that jump force to the ball.
  5. The physical collision (penetrate + approach) then resolves the hit: the ball deflects along `n`
     (toward the aim) with force from the bot's jump velocity. No `bc:launch`.
- **Miss:** with `botMissChance`, the bot mis-positions / under-jumps / mistimes so it doesn't make contact
  → the ball falls → existing `onLand` floor fault → rotation (unchanged).
- The bot **body** visually moves + jumps (the earlier leap-to-ball becomes the *real* driven jump — keep
  the body synced to the collider so it reads as the bot striking the ball).

## Notes / what stays
- Server-authoritative: the server drives the bot's hit-sphere + body deterministically.
- The over-pipe `ownerCell` / `onClear` save logic still works (a real bot hit sends the ball over the
  pipe → ownership transfers → save). The King serve can stay as-is (auto-serve) OR, nicer, become a
  physical off-center serve too — but the volley is the priority; keep the serve working.
- The human hit is UNCHANGED (same collision); bots now share that mechanic.

## Acceptance criteria
- Bots **visibly move their feet** to position relative to the incoming ball and **jump into it**; the hit
  is produced by the **real collision** (no `bc:launch` artificial volley).
- **Aim emerges from off-center contact:** an outer bot stands to deflect the ball toward `C`; the King
  bot toward an outer square — the ball's direction follows the contact geometry + the bot's jump.
- Bots still miss at ~`botMissChance` → faults → rotation; the human and bots hit via the same mechanic.
- Verified in Play: bots reposition + jump to the ball, the ball flies via the physical strike, rallies +
  misses + rotation + the save/dethrone all still work.

## Relevant files
- `src/server/BotController.luau` — the AI: predict contact, compute the off-center stand position, move
  the bot, drive the jump-velocity collider; remove the `bc:launch` path.
- `src/server/HitResolver.luau` (or a new bot-collider source) — provide bot hit-sphere colliders; combine
  with human colliders for `bc:step`.
- `src/server/NineSquareServer.server.luau` — pass the combined (human + bot) colliders to `bc:step`;
  drop the artificial bot-volley wiring.
- `src/server/RotationService.luau` — bot bodies (move them to the stand position + jump, synced to the
  collider).
- `src/shared/GridConfig.luau` — `botJumpVelocity`, off-center offset, move speed, reuse `hitZoneRadius` /
  `botMissChance` / contact window.
- `src/server/BallController.luau` — reused (collision, `strikeVelocity`); do NOT change the physics.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; standalone
  `require` reads a stale module — use `script_read`/`get_console_output`/screenshots; leave Studio in
  **Edit**).

## Constraints
- Don't change the human's hit, the swept collision/physics, the rotation timing, the over-pipe
  `ownerCell`/save logic, or the dethrone — bots now go THROUGH the existing collision. Tunables in
  `GridConfig`. Bot hit-spheres are abstract colliders (like the human's), not physical parts that the
  ball box-collides with — keep them out of `BallController._surfaces`.
