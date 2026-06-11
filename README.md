# 9 Square in the Air (Roblox)

A multiplayer king-of-the-hill volley game for Roblox, based on the playground game
*9 Square in the Air*. Built live in Roblox Studio via the official **Roblox Studio MCP
server** (`StudioMCP`, which ships inside Roblox Studio).

## Status

**Milestone M5 (multiplayer + lobby) — complete** (closed out 2026-06-10). M1 greybox is tagged
`m1-greybox`; M2 folded into the M1 contact model; M3 built the grid + rotation + dethrone; M4 made solo
play a full game with bots. **M5** turns it into a build you can play with friends: **multiple real
players** share the 9-square at once, **bots backfill** every empty seat, overflow players **spectate** from
an upper-floor gallery and **auto-join** the next freed seat, the server is hardened to be **authoritative**
enough to trust in a real session, and the lobby is **legible** — seat nameplates, a spectator/queue HUD,
and brief join/leave/rotation feedback. See **["M5 multiplayer + lobby"](#m5--multiplayer--lobby) below** and
the **["How to test with friends"](#how-to-test-with-friends) checklist**. **M6 (progression / leaderboard /
audio-VFX / mobile) is next.**

Solo play in the place **"9 Square Beta"** is still a full game: the non-human squares are **bots** that
serve (when King) and
**physically hit** incoming balls — bots are now **real hitters**, not an artificial launch. Each bot
that intercepts a descending ball gets a moving **hit-sphere collider** (the same `{center, radius, vel}`
shape the human carries), driven to an **off-center stand** relative to the ball and then **driven up and
INTO the ball along the aim line** (a jump/run toward the contact point). That collider is fed into
`bc:step(dt, colliders)` alongside the human's, so the **same swept, velocity-proportional collision**
(`BallController:strikeVelocity`) resolves the bot hit. The **aim emerges from the off-center contact**:
the bot stands on the far side of the ball from its aim cell so `n = unit(ball − center)` points toward
the aim (outer bot → center C; King → a random outer square), and the jump velocity supplies the force.
Bots **miss** at a tuned rate (`botMissChance = 0.18`, under-driving so the spheres never overlap) → the
ball falls → floor fault → the grid rotates. The bot bodies are now **real R15 rigs** (the default blocky
"Rig Builder" dummy — one `ReplicatedStorage.BotRigTemplate` cloned 8×), kept synced to the collider so
they visibly **run their feet + leap into the ball**, recoloured gold on the throne. Each rig's
`HumanoidRootPart` is **anchored and CFrame-driven by the server** (the existing intercept slide / jump /
procedural idle sway-steps-lean — **no `Humanoid:MoveTo`/pathfinding**, `WalkSpeed`/`JumpPower = 0`), and
**stock R15 animation tracks (idle/walk/run/jump) are layered on top** via each rig's `Animator`, gated by
the body's actual per-frame speed. The rigs are cosmetic only: every part is `CanCollide = false` and put
in a non-colliding **`BotRig` collision group** (the R15 Humanoid re-enables `CanCollide` at runtime, so
the group is what actually guarantees the rigs never perturb the ball, the player, or each other), and
they live OUTSIDE `NineSquare.Frame` so they're never in `BallController._surfaces` — the hit is the
abstract collider's, not the rig's. Real rallies happen (bot ↔ center ↔ bot), the human climbs the ranks
and can reach **King**, and a bot-King fault fires the **dethrone**. The **human's volley, the swept
collision/physics, the over-pipe save/ownership, rotation timing, and the dethrone are unchanged** — bots
still go *through* the existing collision. Tunables (`botJumpVelocity`, `botStandoff`, `botOffCenterFrac`,
`botRestColliderY`, `botMoveSpeed`, R15 anim ids + the walk-blend speed threshold) live in `GridConfig`.
M3 loop / rank HUD / camera are unchanged.

## Docs

- Master PRD: [`docs/9-square-prd.md`](docs/9-square-prd.md)
- M1 design spec: [`docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md`](docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md)
- M1 plan: [`docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md`](docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md)
- **M3 design spec** (done): [`docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md`](docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md)
- **M4 design spec** (done): [`docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md`](docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md)
- **M5 design spec** (done): [`docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`](docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md)

## Build milestones (PRD §15)

1. **M1** — Greybox arena + readability + physical contact volley.  ✅ *done (`m1-greybox`)*
2. **M2** — Hit resolver: timing tiers + scatter.  *folded into the M1 contact model* — the
   velocity-proportional, contact-geometry strike (direction from where you hit it, power from your
   velocity, dash-jump momentum) already makes timing + positioning matter continuously, which is
   what discrete tiers were a proxy for. **Scatter dropped** to keep contact deterministic + skill-
   expressive (revisit only if play ever feels too predictable).
3. **M3** — Full grid + rotation + dethrone.  ✅ *done (accepted 2026-06-10)*
4. **M4** — Bots fill empty squares; solo play fully functional.  ✅ *done (accepted 2026-06-10)*
5. **M5** — Multiplayer + lobby (multi-human seating, bot backfill, spectator queue, gallery,
   server-authority hardening, lobby UX).  ✅ *done (2026-06-10)*
6. **M6** — Progression, leaderboard, audio/VFX, mobile tuning.  ← *next*

## Key design decisions (evolutions from the PRD)

- **Server-authoritative, deterministic** ball arcs — no client-side physics.
- The hit is a **physical contact volley**: get under the ball and jump; you must *reach* the frame
  plane (jump apex) **and** *touch* the ball. **Serving is physical too** (no button) — the ball
  hovers at center and you strike it.
- **Velocity-proportional strike**: the server reads the player's replicated HumanoidRootPart
  velocity at contact and models a sphere bounce (`BallController:strike`), so harder/faster motion
  into the ball produces a harder/steeper send. `hitMinPop` floors the outgoing speed so a clean
  contact always stays in play. Supersedes the PRD aim-assist (§5.4) and the old fixed `hitSpeed*`.
- **Movement skill moves (client-side)**: double-tap W/A/S/D to **dash** (a brief camera-relative
  horizontal burst) and double-tap Space mid-air for a **double-jump flip** (one extra air-jump with
  a cosmetic spin + upward velocity). Both are gated/costed by a **stamina** pool shown on a HUD bar.
  They feed the velocity-proportional strike directly (no special-casing): a dash into the ball is a
  hard directional drive, a flip meets the ball higher and spikes. Client-authoritative for now
  (anti-cheat is M5); all tunables live in `GridConfig`.
- **Faults**: a ball that returns to the square it was struck from is a *self-fault*; landing outside
  the 9 squares is *out-of-bounds*. Both flash the square + play the oof sound, then re-serve.
- **Scene**: an enclosed gym (`MatchService.buildGym`, build-once) with painted floor grid lines so
  the grid reads in Play even when dynamic shadows don't render.
- **Upper-floor spectator gallery (M5.3)**: `MatchService.buildGallery` (called from `buildGym`) adds a
  mezzanine ABOVE the gym ceiling. A square OPENING (`GridConfig.galleryOpening`) is punched through BOTH
  the gym ceiling (now a 4-panel ring: `CeilingN/S/E/W`) and the gallery floor ring (`GalFloorN/S/E/W`),
  so spectators standing on the gallery look straight DOWN onto the 9-square. Includes short perimeter
  walls, a roof, ceiling lights, a safety railing ringing the opening (`GalRail*`), bench seating, and a
  hidden `GallerySpawn`. M5.2 spectators are parked here via `GridConfig.specSpawnOffset` and watch from
  the overlook camera (`specOverlookEye/Look`) looking down through the opening. The whole gallery sits
  ABOVE the gym (`galleryFloorY` > gym `H`), lives OUTSIDE `NineSquare.Frame`, and never enters the ball
  (`BallController._surfaces`) or court collision — so seated-player cameras, the wall-fade occlusion, and
  the 1-human+8-bot gameplay baseline are all unaffected. All gallery dimensions are `GridConfig` tunables
  (`gallery*`) so they can be nudged without hand-editing Studio.
  - **Asset persistence**: the structural gallery is built entirely from code (always rebuilds on Play, no
    place dependency). The bench *seating* uses a creator-store 3D model cloned from
    `ReplicatedStorage.GalleryBenchTemplate` (inserted once via the Studio MCP, normalized with a
    `FootToPivotY` attribute + a `PrimaryPart` so it grounds cleanly). `buildGallery` clones it IF present
    and falls back to a code bench otherwise — so the build is robust whether or not the template ships in
    the place. To keep the nicer benches, that template must persist in `ReplicatedStorage`. The railing
    around the opening is code-built (deterministic fall-guard) rather than asset-based.

## M5 — multiplayer + lobby

The build is playable with friends: 2–9 humans share the court, bots backfill the rest, overflow players
spectate + auto-join, and the server stays authoritative. The pieces:

- **Occupancy / seating (humans fill, bots backfill).** A **seat** is a rank 1..9 ↔ cell (King = rank 1 = C).
  `RotationService.byRank[1..9]` is the single source of truth — each seat holds either a **human `Player`**
  or a **bot** rig. Every seat starts as a bot, so it's **always a full 9-square**. A joining human takes the
  **entry rank** (the highest-numbered seat a bot still holds, farthest from the King) by **displacing that
  bot** — so everyone starts at the bottom and earns their way to C. Humans always outrank bots. Rotation,
  serve, and dethrone are unchanged mechanically and work for **any** mix of humans and bots (any human King
  hover-serves; any bot King auto-serves).
- **Spectator overflow + auto-join (FIFO queue).** Spectators exist only when **humans > 9**. Extra joiners go
  into a server **FIFO queue** and spawn in the gallery. When a seat frees (a human leaves, or a bot still
  holds a seat while someone waits), the **longest-waiting** spectator is auto-seated at the entry rank. A
  `Spectating` flag + 1-based `QueuePos` are replicated per spectator so the client shows the overlook camera
  + a "Spectating — #N in line / NEXT UP!" HUD; the instant the server seats them, they flip back to a normal
  seated camera/HUD. **Spectators never affect the ball** (their colliders are excluded from `bc:step` every
  frame, re-checked against the live occupancy model).
- **Upper-floor gallery** — see the spectator-gallery note under *Key design decisions* above (M5.3).
- **Server-authority / anti-cheat.** The server owns the ball, contact resolution, scoring, seats, rotation,
  serve, and the queue; the client only *proposes* its character pos/velocity. `HitResolver` **clamps** each
  player's strike velocity to a plausible max, **caps the per-frame centre jump** (anti-teleport), and bounds
  the contribution against a **server-mirrored stamina pool** — so a spoofed HRP can't manufacture a super-hit
  or warp into the ball. Disconnects mid-rally / mid-serve / while King are handled so the queue + backfill
  never wedge (no empty seats, no double-seating, no lost ball; a King leaving mid-hover-serve re-serves for
  the new King). Inputs from unseated players are ignored.
- **Lobby UX (M5.6) — make the table legible.** Three server-authoritative, lightweight surfaces over the
  existing occupancy model (no gameplay logic changed — UX only):
  - **Seat nameplates.** `RotationService` builds a `workspace.NineSquare.Nameplates` folder — one
    `BillboardGui` per cell (fixed anchor, labels the *seat* not the moving body) — and **relabels them off
    `byRank` on every occupancy change** (join / leave / auto-seat / rotation). Each plate shows a human's
    **DisplayName** (cyan) or **"Bot"** (violet); the **King's plate is gold + crowned (`👑`)**. Server-built,
    so it replicates to every client for free and never trusts the client for who's King.
  - **Spectator / queue HUD.** Spectators see "Spectating — #N in line", promoted to **"NEXT UP!"** (green) at
    position 1; the rank pill hides while spectating and returns on auto-seat.
  - **Join / leave / rotation feedback.** A `HudEvent` `RemoteEvent` carries `{ kind, text, tone }`; the
    client renders a short-lived **toast** under the rank pill (capped to 4 stacked lines so a burst never
    spams). The server fires it on join, leave, queue auto-seat, dethrone, taking the King, and a player's own
    rank change ("Moved up — now Rank N" / "Faulted — back to Rank 9"). The whole table sees join/leave; the
    King/rank nudges are personal.
  - Tunables (`nameplate*`) live in `GridConfig`.

## Persistent player stats (DataStore)

Every **human** carries a persistent profile across sessions, surfaced in the standard Roblox **leaderstats**
player list (so the stats auto-show for everyone, no custom UI needed). Server-authoritative throughout — the
client never writes a stat. Bots are excluded (no `UserId`; they never persist).

- **What's tracked** (per human, keyed by `UserId`):
  - **`Best`** — best rank *reached* = the **lowest rank number ever held** (King = rank 1 = best). Improves
    only when a better (lower) rank is reached; a fault-back never worsens it. Shown as `0` until the player's
    first seat.
  - **`King Turns`** — total rallies held as **King** (rank 1) — the marquee stat.
  - **`Turns`** — total rallies played while seated.
  - (also stored: `turnsAtBest` — rallies held at the best rank, i.e. how long they lasted in their peak spot;
    not shown in the player list but persisted + available via `StatsService.getProfile`.)
- **A "turn" = one rally** (a serve→fault cycle) the player took part in while seated. `NineSquareServer`
  observes the existing rally loop: when the ball comes to rest and the deferred rotation runs, it credits a
  turn to **every seated human at the rank they held during that rally** (`recordRally`), then — after the
  shift — improves each human's best rank from their new seat (`noteRank`). The seating/rotation model is
  **unchanged**; stats are pure observation.
- **Persistence.** `StatsService` uses `DataStoreService` keyed per `UserId` under
  `GridConfig.statsStoreName .. "_" .. statsStoreVersion` (default `NineSquareStats_v1`). Loaded on
  `PlayerAdded`, saved on `PlayerRemoving` + a periodic autosave (`statsAutosaveInterval`, default 120s) +
  `game:BindToClose`. **Every DataStore call is wrapped in `pcall` with an in-memory fallback** — if the store
  is unavailable the game never errors or blocks; it just runs on in-memory stats for the session and logs a
  clear `[Stats] DataStore unavailable … FALLING BACK to in-memory` note once.
- **⚠️ Real persistence requires API access.** On a **published place** DataStore access is on by default. In
  **Studio** it only writes if you enable **Game Settings → Security → "Enable Studio Access to API
  Services"**; otherwise reads/writes are rejected and the game runs on the in-memory fallback (you'll see the
  fallback note in the output, and stats won't survive a rejoin). To reset everyone's stats fresh, bump
  `GridConfig.statsStoreVersion` (a new keyspace).
- **Files.** `src/server/StatsService.luau` (profile model + DataStore load/save + leaderstats + turn/rank
  updates), wired into the rally loop + join/leave in `src/server/NineSquareServer.server.luau`; tunables in
  `src/shared/GridConfig.luau` (`statsStoreName` / `statsStoreVersion` / `statsAutosaveInterval`).

## Known issues / next steps

- **OOB / pipe-escape edge case (tracked separately).** On certain outer-bot out-of-bounds hits the ball can
  fly to a very large Y and the deferred rotation can fail to resolve / wedge the rally. Not addressed in M5.6
  (UX/docs only) — left as a separate item to fix in the physics/rotation path.
- **Pipe/wall collision is dormant.** `BallController:_collide` correctly bounces the ball off the
  frame pipes + gym walls, BUT with the current high apex (~24) vs frame height (11) the ball arcs
  4–6 studs clear of every pipe and never reaches the walls — so it visually passes through the
  *open squares* of the frame and never touches a bar. To make pipes interactive, **flatten the
  trajectories** (lower `hitSpeedV` and/or raise `hitSpeedH`, or lower the apex relative to the
  frame) so the ball crosses the frame plane nearer pipe height between squares. (Verified via a
  trajectory sim: closest pipe approach 4.05 studs vs ball radius 2.0.)
- `Lighting.Technology` can't be set by script — set it to **ShadowMap/Future** in Studio Properties
  if you want real dynamic shadows (painted grid lines mean you don't strictly need it).

## How to test with friends

A checklist for a real multi-player session in **"9 Square Beta"**:

1. **Publish + start.** Publish the place (the git repo is code-of-record; the place holds the build), then
   either run a **Studio "Local Server" test** with 2–4 simulated players (Studio → Test → *Start* with
   *Players* = N, *Server* mode) **or** join the published place from multiple devices/accounts.
2. **Seats fill bottom-up.** The first human takes **Rank 9 / NW** (the entry seat, farthest from the King),
   displacing a bot; each additional human takes the next-highest bot seat. Bots backfill everything else, so
   it's **always a full 9-square**. Confirm each player's **nameplate** shows their name over their seat, and
   the **King's plate is gold + crowned** (`👑`).
3. **Climb + rotate.** Rally the ball; on a fault the grid rotates one step toward the King. Watch your **rank
   pill** update and a brief **toast** appear ("Moved up — now Rank N" when you advance, "Faulted — back to
   Rank 9" when you're knocked out). Take the center square to become **King** ("You're the KING! 👑").
4. **Dethrone.** Fault while King → you drop to Rank 9 and the next occupant takes C; the whole table gets a
   "X takes the throne" toast and the King square flashes.
5. **Overflow → spectating.** Add a **10th** player: with all 9 seats human they spawn in the **upper gallery**
   and see **"Spectating — #N in line"** (the longest-waiting shows **"NEXT UP!"**). They look straight down
   onto the court through the gallery opening and **cannot affect the ball**.
6. **Auto-join.** Have a seated player **leave**. The longest-waiting spectator is **auto-seated** into the
   freed rank ("You're in! Seated at Rank N") and the line re-indexes. With no spectator waiting, a fresh bot
   backfills — a seat is never empty.
7. **What to look for:** every seat labeled (human name or "Bot"), King unmistakable, ranks shift cleanly on
   faults, the queue HUD counts down, no errors in the Output, and **no wedged rally** (see the OOB note under
   *Known issues* — if the ball ever flies off to a huge height and the rally stalls, that's the tracked
   edge case, not your test).

Verify over MCP: `start_stop_play`, `get_console_output` for the `[NineSquare]` / `[Rotation]` logs, and
`execute_luau` against the **Server** datamodel to read `workspace.NineSquare.Nameplates` + each player's
`Rank` / `Spectating` / `QueuePos` attributes (the authoritative data the HUD reflects).

## Layout

- `src/shared/GridConfig.luau` — dimensions + pure grid/contact math (all tunables).
- `src/server/` — `BallController` (ball physics/arcs/collision + the swept player/bot hit-sphere
  collision), `MatchService` (builds gym + court, player-cell lookup), `HitResolver` (the human's moving
  hit-sphere colliders), `RotationService` (9-rank occupancy + R15 bot rigs cloned from
  `ReplicatedStorage.BotRigTemplate` + layered idle/walk/run/jump anim tracks + `driveOccupant`/`restOccupant`
  rig sync + rotation/dethrone; also owns the **M5.6 seat nameplates** — builds `workspace.NineSquare.Nameplates`
  and relabels them off `byRank` on every occupancy change), `BotController` (per-Heartbeat physical bot hitter:
  predicts the contact, drives an off-center hit-sphere collider into the ball along the aim line, misses by
  under-driving; returns colliders merged into `bc:step`), `NineSquareServer` (bootstrap + Heartbeat + the
  king-of-the-hill loop; merges human + bot colliders into `bc:step`; owns the **M5.1/M5.2 join/leave +
  spectator FIFO queue**, the **M5.4 trust boundary**, and the **M5.6 `HudEvent` feed** — fires join / leave /
  auto-seat / dethrone / King / rank-change toasts).
- `src/client/NineSquareClient.client.luau` — shadow, strike ring, highlight, camera, **spectator overlook
  camera + queue HUD** ("Spectating — #N in line / NEXT UP!").
- `src/client/RankHud.client.luau` — server-authoritative rank pill + King-square indicator + the **M5.6 HUD
  toast feed** (renders `HudEvent` notes; hides the pill while spectating).
- `src/client/Movement.client.luau` — dash, double-jump flip, stamina + HUD bar (client-side, server-validated).
- `docs/` — PRD, specs, plans.

## Continuing on another machine (e.g. Mac)

The git repo is the **source of truth for code**; the Roblox **place** ("9 Square Beta") lives in
the Roblox account (open it from Studio on the Mac).

1. `git clone` this repo on the Mac.
2. The MCP server is the **official Roblox one built into Studio** — nothing to `npm install`
   and no companion plugin. The repo's `.mcp.json` already points Claude Code at the binary:
   ```json
   { "mcpServers": { "robloxstudio": {
       "command": "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP" } } }
   ```
   On first run, approve the project-scoped server when Claude Code prompts
   (`claude mcp list` should then show it ✔ Connected). Studio must be open with the place loaded.

   **Critical — enable Studio as an MCP server, or the client connects but shows _no tools_.**
   The binary is only a bridge; Studio has to opt in to serving tools. In Studio: open the
   **Assistant** panel → **…** → **Manage MCP Servers** → turn on **"Enable Studio as MCP server."**
   Enable this *before* the client connects (Studio must be serving first), then restart/reconnect
   Claude Code so it re-fetches the tool list. Requires the latest Roblox Studio.
3. Open the "9 Square Beta" place in Studio.
4. Deploy `src/*.luau` into Studio with the `multi_edit` tool onto the fixed instance paths
   (mapping table at the top of the M1 plan); `multi_edit` creates a script if the path doesn't
   exist yet. Use `script_read` / `script_grep` to inspect, and `execute_luau` for one-off setup.
   The server bootstrap rebuilds the court/gym on Play.

**Note:** unlike the old community plugin, the official server **also works during Play/Test** —
`start_stop_play`, `console_output`, `screen_capture`, and `playtest_subagent` let you launch and
observe a play session over MCP, so gameplay can be verified without doing it all by hand.

### MCP tool reference (`StudioMCP`)

Tools surface in Claude Code as `mcp__robloxstudio__<tool>`. The ones this project uses:

| Tool | Use for |
| --- | --- |
| `multi_edit` | Deploy/edit a script at a dot-notation path; **creates** it if missing. |
| `script_read` | Read a script (whole or line-range). |
| `script_search` / `script_grep` | Fuzzy-find scripts by name / pattern-search across all scripts. |
| `search_game_tree` | Dump the instance hierarchy as JSON (filter by path/type/keyword). |
| `inspect_instance` | Properties + attributes of an instance. |
| `execute_luau` | Run arbitrary Luau (one-off setup, building instances, assertions). |
| `start_stop_play` | Start/stop a play session. |
| `console_output` / `screen_capture` | Read gameplay logs / capture the viewport during Play. |
| `playtest_subagent` | Spawn test characters for gameplay scenarios. |
| `character_navigation`, `keyboard_input`, `mouse_input` | Simulate player input during Play. |
| `list_roblox_studios` / `set_active_studio` | List connected Studio instances / pick the active one. |

Asset generation (`generate_mesh`, `generate_material`, `generate_procedural_model`,
`insert_from_creator_store`) is available but unused — this game is built from primitives in code.
