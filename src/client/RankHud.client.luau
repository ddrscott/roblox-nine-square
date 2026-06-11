--!strict
-- StarterPlayer.StarterPlayerScripts.RankHud
-- M3 step 4: minimal, server-authoritative rank/King HUD legibility.
--   (A) Rank readout -- shows the LOCAL player's current rank ("Rank N", or "KING" at rank 1), read from
--       the replicated "Rank" player attribute (the server owns it; the client only displays). Updates
--       live whenever rotation changes the player's rank.
--   (B) King-square indicator -- a glowing ring/box on cell C so the throne is always visible on the court.
-- Intentionally minimal (no leaderboard / reign timer / VFX -- those are M6).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local Remotes = RS:WaitForChild("NineSquareRemotes")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

-- Mobile = a touch session without a keyboard, OR a small/portrait viewport (so a phone-emulated portrait
-- preview also counts, not just a real touch device). Hoisted up here (above the toast feed) so both the
-- event-toast feed (C) and the compact stats panel (D) gate their compact sizing on the SAME check. The play
-- view's form factor doesn't change mid-session, so it's safe to evaluate where each consumer needs it.
-- NOTE: at the first frame `CurrentCamera.ViewportSize` can still read a transient (often portrait/zero)
-- value before it settles, which would wrongly flag a desktop session as "mobile". Wait for a settled,
-- non-zero viewport (a couple of RenderStepped frames, bounded) before trusting the aspect branch.
local RunService = game:GetService("RunService")
local function settledViewport(): Vector2?
	local cam = workspace.CurrentCamera
	for _ = 1, 5 do
		cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if vp and vp.X > 1 and vp.Y > 1 then return vp end
		RunService.RenderStepped:Wait()
	end
	local cam2 = workspace.CurrentCamera
	return cam2 and cam2.ViewportSize or nil
end

local function isMobile(): boolean
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return true end
	local vp = settledViewport()
	if vp and vp.Y > 0 and (vp.X / vp.Y) <= G.mobileStatsAspectMax then return true end
	return false
end

-- Shared HUD style language (buttons vs labels) -- everything in this script is a LABEL/PANEL (status, never
-- tappable), so it uses the flat label background + neutral panel hairline + Medium font, with the ACCENT
-- colours applied only as TEXT tint. Centralised in GridConfig so the HUD stays consistent + tweakable.
local UI = G.uiStyle

-- ── (A) Rank readout ────────────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "RankHud"; gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Top-LEFT LABEL pill: flat dark info card with a faint neutral hairline (a tidy card, NOT a button). The
-- rank ACCENT (gold KING / cyan rank) is applied to the TEXT, never as a bright button-style ring.
-- Anchored top-LEFT with a small margin and DROPPED below the Roblox CoreGui topbar buttons (menu / chat /
-- mic live top-left) so the pill never hides behind them. The toast feed stacks directly under it.
local LEFT_MARGIN = 12       -- px gap from the left screen edge
local PILL_TOP = 76          -- px from the top: clear of the top-left CoreGui icons
local pill = Instance.new("Frame")
pill.Name = "RankPill"; pill.AnchorPoint = Vector2.new(0, 0)
pill.Position = UDim2.new(0, LEFT_MARGIN, 0, PILL_TOP); pill.Size = UDim2.fromOffset(140, 40)
pill.BackgroundColor3 = UI.labelBg; pill.BackgroundTransparency = UI.labelBgTransparency
pill.BorderSizePixel = 0; pill.Parent = gui
local pillCorner = Instance.new("UICorner"); pillCorner.CornerRadius = UDim.new(0, UI.labelCorner); pillCorner.Parent = pill
local pillStroke = Instance.new("UIStroke"); pillStroke.Thickness = UI.panelHairlineThickness
pillStroke.Color = UI.panelHairlineColor; pillStroke.Transparency = UI.panelHairlineTransparency; pillStroke.Parent = pill

local rankLabel = Instance.new("TextLabel")
rankLabel.Name = "RankLabel"; rankLabel.BackgroundTransparency = 1
rankLabel.Size = UDim2.fromScale(1, 1); rankLabel.Font = UI.buttonFont
rankLabel.TextSize = 20; rankLabel.TextColor3 = UI.labelText
rankLabel.Text = "Rank ?"; rankLabel.Parent = pill

local KING_COLOR = UI.accentKing

-- While this client is an overflow SPECTATOR (M5.2), the rank pill is meaningless (no seat) -- hide it; the
-- SpectatorHud ("Spectating -- #N in line") owns the screen instead. The pill returns the instant the server
-- auto-seats us (Spectating -> false) and replicates a real Rank.
local function isSpectating(): boolean
	return LocalPlayer:GetAttribute("Spectating") == true
end

local function render(rank: number?)
	if isSpectating() then pill.Visible = false; return end
	pill.Visible = true
	if rank == nil then return end
	-- Label: tint the TEXT only (gold for KING, plain for a numbered rank). The card's hairline stays a neutral
	-- panel grey so it never reads as a tappable accent-ringed button.
	if rank <= 1 then
		rankLabel.Text = "KING"
		rankLabel.TextColor3 = KING_COLOR
	else
		rankLabel.Text = "Rank " .. tostring(rank)
		rankLabel.TextColor3 = UI.labelText
	end
end

-- The "Rank" attribute is server-owned; observe it and re-render on every change.
local function renderFromAttr()
	render(LocalPlayer:GetAttribute("Rank") :: number?)
end
renderFromAttr()
LocalPlayer:GetAttributeChangedSignal("Rank"):Connect(renderFromAttr)
-- Re-render on spectator transitions too (hide while spectating, restore the pill on auto-seat).
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(renderFromAttr)

-- ── (B) King-square indicator ────────────────────────────────────────────────────────────────────
-- A glowing gold box around cell C's floor marker so the throne is always visible. The court is built
-- on the server each Play, so we wait for / re-acquire the Floor_C part before adorning it.
local kingBox = Instance.new("SelectionBox")
kingBox.Name = "KingSquare"; kingBox.LineThickness = 0.12
kingBox.Color3 = KING_COLOR; kingBox.SurfaceColor3 = KING_COLOR
kingBox.SurfaceTransparency = 0.85; kingBox.Parent = workspace

local function floorC(): BasePart?
	local ns = workspace:FindFirstChild("NineSquare")
	local floors = ns and ns:FindFirstChild("Floors")
	local f = floors and floors:FindFirstChild("Floor_C")
	if f and f:IsA("BasePart") then return f end
	return nil
end

task.spawn(function()
	while true do
		if kingBox.Adornee == nil or kingBox.Adornee.Parent == nil then
			kingBox.Adornee = floorC()
		end
		task.wait(1)
	end
end)

-- ── (C) HUD event toast feed (M5.6) ───────────────────────────────────────────────────────────────
-- Brief, non-spammy on-screen notes for the lobby moments: a player joined/left, an auto-seat from the
-- queue, a dethrone, taking the King, or this player's own rotation. The server (authoritative) fires
-- HudEvent with { kind, text, tone }; we render a short-lived toast under the rank pill, capped to a few
-- stacked lines so a burst (e.g. several joins) never spams the screen. Display only -- no rules here.
local HudEvent = Remotes:FindFirstChild("HudEvent")
if not HudEvent then HudEvent = Remotes:WaitForChild("HudEvent", 10) end

if HudEvent then
	-- Responsive sizing: on a phone (touch / small portrait) the feed is a small corner note -- NARROWER
	-- holder + SMALLER text + FEWER stacked lines + SHORTER on-screen time -- so it never banners across the
	-- court. Desktop keeps the roomier sizing. All values are GridConfig tunables (mobile vs desktop); content
	-- and the events that fire are unchanged.
	local mobile = isMobile()
	local TOAST_WIDTH = mobile and G.toastWidthMobile or G.toastWidthDesktop
	local TOAST_HEIGHT = mobile and G.toastHeightMobile or G.toastHeightDesktop
	local TOAST_TEXTSIZE = mobile and G.toastTextSizeMobile or G.toastTextSizeDesktop
	local MAX_TOASTS = mobile and G.toastMaxLinesMobile or G.toastMaxLinesDesktop   -- cap stacked lines so a burst never floods the screen
	local TOAST_SECONDS = mobile and G.toastSecondsMobile or G.toastSecondsDesktop  -- how long each note lingers before it fades

	-- Left-anchored, stacked directly UNDER the rank pill so status reads down the LEFT edge (the top-centre
	-- stays clear of the court). The pill sits at PILL_TOP and is 40px tall; start the feed just below it.
	-- Holder height = the max stacked lines (each TOAST_HEIGHT, +4px UIListLayout padding) so it never
	-- reserves more vertical room than the cap can fill.
	local holderHeight = MAX_TOASTS * (TOAST_HEIGHT + 4)
	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "ToastHolder"; toastHolder.AnchorPoint = Vector2.new(0, 0)
	toastHolder.Position = UDim2.new(0, LEFT_MARGIN, 0, PILL_TOP + 40 + 8); toastHolder.Size = UDim2.fromOffset(TOAST_WIDTH, holderHeight)
	toastHolder.BackgroundTransparency = 1; toastHolder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 4); layout.Parent = toastHolder

	local TONE_COLOR = {
		good = UI.accentGood,
		bad = UI.accentBad,
		neutral = UI.accentNeutral,
	}
	local seq = 0

	local function showToast(text: string, tone: string?)
		-- Trim the oldest if we're at the cap (oldest = lowest LayoutOrder still present).
		local kids = {}
		for _, c in ipairs(toastHolder:GetChildren()) do
			if c:IsA("TextLabel") then table.insert(kids, c) end
		end
		if #kids >= MAX_TOASTS then
			table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			kids[1]:Destroy()
		end

		seq += 1
		local toast = Instance.new("TextLabel")
		toast.LayoutOrder = seq; toast.Size = UDim2.fromOffset(TOAST_WIDTH, TOAST_HEIGHT)
		toast.BackgroundColor3 = UI.labelBg; toast.BackgroundTransparency = UI.labelBgTransparency
		toast.BorderSizePixel = 0; toast.Font = UI.labelFont; toast.TextSize = TOAST_TEXTSIZE
		toast.TextColor3 = TONE_COLOR[tone or "neutral"] or TONE_COLOR.neutral
		toast.TextXAlignment = Enum.TextXAlignment.Left   -- read from the LEFT edge (left-anchored feed)
		toast.Text = text; toast.Parent = toastHolder
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, UI.labelCorner); corner.Parent = toast
		local tPad = Instance.new("UIPadding"); tPad.PaddingLeft = UDim.new(0, 10); tPad.PaddingRight = UDim.new(0, 10); tPad.Parent = toast

		task.delay(TOAST_SECONDS, function()
			if toast and toast.Parent then toast:Destroy() end
		end)
	end

	HudEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.text) == "string" then
			showToast(payload.text, payload.tone)
		end
	end)
end

-- ── (D) Compact MOBILE stats readout (this task) ───────────────────────────────────────────────────
-- Best / King Turns / Turns normally show in Roblox's BUILT-IN leaderstats PLAYER LIST (CoreGui, top-right,
-- opened via the player-list button). On a phone that list is bulky, not freely repositionable, and covers
-- too much of the narrow portrait play view. So on TOUCH / small (portrait) screens we hide the built-in
-- list and draw our OWN compact, RIGHT-ANCHORED panel that reads the SAME server-authoritative leaderstats
-- IntValues live (display only -- no values are computed here). Desktop is unchanged: it keeps the normal
-- built-in player list and never gets this panel.
local StarterGui = game:GetService("StarterGui")

-- isMobile() (touch/no-keyboard OR small/portrait viewport) is defined at the top of this script and shared
-- with the event-toast feed (C) above.
if isMobile() then
	-- Hide the bulky built-in player list on mobile (it's what covers the play view); our compact panel
	-- replaces it. pcall: SetCoreGuiEnabled can transiently throw before the CoreGui is ready.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	local STAT_LABELS = { { key = "Best", text = "Best" }, { key = "King Turns", text = "King" }, { key = "Turns", text = "Turns" } }
	local rowH = G.mobileStatsRowHeight
	local panelH = rowH * #STAT_LABELS + 8   -- rows + a little vertical padding

	-- Right-anchored, top-right, just below the CoreGui topbar -- out of the central play view and clear of
	-- the rank pill (now top-LEFT), the camera toggle / stamina bar / Join button (all bottom). IgnoreGuiInset
	-- is left FALSE so the panel sits under Roblox's top inset on a phone.
	local statsPanel = Instance.new("Frame")
	statsPanel.Name = "StatsPanel"; statsPanel.AnchorPoint = Vector2.new(1, 0)
	statsPanel.Position = UDim2.new(1, -G.mobileStatsMargin, 0, G.mobileStatsMargin)
	statsPanel.Size = UDim2.fromOffset(G.mobileStatsWidth, panelH)
	statsPanel.BackgroundColor3 = UI.labelBg; statsPanel.BackgroundTransparency = UI.labelBgTransparency
	statsPanel.BorderSizePixel = 0; statsPanel.Parent = gui
	local sCorner = Instance.new("UICorner"); sCorner.CornerRadius = UDim.new(0, UI.labelCorner); sCorner.Parent = statsPanel
	local sStroke = Instance.new("UIStroke"); sStroke.Thickness = UI.panelHairlineThickness
	sStroke.Color = UI.panelHairlineColor; sStroke.Transparency = UI.panelHairlineTransparency; sStroke.Parent = statsPanel
	local sPad = Instance.new("UIPadding")
	sPad.PaddingTop = UDim.new(0, 4); sPad.PaddingBottom = UDim.new(0, 4)
	sPad.PaddingLeft = UDim.new(0, 8); sPad.PaddingRight = UDim.new(0, 8); sPad.Parent = statsPanel
	local sLayout = Instance.new("UIListLayout")
	sLayout.SortOrder = Enum.SortOrder.LayoutOrder; sLayout.Padding = UDim.new(0, 0); sLayout.Parent = statsPanel

	-- Each row: a left-aligned name + a right-aligned value, both compact.
	local valueLabels: { [string]: TextLabel } = {}
	for i, spec in ipairs(STAT_LABELS) do
		local row = Instance.new("Frame")
		row.LayoutOrder = i; row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, rowH); row.Parent = statsPanel

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1; name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.fromScale(0, 0.5); name.Size = UDim2.fromScale(0.6, 1)
		name.Font = UI.labelFont; name.TextSize = G.mobileStatsTextSize
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = UI.labelMutedText; name.Text = spec.text; name.Parent = row

		local value = Instance.new("TextLabel")
		value.BackgroundTransparency = 1; value.AnchorPoint = Vector2.new(1, 0.5)
		value.Position = UDim2.fromScale(1, 0.5); value.Size = UDim2.fromScale(0.4, 1)
		value.Font = Enum.Font.GothamBold; value.TextSize = G.mobileStatsTextSize
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextColor3 = UI.labelText; value.Text = "-"; value.Parent = row
		valueLabels[spec.key] = value
	end

	-- Read the LocalPlayer's leaderstats IntValues (server-owned, replicated) and mirror them into the panel.
	-- The leaderstats folder is built on the server when this human loads, so we wait for it, then bind each
	-- value's .Changed so the panel ticks live as the player climbs / holds / rotates.
	task.spawn(function()
		local ls = LocalPlayer:WaitForChild("leaderstats", 30)
		if not ls then return end
		for _, spec in ipairs(STAT_LABELS) do
			local iv = ls:WaitForChild(spec.key, 10) :: IntValue?
			local lbl = valueLabels[spec.key]
			if iv and lbl then
				local function sync() lbl.Text = tostring(iv.Value) end
				sync()
				iv.Changed:Connect(sync)
			end
		end
	end)
end
