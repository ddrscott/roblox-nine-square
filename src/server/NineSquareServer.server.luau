--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, physical contact detection, the Heartbeat loop, and court spawn.
-- Serving is physical: the ball hovers at center; a player gets under it and jumps to strike it.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
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

-- The ball reports physics events; the game owns the rules, feedback, and re-serve timing.
local function playOof()
	local s = Instance.new("Sound"); s.SoundId = "rbxasset://sounds/uuhhh.mp3"; s.Volume = 1
	s.Parent = bc.ball; s:Play(); Debris:AddItem(s, 3)
end

-- First floor contact of a rally: legal land elsewhere, self-square fault, or out-of-bounds.
bc.onLand = function(landed, struck)
	if landed == nil then
		print("[NineSquare] FAULT (out-of-bounds) struck=" .. tostring(struck))
		MatchService.flashCell(struck); playOof()
	elseif landed == struck then
		print("[NineSquare] FAULT (self-square) cell=" .. landed)
		MatchService.flashCell(landed); playOof()
	else
		print("[NineSquare] ball landed in " .. landed .. " (unreturned)")
	end
end

-- The default SpawnLocation is by the old Obby (z~0), but the court is at z=200.
-- Place a character at the center square (C) so they start/serve under the hovering ball.
local function placeAtCourt(char: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(G.cellCenter("C") + Vector3.new(0, 5, 0))
		print(("[NineSquare] placed %s at %s"):format(char.Name, tostring(hrp.Position)))
	else
		warn("[NineSquare] no HumanoidRootPart to place: " .. char.Name)
	end
end

-- Snap every present player back to the serve square. M1 is single-square; later rotation
-- milestones (M3) can extend this to place players at their assigned square.
local function placeAllAtCourt()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then placeAtCourt(plr.Character) end
	end
end

-- Ball has bounced out its energy and stopped: re-serve after a beat (unless it's batted back into play).
-- On re-serve, snap players back to the centre so they don't have to walk back to serve.
bc.onRest = function()
	task.delay(0.6, function()
		if bc.phase == "Rest" then
			bc:resetToServe()
			placeAllAtCourt()
		end
	end)
end

-- Physical contact is now a real collision inside the ball's step: each Heartbeat we gather the
-- players' moving hit-spheres and hand them to bc:step, which resolves a hit only on penetration +
-- approach (so a descending player can't pull a rising ball down) and bounces the ball off the sphere
-- exactly like it bounces off the pipes/walls/floor. No more proximity trigger or time cooldown.
RunService.Heartbeat:Connect(function(dt)
	bc:step(dt, HitResolver.playerColliders())
end)

-- Spawn placement: same court placement plus a resync so the late-loading client gets ball state.
local function placeAtCourtAndSync(char: Model)
	placeAtCourt(char)
	task.delay(1, function() bc:resync() end)
end
local function hook(plr: Player)
	if plr.Character then placeAtCourtAndSync(plr.Character) end
	plr.CharacterAdded:Connect(placeAtCourtAndSync)
end
Players.PlayerAdded:Connect(hook)
for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
