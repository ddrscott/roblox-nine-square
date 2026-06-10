---
title: "9 Square in the Air - Roblox PRD"
type: prd
status: draft
version: 0.1
platform: Roblox (Luau)
author: Scott Pierce
last_updated: 2026-06-09
---

# 9 Square in the Air - Roblox Product Requirements Document

## 1. Overview

A multiplayer king-of-the-hill ball game for Roblox, based on the playground game 9 Square in the Air. Nine players stand under a 3x3 grid of squares suspended overhead. The King in the center square serves the ball into another square. The player under that square gets one touch to volley it up and over into someone else's square. Miss your square, hit it out of bounds, or fail to clear it, and you are eliminated and rotate to the back. Survive and climb toward the center to become King and hold the throne as long as possible.

The Roblox build uses a hybrid control model (aim assist plus skill timing), fills empty squares with bots, and uses an open court where balls that sail out of the grid count as a miss by the hitter.

> **Note (design evolution):** During M1 brainstorming the hit model evolved away from aim-assist (§5.4)
> toward a **physical contact volley** with **reflection/bump** direction + small steering. The
> per-milestone specs under `docs/superpowers/specs/` are authoritative where they diverge from this PRD.

### 1.1 One-line pitch

Volley, dethrone, reign. Climb the 9-square grid one square at a time and rule the center for as long as your timing holds.

## 2. Goals and non-goals

### Goals

- Faithful translation of the single-touch 9 Square ruleset into a server-authoritative Roblox game.
- Readable, fair, low-latency hit mechanic that works on mobile, PC, and console.
- Seamless solo-to-full-lobby experience: bots fill any empty square so a single player can always play.
- Satisfying king-of-the-hill loop with a reign timer and progression hooks that drive replay.

### Non-goals (v1)

- Realistic ball physics. The ball uses deterministic server-driven arcs, not free physics.
- Wall and ceiling bounces. Court is open; out of bounds is a fault on the hitter.
- Ranked matchmaking, tournaments, or cross-server play.
- Power-ups or modifiers. Pure skill game in v1.

## 3. Core rules (digital interpretation)

1. Nine squares arranged 3x3. The center square is the King (also Queen, same role). The eight outer squares are ranked positions players rotate through.
2. Only the King serves. The King aims at any of the eight outer squares and serves the ball in a high arc into it.
3. Single touch. Whoever's square the ball descends into gets exactly one contact to send it up and over into a different square.
4. A legal hit must leave the hitter's own square and land inside another square's column.
5. Fault conditions eliminate the responsible player and trigger a rotation (see Section 6).
6. There is no fixed end score. Play is continuous. The objective is to reach and hold the King square.

## 4. Grid and rotation system

### 4.1 Layout

```
[ NW ][ N  ][ NE ]
[ W  ][ C  ][ E  ]
[ SW ][ S  ][ SE ]
```

`C` is the King square (rank 1). The eight outer cells map to ranks 2 through 9.

### 4.2 Rank-to-cell mapping (default, configurable)

| Rank | Cell | Role |
|------|------|------|
| 1 | C | King (serves) |
| 2 | N | Challenger (next in line for throne) |
| 3 | NE | |
| 4 | E | |
| 5 | SE | |
| 6 | S | |
| 7 | SW | |
| 8 | W | |
| 9 | NW | Entry square (lowest) |

Rank order is a config table, not hardcoded. The default is a clockwise ring with the King in the center. Advancing one rank moves a player one step closer to the throne.

### 4.3 Rotation on fault

When the player at rank R faults:

1. The faulting player is removed from their square and pushed to the tail of the waiting queue.
2. Every player at rank R+1 through 9 advances one rank toward the King (rank K moves to the cell of rank K-1).
3. Rank 9 (entry square) is filled from the front of the waiting queue.

If the King (rank 1) faults, the rank 2 player takes the throne and everyone shifts up. This is the dethrone moment and should get extra audio and visual emphasis.

The waiting queue holds humans first, then bots, so empty squares are always backfilled (see Section 7).

## 5. Hit mechanic (hybrid: aim assist + skill timing)

This is the heart of the game. The model rewards timing skill while keeping aiming forgiving enough for mobile.

### 5.1 Ball lifecycle in a rally

```
Serve -> InFlight -> Descending(targetSquare) -> [ HitResolved -> InFlight ] | [ Fault -> Rotation ]
```

- The server computes a deterministic parabolic arc to a target square center (plus scatter, see below).
- A ground shadow is projected in the target square so the responsible player can read where and when the ball will arrive. The shadow is the primary timing telegraph and is mandatory for playability.

### 5.2 The hit input

When the ball enters the descending phase over a player's square, a timing window opens. The player presses a single action (Hit). Two factors resolve the outcome:

- Timing: how close the press lands to the ideal contact point.
- Aim: the player's current aim direction, which aim assist snaps toward the nearest valid target square center within a configurable cone.

### 5.3 Timing tiers

| Tier | Window | Result |
|------|--------|--------|
| Perfect | tight center window | Clean hit, full control, minimal scatter, snaps to aimed square |
| Good | wider window | Hit lands but with moderate scatter around the aimed square |
| Early / Late | edges of window | Weak or mishit: reduced power, large scatter, may fail to clear own square or sail out of bounds |
| Miss (no press) | window expires | Ball lands on floor in own square: fault |

Scatter means the actual landing point is offset from the aimed square center by a radius that grows as timing quality drops. Poor timing can push the landing into the hitter's own square (self-fault) or past the grid edge (out of bounds fault).

### 5.4 Aim model

> **Superseded for the hit by contact-aim (reflection/bump + steering) as of M1.** Retained here for serve and as historical reference.

- Default aim source is camera facing direction (PC), right stick (console), or drag direction (mobile).
- Aim assist snaps the resolved direction to the nearest valid square center inside a cone (default 25 degrees, tunable).
- The currently targeted square is highlighted before the press so the player gets feedback on where they are about to send the ball.
- The King's serve uses the same aim assist but with a wider, more forgiving cone since the serve is not under time pressure.

### 5.5 Serve

The King initiates each rally. The King presses Serve, the aim reticle snaps to a chosen outer square, and the ball launches in a high arc into it. Optional serve charge (hold to set power within bounds) can be a Should-have, not required for v1.

## 6. Fault and elimination rules

A rally ends and triggers rotation when any of these occur. The faulting player is always the one eliminated.

| Fault | Responsible player |
|-------|--------------------|
| Ball lands on floor inside a square with no hit | The player under that square |
| Ball hit out of bounds (open court) | The hitter |
| Ball fails to leave the hitter's own square | The hitter (self-fault) |
| Second contact in a single rally turn | The player who double-touched (enforced by single-touch rule) |

The server is the sole authority on landing position and fault attribution. Clients never decide faults.

Edge case: a ball that grazes the boundary between two squares resolves to the square whose center is closest to the landing point. Define a small dead-band at boundaries to avoid ambiguous calls; recommend resolving toward the square with the larger overlap area.

## 7. Bots

Bots fill any square not occupied by a human so play never stalls.

- Bots occupy squares, serve when King, and react to balls entering their square with a timing press.
- Bot skill is parameterized: reaction latency, timing accuracy distribution, and aim spread. Expose a difficulty enum (Easy, Normal, Hard) mapping to those parameters.
- When a human joins, they take the next open square. If all nine squares are bots, the joining human replaces the lowest-rank bot (rank 9). The displaced bot moves to the queue tail.
- When a human faults and the queue has bots, the human re-enters ahead of bots in the queue so humans get priority on the next open square.
- A fully solo session is nine bots plus one human, fully playable.

## 8. Camera and readability

Standing under an overhead grid and tracking a ball arc is the main UX risk. Recommendations:

- Use an angled third-person camera locked to face the court center, tilted up enough to see the grid and the ball apex without neck-craning framing.
- Project a ball shadow on the floor of the target square at all times during flight. Shadow size and position telegraph landing point and timing. This is the single most important readability feature.
- Add a descent indicator (for example a shrinking ring on the shadow) that hits minimum size at the ideal contact moment, giving players a clean timing cue.
- Highlight the local player's own square edge so they always know their responsibility zone.

## 9. Match structure and progression

- Play is continuous king-of-the-hill. No fixed rounds in v1.
- Track per player: current rank, current reign duration (time as King), longest reign, total crowns (number of times reaching King), and faults.
- Surface a live reign timer for the current King and a server leaderboard for longest reign and most crowns.
- Optional Should-have: short highlight or banner on each dethrone showing who took the throne.

## 10. Input and platforms

Single primary action keeps it mobile-friendly.

| Platform | Hit | Aim | Serve |
|----------|-----|-----|-------|
| Mobile | On-screen Hit button (tap) | Drag or auto-face | Serve button |
| PC | Click or spacebar | Mouse / camera facing | Click target |
| Console | A / primary button | Right stick | Primary button |

Aim assist absorbs most of the precision gap across platforms. The hit is always one button.

## 11. Technical architecture

### 11.1 Authority model

Server-authoritative. The server owns ball state, square ownership, fault detection, rotation, and all scoring. Clients send input intents only.

- Ball is server-simulated. Clients receive replicated trajectory data and render the arc and shadow locally. Do not hand network ownership of the ball to clients.
- Hit input is a RemoteEvent carrying client press timestamp and aim vector. The server validates timing against authoritative ball state and resolves the outcome. Reject or clamp inputs that fall outside plausible windows.
- Never trust the client for landing position, fault calls, or rotation.

### 11.2 Suggested module breakdown

| Module | Responsibility |
|--------|----------------|
| MatchService (server) | Lobby, queue, rotation, scoring |
| BallController (server) | Arc computation, descent phase, landing resolution |
| HitResolver (server) | Validates hit intent, computes timing tier and scatter, attributes faults |
| BotController (server) | Drives bot squares: serve, react, hit with skill params |
| GridConfig (shared) | Rank-to-cell map, square sizes, frame height, all tunables |
| ClientInput (client) | Captures Hit and aim, sends intent RemoteEvent |
| ClientRender (client) | Renders replicated arc, shadow, descent ring, square highlights, HUD |

### 11.3 Core data model (sketch)

```lua
type SquareState = {
  rank: number,          -- 1..9
  cell: string,          -- "C","N","NE",...
  occupantId: string?,   -- userId or botId
  isKing: boolean,
}

type BallState = {
  phase: "Serve" | "InFlight" | "Descending" | "Resolved",
  origin: Vector3,
  target: Vector3,       -- resolved landing point (center + scatter)
  targetSquareRank: number,
  apex: number,
  launchTime: number,
}

type PlayerRecord = {
  id: string,
  isBot: boolean,
  rank: number?,         -- nil if queued
  reignStart: number?,
  longestReign: number,
  crowns: number,
  faults: number,
}
```

### 11.4 Hit resolution flow

1. Ball enters Descending phase over square with rank R. Server marks a contact window.
2. Client of occupant presses Hit, sends intent (timestamp, aim vector).
3. Server maps press time to a timing tier and computes scatter radius from that tier.
4. Server resolves aim to a target square via aim-assist cone, applies scatter, derives landing point.
5. Server checks landing: another square (legal, continue), own square (self-fault), or out of bounds (fault on hitter), or no input before window close (floor fault on occupant).
6. On legal hit, server starts a new arc to the new target. On fault, server runs rotation and starts a new King serve.

### 11.5 Anti-cheat notes

- Validate press timestamps against server ball clock with a tolerance band sized to expected latency. Discard impossible inputs.
- Aim vectors are clamped and snapped server-side; client-supplied aim is advisory.
- Scoring and rank changes only ever mutate on the server.

## 12. Tunable parameters

All values live in `GridConfig` and should be data-driven, not hardcoded.

| Parameter | Notes |
|-----------|-------|
| Square size (studs) | Start ~14x14, tune for avatar scale and arc readability |
| Frame height (studs) | Overhead grid height above floor |
| Arc apex height | Controls hang time and difficulty |
| Descent time | Window length from apex to contact point |
| Hit window: perfect / good / edge (ms) | Timing tier boundaries |
| Aim-assist cone (degrees) | Default 25 for hits, wider for serve |
| Scatter radius by tier | Perfect ~0, scaling up to large for mishits |
| Bot reaction latency (per difficulty) | Easy slow, Hard near-instant |
| Bot timing accuracy / aim spread | Per difficulty |
| Serve power / arc | Fixed or chargeable |

## 13. Scope (MoSCoW)

### Must

- 3x3 grid, King serve, single-touch hybrid hitting with timing tiers and aim assist.
- Ball shadow and descent telegraph.
- Fault detection (floor, out of bounds, self-square) and rotation toward King.
- Bots filling empty squares; solo play fully functional.
- Server authority and basic anti-cheat on hit timing.
- Reign timer and current King indicator.

### Should

- Per-player stats (longest reign, crowns, faults) and a server leaderboard.
- Bot difficulty scaling.
- Hit-quality feedback (audio and VFX per timing tier).
- Dethrone emphasis moment.

### Could

- Cosmetics: ball skins, crowns, trails.
- Emotes and taunts.
- Private servers.
- Serve charge mechanic.

### Won't (v1)

- Realistic free physics.
- Wall and ceiling bounces.
- Power-ups, ranked play, tournaments.

## 14. Open decisions

These are not blockers but should be settled before or during build:

- Studs scaling: exact square size and frame height need playtesting against Roblox avatar scale and camera angle.
- Continuous play vs timed rounds: v1 assumes continuous; a timed round mode could improve session pacing and is worth prototyping.
- Queue behavior above 9 humans: confirm humans-priority queue and whether extra humans spectate or sit in a visible line.
- Monetization: cosmetics-only via game passes and developer products is the assumed direction. Confirm.
- Double-touch enforcement: with a single press-to-hit model, double touch is mostly structural, but decide whether mid-air re-contact is even possible and needs guarding.

## 15. Suggested build milestones

1. Greybox arena: static 3x3 frame, single ball, manual serve, shadow telegraph, one human under one square. Prove readability.
2. Hit resolver: timing tiers, aim assist, scatter, fault detection for a single square. Tune the window.
3. Full grid and rotation: nine squares, King serve, rotation on fault, dethrone.
4. Bots: fill squares, serve, react, difficulty params. Validate solo play.
5. Networking hardening: server authority, intent validation, latency tolerance, anti-cheat pass.
6. Progression and polish: stats, leaderboard, audio and VFX, camera tuning, mobile controls.
