# Add legs at the 4 grid corners (frame stands on something)

## Problem
The overhead 3×3 frame (the black Neon beams at `frameHeight`) floats in the air. Add four vertical
**legs/posts** at the frame's outer corners, running from the floor up to the frame, so it reads as a
structure standing on the court rather than hovering.

## Where
Built in `MatchService.buildArena` (rebuilds every Play), alongside the existing `Frame` beams. The
frame's outer corners are at `±1.5 * squareSize` on X and Z (squareSize=14 → ±21) relative to the
court origin, at `y = frameHeight` (11). So the 4 legs go at `origin + (±21, *, ±21)`, each spanning
**y = 0 (floor) up to y = frameHeight**, i.e. a post of height `frameHeight`, centred at
`y = frameHeight/2`. Derive all positions from `GridConfig` (`origin`, `squareSize`, `frameHeight`) so
they stay aligned if tunables change.

## Look
Structural support posts that match the frame: dark (≈ the frame's `Color3.fromRGB(40,40,45)`), a touch
thicker than the beams (`beamThickness` is 0.5 — try ~0.8–1.2 square posts) so they read as legs. Use a
solid material (e.g. SmoothPlastic or a metal); they do NOT need to glow like the Neon beams.

## Acceptance criteria
- Four vertical legs at the frame's outer corners, each connecting the floor (y=0) to the frame
  (y=frameHeight); the frame visibly "stands on" them.
- **Cosmetic only — they must NOT change ball physics:** non-colliding and NOT picked up by the ball's
  collision surfaces (see constraint below).
- Positions/size derived from `GridConfig`; built in `buildArena` so they appear every Play.
- Verified in a Play test (legs visible at all four corners, floor-to-frame).

## Relevant files
- `src/server/MatchService.luau` — `buildArena`, near where the `Frame` folder/beams are built.
- `src/shared/GridConfig.luau` — reuse `origin`, `squareSize`, `frameHeight`, `beamThickness` (add a
  leg-thickness tunable if you like).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done).

## Constraints
- **Keep the ball feel unchanged.** `BallController:_surfaces()` collects every BasePart under the
  `NineSquare.Frame` folder as a collision surface — so do NOT put the legs in `Frame`. Put them in a
  separate folder (e.g. `FrameLegs`) and set `CanCollide = false` so the custom ball collision never
  sees them. (They're at the court's outer corners anyway, but keep them out of `_surfaces` to be safe.)
- Don't disturb the floor, grid lines, painted-shadow lines, or the frame beams.
