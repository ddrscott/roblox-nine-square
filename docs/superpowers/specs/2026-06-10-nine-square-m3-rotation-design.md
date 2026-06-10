---
title: "9 Square in the Air — Milestone 3: Full Grid, Rotation & Dethrone"
type: design-spec
parent_prd: "9 Square in the Air - Roblox PRD (v0.1)"
status: draft
version: 0.1
platform: Roblox (Luau)
author: Scott Pierce
last_updated: 2026-06-10
---

# Milestone 3 — Full Grid, Rotation & Dethrone

## 0. Context
Scopes **only M3** (PRD §15.3, grounded in §4 rotation + §6 faults). Builds on M1's physical
**contact volley** (M2 was folded into the M1 contact model; scatter dropped). M3 turns "a ball you can
volley" into the **king-of-the-hill loop**: nine ranked squares, the King serves, single-touch volley,
a fault rotates everyone toward the throne, and a King fault is the **dethrone** moment.

**M3 scope decision (agreed):** the eight non-human squares are **static DUMMY occupants** — placeholders
that hold a square and auto-fault when the ball lands on them. This proves the *system* (ownership,
rotation, dethrone, serve flow) solo-testably, with **no AI**. Smart volleying/serving **bots are M4**.

## 1. Goal & success criteria
**Goal:** one human plays as a ranked occupant alongside 8 dummies; the King serves into a square; a
ball to the human's square is volleyed (M1 contact); a ball to a dummy's square — or a human fault —
attributes the fault correctly and **rotates** everyone one step toward the King; the human climbs and
can become King; a King fault is a **dethrone**.

**M3 is done when:**
1. All 9 squares have an owner at a rank; the rank→cell map is a `GridConfig` table.
2. The King's square serves the ball into an outer square each rally (human King = physical serve;
   dummy King = server auto-serve).
3. A fault attributes per PRD §6 and triggers rotation per PRD §4.3 (faulter → tail, ranks advance
   toward King, rank 9 backfilled).
4. The human climbs ranks as others fault and can reach King; a **King fault fires a dethrone** (with an
   emphasis hook).
5. The local player's rank + the King square are indicated (minimal HUD/highlight).
6. Deterministic + server-authoritative; all numbers in `GridConfig`.

## 2. Scope
**In:** rank↔cell map; occupant/rank model (+ a queue abstraction, trivially the fixed 9 in M3); rotation
on fault; King serve (human physical / dummy auto); single-touch volley reuse (M1 contact); fault
attribution + rotation wiring; static dummy occupants; dethrone emphasis hook; minimal rank/King HUD.
**Deferred:** smart bots + difficulty (M4); networking hardening / anti-cheat (M5); stats, reign timer,
leaderboard, audio/VFX polish (M6); aim-assist (dropped — superseded by contact-aim).

## 3. Rank ↔ cell mapping (PRD §4.2)
`GridConfig.rankCells = { "C", "N", "NE", "E", "SE", "S", "SW", "W", "NW" }` — index = rank (1..9), King =
rank 1 = `C`, then the clockwise ring. `cellForRank(r) = rankCells[r]`. Config table, not hardcoded.

## 4. Occupant & rotation model (new `RotationService`, or extend `MatchService`)
- `occupant = { id, isDummy: boolean, rank: number }`; `byRank[rank] = occupant`. M3 has exactly 9
  occupants (1 human + 8 dummies), so a faulter simply goes to rank 9 — but keep a small **queue
  abstraction** so M4/M5 (join/leave, >9) slot in.
- `placeAll()` — put each occupant at `cellForRank(rank)`: the human via HRP teleport (generalize the
  existing `placeAtCourt` to take a cell), dummies as a simple `Part`/`Model` standing in the cell.
- `rotateOnFault(faultRank)` — PRD §4.3: occupant at `faultRank` → tail (rank 9); ranks `faultRank+1..9`
  each advance one toward the King; re-place everyone. (With a fixed 9, this is a cyclic shift of
  ranks `faultRank..9`.) **Dethrone** iff `faultRank == 1` (rank-2 occupant becomes King).

## 5. Serve flow (PRD §3.2, §5.5)
Each rally is served by the King (rank 1, `C`):
- **Human King:** the ball hovers at `C` (phase Live); the human jump-strikes it (M1 physical serve).
  The struck direction (contact-aim) decides the target square — i.e. the square the ball lands in.
- **Dummy King:** after a short delay, the server **auto-serves** — launches the ball from `C` toward a
  **random outer square's** frame point (a deterministic arc), no hover.
Then the normal rally proceeds: the ball arcs to a square; that square's occupant gets one touch.

## 6. Single-touch volley + fault attribution (PRD §6)
- The occupant of the square the ball descends into gets **one** contact (M1 collision already gives one
  hit per approach — the ball is repositioned out of the hit-sphere). A guard against a second contact in
  the same turn (double-touch) can be a light check; strict enforcement may defer to M4/M5.
- **Dummy squares can't volley** → the ball lands on the floor in that square → that dummy **faults**
  (floor fault, the occupant of the landing square). So any ball into a dummy square ends the rally.
- Map the existing `BallController.onLand(landed, struck)`:
  - `landed ~= nil` and `landed ~= struck` → **floor fault**: occupant of `landed` faulted (failed to
    return) → `rotateOnFault(rankOf(landed))`.
  - `landed == struck` → **self-square fault**: the hitter (occupant of `struck`) → `rotateOnFault(rankOf(struck))`.
  - `landed == nil` (out of bounds) → **out-of-bounds fault**: the hitter → `rotateOnFault(rankOf(struck))`.
- After rotation, the (new) King serves the next rally (§5).

## 7. Dethrone & minimal HUD
- **Dethrone:** when `rotateOnFault(1)` runs, fire an emphasis hook (M3: a clear print + the King-square
  flash + a sound stub; full VFX/banner is M6). Rank-2 becomes King.
- **HUD (minimal):** show the local player's current rank (e.g. `Rank 4` / `KING`) and highlight the King
  square (or the local player's own square). Reuse the existing client highlight/telegraph.

## 8. Modules touched
| Module | M3 work |
|---|---|
| `GridConfig` (shared) | `rankCells` map (+ any new tunables: serve delay, dummy look) |
| `RotationService` (server, new) or `MatchService` | occupant/rank model, `placeAll`, `rotateOnFault`, dummies |
| `BallController` (server) | reuse; add a serve-to-target launch for the dummy-King auto-serve |
| `NineSquareServer` (server) | wire `onLand` → fault attribution → `rotateOnFault` → next King serve; human-vs-dummy serve branch |
| `MatchService` | build the dummy occupant parts |
| client | minimal rank/King HUD + highlight |

## 9. Build order (incremental)
1. **Rank map + occupant model + dummies + `placeAll`** — `rankCells`, the occupant/rank table, build/
   place 8 dummies + the human at their cells. (Static: see them stand in their squares.)
2. **Rotation** — `rotateOnFault` (PRD §4.3) + re-place; a temporary manual trigger to watch ranks shift
   and the dethrone case.
3. **Serve + fault wiring** — King serve (human physical / dummy auto-serve to a random square); wire
   `onLand` → attribute fault → `rotateOnFault` → next serve. The full loop runs with dummies.
4. **Dethrone emphasis + minimal HUD** — dethrone hook; local rank / King indicator.

## 10. Definition of done
The rotation loop runs solo (human + 8 dummies): the King serves, faults rotate everyone correctly per
PRD §4.3, the human can climb to King, and a King fault is a dethrone. Deterministic, server-authoritative,
tunable in `GridConfig`. Then **M4** replaces the dummies with bots that actually serve/volley.

## M3 Acceptance
**Date:** 2026-06-10 · **Status:** PASS (all §1 criteria) · **Verified in:** Studio Play, place "9 Square Beta"
(server-authoritative; build steps 1–4 deployed via the robloxstudio MCP).

Pass/fail against §1 "M3 is done when":

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | All 9 squares owned at a rank; rank→cell map is a `GridConfig` table | PASS | `GridConfig.rankCells`; `RotationService.byRank` holds 9 occupants (1 human + 8 dummies). Console: `rotation occupancy ready (human rank 9 / NW, dummies ranks 1..8)`. |
| 2 | King's square serves each rally (human physical / dummy auto-serve) | PASS | Dummy King auto-serves: `dummy-King auto-serve C -> NE`. Human-King hover-serve branch in `serveNextRally` (`isHumanKing`). |
| 3 | Fault attributes per PRD §6 + rotates per §4.3 | PASS | `FAULT (floor / unreturned) cell=NE` → `attributing fault: cell=NE rank=3 occupant=dummy3` → `rotateOnFault(3): dummy3 -> rank 9; ranks 4..9 advanced toward King`. |
| 4 | Human climbs to King; **King fault fires a dethrone** (emphasis hook) | PASS | Human climbed NW(9)→W(8)→…→Rank 4 across rotations. King fault: `FAULT … cell=C` → `rotateOnFault(1)` → `DETHRONE: new King is dummy2` → emphasis `DETHRONED -- dummy2 takes the throne (rank 1 / C)` (`MatchService.flashCell("C")` + distinct chime). |
| 5 | Local player's rank + King square indicated (minimal HUD/highlight) | PASS | `RankHud` LocalScript: top-centre pill shows live `Rank N` / `KING` from the replicated `Rank` attribute; gold `SelectionBox` on `Floor_C` marks the throne. Client verify: `attr=7 hudText=Rank 7 kingBoxAdornee=Workspace.NineSquare.Floors.Floor_C`. Screenshot confirms "Rank 4" + gold King box on C. |
| 6 | Deterministic + server-authoritative; numbers in `GridConfig` | PASS | Rank owned server-side (`RotationService` → `plr:SetAttribute("Rank", …)`); client only reads/displays. Serve/rotation/fault decided on the server; clients send no rotation input. Tunables (`serveDelay`, `serveArcApex`, `rankCells`, dummy look) in `GridConfig`. |

**Step 4 changes (this commit):** `RotationService` sets the human's `Rank` attribute on every rank change
(injected `_setHumanRank`, called from `placeAll` / `placeHuman` / `rotateOnFault`; added `humanRank()`).
`NineSquareServer` wires the rank replication + the dethrone emphasis (`flashCell("C")` + chime + console
line) and seeds `Rank` on (re)join. New client `RankHud.client.luau` renders the rank pill + King-square box.

**M3 COMPLETE.** Next: **M4** replaces the 8 static dummies with bots that actually serve and volley.
