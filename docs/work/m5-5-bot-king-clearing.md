# M5.5 — Bot-King outward-clearing fix (stop the center self-rally)

Spec: `docs/superpowers/specs/2026-06-10-nine-square-m5-multiplayer-design.md`. The tracked bot bug from
the aim-variety work.

## Problem
A BOT holding the center seat (C / King) often can't drive the ball OUTWARD over a pipe into an outer
cell — it over-verticalises the hit, the ball pops up and falls back into C, and the bot **self-rallies in
its own square** (long `dummy1 SWING defending C -> aim X` runs with no SAVEs / no outer swings). Observed
at both botJumpVelocity 9 and 12, so it's NOT an energy problem — peak ~30 is plenty to clear the pipe
(13). The issue is the center hit's DIRECTION: too little horizontal velocity toward the aimed outer, so
the ball lands back in C.

## Diagnosis to confirm + fix
- The outgoing strike leaves along the line-of-centres `n = unit(ball - colliderCenter)` (≈ `unit(colVel)`
  via `liftNormal`). For the King at C hitting a descending-near-vertical ball, `n` ends up near-vertical →
  a high pop with little horizontal → back into C.
- The in-bounds/peak forecast loop (`_tryCommit`) can over-FLATTEN-then-steepen and still leave the hit too
  vertical from center. The CENTER seat specifically needs a flatter, more horizontal drive than an outer
  seat (it must reach ~14 studs out + clear a pipe at 7 studs), whereas outer seats hit DOWNHILL into C and
  clear easily.
- **Fix:** give the center/King hit enough HORIZONTAL drive to actually carry to the aimed outer cell —
  e.g. a larger effective `standoff` / off-center offset for the C seat (a King-specific multiplier), or
  ensure the forecast loop targets the aimed cell's landing from center without collapsing to vertical. The
  ball must clear `pipeClearHeight` at the pipe AND land in the aimed outer cell (not back in C). Keep the
  camera-height behaviour for OUTER hits unchanged.

## Acceptance criteria
- A bot King at C reliably sends the ball OUT to its (varied, non-ping-pong) aimed outer cells — measured:
  over a window of bot-King swings, the ball clears C (SAVE -> C logged) and an OUTER bot receives it, with
  NO long self-rally runs (no >~3 consecutive `defending C` swings without a clear).
- Outer-bot hits, the in-bounds accuracy, the camera-height arc, save/fault, and rotation are unchanged.
- Verified via the MCP (console: confirm C clears to varied outers + outer swings interleave; ball peak
  still ~in the camera view). Studio left in Edit.

## Relevant files
- `src/server/BotController.luau` — `_tryCommit` aim/forecast/off-center+standoff for the C seat (add the
  King-specific outward drive); keep outer-seat behaviour as-is.
- `src/shared/GridConfig.luau` — a King/center outward-drive tunable (e.g. `botKingStandoffMult` or
  `botCenterOffCenterFrac`).
- Build/verify via the robloxstudio MCP (mode flip-flops; verify via `get_console_output` over several
  bot-King rallies + a ball-peak probe using ball.Position.Y; leave Studio in Edit).

## Constraints
- Don't change the shared strike formula / swept collision / save-fault / rotation. Don't regress the
  camera-height arc for OUTER hits or the in-bounds accuracy. Tunables in `GridConfig`. Deterministic-ish
  is fine (the aim already uses math.random for variety + jitter).
