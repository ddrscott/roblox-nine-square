# Fade walls that obstruct the camera (camera occlusion)

## Problem
With the scriptable court camera (zoom + shift-follow), the camera can end up positioned so a gym
wall (or the ceiling) sits between it and the court/player — and because we use a Scriptable camera,
Roblox's built-in camera-occlusion (auto-transparency of obstructing parts) does NOT apply, so the
wall either blocks the view or, when the camera clips into/through it, you see through into the void.

**Surface-normal note (answers the original question):** standard `Part`s have no per-face one-sided
normal control. Only `MeshPart.DoubleSided` exists, and parts are single-sided-ish only for meshes —
making a wall single-sided would cull its BACK face, so from outside you'd see straight through it
into the room (worse). So one-sided faces are not the fix. **Chosen approach: fade obstructing walls**
(replicate the default camera's occlusion behaviour ourselves), client-side.

## Approach
Each frame, make any gym **wall/ceiling** that is between the camera and the focus point (the player
in follow mode, else the court centre) **fade toward transparent**, and fade it back to opaque once it
no longer obstructs. This both unblocks the view and removes the "see through the wall" artifact when
the camera is near/outside a wall.

Implementation guidance:
- Operate on a **whitelist** of the gym's occluders: `WallE`, `WallW`, `WallN`, `WallS`, `Ceiling`
  (built in `MatchService.buildGym`). Do NOT touch the floor, grid lines, frame pipes, ball, or player.
- Detecting obstruction — either is fine:
  - **Side test (simple, robust for this box gym):** the gym is axis-aligned and the camera only exits
    through one wall/ceiling at a time. Fade a wall when the camera is on its OUTSIDE relative to the
    court centre (e.g. fade `WallS` (z = origin.z + L/2) when `cam.Z > wall.Z`; `WallN` when
    `cam.Z < wall.Z`; `WallE/W` by X; `Ceiling` when `cam.Y > ceiling.Y`). Add a small margin so it
    fades just before the camera reaches the plane.
  - **Raycast sweep (faithful to default occlusion):** cast from the focus point to the camera; any
    whitelisted part crossed → fade. (Roblox `Raycast` returns one hit; loop with an exclude list, or
    cast against just the whitelist, to catch multiple.)
- **Smooth the fade** (lerp transparency toward the target each frame; e.g. `camWallFadeSpeed`) so it
  doesn't pop. Fade target ~`camWallFadeTransparency` (e.g. 0.85–1.0). Restore to the wall's original
  transparency (the walls are opaque = 0; windows are separate Glass parts — leave them).
- Client-side only (a LocalScript — extend `NineSquareClient` or add a small `WallFade` client).

## Acceptance criteria
- Zooming out / following to a position where a wall or the ceiling would block or be clipped by the
  camera makes that wall fade so the court/player stays clearly visible — no see-through-to-void.
- When the camera returns so the wall no longer obstructs, it fades back to opaque.
- Floor, grid lines, frame, ball, and player are never affected; windows (Glass) unchanged.
- Fade is smooth (no harsh pop). Tunables live in `GridConfig`.
- Verified in a Play test (zoom fully out and/or shift-follow to an edge so a wall would clip; confirm
  it fades and restores).

## Relevant files
- `src/client/NineSquareClient.client.luau` — owns the camera (zoom/follow); natural home, or add a
  dedicated `src/client/WallFade.client.luau` (Studio: `StarterPlayer.StarterPlayerScripts.<name>`).
- `src/server/MatchService.luau` — builds the gym walls/ceiling (names: `WallE/W/N/S`, `Ceiling`).
- `src/shared/GridConfig.luau` — add `camWallFadeTransparency`, `camWallFadeSpeed` (+ margin if used).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done). New client scripts deploy cleanly via `script.Source` (chunked) in Edit.

## Constraints
- **Do NOT clamp the camera, and do NOT move the walls.** The walls are intentionally close to the
  grid for good ball bounce — keep them where they are and fade them when near/obstructing the camera.
- Client-side only; don't change camera offsets or the strike. Keep the clean structure.
- Only fade the whitelisted walls/ceiling; always restore them when not occluding (no stuck-invisible
  walls). Keep tunables in `GridConfig`.
