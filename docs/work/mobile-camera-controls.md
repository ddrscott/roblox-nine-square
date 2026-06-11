# Mobile camera: pinch-zoom + on-screen mode toggle + fit-the-grid (playable on phones)

## Problem
The court camera (in `NineSquareClient.client.luau`) is desktop-only:
- **Zoom** is mouse-wheel (`InputChanged` / MouseWheel) — phones have no wheel.
- **Camera-mode toggle** (court overview ↔ follow-the-player) is bound to **LeftShift** — phones have no
  shift key.
- On a small / portrait screen the wide 3×3 grid (3·squareSize = 42 studs) doesn't fit the narrow
  horizontal FOV, so you can't see the whole court. Net: it's unplayable on mobile.

## What to build (touch parity for the two camera controls + framing)
1. **Pinch-to-zoom (touch):** two-finger pinch drives the SAME zoom parameter the mouse wheel does (the
   0..1 lerp between `camFarEye`/`camFarLook` and `camNearEye`/`camNearLook`). Use
   `UserInputService.TouchPinch` (or track two `TouchMoved` points) → map pinch scale to the zoom delta.
   Pinch out = zoom out, pinch in = zoom in. Keep desktop mouse-wheel working unchanged.
2. **On-screen camera-mode toggle (the "shift" equivalent):** a small, thumb-reachable on-screen button
   (ScreenGui, touch devices only) that toggles court-overview ↔ follow mode — same toggle LeftShift does
   on desktop. Label it clearly (e.g. "Camera" / an icon, with the current mode). Desktop keeps LeftShift;
   the button can show on touch only (or both).
3. **Fit the whole grid on small / portrait screens (the core playability fix):** when fully zoomed OUT, the
   ENTIRE 3×3 grid (+ a margin) must be visible regardless of aspect ratio. On portrait phones the
   horizontal FOV is narrow, so pull the camera back far enough (and/or widen `FieldOfView`) that the grid
   width fits. Two acceptable approaches: (a) compute the required zoomed-out distance from the live
   `Camera.ViewportSize` aspect + the grid width each frame and frame it ("fit" the grid), or (b) extend the
   zoom-out range with a more-distant far-eye + a mobile FOV bump tuned so common phone aspects (portrait
   ~9:19.5 and landscape) see the full grid. Prefer (a) if clean — it self-adjusts to any device. On touch,
   DEFAULT to this fit-the-grid framing so a player opening on a phone immediately sees the whole court.
4. Detect touch via `UserInputService.TouchEnabled` (and treat keyboard-less as mobile). Don't show the
   touch button on desktop-only sessions; don't break the existing mouse/keyboard path.

## Acceptance criteria
- On a touch device (test via Studio's Device emulator — phone presets, both portrait & landscape): the
  whole 3×3 grid is visible when zoomed out (default framing), pinch-to-zoom adjusts the view, and an
  on-screen button toggles court ↔ follow mode.
- On desktop: mouse-wheel zoom and the LeftShift follow toggle still work exactly as before (no regression);
  the touch button is hidden (or harmless).
- The camera never clips outside the gym awkwardly when zoomed out to fit (respect the existing wall-fade);
  follow mode still centers on the local player's seat.
- Verified via the MCP using Studio's device/viewport emulation (different aspect ratios) — assert the grid
  corners are on-screen when zoomed out, and the toggle/pinch change the camera. Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` — the court camera, zoom lerp, mouse-wheel + LeftShift handlers;
  add `TouchPinch` zoom, the touch mode-toggle button (a ScreenGui), and the aspect-aware fit-the-grid
  zoom-out framing. Keep the desktop path intact.
- `src/shared/GridConfig.luau` — zoom-range / mobile-FOV / fit-margin tunables (e.g. a more-distant far-eye
  or a `camFitMarginStuds`, `camMobileMaxFOV`), and the grid width derives from `squareSize`.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output`; use the device emulator + `Camera:WorldToViewportPoint`
  on the grid corners to assert they're on-screen at zoomed-out on a phone aspect; `screen_capture` works.
  Leave Studio in Edit.)

## Constraints
- Client camera/UX only — don't change gameplay, the server, physics, occupancy, or scoring. Don't regress
  the desktop mouse-wheel zoom or LeftShift toggle, the wall-fade occlusion, follow mode, or the spectator
  overlook camera (M5.2) — spectators have their own camera; this is the SEATED/court camera. Keep new
  values in `GridConfig`. Touch controls show only on touch devices.
