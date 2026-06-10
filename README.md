# 9 Square in the Air (Roblox)

A multiplayer king-of-the-hill volley game for Roblox, based on the playground game
*9 Square in the Air*. Built live in Roblox Studio via the `robloxstudio-mcp` integration.

## Status

- **Current milestone:** M1 — Greybox Readability Prototype (design approved; build pending)

## Docs

- Master PRD: [`docs/9-square-prd.md`](docs/9-square-prd.md)
- M1 design spec: [`docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md`](docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md)

## Build milestones (PRD §15)

1. **M1** — Greybox arena + readability: frame at jump-reach height, shadow + descent-ring telegraph, physical contact volley.
2. **M2** — Hit resolver: timing tiers + scatter layered on the same contact.
3. **M3** — Full grid + rotation + dethrone.
4. **M4** — Bots fill empty squares; solo play fully functional.
5. **M5** — Networking hardening / anti-cheat.
6. **M6** — Progression, leaderboard, audio/VFX, mobile tuning.

## Key design decisions (evolutions from the PRD)

- **Server-authoritative, deterministic** ball arcs — no client-side physics.
- The hit is a **physical contact volley**: the player must *reach* the frame plane (jump apex) **and** *touch* the ball.
- **Contact-aim** — outgoing direction comes from the contact geometry (**reflection/bump**) plus a small steering nudge. This **supersedes the PRD's aim-assist model (§5.4)**.

## Layout

- `src/` — Luau modules (GridConfig, BallController, MatchService, HitResolver, ClientInput, ClientRender), synced into Studio.
- `docs/` — PRD and per-milestone design specs.
