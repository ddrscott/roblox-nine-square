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

-- A seated player has a real court rank (Rank > 0) and is NOT spectating. We show them a "Leave" button (the
-- counterpart to "Join Game") so they can step off the court back into the gallery lobby.
local function isSeated(): boolean
	if isSpectating() then return false end
	local rank = LocalPlayer:GetAttribute("Rank")
	return type(rank) == "number" and rank > 0
end

-- ── LOBBY / SEAT UI -- a single RIGHT-anchored column UNDER the scoreboard (this task) ─────────────────
-- The Join Game button, the new Leave button, and the Spectating/queue pill all used to sit bottom-CENTRE,
-- covering the court view. They now live in ONE right-anchored ScreenGui, stacked vertically just BELOW the
-- scoreboard (the stats panel / player-list is top-right), so nothing blocks the centre of the screen and the
-- column stays clear of the bottom-right camera-mode toggle + the default touch jump button. Visibility is
-- mutually exclusive off the server-replicated attributes (the client only reflects + requests):
--   * SPECTATING + not queued (QueuePos 0) -> Join Game button (tappable) + Spectating pill
--   * SPECTATING + queued (QueuePos N)      -> "In queue (#N)" button (disabled) + Spectating pill
--   * SEATED (Rank>0, Spectating false)     -> Leave button only (return to the gallery lobby)
-- Layout switches to compact widths/heights on a touch/portrait session.
local JoinRequest = Remotes:WaitForChild("JoinRequest")
local LeaveRequest = Remotes:WaitForChild("LeaveRequest")

local lobbyIsMobile = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	or (cam.ViewportSize.Y > 0 and (cam.ViewportSize.X / cam.ViewportSize.Y) <= G.mobileStatsAspectMax)
local colW = lobbyIsMobile and G.lobbyUIWidthMobile or G.lobbyUIWidth
local btnH = lobbyIsMobile and G.lobbyUIButtonHeightMobile or G.lobbyUIButtonHeight
local pillH = lobbyIsMobile and G.lobbyUIPillHeightMobile or G.lobbyUIPillHeight
local btnTxt = lobbyIsMobile and G.lobbyUITextSizeMobile or G.lobbyUITextSize
local pillTxt = lobbyIsMobile and G.lobbyUIPillTextSizeMobile or G.lobbyUIPillTextSize

local lobbyGui = Instance.new("ScreenGui")
lobbyGui.Name = "LobbyHud"; lobbyGui.ResetOnSpawn = false; lobbyGui.IgnoreGuiInset = false
lobbyGui.Enabled = false; lobbyGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Right-anchored column. A top-anchored vertical list growing DOWN from below the scoreboard reserve.
local lobbyCol = Instance.new("Frame")
lobbyCol.Name = "Column"; lobbyCol.AnchorPoint = Vector2.new(1, 0)
lobbyCol.Position = UDim2.new(1, -G.lobbyUISideMargin, 0, G.lobbyUITopReserve)
lobbyCol.Size = UDim2.fromOffset(colW, btnH + pillH + G.lobbyUIGap)
lobbyCol.BackgroundTransparency = 1; lobbyCol.Parent = lobbyGui
local colLayout = Instance.new("UIListLayout")
colLayout.FillDirection = Enum.FillDirection.Vertical
colLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
colLayout.SortOrder = Enum.SortOrder.LayoutOrder
colLayout.Padding = UDim.new(0, G.lobbyUIGap); colLayout.Parent = lobbyCol

-- Join / In-queue button (shown to a SPECTATING watcher).
local joinBtn = Instance.new("TextButton")
joinBtn.Name = "JoinBtn"; joinBtn.LayoutOrder = 1
joinBtn.Size = UDim2.fromOffset(colW, btnH)
joinBtn.BackgroundColor3 = Color3.fromRGB(46, 160, 92); joinBtn.BackgroundTransparency = 0.05
joinBtn.BorderSizePixel = 0; joinBtn.AutoButtonColor = true
joinBtn.Font = Enum.Font.GothamBold; joinBtn.TextSize = btnTxt
joinBtn.TextColor3 = Color3.fromRGB(245, 250, 245); joinBtn.Text = "Join Game"; joinBtn.Parent = lobbyCol
local joinCorner = Instance.new("UICorner"); joinCorner.CornerRadius = UDim.new(0, 12); joinCorner.Parent = joinBtn
local joinStroke = Instance.new("UIStroke"); joinStroke.Thickness = 2
joinStroke.Color = Color3.fromRGB(150, 235, 160); joinStroke.Transparency = 0.25; joinStroke.Parent = joinBtn

-- Leave / Spectate button (shown to a SEATED player) -- the counterpart to Join Game.
local leaveBtn = Instance.new("TextButton")
leaveBtn.Name = "LeaveBtn"; leaveBtn.LayoutOrder = 2
leaveBtn.Size = UDim2.fromOffset(colW, btnH)
leaveBtn.BackgroundColor3 = Color3.fromRGB(170, 78, 70); leaveBtn.BackgroundTransparency = 0.05
leaveBtn.BorderSizePixel = 0; leaveBtn.AutoButtonColor = true
leaveBtn.Font = Enum.Font.GothamBold; leaveBtn.TextSize = btnTxt
leaveBtn.TextColor3 = Color3.fromRGB(250, 245, 245); leaveBtn.Text = "Leave \u{2192} Spectate"; leaveBtn.Parent = lobbyCol
local leaveCorner = Instance.new("UICorner"); leaveCorner.CornerRadius = UDim.new(0, 12); leaveCorner.Parent = leaveBtn
local leaveStroke = Instance.new("UIStroke"); leaveStroke.Thickness = 2
leaveStroke.Color = Color3.fromRGB(245, 170, 160); leaveStroke.Transparency = 0.25; leaveStroke.Parent = leaveBtn

-- Spectating / queue pill (shown to a SPECTATING watcher, beneath the Join button).
local specPill = Instance.new("Frame")
specPill.Name = "SpecPill"; specPill.LayoutOrder = 3
specPill.Size = UDim2.fromOffset(colW, pillH)
specPill.BackgroundColor3 = Color3.fromRGB(20, 22, 28); specPill.BackgroundTransparency = 0.2
specPill.BorderSizePixel = 0; specPill.Parent = lobbyCol
local specCorner = Instance.new("UICorner"); specCorner.CornerRadius = UDim.new(0, 10); specCorner.Parent = specPill
local specStroke = Instance.new("UIStroke"); specStroke.Thickness = 1.5
specStroke.Color = Color3.fromRGB(255, 210, 80); specStroke.Transparency = 0.35; specStroke.Parent = specPill
local specLabel = Instance.new("TextLabel")
specLabel.BackgroundTransparency = 1; specLabel.Size = UDim2.fromScale(1, 1)
specLabel.Font = Enum.Font.GothamBold; specLabel.TextSize = pillTxt
specLabel.TextColor3 = Color3.fromRGB(235, 240, 245); specLabel.Text = "Spectating"; specLabel.Parent = specPill

local function renderLobbyHud()
	local spectating = isSpectating()
	local seated = isSeated()
	-- The whole column is only shown when there's something to show (spectating OR seated).
	lobbyGui.Enabled = spectating or seated
	joinBtn.Visible = spectating
	specPill.Visible = spectating
	leaveBtn.Visible = seated
	if spectating then
		local pos = LocalPlayer:GetAttribute("QueuePos")
		if type(pos) == "number" and pos > 0 then
			-- Queued: all 9 seats are humans; the server auto-seats the longest-waiting on the next seat freeing.
			joinBtn.Text = "In queue (#" .. tostring(pos) .. ")"
			joinBtn.BackgroundColor3 = Color3.fromRGB(70, 76, 92)
			joinBtn.AutoButtonColor = false; joinBtn.Active = false
			joinStroke.Color = Color3.fromRGB(255, 210, 80)
		else
			joinBtn.Text = "Join Game"
			joinBtn.BackgroundColor3 = Color3.fromRGB(46, 160, 92)
			joinBtn.AutoButtonColor = true; joinBtn.Active = true
			joinStroke.Color = Color3.fromRGB(150, 235, 160)
		end
		-- Pill copy: "NEXT UP" when longest-waiting, "#N in line" when queued, plain "Spectating" otherwise.
		if type(pos) == "number" and pos == 1 then
			specLabel.Text = "Spectating \u{2014} NEXT UP!"; specStroke.Color = Color3.fromRGB(150, 235, 160)
		elseif type(pos) == "number" and pos > 0 then
			specLabel.Text = "Spectating \u{2014} #" .. tostring(pos) .. " in line"; specStroke.Color = Color3.fromRGB(255, 210, 80)
		else
			specLabel.Text = "Spectating"; specStroke.Color = Color3.fromRGB(255, 210, 80)
		end
	end
end

joinBtn.Activated:Connect(function()
	-- Only request while watching + not already queued (the server re-validates regardless).
	if not isSpectating() then return end
	local pos = LocalPlayer:GetAttribute("QueuePos")
	if type(pos) == "number" and pos > 0 then return end
	JoinRequest:FireServer()
end)

leaveBtn.Activated:Connect(function()
	-- Only request a leave while actually seated (the server re-validates + frees/backfills the seat).
	if not isSeated() then return end
	LeaveRequest:FireServer()
end)

renderLobbyHud()
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(renderLobbyHud)
LocalPlayer:GetAttributeChangedSignal("QueuePos"):Connect(renderLobbyHud)
LocalPlayer:GetAttributeChangedSignal("Rank"):Connect(renderLobbyHud)

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
	-- SPECTATOR / LOBBY: hand the camera to Roblox's default third-person (Custom) so a watching player can
	-- ROAM the upper foyer freely + look around. The server spawns them on a BENCH-FREE gallery band FACING
	-- the court centre across the opening, so the trailing default camera starts over open floor looking
	-- toward the play area (not into the bench/wall). The scripted court/follow camera below is for SEATED
	-- players only (it's court-tuned + flattens focus to court height, which is wrong for a gallery roamer).
	if isSpectating() then
		cam.CameraType = Enum.CameraType.Custom
		currentFocus = nil   -- reset the eased focus so seating later glides from a fresh court target
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = G.camBaseFOV
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
