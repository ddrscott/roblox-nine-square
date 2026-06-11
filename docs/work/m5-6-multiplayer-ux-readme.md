# M5.6 — Multiplayer UX + README + playtest checklist (close out M5)

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`. The polish + docs that make
the friends playtest legible. Do this LAST (depends on M5.1–M5.5).

## Problem
With multiplayer + spectators live, players need to SEE who's who and where they stand, and Scott needs a
written way to run the friends test. Today there's a local rank pill + King square; that's not enough for
N humans + a spectator queue.

## What to build
- **Nameplates over seats:** each occupant (human + bot) shows a name/label over their seat — who is King,
  who's in which square — so a table of friends can tell themselves apart. Highlight the King.
- **Spectator / queue HUD:** for spectators, "Spectating — #N in line / next up"; for seated players, their
  current rank + a nudge when they're about to be dethroned or when they take the King.
- **Join / leave + rotation feedback:** a brief on-screen note when a player joins, leaves, is auto-seated
  from the queue, gets dethroned, or becomes King (lightweight, non-spammy).
- **README:** update with the M5 architecture (occupancy/seating, spectator queue, gallery, server-
  authority model) and a **"How to test with friends"** checklist (how to start, how seats fill, how
  overflow/spectating works, what to look for). Keep README current per project rule.
- **Playtest pass:** a final multi-occupant run confirming the whole M5 loop end-to-end.

## Acceptance criteria
- Each seat shows who occupies it (human name or bot), King clearly marked; spectators see their queue
  position; join/leave/rotation/dethrone/King events give brief feedback.
- README documents the M5 multiplayer + lobby architecture and a clear friends-test checklist.
- A final playtest run shows the full loop working (join → seat/backfill → rotate → dethrone → leave →
  spectator auto-join) with no errors. Verified via the MCP; Studio left in Edit.

## Relevant files
- `src/client/RankHud.client.luau` (+ a new nameplate/spectator HUD client as needed) — nameplates, queue
  HUD, event feedback.
- `src/server/*` — fire the per-player events the HUD needs (rank/King/queue/join-leave), if not already
  exposed by M5.1/M5.2.
- `README.md` — M5 architecture + friends-test checklist (source of truth, keep current).
- Build/verify via the robloxstudio MCP (mode flip-flops; verify in Play + console; Edit).

## Constraints
- UX/docs only on top of M5.1–M5.5 — don't change occupancy/queue/physics logic, just surface it. Keep the
  HUD lightweight and non-spammy. Server-authoritative data feeds the client (don't trust the client for
  who's King / queue order).
