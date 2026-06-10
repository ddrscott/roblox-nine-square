---
title: "9 Square in the Air — Milestone 1: Greybox Readability Prototype"
type: design-spec
parent_prd: "9 Square in the Air - Roblox PRD (v0.1)"
status: draft
version: 0.1
platform: Roblox (Luau)
author: Scott Pierce
last_updated: 2026-06-09
---

# Milestone 1 — Greybox Readability Prototype

## 0. Context

This spec scopes **only Milestone 1** of the parent PRD ("9 Square in the Air"). The full
game is built milestone-by-milestone (PRD §15). M1 exists to answer a single question:

> **Can a player standing under an overhead 3×3 grid read a descending ball and land a timed,
> physical volley?**

Everything not needed to answer that is explicitly deferred to later milestones.

### Divergences from the parent PRD (intentional, agreed during design)

- **Hit/aim model (supersedes PRD §5.4 aim-assist):** Direction is **not** produced by an
  aim-assist cone snapping to the nearest square center. Instead it is produced **physically**
  by the contact geometry of the volley (reflection/bump) plus a small steering input. Aim-assist
  is dropped; it may return only as an optional gentle helper in a later milestone if playtesting
  demands it.
- **Hit requires real contact, not just timing.** The player must (a) reach the frame-plane
  height via a jump **and** (b) actually overlap the ball with their hit-zone. Reaching the right
  height at the right time but missing the ball spatially is a whiff.

## 1. Goal & success criteria

**Goal:** A greybox arena where one human can repeatedly serve a ball into the square they're
standing under, then jump to volley it back up, with the outgoing direction determined by where
they contact the ball.

**M1 is "done" when:**
1. Standing under any outer square, the player can reliably tell **where** and **when** the ball
   will arrive, from the floor shadow + shrinking descent ring.
2. The player can time a **jump** so their hit-zone meets the ball at the frame plane.
3. A successful contact sends the ball back up, and **the contact point visibly changes the
   outgoing direction** (off-center contact deflects it; a small steer nudges it further).
4. All key numbers (square size, frame height, apex, windows, hit-zone radius, steer cone) live in
   `GridConfig` and are tunable live.

This is the go/no-go gate for Milestone 2.

## 2. Scope

### In scope (M1)
- Static greybox arena: 3×3 floor tiles + thin overhead frame beams.
- Free player movement under the 8 outer squares.
- Manual serve from center into the player's **current** square.
- Server-driven deterministic ball arc with phase machine.
- Telegraph: floor shadow disc, shrinking descent ring (bottoms out at frame-plane crossing),
  highlighted target-square edge.
- Angled court camera locked facing center.
- Physical contact volley: jump → hit-zone/ball overlap → **reflection-based** outgoing direction
  + small steering during a short contact dwell.
- Binary success (contact or whiff). Server-authoritative.

### Deferred (NOT in M1)
| Concern | Milestone |
|---|---|
| Timing tiers, scatter refinement of the same contact | M2 |
| Rotation, ranks, dethrone | M3 |
| Bots filling all 9 squares | M4 |
| Networking hardening / full anti-cheat | M5 |
| Stats, leaderboard, audio/VFX polish, mobile tuning | M6 |

In M1 the "King" is only an **auto-serve origin** at center — there is no occupant, no bot, no
rotation. No scoring.

## 3. Arena & dimensions (`GridConfig` defaults — all tunable)

| Param | Default | Notes |
|---|---|---|
| `squareSize` | 14 × 14 studs | Room to move + jump; tune to avatar scale |
| Court footprint | 42 × 42 studs | 3×3 of squares |
| `floorThickness` | 1 stud | Greybox tiles |
| `frameHeight` | **measured jump-reach** (≈13–14 studs to hand-top at R15 apex) | Contact plane = top of jump reach; measured precisely in greybox, then stored |
| `ballRadius` | 1 stud (2-stud sphere) | |
| `apexHeight` | ~30 studs | Ball arcs well above frame, descends visibly through it |
| `descentWindow` | ~1.2 s | Apex → frame-plane crossing; the readable telegraph window |
| `hitZoneRadius` | ~2.5 studs | Sphere at hands/upper body at jump apex |
| `contactDwell` | ~0.15 s | Window during which steering applies |
| `steerCone` | ±15° | Max horizontal nudge from held aim/move input |
| `lobPowerV` | fixed | Vertical impulse: clears frame, ~1 square horizontal reach |

Frame at jump-reach height is the central tuning relationship — see §5.

## 4. Movement & serve

- Player walks freely under the 8 outer squares (center is the serve origin, no standing there).
- `MatchService` tracks **which square the player is currently under** (XZ → cell lookup).
- Pressing **Serve** fires the ball from center into the player's current square. If the player is
  not under an outer square, serve is ignored (or targets the last valid square — tunable).
- Loop: position under a square → serve → read → jump-volley → ball lobs back up → reposition.

## 5. Ball lifecycle (server-authoritative, deterministic)

```
Serve → InFlight → Descending(targetSquare) → [ Contact → InFlight(new arc) ] | [ Whiff → land/reset ]
```

- Server computes a parabola from center to the target square center at `frameHeight`, apex
  `apexHeight`. Clients receive replicated trajectory params and render arc + shadow locally.
- **Contact plane = frame plane = jump reach.** "Ideal contact" is the instant the descending ball
  crosses the frame plane over the player's square. The descent ring reaches **minimum size** at
  that instant — it is the jump cue.
- Server never hands ball ownership to the client (PRD §11.1). Contact is resolved by **server-side
  geometry**, not the physics engine, preserving determinism.

## 6. Contact model (the heart of M1)

A volley succeeds only if BOTH hold at the frame-plane crossing:
1. **Reach:** the player is jumping and their hit-zone is at/near frame-plane height.
2. **Touch:** the hit-zone sphere overlaps the ball.

No overlap → **whiff** (ball passes through, falls, resets). Overlap → **contact**, resolved as:

- **Base direction = reflection / bump.** Compute the contact normal (vector from the contact
  point on the hit-zone through the ball center). The ball deflects **opposite the side contacted**:
  meet the ball on its lower-left → it sails upper-right; centered contact → straight, high lob.
  This rewards positioning the jump under a chosen side of the ball.
- **Steering ("the stir"):** during `contactDwell` (~0.15 s), the player's held aim/move direction
  rotates the outgoing horizontal vector by up to `steerCone` (±15°). Fine guidance only.
- **Vertical:** fixed `lobPowerV` for M1 (clears frame, ~1 square of horizontal travel). Outgoing
  arc then re-enters the normal ball lifecycle (in M1 it simply lobs up and lands; no second
  occupant yet).

Server is the sole authority on overlap, contact normal, and resulting vector. Client sends only
input intents (jump time, held steer direction); server validates against authoritative ball +
character state.

## 7. Telegraph & camera

- **Floor shadow disc** tracks the ball's live XZ inside the target square — primary "where" cue.
- **Descent ring** on the shadow shrinks to minimum at the frame-plane crossing — primary "when"
  cue / jump timing.
- **Target-square edge highlight** marks the player's responsibility zone.
- **Camera:** angled third-person, locked facing court center, tilted up enough to see the grid and
  the ball apex without neck-craning framing (PRD §8).

## 8. Module breakdown (M1 subset — names match PRD §11.2 so later milestones slot in)

| Module | M1 responsibility |
|---|---|
| `GridConfig` (shared) | All dimensions/tunables in §3 |
| `BallController` (server) | Arc compute, phase machine, trajectory replication, frame-plane crossing detection |
| `MatchService` (server, stub) | Player→current-square lookup, serve trigger; no rotation/scoring |
| `HitResolver` (server, minimal) | Hit-zone/ball overlap test, reflection direction, steering, whiff/contact outcome |
| `ClientInput` (client) | Serve intent; jump + held steer direction intent |
| `ClientRender` (client) | Arc, shadow, descent ring, square highlight, camera |

## 9. Data model (M1 sketch)

```lua
type BallState = {
  phase: "Serve" | "InFlight" | "Descending" | "Resolved",
  origin: Vector3,
  target: Vector3,          -- target square center at frameHeight
  apex: number,
  launchTime: number,
  targetCell: string,       -- "N","NE",... (M1: the player's current square)
}

type ContactIntent = {
  jumpTime: number,         -- client press timestamp (validated vs server ball clock)
  steerDir: Vector3?,       -- held horizontal aim/move at contact, optional
}
```

(No `PlayerRecord`/ranks in M1 — that's M3.)

## 10. Authority & anti-cheat (M1 level)

- Server owns ball state, overlap test, and outgoing vector. Clients send intents only.
- Validate jump/contact timestamps against the server ball clock with a latency-tolerant band;
  discard impossible inputs. Steering is clamped to `steerCone` server-side.
- Full hardening is M5; M1 does the basics so the mechanic is honest.

## 11. M1 build sub-steps

1. **Arena + config:** greybox 3×3 floor + frame beams from `GridConfig`. Measure and store
   `frameHeight` = actual jump reach.
2. **Ball + arc:** server arc center→square, phase machine, replicated render of the ball.
3. **Telegraph:** floor shadow + shrinking descent ring + square-edge highlight + court camera.
   *Checkpoint: is the "where/when" readable?*
4. **Serve + movement:** player→current-square lookup; Serve fires into it.
5. **Contact volley:** hit-zone, overlap test, reflection direction, steering dwell, whiff/contact.
   *Checkpoint: does the contact feel good and does touch point clearly change direction?*

## 12. Definition of done

All four success criteria in §1 are demonstrably true in a live Studio playtest, with the telegraph
readable and the contact direction visibly governed by where the ball is struck. Numbers are
tunable in `GridConfig`. Then proceed to M2 (timing tiers + scatter on top of this same contact).
