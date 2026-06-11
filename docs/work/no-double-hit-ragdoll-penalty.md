# No double-hit: same player can't hit the ball twice in a row → fault + ragdoll out

## Rule (from Scott)
A player cannot hit the ball **twice in a row**. If the same player contacts the ball on two CONSECUTIVE
player touches (a double-touch / carry), it's a fault: they **go into rag-doll mode and are OUT until the
point resets**.

## Detection — "twice in a row"
- Track the **last player/occupant that hit the ball** (the ball already tracks `struckCell` — the cell the
  ball was last struck from). A double-hit = the SAME occupant strikes the ball again with **no other
  occupant hitting it in between**.
- Surface bounces (floor / wall / pipe) between the two hits do NOT reset it — only another PLAYER/bot
  touching the ball resets the "last hitter". (Hit X → ball bounces off a wall → comes back → X hits again =
  double-hit.)
- The SERVE is the first hit of the rally (not a double). A return by a DIFFERENT occupant resets the
  tracker. The contact model already collapses one approach to one hit (it repositions the ball out of the
  hit-sphere), so a double-hit is a genuine second contact (ball left the sphere + re-entered).

## Penalty
- **Fault the double-hitter** — it ends the rally exactly like the other faults (it flows into the existing
  deferred rotation at rest → re-serve), and the double-hitter rotates out to the back. Reuse the existing
  fault/rotation/serve path (treat the double-hitter's cell as the OUT cell).
- **Rag-doll the (human) double-hitter** and keep them OUT until the point resets: on the double-hit, put the
  human character into a limp/ragdoll state (e.g. `Humanoid.PlatformStand = true`, optionally re-enable the
  Ragdoll/FallingDown states that the no-trip change disabled, + a small flop impulse) so they visibly drop.
  They stay ragdolled through the dead-ball; on the next serve / when they're re-placed at their seat, they
  **recover** (PlatformStand=false, states restored, stood back up at their cell).
- **Scope:** the FAULT applies to whoever double-hit (human or bot). The RAGDOLL applies to HUMAN players
  only (bots are server-driven anchored rigs — they can't meaningfully ragdoll; just fault them). Bots
  rarely double-hit (they swing once per descent toward their square), so this is mostly a human rule.

## Edge cases / safety
- Reset the "last hitter" on every serve / rally reset (so the new rally's first hit is never a double).
- Don't double-resolve: a double-hit is ONE fault (guard with the existing rally-armed/resolving flags).
- Server-authoritative + deterministic — detection + the fault + the ragdoll are decided server-side.

## Acceptance criteria
- A player who strikes the ball twice in a row (same player, consecutive player touches, regardless of
  surface bounces between) → **faults**, the rally ends → deferred rotation → re-serve, and (if human) they
  **ragdoll and are out until the re-serve**, then recover + rotate to the back.
- A normal rally (alternating hitters) is UNAFFECTED — no false double-hit faults; a different player hitting
  in between always resets the tracker.
- Deterministic + server-authoritative; no double-fault; the loop never wedges (re-serve recovers).
  Verified in Play via the MCP. Studio left in Edit.

## Relevant files
- `src/server/BallController.luau` — expose the last/previous hitter (it tracks `struckCell`); fire enough
  info on `onPlayerHit` to compare consecutive hitters; reset on launch/serve.
- `src/server/NineSquareServer.server.luau` — detect the double-hit in the `onPlayerHit` path (compare to the
  previous hitter), trigger the double-hit fault (reuse `attributeFault`/deferred rotation/re-serve) + the
  ragdoll of the human double-hitter; recover them on re-serve / re-place.
- `src/client/Movement.client.luau` (or server) — the ragdoll visuals/recovery (PlatformStand + states); the
  no-trip change disabled FallingDown/Ragdoll — re-enable for the deliberate penalty, restore after.
- `src/shared/GridConfig.luau` — any ragdoll tunables (impulse, recover timing).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play, force a same-player double-hit and confirm
  fault + ragdoll + out + recovery on re-serve; confirm a normal alternating rally never false-faults. Leave
  Studio in Edit.)

## Constraints
- Don't change the ball physics/strike feel or the normal fault/rotation mechanics — ADD the double-hit
  detection + ragdoll penalty on top, reusing the fault/rotation/serve path. Server-authoritative +
  deterministic; reset the tracker each serve; one fault per double-hit; ragdoll humans only. Tunables in
  `GridConfig`.
