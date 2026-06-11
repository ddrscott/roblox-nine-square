# Mobile: dash button + double-jump via double-tap jump

## Problem
Dash and the double-jump flip only work on desktop — they're bound to KEYBOARD double-taps in
`Movement.client.luau` (double-tap WASD = dash in that direction; double-tap Space = flip). Phones have no
keyboard (just the thumbstick + the touch jump button), so neither fires. Make both work on mobile.

## Decisions (from Scott)
- **Dash:** an on-screen **Dash button** (touch only). Dash in the player's CURRENT direction — the
  thumbstick move direction (`Humanoid.MoveDirection`) if moving, else the character's facing — since there's
  no "double-tap a direction" on a thumbstick.
- **Double-jump (flip):** the player **taps jump twice** (double-taps the touch jump button) to flip — just
  like double-tapping spacebar. **No separate flip button.**

## Build
### 1. Double-jump via a platform-agnostic JUMP double-tap
- Detect a double-tap of the JUMP request using **`UserInputService.JumpRequest`** (it fires for the touch
  jump button, the spacebar, AND gamepad A) instead of the current keyboard-`KeyCode.Space`-only detection.
  Two JumpRequests within `GridConfig.doubleTapWindow` → trigger the existing flip (the first press is the
  normal jump; the second, while airborne, is the flip). Keep it stamina-gated (`flipCost`) exactly as now.
- This makes "tap jump twice → flip" work on TOUCH, KEYBOARD, and GAMEPAD with one code path. Desktop
  behaviour must stay identical (double-tap space still flips, same feel). Reuse the existing flip
  implementation (flipUpVelocity + flipForwardBoost + the cosmetic spin); only the TRIGGER changes/generalizes.

### 2. Dash button (touch only)
- Add a thumb-reachable on-screen **"Dash"** button (a touch-only ScreenGui, like the existing mobile camera
  toggle) — shown when `UserInputService.TouchEnabled` (and keyboard-less). Tapping it fires the existing
  dash burst (stamina-gated, `dashCost`), but DIRECTED by the current input: `Humanoid.MoveDirection` (the
  thumbstick) if the player is moving, else the HRP facing direction. Reuse the dash speed/duration/feel
  (`dashSpeed`/`dashDuration`) + the dash-jump momentum maintainer.
- Place it clear of the default touch jump button (bottom-right) and the camera-mode toggle — don't overlap.
  Consistent with the shared `GridConfig.uiStyle` button look.
- Desktop keeps the double-tap-WASD dash (don't break it); the dash button is touch-only.

## Acceptance criteria
- On mobile (Studio device emulator / a touch session): a **Dash button** appears and dashes the player in
  their current thumbstick/facing direction (stamina-gated); **tapping jump twice** performs the double-jump
  flip (stamina-gated). Both feel like the desktop versions.
- On desktop: unchanged — double-tap WASD still dashes, double-tap Space still flips (now via the unified
  JumpRequest path, same feel); no dash button shown.
- Stamina costs + the dash-jump momentum behaviour preserved; no other movement regression. Verified via the
  MCP. Studio left in Edit.

## Relevant files
- `src/client/Movement.client.luau` — replace/generalize the flip trigger to `UserInputService.JumpRequest`
  double-tap; add the touch Dash button + direct the dash by `Humanoid.MoveDirection`/facing; keep the
  desktop double-tap-WASD dash + stamina + momentum.
- `src/shared/GridConfig.luau` — reuse `doubleTapWindow`/`dashSpeed`/`dashDuration`/`dashCost`/`flipCost`;
  add a dash-button size/position tunable if useful.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client input on the
  Client datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  test the Dash button + a double JumpRequest (and confirm desktop double-tap space/WASD still work). Use the
  device emulator for a touch session if available. Leave Studio in Edit.)

## Constraints
- Client input/UI only — don't change the dash/flip physics or stamina logic, just add the touch triggers
  (Dash button + JumpRequest double-tap) and direct the mobile dash by the thumbstick/facing. Keep desktop
  identical. Touch button shows only on touch devices; don't overlap the jump button / camera toggle.
  Tunables in `GridConfig`.
