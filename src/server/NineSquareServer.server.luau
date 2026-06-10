--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, physical contact detection, the Heartbeat loop, and court spawn.
-- Serving is physical: the ball hovers at center; a player gets under it and jumps to strike it.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local ns = game.ServerScriptService:WaitForChild("NineSquare")
local BallController = require(ns.BallController)
local MatchService = require(ns.MatchService)
local HitResolver = require(ns.HitResolver)

-- Overhead noon sun so the frame casts straight-down grid shadows on the floor.
local function setupLighting()
	local L = game:GetService("Lighting")
	L.GeographicLatitude = 23.5   -- cancels Roblox's ~23.5deg sun tilt: noon sun ends up at the zenith
	L.ClockTime = 12
	L.GlobalShadows = true
	L.Brightness = 3
	L.Ambient = Color3.fromRGB(150, 150, 160)        -- lift interior light (the gym ceiling blocks the sun)
	L.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	-- Raise the Bloom threshold so only true light sources (the Neon ceiling fixtures) bloom.
	-- At the default Threshold = 2 the lit ball exceeded it and rendered as a glowing white halo.
	-- Self-heals on a fresh place: set it if a Bloom child exists.
	local bloom = L:FindFirstChildWhichIsA("BloomEffect")
	if bloom then bloom.Threshold = 3.5 end
	-- NOTE: Lighting.Technology (ShadowMap/Future) cannot be set by scripts; set it once in Studio Properties.
end

print("[NineSquare] server starting")
setupLighting()
MatchService.buildGym(Vector3.new(0, 0, 200))
MatchService.buildArena(Vector3.new(0, 0, 200))
local bc = BallController.new()
print("[NineSquare] arena + ball ready")

RunService.Heartbeat:Connect(function()
	bc:step()
	local now = workspace:GetServerTimeNow()
	if bc:isHittable(now) then
		local res = HitResolver.checkContact(bc.ball.Position)
		if res.contact then
			-- horizontal direction/reach comes from the contact normal; vertical is a fixed pop for hang time
			local n = res.normal
			local v0 = Vector3.new(n.X, 0, n.Z) * G.hitSpeedH + Vector3.new(0, G.hitSpeedV, 0)
			bc:launch(res.point, v0)
			print(("[NineSquare] hit by %s  n=%s  -> %s"):format(
				res.player and res.player.Name or "?", tostring(res.normal), tostring(bc.targetCell)))
		end
	end
end)

-- The default SpawnLocation is by the old Obby (z~0), but the court is at z=200.
-- Place each spawning character at the center square (C) so they start under the served ball.
local function placeAtCourt(char: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(G.cellCenter("C") + Vector3.new(0, 5, 0))
		print(("[NineSquare] placed %s at %s"):format(char.Name, tostring(hrp.Position)))
		task.delay(1, function() bc:resync() end)  -- make sure the late-loading client gets ball state
	else
		warn("[NineSquare] no HumanoidRootPart to place: " .. char.Name)
	end
end
local function hook(plr: Player)
	if plr.Character then placeAtCourt(plr.Character) end
	plr.CharacterAdded:Connect(placeAtCourt)
end
Players.PlayerAdded:Connect(hook)
for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
