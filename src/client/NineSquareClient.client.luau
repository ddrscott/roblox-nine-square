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

-- Flat shadow disc (created once). For a Cylinder, local X is the AXIS/length, so the thin
-- dimension goes on X and the circle (diameter) on Y/Z; rotating 90 deg about Z lays it flat.
local shadow = Instance.new("Part")
shadow.Name = "BallShadow"; shadow.Anchored = true; shadow.CanCollide = false; shadow.CastShadow = false
shadow.Shape = Enum.PartType.Cylinder
shadow.Size = Vector3.new(0.2, G.ballRadius * 3, G.ballRadius * 3)
shadow.Orientation = Vector3.new(0, 0, 90)
shadow.Color = Color3.new(0, 0, 0); shadow.Material = Enum.Material.SmoothPlastic; shadow.Transparency = 0.25
shadow.Parent = workspace

-- Camera-facing timing ring, anchored over the shadow.
local ringGui = Instance.new("BillboardGui")
ringGui.Size = UDim2.fromScale(6, 6); ringGui.AlwaysOnTop = false; ringGui.Parent = shadow
local ring = Instance.new("ImageLabel")
ring.BackgroundTransparency = 1; ring.Size = UDim2.fromScale(1, 1); ring.ImageTransparency = 1
ring.Image = "rbxassetid://5028857084"; ring.ImageColor3 = Color3.fromRGB(255, 80, 80); ring.Parent = ringGui

local highlight = Instance.new("SelectionBox")
highlight.LineThickness = 0.08; highlight.Color3 = Color3.fromRGB(255, 210, 80); highlight.Parent = workspace

local state: any = nil
BallSync.OnClientEvent:Connect(function(data) state = data end)

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
	-- Shadow ALWAYS tracks the ball so you can read where you are under it.
	if ball then
		local o = courtOrigin()
		shadow.Position = Vector3.new(ball.Position.X, o.Y + 0.06, ball.Position.Z)
		shadow.Transparency = 0.25
	else
		shadow.Transparency = 1
	end
	-- Timing ring + target highlight only while a serve is live.
	local active = state ~= nil and ball ~= nil and state.kind ~= "idle" and state.startT ~= nil
	if not active then
		ring.ImageTransparency = 1; highlight.Adornee = nil; return
	end
	ring.ImageTransparency = 0
	local now = workspace:GetServerTimeNow()
	local tToArrive = (state.startT + state.travel) - now
	local k = math.clamp(tToArrive / state.descentWindow, 0, 1)  -- 1 far out, 0 at arrival
	local scale = 1.2 + 4.0 * k
	ringGui.Size = UDim2.fromScale(scale, scale)
	ring.ImageColor3 = (k < 0.12) and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 80, 80)
	local tfloor = ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_" .. tostring(state.targetCell))
	highlight.Adornee = tfloor
end)

-- Serve input: PC = E key / click, mobile = a button, console = ButtonY.
local UIS = game:GetService("UserInputService")
local Serve = Remotes:WaitForChild("Serve")
local function tryServe() Serve:FireServer() end
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonY then tryServe() end
end)
do
	local hud = Instance.new("ScreenGui"); hud.Name = "NineSquareHUD"; hud.ResetOnSpawn = false; hud.Parent = plr:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton"); b.Size = UDim2.fromOffset(160, 64); b.Position = UDim2.new(0.5, -80, 1, -100)
	b.Text = "SERVE"; b.TextScaled = true; b.Parent = hud
	b.Activated:Connect(tryServe)
end
