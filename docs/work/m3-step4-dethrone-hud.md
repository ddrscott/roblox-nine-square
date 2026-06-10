# M3 step 4: dethrone emphasis + minimal rank/King HUD

See the M3 design spec `docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md` (§7, §9
step 4). Steps 1–3 give the full rotation loop. This step adds the feedback that makes it legible: a
dethrone moment + a minimal HUD so the player knows their rank and who's King. Final closeout of M3.

## Build
### A. Dethrone emphasis
- Hook `RotationService.onDethrone` (fired in step 2 when the King faults). On dethrone: a clear emphasis
  — flash the King square (reuse `MatchService.flashCell("C")` or a crown/colour pulse), play a distinct
  sound, and a `print("[NineSquare] DETHRONED — <new King> takes the throne")`. M3 stub is fine; full
  VFX/banner is M6.

### B. Minimal HUD (client)
- Replicate the **local player's current rank** to their client (server-authoritative). Simplest:
  set a player attribute (e.g. `plr:SetAttribute("Rank", rank)`) whenever rotation changes ranks; the
  client reads/observes it. (Or a small RemoteEvent.)
- A small client HUD (in `NineSquareClient` or a new `RankHud` LocalScript) showing the local rank, e.g.
  `Rank 4` or `KING` when rank == 1.
- Indicate the **King square**: highlight cell `C` (a crown icon, a coloured ring, or reuse the
  SelectionBox highlight) so players can see the throne. Update if needed.

## Acceptance criteria
- When the King faults, there's an unmistakable **dethrone moment** (King-square flash + distinct sound +
  console line) and the rank-2 occupant becomes King.
- The local player sees their **current rank** on a HUD, and it updates live as they climb / get
  knocked back.
- The **King square is visibly indicated**.
- Server-authoritative (rank comes from the server, not computed on the client). Verified in Play: rotate
  a few times, watch the HUD rank change and the King indicator move; trigger a King fault and confirm the
  dethrone emphasis.

## Relevant files
- `src/server/RotationService.luau` — fire `onDethrone`; set the per-player `Rank` attribute on rotation.
- `src/server/NineSquareServer.server.luau` — wire `onDethrone` to flash/sound; ensure rank attributes
  set on the human at spawn + each rotation.
- `src/server/MatchService.luau` — `flashCell` reuse for the King-square emphasis if helpful.
- `src/client/NineSquareClient.client.luau` (or a new `src/client/RankHud.client.luau`) — the rank HUD +
  King-square indicator. Client reads the replicated rank (attribute/RemoteEvent).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops; leave Studio in Edit).

## Constraints
- Keep it minimal — this is M3 legibility, not M6 polish (no leaderboard, reign timer, or full VFX).
- Server owns rank/King; client only displays. Don't break the rotation loop, contact, camera, or the
  no-trip fix.

## After this: M3 is complete
With steps 1–4 done, the king-of-the-hill loop runs solo (human + 8 dummies): the King serves, faults
rotate everyone toward the centre, the human can climb to King, and a King fault is a dethrone — which
fulfils the M3 goal. Record M3 acceptance in the M3 design spec (a "## M3 Acceptance" section) and
update the README milestone status to mark M3 done; then M4 replaces the dummies with real bots.
