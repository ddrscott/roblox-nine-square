# 9 Square — M5: Multiplayer + Lobby (design)

Status: **proposed** (awaiting accept)
Date: 2026-06-10
Goal: a build Scott can actually play with friends — multiple real players in the 9-square at once,
bots backfilling empty seats, overflow players spectating from an upper-floor gallery and auto-joining
the next freed seat, with the server authoritative enough to trust in a real session.

## Decisions (from Scott)
1. **Seating:** humans fill seats; **bots backfill** the rest → it's always a full 9-square (3 friends =
   3 humans + 6 bots).
2. **Overflow:** players beyond the 9 seats **spectate from the upper gallery** and **auto-join the next
   freed seat** (a live FIFO queue).
3. **Scope:** **fuller M5** — multiplayer + server-authority hardening / anti-cheat / edge cases, not just
   a thin MVP.
4. **Build with 3D assets** (creator-store models) so the environment is easy to tweak. Scott cannot edit
   in Studio himself — every change ships via the robloxstudio MCP.

## Where we are today (the gap)
- Occupancy is hard-wired for **one** human: `RotationService` seats the local player at rank 9 / NW and
  fills ranks 1..8 with bot dummies; `NineSquareServer` serve/fault/rotation assume that single human.
- Clients (camera, HUD, movement, hit-sphere) are already per-player and replication-friendly, but nothing
  assigns a *joining* player a seat, handles a *leaving* player, or supports >1 human.
- The ball + scoring (faults/saves/rotation/dethrone) are already server-authoritative and deterministic —
  the trust model is mostly there; the player's *contribution* (HRP velocity into the strike, stamina/dash)
  is client-driven and not yet validated.

## Architecture

### Occupancy model (the core rework)
- A **seat** = a rank 1..9 ↔ cell (C,N,NE,E,SE,S,SW,W,NW); King = rank 1 = C. Each seat's occupant is
  either a **human `Player`** or a **bot**. `RotationService` becomes the single source of truth for
  `byRank[1..9] = { kind = "human"|"bot", player?, id, rank, cell, isDummy }`.
- **Join:** a player entering takes the **highest-numbered open-ish seat** (the entry rank, farthest from
  King) by **displacing the bot** that currently holds the lowest-status seat — so every human starts at
  the bottom and earns their way toward C. Humans always outrank bots for a seat (bots are pure backfill).
- **Leave:** the leaver's seat is filled by (1) the longest-waiting **spectator** if any, else (2) a
  **bot**. Ranks are never left empty → always a full 9-square.
- **Rotation / dethrone:** unchanged mechanically — occupants (human or bot) cyclically shift on a fault,
  King dethroned at rank-1 fault. Serve already branches human-King (physical hover-serve) vs bot-King
  (auto-serve); generalize so ANY human King serves and ANY bot King auto-serves.
- **Per-human client:** each human gets its OWN court camera / rank HUD / movement / hit-sphere bound to
  *their* seat (the existing clients key off the LocalPlayer; ensure they read the server-assigned seat).

### Spectator overflow + auto-join queue
- Spectators exist only when **humans > 9**. Extra joiners go into a server FIFO **spectator queue** and
  spawn in the **upper gallery** (below).
- On any seat freeing (a human leaves, or — proactively — whenever a spectator is waiting AND a bot still
  holds a seat), the **longest-waiting spectator is seated** (enters at the entry rank, displacing a bot).
  Net effect: humans always get priority; bots only ever hold seats no human (seated or queued) wants.
- Spectator client: a court-overlook camera from the gallery + a small "you're #N in line" HUD.

### Upper-floor spectator gallery (3D assets)
- Build an **upper floor / mezzanine** above the existing gym with a **viewing opening over the court**
  ("knock out a window" — an opening in the gallery floor/wall that looks straight down onto the 9-square).
- Spectators **spawn here** and can walk the gallery and watch the match below through the opening.
- Use **creator-store 3D assets** (railing, windows/frames, benches/bleacher seating, light decor) so the
  space is tweakable. Keep it OUTSIDE the court collision sets (never feeds the ball/player collision).
- A `SpawnLocation` (or scripted spawn) in the gallery for spectators; seated players spawn at their seat.

### Server-authority / anti-cheat (the "fuller M5" part)
- **Trust boundary:** the server owns the ball, all contact resolution, scoring, seats, rotation, serve,
  and the queue. The client may only *propose* its character's position/velocity.
- **Validate the player's strike contribution:** the strike reads replicated HRP velocity — clamp it to a
  plausible max derived from the movement tunables (walk + dash + jump), and reject/clamp implausible
  teleport jumps in position, so a client can't spoof a super-hit or warp into the ball.
- **Server-owned economy:** stamina / dash / flip gating validated server-side (or at least
  sanity-checked), not blindly trusted from the client.
- **Lifecycle robustness:** handle disconnects mid-rally / mid-serve / while King; the queue and backfill
  must never wedge (no empty seats, no double-seating, no lost ball).
- Rate-limit remotes; ignore inputs from players not seated (spectators can't affect the ball).

## Task sequence (each is a queued work item; build + verify in Studio via MCP)
- **M5.1 — Multi-human occupancy + bot backfill + join/leave.** The foundation: seat model, join displaces
  a bot at the entry rank, leave backfills (spectator→bot), rotation/serve generalized to N humans. Verify
  with 2+ simulated players.
- **M5.2 — Spectator overflow queue + auto-join.** FIFO queue, seat the longest-waiting spectator when a
  seat frees / a bot is displaceable; spectator state + court-overlook camera.
- **M5.3 — Upper-floor spectator gallery (3D assets).** Build the mezzanine + viewing opening + spectator
  spawn from creator-store models; spectators spawn and watch from here.
- **M5.4 — Server-authority hardening / anti-cheat.** Clamp/validate player velocity+position into the
  strike, server-side stamina/economy checks, disconnect/lifecycle robustness, remote rate-limits.
- **M5.5 — Bot-King outward-clearing fix.** The tracked bug: a bot holding center over-verticalises its
  hit and self-rallies in C. Give the center seat a flatter outward drive so bot Kings distribute (matters
  for partial/all-bot games and the demo's idle moments).
- **M5.6 — Multiplayer UX + README + playtest checklist.** Nameplates over seats, spectator/queue HUD,
  join/leave feedback; update README with the M5 architecture + a "how to test with friends" checklist.

## Acceptance (milestone)
- 2–9 friends can join and each controls their own seat; bots backfill the rest; rotation/dethrone/serve
  all work with any mix of humans and bots.
- A 10th+ player spectates from the gallery and is auto-seated when a seat frees.
- The gallery (3D-asset build) overlooks the court through an opening; spectators spawn there.
- A client cannot spoof an oversized hit or warp into the ball; disconnects don't wedge the game.
- Verified in Studio (multi-player simulation) via the MCP; README updated; Studio left in Edit.

## Notes / constraints
- Keep the deterministic, server-authoritative ball + the abstract bot hit-sphere collider (don't let rig
  or gallery parts into the ball/player collision sets).
- 3D-asset builds: source via the MCP creator store; keep them tweakable and out of the collision sets.
- All work ships via the robloxstudio MCP (Scott can't hand-edit Studio); leave Studio in Edit after each.
