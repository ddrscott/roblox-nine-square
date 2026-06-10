---
title: "9 Square in the Air — Milestone 4: Bots"
type: design-spec
parent_prd: "9 Square in the Air - Roblox PRD (v0.1)"
status: accepted
version: 0.1
platform: Roblox (Luau)
author: Scott Pierce
last_updated: 2026-06-10
---

# Milestone 4 — Bots

## 0. Context
Scopes **only M4** (PRD §15.4, §7). M3 built the king-of-the-hill loop with **static dummy occupants**
that auto-fault. M4 turns those dummies into **bots that actually volley**, so real rallies happen and a
solo human plays a full game (PRD §7: "a fully solo session is nine bots plus one human, fully playable").

**Initial bot behaviour (agreed):** when a ball comes to a bot's square the bot volleys it with a simple
aim — **on an outer square, hit toward the center (C); on the center (King), hit toward the outside (a
random outer square)** — and **occasionally misses** (so faults happen, the grid rotates, and the human
can climb). Smarter aim/skill curves are later polish.

**"Leverage Roblox AI":** the bot **bodies** are Roblox `Humanoid` NPCs (so they read as players and can
animate); their movement-to-the-ball can use `Humanoid:MoveTo` / `PathfindingService` for believability.
But the **hit itself is resolved server-side** (deterministic, server-authoritative — PRD §11 forbids
client/physics-owned scoring), exactly like the existing King auto-serve. We do not try to make a
Humanoid physically jump-time the ball through the contact collision; that is unreliable.

## 1. Goal & success criteria
**Goal:** the 8 non-human squares are bots that serve (when King) and volley balls into their square with
the simple aim rule, missing sometimes; the human competes, climbs as bots miss, can reach King, and a
bot King can be dethroned — a complete solo king-of-the-hill game.

**M4 is done when:**
1. A ball descending into a **bot's** square is **volleyed** by that bot (not an automatic fault) toward
   its aim target: outer bot → center (C); King bot → a random outer square.
2. Bots **miss** at a tunable rate, producing faults → rotation, so rallies end and ranks rotate.
3. Real **rallies** occur (ball passes bot→center→bot…), and a **solo human** can survive, climb the
   ranks, and become King; a bot King fault still triggers the dethrone.
4. Bot behaviour is **server-authoritative + deterministic**; all params (miss rate, volley speed, aim)
   live in `GridConfig`.
5. The human's physical-contact volley (M1) is unchanged and coexists with bot squares.

## 2. Scope
**In:** a `BotController` that, per Heartbeat, intercepts the ball at the contact window over a
bot-occupied square and resolves a **volley toward the aim target** or a **miss** (→ fault); the aim rule
(outer→center / King→outside); a tunable **miss chance** (single "Normal" difficulty to start); reuse of
the King serve from M3 for a bot King; bot bodies as Humanoid NPCs (replacing the cosmetic cylinders) with
a simple volley animation/hop; coexistence with the human's physical volley.
**Deferred:** difficulty enum + per-difficulty reaction-latency/accuracy/aim-spread curves (later in M4 or
M6); pathfinding-heavy movement; networking hardening / anti-cheat (M5); stats/leaderboard/full VFX (M6).

## 3. Bot volley resolution (the core)
Each Heartbeat, after `bc:step`, the server checks the ball:
- If `phase == "Flight"`, the ball is **descending** (current vY < 0), its XZ is over square `cell`, the
  occupant of `cell` is a **bot**, and the ball has reached the **contact window** (descending through ~
  `frameHeight`, with a small band), then **resolve the bot's turn once** (debounce per descent):
  - **Hit (prob `1 - botMissChance`):** launch the ball from the contact point toward the **aim target's**
    frame point — `aimCell = (cell == "C") and randomOuter() or "C"` — with a deterministic velocity
    (reuse the M3 `serveToTarget`/ballistic launch: horizontal toward the target + an upward pop for hang
    time, `botVolleySpeed`/`serveArcApex`). Mark this as the bot's single touch.
  - **Miss (prob `botMissChance`):** do nothing — the ball falls to the floor in the bot's square →
    existing `onLand` → **floor fault** → `rotateOnFault` (M3). (Occasionally a bot could also mis-aim out
    of bounds; for the initial version a simple "no-hit miss" is enough.)
- The **human's** square is NOT handled here — the human volleys via the existing physical contact
  (`BallController` player collision). `BotController` only resolves bot-occupied squares.

The King serve already branches in M3 (human King = physical hover; dummy/bot King = auto-serve to a
random outer square) — that auto-serve IS the King bot's "hit toward the outside," so it stays.

## 4. Bot bodies (leverage Roblox Humanoid)
- Replace the cosmetic dummy cylinders with simple **Humanoid NPC** rigs (or keep a stylised body) that
  stand in their square, so bots look like players and can animate. On a volley, play a quick hop / jump
  animation (juice). Optional: `Humanoid:MoveTo` the ball's predicted landing XZ within the square before
  the volley for believability.
- Keep them out of `BallController._surfaces` (the ball must not collide with bot bodies; the hit is
  server-resolved). Re-placed by `RotationService.placeAll` on rotation, same as today.

## 5. Modules touched
| Module | M4 work |
|---|---|
| `GridConfig` (shared) | `botMissChance`, `botVolleySpeed`/reuse serve tunables, contact-window band; (later) difficulty params |
| `BotController` (server, new) | per-Heartbeat ball interception over bot squares → volley-or-miss with the aim rule |
| `NineSquareServer` (server) | run `BotController` each Heartbeat after `bc:step`; provide ball/occupant access |
| `RotationService` (server) | expose occupant-at-cell / is-bot; bot bodies (or via MatchService) |
| `BallController` (server) | reused; bot volley uses `bc:launch` with a computed v0 (physics unchanged) |
| client | none required (bots are server-side); optional bot anim is server-driven |

## 6. Build order (incremental)
1. **BotController — volley + aim + miss, wired into the loop.** Intercept the ball at the contact window
   over a bot square; volley toward aim (outer→C / King→outer) or miss → fault. Real rallies + rotation
   from bot misses; the human can climb. (Core M4 — this makes it a game.)
2. **Bodies + difficulty tune + acceptance.** Humanoid bot bodies + a volley hop; tune `botMissChance` for
   a fun rotation rate; confirm the human can reach King and a bot-King dethrone fires; record M4
   acceptance in this spec and mark M4 done / M5 next in the README.

## 7. Definition of done
Solo play is a full game: bots serve + volley with the simple aim, miss at a tuned rate, rallies happen,
the human climbs and can become King, and a bot King can be dethroned — all server-authoritative and
tunable. Then **M5** hardens networking/anti-cheat and **M6** adds progression + polish.

## M4 Acceptance

**Date:** 2026-06-10 · **Result: PASS** (verified solo in the place "9 Square Beta" over MCP — a Play
session of the full loop, plus an isolated RotationService check). Step 1 (BotController volley + aim +
miss) shipped earlier; step 2 added bot bodies, tuned the miss rate, and closed out the milestone.

### §1 success criteria

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Ball descending into a bot square is **volleyed** toward its aim (outer→C / King→outer), not an auto-fault | ✅ PASS | Console: `[Bot] dummy6 VOLLEY SE -> C`, `[Bot] dummy2 VOLLEY C -> S`, `[Bot] dummy3 VOLLEY C -> E` … — outer bots aim C, the King (C) aims a random outer square. |
| 2 | Bots **miss** at a tunable rate → fault → rotation | ✅ PASS | Console: `[Bot] dummy3 MISS in C -> floor fault` → `FAULT (floor / unreturned) cell=C` → `rotateOnFault(1)`. Misses occur ~1 per several exchanges at `botMissChance = 0.18`. |
| 3 | Real **rallies** occur; the human can climb + reach **King**; a bot-King fault fires the dethrone | ✅ PASS | Rallies of up to ~9 exchanges (`C↔SE`, `C↔N`, `C↔E` …) before a miss. HUD showed the human climbing 9→8→7. Bot-King faults fired `DETHRONE` (dummy1→dummy2→dummy3→dummy4 took the throne). Isolated check (human seeded at rank 2, rank-1 bot faults): `human_after = 1`, `humanCell = "C"`, `isHumanKing = true`, `dethroned_to = "human"` — the human **can** reach King and the serve branch flips to the human's physical hover-serve. |
| 4 | Bot behaviour **server-authoritative + deterministic**; all params in `GridConfig` | ✅ PASS | `BotController.resolve` runs each Heartbeat after `bc:step`; the hit is a computed `bc:launch`, never a physical collision. Tunables (`botMissChance`, `botContactBand`, `botVolley`/serve arc, body + hop sizes) live in `GridConfig`. |
| 5 | Human's physical-contact volley (M1) unchanged + coexists | ✅ PASS | `BotController` only resolves `.isDummy` squares; the human's square is left to the M1 swept-sphere collision. The M1/M3 loop (serve, fault attribution, rotation, HUD, camera) is untouched. |

### Bot bodies (§4)
- The 8 bot occupants are cheap **stylised humanoid bodies** — a `Model` of anchored parts (torso + cube
  head + two arms) with the torso as `PrimaryPart`, built in `RotationService.buildBotBody`. Verified in
  Play: **8 models / 32 parts, all `CanCollide = false`, none under `NineSquare.Frame`** (so they are
  excluded from `BallController:_surfaces`, which only gathers from `Frame` + `Gym`). They re-place + the
  rank-1 holder recolours **gold** on every `placeAll` (rotation), so the King body always reads gold in C.
- On a volley, `BotController` calls `RotationService:hopOccupant(id)`, which **pivots the whole body up
  and back down** (Heartbeat-driven, `botHopHeight`/`botHopUpTime`/`botHopDownTime`) so the hit reads
  visually. Cosmetic only — `CanCollide` stays false; the ball never touches a bot.
- Screenshots: top-down Play view shows 8 bodies one-per-square with the gold King bot in C inside the
  gold King box, the human (green) in a side square, and the ball in flight.

### Final tuned values (`GridConfig`)
- `botMissChance = 0.18` (was 0.25). 0.25 ended rallies too fast (most descents faulted); 0.18 gives a
  steady rotation cadence (~1 fault every few exchanges) while letting bot↔C↔bot rallies actually happen,
  so the human can ride a clean rally upward and realistically climb to King.
- `botContactBand = 3`, serve/volley arc reused from M3 (`serveArcApex = 6`) — unchanged; bot↔center↔bot
  rallies read well and are returnable.
- Bot body/hop: `botTorsoSize = (2.2, 2.6, 1.2)`, `botHeadSize = 1.4`, `botArmSize = (0.7, 2.4, 0.7)`,
  `botBodyColor` violet / `botKingColor` gold / `botSkinColor` tan; `botHopHeight = 2.6`,
  `botHopUpTime = 0.10`, `botHopDownTime = 0.22`.

**M4 is complete.** Next: **M5** — networking hardening / anti-cheat.
