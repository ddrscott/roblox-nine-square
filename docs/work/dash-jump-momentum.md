# Maintain dash momentum when jumping mid-dash

## Problem
Jumping during a dash kills the horizontal momentum. The dash re-asserts a horizontal velocity for
`dashDuration`, but once that ends (often while still airborne) Roblox's air control bleeds the
horizontal speed back toward WalkSpeed — so a dash→jump doesn't carry you. Players expect a dash-jump
to **preserve the dash's horizontal velocity through the jump arc** (momentum), which also feeds the
velocity-proportional strike (carry speed into the ball for a harder, more directional hit).

## Fix
In `Movement.client.luau`: when the player jumps while dashing (or goes airborne while a dash is
active), keep the dash's **horizontal** velocity for the duration of the airborne arc — i.e. while the
Humanoid is airborne (Jumping/Freefall), re-assert the dash's horizontal velocity component each frame
(leaving the vertical to the jump + gravity) to counteract air control. Release it when the character
lands (Humanoid back to Running/grounded), so normal ground control resumes.

Notes:
- Track the dash's horizontal velocity (the burst direction × speed). On a jump-during-dash, hand that
  horizontal off to an "air-momentum" maintainer that runs until landing.
- Vertical comes from the jump/flip + gravity — don't touch it; only pin the horizontal.
- The existing double-jump flip adds its own velocity; the carried dash horizontal should compose with
  it (a dash → jump → flip keeps the horizontal).

## Acceptance criteria
- A dash immediately followed by a jump carries the dash's horizontal speed through the whole jump arc
  — you travel noticeably farther horizontally than a normal standing jump.
- Momentum is maintained while airborne and released on landing (normal walking resumes; you don't keep
  sliding on the ground).
- A normal (non-dash) jump and a ground dash are unchanged; the no-trip fix still holds (no stumbling).
- The carried horizontal speed flows into the strike (dash-jump into the ball hits harder/more
  directional) since the server reads the replicated HRP velocity.
- Verified in a Play test: dash, jump mid-dash, and confirm you keep flying horizontally and land
  farther out.

## Relevant files
- `src/client/Movement.client.luau` — owns the dash, double-jump flip, and the character/Humanoid refs;
  add the dash-horizontal tracking + airborne maintainer here.
- `src/shared/GridConfig.luau` — reuse `dashSpeed`/`dashDuration`; add a tunable only if you need one
  (e.g. an optional max air-momentum time).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done). Movement client is `StarterPlayer.StarterPlayerScripts.Movement`.

## Constraints
- Client-side, local player only. Don't break walking, normal jumping, the ground dash, the flip, or
  the no-trip fix (`FallingDown`/`Ragdoll` disabled). Keep tunables in `GridConfig`.
- Keep it controlled: maintain horizontal only while airborne (until landing); don't make the player
  slide forever on the ground.
