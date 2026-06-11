# Lobby spawn (gallery) + tap-to-join + opening barrier + lock the building shell

Three related changes (all decided with Scott). Builds on M5.1 (seat model + `_backfillHook`), M5.2
(spectator state/queue + gallery spawn), M5.3 (gallery + opening).

## A. Players spawn in the watching gallery and enter the court via a "Join Game" button (decided)
Today a joining human is **auto-seated** at the entry rank (M5.1 `PlayerAdded → seatHuman`), and M5.2 has a
**proactive sweep** that pulls waiting spectators into bot seats automatically. Scott wants instead: **you
join → spawn in the gallery watching area → tap a "Join Game" button to drop into the court.** The court is
always full (humans + bots), so "entering" = taking a **bot's** seat at the entry rank.

Change the flow:
- **On join (PlayerAdded):** do NOT auto-seat. Put the player in the existing non-seated **spectator/lobby**
  state (M5.2: parked at the gallery spawn / `specSpawnOffset`, overlook camera + HUD) so they watch the
  current game from above. With 0 humans seated, the 9 bots play a full, watchable game.
- **"Join Game" button (client ScreenGui):** shown to any non-seated human. Tapping fires a RemoteEvent to
  the server.
- **Server join request:** if a **bot** seat exists → `seatHuman` at the entry rank (displace a bot) and
  teleport them to their court cell (existing seatHuman path). If all 9 seats are humans → add them to the
  FIFO **join queue**; auto-seat the longest-waiting on the next human-seat-freeing (reuse M5.1
  `_backfillHook` / M5.2 queue). Reflect state on the button: "Join Game" → "In queue (#N)" (when full) →
  hidden once seated (switch to the seated camera/HUD, which already exists).
- **Disable the M5.2 proactive "auto-seat spectators into bot seats" sweep** — entry is now explicitly
  button-driven (otherwise lobby watchers get yanked into the court without tapping). KEEP the
  leave→backfill (a freed human seat goes to the longest-waiting queued joiner first, else a bot).
- Seated players stay in the court through rotation/dethrone; they return to the lobby only on disconnect
  (no auto-return / no "leave" button needed for now).

## B. Invisible barrier across the gallery opening (decided)
A **transparent, collidable** cap across the gallery floor opening (`G.galleryOpening` square) at the
gallery floor level (`G.galleryFloorY`), built into the `Gallery` folder (build-once like the rest):
- `Transparency = 1` (invisible — the downward sightline to the court is preserved), `CanCollide = true`
  (lobby watchers can't fall through the opening into the play area), `Anchored`, `CastShadow=false`.
- It must NOT block the spectator's view (transparent), and teleporting a seated player DOWN to their court
  cell is a CFrame set that bypasses collision (unaffected).
- **Ball note:** the game ball is server-driven/anchored and already **volume-clamped** (the OOB wedge fix)
  so it never reaches gallery height and does NOT use Roblox physics collision — so "keeps the ball out of
  the watch area" is already guaranteed by the clamp; the barrier's real job is blocking PLAYERS. Do NOT try
  to route the ball through Roblox collision, and keep the barrier OUT of `NineSquare.Frame` /
  `BallController._surfaces` (so it never perturbs the ball).

## C. Lock the building shell so it's easy to manage in Studio (decided: lock it)
Set `Locked = true` on the big enclosing parts so they're **click-through in the Studio viewport** (you
select small interior objects behind them normally; select the shell deliberately via the Explorer):
- Gym: the `Ceiling*` panels and `WallE/W/N/S`.
- Gallery: `GalRoof`, `GalWall*` (and optionally the gallery floor ring).
- Set `Locked = true` at creation in `buildGym`/`buildGallery`. Because the world is build-once, also do a
  one-time pass that sets `Locked = true` on the ALREADY-built/persisted shell parts in the current place
  (via the MCP in Edit) so it takes effect now — `Locked` persists in the saved place like any property.
- Leave the floor numbers, grid lines, frame, ball, players, bench, trees, etc. unlocked (tweakable).

## Acceptance criteria
- A joining human spawns in the gallery watching area, **cannot fall through the opening** (barrier), and
  sees a **"Join Game"** button. They keep watching until they tap it (they are NOT auto-pulled into the
  court).
- Tapping Join → seated into the court (a bot is displaced at the entry rank) and teleported to their cell;
  if all 9 are humans → queued (button shows position) and auto-seated when a human leaves.
- With no humans, the 9 bots play a full game visible from the lobby.
- The gym ceiling/walls + gallery roof/walls are `Locked` (click-through in Studio; selectable via
  Explorer); interior/tweakable parts stay unlocked.
- No regression to gameplay, rotation, scoring, the ball, the wall-fade, or the seated/court + spectator
  cameras. Barrier is out of the ball/player court-collision sets. Verified via the MCP. Studio left in Edit.

## Relevant files
- `src/server/NineSquareServer.server.luau` — join flow: stop auto-seat-on-join (park as lobby spectator);
  add the Join RemoteEvent handler (seat-from-bot or enqueue); DISABLE the proactive bot-displacement sweep;
  keep leave→backfill (queued joiner → bot).
- `src/client/NineSquareClient.client.luau` (+ `RankHud`/a small lobby HUD) — the "Join Game" button
  (touch + desktop), its state (Join / In queue #N / hidden when seated), wired to the remote; reuse the
  existing spectator-vs-seated camera/HUD switch.
- `src/server/RotationService.luau` — reuse `seatHuman` / queue / `_backfillHook` (entry on demand);
  no rotation-mechanics change.
- `src/server/MatchService.luau` — the opening barrier in `buildGallery` (build-once); `Locked = true` on
  the gym + gallery shell parts in `buildGym`/`buildGallery`.
- `src/shared/GridConfig.luau` — barrier tunables (reuse `galleryOpening`/`galleryFloorY`); any join/lobby
  tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; simulate join → assert lobby (not seated) + barrier
  blocks a fall (a part with CanCollide over the opening) + a Join request seats-from-bot or enqueues +
  leave-backfill seats a queued joiner; assert shell parts `Locked`. `screen_capture` works. Leave Studio in
  Edit.)

## Constraints
- Don't change the ball physics, the strike/collision, rotation/dethrone mechanics, scoring, or the
  fairness ordering (joiner enters at the back/entry rank; faulter → very back) — only the ENTRY TRIGGER
  (auto → tap-to-join) and the spawn location (court → gallery lobby). Server-authoritative (the client only
  REQUESTS to join; the server decides seat/queue). Barrier + shell-lock stay out of the ball/player
  court-collision sets. Keep build-once.
