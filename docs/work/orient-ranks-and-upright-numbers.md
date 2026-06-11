# Orient the grid: worst rank at lower-right + upright floor numbers (camera common-sense)

## Problem
From the default court camera the rank layout reads "wrong." The worst/entry rank (rank 9) currently sits
at the **NW cell = upper-LEFT** of the screen, and the floor number decals aren't necessarily upright from
the camera. Common-sense for this camera is: the **worst rank in the lower-RIGHT**, and the numbers
**readable right-side-up**. (Purely presentational — gameplay is symmetric — but it should feel natural.)

## Camera geometry (the basis for "lower-right")
Default court cam: `camFarEye ≈ origin+(0,42,38)` looking at `origin+(0,7,0)` → camera is on +Z looking
toward −Z. So on screen: **right = +X (East)**, **up/far = −Z (North)**, **down/near = +Z (South)**.
Therefore **lower-right = (+X,+Z) = the `SE` cell**. The worst rank (9) must land on `SE`.

## Fix
### 1. Re-seat the rank→cell ring so rank 9 = SE (keep smooth adjacent-cell rotation)
- King stays center: **rank 1 = `C`** (unchanged). Only the OUTER ring (ranks 2–9) is re-anchored.
- `GridConfig.rankCells` is currently `{ "C","N","NE","E","SE","S","SW","W","NW" }` (rank9 = NW = upper-left).
- Change it to: **`{ "C", "S", "SW", "W", "NW", "N", "NE", "E", "SE" }`** → rank9 = `SE` (lower-right).
  This keeps the ring traversal ADJACENT-cell on every advancement (verified): rank advancement
  9→8→…→2→1 walks SE→E→NE→N→NW→W→SW→S→C — up the right side, across the top, down the left, across the
  bottom, into center (each step is a neighboring square; only the King-faults-to-entry step C→SE is the
  intended "go to the back" jump). No occupant teleporting mid-ring.
- The worker should CONFIRM, after the change, that (a) rank9 resolves to SE = lower-right from the default
  camera, (b) rank1 = C center, and (c) `rotateOnFault` still moves occupants between ADJACENT cells around
  the ring (no cross-grid jumps except the dethroned King → entry). If a different equally-valid ring
  rotation reads more naturally, that's fine as long as rank9 = SE and rotation stays adjacent-cell.

### 2. Floor numbers upright from the camera
- The per-cell floor rank-number decals (SurfaceGui Top-face + TextLabel, built in `MatchService.buildArena`/
  the floor-numbers build) should read **right-side-up from the default camera**: the top of each digit
  points toward the FAR edge (−Z / North / screen-up), baseline toward the viewer (+Z), not rotated 90°/180°
  or mirrored. Orient the floor-number part/SurfaceGui accordingly (fix the part CFrame / SurfaceGui face/
  orientation so the digit is upright on screen). Verify the rendered text orientation, not just that a
  label exists.

## Acceptance criteria
- From the default court camera: rank **9 is the lower-right square (SE)**, rank **1 is center (King)**, and
  the outer ranks ring the center sensibly; every floor number reads **upright** (not rotated/mirrored).
- `rotateOnFault` still advances occupants between adjacent cells around the ring (smooth rotation; only the
  dethroned King jumps to the entry corner). Seating, serve, bot aim, King highlight, rank HUD, jerseys, and
  stats all stay consistent (they read from `rankCells`/`rankForCell`, so they should follow automatically —
  verify the King highlight + HUD still point at the right cells).
- No gameplay/physics/collision change. Verified via the MCP. Studio left in Edit.

## Relevant files
- `src/shared/GridConfig.luau` — `rankCells` reorder (the one-line source-of-truth change); `cellForRank`/
  `rankForCell` derive from it.
- `src/server/MatchService.luau` — orient the floor rank-number decals upright from the default camera
  (part/SurfaceGui orientation). The numbers themselves are `rankForCell(cell)` so they auto-update to the
  new mapping.
- Anything reading `rankCells` (RotationService rotation/seating, NineSquareServer serve, BotController aim,
  RankHud/King highlight, jerseys, StatsService) should follow automatically — VERIFY, don't re-hardcode.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output` + assertions: `rankForCell("SE")==9`,
  `cellForRank(1)=="C"`, rotation adjacency, floor-number text orientation. `screen_capture` flaky — a
  capture from the default camera would best confirm "upright + 9 lower-right"; try it, else assert
  geometrically (the SE floor-number label shows "9"; its SurfaceGui/part orientation puts text-up toward
  −Z). Leave Studio in Edit.)

## Constraints
- Presentation/orientation only — do NOT change rotation MECHANICS, seating fairness, physics, collision,
  serve, or scoring; just WHICH physical cell each rank maps to (via `rankCells`) and the floor-number text
  orientation. Keep rotation adjacent-cell. King stays center. Tunables/data in `GridConfig`.
