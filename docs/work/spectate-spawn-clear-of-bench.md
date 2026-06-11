# Spectate spawn: place/orient watchers so the bench isn't in the camera (KEEP roam)

## Correction / context
Supersedes the "look DOWN at the court (fixed overview)" idea — that was a MISREAD. Scott wants spectators
to **keep walking around the foyer while they wait** (the roaming third-person `Custom` camera from commit
`a1e5e5c` STAYS). The only problem: a watcher **spawns right next to the gallery bench**, and the
third-person camera sits BEHIND the player, so the red bench backrest fills the view (Scott's screenshot).
Fix the SPAWN placement/orientation so the camera has a clear view — do NOT change the camera type.

## The cause
The spectator spawn (`G.specSpawnOffset`, used in `parkSpectator` + the gallery `GallerySpawn`) sits on the
SOUTH gallery band, right in front of the bench (`GalBench`, south band). With the default third-person
camera behind the player, "behind" = toward the bench → the bench blocks the view.

## Fix
- KEEP the `Custom` (default third-person, roam) spectator camera and KEEP movement working (don't anchor,
  don't switch to a fixed/scripted spectator camera). Spectators walk the foyer while waiting.
- Reposition / reorient the spectator spawn so the camera (which trails BEHIND the player) is NOT looking
  through the bench (or a wall), and the player faces toward the court/opening:
  - Move the spawn OFF the south bench band — onto a band WITHOUT the bench (north/east/west) and/or nearer
    the opening edge, and face the player toward the central OPENING / court (so they see the play area
    across/through the opening and the camera-behind is over open gallery floor, not the bench).
  - Mind the perimeter walls: the gallery is a ring with walls + a central hole, so don't spawn so close to
    a wall that the trailing camera clips it. Facing ACROSS the opening (toward court center) from a
    bench-free band edge generally gives the cleanest trailing-camera view.
  - This is a spatial tweak: the worker should try a placement, screenshot the spectator view, and adjust
    `specSpawnOffset` (+ the facing in `parkSpectator`) until the camera shows the court/opening with the
    bench (and walls) OUT of the way.

## Acceptance criteria
- While spectating (the default lobby state on join), the third-person camera shows a clear view toward the
  court / opening — the **bench is NOT filling/blocking the camera**, and it's not jammed against a wall.
  Confirm with a `screen_capture` while Spectating=true.
- The spectator can still **walk around** the foyer (Custom camera, not anchored, Humanoid not Seated). The
  Join Game button + lobby flow + bench-seat disable are unchanged.
- Seated-player camera/flow unchanged. Studio left in Edit.

## Relevant files
- `src/server/NineSquareServer.server.luau` — `parkSpectator`: spawn position (`G.specSpawnOffset`) +
  facing so the trailing camera clears the bench/walls and faces the court.
- `src/shared/GridConfig.luau` — `specSpawnOffset` (tune the spawn spot).
- `src/server/MatchService.luau` — `GallerySpawn` position (keep it consistent with the new spectator spawn,
  on a bench-free band).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client camera on the
  Client datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` while spectating to confirm the bench/walls are clear of the camera + the court/opening
  is in view; check the Humanoid can still move. Leave Studio in Edit.)

## Constraints
- Spawn placement/orientation ONLY — KEEP the roaming `Custom` spectator camera and working movement; do NOT
  switch to a fixed look-down camera, don't anchor the player, don't change the lobby/Join flow, the
  bench-seat disable, occupancy, gameplay, or the server loop. Reuse `specSpawnOffset` as the tunable.
