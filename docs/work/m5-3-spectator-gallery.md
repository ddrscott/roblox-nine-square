# M5.3 — Upper-floor spectator gallery (3D assets)

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`. Pairs with **M5.2**
(spectators spawn here).

## Problem
Overflow players need a place to watch. Scott wants an **upper-floor viewing area** above the gym with an
opening over the court — "knock out a window from the upper floor" — and wants it built from **3D assets**
so it's easy to tweak (he can't edit Studio himself).

## What to build
- An **upper floor / mezzanine** above the existing gym (the gym is square `W,L,H` built in
  `MatchService.buildGym`). Add a second level / gallery ringing or overlooking the court.
- A **viewing opening over the court** — "knock out a window": an opening in the gallery floor or the gym
  wall so spectators look straight DOWN onto the 9-square below (clear line of sight to the match).
- **Spectator spawn** in the gallery: a `SpawnLocation` (or scripted spawn point) so M5.2's spectators
  appear here and can walk the gallery + watch through the opening. Seated players still spawn at their
  seat.
- **Use creator-store 3D assets** (via the MCP `search_creator_store` / `insert_from_creator_store`):
  railings, window frames / glass, bleacher or bench seating, light decor — something tweakable, not bare
  greybox. Keep volumes/positions as tunables (or clearly-named instances) so Scott can nudge them.

## Acceptance criteria
- There's a walkable upper gallery above the gym with an opening that overlooks the 9-square; standing in
  the gallery you can see the match below.
- Spectators (M5.2) spawn in the gallery and can watch; the gallery is built from inserted 3D assets
  (railing/windows/seating), not just plain blocks.
- The gallery + assets are OUTSIDE the court collision sets — they never feed the ball or player collision
  and don't change gameplay. Verified in Play via the MCP (screenshot the gallery + the overlook; confirm
  no console errors / failed asset loads). Studio left in Edit.

## Relevant files
- `src/server/MatchService.luau` — `buildGym` (extend with the upper floor / gallery + opening), plus the
  spectator `SpawnLocation`. Keep the build-once pattern.
- `src/shared/GridConfig.luau` — gallery dimensions / opening size / spawn position tunables.
- Inserted 3D assets via the robloxstudio MCP creator store (railing/windows/benches/decor).
- Build/verify via the MCP (mode flip-flops — `get_studio_state` first; `screen_capture` the gallery;
  `get_console_output` for asset-load errors; leave Studio in Edit).

## Constraints
- The gallery/assets must NOT enter the ball (`BallController._surfaces`) or player collision — purely
  environmental, above/around the court. Don't block the existing court camera or the wall-fade occlusion
  for seated players (it's an UPPER area; make sure seated-player cameras/gameplay are unaffected). Build
  with 3D assets so it's tweakable; keep it server-built (Scott can't hand-edit Studio).
