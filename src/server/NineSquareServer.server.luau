--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, serve handling, the Heartbeat loop, and spawns players at the court.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local ns = game.ServerScriptService:WaitForChild("NineSquare")
local BallController = require(ns.BallController)
local MatchService = require(ns.MatchService)
local Serve = RS.NineSquareRemotes.Serve

print("[NineSquare] server starting")
MatchService.buildArena(Vector3.new(0, 0, 200))
local bc = BallController.new()
print("[NineSquare] arena + ball ready")

bc.onArrive = function(arc)
	-- Task 6 replaces this with HitResolver. For now: whiff -> reset after a beat.
	task.delay(0.4, function() bc:reset() end)
end

Serve.OnServerEvent:Connect(function(plr)
	if bc.phase ~= "Idle" then return end
	local cell = MatchService.playerCell(plr)
	if cell then bc:serve(cell) end
end)

RunService.Heartbeat:Connect(function() bc:step() end)

-- M1 deviation from plan: the default SpawnLocation is by the old Obby (z~0), but the court is at
-- z=200. Place each spawning character under square N so they start in play position.
local function placeAtCourt(char: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(G.cellCenter("N") + Vector3.new(0, 5, 0))
		print(("[NineSquare] placed %s at %s"):format(char.Name, tostring(hrp.Position)))
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
