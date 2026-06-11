# Slow the ball a little (lower gravity) so it's easier to make contact

## Goal
Make the ball a bit slower / floatier — more hang time — so players can get under it and time the hit more
easily. Scott suggested lowering gravity OR adding air friction.

## Approach: lower the ball's effective gravity (PREFERRED — keep it deterministic)
- Add `GridConfig.ballGravityScale` (~**0.8**, "a little") and set the ball's gravity to
  `workspace.Gravity * ballGravityScale` in `BallController.new` (`self.gravity = ...`). Lower g → slower
  vertical motion + more hang time → easier contact. The ball stays a clean analytic projectile.
- **AVOID per-step air drag.** Real velocity-proportional drag would break the CLOSED-FORM trajectory math
  the game depends on — `BallController:step` (analytic `p0 + v0·t − ½g·t²`), the bot's `_forecast` /
  `_descentTimeToHeight`, and the serve solve are all analytic. Drag needs numerical integration and would
  desync the bot/serve predictions. Gravity-scale gives the same "slower/floatier" feel with none of that
  risk.

## CRITICAL — one consistent gravity everywhere (or bots/serve desync)
All trajectory solves must use the SAME scaled gravity:
- `BallController:step`, `_descentTimeToHeight`, and `BotController._forecast` already read `bc.gravity` /
  `self._bc.gravity` — so they adapt automatically once `self.gravity` is scaled. 
- **`serveToTarget` in `NineSquareServer` currently uses `workspace.Gravity` directly** — change it to use
  `bc.gravity` (the scaled value) so the serve arc matches the ball's real gravity. (Audit for any other
  `workspace.Gravity` use in trajectory math and switch it to `bc.gravity`.)

## Side effects to manage
- Lower g = HIGHER + LONGER arcs (more hang time). The arc peak was tuned to ~stay in the camera view
  (~peak 30) and bots tuned to land in-court. Keep the gravity reduction MODEST ("a little") and VERIFY:
  - the rally arc still stays ~within the default camera view (it shouldn't sail above the top again),
  - bots still land in-court (their in-bounds forecast uses `bc.gravity`, so it re-solves correctly — just
    confirm), and the serve still lands in its target square.
  - If the peak rises too much, nudge `botJumpVelocity` / `humanHitForceMult` down slightly OR use a smaller
    gravity reduction — pick the scale that makes contact easier without breaking the camera framing/OOB.

## Acceptance criteria
- The ball is noticeably slower / floatier (more hang time) — easier to get under + time a hit. Verified in
  Play (a serve/volley visibly hangs longer / falls slower than before).
- Deterministic + server-authoritative preserved; bots still land in-court and the King serve still lands in
  its target square (consistent `bc.gravity` everywhere — no desync); the rally arc stays ~in the camera
  view (no regression to the OOB/ceiling framing). Tunable via `GridConfig.ballGravityScale`.
- Studio left in Edit.

## Relevant files
- `src/shared/GridConfig.luau` — `ballGravityScale` (~0.8; 1.0 = unchanged).
- `src/server/BallController.luau` — `self.gravity = workspace.Gravity * G.ballGravityScale`.
- `src/server/NineSquareServer.server.luau` — `serveToTarget` use `bc.gravity` instead of `workspace.Gravity`.
- `src/server/BotController.luau` — reused (already reads `bc.gravity`; verify, no change expected).
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; standalone `require`
  STALE — verify via `script_read`/`get_console_output`; in Play, confirm the ball hangs longer / falls
  slower, rallies sustain, bots land in-court, serve lands in target, arc peak still ~in view via
  ball.Position.Y. Leave Studio in Edit.)

## Constraints
- Don't add per-step air drag (keep the analytic projectile). Keep ONE gravity (`bc.gravity`) across step +
  bot forecast + descent solves + serve. Don't break the camera-view arc framing or bot in-bounds accuracy
  (keep the reduction modest + re-verify). Deterministic + server-authoritative. Tunable in `GridConfig`.
