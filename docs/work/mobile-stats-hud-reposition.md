# Mobile: move the game-stats UI to the right + make it smaller

## Problem
On mobile the on-screen **game stats** cover too much of the screen. Move that UI **to the right side** and
make it **a little smaller** on mobile so it stops blocking the play area. Desktop should stay fine.

## Identify the offending element first (don't guess)
Use Studio's **device emulator** (a phone preset, portrait) + `screen_capture` to SEE which UI dominates the
mobile screen, then fix that one. Likely candidates (check each in the client code):
- The **player stats readout** (Best / King Turns / Turns) from the stats work. NOTE: if these live in
  Roblox's **built-in leaderstats player list** (CoreGui, top-right, opened via the player-list button),
  that panel is NOT freely repositionable. If THAT is the offender on mobile, the right fix is to roll a
  **compact, right-anchored custom stats label** for mobile (read the LocalPlayer's `leaderstats`/replicated
  values) and/or shrink it — rather than trying to move the CoreGui list.
- The **RankHud** (`RankHud.client.luau`) — the rank pill + the join/leave/rotation event toasts (M5.6).
- Any other custom scoreboard/HUD panel.
Pick whichever is actually oversized/intrusive on the phone screen (a before screenshot confirms it).

## Fix
- **Right-anchor it:** position the stats UI against the RIGHT edge of the screen (e.g. `AnchorPoint.X = 1`,
  `Position` near the right, with a small margin), out of the central play view.
- **Smaller on mobile:** scale it down on touch / small screens (smaller font + dimensions, or a UIScale)
  so it's compact but still readable. Gate on `UserInputService.TouchEnabled` (and/or a small viewport) so
  DESKTOP layout is unchanged (or also fine if it already reads well).
- Keep it from overlapping the other mobile UI (the Join Game button, the mobile camera mode toggle, the
  stamina bar) — check the corners don't collide.

## Acceptance criteria
- On a mobile/portrait emulator: the game-stats UI sits on the **right side**, is **noticeably smaller**,
  and no longer covers the play area (confirm with before/after `screen_capture` on a phone preset).
- On desktop: the stats are still legible and not broken (unchanged or still fine).
- The stat VALUES are unchanged (this is layout/size only); other HUD elements (Join button, camera toggle,
  stamina, rank pill, toasts) still work and don't overlap.
- Verified via the MCP device emulator. Studio left in Edit.

## Relevant files
- `src/client/RankHud.client.luau` — rank pill / event toasts / any stats display.
- The stats client / `StatsService` (`src/server/StatsService.luau`) — if stats are shown via leaderstats
  (built-in list), consider a compact custom mobile panel reading the replicated values; server stats logic
  stays unchanged.
- `src/client/NineSquareClient.client.luau` — if the stats HUD lives here / to avoid overlap with the mobile
  camera toggle + Join button.
- `src/shared/GridConfig.luau` — any HUD size/position tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output`; use the DEVICE EMULATOR (phone, portrait) +
  `screen_capture` to confirm the reposition/resize. Leave Studio in Edit.)

## Constraints
- Client UI/layout ONLY — don't change the stats logic, values, gameplay, or the server. Mobile-responsive:
  shrink/right-anchor on touch/small screens without breaking desktop. Keep it readable and clear of the
  other mobile controls. Tunables in `GridConfig` where sensible.
