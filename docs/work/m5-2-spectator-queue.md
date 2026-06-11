# M5.2 — Spectator overflow queue + auto-join

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`. Depends on **M5.1**
(the seat model + the leave-backfill hook).

## Problem
When more than 9 players are present, the extras need somewhere to go. Decision: they **spectate** and
**auto-join the next freed seat** (a live FIFO queue), so humans always get priority over bots.

## What to build
- **Server FIFO spectator queue.** Spectators exist only when humans > 9. A joining player beyond the 9
  seats is added to the queue and put in **spectator state** (no seat, no ball collider, spawned in the
  gallery — gallery itself is M5.3; for now spawn them clear of the court / at a placeholder overlook).
- **Auto-seat priority:** whenever a seat could be filled — a human leaves, OR a spectator is waiting while
  a **bot** still holds a seat — seat the **longest-waiting spectator** (enter at the entry rank,
  displacing a bot), via the hook M5.1 exposed. Net: bots only ever hold seats no human (seated or queued)
  wants; a freed seat goes to a spectator before a bot.
- **Spectator client state:** a court-overlook camera + a small "Spectating — #N in line" HUD; flip cleanly
  to the normal seated camera/HUD when auto-seated (and back to spectator if they later leave their seat —
  they don't; only leaving the game removes them).
- **Lifecycle:** a spectator disconnecting is removed from the queue cleanly; queue order stable; no
  double-seating, no lost ball, no wedged seat.

## Acceptance criteria
- With 9 humans seated, a 10th+ joiner becomes a spectator with a queue position HUD and a court-overlook
  view (no seat, can't affect the ball).
- When a seated human leaves, the longest-waiting spectator is auto-seated at the entry rank (and a bot
  fills only if the queue is empty).
- Queue order is FIFO + stable; disconnecting spectators leave the queue cleanly. Verified via the MCP
  (simulate >9 occupants — real extra clients if possible, else script-driven fake seats/queue entries to
  exercise the logic + log the queue). Studio left in Edit.

## Relevant files
- `src/server/RotationService.luau` / `src/server/NineSquareServer.server.luau` — the queue + auto-seat on
  the M5.1 leave/backfill hook; spectator state per player; remote/attribute to tell the client it's
  spectating + its queue index.
- `src/client/*` — spectator camera + queue HUD; switch to seated mode on assignment.
- `src/shared/GridConfig.luau` — any queue/overlook tunables.
- Build/verify via the robloxstudio MCP (mode flip-flops; stale-require gotcha — verify via console logs of
  the queue + seat transitions; leave Studio in Edit).

## Constraints
- Spectators must NOT affect the ball (no collider, no scoring). Server-authoritative queue. Keep M5.1's
  occupancy invariants (always full 9-square, no empty rank). The gallery SPAWN POINT comes in M5.3 — here
  just spawn spectators clear of the court / at a temporary overlook so the queue logic is testable.
