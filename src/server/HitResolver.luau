--!strict
-- ServerScriptService.NineSquare.HitResolver
-- Detects a physical volley contact (a player's jumping hit-zone overlaps the ball) and computes
-- the outgoing direction from the contact geometry (reflection/bump) + a small steer from the
-- player's held move input. Reads replicated character state (M1 simplification; intent validation
-- and anti-cheat are M5).
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)

local HitResolver = {}

local function hitZoneCenter(plr: Player): Vector3?
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position + Vector3.new(0, G.hitZoneYOffset, 0)
end

local function steerOf(plr: Player): Vector3
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum.MoveDirection or Vector3.zero
end

export type Result = { contact: boolean, point: Vector3, dir: Vector3, player: Player? }

-- Does any player's hit-zone currently overlap the ball? First overlap wins.
function HitResolver.checkContact(ballPos: Vector3): Result
	for _, plr in ipairs(Players:GetPlayers()) do
		local hz = hitZoneCenter(plr)
		if hz and (ballPos - hz).Magnitude <= (G.hitZoneRadius + G.ballRadius) then
			local base = G.reflectDir(ballPos, hz)
			local dir = G.applySteer(base, steerOf(plr))
			return { contact = true, point = ballPos, dir = dir, player = plr }
		end
	end
	return { contact = false, point = ballPos, dir = Vector3.zero, player = nil }
end

return HitResolver
