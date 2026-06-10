--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, serve handling, contact detection, the Heartbeat loop, and court spawn.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local ns = game.ServerScriptService:WaitForChild("NineSquare")
local BallController = require(ns.BallController)
local MatchService = require(ns.MatchService)
local HitResolver = require(ns.HitResolver)
local Serve = RS.NineSquareRemotes.Serve

print("[NineSquare] server starting")
MatchService.buildArena(Vector3.new(0, 0, 200))
local bc = BallController.new()
print("[NineSquare] arena + ball ready")

-- Whiff or volley-landing: reset the ball shortly after the arc resolves.
bc.onArrive = function(_arc)
	task.delay(0.4, function() if bc.phase == "Resolved" then bc:reset() end end)
end

Serve.OnServerEvent:Connect(function(plr)
	if bc.phase ~= "Idle" then return end
	local cell = MatchService.playerCell(plr)
	if cell then bc:serve(cell) end
end)

RunService.Heartbeat:Connect(function()
	bc:step()
	-- Physical contact: while a served ball descends/hovers over a square, a player who jumps
	-- into it volleys it back up. Direction comes from where they strike it (reflection) + steer.
	if bc.arc and bc.arc.kind == "serve" and (bc.phase == "Descending" or bc.phase == "Hover") then
		local res = HitResolver.checkContact(bc.ball.Position)
		if res.contact then
			print(("[NineSquare] contact by %s dir=%s"):format(res.player and res.player.Name or "?", tostring(res.dir)))
			bc:volley(res.point, res.dir)
		end
	end
end)

-- The default SpawnLocation is by the old Obby (z~0), but the court is at z=200.
-- Place each spawning character under square N so they start in play position.
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
