# Persistent player stats — best rank reached + turns held (DataStore)

## Problem / goal
Players should have stats that carry across sessions: **how high they got** (best rank reached) and **how
many turns they got in that spot** (turns held at a position, esp. the King throne). Decision: **persistent**
— saved across sessions via a DataStore (a real per-player profile), not session-only.

## Context (current seating/rank model — already implemented, do NOT change)
- 9 seats = ranks 1..9 ↔ cells; **King = rank 1 = C (the BEST rank; lower number = higher)**; entry = rank
  9 (the back of the line). New players join at the back (rank 9); a fault sends the faulter to the very
  back and advances everyone else one toward King. `RotationService.byRank` is the seat source of truth;
  faults/rotation are server-side; `NineSquareServer` runs the rally loop (serve → fault → deferred
  rotation at rest → re-serve).

## What to build
A server-authoritative, persistent **stats system** for HUMAN players (bots don't persist — no UserId;
give bots ephemeral counters or skip them).

### Tracked stats (per human, keyed by UserId)
- **bestRank** — the highest rank reached = the **lowest rank number** ever held (1 = King = best). Update
  whenever the player rotates into a new rank better than their stored best.
- **turnsAtBest** — turns held at that best rank (how long they lasted in their peak spot).
- **kingTurns** — total turns held as King (rank 1) — the marquee stat.
- **totalTurns** — total turns played.
- Define a **"turn"** = one rally (a serve→fault cycle) the player participated in while seated. Increment
  the seated occupant's counters each rally; "turns in that spot" = rallies held at a given rank before
  rotating out.

### Persistence
- Use `DataStoreService` (key per `UserId`, e.g. `NineSquareStats_v1`). Load the profile on join (PlayerAdded),
  merge into the live session, **save on PlayerRemoving + periodic autosave + `game:BindToClose`**.
- **Robustness:** wrap all DataStore calls in `pcall`; if DataStore is unavailable (e.g. Studio without
  "Enable Studio Access to API Services", or a transient failure), **fall back to in-memory** stats for the
  session so the game never errors or blocks — log a clear note. (NOTE for Scott: persistence only actually
  saves when API access is enabled — on a published place it's on; in Studio it requires the Game Settings
  "Enable Studio Access to API Services" toggle, and reads back as in-memory otherwise.)

### Display
- Surface stats in the Roblox **leaderstats** player list (the standard built-in scoreboard): e.g. "Best"
  (best rank) + "King Turns" (and/or "Turns"). leaderstats auto-shows in the player list for everyone.
- Optional: a small in-game scoreboard/HUD panel summarizing the table's best ranks — keep it lightweight
  if added; leaderstats alone satisfies "players will have stats."

## Acceptance criteria
- Each human gets a persistent profile: best rank reached + turns held (at best / as King / total),
  visible in the leaderstats player list, updating live as they climb/hold/rotate.
- Stats persist across sessions when DataStore is available (rejoin restores best rank + turns); when it
  isn't, the game still runs on in-memory stats with no errors (pcall fallback).
- Turn counters increment per rally for the seated occupant; bestRank improves only when a better (lower)
  rank is reached; King turns count only while at rank 1.
- Bots are excluded from persistence (no UserId) and don't corrupt the human stats.
- Server-authoritative (client never writes stats). No regression to seating/rotation/physics/queue/gallery.
  Verified via the MCP. Studio left in Edit.

## Relevant files
- NEW `src/server/StatsService.luau` (or fold into existing server) — the profile model, DataStore load/
  save (pcall + in-memory fallback), per-rally turn increments, bestRank/kingTurns/totalTurns updates,
  leaderstats setup per player.
- `src/server/NineSquareServer.server.luau` — hook the rally/rotation lifecycle (each rally = a turn for the
  seated occupant; rank changes update bestRank/kingTurns); PlayerAdded/PlayerRemoving → load/save.
- `src/server/RotationService.luau` — expose the per-rally seated-occupant info / rank-change signal the
  stats need (read `byRank`; it already tracks human player + rank).
- `src/shared/GridConfig.luau` — stats tunables (DataStore name/version, autosave interval).
- `README.md` — document the stats + the "Enable Studio Access to API Services" requirement for persistence.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  is STALE — verify via `script_read`/`get_console_output` + assertions: simulate rallies/rotations and
  assert leaderstats values update, bestRank improves on climb, King turns count, and the pcall fallback
  path works when DataStore is unavailable. `screen_capture` has been flaky — rely on instance/log
  assertions. Leave Studio in Edit.)

## Constraints
- Persistence/stat-tracking only — don't change seating, rotation, the rally loop, physics, the queue, or
  the gallery; just OBSERVE the loop and record. Server-authoritative; DataStore calls always pcall-guarded
  with an in-memory fallback so the game never breaks if persistence is off/unavailable. Bots excluded.
