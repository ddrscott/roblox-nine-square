# M3 step 2: rotation-on-fault (the rotation mechanism)

See the M3 design spec `docs/superpowers/specs/2026-06-10-nine-square-m3-rotation-design.md` (§4, §9
step 2). Step 1 (rank map + occupant model + dummies + `placeAll`) is DONE in `RotationService`. This
step adds the rotation algorithm + a dethrone hook + a way to verify it. Do NOT wire faults or serves
yet (that is step 3).

## Build
- **`RotationService.rotateOnFault(faultRank: number)`** — PRD §4.3. With the fixed 9 occupants this is a
  cyclic shift of ranks `faultRank..9`: the faulting occupant is pushed to **rank 9**, and every
  occupant at `faultRank+1 .. 9` **advances one rank toward the King** (rank K takes rank K-1's cell).
  Concretely: `local faulter = byRank[faultRank]; for r = faultRank, 8 do byRank[r] = byRank[r+1];
  byRank[r].rank = r end; byRank[9] = faulter; faulter.rank = 9`, then `placeAll()` (so everyone —
  including the human, via the injected human-teleport — moves to their new cell).
- **Dethrone hook** — when `faultRank == 1` (the King faulted), this is the dethrone: the occupant now at
  rank 1 is the new King. Expose an optional `RotationService.onDethrone(newKingOccupant)` callback
  (fire it from `rotateOnFault`); for this step a print is fine, emphasis/VFX is step 4.
- **Verification path** — add a TEMPORARY way to trigger rotations so it can be eyeballed (e.g. a small
  debug function callable from the server, or trigger a couple of `rotateOnFault` calls on start with
  waits, then leave the ranks settled). Confirm placement shifts correctly, then make sure no debug
  auto-loop is left running in the committed code (a callable debug helper is fine; an infinite rotate
  loop is not).

## Acceptance criteria
- `rotateOnFault(R)` for an outer rank R moves the rank-R occupant to NW (rank 9) and advances ranks
  R+1..9 one step toward the King; everyone (incl. the human) is re-placed at their new cell.
- `rotateOnFault(1)` is a **dethrone**: the old King → rank 9, the rank-2 occupant becomes King at C, and
  the `onDethrone` hook fires with the new King.
- The human's rank updates and the human is teleported to their new square when they move.
- Verified in Play (console shows the rank shifts; placement screenshot after a rotation shows occupants
  in their new cells). No leftover auto-rotation loop.

## Relevant files
- `src/server/RotationService.luau` — add `rotateOnFault`, `onDethrone`. (Reuse the existing `byRank`,
  `placeAll`, and the injected human-teleport from step 1.)
- `src/server/NineSquareServer.server.luau` — only if you need a debug trigger; do NOT wire real faults
  here yet (step 3).
- `src/shared/GridConfig.luau` — `rankCells`/`cellForRank` already exist; add a cell→rank reverse helper
  if handy (step 3 needs it).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit). For a live read of GridConfig, use `script_read`/`script_grep` (a standalone
  `execute_luau` `require` reads a stale cached module copy in this place).

## Constraints
- Rotation MECHANISM only — no fault attribution, no serve changes, no `onLand` wiring (that's step 3).
- Server-authoritative; keep `RotationService` decoupled (human teleport stays injected). Don't break
  the existing ball/contact loop or step-1 placement.
