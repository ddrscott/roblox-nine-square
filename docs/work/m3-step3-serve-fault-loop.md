# M3 step 3: King serve + fault→rotation wiring (the live loop)

See the M3 design spec `docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md` (§5, §6, §9
step 3). Steps 1–2 give occupancy + `rotateOnFault`. **This step makes the king-of-the-hill loop run**:
the King serves, the ball lands, the right occupant is faulted, everyone rotates, the new King serves —
so a solo human climbs the ranks toward the centre.

## Build
### A. Cell ↔ rank lookup
- `rankOfCell(cell) -> rank` (inverse of `rankCells`) in `GridConfig` or `RotationService`; and
  `RotationService.occupantAtCell(cell)`. Needed for fault attribution.

### B. King serve (PRD §3.2, §5.5)
A rally is always served by the King (rank 1 = C):
- **Human King** (the human occupies rank 1): the ball hovers at C (phase Live) and the human jump-strikes
  it (existing M1 physical serve / contact-aim). The struck direction decides which square it goes to.
- **Dummy King** (a dummy occupies rank 1): after a short delay (`GridConfig.serveDelay`), the server
  **auto-serves** — launch the ball from `cellFramePoint("C")` toward a **random outer square's**
  frame point with a deterministic velocity (reuse the same ballistic launch the contact uses, or compute
  a velocity that arcs to that square). No hover.
- Add a `serveNextRally()` in `NineSquareServer` that checks who is King and does the right thing.

### C. Fault attribution + rotation (PRD §6) — wire `BallController.onLand`
Replace the current `onLand` (which just prints) with attribution → rotation:
- `landed ~= nil and landed ~= struck` → **floor fault**: the occupant of `landed` failed to return it →
  `rotateOnFault(rankOfCell(landed))`.
- `landed == struck` → **self-square fault**: the hitter (occupant of `struck`) →
  `rotateOnFault(rankOfCell(struck))`.
- `landed == nil` (out of bounds) → **OOB fault**: the hitter (occupant of `struck`) →
  `rotateOnFault(rankOfCell(struck))`.
Keep the existing flash + oof-sound feedback on a fault. After attributing + rotating, the new King
serves the next rally.

### D. Re-serve flow
- The rally ends at the landing (`onLand`): attribute the fault and `rotateOnFault` there.
- When the ball comes to rest (`onRest`) — or after a short beat — call `serveNextRally()` for the (new)
  King. Replace the old "re-serve at centre + place all players at centre" behaviour (the M1
  reset-players task): rotation already re-placed everyone via `placeAll`, so just serve.
- A dummy square can't volley, so any ball into a dummy square lands on its floor → that dummy faults →
  rotation. The human survives by volleying balls served to their square (M1 contact) and climbs as
  dummies fault.

## Acceptance criteria
- The loop runs solo (human + 8 dummies): the King serves into a square; a ball to the **human's** square
  can be volleyed onward (M1 contact); a ball to a **dummy's** square (or a human fault) attributes the
  fault to the correct occupant and **rotates** everyone one step toward the King; the new King serves.
- A human at an outer rank **climbs toward the centre** as the dummies ahead of them fault, and can reach
  **King (C)**; when the human is King, they serve physically.
- Fault attribution matches PRD §6 (floor/self-square/OOB). Server-authoritative; deterministic.
- Verified in a Play test: watch several rallies — confirm rotations occur on each fault, the human's
  rank advances, and serving alternates between dummy-King (auto) and human-King (physical) correctly.

## Relevant files
- `src/server/NineSquareServer.server.luau` — `serveNextRally`, the King-type branch, `onLand` wiring,
  `onRest`→serve. (Replace the M1 reset-to-centre/`placeAllAtCourt` re-serve.)
- `src/server/RotationService.luau` — `occupantAtCell`/`rankOfCell`, expose King query (`isHumanKing()` /
  `kingOccupant()`).
- `src/server/BallController.luau` — likely reused as-is; if the dummy-King auto-serve needs a launch
  from C to a target square, use `bc:launch(point, v0)` with a computed v0 (don't change the contact/
  collision physics).
- `src/shared/GridConfig.luau` — `rankOfCell` (if placed here), `serveDelay`, any serve velocity tunable.
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops; leave Studio in Edit). Use
  `script_read`/console for verification (standalone `require` reads a stale module copy).

## Constraints
- Reuse the M1 contact volley + `BallController` physics unchanged (don't touch the swept player
  collision, surfaces, floor). Single-touch: the existing collision already gives one hit per approach.
- Server-authoritative; clients send no fault/rotation decisions. Tunables in `GridConfig`. Don't break
  the no-trip fix, camera, dummies, or step-1/2 work.
