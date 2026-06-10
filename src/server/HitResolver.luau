--!strict
-- ServerScriptService.NineSquare.HitResolver
-- Detects a physical contact (a player's jumping hit-zone overlaps the ball) and returns the
-- CONTACT NORMAL = unit(ballCenter - hitZoneCenter). The server turns that into a radial-impulse
-- launch velocity, so where the player strikes the ball precisely determines its direction.
-- A small lift floor (minLift) guarantees every clean hit arcs up and over toward another square.
-- Reads replicated character state (M1 simplification; intent validation + anti-cheat are M5).
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

export type Result = { contact: boolean, point: Vector3, normal: Vector3, player: Player? }

-- Does any player's hit-zone currently overlap the ball? First overlap wins.
function HitResolver.checkContact(ballPos: Vector3): Result
	for _, plr in ipairs(Players:GetPlayers()) do
		local hz = hitZoneCenter(plr)
		if hz and (ballPos - hz).Magnitude <= (G.hitZoneRadius + G.ballRadius) then
			local d = ballPos - hz
			local n = (d.Magnitude > 1e-3) and d.Unit or Vector3.new(0, 1, 0)
			-- guarantee an upward component so the ball always arcs over, keeping horizontal aim
			if n.Y < G.minLift then
				local h = Vector3.new(n.X, 0, n.Z)
				h = (h.Magnitude > 1e-3) and h.Unit or Vector3.zero
				n = (h * math.sqrt(1 - G.minLift * G.minLift) + Vector3.new(0, G.minLift, 0)).Unit
			end
			return { contact = true, point = ballPos, normal = n, player = plr }
		end
	end
	return { contact = false, point = ballPos, normal = Vector3.new(0, 1, 0), player = nil }
end

return HitResolver
