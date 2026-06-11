# Drop the "Spectating" HUD label → put "Spectators Area" text on the gallery walls

## Problem
The on-screen **"Spectating"** status label is redundant UX clutter. Instead, communicate it in the WORLD:
remove the HUD label and add **"Spectators Area"** signage on the gallery (foyer) walls.

## What to do
### 1. Remove the "Spectating" HUD label
- Remove the on-screen "Spectating" status pill/label from the HUD. Note the HUD is now StarterGui-authored
  via `HudBuilder` (`StarterGui.NineSquareHUD`), so remove that component from BOTH the `HudBuilder` default
  tree AND the authored StarterGui instance, plus the client binding that updates it (`RankHud` /
  `NineSquareClient`).
- KEEP the Join Game button and its queue state — the join button already shows "Join Game" / "In queue
  (#N)", so dropping the separate "Spectating" label loses no needed info. (If the queue "#N in line" only
  lived on the removed label, fold that into the Join button's "In queue (#N)" so a queued player still sees
  their position.)

### 2. Add "Spectators Area" signage on the gallery walls
- In `MatchService.buildGallery`, add a **`SurfaceGui` + `TextLabel` reading "Spectators Area"** on the
  gallery's interior wall face(s) (`GalWall*`) so anyone up in the foyer sees it. Put it where it reads well
  — e.g. the back/north interior wall (and/or repeat on a couple of walls). Sized + styled to be legible
  from the foyer; consistent with the gym's look. Text is a `GridConfig` tunable (`spectatorsAreaText =
  "Spectators Area"`).
- Build-once (it's in the build-once gallery) AND a one-time pass on the current persisted Gallery so it
  shows now. Keep it OUT of the ball/player collision sets (it's a surface label on an existing wall).

## Acceptance criteria
- No "Spectating" label appears on screen while spectating (it's gone from the HUD); the Join Game button +
  queue state still work (a queued player still sees "In queue (#N)").
- The gallery interior wall(s) show readable **"Spectators Area"** text — verified via `screen_capture` from
  the foyer.
- No regression to gameplay, the lobby/seat flow, the rest of the HUD, or the world collision. Studio left
  in Edit.

## Relevant files
- `src/shared/HudBuilder.luau` — remove the Spectating label component from the authored/default HUD tree.
- `src/client/RankHud.client.luau` / `src/client/NineSquareClient.client.luau` — remove the binding that set
  the Spectating label; ensure the Join button still carries the queue "#N" state.
- the authored `StarterGui.NineSquareHUD` — remove the Spectating label instance (via the MCP, persisted).
- `src/server/MatchService.luau` — `buildGallery`: the "Spectators Area" wall SurfaceGui/TextLabel (build-once
  + one-time pass on the current place).
- `src/shared/GridConfig.luau` — `spectatorsAreaText` (+ any sign size/colour tunables).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; `screen_capture` the foyer wall sign + confirm no
  on-screen "Spectating" label while spectating. Leave Studio in Edit.)

## Constraints
- Presentation only — don't change the lobby/seat/queue LOGIC (just drop the redundant label + add world
  signage). Keep the Join button + queue position working. The wall sign stays out of the ball/player
  collision sets; build-once so it's tweakable. Tunables in `GridConfig`.
