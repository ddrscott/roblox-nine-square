# Floor rank-number decals + on-player jersey labels (replace over-grid nameplates)

## Problem
M5.6 put floating name labels (`BillboardGui` nameplates) OVER each grid square. Scott doesn't like them.
Instead:
1. The RANK of each square should read as a **large number on the FLOOR**, centered on each panel.
2. Player/bot IDENTITY should be a **label attached to the occupant** (a "jersey"), so it moves with them
   as they rotate.

## Decisions (from Scott)
- **Floor:** a simple **large rank number** decal centered on each of the 9 floor panels. The number is the
  square's RANK from `GridConfig.rankCells` — King/center **C = 1**, then outward: N=2, NE=3, E=4, SE=5,
  S=6, SW=7, W=8, NW=9. These are STATIC per panel (rank↔cell is fixed; occupants rotate, the numbers
  don't).
- **Jersey:** each occupant wears a label attached to THEM — **humans show their display name**, **bots show
  a letter** (A, B, C, …). The jersey moves with the occupant as they rotate through ranks. King still
  clearly marked (e.g. gold + crown on the jersey).
- **Remove** the old over-grid `BillboardGui` nameplate system from M5.6.

## Build
### Floor rank numbers (MatchService)
- In `MatchService.buildArena` (where the floor markers/cells are built), add a **large number per cell**
  centered on the panel, facing UP — a `SurfaceGui` on the floor part's **Top** face with a big `TextLabel`
  showing the rank number (no image upload needed; crisp + tweakable), OR a `Decal` if cleaner. Centered on
  each cell, sized to fill most of the panel but not overpower the grid lines.
- Number = `GridConfig.rankForCell(cell)` for each cell. The center "1" reads as the King throne.
- Keep it readable but tasteful (think a painted court number) — colour/opacity/size as `GridConfig`
  tunables (e.g. `floorNumberColor`, `floorNumberSizeFrac`, `floorNumberTransparency`). Build-once with the
  arena; never enters the ball/player collision sets.

### Jersey labels on occupants (RotationService)
- **Remove** the M5.6 over-grid Nameplates folder/system (the `workspace.NineSquare.Nameplates`
  `BillboardGui`-per-cell + its relabel-on-occupancy logic).
- Give each occupant a jersey label **attached to the occupant's rig** (a `BillboardGui` on the rig's
  Head/Torso, or a `SurfaceGui` on the torso for a true jersey look — billboard is more readable from the
  court camera; your call, keep it legible from the high angle). It moves with the rig automatically.
  - **Human occupant:** label = the player's `DisplayName`.
  - **Bot occupant:** label = a **stable letter** (A, B, C, …) assigned per bot so it's consistent while
    that bot is on the board.
  - **King** (rank 1 / C): mark the jersey clearly (gold tint + 👑) so the King reads at a glance.
- The jersey is parented to / follows the rig, so as occupants rotate cells the label travels with them
  (no per-cell relabeling needed — it's attached to the occupant, not the square).
- Server-built + server-authoritative (don't trust the client for who's King / who's who); replicates to all
  clients incl. spectators in the gallery.

## Acceptance criteria
- Each floor panel shows a large, centered rank number (center = 1 = King, 2–9 outward per `rankCells`),
  readable from the court camera, not overpowering the grid.
- The old over-grid floating nameplates are GONE.
- Every occupant wears a jersey label that moves with them: humans show their name, bots show a letter; the
  King's jersey is clearly marked. As a fault rotates occupants, each jersey travels with its occupant.
- No regression to gameplay, collision, the gallery, or the spectator HUD. Verified via the MCP. Studio left
  in Edit.

## Relevant files
- `src/server/MatchService.luau` — `buildArena`: add the floor rank-number decals/SurfaceGui per cell
  (build-once, out of collision sets).
- `src/server/RotationService.luau` — REMOVE the M5.6 over-grid Nameplates system; add the per-occupant
  jersey label (human name / bot letter, King-marked) attached to the rig; assign + track bot letters.
- `src/shared/GridConfig.luau` — floor-number tunables (color/size/transparency) + jersey tunables
  (size, King tint); `rankForCell` already exists.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output` + instance/attribute assertions: each cell's
  floor number text = its rank, each rig has a jersey label with the right text, King marked. NOTE:
  `screen_capture` has been timing out this session — try it, but rely on instance assertions if it fails.
  Leave Studio in Edit.)

## Constraints
- Visual only — don't change occupancy/seating/queue/physics/rotation logic, just how rank + identity are
  shown. Floor numbers + jerseys stay OUT of the ball/player collision sets. Server-authoritative labels.
  Keep it simple + tweakable (tunables in `GridConfig`).
