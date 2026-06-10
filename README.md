# 9 Square in the Air (Roblox)

A multiplayer king-of-the-hill volley game for Roblox, based on the playground game
*9 Square in the Air*. Built live in Roblox Studio via the `robloxstudio-mcp` integration.

## Status

**Milestone M1 (greybox) — in progress.** Playable single-player loop exists in the place
**"9 Square Beta"**. Working: enclosed gymnasium scene, 3×3 court, physical serve + contact volley,
self-square / out-of-bounds faults, soft ball shadow, fixed court camera.

## Docs

- Master PRD: [`docs/9-square-prd.md`](docs/9-square-prd.md)
- M1 design spec: [`docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md`](docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md)
- M1 plan: [`docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md`](docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md)

## Build milestones (PRD §15)

1. **M1** — Greybox arena + readability + physical contact volley.  ← *current*
2. **M2** — Hit resolver: timing tiers + scatter on the same contact.
3. **M3** — Full grid + rotation + dethrone.
4. **M4** — Bots fill empty squares; solo play fully functional.
5. **M5** — Networking hardening / anti-cheat.
6. **M6** — Progression, leaderboard, audio/VFX, mobile tuning.

## Key design decisions (evolutions from the PRD)

- **Server-authoritative, deterministic** ball arcs — no client-side physics.
- The hit is a **physical contact volley**: get under the ball and jump; you must *reach* the frame
  plane (jump apex) **and** *touch* the ball. **Serving is physical too** (no button) — the ball
  hovers at center and you strike it.
- **Contact-aim**: outgoing horizontal direction comes from the contact geometry (radial impulse /
  reflection). Vertical pop is a fixed `hitSpeedV` for hang time. Supersedes the PRD aim-assist (§5.4).
- **Faults**: a ball that returns to the square it was struck from is a *self-fault*; landing outside
  the 9 squares is *out-of-bounds*. Both flash the square + play the oof sound, then re-serve.
- **Scene**: an enclosed gym (`MatchService.buildGym`, build-once) with painted floor grid lines so
  the grid reads in Play even when dynamic shadows don't render.

## Known issues / next steps

- **Pipe/wall collision is dormant.** `BallController:_collide` correctly bounces the ball off the
  frame pipes + gym walls, BUT with the current high apex (~24) vs frame height (11) the ball arcs
  4–6 studs clear of every pipe and never reaches the walls — so it visually passes through the
  *open squares* of the frame and never touches a bar. To make pipes interactive, **flatten the
  trajectories** (lower `hitSpeedV` and/or raise `hitSpeedH`, or lower the apex relative to the
  frame) so the ball crosses the frame plane nearer pipe height between squares. (Verified via a
  trajectory sim: closest pipe approach 4.05 studs vs ball radius 2.0.)
- `Lighting.Technology` can't be set by script — set it to **ShadowMap/Future** in Studio Properties
  if you want real dynamic shadows (painted grid lines mean you don't strictly need it).

## Layout

- `src/shared/GridConfig.luau` — dimensions + pure grid/contact math (all tunables).
- `src/server/` — `BallController` (ball physics/arcs/collision), `MatchService` (builds gym + court,
  player-cell lookup), `HitResolver` (contact normal), `NineSquareServer` (bootstrap + Heartbeat).
- `src/client/NineSquareClient.client.luau` — shadow, strike ring, highlight, camera.
- `docs/` — PRD, specs, plans.

## Continuing on another machine (e.g. Mac)

The git repo is the **source of truth for code**; the Roblox **place** ("9 Square Beta") lives in
the Roblox account (open it from Studio on the Mac).

1. `git clone` this repo on the Mac.
2. Install Node + the `robloxstudio-mcp` server, and the Studio companion plugin (see the MCP setup).
3. Open the "9 Square Beta" place in Studio (Edit mode).
4. Deploy `src/*.luau` into Studio via the MCP `set_script_source` onto the fixed instance paths
   (mapping table at the top of the M1 plan). The server bootstrap rebuilds the court/gym on Play.

**Note:** the `robloxstudio-mcp` plugin only operates in Studio **Edit mode** — all MCP calls time
out during Play/Test. Verify logic in Edit; play-test by hand.
