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

-- ── "Join Game" button (lobby / tap-to-join, this task) ─────────────────────────────────────────────
-- On join the player spawns in the gallery LOBBY watching the live game (Spectating=true, no seat). A big,
-- thumb-reachable button lets them REQUEST to enter the court (touch + desktop -- a TextButton activates on
-- tap or click). The SERVER decides seat-vs-queue (JoinRequest); the client only requests + reflects state:
--   * watching, not queued (QueuePos == 0)  -> "Join Game"   (enabled; tapping fires JoinRequest)
--   * queued, all 9 seats human (QueuePos N) -> "In queue (#N)" (disabled; auto-seated when a seat frees)
--   * seated (Spectating == false)           -> hidden        (the seated camera/HUD takes over)
local JoinRequest = Remotes:WaitForChild("JoinRequest")

local joinGui = Instance.new("ScreenGui")
joinGui.Name = "JoinGameHud"; joinGui.ResetOnSpawn = false; joinGui.IgnoreGuiInset = true
joinGui.Enabled = false; joinGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local joinBtn = Instance.new("TextButton")
joinBtn.AnchorPoint = Vector2.new(0.5, 1)
joinBtn.Position = UDim2.new(0.5, 0, 1, -86)        -- bottom-centre, above the spectator pill
joinBtn.Size = UDim2.fromOffset(220, 56)
joinBtn.BackgroundColor3 = Color3.fromRGB(46, 160, 92); joinBtn.BackgroundTransparency = 0.05
joinBtn.BorderSizePixel = 0; joinBtn.AutoButtonColor = true
joinBtn.Font = Enum.Font.GothamBold; joinBtn.TextSize = 22
joinBtn.TextColor3 = Color3.fromRGB(245, 250, 245); joinBtn.Text = "Join Game"; joinBtn.Parent = joinGui
local joinCorner = Instance.new("UICorner"); joinCorner.CornerRadius = UDim.new(0, 12); joinCorner.Parent = joinBtn
local joinStroke = Instance.new("UIStroke"); joinStroke.Thickness = 2
joinStroke.Color = Color3.fromRGB(150, 235, 160); joinStroke.Transparency = 0.25; joinStroke.Parent = joinBtn

local function renderJoinButton()
	local spectating = isSpectating()
	if not spectating then joinGui.Enabled = false; return end
	joinGui.Enabled = true
	local pos = LocalPlayer:GetAttribute("QueuePos")
	if type(pos) == "number" and pos > 0 then
		-- Queued: all 9 seats are humans; the server auto-seats the longest-waiting on the next seat freeing.
		joinBtn.Text = "In queue (#" .. tostring(pos) .. ")"
		joinBtn.BackgroundColor3 = Color3.fromRGB(70, 76, 92)
		joinBtn.AutoButtonColor = false; joinBtn.Active = false
		joinStroke.Color = Color3.fromRGB(255, 210, 80)
	else
		-- Watching the lobby, not queued: tappable request to enter the court.
		joinBtn.Text = "Join Game"
		joinBtn.BackgroundColor3 = Color3.fromRGB(46, 160, 92)
		joinBtn.AutoButtonColor = true; joinBtn.Active = true
		joinStroke.Color = Color3.fromRGB(150, 235, 160)
	end
end

joinBtn.Activated:Connect(function()
	-- Only request while watching + not already queued (the server re-validates regardless).
	if not isSpectating() then return end
	local pos = LocalPlayer:GetAttribute("QueuePos")
	if type(pos) == "number" and pos > 0 then return end
	JoinRequest:FireServer()
end)

renderJoinButton()
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(renderJoinButton)
LocalPlayer:GetAttributeChangedSignal("QueuePos"):Connect(renderJoinButton)

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
local function setFollowMode(on: boolean) end   -- forward decl (touch button label sync); defined after the GUI exists
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setFollowMode(not followMode)
	end
end)

-- ── TOUCH / MOBILE camera parity (pinch-zoom + on-screen mode toggle + fit-the-grid) ────────────────
-- Phones have no mouse wheel (zoom) and no Shift (follow toggle), and a narrow portrait FOV can't fit the
-- wide 3x3 grid. We treat a touch-enabled, keyboard-less session as mobile and: (1) drive the SAME `zoom`
-- 0..1 lerp via a two-finger pinch, (2) show a thumb-reachable button that toggles court<->follow (the
-- LeftShift equivalent), and (3) DEFAULT the framing to "fit the grid" so opening on a phone shows the whole
-- court (the per-frame fit logic lives in updateCamera). Desktop mouse-wheel + LeftShift are untouched.
local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Pinch-to-zoom: TouchPinch gives a cumulative `scale` (1 = no change; >1 = fingers spreading = pinch OUT).
-- We integrate scale CHANGES into `zoom`. Pinch out (scale rising) zooms OUT (zoom -> 0); pinch in zooms IN.
local lastPinchScale = 1
UserInputService.TouchPinch:Connect(function(_touchPositions, scale, _velocity, gpState)
	if gpState == Enum.UserInputState.Begin then
		lastPinchScale = scale
		return
	end
	local d = scale - lastPinchScale
	lastPinchScale = scale
	-- pinch OUT (d > 0) should DECREASE zoom (toward the wide court view) -> subtract
	zoom = math.clamp(zoom - d * G.camPinchSensitivity, 0, 1)
end)

-- On-screen camera-mode toggle (touch only): the LeftShift equivalent. A small, thumb-reachable button that
-- flips court-overview <-> follow and shows the current mode.
if isTouch then
	local camGui = Instance.new("ScreenGui")
	camGui.Name = "MobileCameraControls"; camGui.ResetOnSpawn = false
	camGui.IgnoreGuiInset = true; camGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -16, 1, -120)   -- bottom-right, above the default touch jump button
	btn.Size = UDim2.fromOffset(116, 54)
	btn.BackgroundColor3 = Color3.fromRGB(20, 22, 28); btn.BackgroundTransparency = 0.2
	btn.BorderSizePixel = 0; btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold; btn.TextSize = 16
	btn.TextColor3 = Color3.fromRGB(235, 240, 245)
	btn.Text = "Camera\nCourt"; btn.Parent = camGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Thickness = 1.5
	s.Color = Color3.fromRGB(255, 210, 80); s.Transparency = 0.35; s.Parent = btn

	function setFollowMode(on: boolean)
		followMode = on
		btn.Text = on and "Camera\nFollow" or "Camera\nCourt"
		s.Color = on and Color3.fromRGB(150, 235, 160) or Color3.fromRGB(255, 210, 80)
	end
	btn.Activated:Connect(function() setFollowMode(not followMode) end)
	setFollowMode(false)
else
	-- Desktop: no GUI; setFollowMode just flips the flag (keeps the LeftShift path identical to before).
	function setFollowMode(on: boolean) followMode = on end
end

-- On touch, fit the WHOLE grid when zoomed out. The four grid CORNERS (+ a margin) are at +/-gridHalfExtent
-- in X and Z, in the court's local frame (offsets from the focus / court origin).
local gridHalfExtent = 1.5 * G.squareSize + G.camFitMarginStuds
local gridCorners = {
	Vector3.new(-gridHalfExtent, 0, -gridHalfExtent), Vector3.new(gridHalfExtent, 0, -gridHalfExtent),
	Vector3.new(-gridHalfExtent, 0, gridHalfExtent), Vector3.new(gridHalfExtent, 0, gridHalfExtent),
}

-- Fit-the-grid (touch): given the design eye/look offsets (relative to the focus = court origin) and the live
-- viewport aspect, return an eye offset + FieldOfView so all four grid CORNERS fit on screen. The court cam is
-- TILTED (high + south, looking down), so the near (south) corners sit closer and subtend a wider angle than a
-- focus-distance approximation predicts -- we therefore project every corner and pull back until the WORST one
-- fits, rather than using a closed-form distance. On a narrow portrait FOV we first widen FieldOfView up to
-- camMobileMaxFOV, then (still too tight) pull the eye back ALONG ITS OWN DIRECTION (binary search), capped at
-- camFitMaxDistScale. We never pull CLOSER than the design distance, so landscape/wide aspects keep the design
-- framing. (Pulling back may put the eye outside the south wall -- the existing wall-fade handles that.)
local function worstCornerFrac(eyeOffset: Vector3, lookOffset: Vector3, fov: number, aspect: number): number
	local inv = CFrame.lookAt(eyeOffset, lookOffset):Inverse()   -- offset-space view (focus at the origin)
	local tanV = math.tan(math.rad(fov) / 2)
	local tanH = tanV * aspect
	local worst = 0
	for _, c in ipairs(gridCorners) do
		local lp = inv * c
		local depth = -lp.Z                       -- distance in front of the camera
		if depth <= 0 then return math.huge end   -- corner behind the camera -> never "fits"
		worst = math.max(worst, math.abs((lp.X / depth) / tanH), math.abs((lp.Y / depth) / tanV))
	end
	return worst   -- <= 1 means every corner is within the frustum
end
local function fitEyeForGrid(eyeOffset: Vector3, lookOffset: Vector3): (Vector3, number)
	local vp = cam.ViewportSize
	local aspect = (vp.Y > 0) and (vp.X / vp.Y) or 1
	local fov = G.camBaseFOV
	-- already fits at the design framing (landscape / wide) -> keep it exactly as-is
	if worstCornerFrac(eyeOffset, lookOffset, fov, aspect) <= 1 then return eyeOffset, fov end
	-- widen FOV (up to the mobile cap) to reduce how far we must pull back
	fov = math.min(G.camMobileMaxFOV, fov)
	if worstCornerFrac(eyeOffset, lookOffset, fov, aspect) <= 1 then return eyeOffset, fov end
	-- still too tight: pull the eye back along its direction; binary-search the smallest scale that fits, capped
	local lo, hi, best = 1.0, G.camFitMaxDistScale, G.camFitMaxDistScale
	for _ = 1, 22 do
		local mid = (lo + hi) / 2
		local cand = lookOffset + (eyeOffset - lookOffset) * mid
		if worstCornerFrac(cand, lookOffset, fov, aspect) <= 1 then best = mid; hi = mid else lo = mid end
	end
	return lookOffset + (eyeOffset - lookOffset) * best, fov
end

local currentFocus: Vector3? = nil
local function updateCamera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = G.camBaseFOV
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
	local courtView = false
	if hrp then
		target = Vector3.new(hrp.Position.X, courtOrigin().Y, hrp.Position.Z)
		farEye, farLook, nearEye, nearLook = G.camFollowFarEye, G.camFollowFarLook, G.camFollowNearEye, G.camFollowNearLook
	else
		target = courtOrigin()
		farEye, farLook, nearEye, nearLook = G.camFarEye, G.camFarLook, G.camNearEye, G.camNearLook
		courtView = true
	end
	currentFocus = currentFocus and currentFocus:Lerp(target, G.camFollowSmooth) or target
	local focus = currentFocus :: Vector3
	local eyeOffset = farEye:Lerp(nearEye, zoom)
	local lookOffset = farLook:Lerp(nearLook, zoom)
	-- TOUCH: when zoomed out, fit the whole grid (handles narrow portrait FOV). The fit only PULLS BACK /
	-- widens FOV beyond the design framing, so it's a no-op on landscape/wide aspects, and we fade it out as
	-- the player pinches IN (zoom -> 1) so close-up framing is unaffected.
	if isTouch and courtView then
		local fitEye, fitFov = fitEyeForGrid(eyeOffset, lookOffset)
		local w = 1 - zoom   -- full fit when zoomed out, none when zoomed all the way in
		eyeOffset = eyeOffset:Lerp(fitEye, w)
		cam.FieldOfView = G.camBaseFOV + (fitFov - G.camBaseFOV) * w
	end
	cam.CFrame = CFrame.lookAt(focus + eyeOffset, focus + lookOffset)
end

-- Camera-occlusion fade: the Scriptable camera bypasses Roblox's built-in auto-transparency, so when the
-- eye crosses to the OUTSIDE of a gym wall/ceiling (relative to the court centre) it would block the view
-- or let you see through into the void. We fade just those whitelisted occluders toward transparent and
-- restore them to opaque when the eye is back inside. The gym is an axis-aligned box and the camera exits
-- through at most one wall/ceiling at a time, so a per-wall side test (eye vs. the wall plane, plus a
-- margin) is robust -- no raycasting needed. Floor, grid, frame, ball, player, and Glass windows are never
-- touched (only the names below are considered).
-- Matched by NAME PREFIX (not exact name): the E/W side walls are now FRAMES of panels around a real window
-- gap (WallE_Bottom/_Top/_EndN/_EndS/_Glass, likewise WallW_*) and the ceiling is a ring (CeilingN/S/E/W), so
-- a single FindFirstChild no longer suffices. We fade EVERY gym part whose name starts with one of these
-- prefixes -- including the windowed-wall panels + their glass pane -- using each part's OWN position for the
-- per-plane side test (all panels of a wall share that wall's plane, so the test is identical + correct).
local WALL_PREFIXES = { "WallE", "WallW", "WallN", "WallS", "Ceiling" }
-- For each prefix: the position component to test and the sign of "outside" (eye beyond the plane = obstructing).
-- WallE is at +X, so the eye is outside when eye.X > wall.X (sign +1); WallW at -X uses sign -1; etc.
local WALL_AXIS = { WallE = { "X", 1 }, WallW = { "X", -1 }, WallN = { "Z", -1 }, WallS = { "Z", 1 }, Ceiling = { "Y", 1 } }
local function wallPrefixOf(name: string): string?
	-- The windowed-wall GLASS panes (WallE_Glass / WallW_Glass) keep their own resting transparency; never
	-- fade them (fading would restore them to OPAQUE when the eye is inside). Only the solid frame panels fade.
	if string.sub(name, -6) == "_Glass" then return nil end
	for _, p in ipairs(WALL_PREFIXES) do
		if name == p or string.sub(name, 1, #p + 1) == p .. "_" then return p end
	end
	return nil
end
local function updateWallFade(dt: number)
	local gym = workspace:FindFirstChild("Gym")
	if not gym then return end
	local eye = cam.CFrame.Position
	local k = math.clamp(dt * G.camWallFadeSpeed, 0, 1)   -- frame-rate-independent lerp factor
	for _, part in ipairs(gym:GetChildren()) do
		if part:IsA("BasePart") then
			local prefix = wallPrefixOf(part.Name)
			local axis = prefix and WALL_AXIS[prefix]
			if axis then
				local comp, sign = axis[1], axis[2]
				-- eye position past the wall plane (toward outside), minus a margin so it fades a touch early
				local obstructing = (eye[comp] - part.Position[comp]) * sign > -G.camWallFadeMargin
				local goal = obstructing and G.camWallFadeTransparency or 0
				part.Transparency = part.Transparency + (goal - part.Transparency) * k
			end
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
