# Shrink + raise the player contact sphere to cover the upper body

## Problem
The player's hit-sphere (used by `HitResolver.checkContact` to detect a ball contact, and whose
centre defines the strike normal) is currently fairly large and centred around the torso. Make it
**smaller and raised** so it sits over the player's **upper body / head** — i.e. you volley with your
head/shoulders/hands, not your whole body. More realistic.

## Current values (`src/shared/GridConfig.luau`)
- `hitZoneRadius = 2.5` — sphere radius.
- `hitZoneYOffset = 2.0` — sphere centre above the HumanoidRootPart.
- `HitResolver` centres the sphere at `hrp.Position + (0, hitZoneYOffset, 0)`, radius `hitZoneRadius`;
  contact when `|ball - centre| <= hitZoneRadius + ballRadius` (ballRadius = 2). The contact normal is
  `unit(ball - centre)`, so a higher/smaller sphere also makes the normal a touch more vertical when
  you meet the ball from below — that's fine.

## Direction
- **Smaller:** reduce `hitZoneRadius` (try ~1.5–1.8) so it reads as an upper-body sphere, not a body blob.
- **Raised:** increase `hitZoneYOffset` (try ~2.6–3.0) so the sphere covers the head/upper torso.
- Pick final values by eye + the playability check below; these are starting points.

## Keep it playable (the constraint)
Contact happens at the jump apex, at the frame plane (`frameHeight = 11`). A smaller sphere shrinks
the contact window, so **re-verify a player can still reliably serve and volley at the frame plane.**
The reachable height of the sphere top at apex ≈ (apex HRP Y) + `hitZoneYOffset` + `hitZoneRadius` +
`ballRadius`. If shrinking the radius drops that below where the ball sits (`frameHeight`), the ball
becomes unhittable — compensate by raising `hitZoneYOffset` and/or nudging `frameHeight` down a little
so the raised sphere still meets the hovering/arcing ball. Aim for "a touch more precise," not punishing.

## Acceptance criteria
- `hitZoneRadius` is smaller and `hitZoneYOffset` raised so the contact sphere covers the upper
  body/head (visually/numerically confirm the sphere sits over the upper torso/head).
- A player can still **reliably serve and volley at the frame plane** — confirmed in a live Play test
  (and/or the existing contact probes: a jump-height hit-zone still overlaps a ball at `frameHeight`).
- All values live in `GridConfig`; the change is deployed to Studio and verified.

## Relevant files
- `src/shared/GridConfig.luau` — `hitZoneRadius`, `hitZoneYOffset` (and `frameHeight` only if needed
  to keep the ball reachable).
- `src/server/HitResolver.luau` — uses these (read-only; no logic change expected).
- Deploy via the `robloxstudio` MCP and verify in Play (Studio Play/Edit mode flip-flops — check
  `get_studio_state` before mode-sensitive ops; leave Studio in Edit when done).

## Constraints
- Keep all tunables in `GridConfig` (project convention). Don't change the strike formula or the
  contact detection logic — this is a geometry/tuning change.
- Don't break the serve → volley → settle/re-serve loop.
