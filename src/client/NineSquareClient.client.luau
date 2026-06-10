--!strict
-- StarterPlayer.StarterPlayerScripts.NineSquareClient
-- Soft height-aware ball shadow, strike-height ring, predicted-landing highlight, and a clear fixed
-- high court camera. Serving is physical (no button) -- get under the ball and jump.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local G = require(RS.GridConfig)
local Remotes = RS:WaitForChild("NineSquareRemotes")
local BallSync = Remotes:WaitForChild("BallSync")
local cam = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local function courtOrigin(): Vector3
	local ns = workspace:FindFirstChild("NineSquare")
	local cFloor = ns and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_C")
	if cFloor then return Vector3.new(cFloor.Position.X, 0, cFloor.Position.Z) end
	return G.origin
end

-- Soft shadow: stacked translucent discs that grow + fade with ball height (fakes a soft penumbra).
local shadowFolder = Instance.new("Folder"); shadowFolder.Name = "BallShadow"; shadowFolder.Parent = workspace
local discSpecs = { { r = 1.3, a = 0.42 }, { r = 2.1, a = 0.60 }, { r = 3.0, a = 0.80 } }
local discs = {}
for i, spec in ipairs(discSpecs) do
	local d = Instance.new("Part")
	d.Name = "ShadowDisc" .. i; d.Anchored = true; d.CanCollide = false; d.CastShadow = false
	d.Shape = Enum.PartType.Cylinder; d.Orientation = Vector3.new(0, 0, 90)
	d.Color = Color3.new(0, 0, 0); d.Material = Enum.Material.SmoothPlastic; d.Transparency = 1
	d.Parent = shadowFolder
	discs[i] = { part = d, spec = spec }
end

-- Strike-height ring on the core disc: green/small when the ball is at strike height.
local ringGui = Instance.new("BillboardGui"); ringGui.Size = UDim2.fromScale(6, 6); ringGui.Parent = discs[1].part
local ring = Instance.new("ImageLabel")
ring.BackgroundTransparency = 1; ring.Size = UDim2.fromScale(1, 1); ring.ImageTransparency = 1
ring.Image = "rbxassetid://5028857084"; ring.ImageColor3 = Color3.fromRGB(255, 80, 80); ring.Parent = ringGui

local highlight = Instance.new("SelectionBox")
highlight.LineThickness = 0.08; highlight.Color3 = Color3.fromRGB(255, 210, 80); highlight.Parent = workspace

-- Player ground shadow: a soft dark disc under the local player so you can read your position on the
-- floor relative to the ball's shadow. It grows + fades with jump height (also a jump-height cue).
local playerShadow = Instance.new("Part")
playerShadow.Name = "PlayerShadow"; playerShadow.Anchored = true; playerShadow.CanCollide = false
playerShadow.CanQuery = false; playerShadow.CastShadow = false
playerShadow.Shape = Enum.PartType.Cylinder; playerShadow.Orientation = Vector3.new(0, 0, 90)
playerShadow.Color = Color3.new(0, 0, 0); playerShadow.Material = Enum.Material.SmoothPlastic; playerShadow.Transparency = 1
playerShadow.Parent = shadowFolder

local state: any = nil
BallSync.OnClientEvent:Connect(function(data) state = data end)

-- Mouse-wheel zoom: 0 = zoomed out (default high view), 1 = zoomed in. Scroll up to zoom in.
local zoom = 0
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom = math.clamp(zoom + input.Position.Z * G.camZoomStep, 0, 1)
	end
end)

-- Shift toggles FOLLOW mode: the camera tracks the local player (keeps them centred) instead of the
-- fixed court overview. Tap LeftShift / RightShift to toggle.
local followMode = false
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		followMode = not followMode
	end
end)

-- Court camera: high and behind (south), looking down at the grid. The mouse wheel zooms between each
-- mode's far (out) and near (in) offsets; zooming in raises the look target so the view pitches up and
-- shows less floor. In follow mode the offsets are tighter (gym-safe) and centred on the player. The
-- focus point eases (camFollowSmooth) so toggling modes / following glides smoothly.
local currentFocus: Vector3? = nil
local function updateCamera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 58
	local target, farEye, farLook, nearEye, nearLook
	local char = LocalPlayer.Character
	local hrp = followMode and char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		target = Vector3.new(hrp.Position.X, courtOrigin().Y, hrp.Position.Z)
		farEye, farLook, nearEye, nearLook = G.camFollowFarEye, G.camFollowFarLook, G.camFollowNearEye, G.camFollowNearLook
	else
		target = courtOrigin()
		farEye, farLook, nearEye, nearLook = G.camFarEye, G.camFarLook, G.camNearEye, G.camNearLook
	end
	currentFocus = currentFocus and currentFocus:Lerp(target, G.camFollowSmooth) or target
	local focus = currentFocus :: Vector3
	cam.CFrame = CFrame.lookAt(focus + farEye:Lerp(nearEye, zoom), focus + farLook:Lerp(nearLook, zoom))
end

RunService.RenderStepped:Connect(function()
	updateCamera()
	-- player ground shadow: tracks the local player's XZ; grows + fades with jump height
	local pchar = LocalPlayer.Character
	local phrp = pchar and pchar:FindFirstChild("HumanoidRootPart")
	if phrp then
		local po = courtOrigin()
		local ph = math.max(0, (phrp.Position.Y - 2.5) - po.Y)   -- feet height above the floor
		local pgrow = 1 + math.clamp(ph / 16, 0, 1.5) * 0.7
		playerShadow.Size = Vector3.new(0.1, 5 * pgrow, 5 * pgrow)
		playerShadow.Position = Vector3.new(phrp.Position.X, po.Y + 0.04, phrp.Position.Z)
		playerShadow.Transparency = math.clamp(0.55 + ph / 30, 0, 0.92)
	else
		playerShadow.Transparency = 1
	end
	local ns = workspace:FindFirstChild("NineSquare")
	local ball = ns and ns:FindFirstChild("Ball")
	if ball then
		local o = courtOrigin()
		local h = math.max(0, ball.Position.Y - o.Y)             -- ball height above the floor
		local grow = 1 + math.clamp(h / G.frameHeight, 0, 1.5) * 0.8   -- bigger when higher
		local fade = math.clamp(h / (G.frameHeight * 1.4), 0, 1) * 0.45 -- fainter when higher
		for i, dd in ipairs(discs) do
			local diameter = G.ballRadius * 2 * dd.spec.r * grow
			dd.part.Size = Vector3.new(0.12, diameter, diameter)
			dd.part.Position = Vector3.new(ball.Position.X, o.Y + 0.05 + i * 0.008, ball.Position.Z)
			dd.part.Transparency = math.clamp(dd.spec.a + fade, 0, 1)
		end
	else
		for _, dd in ipairs(discs) do dd.part.Transparency = 1 end
	end
	-- strike ring (height cue) + predicted-landing highlight while a ball is live
	local active = state ~= nil and ball ~= nil and state.kind ~= "idle"
	if not active then ring.ImageTransparency = 1; highlight.Adornee = nil; return end
	ring.ImageTransparency = 0
	local fh = state.frameHeight or G.frameHeight
	local diff = math.abs(ball.Position.Y - fh)                  -- 0 = ball at your strike height
	local s = 1.4 + 4.0 * math.clamp(diff / 8, 0, 1)
	ringGui.Size = UDim2.fromScale(s, s)
	ring.ImageColor3 = (diff < 1.8) and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 80, 80)
	local tcell = state.targetCell
	local tfloor = tcell and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_" .. tostring(tcell))
	highlight.Adornee = tfloor
end)
