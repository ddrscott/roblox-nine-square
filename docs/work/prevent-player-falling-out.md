# Prevent the player from falling out of the building (find the gap + seal + safety net)

## Problem
A player can FALL OUT of the building. Find HOW it happens, seal the gap(s), and add a safety net so it
can never happen again (court players AND gallery/foyer spectators).

## Investigate — likely culprits (confirm which)
- **Cut-out windows (court):** `WallE`/`WallW` are now frames of panels around a window gap, and the gap is
  sealed only to the BALL — the just-added `WallE_Barrier`/`WallW_Barrier` are `CanCollide=false` (ball-only,
  via `_collide`), so they DON'T stop a PLAYER. The window is at ~y26.5–33.5; a court player normally can't
  reach that height, BUT dash + double-jump/flip (dashSpeed 40 + flip up/forward) carries real momentum/height
  — check whether a player can dash/flip up to and OUT THROUGH a window opening.
- **Gallery foyer (spectators):** the foyer walls (`GalWall*`) were raised to ~24, but dash+flip momentum
  may clear them; and check for gaps/seams (floor-ring outer edges, opening corners, wall/floor joins, the
  roof line). A roaming spectator could pop over or slip through.
- **Seams / openings:** the gym ceiling opening (over the court — likely unreachable at y50, but verify), any
  gap where walls don't meet the floor, the gym↔gallery junction.
- Reproduce in Play (dash/flip toward each window + the foyer walls/edges) to pin the actual exit.

## Fix
### A. Seal the gap(s) for PLAYERS
- Make the window openings **player-impassable**: add `CanCollide=true` collision across each window gap for
  players (a separate player-collision barrier, or set the ball-barrier collidable — but keep it INVISIBLE
  and OUT of the ball/court collision sets so it doesn't change ball feel; it just blocks the character). The
  window stays visually open (light + view through it).
- Ensure the **foyer is fully enclosed** against dash/flip: raise/cap the gallery walls (and/or add an
  invisible ceiling/lip) so a spectator can't launch over them, and close any floor-edge/seam/corner gap.
- Apply to the build (build-once) AND a one-time pass on the current persisted Gym/Gallery so it takes effect
  now.

### B. Safety net — "fell out" recovery (catch-all, server-side)
- A server Heartbeat check per player: if a seated/spectating player's HRP drops below a floor threshold
  (e.g. well below the court floor) OR leaves the building's XZ footprint by a margin, **teleport them back
  to their spawn** — seated → their court cell (`placeAtCell`/`cellOfPlayer`), spectator/lobby → the gallery
  spawn (`parkSpectator`). This GUARANTEES no infinite fall even if a specific gap is missed (mirrors the
  ball-escape watchdog, but for players). Cheap, debounced, server-authoritative.

## Acceptance criteria
- A court player CANNOT get out through a window (or anywhere) via dash/flip/jump — verified by trying in
  Play; the windows still look open.
- A spectator CANNOT leave the foyer (walls/edges/opening all contain them, even with dash+flip) — verified
  by trying in Play.
- Safety net: if a player somehow ends up below the floor / outside the footprint, they're teleported back to
  their spawn within a moment (no falling forever) — verified by injecting an out-of-bounds HRP position.
- No regression to gameplay, ball feel, cameras, the windows' open look, or the lobby/seating flow. Studio
  left in Edit.

## Relevant files
- `src/server/MatchService.luau` — window player-collision barrier(s) in `buildWindowedWall`; gallery
  enclosure (raise/cap `GalWall*` / add an invisible lip/ceiling, close seams) in `buildGallery`; build-once
  + one-time pass on the current place.
- `src/server/NineSquareServer.server.luau` — the per-player "fell out" Heartbeat recovery (teleport seated →
  cell / spectator → gallery spawn); reuse `placeAtCell` / `rotation:cellOfPlayer` / `parkSpectator`.
- `src/shared/GridConfig.luau` — fall-threshold Y / footprint-margin tunables; any barrier dims.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play try to dash/flip out each window + over the
  foyer walls, and inject an out-of-bounds HRP to confirm the teleport-back. `screen_capture` works. Leave
  Studio in Edit.)

## Constraints
- Don't change the ball physics / in-court feel, gameplay, cameras, the windows' open LOOK, or the
  lobby/seating flow. Player-collision barriers stay INVISIBLE and OUT of the ball/court collision sets
  (block characters only). Safety net is server-authoritative + cheap. Tunables in `GridConfig`.
