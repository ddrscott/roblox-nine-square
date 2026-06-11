# M5.1 — Multi-human occupancy + bot backfill + join/leave

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md` (READ IT). This is the M5
FOUNDATION — everything else builds on the seat model.

## Problem
Occupancy is hard-wired for ONE human: `RotationService` seats the local player at rank 9 / NW and fills
ranks 1..8 with bots; `NineSquareServer` serve/fault/rotation assume that single human. To play with
friends, occupancy must support N humans with bots backfilling.

## What to build (decision: humans fill, bots backfill — always a full 9-square)
- **Seat model:** `RotationService.byRank[1..9]` becomes the single source of truth, each entry
  `{ kind = "human"|"bot", player?, id, rank, cell, isDummy }`. Rank 1 = King = C. Keep the existing
  rank↔cell map (`GridConfig.rankCells`) and rotation/dethrone math.
- **Join (PlayerAdded / and any already-connected players at boot):** seat the joining player at the
  **entry rank** (the highest-numbered seat, farthest from King) by **displacing the bot** there; that bot
  is removed/recycled. If multiple humans join, each takes the next-highest open seat. Humans always
  outrank bots — bots are pure backfill.
- **Leave (PlayerRemoving):** the leaver's seat is filled by (1) the longest-waiting spectator if the queue
  exists (M5.2 will own the queue; for THIS task just expose a hook + default to a bot), else (2) a fresh
  bot. Never leave a rank empty.
- **Generalize the loop:** `serveNextRally` / fault / rotation must work for ANY occupant. The King serve
  already branches human-King (physical hover-serve) vs bot-King (auto-serve) — make it key off
  `byRank[1].kind`/player, not a single hard-coded human. Faults/saves/rotation already server-side; make
  sure they reference the seat occupant, not "the human".
- **Per-human client binding:** each human's court camera / rank HUD / movement / hit-sphere must bind to
  THAT player's server-assigned seat. The clients key off LocalPlayer already — make the server replicate
  each player's current rank/cell (e.g. a per-player attribute or a replicated occupancy table) so each
  client reads its own seat (and the human's hit collider is fed to `bc:step` from the server for the
  seated humans, same as today for the one human).

## Acceptance criteria
- With 1 human + 8 bots: plays exactly as today (no regression).
- Simulate 2–3 players (Studio local multiplayer: Play with 2–3 players, or script-spawn extra humanoids /
  fake occupants if true multi-client isn't available in this MCP) — each takes its own seat, bots fill the
  rest, the 9-square is always full; each human controls only its own seat.
- A player leaving backfills with a bot (no empty rank, no crash); a player joining displaces the
  lowest-status bot at the entry rank.
- Rotation, dethrone, King serve (human OR bot King), faults, saves all still work with a human/bot mix.
- Server-authoritative + deterministic preserved; the abstract bot hit-sphere collider unchanged. Verified
  in Play via the MCP; Studio left in Edit.

## Relevant files
- `src/server/RotationService.luau` — the seat model + join/leave + bot create/recycle + placement.
- `src/server/NineSquareServer.server.luau` — PlayerAdded/PlayerRemoving wiring, serve/fault/rotation
  generalized to N humans, per-player seat replication, feeding seated-human colliders to `bc:step`.
- `src/client/*` (RankHud, NineSquareClient, Movement, HitSphereView) — read the server-assigned seat for
  the LocalPlayer (camera/HUD/collider bind to the right cell).
- `src/shared/GridConfig.luau` — any new occupancy tunables (entry rank already = #ranks).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; stale-require gotcha
  — verify via `script_read`/`get_console_output`/console logs of seat assignment; leave Studio in Edit).

## Constraints
- Don't change the ball physics / swept collision / strike / save-fault / rotation MATH — only WHO occupies
  seats and how they're assigned. Keep it deterministic + server-authoritative. Expose a clean hook for the
  M5.2 spectator queue to override the leave-backfill (spectator before bot).
