# Spectate camera: look DOWN at the court (not behind the bench / not Custom)

## Problem
The spectate camera is wrong. History: it was a fixed overlook that stared at the gallery floor; I then
switched it to Roblox's default third-person (`CameraType.Custom`) so watchers could roam — but Custom puts
the camera **behind the player**, who spawns at the gallery **bench**, so the view is filled with the red
bench backrest (see Scott's screenshot) and faces the wrong way. Movement-while-spectating is now good and
should STAY; only the camera is wrong.

## Decision (from Scott)
The spectate camera should **look DOWN at the court (watch the match)** — a fixed overview angled down
through the gallery opening at the play area, framing the whole 9-square centered. Spectators watch the
game and tap **Join Game** to drop in.

## Fix
In `src/client/NineSquareClient.client.luau` `updateCamera`:
- When `isSpectating()`, do NOT use `CameraType.Custom` (that's what put the camera behind the bench).
  Instead use the **court OVERVIEW** camera — the SAME proven framing seated players get when NOT in follow
  mode: `Scriptable`, focus = `courtOrigin()`, the `camFarEye`/`camFarLook` (→ `camNearEye`/`camNearLook`)
  offsets, and the touch **fit-the-grid** path so the whole court is visible (esp. on phones). This looks
  down at the court center and frames the match.
- Cleanest implementation: gate FOLLOW mode on `(not spectating)` and let spectators fall through the
  existing `courtView` branch (focus = court origin, `camFar*` offsets, `isTouch and courtView` fit-grid) —
  so spectators get exactly the working court overview, looking down at the play area. Remove the
  `Custom`/early-return spectator branch.
- KEEP movement working while spectating (do NOT anchor the character) — Scott confirmed movement is better
  now. (With the scripted court cam, movement is camera-relative; that's fine — watching is the priority.)
- This supersedes the Custom-camera spectator change from commit `a1e5e5c`. KEEP that commit's bench-seat
  disable (no auto-sit) — only revert the camera portion.

## Acceptance criteria
- Spectating → the camera looks **down at the court / play area** (the whole 9-square framed, centered) —
  NOT behind the bench, NOT staring at the gallery floor, NOT facing a wall. Confirm with a `screen_capture`
  while spectating (you should see the court + grid from above, like the seated overview).
- Movement still works while spectating (the character can walk; not anchored). Tapping Join still drops in.
- Desktop AND mobile (portrait) both frame the court (mobile fit-grid applies). Seated players' camera
  (court / follow / zoom / wall-fade) is unchanged. Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` — `updateCamera`: spectator → court overview (reuse `courtView`
  path); gate `followMode` on not-spectating; drop the `Custom` branch.
- `src/shared/GridConfig.luau` — reuse `camFarEye`/`camFarLook` etc.; the M5.2/M5.3 `specOverlookEye/Look`
  become unused (leave or remove).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client camera runs on
  the Client datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output`;
  `screen_capture` while Spectating=true to confirm the court is framed from above. Leave Studio in Edit.)

## Constraints
- Client camera only — don't change movement (keep it working / not anchored), the lobby/Join flow, the
  bench-seat disable, occupancy, gameplay, or the server. Reuse the existing court-overview framing (don't
  invent a new one). Seated-player camera unaffected.
