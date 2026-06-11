# Leave-to-spectate button + foyer fall-out barriers + move buttons to the right under the scoreboard

Three related lobby/spectator UX fixes.

## A. A way to go back to SPECTATE while playing
Today entry is one-way: a lobby watcher taps "Join Game" to get seated, but a seated player can't leave the
court back to the gallery. Add the inverse:
- Show a **"Leave"** / **"Spectate"** button to a SEATED human (Rank > 0, not Spectating) — the counterpart
  to the Join Game button. Tapping it fires a server request (reuse the remotes pattern — e.g. a new
  `LeaveRequest` RemoteEvent alongside `JoinRequest`, self-healed like the others).
- Server handler: `rotation:unseatHuman(plr)` frees their seat (the existing `_backfillHook` seats the
  longest-waiting queued spectator if any, else a bot — so the seat's never empty), then `parkLobbyWatcher(plr)`
  puts them back in the gallery LOBBY (Spectating=true, no rank), watching with the roam camera + the Join
  Game button available again. They re-enter later via Join (at the entry rank, per the existing fairness).
- Handle the King leaving mid-serve the same way the disconnect path does (re-serve for the new King) so the
  loop never wedges. Server-authoritative (client only requests).

## B. Enough barriers so a spectator can't fall OUT of the foyer
A roaming spectator must not be able to walk off the gallery / fall out. The opening already has the
invisible barrier (the central hole over the court). This is about the OUTER foyer: audit the gallery for
ANY place a walking spectator could fall out — the outer edges of the floor ring, gaps at the opening
corners, the perimeter where walls don't fully meet the floor, any window/door gaps — and add barriers
(extend/раise the `GalWall*` perimeter, add edge railings/invisible walls) so the foyer is fully enclosed
and a spectator stays contained while roaming. Verify by walking the edges in Play (can't fall to the court
or off the building). Keep barriers OUT of the ball/player COURT collision sets (gallery is above the court).

## C. Move the lobby buttons to the SIDE, under the scoreboard (don't obstruct the camera)
The "Join Game" button + the "Spectating" pill currently sit bottom-CENTER, covering the view. Move the
lobby UI — **Join Game**, the new **Leave/Spectate** button, and the **Spectating / queue pill** — to the
RIGHT side of the screen, stacked vertically **beneath the scoreboard** (the stats panel is top-right), so
they don't obstruct the court/camera. Right-anchor them; keep them clear of the existing mobile camera-mode
toggle (bottom-right) and the default touch jump button — don't overlap. Compact on mobile.

## Acceptance criteria
- A SEATED player sees a Leave/Spectate button; tapping it returns them to the gallery lobby (Spectating,
  roam camera, Join Game available), their seat backfilled (queued spectator → else bot, never empty). They
  can Join again afterward. No wedge if the King leaves this way.
- A roaming spectator CANNOT fall out of the foyer anywhere — verified by walking the gallery edges in Play.
- The Join / Leave / Spectating UI sits on the RIGHT under the scoreboard, not covering the center; doesn't
  overlap the camera toggle or jump button; readable on mobile + desktop. Verified via `screen_capture`.
- No regression to gameplay, the seated/court + spectator (roam) cameras, occupancy, or the bench-seat/barrier
  work. Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` — add the Leave/Spectate button (shown when seated); reposition
  Join Game + Spectating pill + Leave to the right under the scoreboard; keep clear of the camera toggle.
- `src/server/NineSquareServer.server.luau` — `LeaveRequest` remote + handler (`unseatHuman` → `parkLobbyWatcher`,
  King re-serve guard); reuse the existing seat/backfill/lobby helpers.
- `src/server/MatchService.luau` — `buildGallery`: add/extend foyer barriers (perimeter walls/railings) so a
  spectator can't fall out; build-once + a one-time pass on the current place if needed (the gallery is
  build-once). Keep barriers out of the court collision sets.
- `src/shared/GridConfig.luau` — any barrier dims / button layout tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play: tap Leave from a seat → back to spectating
  (seat backfilled); walk the foyer edges → contained; `screen_capture` the right-side button layout. Leave
  Studio in Edit.)

## Constraints
- Keep the roaming `Custom` spectator camera + working movement, the tap-to-join flow, the bench-seat
  disable, and the opening barrier — this ADDS the leave path, more barriers, and a button reposition. Don't
  change gameplay/physics/scoring/occupancy mechanics. Server-authoritative (client only requests join/leave).
  Barriers stay out of the ball/player court-collision sets. Tunables in `GridConfig`.
