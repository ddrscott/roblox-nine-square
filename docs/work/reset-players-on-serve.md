# Reset players to the serve spot when the ball re-serves

## Problem
After a rally the ball settles and re-serves at the centre, but players are left wherever they ended
up and have to walk all the way back to the centre to serve again — tedious. When the ball resets,
snap players back to the serve position too.

## Behaviour
- When the ball **re-serves** (the reset after a land/fault settles — i.e. when `bc:resetToServe()`
  runs), teleport every player's character back to the **centre square** (the serve spot, under the
  hovering ball), exactly like the initial spawn placement.
- Only on the re-serve — NOT mid-rally and NOT while a dead ball is still being batted around.

## Implementation
- In `src/server/NineSquareServer.server.luau`: there's already `placeAtCourt(char)` that sets the
  character to `cellCenter("C") + (0,5,0)`. Factor a `placeAllAtCourt()` (loop `Players:GetPlayers()`)
  and call it right after `bc:resetToServe()` in the `bc.onRest` handler (the `task.delay` that
  re-serves once the ball has come to rest). Reuse the existing placement so behaviour matches spawn.
- Server-side (authoritative). Setting `HumanoidRootPart.CFrame` replicates to the client.

## Acceptance criteria
- After the ball lands/faults and re-serves, the player is snapped back to the centre serve square
  (under the hovering ball) with no walk-back required.
- The teleport happens on the re-serve only (not during an active rally / dead-ball batting).
- Verified in a Play test: walk/jump away, let the ball land, and confirm you're returned to centre
  when it re-serves.

## Relevant files
- `src/server/NineSquareServer.server.luau` — `bc.onRest` re-serve path + `placeAtCourt`.
- `src/server/BallController.luau` — `resetToServe`/`onRest` (read-only; the game owns repositioning).
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done).

## Constraints
- M1 is effectively single-player, so "back to centre" is correct for now. Keep it a small helper
  (`placeAllAtCourt`) so later rotation milestones (M3) can place players per their assigned square
  without a rewrite. Don't break the existing spawn placement.
- Server-authoritative; don't move player logic to the client.
