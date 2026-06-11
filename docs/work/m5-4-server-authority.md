# M5.4 — Server-authority hardening / anti-cheat

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`. The "fuller M5" part —
make the server trustworthy enough for a real session with friends.

## Problem
The ball + scoring are already server-authoritative + deterministic, but the PLAYER's contribution is
client-driven and unvalidated: the strike reads the player's replicated HRP velocity, and stamina / dash /
flip are client-gated. A client could spoof velocity (super-hit), warp into the ball, or fake stamina.

## What to build
- **Define + enforce the trust boundary:** the server owns the ball, contact resolution, scoring, seats,
  rotation, serve, and the spectator queue. The client only PROPOSES its character position/velocity.
- **Validate the strike contribution:** when feeding a seated human's collider velocity into `bc:step`,
  **clamp it to a plausible max** derived from the movement tunables (walk + dash burst + jump/flip), and
  reject/clamp **implausible position jumps** (anti-teleport: cap per-frame displacement) so a client can't
  manufacture an oversized hit or warp the collider into the ball.
- **Server-side economy sanity:** stamina / dash / flip costs validated (or at least bounded) server-side
  rather than blindly trusted — a client can't dash/flip with no stamina to cheat the velocity-proportional
  strike.
- **Ignore non-seated input:** spectators (and any player not holding a seat) can NEVER affect the ball —
  their colliders are not fed to `bc:step`.
- **Lifecycle robustness:** disconnects mid-rally / mid-serve / while King must not wedge the game — the
  seat backfills (spectator→bot), the ball re-serves cleanly, no orphaned state. Rate-limit any client→
  server remotes.

## Acceptance criteria
- A client cannot produce a hit harder than the legitimate movement tunables allow (velocity into the
  strike is clamped) and cannot warp the collider into the ball (position delta clamped) — demonstrate the
  clamp triggers on an injected oversized velocity/teleport in a Server-side test, and normal play is
  unaffected.
- Stamina/dash/flip can't be spoofed to cheat the strike (server bounds them).
- Spectators / unseated players never influence the ball.
- Disconnects at any phase (rally, serve, King) recover cleanly — no empty seat, no stuck ball, no error
  spam. Verified via the MCP (Server-side injected-cheat tests + disconnect simulation + console). Studio
  left in Edit.

## Relevant files
- `src/server/NineSquareServer.server.luau` — where seated-human colliders are gathered + fed to `bc:step`
  (add the velocity/position clamps); disconnect/lifecycle handling; remote rate-limits.
- `src/server/BallController.luau` — reused (don't change the physics); the clamp is on the INPUT colliders,
  not the strike formula.
- `src/server/RotationService.luau` — seat lifecycle robustness on disconnect.
- `src/client/Movement.client.luau` — stamina/dash/flip; mirror/authorize the economy server-side (or
  validate the client's claim).
- `src/shared/GridConfig.luau` — clamp tunables (max plausible strike speed, max per-frame displacement).
- Build/verify via the robloxstudio MCP (mode flip-flops; verify via Server-side tests + console; Edit).

## Constraints
- Don't change the deterministic ball physics or the strike formula — validate/clamp the INPUTS. Keep
  legitimate play feeling identical (clamps only bite on cheating). Server-authoritative throughout.
