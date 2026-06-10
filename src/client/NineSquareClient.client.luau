--!strict
-- StarterPlayer.StarterPlayerScripts.NineSquareClient
-- Renders the ball shadow, shrinking descent ring, target-square highlight, and locks an angled court camera.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local Remotes = RS:WaitForChild("NineSquareRemotes")
local BallSync = Remotes:WaitForChild("BallSync")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- Sync the client's idea of origin with the server's by reading the built floor (C floor sits at origin).
local function courtOrigin(): Vector3
	local ns = workspace:FindFirstChild("NineSquare")
	local cFloor = ns and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_C")
	if cFloor then return Vector3.new(cFloor.Position.X, 0, cFloor.Position.Z) end
	return G.origin
end

-- Telegraph visuals (created once)
local shadow = Instance.new("Part")
shadow.Anchored = true; shadow.CanCollide = false; shadow.Size = Vector3.new(G.ballRadius*3, 0.1, G.ballRadius*3)
shadow.Shape = Enum.PartType.Cylinder; shadow.Color = Color3.new(0,0,0); shadow.Transparency = 0.4
shadow.Orientation = Vector3.new(0,0,90); shadow.Parent = workspace
local ringGui = Instance.new("BillboardGui")
ringGui.Size = UDim2.fromScale(6,6); ringGui.AlwaysOnTop = false; ringGui.Parent = shadow
local ring = Instance.new("ImageLabel")
ring.BackgroundTransparency = 1; ring.Size = UDim2.fromScale(1,1)
ring.Image = "rbxassetid://5028857084"; ring.ImageColor3 = Color3.fromRGB(255,80,80); ring.Parent = ringGui
local highlight = Instance.new("SelectionBox")
highlight.LineThickness = 0.08; highlight.Color3 = Color3.fromRGB(255,210,80); highlight.Parent = workspace
local function setHidden(h: boolean)
	shadow.Transparency = h and 1 or 0.4; ring.ImageTransparency = h and 1 or 0
end
setHidden(true)

local state: any = nil
BallSync.OnClientEvent:Connect(function(data) state = data; if data.kind=="idle" then setHidden(true) end end)

-- Lock an angled camera south of and above the court, looking north and up at the grid.
local function updateCamera()
	local o = courtOrigin()
	local depth = 3 * G.squareSize
	local eye = o + Vector3.new(0, G.frameHeight + 20, depth * 0.9)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eye, o + Vector3.new(0, G.frameHeight * 0.6, 0))
end

RunService.RenderStepped:Connect(function()
	updateCamera()
	local ns = workspace:FindFirstChild("NineSquare")
	local ball = ns and ns:FindFirstChild("Ball")
	if not state or not ball or state.kind == "idle" then setHidden(true); highlight.Adornee = nil; return end
	setHidden(false)
	-- shadow tracks ball XZ on the floor
	local o = courtOrigin()
	shadow.Position = Vector3.new(ball.Position.X, o.Y + 0.06, ball.Position.Z)
	-- ring shrinks from 1.0 -> min over the descent window, min at arrival
	local now = workspace:GetServerTimeNow()
	local tToArrive = (state.startT + state.travel) - now
	local k = math.clamp(tToArrive / state.descentWindow, 0, 1)  -- 1 far out, 0 at arrival
	local scale = 1.2 + 4.0 * k
	ringGui.Size = UDim2.fromScale(scale, scale)
	ring.ImageColor3 = (k < 0.12) and Color3.fromRGB(120,255,120) or Color3.fromRGB(255,80,80)
	-- highlight the target square floor
	local tcell = state.targetCell
	local tfloor = ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_" .. tostring(tcell))
	highlight.Adornee = tfloor
end)
