# Remove the artificial ball + player shadows (real sun shadows now show position)

## Problem
The fake position shadows were added back when dynamic shadows didn't reliably render. Now the sun is
overhead (zenith) casting correct straight-down shadows, so the artificial shadows under the ball and player
are redundant — positions read fine from the real shadows. Remove the fakes.

## What to remove (client visuals, `NineSquareClient.client.luau`)
- The **artificial BALL ground-shadow** — the stacked translucent shadow discs (`BallShadow` folder /
  `discs` / `ShadowDisc*`) and their per-frame grow/fade.
- The **artificial PLAYER ground-shadow** — the `PlayerShadow` disc and its per-frame update.

## KEEP (these are gameplay cues, NOT position shadows)
- The **strike-height RING** (the green/red ring that grows/shrinks with the ball's height and turns green at
  strike height — a hit-timing cue). It's currently a `BillboardGui` parented to the core shadow disc — when
  the discs are removed, **re-home it** onto a minimal anchor (a single tiny invisible non-colliding part
  tracking the ball's floor XZ, or attach to the ball) so the ring still renders + updates as before.
- The **predicted-landing highlight** (the SelectionBox on the target cell) — unchanged.

## Make the real shadow actually show
- Ensure the **ball casts a real shadow**: set the ball part `CastShadow = true` (it may have been false to
  avoid clashing with the fake). Players/bots cast shadows by default — verify their rigs do (no
  `CastShadow=false` on the visible body parts).
- Real shadows need `Lighting.GlobalShadows = true` (already set in setupLighting) and
  `Lighting.Technology = ShadowMap`/`Future` (can't be set by script — Scott set it in Studio). Verify a real
  straight-down shadow appears under the ball + players in Play. (If a worker's Studio quality level doesn't
  render dynamic shadows, still remove the fakes per Scott's call — and note it.)

## Acceptance criteria
- The fake ball shadow discs + the player shadow disc are GONE (no `ShadowDisc*` / `PlayerShadow` updating).
- A real, straight-down sun shadow shows under the ball and players (positions still easy to read). Verified
  via `screen_capture`.
- The strike-height ring still works (grows/shrinks + greens at strike height) and the predicted-landing
  highlight still shows — both re-homed/intact.
- No gameplay change; no errors from the removed per-frame shadow code (clean up its RenderStepped usage).
  Studio left in Edit.

## Relevant files
- `src/client/NineSquareClient.client.luau` — remove the BallShadow discs + PlayerShadow + their per-frame
  updates; re-home the strike ring; keep the landing highlight.
- `src/server/BallController.luau` (or wherever the ball part is built) — set the ball `CastShadow = true`.
- `src/shared/GridConfig.luau` — drop now-dead shadow-disc tunables if any.
- Build/verify via the robloxstudio MCP (mode flip-flops — `get_studio_state` first; client visuals on the
  Client datamodel in Play; standalone `require` STALE — verify via `script_read`/`get_console_output` +
  `screen_capture`: fakes gone, real shadow under the ball/players, ring + highlight still working. Leave
  Studio in Edit.)

## Constraints
- Visual cleanup only — don't change gameplay, the ball physics, or the strike-ring / landing-highlight
  BEHAVIOUR (just keep them working without the shadow discs). Ensure the ball casts a real shadow. Tunables
  in `GridConfig`.
