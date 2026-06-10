# M3 step 1: rank↔cell map + occupant model + dummy occupants + placeAll

See the M3 design spec: `docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md` (§3, §4, §9
build order step 1). This is the FOUNDATION only — rotation, serve, and fault wiring are later steps.

## Goal
Stand up the 9-rank occupancy: a rank→cell map, an occupant/rank model, 8 static **dummy** occupants
plus the human, all placed at their squares. No rotation/serve logic yet — just see everyone standing in
their square.

## Build
1. **`GridConfig.rankCells`** (PRD §4.2): `{ "C", "N", "NE", "E", "SE", "S", "SW", "W", "NW" }` — index =
   rank (1..9), King = rank 1 = `C`. Add a `cellForRank(r)` helper (or just index the table).
2. **Occupant/rank model** — a new server module `src/server/RotationService.luau` (Studio:
   `ServerScriptService.NineSquare.RotationService`), OR extend `MatchService` if cleaner. Hold
   `byRank[rank] = { id, isDummy, rank }`. M3 = exactly 9 occupants: the human at **rank 9** (entry
   square, PRD §7) and **dummies at ranks 1..8** (so the King, rank 1/C, starts as a dummy). Keep a tiny
   queue abstraction so M4/M5 can extend, but M3 just uses the fixed 9.
3. **Dummy occupants** — build 8 simple, clearly-non-player markers (e.g. a coloured capsule/cylinder
   `Part` or a small `Model`) that stand in a cell at floor level. A `RotationService` (or
   `MatchService`) function creates/owns them in a `Dummies` folder. They don't move; cosmetic +
   non-colliding with the ball is fine (don't add them to `BallController._surfaces`).
4. **`placeAll()`** — position every occupant at `cellForRank(rank)`:
   - human: teleport the HRP (generalize the existing `placeAtCourt` in `NineSquareServer` to take a cell,
     e.g. `placeAtCell(char, cell)`), not just `C`.
   - dummies: move their part/model to the cell.
5. **Wire into bootstrap** (`NineSquareServer`): build the rotation state on start (human rank 9, dummies
   1..8) and `placeAll()`; place the human at their assigned cell on `CharacterAdded` too (replacing the
   current always-centre placement — though keep the ball's centre serve point for now; serve wiring is a
   later step). Don't break the existing ball/contact loop.

## Acceptance criteria
- All 9 squares are occupied: the local human stands in the **rank-9 (NW)** square; 8 dummies stand in the
  other squares including the King (C). Verified by a Play screenshot showing dummies in their cells.
- `GridConfig.rankCells` drives the placement (change the table → placement follows).
- The existing M1 contact/ball behaviour is unaffected (the ball still hovers/serves at centre for now;
  faults still print — rotation wiring comes in step 3).
- Server-authoritative; all data in `GridConfig` / the service.

## Relevant files
- `src/shared/GridConfig.luau` — `rankCells` (+ `cellForRank` if you add it).
- `src/server/RotationService.luau` (new) — occupant model, dummies, `placeAll`. (Or extend `MatchService`.)
- `src/server/MatchService.luau` — may host the dummy-building if you prefer it with the scene builders.
- `src/server/NineSquareServer.server.luau` — generalize placement to a cell; build + place the rotation
  state on start / spawn.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; new
  ModuleScript deploys via `multi_edit` create or chunked `script.Source`; leave Studio in Edit).

## Constraints
- FOUNDATION ONLY — do NOT implement rotation-on-fault, the King serve branch, or fault→rotation wiring
  (those are M3 steps 2–3). Just placement.
- Don't break the existing ball/contact loop, the player no-trip fix, camera, or scene. Dummies must not
  interfere with the ball (keep them out of `BallController._surfaces`, CanCollide false).
- Keep it server-authoritative; tunables/config in `GridConfig`.
