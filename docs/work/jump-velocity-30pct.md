# Increase jump velocity 30% (more force transferred to the ball)

## Problem
More initial force should transfer to the ball on a hit. Since the strike is velocity-proportional (the
ball gets the player's velocity into it along the contact normal), **increase the jump velocity by 30%**
so a jump-strike carries more power — for the human AND the bots.

## Change
- **Human:** increase the character's **jump velocity by 30%**. In Roblox that's the Humanoid jump: set
  `Humanoid.UseJumpPower = true` and `JumpPower = default * 1.3` (or `JumpHeight = default * 1.3` if using
  JumpHeight). Apply it where the local character is set up (the same spot the no-trip fix disables
  `FallingDown`/`Ragdoll` — `src/client/Movement.client.luau`, on `CharacterAdded` + current character).
  Put the multiplier / target value in `GridConfig` (e.g. `jumpVelocityMult = 1.3` or a `jumpPower` value).
- **Bot:** increase the **bot jump velocity by 30%** — bump the `botJumpVelocity` tunable (from the
  physical-bots task) by 30% so bots transfer the same extra force.

## Acceptance criteria
- The human's jump is ~30% faster (more upward velocity → a jump-strike sends the ball harder/higher);
  the bot jump velocity is likewise +30%.
- Hits feel more powerful; verified in Play (a clean jump-strike sends the ball with noticeably more force
  than before). Tunable in `GridConfig`.

## Relevant files
- `src/client/Movement.client.luau` — set the human Humanoid jump +30% on character setup.
- `src/shared/GridConfig.luau` — the jump multiplier / `jumpPower`, and `botJumpVelocity` +30%.
- (bot side comes from the physical-bots task's `botJumpVelocity`.)
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in **Edit**).

## Constraints
- Just the jump velocity (+30%) — don't change the contact/strike formula or the collision. Keep tunables
  in `GridConfig`. Don't break the no-trip fix or the dash/flip.
- Note: a higher jump may make hits stronger / fly further (possibly more OOB) — that's the intent (more
  force); leave further balancing to play-tuning.
