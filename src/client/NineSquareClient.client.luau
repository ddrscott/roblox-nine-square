--!strict
-- StarterPlayer.StarterPlayerScripts.NineSquareClient
-- Strike-height ring, predicted-landing highlight, and a clear fixed high court camera. Position shadows are
-- the real overhead sun's job now (the old fake ball/player discs were removed). Serving is physical (no
-- button) -- get under the ball and jump.
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

-- Position shadows (the fake ball discs + the player disc) were REMOVED -- the sun is overhead now and casts
-- real straight-down shadows under the ball + players, so the artificial ones are redundant. We keep the two
-- GAMEPLAY cues below (the strike-height ring + the predicted-landing highlight); those are NOT position
-- shadows. The strike ring is re-homed onto a minimal invisible anchor that tracks the ball's floor XZ.

-- Strike-ring anchor: a single tiny invisible, non-colliding, non-querying part that sits on the floor under
-- the ball. It exists ONLY to host the strike-ring BillboardGui (replacing the old core shadow disc); it
-- never collides, never casts a shadow, and is never seen.
local ringAnchor = Instance.new("Part")
ringAnchor.Name = "StrikeRingAnchor"; ringAnchor.Anchored = true; ringAnchor.CanCollide = false
ringAnchor.CanQuery = false; ringAnchor.CastShadow = false; ringAnchor.Transparency = 1
ringAnchor.Size = Vector3.new(0.1, 0.1, 0.1); ringAnchor.Parent = workspace

-- Strike-height ring (hit-timing cue): green/small when the ball is at strike height, red/large otherwise.
local ringGui = Instance.new("BillboardGui"); ringGui.Size = UDim2.fromScale(6, 6); ringGui.Parent = ringAnchor
local ring = Instance.new("ImageLabel")
ring.BackgroundTransparency = 1; ring.Size = UDim2.fromScale(1, 1); ring.ImageTransparency = 1
ring.Image = "rbxassetid://5028857084"; ring.ImageColor3 = Color3.fromRGB(255, 80, 80); ring.Parent = ringGui

local highlight = Instance.new("SelectionBox")
highlight.LineThickness = 0.08; highlight.Color3 = Color3.fromRGB(255, 210, 80); highlight.Parent = workspace

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

-- ── LOBBY / SEAT UI -- BIND to the StarterGui-authored HUD (no layout built here) ──────────────────────
-- The Join Game button + the small Spectate (leave) button are AUTHORED in the StarterGui `NineSquareHUD`
-- TopRight cluster (Studio-editable; self-healed by HudBuilder if absent), stacked under the stamina bar +
-- scoreboard via a UIListLayout so they never collide. This script only RESOLVES them by name + binds state
-- -- it builds no layout. (The old separate "Spectating" status label was dropped as redundant -- the world
-- now signs the foyer "Spectators Area"; the Join button carries the queue position.) Visibility is mutually
-- exclusive off the server-replicated attributes (the client only reflects + requests):
--   * SPECTATING + not queued (QueuePos 0) -> Join Game button (tappable)
--   * SPECTATING + queued (QueuePos N)      -> "In queue (#N)" / "Next up!" button (disabled), carries position
--   * SEATED (Rank>0, Spectating false)     -> small Spectate button only (return to the gallery lobby)
local JoinRequest = Remotes:WaitForChild("JoinRequest")
local LeaveRequest = Remotes:WaitForChild("LeaveRequest")

-- Shared HUD style language (buttons look tappable; labels look static). Centralised in GridConfig.
local UI = G.uiStyle

local HudBuilder = require(RS:WaitForChild("HudBuilder"))
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local hud = HudBuilder.get(playerGui)               -- the authored StarterGui HUD (self-healed if absent)
local topRight = hud:WaitForChild("TopRight")
local joinBtn = topRight:WaitForChild("JoinBtn") :: TextButton
local joinStroke = joinBtn:WaitForChild("Edge") :: UIStroke
local leaveBtn = topRight:WaitForChild("LeaveBtn") :: TextButton

local function renderLobbyHud()
	local spectating = isSpectating()
	local seated = isSeated()
	joinBtn.Visible = spectating
	leaveBtn.Visible = seated
	if spectating then
		-- The separate "Spectating" status label was dropped (redundant: the world now signs the foyer with
		-- "Spectators Area" wall text). The Join button CARRIES the queue state so a queued player still sees
		-- their position -- "Join Game" when joinable, "NEXT UP!" when first in line, "In queue (#N)" otherwise.
		local pos = LocalPlayer:GetAttribute("QueuePos")
		if type(pos) == "number" and pos > 0 then
			-- Queued: all 9 seats are humans; the server auto-seats the longest-waiting on the next seat freeing.
			-- Visibly DISABLED -- flat grey, dimmed text, no stroke, non-tappable (doesn't read as a live button).
			joinBtn.Text = (pos == 1) and "Next up!" or ("In queue (#" .. tostring(pos) .. ")")
			joinBtn.BackgroundColor3 = UI.buttonDisabledFill
			joinBtn.TextColor3 = (pos == 1) and UI.accentGood or UI.buttonDisabledText
			joinBtn.AutoButtonColor = false; joinBtn.Active = false
			joinStroke.Transparency = 1
		else
			joinBtn.Text = "Join Game"
			joinBtn.BackgroundColor3 = UI.buttonGoFill
			joinBtn.TextColor3 = UI.buttonText
			joinBtn.AutoButtonColor = true; joinBtn.Active = true
			joinStroke.Color = UI.buttonGoStroke; joinStroke.Transparency = UI.buttonStrokeTransparency
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
	btn.BackgroundColor3 = G.uiStyle.buttonNeutralFill; btn.BackgroundTransparency = G.uiStyle.buttonBgTransparency
	btn.BorderSizePixel = 0; btn.AutoButtonColor = true
	btn.Font = G.uiStyle.buttonFont; btn.TextSize = 16
	btn.TextColor3 = G.uiStyle.buttonText
	btn.Text = "Camera\nCourt"; btn.Parent = camGui
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, G.uiStyle.buttonCorner); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Thickness = G.uiStyle.buttonStrokeThickness
	s.Color = G.uiStyle.accentKing; s.Transparency = G.uiStyle.buttonStrokeTransparency; s.Parent = btn

	function setFollowMode(on: boolean)
		followMode = on
		btn.Text = on and "Camera\nFollow" or "Camera\nCourt"
		s.Color = on and G.uiStyle.accentGood or G.uiStyle.accentKing
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
	-- The invisible ball-BARRIER (WallE_Barrier / WallW_Barrier) that seals each window gap to the ball must
	-- likewise NEVER fade -- it is Transparency=1 by design (window stays visually open); fading would lerp it
	-- toward opaque when the eye is inside and make the barrier visible across the open window.
	if string.sub(name, -6) == "_Glass" or string.sub(name, -8) == "_Barrier" then return nil end
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
	local ns = workspace:FindFirstChild("NineSquare")
	local ball = ns and ns:FindFirstChild("Ball")
	-- Keep the strike-ring anchor on the floor directly under the ball (its XZ), so the ring renders where the
	-- old core shadow disc used to be. (Position shadows are now the real sun's job.)
	if ball then
		local o = courtOrigin()
		ringAnchor.Position = Vector3.new(ball.Position.X, o.Y + 0.05, ball.Position.Z)
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
