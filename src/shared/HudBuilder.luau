--!strict
-- ReplicatedStorage.HudBuilder
--
-- STANDARD, STUDIO-EDITABLE HUD (build-once / self-heal). The 9-Square HUD is authored as SAVED instances
-- under StarterGui (a ScreenGui `NineSquareHUD` with named component frames, laid out with real layout
-- objects -- UIListLayout / UIPadding / UISizeConstraint + a top-level UIScale -- and the shared button/label
-- style language from GridConfig.uiStyle). StarterGui clones to each player's PlayerGui on spawn (standard).
--
-- This module is the SINGLE SOURCE for that tree's structure. Two callers:
--   * get(playerGui): client scripts call this to RESOLVE the authored HUD from their PlayerGui (binding
--     state only -- text / bar fill / Visible / button.Activated). If the authored tree is ABSENT (a fresh
--     place with no StarterGui HUD), it SELF-HEALS by building the default tree into the PlayerGui so a
--     clean place still works. It NEVER rebuilds a tree that already exists, so Studio tweaks to the saved
--     StarterGui HUD persist (build-once, like the world build).
--   * buildInto(parent): constructs the default tree under `parent` (a ScreenGui). Used by the self-heal
--     path AND by the Edit-time authoring (the StarterGui instances were authored to MIRROR this exactly,
--     so the saved HUD and a self-healed HUD are identical).
--
-- Resolution-independent + responsive: sizes/positions are SCALE-based UDim2 + a UISizeConstraint clamp,
-- and a top-level UIScale (HudScale) is driven off the viewport by applyScale() -- ONE layout scales across
-- phones + desktop with NO per-device fixed-pixel swaps.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS:WaitForChild("GridConfig"))

local HudBuilder = {}

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = parent; return c
end
local function hairline(parent: Instance)
	local UI = G.uiStyle
	local s = Instance.new("UIStroke"); s.Name = "Hairline"; s.Thickness = UI.panelHairlineThickness
	s.Color = UI.panelHairlineColor; s.Transparency = UI.panelHairlineTransparency; s.Parent = parent; return s
end
local function pad(parent: Instance, t: number, b: number, l: number, r: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t); p.PaddingBottom = UDim.new(0, b)
	p.PaddingLeft = UDim.new(0, l); p.PaddingRight = UDim.new(0, r); p.Parent = parent; return p
end

-- Build the full default tree under `parent` (a ScreenGui). Mirrors the StarterGui-authored instances.
function HudBuilder.buildInto(gui: ScreenGui)
	local UI = G.uiStyle
	gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 2

	local scale = Instance.new("UIScale"); scale.Name = "HudScale"; scale.Scale = 1; scale.Parent = gui

	-- ── TOP-RIGHT cluster: right-anchored column; UIListLayout stacks top->down (reflow, never overlap) ──
	local right = Instance.new("Frame")
	right.Name = "TopRight"; right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.new(1, -12, 0, 48)
	right.Size = UDim2.new(G.hudRightWidthScale, 0, 0, 0); right.AutomaticSize = Enum.AutomaticSize.Y
	right.BackgroundTransparency = 1; right.Parent = gui
	local rSize = Instance.new("UISizeConstraint")
	rSize.MinSize = Vector2.new(G.hudRightMinWidth, 0); rSize.MaxSize = Vector2.new(G.hudRightMaxWidth, math.huge); rSize.Parent = right
	local rList = Instance.new("UIListLayout")
	rList.FillDirection = Enum.FillDirection.Vertical; rList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rList.SortOrder = Enum.SortOrder.LayoutOrder; rList.Padding = UDim.new(0, 8); rList.Parent = right

	-- (1) Stamina bar -- LABEL panel + readable caption ABOVE a fill track (no more washed-out overlay word).
	local stamina = Instance.new("Frame")
	stamina.Name = "StaminaBar"; stamina.LayoutOrder = 1; stamina.Size = UDim2.new(1, 0, 0, 32)
	stamina.BackgroundColor3 = UI.labelBg; stamina.BackgroundTransparency = UI.labelBgTransparency
	stamina.BorderSizePixel = 0; stamina.Parent = right
	corner(stamina, UI.labelCorner); hairline(stamina); pad(stamina, 4, 4, 8, 8)
	local stamCap = Instance.new("TextLabel")
	stamCap.Name = "Caption"; stamCap.BackgroundTransparency = 1; stamCap.Size = UDim2.new(1, 0, 0, 11)
	stamCap.Position = UDim2.fromScale(0, 0); stamCap.Font = UI.labelFont; stamCap.TextSize = 11
	stamCap.TextXAlignment = Enum.TextXAlignment.Left; stamCap.TextColor3 = UI.labelMutedText
	stamCap.Text = "STAMINA"; stamCap.Parent = stamina
	local track = Instance.new("Frame")
	track.Name = "Track"; track.AnchorPoint = Vector2.new(0, 1); track.Position = UDim2.fromScale(0, 1)
	track.Size = UDim2.new(1, 0, 0, 9); track.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
	track.BackgroundTransparency = 0.2; track.BorderSizePixel = 0; track.Parent = stamina
	corner(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"; fill.Size = UDim2.fromScale(1, 1); fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(120, 220, 255); fill.Parent = track
	corner(fill, 4)

	-- (2) Scoreboard -- LABEL panel of stat rows (Turns + TAK): muted name + bright value per row.
	local scoreboard = Instance.new("Frame")
	scoreboard.Name = "Scoreboard"; scoreboard.LayoutOrder = 2; scoreboard.Size = UDim2.new(1, 0, 0, 0)
	scoreboard.AutomaticSize = Enum.AutomaticSize.Y; scoreboard.BackgroundColor3 = UI.labelBg
	scoreboard.BackgroundTransparency = UI.labelBgTransparency; scoreboard.BorderSizePixel = 0; scoreboard.Parent = right
	corner(scoreboard, UI.labelCorner); hairline(scoreboard); pad(scoreboard, 5, 5, 8, 8)
	local sList = Instance.new("UIListLayout"); sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Padding = UDim.new(0, 1); sList.Parent = scoreboard
	local STATS = { { key = "Turns", text = "Turns" }, { key = "TAK", text = "TAK" } }
	for i, spec in ipairs(STATS) do
		local row = Instance.new("Frame"); row.Name = "Row_" .. spec.key; row.LayoutOrder = i
		row.BackgroundTransparency = 1; row.Size = UDim2.new(1, 0, 0, 20); row.Parent = scoreboard
		local nm = Instance.new("TextLabel"); nm.Name = "Name"; nm.BackgroundTransparency = 1
		nm.AnchorPoint = Vector2.new(0, 0.5); nm.Position = UDim2.fromScale(0, 0.5); nm.Size = UDim2.fromScale(0.6, 1)
		nm.Font = UI.labelFont; nm.TextSize = 14; nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = UI.labelMutedText; nm.Text = spec.text; nm.Parent = row
		local val = Instance.new("TextLabel"); val.Name = "Value"; val.BackgroundTransparency = 1
		val.AnchorPoint = Vector2.new(1, 0.5); val.Position = UDim2.fromScale(1, 0.5); val.Size = UDim2.fromScale(0.4, 1)
		val.Font = Enum.Font.GothamBold; val.TextSize = 14; val.TextXAlignment = Enum.TextXAlignment.Right
		val.TextColor3 = UI.labelText; val.Text = "-"; val.Parent = row
	end

	-- (3) Join Game BUTTON -- LESS BOLD (Gotham Medium), solid GO fill, AutoButtonColor, stroke edge.
	local join = Instance.new("TextButton")
	join.Name = "JoinBtn"; join.LayoutOrder = 3; join.Visible = false; join.Size = UDim2.new(1, 0, 0, 44)
	join.BackgroundColor3 = UI.buttonGoFill; join.BackgroundTransparency = UI.buttonBgTransparency
	join.BorderSizePixel = 0; join.AutoButtonColor = true; join.Font = Enum.Font.GothamMedium
	join.TextSize = 18; join.TextColor3 = UI.buttonText; join.Text = "Join Game"; join.Parent = right
	corner(join, UI.buttonCorner)
	local jStroke = Instance.new("UIStroke"); jStroke.Name = "Edge"; jStroke.Thickness = UI.buttonStrokeThickness
	jStroke.Color = UI.buttonGoStroke; jStroke.Transparency = UI.buttonStrokeTransparency; jStroke.Parent = join

	-- (4) Spectate (leave) BUTTON -- small, low-key neutral button (don't promote leaving). Right-aligned.
	local leave = Instance.new("TextButton")
	leave.Name = "LeaveBtn"; leave.LayoutOrder = 4; leave.Visible = false
	leave.AutomaticSize = Enum.AutomaticSize.None; leave.Size = UDim2.new(0, 90, 0, 26)
	leave.BackgroundColor3 = UI.buttonNeutralFill; leave.BackgroundTransparency = UI.buttonBgTransparency
	leave.BorderSizePixel = 0; leave.AutoButtonColor = true; leave.Font = UI.labelFont
	leave.TextSize = 13; leave.TextColor3 = UI.buttonText; leave.Text = "Spectate"; leave.Parent = right
	corner(leave, UI.labelCorner)
	local lStroke = Instance.new("UIStroke"); lStroke.Name = "Edge"; lStroke.Thickness = 1
	lStroke.Color = UI.buttonNeutralStroke; lStroke.Transparency = UI.buttonStrokeTransparency; lStroke.Parent = leave

	-- (5) Spectating status LABEL -- NOT a button (flat bg, no stroke, medium font, accent TEXT tint only).
	local spec = Instance.new("Frame")
	spec.Name = "SpecLabel"; spec.LayoutOrder = 5; spec.Visible = false; spec.Size = UDim2.new(1, 0, 0, 34)
	spec.BackgroundColor3 = UI.labelBg; spec.BackgroundTransparency = UI.labelBgTransparency
	spec.BorderSizePixel = 0; spec.Parent = right
	corner(spec, UI.labelCorner)
	local specTxt = Instance.new("TextLabel"); specTxt.Name = "Text"; specTxt.BackgroundTransparency = 1
	specTxt.Size = UDim2.fromScale(1, 1); specTxt.Font = UI.labelFont; specTxt.TextSize = 15
	specTxt.TextColor3 = UI.labelText; specTxt.Text = "Spectating"; specTxt.Parent = spec

	-- ── TOP-LEFT cluster: KING chip (label) + transient toast feed ──
	local left = Instance.new("Frame")
	left.Name = "TopLeft"; left.AnchorPoint = Vector2.new(0, 0); left.Position = UDim2.new(0, 12, 0, 76)
	left.Size = UDim2.new(G.hudLeftWidthScale, 0, 0, 0); left.AutomaticSize = Enum.AutomaticSize.Y
	left.BackgroundTransparency = 1; left.Parent = gui
	local lSize = Instance.new("UISizeConstraint")
	lSize.MinSize = Vector2.new(G.hudLeftMinWidth, 0); lSize.MaxSize = Vector2.new(G.hudLeftMaxWidth, math.huge); lSize.Parent = left
	local lList = Instance.new("UIListLayout")
	lList.FillDirection = Enum.FillDirection.Vertical; lList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	lList.SortOrder = Enum.SortOrder.LayoutOrder; lList.Padding = UDim.new(0, 4); lList.Parent = left

	local king = Instance.new("Frame")
	king.Name = "KingChip"; king.LayoutOrder = 1; king.Visible = false
	king.AutomaticSize = Enum.AutomaticSize.X; king.Size = UDim2.fromOffset(0, 30)
	king.BackgroundColor3 = UI.labelBg; king.BackgroundTransparency = UI.labelBgTransparency
	king.BorderSizePixel = 0; king.Parent = left
	corner(king, UI.labelCorner); hairline(king); pad(king, 0, 0, 12, 12)
	local kingTxt = Instance.new("TextLabel"); kingTxt.Name = "Text"; kingTxt.BackgroundTransparency = 1
	kingTxt.AutomaticSize = Enum.AutomaticSize.X; kingTxt.Size = UDim2.fromScale(0, 1)
	kingTxt.Font = UI.buttonFont; kingTxt.TextSize = 16; kingTxt.TextColor3 = UI.accentKing
	kingTxt.Text = "\u{1F451} KING"; kingTxt.Parent = king

	local toasts = Instance.new("Frame")
	toasts.Name = "ToastHolder"; toasts.LayoutOrder = 2; toasts.Size = UDim2.new(1, 0, 0, 0)
	toasts.AutomaticSize = Enum.AutomaticSize.Y; toasts.BackgroundTransparency = 1; toasts.Parent = left
	local tList = Instance.new("UIListLayout")
	tList.HorizontalAlignment = Enum.HorizontalAlignment.Left; tList.SortOrder = Enum.SortOrder.LayoutOrder
	tList.Padding = UDim.new(0, 4); tList.Parent = toasts

	return gui
end

-- Resolve the authored HUD from the player's PlayerGui, SELF-HEALING a default tree if absent (fresh place).
-- Build-once: an existing NineSquareHUD (the StarterGui-authored one, cloned on spawn) is returned AS-IS so
-- Studio tweaks persist. Returns the ScreenGui (never nil).
function HudBuilder.get(playerGui: Instance): ScreenGui
	local existing = playerGui:FindFirstChild("NineSquareHUD")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end
	-- brief wait for StarterGui's clone to arrive before deciding to self-heal (avoids a double tree)
	local arrived = playerGui:WaitForChild("NineSquareHUD", 3)
	if arrived and arrived:IsA("ScreenGui") then
		return arrived
	end
	-- fresh place / no authored HUD: build the default tree so a clean place still works
	local gui = Instance.new("ScreenGui"); gui.Name = "NineSquareHUD"
	HudBuilder.buildInto(gui)
	gui.Parent = playerGui
	return gui
end

-- Drive the top-level UIScale off the viewport so ONE layout scales across phones + desktop (no per-device
-- fixed-pixel swaps). The HUD is designed for a ~1280-px-wide reference; we scale linearly with viewport
-- width and clamp so it stays legible on a tiny phone and doesn't balloon on a huge monitor. Call once +
-- on viewport changes. (A narrow PORTRAIT phone gets a slightly larger floor so the corner stays tappable.)
function HudBuilder.applyScale(gui: ScreenGui, viewport: Vector2)
	local hudScale = gui:FindFirstChild("HudScale")
	if not (hudScale and hudScale:IsA("UIScale")) then return end
	local w = math.max(1, viewport.X)
	local s = w / G.hudReferenceWidth
	-- a narrow/portrait viewport (small width) shouldn't shrink the corner to unreadable -- lift the floor
	if viewport.Y > 0 and (viewport.X / viewport.Y) <= G.mobileStatsAspectMax then
		s = math.max(s, G.hudMinScaleMobile)
	end
	hudScale.Scale = math.clamp(s, G.hudMinScale, G.hudMaxScale)
end

return HudBuilder
