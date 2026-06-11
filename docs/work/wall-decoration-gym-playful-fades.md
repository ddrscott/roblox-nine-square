# Decorate the game-area walls (gym + playful) — and they must FADE with the wall

## Problem / direction (from Scott)
The gym interior walls around the court are bare. Add MORE decoration in a **mix of gym + playful**
(rec-center vibe). **Critical:** the decorations must NOT obstruct the player's camera — they must
**fade/disappear with the wall** exactly like the existing camera wall-fade does.

## What to add (gym + playful mix; gym INTERIOR walls around the court)
On the interior faces of the gym walls (`WallE`/`WallW`/`WallN`/`WallS`), add a tasteful mix, e.g.:
- **Gym/sporty:** pennant/championship banners, a wall clock, a scoreboard-style sign, base wall padding
  trim, sports posters.
- **Playful:** bright color blocking / a simple mural, fun posters, colorful pennants.
Use 3D assets (creator-store via the MCP) where they look good + built parts/decals/SurfaceGuis otherwise.
Place them on/above the wall faces, NOT in the play volume — cosmetic only, CanCollide=false, OUT of the
ball/player collision sets and NOT under `NineSquare.Frame`. Build-once (in `buildGym`) + a one-time pass on
the current persisted Gym so it shows now. Don't over-clutter; keep it readable.

## CRITICAL — decorations fade with the wall (camera occlusion)
The seated camera uses a wall-fade (`updateWallFade` in `NineSquareClient`): when the camera eye crosses to
the OUTSIDE of a gym wall, it fades that wall (matched by NAME PREFIX `WallE/W/N/S`, `Ceiling`) toward
`camWallFadeTransparency`. The new decorations sit ON those walls, so they MUST fade together — otherwise
banners/clock/posters would float in view when the wall is gone.
- Parent each wall's decorations TO/under that wall (e.g. a child `Decor` folder of the wall part, or named
  with the wall's prefix) so the fade can find them.
- EXTEND `updateWallFade` so that when a wall is obstructing, it ALSO fades that wall's decoration visuals
  with the same lerp: BaseParts → `Transparency`; `Decal`/`Texture` → `.Transparency`; `SurfaceGui` labels →
  `TextTransparency`/`ImageTransparency` (or toggle the SurfaceGui `.Enabled`). So the whole decorated wall
  (structure + banners + clock + posters + signs) vanishes/returns together as the camera crosses it.
- Verify: from a seated view where a wall fades, its decorations fade WITH it (don't float); when the eye is
  inside, they're fully visible.

## Acceptance criteria
- The gym walls around the court are noticeably more decorated (gym + playful mix), readable + not
  over-cluttered, not intruding on the play volume. Verified via `screen_capture` (inside the gym).
- When the camera wall-fade hides a wall, that wall's decorations **fade with it** (no floating
  banners/clock/posters obstructing the view) — and they reappear when the eye is back inside. Verified by
  moving the camera so a decorated wall fades.
- Decorations are CanCollide=false, out of the ball/player collision sets, don't change gameplay/ball feel.
  Build-once + applied to the current place. Studio left in Edit.

## Relevant files
- `src/server/MatchService.luau` — `buildGym`: add the wall decorations (parented per-wall for the fade);
  build-once + one-time pass.
- `src/client/NineSquareClient.client.luau` — extend `updateWallFade` to fade each wall's decoration
  children (parts + decals/textures + SurfaceGui labels) along with the wall.
- `src/shared/GridConfig.luau` — decoration tunables (which/where/colours) if useful; reuse `camWallFade*`.
- Creator-store 3D assets via the MCP (banners/clock/props) — note any that must PERSIST in the place.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output` + `screen_capture` inside the gym AND from an angle
  where a decorated wall fades, confirming the decor fades with it. Leave Studio in Edit.)

## Constraints
- Cosmetic only — don't change gameplay, ball feel, collision, or the court. Decorations CanCollide=false,
  out of the ball/player collision sets + `NineSquare.Frame`. They MUST fade with their wall via the
  extended wall-fade (no floating decor blocking the camera). Build-once / tweakable; tunables in
  `GridConfig`. Note any creator-store assets that must persist in the saved place.
