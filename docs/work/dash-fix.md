# Fix dash: swap reversed left/right + cut distance to ~1/4

## Problem
Two issues with the dash added in `src/client/Movement.client.luau` (commit 3a423c1):
1. **Left/right are reversed** — double-tapping the left key dashes right and vice-versa. (Forward/back
   seem fine — the user only reported left/right; confirm W/S are correct.)
2. **Dash distance is way too far** — reduce it to roughly **a quarter** of the current distance.

## Direction
1. **Reversed L/R:** the dash is camera-relative. The bug is almost certainly a sign flip in the
   right/left mapping — e.g. the A/D (or left/right input) maps to the wrong sign of the camera's
   right vector. Fix the mapping so left input → camera-left, right input → camera-right. Don't touch
   forward/back unless they're also wrong.
2. **Quarter distance:** dash travel ≈ `dashSpeed × dashDuration` (GridConfig: `dashSpeed = 80`,
   `dashDuration = 0.18`). Cut the effective distance to ~25% — simplest is `dashSpeed` 80 → ~20
   (keep duration so it stays snappy), or scale to taste. Keep it feeling like a quick step, not a slide.

## Acceptance criteria
- Tapping left dashes left and tapping right dashes right (relative to the camera / how the player
  reads the court). Forward/back unchanged and correct.
- Dash covers roughly a quarter of the previous distance — a short hop, not a long slide.
- Values live in `GridConfig`; change deployed to Studio and verified in a Play test.

## Relevant files
- `src/client/Movement.client.luau` — dash input → direction mapping (the L/R sign bug).
- `src/shared/GridConfig.luau` — `dashSpeed` / `dashDuration` (the distance).
- Deploy via the `robloxstudio` MCP and verify in Play (mode flip-flops — check `get_studio_state`
  before mode-sensitive ops; leave Studio in Edit when done).

## Constraints
- Client-side only (consistent with the existing movement). Don't change the stamina/flip behaviour.
- Keep tunables in `GridConfig`.
