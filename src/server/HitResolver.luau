--!strict
-- ServerScriptService.NineSquare.HitResolver
-- Geometry/state provider for the players' hit-spheres. Each character carries a body-sized contact
-- sphere (centre = HumanoidRootPart + hitZoneYOffset, radius = hitZoneRadius) that moves with the
-- player's current velocity. BallController folds these in as MOVING-sphere colliders during its
-- collision step (alongside the pipes/walls/floor) so a contact is a real penetration+rebound, not a
-- one-shot proximity trigger. This module owns no ball logic; it just reports where the spheres are.
-- Reads replicated character state (M1 simplification; intent validation + anti-cheat are M5).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local HitResolver = {}

export type PlayerCollider = { center: Vector3, radius: number, vel: Vector3, player: Player }

-- One moving-sphere collider per player that has a character with a HumanoidRootPart. Centre is the
-- hit-zone (HRP raised by hitZoneYOffset); velocity is the HRP's assembly velocity so a faster drive
-- into the ball hits harder. BallController decides penetration/approach + the rebound.
function HitResolver.playerColliders(): { PlayerCollider }
	local list: { PlayerCollider } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			table.insert(list, {
				center = hrp.Position + Vector3.new(0, G.hitZoneYOffset, 0),
				radius = G.hitZoneRadius,
				vel = hrp.AssemblyLinearVelocity,
				player = plr,
			})
		end
	end
	return list
end

return HitResolver
