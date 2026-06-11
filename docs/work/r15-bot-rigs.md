# Swap dummy bot bodies for animated R15 rigs (keep the deterministic collider)

## Problem
The 8 bots (`Bot_rank1`..`Bot_rank8`) are minimal custom greybox bodies built in `RotationService.luau`
(dummy geometry: `botHeadSize`, `dummyHeight`, `dummyRadius`, `botRestColliderY`). They look like blocky
placeholders. Swap the **visual** for a real **R15 rig** with canned idle/walk/jump animations so the
bots read as characters — and open the path to real avatars later (M6) — **without giving up the
deterministic, server-authoritative physics** the aim/strike/fault/save logic depends on.

## Approach (the pragmatic recommendation — DO NOT do a full Humanoid-pathfinding rework)
Keep EVERYTHING that makes the hit deterministic; only change the body the player sees.

- **Keep the abstract hit-sphere collider** (`{center, radius=hitZoneRadius, vel}`) exactly as-is, fed into
  `BallController:step`. The ball strikes the COLLIDER, never the rig parts. **The R15 character parts must
  NOT enter `BallController._surfaces`** and must be `CanCollide = false` (so they never interfere with the
  swept ball collision or with each other on rotation). The aim (off-center stand), `botJumpVelocity`,
  save/fault, and rotation placement are unchanged.
- **Keep the server-driven root.** The server already drives each bot body's position (intercept slide,
  jump, and the just-added procedural idle sway/ready-steps in `BotController.update_idle` +
  `RotationService.idleOccupant`/`driveOccupant`). Re-parent / re-target that driving onto the R15 rig's
  `HumanoidRootPart` (CFrame-driven, NOT `Humanoid:MoveTo()`/pathfinding — that's non-deterministic and is
  explicitly out of scope). The collider stays attached to the rig (torso/head) the same way it is now.

### Rig (decision: default R15 blocky dummy)
- Use Roblox's **standard R15 "Rig Builder" dummy** (blocky R15) as the bot body — built-in, lightweight,
  stock animations. Insert/build one rig template and clone it 8×, one per rank. Greybox-plus look is fine.
- Set the `Humanoid` so it does NOT self-locomote: e.g. `Humanoid.PlatformStand`/anchored root or
  `WalkSpeed = 0` and drive the `HumanoidRootPart` CFrame directly each step (whatever cleanly lets the
  server own the position while the rig still animates). All character parts `CanCollide = false`,
  `Massless`/anchored as needed so physics doesn't fight the server drive.

### Animation (decision: LAYER anims on the driven root — keep the procedural idle)
- **Keep** the existing procedural idle (the server-driven sway/ready-steps + ball-lean from the lifelike
  task) as the root TRANSLATION — it stays. ADD canned R15 animation tracks ON TOP for limb life:
  - a looped **idle** track while resting,
  - a **walk/run** track while the bot is sliding to intercept (or doing a ready-step) — gate by the
    body's actual per-frame speed so it blends naturally,
  - a **jump** track fired when the bot drives its collider up to strike.
- Use the stock Roblox R15 animation asset ids (idle/walk/jump) via an `Animator` on each `Humanoid`.
  Keep the anim ids + any blend/speed thresholds as tunables in `GridConfig`.

## Acceptance criteria
- The 8 bots are visibly **R15 character rigs** (not dummy blocks), each playing a looped **idle**
  animation at rest, a **walk/run** while moving to intercept, and a **jump** when striking.
- **Physics unchanged:** verified in Play — rallies, off-center aim, bot strikes (`SWING`), over-pipe
  `SAVE`s, fault attribution, deferred rotation, and correct re-placement after a rotation all still work
  exactly as before; the ball strikes the abstract collider (rig parts are `CanCollide=false` and absent
  from `_surfaces`); no part of a rig knocks the ball or another bot around.
- The procedural idle motion (root sway/steps + ball-lean) still drives position; animations are layered
  on top (re-run the 8s travel probe: all 8 bots still show non-zero, varied `totalTravel`).
- No console errors / failed anim or asset loads; performance is fine with 8 rigs.
- Studio left in **Edit**.

## Relevant files
- `src/server/RotationService.luau` — build/clone the R15 rig per rank (replace the dummy-geometry body);
  drive the rig's `HumanoidRootPart`; hold the `Humanoid`/`Animator` + animation tracks; keep the collider
  attachment + `idleOccupant`/`driveOccupant`/`restOccupant` driving the rig.
- `src/server/BotController.luau` — unchanged hit logic; feed the same speed/jump signals so the right
  animation track plays (idle/walk/jump) per bot state.
- `src/server/NineSquareServer.server.luau` — bot setup/placement wiring (now spawns rigs); Heartbeat step
  unchanged otherwise.
- `src/shared/GridConfig.luau` — stock R15 idle/walk/jump anim ids + walk-blend speed threshold; the dummy
  geometry tunables (`botHeadSize`/`dummyHeight`/`dummyRadius`) become legacy or feed the collider only.
- `src/server/BallController.luau` — DO NOT change; just ensure rig parts never enter `_surfaces`.
- Use the `robloxstudio` MCP to insert/build the R15 rig + stock animations and verify in Play (mode
  flip-flops — `get_studio_state` first; standalone `require` reads a STALE module — verify via
  `script_read`/`get_console_output`/the travel probe; leave Studio in **Edit**).

## Constraints
- **Deterministic & server-authoritative stays.** Drive the `HumanoidRootPart` by CFrame from the server —
  NO `Humanoid:MoveTo()` / pathfinding / Humanoid self-locomotion (out of scope; it would loosen the
  off-center aim). Animations are COSMETIC only.
- The abstract hit-sphere collider is the ONLY thing the ball collides with. Rig parts: `CanCollide=false`,
  out of `BallController._surfaces`, must not perturb the ball or each other (esp. during rotation).
- Don't change the strike formula, swept collision, `botJumpVelocity`, aim, save/fault, or rotation logic.
- Default R15 blocky dummy (not custom avatars yet — real avatars are M6). Tunables in `GridConfig`.
