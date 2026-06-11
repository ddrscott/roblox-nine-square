# Outdoor terrain + clear-day sky (backdrop out the windows / through clipped walls)

## Problem
Right now there's nothing outside the gym — out the upper-floor gallery windows/opening, and whenever a
player's court camera clips/fades a gym wall (the wall-fade makes walls transparent), you see empty void /
bare skybox. Add an **outdoor environment + sky** so there's something to see.

## Decisions
- **Sky / time of day:** **clear day** — bright blue sky, sun up, soft clouds; neutral and readable.
- **Setting:** **grassy park / schoolyard** (default chosen since only the sky was specified — a friendly,
  bright playground vibe that fits a 9-square game). Green ground, some trees, maybe a path / perimeter
  fence. Easy to retheme later.

## What to build
- **Sky:** add a clear-day `Sky` to `Lighting` (bright blue, visible sun, light clouds) + set the lighting
  to midday (`ClockTime ~14`, sun up). Optionally a subtle `Atmosphere` for depth/haze on the horizon.
  Keep the existing interior gym lighting working (the gym is still lit inside).
- **Outdoor terrain around + below the gym:** a grassy ground that extends out to the horizon around the
  gym footprint (Roblox `Terrain` grass, or a large ground plane + terrain — pick the more tweakable
  approach), with gentle low hills for interest. The gym sits ON this ground; the terrain must NOT intrude
  into the court/gym interior or the play surface (keep it outside/below the gym footprint; the gym floor
  stays the play surface).
- **Scenery (3D assets, tweakable):** scatter some creator-store assets — trees, maybe a fence/path or a
  couple of simple props — around the gym so there's depth and something to look at out the gallery windows
  and through faded walls. Don't over-populate (perf); keep counts/positions parameterized so Scott can
  tweak.
- **Make sure it reads from the two viewpoints that matter:** (a) standing in the upper gallery looking out
  the windows / down through the opening, and (b) the seated court camera when the wall-fade turns a wall
  transparent — instead of void, you now see grass + trees + sky.

## Acceptance criteria
- A clear-day sky is visible (blue, sun, clouds); midday lighting; interior gym lighting still works.
- Grassy outdoor terrain + some scenery surrounds the gym, visible BOTH out the gallery windows/opening AND
  when a court-camera wall-fade exposes the outside (no more empty void / bare skybox).
- The terrain/scenery is OUTSIDE the court + gym interior — it never intrudes on the play surface, the
  ball/player collision, the grid, or gameplay. No regression to the gym, gallery, camera, or wall-fade.
- Built via the MCP and tweakable (extents/asset positions parameterized in `GridConfig` or clearly-named
  instances). Verified via the MCP. Studio left in Edit.

## Relevant files
- `src/server/MatchService.luau` — build-once outdoor terrain/ground + scenery around the gym (alongside
  `buildGym`/`buildGallery`); keep it out of the ball/player collision sets and clear of the gym interior.
- Lighting/sky: set the `Sky` + lighting (in MatchService's build, or a small setup in
  `NineSquareServer`/`setupLighting` if that's where lighting lives — match the existing pattern).
- `src/shared/GridConfig.luau` — terrain extent / hill / scenery-count / sky tunables.
- Creator-store 3D assets via the robloxstudio MCP (trees / fence / props) — note any that must PERSIST in
  the place (like the gallery bench template) in your summary.
- Build/verify via the MCP (mode flip-flops — `get_studio_state` first; standalone `require` is STALE —
  verify via `script_read`/`get_console_output`; try `screen_capture` from the gallery window + a
  wall-clipped court angle to confirm the backdrop, but it's been flaky — fall back to instance/geometry
  assertions: Sky exists in Lighting, terrain/scenery instances exist outside the gym footprint, nothing
  added to the ball/player collision sets. Leave Studio in Edit.)

## Constraints
- Visual/environment only — don't change gameplay, the court, collision, the gallery structure, the camera,
  or the wall-fade logic. Terrain/scenery stays OUT of the ball/player collision sets and clear of the gym
  interior + play surface. Keep it performant (don't over-scatter) and tweakable (tunables in `GridConfig`).
  Server-built (Scott can't hand-edit Studio).
