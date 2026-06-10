# Stop the player tripping on dash / flip

## Problem
The avatar frequently trips/tips over. Cause: the movement moves apply sudden velocity to the R15
character — the dash overwrites `AssemblyLinearVelocity` for `dashDuration`, and the double-jump flip
applies an upward velocity + a cosmetic spin. Roblox Humanoids stumble into the `FallingDown` (trip)
state on sharp velocity changes or when left mid-spin on landing. Doubling the dash speed (20→40) made
it worse.

## The fix
1. **Disable the trip states on the LOCAL character.** When the character spawns (and for the current
   one), get its `Humanoid` and call:
   `humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)` and the same for
   `Enum.HumanoidStateType.Ragdoll`. This keeps the avatar upright through dash bursts and landings.
2. **Land the flip upright.** The cosmetic forward-flip spin rotates the character; make sure it resets
   the character to an upright orientation when the spin ends (keep position + facing yaw, zero out
   pitch/roll) so it doesn't finish tilted and stumble. (If the spin is purely visual on a weld/Motor,
   ensure it returns to identity; if it tilts the root, restore the root's upright CFrame at the end.)

## Acceptance criteria
- Dashing (at the current `dashSpeed`) and the double-jump flip no longer trip/tip the avatar — it
  stays upright and keeps control.
- The flip lands upright (not tilted / not stumbling).
- Normal walking + jumping are unaffected.
- Verified in a Play test: dash repeatedly and flip several times — no tripping / ragdoll / face-plant.

## Relevant files
- `src/client/Movement.client.luau` — owns the dash + double-jump flip (and the character reference);
  natural home for the `SetStateEnabled` calls (on `CharacterAdded` + current character) and the
  flip-spin orientation cleanup.
- (If a dedicated character-setup spot fits better, that's fine — keep it client-side and local-player.)
- Deploy via the `robloxstudio` MCP; verify in Play (mode flip-flops — `get_studio_state` first; leave
  Studio in Edit when done). The Movement client is `StarterPlayer.StarterPlayerScripts.Movement`.

## Constraints
- Client-side, local player only. Don't break walking/jumping or the dash/flip behaviour itself.
- Scope the disabled states to the trip states (`FallingDown`, `Ragdoll`); don't broadly disable other
  Humanoid states. Re-apply on each `CharacterAdded` (states reset per character).
