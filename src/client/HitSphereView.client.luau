--!strict
-- StarterPlayer.StarterPlayerScripts.HitSphereView
-- Debug visual: renders the LOCAL player's contact sphere -- the hit-zone HitResolver tests the ball
-- against (centre = HumanoidRootPart + hitZoneYOffset, radius = hitZoneRadius). Purely cosmetic and
-- client-side; toggle with GridConfig.showHitSphere. The ball makes contact when its surface touches
-- this sphere.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS:WaitForChild("GridConfig"))

if not G.showHitSphere then return end

local plr = Players.LocalPlayer

local orb = Instance.new("Part")
orb.Name = "HitSphereView"
orb.Shape = Enum.PartType.Ball
orb.Anchored = true; orb.CanCollide = false; orb.CanQuery = false; orb.CanTouch = false; orb.CastShadow = false
orb.Material = Enum.Material.ForceField
orb.Color = Color3.fromRGB(80, 200, 255)
orb.Transparency = 0.5
orb.Size = Vector3.new(G.hitZoneRadius * 2, G.hitZoneRadius * 2, G.hitZoneRadius * 2)
orb.Parent = workspace

RunService.RenderStepped:Connect(function()
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		orb.Size = Vector3.new(G.hitZoneRadius * 2, G.hitZoneRadius * 2, G.hitZoneRadius * 2)  -- live-tunable
		orb.Position = hrp.Position + Vector3.new(0, G.hitZoneYOffset, 0)
		orb.Transparency = 0.5
	else
		orb.Transparency = 1
	end
end)
