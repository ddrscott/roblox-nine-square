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
- **Camera (seated/court) — desktop + mobile parity** (`NineSquareClient.client.luau`): a high court
  overview you can **zoom** (mouse-wheel on desktop, **two-finger pinch** on touch — both drive the same
  `zoom` 0..1 lerp between the far/near eye+look offsets) and **toggle to follow-the-player** (LeftShift on
  desktop, an on-screen **"Camera" button** on touch — shown only when `TouchEnabled` and no keyboard). On
  touch the zoomed-out framing **fits the whole 3×3 grid** regardless of aspect: `fitEyeForGrid` projects the
  four grid corners (+`camFitMarginStuds`) each frame against the live `Camera.ViewportSize` aspect, widens
  `FieldOfView` up to `camMobileMaxFOV`, then pulls the eye back along its own direction (capped by
  `camFitMaxDistScale`) until the worst corner fits — so a phone opens on the full court (pulling past the
  south wall is fine; the **wall-fade** handles it). Desktop mouse-wheel + LeftShift are unchanged; the
  spectator overlook camera (M5.2) is separate. Tunables: `camBaseFOV`, `camPinchSensitivity`,
  `camFitMarginStuds`, `camMobileMaxFOV`, `camFitMaxDistScale` in `GridConfig`.
- **Faults**: a ball that returns to the square it was struck from is a *self-fault*; landing outside
  the 9 squares is *out-of-bounds*. Both flash the square + play the oof sound, then re-serve.
- **Scene**: an enclosed gym (`MatchService.buildGym`, build-once) with painted floor grid lines so
  the grid reads in Play even when dynamic shadows don't render.
- **Build-once / self-heal world (tweak in Studio, it sticks)**: the arena, gym, gallery, and outdoors are
  **built once** — the **saved place (`.rbxl`) is the source of truth for how everything LOOKS.** `buildArena`
  no longer wipes + rebuilds `workspace.NineSquare` each Play; it only sets `G.origin` (runtime positioning)
  and then **builds only the sub-groups that are MISSING** (`ensureGroup` per `Floors` / `FloorNumbers` /
  `Frame` / `FrameLegs` / `GridLines` / `SaveHighlight` + a self-healed `CourtSpawn`). `setupLighting` is
  **apply-once** behind a `Lighting.NineSquareLit` attribute sentinel (Sky/Atmosphere self-heal only if
  missing). **So: tweak any part in Studio (color, size, material, position) or the lighting/sky, then
  Publish/Save — the scripts won't overwrite it.** (Verified: GridLines set solid white in Edit stays white
  after Play; deleting `NineSquare`/Sky and the sentinel rebuilds the full world on Play.) Kids can freely
  re-color/move parts; they should avoid **DELETING** the functional ones — the `Frame` beams (the ball
  collides off these via `BallController._surfaces`) and the `Floor_*` markers (fault-flash targets) — but
  even those **self-heal** (rebuild) if removed. To force a one-time re-stamp of the defaults, delete the
  `Lighting.NineSquareLit` attribute (lighting) or the relevant `NineSquare` sub-folder (geometry).
  - **The HUD follows the same model.** `StarterGui.NineSquareHUD` is an **authored, saved instance tree in the
    place** (like `BotRigTemplate` / `OutdoorTreeTemplate` — **it must persist in the saved `.rbxl`** for the
    designed layout to ship; the editor-authored tree is the source of truth for how the HUD LOOKS). Client
    scripts only **bind** to it and **self-heal** a default tree (via `HudBuilder`) only if it's MISSING — so
    Studio GUI-editor tweaks stick across Play→Edit and a fresh place still works. (Verified: the authored
    `NineSquareHUD` survives a Play→Edit cycle un-clobbered.)
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
- **Side windows are REAL cut-outs (not decals)**: each E/W gym wall (`WallE`/`WallW`) is built by
  `MatchService.buildWindowedWall` as a **frame of solid panels around a genuine rectangular gap** — a bottom
  panel (`WallE_Bottom`), a top panel (`WallE_Top`), and two Z-end panels (`WallE_EndN`/`_EndS`) — with a
  light-passing **Glass pane** (`WallE_Glass`, `Material=Glass`, `CastShadow=false`) set INSIDE the gap and NO
  opaque part behind it, so outdoor light + sky actually reach the interior (the old approach glued a thin
  glass strip onto a solid slab — purely decorative, no light passed). Placement/size + glass transparency are
  `GridConfig` tunables (`windowCenterY`/`windowHeight`/`windowLength`/`windowGlassTransparency`/
  `windowGlassColor`). The frame panels carry the `WallE`/`WallW` **name prefix** so the camera **wall-fade**
  (now matched by prefix in `NineSquareClient`) still fades the whole windowed wall when the eye clips it; the
  glass pane keeps its own resting transparency (the fade skips `*_Glass`). Frame panels are `Locked=true`
  (click-through shell, like the rest of the gym); the glass pane is left unlocked. The windowed wall is a
  pure gym-shell part (lives OUTSIDE `NineSquare.Frame`), so the ball/player court collision is untouched.
  - **Invisible ball-barrier seals each window to the BALL** (`WallE_Barrier`/`WallW_Barrier`): the glass pane
    is light-passing and **excluded** from the ball's surface collision (`BallController._surfaces` skips
    `Glass`/`Neon`), and the frame panels only ring the gap — so a hard hit toward a side window used to fly
    **straight through the opening into the outdoors** (the escape that hung the rally). Each opening is now
    sealed to the **ball only** by an invisible slab co-located with the glass, spanning the gap +
    `windowBarrierMargin` (so a glancing edge hit can't slip past). It is `Transparency=1` + `CastShadow=false`
    (the window stays **visually open** — light + the view still pass) and `CanCollide=false` (OUT of the
    **player** collision); the ball collides with it anyway because `BallController._collide` is a pure
    sphere-vs-box test that ignores `CanCollide` (it only skips `Floor`/`Glass`/`Neon`). It carries the
    `WallE`/`WallW` prefix so it joins the wall-fade set, but the fade **skips** `*_Barrier` too (fading would
    make the invisible barrier visible when the eye is inside). Tunables: `windowBarrierMargin`,
    `windowBarrierThickness`. Build-once: created in `buildWindowedWall`; a one-time MCP pass stamped the two
    barriers onto the already-built `Gym` in the saved place.
- **Outdoor environment + clear-day sky**: `MatchService.buildOutdoors` (called from `buildGym`, build-once)
  adds a backdrop so the side windows (now real cut-outs, above) and the camera **wall-fade** (which makes a
  gym wall fully transparent) reveal a **grassy park** instead of empty void / bare skybox. It builds a large grass ground
  plane whose TOP sits just BELOW the gym floor (`y = -outdoorGroundDrop`, so the opaque wood floor still
  covers the court and the grass never shows inside the play surface), gentle low rolling hills, and scattered
  trees ringing the gym. The scatter is **deterministic** (fixed `GridConfig.outdoorScatterSeed`). Lighting is
  a **clear day** — `setupLighting` sets a midday `ClockTime` (`outdoorClockTime`), a bright-blue `Sky`
  (`ClearDaySky`, visible sun via `skySunAngularSize`, soft default clouds) + a subtle `Atmosphere` for horizon
  depth — while the **interior gym lighting is unchanged** (same `Ambient` lift + Neon ceiling fixtures + Bloom
  threshold). Everything outdoors is purely visual: every part is `CanCollide=false` + `CanQuery=false` and
  lives in its OWN top-level `Workspace.Outdoors` folder (NOT under `NineSquare.Frame`), so it never enters the
  ball (`BallController._surfaces`) or player collision sets and never intrudes on the court. All extents/counts
  /positions + sky settings are `GridConfig` tunables (`outdoor*`, `sky*`, `atmosphere*`).
  - **Asset persistence**: the ground/hills are code-built. The trees clone a creator-store model from
    `ReplicatedStorage.OutdoorTreeTemplate` (inserted once via the Studio MCP, collision-stripped + given a
    `PrimaryPart` so it grounds + scales cleanly). `buildOutdoors` falls back to a simple code tree (trunk +
    foliage spheres) if the template is absent — so the build is robust either way. **To keep the nicer trees,
    `ReplicatedStorage.OutdoorTreeTemplate` must persist in the place.**
- **Gym wall decorations (gym + playful rec-center mix) that fade with the wall**: `MatchService.buildWallDecor`
  (called from `buildGym`, build-once + a one-time MCP pass on the persisted `Gym`) decorates the bare interior
  faces of the four gym walls with a tasteful **gym/sporty + playful** mix — a **scoreboard-style sign** + a
  **wall clock** + **pennant bunting** (`WallN`), **championship banners** (`WallS`, kept high above the
  basketball hoop), a bright **color-blocking mural** + a poster (`WallE`, clear of the window gap), and
  **pennant bunting** + a poster + base **wall-padding trim** (`WallW`/others). Every piece is **cosmetic only**:
  `CanCollide=false` + `CanQuery=false` + `CanTouch=false`, sits a hair off the wall face toward the court
  (`GridConfig.wallDecorOffset`, far short of the play volume), and lives in a **`WallDecor` folder parented
  UNDER that wall's part** — so it is **NOT** under `NineSquare.Frame` (never enters the ball/player collision
  sets) **and** the camera **wall-fade can find + fade it WITH the wall**. `NineSquareClient.updateWallFade` was
  extended so when a wall is obstructing it also lerps that wall's `WallDecor` descendants toward the same goal
  (BaseParts → `Transparency`, `Decal`/`Texture` → `.Transparency`, SurfaceGui labels → `TextTransparency`/
  `ImageTransparency`) — so the whole decorated wall (structure + banners + clock + posters + signs) vanishes /
  returns together and **nothing floats in view** when the wall is gone. Colours, offsets and copy are
  `GridConfig` tunables (`wallDecor*`); set `wallDecorEnabled = false` to skip. All built from code (no
  creator-store assets required), so nothing extra needs to persist for the decorations.

## M5 — multiplayer + lobby

The build is playable with friends: 2–9 humans share the court, bots backfill the rest, overflow players
spectate + auto-join, and the server stays authoritative. The pieces:

- **Lobby spawn + tap-to-join (entry is button-driven).** A joining human does **not** auto-seat. They spawn
  in the **gallery lobby** (parked at `GridConfig.specSpawnOffset`, overlook camera + HUD) and **watch** the
  live (bot) game until they tap a **"Join Game"** button (a client `ScreenGui` `TextButton`, touch + desktop)
  shown to any non-seated human. The button fires a `JoinRequest` `RemoteEvent`; the **server decides**
  (server-authoritative — the client only requests): if a **bot** seat exists → `seatHuman` at the **entry
  rank** (displaces a bot) + teleport to their court cell; if **all 9 are humans** → enqueue (FIFO), and the
  longest-waiting joiner is auto-seated on the next human-seat freeing (the `_backfillHook`, kept). Button
  state: **"Join Game"** → **"In queue (#N)"** (full) → **hidden** once seated (the seated camera/HUD takes
  over). The M5.2 **proactive "auto-seat spectators into bot seats" sweep is disabled** so lobby watchers are
  never pulled into the court without tapping; **leave→backfill** (queued joiner first, else bot) is kept.
  With **0 humans** the 9 bots play a full, watchable game from the lobby's vantage.
- **Leave → Spectate (step off the court).** The counterpart to Join Game: a **seated** human (Rank > 0, not
  Spectating) sees a **"Leave → Spectate"** button that fires a `LeaveRequest` `RemoteEvent` (self-healed
  alongside `JoinRequest`). The **server** handler frees their seat via `unseatHuman` — the same `_backfillHook`
  seats the longest-waiting queued spectator, else a bot, so the **rank is never empty** — then
  `parkLobbyWatcher` returns them to the gallery lobby (Spectating = true, no rank, roam camera, Join Game
  available again); they re-enter later via Join at the entry rank. If the **King** leaves this way while the
  ball is parked for a hover-serve, it **re-serves** for the new King (the same wedge guard as the disconnect
  path), so the loop never wedges. Server-authoritative — the client only requests.
- **Right-side lobby UI (under the scoreboard).** Join Game, the new Leave → Spectate button, and the
  Spectating / queue pill live in one **right-anchored** `ScreenGui` (`LobbyHud`) stacked vertically **beneath
  the scoreboard** (the stats panel is top-right), so they no longer cover the centre of the view and stay clear
  of the bottom-right mobile camera-mode toggle + the default touch jump button. Compact widths/heights on a
  touch/portrait session; layout tunables are `GridConfig.lobbyUI*`.
- **Fully enclosed foyer (can't fall out).** A roaming spectator stays contained anywhere in the gallery. The
  central opening has its invisible cap (below); the **outer foyer** is enclosed by the four full-span
  perimeter **fall-out walls** (`GalWallN/S/E/W`, `galleryWallHeight = 24` studs — well above a default
  ~7-stud spectator jump — meeting the floor with no gap) + the `GalRoof` on top, while the floor **ring** tiles
  fully around the opening (the N/S bands run the full X span, so the opening corners are floored). Verified by
  walking/shoving the character against every edge + corner in Play (stays contained, never falls to the court
  or off the building). These barriers live in the `Gallery` folder **outside** `NineSquare.Frame`, so they're
  **not** in the ball/player court collision set (the gallery sits above the court).
- **Invisible opening barrier.** A transparent (`Transparency=1`), `CanCollide`, anchored cap
  (`Gallery.OpeningBarrier`) spans the gallery floor opening at `galleryFloorY`, so lobby watchers **can't fall
  through** into the play area while the downward sightline stays clear. Teleporting a seated player **down** to
  their cell is a `CFrame` set that bypasses collision (unaffected). The barrier is `CanQuery=false`, lives in
  the `Gallery` folder **outside** `NineSquare.Frame`, and is never added to `BallController._surfaces` — and
  the ball is already volume-clamped below gallery height anyway, so the barrier's only job is blocking
  **players**.
- **Locked building shell (Studio convenience).** The big enclosing parts are `Locked=true` so they're
  **click-through in the Studio viewport** (select interior objects normally; pick the shell via the Explorer):
  gym `Ceiling*` + `WallE/W/N/S`, gallery `GalRoof` + `GalWall*`. Set at creation in `buildGym`/`buildGallery`
  **and** stamped once on the already-built/persisted shell (Locked persists in the saved place). Interior /
  tweakable parts (floor numbers, grid lines, frame, bench, trees, ball, players) stay **unlocked**. `Locked`
  has no runtime effect — collision/queries/physics are untouched.
- **Occupancy / seating (humans fill, bots backfill).** A **seat** is a rank 1..9 ↔ cell (King = rank 1 = C).
  `RotationService.byRank[1..9]` is the single source of truth — each seat holds either a **human `Player`**
  or a **bot** rig. Every seat starts as a bot, so it's **always a full 9-square**. A joining human takes the
  **entry rank** (the highest-numbered seat a bot still holds, farthest from the King) by **displacing that
  bot** — so everyone starts at the bottom and earns their way to C. Humans always outrank bots. Rotation,
  serve, and dethrone are unchanged mechanically and work for **any** mix of humans and bots (any human King
  hover-serves; any bot King auto-serves).
- **Join queue + auto-join (FIFO).** A player who taps **Join Game** while **all 9 seats are humans** is pushed
  onto a server **FIFO queue** (they keep watching from the gallery). When a **human leaves**, the
  **longest-waiting** queued joiner is auto-seated at the freed rank (the `_backfillHook`); with nobody waiting,
  a fresh bot backfills. (The old M5.2 *proactive* sweep that pulled queued players into **bot** seats is now
  disabled — entry is tap-to-join.) A `Spectating` flag + 1-based `QueuePos` are replicated per non-seated
  human so the client shows the overlook camera + the "Spectating — #N in line / NEXT UP!" HUD and the Join
  button's "In queue (#N)" state; the instant the server seats them they flip back to the seated camera/HUD.
  **Non-seated players never affect the ball** (their colliders are excluded from `bc:step` every frame,
  re-checked against the live occupancy model — a seated human has a rank, a lobby watcher / queued joiner does
  not).
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
    position 1.
  - **Transient notice feed (trimmed).** A `HudEvent` `RemoteEvent` carries `{ kind, text, tone }`; the client
    renders a small, **semi-transparent**, top-left notice that **fades in, holds briefly, then fades out** so
    it flashes and is gone (never persistently over the court). The feed is trimmed to the few moments that
    matter — a brief **"You're in"** on seating, a queue note, and the **King moment** (a personal "You're the
    KING" + a broadcast "X takes the throne"). There are **no** join/leave or rank-change toasts: rank is
    obvious from where you stand + the floor numbers.
  - Tunables (`nameplate*`) live in `GridConfig`.

## Persistent player stats (DataStore)

Every **human** carries a persistent profile across sessions, surfaced in the standard Roblox **leaderstats**
player list (so the stats auto-show for everyone, no custom UI needed). Server-authoritative throughout — the
client never writes a stat. Bots are excluded (no `UserId`; they never persist).

- **Scoreboard = two stats** (this game isn't stats-heavy). The `leaderstats` player list shows only:
  - **`Turns`** — total rallies played while seated.
  - **`TAK`** — **Turns As King** = total rallies held as **King** (rank 1) — the marquee stat.
- **Tracked but not shown** (per human, keyed by `UserId`, still persisted + available via
  `StatsService.getProfile`):
  - `bestRank` — best rank *reached* = the **lowest rank number ever held** (King = rank 1 = best). Improves
    only when a better (lower) rank is reached; a fault-back never worsens it.
  - `turnsAtBest` — rallies held at the best rank (how long they lasted in their peak spot).
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

- **OOB / pipe-escape edge case (MITIGATED — no longer wedges).** On certain outer-bot out-of-bounds hits a
  degenerate surface reflection could give the ball a runaway velocity and fling it to a huge Y (~13,072
  observed). Because the fault rotation is deferred to `bc.onRest` and a ball that high never settles, `onRest`
  never fired → the rally loop wedged. Two server-authoritative safety guards now make a wedge **impossible**
  without touching normal physics feel (both have generous thresholds that only bite on the runaway/escape):
  1. **Speed clamp** — `BallController` clamps the ball's velocity magnitude to `GridConfig.ballMaxSpeed` (280)
     after every launch / strike / reflection / floor bounce, plus a NaN/inf guard, so no interaction can send
     it to Y~13k. The degenerate reflection itself is also hardened (a near-zero / trapped-inside-surface
     contact is ejected without adding energy instead of re-reflecting to a runaway). Normal outgoing speed is
     ~55–130 studs/s, so the clamp never bites legit play.
  2. **Play-volume + settle watchdog** — each Heartbeat, while a ball is in motion, the server checks whether the
     ball has left a sane play volume **or** an armed rally has run past `GridConfig.ballSettleTimeout` (7 s)
     without reaching rest. On either, it **force-resolves** exactly like the normal OOB path — attributes the
     fault to the hitter (`struckCell`/`ownerCell`), applies the deferred rotation, and re-serves — so the loop
     **always** recovers and never waits forever on an `onRest` that won't come. Verified in Studio: the watchdog
     fires on an out-of-volume / non-settling rally and the game continues; normal rallies never trip it.
     - The play volume is now the **gym interior** (`GridConfig.gymHalfExtent` 35 + a small `playVolXZMargin`
       slack), not a loose court+40 box — so a ball that *leaves the gym* (a side window before the barrier
       sealed it, the ceiling opening, any seam) is **immediately** out of volume and force-resolved at once,
       instead of being left to fall/bounce away in a too-large volume (the old loose box let an escaped ball
       sit "in volume" → the rally hung). The out-of-volume check also runs regardless of `rallyArmed` for any
       in-motion ball, so a stray `onLand` on the global floor plane *outside* the gym can't let an escaped ball
       slip past the guard. (Containment fix A — the **window ball-barriers** above — keeps the ball in the gym
       in the first place, so the re-served ball stays contained and there's no re-escape loop.)
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
3. **Climb + rotate.** Rally the ball; on a fault the grid rotates one step toward the King. Your rank is read
   straight off **where you stand + the floor rank numbers** — there are **no** rank-change toasts. Take the
   center square to become **King**: a small gold **KING chip** appears top-left and a brief "You're the KING! 👑"
   notice flashes.
4. **Dethrone.** Fault while King → you drop to Rank 9 and the next occupant takes C; the whole table gets a
   brief "X takes the throne" notice and the King square flashes.
5. **Overflow → spectating.** Add a **10th** player: with all 9 seats human they spawn in the **upper gallery**
   and see **"Spectating — #N in line"** (the longest-waiting shows **"NEXT UP!"**). They look straight down
   onto the court through the gallery opening and **cannot affect the ball**.
6. **Auto-join.** Have a seated player **leave**. The longest-waiting spectator is **auto-seated** into the
   freed rank (a brief "You're in") and the line re-indexes. With no spectator waiting, a fresh bot
   backfills — a seat is never empty.
7. **What to look for:** every seat labeled (human name or "Bot"), King unmistakable, ranks shift cleanly on
   faults, the queue HUD counts down, no errors in the Output, and **no wedged rally**. If the ball ever does
   blow out of the arena or a rally runs long without settling, the **escape/settle watchdog** force-resolves
   it within a few seconds (look for `WATCHDOG force-resolving rally …` in the Output) and play continues —
   the old OOB-escape wedge is mitigated (see *Known issues*).

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
  spectator FIFO queue**, the **M5.4 trust boundary**, and the **trimmed `HudEvent` feed** — fires only a
  brief "You're in" on seating, a queue note, and the King moment; no join/leave or rank-change toasts).
- `src/shared/HudBuilder.luau` — the **HUD's single source of truth** (see "HUD architecture" below):
  `buildInto` constructs the default `NineSquareHUD` tree (mirrors the StarterGui-authored instances),
  `get(playerGui)` resolves the authored HUD (self-healing a default if a fresh place lacks it), `applyScale`
  drives the responsive top-level `UIScale` off the viewport.
- `src/client/NineSquareClient.client.luau` — shadow, strike ring, highlight, camera, **spectator overlook
  camera**, and **binds** the authored HUD's **Join Game / Spectate buttons + Spectating label** (no layout
  built here — `WaitForChild` + state binding only).
- `src/client/RankHud.client.luau` — **binds** the authored HUD: drives the responsive `UIScale`, the top-left
  **KING chip** (only while you hold rank 1), the **transient notice feed** (`HudEvent` notes into the authored
  `ToastHolder`), the **Turns/TAK scoreboard** (mirrors `leaderstats`), + the King-square 3D indicator. Hides
  the bulky built-in PlayerList on phones.
- `src/client/Movement.client.luau` — dash, double-jump flip, stamina (client-side, server-validated); **binds**
  the stamina fill to the authored HUD's stamina bar.
- `docs/` — PRD, specs, plans.

## HUD architecture (StarterGui-authored, layout/scale-driven, Studio-editable)

The HUD is built the **standard Roblox way** and is **Studio-editable**:

- **Authored in `StarterGui`.** A `ScreenGui` `NineSquareHUD` with named component frames lives as **saved
  instances** in the place (editable in the Studio GUI editor). StarterGui clones it into each player's
  `PlayerGui` on spawn (standard). **Build-once / self-heal** like the world build: `HudBuilder.get` returns the
  authored tree **as-is** if present (so Studio tweaks persist across Play→Edit), and only **self-builds a
  default** tree if a fresh place is missing it. `HudBuilder.buildInto` is authored to **mirror** the saved
  instances exactly, so a self-healed HUD is identical to the editor-authored one.
- **Layout containers, not fixed offsets.** Each corner cluster is anchored to a screen corner and arranged by
  **`UIListLayout` + `UIPadding`** so contents **reflow and never overlap**:
  - **top-RIGHT** (`TopRight`): stamina bar → scoreboard (Turns + TAK) → Join Game button → small Spectate
    button → Spectating label, stacked by a `UIListLayout`.
  - **top-LEFT** (`TopLeft`): the KING chip + the transient toast feed (`ToastHolder`), stacked top-down.
- **Resolution-independent.** Widths are **Scale-based `UDim2`** clamped by a `UISizeConstraint`, under a
  top-level **`UIScale` (`HudScale`)** driven off the viewport by `HudBuilder.applyScale` — **one layout scales**
  across phones + desktop (`hud*Scale`/`hud*Width` tunables in `GridConfig`). **No per-device fixed-pixel hacks.**
- **Consistent component language** (`GridConfig.uiStyle`): a **button** always reads tappable (solid fill,
  AutoButtonColor, stroke edge) and a **label/panel** always reads static (flat low-opacity bg, no stroke or a
  faint hairline, lighter font). Join Game is a calmer **medium-weight** button; Spectate is small + low-key;
  Spectating + the scoreboard + the KING chip are labels; the stamina bar shows a readable **caption above the
  fill track**.
- **Client scripts only BIND** (text / bar fill / `Visible` / `button.Activated` → `JoinRequest`/`LeaveRequest`)
  — same data, same remotes, same events; only the GUI construction + layout changed.

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
   The server bootstrap **self-heals** the court/gym on Play (build-once: it only builds what's MISSING, so
   manual Studio tweaks to existing parts persist — see "Build-once / self-heal world" above).

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
