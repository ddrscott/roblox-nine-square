# Double-tap dash + double-jump flip (stamina-gated, feeds the strike)

## Problem
Raise the movement skill ceiling and make play more expressive. Because the ball strike is now
**velocity-proportional** (the server reads `HumanoidRootPart.AssemblyLinearVelocity` in
`HitResolver` and `BallController:strike` turns it into the impact), faster/higher player motion
already produces harder/higher hits. Dash + a double-jump flip give players the velocity tools to
exploit that: dash into the ball for a hard directional drive; flip/double-jump to reach higher and
add vertical velocity for a spike.

## Mechanics
- **Dash** — double-tap a movement key (W/A/S/D) within a short window (~0.25s) → a quick horizontal
  burst in that direction (set the character's horizontal velocity for a brief moment, or apply an
  impulse). Consumes stamina; blocked if stamina is insufficient.
- **Double-jump flip** — double-tap the jump key (Space) → a second jump while airborne that plays a
  flip motion (animation or a simple forward-rotation tween is fine for greybox) and adds upward
  velocity. Only one extra air-jump per airtime; resets on landing. Consumes stamina.
- **Stamina** — a small shared resource (e.g., 0–100). Dash and flip each cost a chunk; it
  regenerates over time while not spending. Show it with a simple client HUD bar.

## Feeds the strike (the point)
No special-casing of the ball is required — the strike already reads HRP velocity. Tune the dash
speed and flip vertical velocity so that:
- A dash directly into the ball produces a clearly harder, directional hit than a standing jump.
- A flip/double-jump lets you meet the ball higher and adds vertical velocity → a steeper/faster
  send (a "spike").
Verify the interaction against `BallController:strike` + `HitResolver.checkContact` (do NOT change
the strike formula; just confirm the new velocities flow through and feel good).

## Authority (client-side — matches M1)
- Implement in a **client LocalScript**. Reading double-tap input and applying velocity to the LOCAL
  character (which the client network-owns) replicates `AssemblyLinearVelocity` to the server, so the
  server-side strike picks it up automatically. No server validation now — anti-cheat is M5 per the
  PRD. Keep the existing "server reads replicated character state" contract.

## Relevant files
- `src/client/NineSquareClient.client.luau` — current client (input/camera/telegraph). Add the
  dash/double-jump/stamina + HUD here, or split into a new `src/client/Movement.client.luau`
  (Studio: `StarterPlayer.StarterPlayerScripts.<name>`) — keep it cohesive and documented.
- `src/shared/GridConfig.luau` — put ALL tunables here (project convention): dash speed/duration,
  double-tap window, stamina max/regen-per-sec, dash cost, flip cost, flip vertical velocity.
- Strike side (read-only, for verification): `src/server/HitResolver.luau`,
  `src/server/BallController.luau` (`:strike`, `currentVelocity`).
- Deploy to Studio via the `robloxstudio` MCP at the matching instance paths; the client script lives
  under `StarterPlayer.StarterPlayerScripts`. Movement/HUD run in the **Client** datamodel.

## Acceptance criteria
- Double-tapping a direction dashes the character that way (visible burst), gated + costed by stamina.
- Double-tapping jump performs a second mid-air jump with a flip motion, gated + costed by stamina;
  only one extra jump per airtime, resets on landing.
- Stamina depletes on dash/flip and regenerates over time; a client HUD bar shows the current level.
- Dashing into the ball is a noticeably harder/directional hit; a flip-jump reaches higher and adds
  vertical to the strike — confirmed live (the velocity flows through `BallController:strike`).
- All numbers live in `GridConfig`; changes deployed to Studio and verified in a Play test
  (screenshot + console / a short probe).

## Constraints
- **Client-side only** (no server-auth movement; that's M5). Don't alter the strike formula.
- Don't break the existing loop (physical serve, contact volley, settle/rest re-serve) or the fixed
  court camera. Dash shouldn't fling players out of the gym or behind the camera.
- Follow the repo's deploy model: edit `src/` (source of truth) AND deploy to the Studio scripts;
  verify in Play. Keep the code clean and documented (clear contracts), consistent with the existing
  BallController/HitResolver refactor.
