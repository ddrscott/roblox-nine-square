# Cut the side windows into the walls (real openings) for natural light

## Problem
The gym side windows are fake: `WallE`/`WallW` are SOLID parts, and `WindowE`/`WindowW` are thin Glass
strips glued onto the solid wall surface — so no light passes through (it's just decoration on an opaque
wall). Scott wants the windows **actually cut out** (real openings) so natural outdoor light comes in.

## Decision (from Scott)
**Cut out the existing two side windows (E/W) as real openings with light-passing glass** — same placement
as now, modest extra daylight. (Not enlarging/adding more; not fully open — glass panes in real holes.)

## How (you can't hole a single part — frame the wall around the gap)
- Today (in `MatchService.buildGym`): `WallE`/`WallW` = `Vector3.new(0.8, H, L)` solid; the window is
  `WindowE`/`WindowW` = `Vector3.new(0.3, 7, L-20)` glass at `y=30` on the wall face. So the opening should
  be: centered at **y=30, 7 tall, (L-20)=50 long** along Z, on each side wall (x = ±W/2).
- Rebuild each side wall (`WallE`, `WallW`) as a **frame of solid panels around a rectangular hole**: a
  bottom panel (below the window), a top panel (above), and the two end panels (beyond the window along Z) —
  leaving a genuine GAP where the window is. Then place a **Glass pane in the gap** (`Material=Glass`,
  `CastShadow=false`, a light transparency so it reads as glass) — or leave the gap open if glass still
  blocks the light too much. The point: NO opaque part behind the glass, so outdoor light/sky reaches the
  interior. Remove the old glued-on `WindowE`/`WindowW` strips and the old solid `WallE`/`WallW`.
- Keep dims as `GridConfig` tunables (window center Y, height, length, glass transparency).

## CRITICAL — don't break these (they target walls by NAME):
- **Camera wall-fade** (`NineSquareClient`): it fades the gym walls (whitelist `WallE/W/N/S`, `Ceiling`)
  when the camera clips them. If you split `WallE` into multiple panels, the fade MUST still cover them —
  either keep them grouped under a Model/Folder named `WallE`/`WallW`, or name the panels with a `WallE`/
  `WallW` prefix and make the fade match the prefix. Verify the windowed walls still fade for a seated
  player whose camera crosses them.
- **Locked shell** (just added): the gym walls are `Locked=true` (click-through in Studio). The new wall
  panels + glass must also be `Locked=true` (the glass pane can stay unlocked if you want it tweakable, but
  the solid frame panels should be locked like the rest of the shell).
- **Build-once:** `buildGym` returns early if `Gym` exists, so the new windowed walls only apply on a fresh
  build. Update the CODE (fresh places) AND rebuild the windowed E/W walls in the CURRENT place via the MCP
  (replace the existing solid `WallE`/`WallW` + `WindowE`/`WindowW` with the new paneled walls + glass), so
  Scott sees it now. Don't disturb the rest of the (tweaked) Gym.

## Acceptance criteria
- `WallE` and `WallW` have REAL window openings (an actual gap in the wall) with a glass pane — no solid
  wall behind the glass. The old glued-on window strips are gone.
- **More natural light visibly enters** through the openings (interior reads brighter / light comes through
  the holes vs the old solid wall — confirm via a before/after `screen_capture` or a brightness check).
- The camera wall-fade still fades the windowed walls (incl. the new panels) when clipped; the new frame
  panels are `Locked` (click-through). 
- No gameplay/collision regression; build-once preserved; applied to the current place AND the default for a
  fresh build. Verified via the MCP. Studio left in Edit.

## Relevant files
- `src/server/MatchService.luau` — `buildGym`: rebuild `WallE`/`WallW` as paneled walls with a real window
  gap + glass; remove the solid wall + glued `WindowE`/`WindowW`; `Locked=true` on the frame panels.
- `src/client/NineSquareClient.client.luau` — the wall-fade whitelist: ensure the new windowed-wall panels
  are still faded (group/prefix match).
- `src/shared/GridConfig.luau` — window opening tunables (center Y, height, length, glass transparency).
- `README.md` — note the windows are now real cut-outs (optional).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output`; `screen_capture` from inside + outside to
  confirm the hole + light; check the fade by sampling the panels' transparency when the eye clips them.
  Leave Studio in Edit.)

## Constraints
- Build/visual change ONLY — don't change gameplay, the court, the ball/physics, rotation, or scoring. The
  windows are on the gym SIDE walls (above the court, players can't reach them) — keep glass out of the
  ball/player COURT collision sets (it's a gym wall, not under `NineSquare.Frame`). Preserve the wall-fade,
  the locked shell, and build-once. Tunables in `GridConfig`.
