# 9 Square in the Air (Roblox)

A multiplayer king-of-the-hill volley game for Roblox, based on the playground game
*9 Square in the Air*. Built live in Roblox Studio via the official **Roblox Studio MCP
server** (`StudioMCP`, which ships inside Roblox Studio).

## Status

**Milestone M1 (greybox) — complete** (accepted 2026-06-10, tagged `m1-greybox`). **M2 is next.**
Playable single-player loop in the place **"9 Square Beta"**: enclosed gymnasium scene, 3×3 court,
physical serve + contact volley, self-square / out-of-bounds faults, soft ball shadow, fixed court
camera. Acceptance results + final tuned values are in the M1 design spec (§ "M1 Acceptance").

## Docs

- Master PRD: [`docs/9-square-prd.md`](docs/9-square-prd.md)
- M1 design spec: [`docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md`](docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md)
- M1 plan: [`docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md`](docs/superpowers/plans/2026-06-09-nine-square-m1-greybox.md)

## Build milestones (PRD §15)

1. **M1** — Greybox arena + readability + physical contact volley.  ✅ *done (`m1-greybox`)*
2. **M2** — Hit resolver: timing tiers + scatter on the same contact.  ← *current*
3. **M3** — Full grid + rotation + dethrone.
4. **M4** — Bots fill empty squares; solo play fully functional.
5. **M5** — Networking hardening / anti-cheat.
6. **M6** — Progression, leaderboard, audio/VFX, mobile tuning.

## Key design decisions (evolutions from the PRD)

- **Server-authoritative, deterministic** ball arcs — no client-side physics.
- The hit is a **physical contact volley**: get under the ball and jump; you must *reach* the frame
  plane (jump apex) **and** *touch* the ball. **Serving is physical too** (no button) — the ball
  hovers at center and you strike it.
- **Contact-aim**: outgoing horizontal direction comes from the contact geometry (radial impulse /
  reflection). Vertical pop is a fixed `hitSpeedV` for hang time. Supersedes the PRD aim-assist (§5.4).
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
- `src/server/` — `BallController` (ball physics/arcs/collision), `MatchService` (builds gym + court,
  player-cell lookup), `HitResolver` (contact normal), `NineSquareServer` (bootstrap + Heartbeat).
- `src/client/NineSquareClient.client.luau` — shadow, strike ring, highlight, camera.
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
