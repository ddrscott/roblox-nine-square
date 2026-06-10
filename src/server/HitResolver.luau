--!strict
-- ServerScriptService.NineSquare.HitResolver
-- Detects a physical contact (a player's hit-sphere overlaps the ball) and reports the contact
-- geometry + the player's velocity. The hit-sphere is centred on the avatar and roughly body-sized
-- ("slightly smaller than the player"). The server turns the normal + player velocity into a simple
-- sphere-bounce impulse, so the impact is proportional to how fast the player drives into the ball.
-- Reads replicated character state (M1 simplification; intent validation + anti-cheat are M5).
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)

local HitResolver = {}

export type Result = { contact: boolean, point: Vector3, normal: Vector3, playerVel: Vector3, player: Player? }

-- Does any player's hit-sphere currently overlap the ball? First overlap wins. Returns the contact
-- normal (line of centres, biased upward by minLift) and the player's current velocity.
function HitResolver.checkContact(ballPos: Vector3): Result
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local center = hrp.Position + Vector3.new(0, G.hitZoneYOffset, 0)
			if (ballPos - center).Magnitude <= (G.hitZoneRadius + G.ballRadius) then
				local d = ballPos - center
				local n = (d.Magnitude > 1e-3) and d.Unit or Vector3.new(0, 1, 0)
				-- bias the normal upward so a clean bump tends to arc the ball up and over
				if n.Y < G.minLift then
					local h = Vector3.new(n.X, 0, n.Z)
					h = (h.Magnitude > 1e-3) and h.Unit or Vector3.zero
					n = (h * math.sqrt(1 - G.minLift * G.minLift) + Vector3.new(0, G.minLift, 0)).Unit
				end
				return { contact = true, point = ballPos, normal = n, playerVel = hrp.AssemblyLinearVelocity, player = plr }
			end
		end
	end
	return { contact = false, point = ballPos, normal = Vector3.new(0, 1, 0), playerVel = Vector3.zero, player = nil }
end

return HitResolver
