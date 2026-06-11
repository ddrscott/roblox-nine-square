# 9 Square in the Air (Roblox)

A multiplayer king-of-the-hill volley game for Roblox, based on the playground game
*9 Square in the Air*. Built live in Roblox Studio via the official **Roblox Studio MCP
server** (`StudioMCP`, which ships inside Roblox Studio).

## Status

**Milestone M4 (bots fill the empty squares; solo play fully functional) — complete** (accepted
2026-06-10). M1 greybox is tagged `m1-greybox`; M2 folded into the M1 contact model; M3 built the
grid + rotation + dethrone. **M5 (networking hardening / anti-cheat) is next.** Solo play in the place
**"9 Square Beta"** is now a full game: the 8 non-human squares are **bots** that serve (when King) and
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
- **M4 design spec** (current): [`docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md`](docs/superpowers/specs/2026-06-10-nine-square-m4-bots-design.md)

## Build milestones (PRD §15)

1. **M1** — Greybox arena + readability + physical contact volley.  ✅ *done (`m1-greybox`)*
2. **M2** — Hit resolver: timing tiers + scatter.  *folded into the M1 contact model* — the
   velocity-proportional, contact-geometry strike (direction from where you hit it, power from your
   velocity, dash-jump momentum) already makes timing + positioning matter continuously, which is
   what discrete tiers were a proxy for. **Scatter dropped** to keep contact deterministic + skill-
   expressive (revisit only if play ever feels too predictable).
3. **M3** — Full grid + rotation + dethrone.  ✅ *done (accepted 2026-06-10)*
4. **M4** — Bots fill empty squares; solo play fully functional.  ✅ *done (accepted 2026-06-10)*
5. **M5** — Networking hardening / anti-cheat.  ← *current*
6. **M6** — Progression, leaderboard, audio/VFX, mobile tuning.

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

## Known issues / next steps

- **Pipe/wall collision is dormant.** `BallController:_collide` correctly bounces the ball off the
  frame pipes + gym walls, BUT with the current high apex (~24) vs frame height (11) the ball arcs
  4–6 studs clear of every pipe and never reaches the walls — so it visually passes through the
  *open squares* of the frame and never touches a bar. To make pipes interactive, **flatten the
  trajectories** (lower `hitSpeedV` and/or raise `hitSpeedH`, or lower the apex relative to the
  frame) so the ball crosses the frame plane nearer pipe height between squares. (Verified via a
  trajectory sim: closest pipe approach 4.05 studs vs ball radius 2.0.)
- `Lighting.Technology` can't be set by script — set it to **ShadowMap/Future** in Studio Properties
  if you want real dynamic shadows (painted grid lines mean you don't strictly need it).

## Layout

- `src/shared/GridConfig.luau` — dimensions + pure grid/contact math (all tunables).
- `src/server/` — `BallController` (ball physics/arcs/collision + the swept player/bot hit-sphere
  collision), `MatchService` (builds gym + court, player-cell lookup), `HitResolver` (the human's moving
  hit-sphere colliders), `RotationService` (9-rank occupancy + R15 bot rigs cloned from
  `ReplicatedStorage.BotRigTemplate` + layered idle/walk/run/jump anim tracks + `driveOccupant`/`restOccupant`
  rig sync + rotation/dethrone), `BotController` (per-Heartbeat physical bot hitter: predicts the contact,
  drives an off-center hit-sphere collider into the ball along the aim line, misses by under-driving;
  returns colliders merged into `bc:step`), `NineSquareServer` (bootstrap + Heartbeat + the king-of-the-hill
  loop; merges human + bot colliders into `bc:step`).
- `src/client/NineSquareClient.client.luau` — shadow, strike ring, highlight, camera.
- `src/client/Movement.client.luau` — dash, double-jump flip, stamina + HUD bar (client-side).
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
