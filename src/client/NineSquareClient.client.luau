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

-- ── Spectator state (M5.2) ───────────────────────────────────────────────────────────────────────
-- When this client is an overflow spectator (humans > 9 seats) the server replicates a `Spectating` flag
-- and a 1-based `QueuePos` ("#N in line"). We show a court-overlook camera + a "Spectating -- #N in line"
-- HUD, and flip cleanly back to the normal seated camera/HUD the instant the server auto-seats us
-- (Spectating -> false). Server-authoritative -- the client only reflects these attributes.
local function isSpectating(): boolean
	return LocalPlayer:GetAttribute("Spectating") == true
end

local specGui = Instance.new("ScreenGui")
specGui.Name = "SpectatorHud"; specGui.ResetOnSpawn = false; specGui.Enabled = false
specGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local specPill = Instance.new("Frame")
specPill.AnchorPoint = Vector2.new(0.5, 1)
specPill.Position = UDim2.new(0.5, 0, 1, -28); specPill.Size = UDim2.fromOffset(280, 44)
specPill.BackgroundColor3 = Color3.fromRGB(20, 22, 28); specPill.BackgroundTransparency = 0.2
specPill.BorderSizePixel = 0; specPill.Parent = specGui
local specCorner = Instance.new("UICorner"); specCorner.CornerRadius = UDim.new(0, 10); specCorner.Parent = specPill
local specStroke = Instance.new("UIStroke"); specStroke.Thickness = 1.5
specStroke.Color = Color3.fromRGB(255, 210, 80); specStroke.Transparency = 0.35; specStroke.Parent = specPill

local specLabel = Instance.new("TextLabel")
specLabel.BackgroundTransparency = 1; specLabel.Size = UDim2.fromScale(1, 1)
specLabel.Font = Enum.Font.GothamBold; specLabel.TextSize = 18
specLabel.TextColor3 = Color3.fromRGB(235, 240, 245); specLabel.Text = "Spectating"; specLabel.Parent = specPill

local function renderSpectatorHud()
	local spectating = isSpectating()
	specGui.Enabled = spectating
	if spectating then
		local pos = LocalPlayer:GetAttribute("QueuePos")
		if type(pos) == "number" and pos == 1 then
			-- Longest-waiting: you take the next freed seat. Make the "you're up next" read unmistakable.
			specLabel.Text = "Spectating  --  NEXT UP!"
			specStroke.Color = Color3.fromRGB(150, 235, 160)
		elseif type(pos) == "number" and pos > 0 then
			specLabel.Text = "Spectating  --  #" .. tostring(pos) .. " in line"
			specStroke.Color = Color3.fromRGB(255, 210, 80)
		else
			specLabel.Text = "Spectating"
			specStroke.Color = Color3.fromRGB(255, 210, 80)
		end
	end
end

renderSpectatorHud()
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(renderSpectatorHud)
LocalPlayer:GetAttributeChangedSignal("QueuePos"):Connect(renderSpectatorHud)

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
	-- SPECTATOR (M5.2): a fixed high court-overlook looking straight down at the whole 9-square, so an
	-- overflow player watches the match while they wait. (The mezzanine gallery view is M5.3; this is the
	-- temporary overlook.) Eases via currentFocus so flipping in/out of spectator mode glides smoothly.
	if isSpectating() then
		local o = courtOrigin()
		currentFocus = currentFocus and currentFocus:Lerp(o, G.camFollowSmooth) or o
		local focus = currentFocus :: Vector3
		cam.CFrame = CFrame.lookAt(focus + G.specOverlookEye, focus + G.specOverlookLook)
		return
	end
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

-- Camera-occlusion fade: the Scriptable camera bypasses Roblox's built-in auto-transparency, so when the
-- eye crosses to the OUTSIDE of a gym wall/ceiling (relative to the court centre) it would block the view
-- or let you see through into the void. We fade just those whitelisted occluders toward transparent and
-- restore them to opaque when the eye is back inside. The gym is an axis-aligned box and the camera exits
-- through at most one wall/ceiling at a time, so a per-wall side test (eye vs. the wall plane, plus a
-- margin) is robust -- no raycasting needed. Floor, grid, frame, ball, player, and Glass windows are never
-- touched (only the names below are considered).
local WALL_NAMES = { "WallE", "WallW", "WallN", "WallS", "Ceiling" }
-- For each wall: the position component to test and the sign of "outside" (eye beyond the plane = obstructing).
-- WallE is at +X, so the eye is outside when eye.X > wall.X (sign +1); WallW at -X uses sign -1; etc.
local WALL_AXIS = { WallE = { "X", 1 }, WallW = { "X", -1 }, WallN = { "Z", -1 }, WallS = { "Z", 1 }, Ceiling = { "Y", 1 } }
local function updateWallFade(dt: number)
	local gym = workspace:FindFirstChild("Gym")
	if not gym then return end
	local eye = cam.CFrame.Position
	local k = math.clamp(dt * G.camWallFadeSpeed, 0, 1)   -- frame-rate-independent lerp factor
	for _, name in ipairs(WALL_NAMES) do
		local wall = gym:FindFirstChild(name)
		local axis = WALL_AXIS[name]
		if wall and wall:IsA("BasePart") and axis then
			local comp, sign = axis[1], axis[2]
			-- eye position past the wall plane (toward outside), minus a margin so it fades a touch early
			local obstructing = (eye[comp] - wall.Position[comp]) * sign > -G.camWallFadeMargin
			local goal = obstructing and G.camWallFadeTransparency or 0
			wall.Transparency = wall.Transparency + (goal - wall.Transparency) * k
		end
	end
end

RunService.RenderStepped:Connect(function(dt)
	updateCamera()
	updateWallFade(dt)
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
