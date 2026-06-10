--!strict
-- StarterPlayer.StarterPlayerScripts.NineSquareClient
-- Renders the flat ball shadow, a height-based "strike" ring, the predicted-landing highlight,
-- and locks an angled court camera. Serving is physical (no button) -- just get under the ball and jump.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local Remotes = RS:WaitForChild("NineSquareRemotes")
local BallSync = Remotes:WaitForChild("BallSync")

local cam = workspace.CurrentCamera

-- Court origin from the built C floor (sits at the court origin on the ground).
local function courtOrigin(): Vector3
	local ns = workspace:FindFirstChild("NineSquare")
	local cFloor = ns and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_C")
	if cFloor then return Vector3.new(cFloor.Position.X, 0, cFloor.Position.Z) end
	return G.origin
end

-- Flat shadow disc. For a Cylinder, local X is the AXIS/length, so the thin dimension goes on X
-- and the circle (diameter) on Y/Z; rotating 90deg about Z lays it flat on the floor.
local shadow = Instance.new("Part")
shadow.Name = "BallShadow"; shadow.Anchored = true; shadow.CanCollide = false; shadow.CastShadow = false
shadow.Shape = Enum.PartType.Cylinder
shadow.Size = Vector3.new(0.2, G.ballRadius * 3, G.ballRadius * 3)
shadow.Orientation = Vector3.new(0, 0, 90)
shadow.Color = Color3.new(0, 0, 0); shadow.Material = Enum.Material.SmoothPlastic; shadow.Transparency = 0.25
shadow.Parent = workspace

-- Camera-facing "strike" ring over the shadow: small/green when the ball is at strike height.
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
	-- Shadow ALWAYS tracks the ball so you can line yourself up under it.
	if ball then
		local o = courtOrigin()
		shadow.Position = Vector3.new(ball.Position.X, o.Y + 0.06, ball.Position.Z)
		shadow.Transparency = 0.25
	else
		shadow.Transparency = 1
	end
	-- Strike ring (height cue) + predicted-landing highlight, while a ball is live.
	local active = state ~= nil and ball ~= nil and state.kind ~= "idle"
	if not active then
		ring.ImageTransparency = 1; highlight.Adornee = nil; return
	end
	ring.ImageTransparency = 0
	local fh = state.frameHeight or G.frameHeight
	local diff = math.abs(ball.Position.Y - fh)            -- 0 = ball is at your strike height
	local k = math.clamp(diff / 8, 0, 1)
	ringGui.Size = UDim2.fromScale(1.2 + 4.0 * k, 1.2 + 4.0 * k)
	ring.ImageColor3 = (diff < 1.8) and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 80, 80)
	local tcell = state.targetCell
	local tfloor = tcell and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_" .. tostring(tcell))
	highlight.Adornee = tfloor
end)
