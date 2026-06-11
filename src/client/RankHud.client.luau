--!strict
-- StarterPlayer.StarterPlayerScripts.RankHud
-- Minimal, server-authoritative King HUD (re-imagined: no generic rank pill, no rank-change toasts).
--   (A) Subtle KING chip -- a small top-LEFT "KING" chip shown ONLY while THIS player holds the throne
--       (rank 1), read from the replicated "Rank" attribute. There is NO generic "Rank N" pill anymore:
--       rank is obvious from where you stand + the floor rank numbers, so a persistent pill was redundant
--       clutter over the court. The chip vanishes the moment you're not King.
--   (B) King-square indicator -- a glowing ring/box on cell C so the throne is always visible on the court.
--   (C) Transient notice feed -- a few brief, small, semi-transparent, fast-fading corner notes (seating /
--       King moment); see the feed section. (D) Compact mobile Turns/TAK scoreboard.
-- Intentionally minimal (no leaderboard / reign timer / VFX).
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

-- ── (A) Subtle KING-only chip ──────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "RankHud"; gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Shared top-LEFT layout anchors. There is NO persistent rank pill: a player's rank is obvious from where
-- they stand + the floor rank numbers, so a "Rank N" card was redundant clutter. The ONLY persistent
-- top-left element is a small KING chip shown while THIS player reigns (rank 1). LEFT_MARGIN / PILL_TOP also
-- anchor the transient notice feed (C) so it reads down the left edge, clear of the court + CoreGui icons.
local LEFT_MARGIN = 12       -- px gap from the left screen edge
local PILL_TOP = 76          -- px from the top: clear of the top-left CoreGui icons

local KING_COLOR = UI.accentKing

-- Small KING chip (label, never a button): flat low-opacity card, faint hairline, gold KING text. Sized to
-- the word, shown ONLY at rank 1. Hidden otherwise (including while spectating, which has no seat/rank).
local kingChip = Instance.new("Frame")
kingChip.Name = "KingChip"; kingChip.AnchorPoint = Vector2.new(0, 0)
kingChip.Position = UDim2.new(0, LEFT_MARGIN, 0, PILL_TOP); kingChip.Size = UDim2.fromOffset(86, 34)
kingChip.BackgroundColor3 = UI.labelBg; kingChip.BackgroundTransparency = UI.labelBgTransparency
kingChip.BorderSizePixel = 0; kingChip.Visible = false; kingChip.Parent = gui
local kcCorner = Instance.new("UICorner"); kcCorner.CornerRadius = UDim.new(0, UI.labelCorner); kcCorner.Parent = kingChip
local kcStroke = Instance.new("UIStroke"); kcStroke.Thickness = UI.panelHairlineThickness
kcStroke.Color = UI.panelHairlineColor; kcStroke.Transparency = UI.panelHairlineTransparency; kcStroke.Parent = kingChip
local kingLabel = Instance.new("TextLabel")
kingLabel.Name = "KingLabel"; kingLabel.BackgroundTransparency = 1
kingLabel.Size = UDim2.fromScale(1, 1); kingLabel.Font = UI.buttonFont
kingLabel.TextSize = 18; kingLabel.TextColor3 = KING_COLOR
kingLabel.Text = "\u{1F451} KING"; kingLabel.Parent = kingChip

-- While this client is an overflow SPECTATOR (M5.2) there's no seat/rank -- the chip is hidden; the lobby HUD
-- ("Spectating -- #N in line") owns the screen instead.
local function isSpectating(): boolean
	return LocalPlayer:GetAttribute("Spectating") == true
end

-- Show the KING chip ONLY when this seated player holds rank 1; hide it for every other rank + while spectating.
local function renderFromAttr()
	local rank = LocalPlayer:GetAttribute("Rank") :: number?
	kingChip.Visible = (not isSpectating()) and type(rank) == "number" and rank <= 1
end
renderFromAttr()
LocalPlayer:GetAttributeChangedSignal("Rank"):Connect(renderFromAttr)
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

-- ── (C) Transient notice feed ──────────────────────────────────────────────────────────────────────
-- The server trims HudEvent to the few moments that matter (a brief "You're in" on seating, a queue note,
-- the King moment). We render each as a SMALL, SEMI-TRANSPARENT, FAST-FADING corner note that flashes
-- briefly and is gone -- it never persistently blocks the court (the corners are occupied: CoreGui top-left,
-- scoreboard top-right, touch controls bottom). Each note tweens UP to readable, holds briefly, then fades
-- OUT and is destroyed, so the feed is empty most of the time. Display only -- no rules ride on it.
local TweenService = game:GetService("TweenService")
local HudEvent = Remotes:FindFirstChild("HudEvent")
if not HudEvent then HudEvent = Remotes:WaitForChild("HudEvent", 10) end

if HudEvent then
	-- Responsive sizing: a phone (touch / small portrait) gets a NARROWER holder + SMALLER text + FEWER stacked
	-- lines + SHORTER on-screen time so it reads as a tiny corner flash, never a banner. All GridConfig tunables.
	local mobile = isMobile()
	local TOAST_WIDTH = mobile and G.toastWidthMobile or G.toastWidthDesktop
	local TOAST_HEIGHT = mobile and G.toastHeightMobile or G.toastHeightDesktop
	local TOAST_TEXTSIZE = mobile and G.toastTextSizeMobile or G.toastTextSizeDesktop
	local MAX_TOASTS = mobile and G.toastMaxLinesMobile or G.toastMaxLinesDesktop   -- cap stacked lines so a burst never floods the screen
	local TOAST_SECONDS = mobile and G.toastSecondsMobile or G.toastSecondsDesktop  -- visible hold (before the fade-out)
	local FADE_TIME = G.toastFadeTime                                               -- in/out tween length (flash feel)
	-- Notices are MORE see-through than persistent labels so they never read as a solid block over the court.
	local BG_VISIBLE = G.toastBgTransparency
	local TXT_VISIBLE = G.toastTextTransparency

	-- Left-anchored, stacked from PILL_TOP down the LEFT edge (no rank pill anymore; the rare KING chip sits at
	-- PILL_TOP, so the feed begins just below that slot to avoid overlap when the chip is shown). Holder height =
	-- the max stacked lines so it never reserves more vertical room than the cap can fill.
	local holderHeight = MAX_TOASTS * (TOAST_HEIGHT + 4)
	local toastHolder = Instance.new("Frame")
	toastHolder.Name = "ToastHolder"; toastHolder.AnchorPoint = Vector2.new(0, 0)
	toastHolder.Position = UDim2.new(0, LEFT_MARGIN, 0, PILL_TOP + 40); toastHolder.Size = UDim2.fromOffset(TOAST_WIDTH, holderHeight)
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
		toast.BackgroundColor3 = UI.labelBg
		toast.BorderSizePixel = 0; toast.Font = UI.labelFont; toast.TextSize = TOAST_TEXTSIZE
		toast.TextColor3 = TONE_COLOR[tone or "neutral"] or TONE_COLOR.neutral
		toast.TextXAlignment = Enum.TextXAlignment.Left   -- read from the LEFT edge (left-anchored feed)
		-- Start fully transparent so it FADES IN (flash feel) rather than popping.
		toast.BackgroundTransparency = 1; toast.TextTransparency = 1
		toast.Text = text; toast.Parent = toastHolder
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, UI.labelCorner); corner.Parent = toast
		local tPad = Instance.new("UIPadding"); tPad.PaddingLeft = UDim.new(0, 10); tPad.PaddingRight = UDim.new(0, 10); tPad.Parent = toast

		-- Fade IN to the (semi-transparent) visible state, hold TOAST_SECONDS, then fade OUT + destroy.
		local inInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(toast, inInfo, { BackgroundTransparency = BG_VISIBLE, TextTransparency = TXT_VISIBLE }):Play()
		task.delay(FADE_TIME + TOAST_SECONDS, function()
			if not (toast and toast.Parent) then return end
			local outInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local out = TweenService:Create(toast, outInfo, { BackgroundTransparency = 1, TextTransparency = 1 })
			out.Completed:Connect(function() if toast and toast.Parent then toast:Destroy() end end)
			out:Play()
		end)
	end

	HudEvent.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.text) == "string" then
			showToast(payload.text, payload.tone)
		end
	end)
end

-- ── (D) Compact MOBILE scoreboard (Turns + TAK) ─────────────────────────────────────────────────────
-- The scoreboard is just two stats: Turns (= rallies played) and TAK (= Turns As King). They show in
-- Roblox's BUILT-IN leaderstats PLAYER LIST (CoreGui, top-right) on desktop. On a phone that list is bulky,
-- not freely repositionable, and covers too much of the narrow portrait play view. So on TOUCH / small
-- (portrait) screens we hide the built-in list and draw our OWN compact, RIGHT-ANCHORED panel that reads the
-- SAME server-authoritative leaderstats IntValues live (display only -- no values are computed here).
-- Desktop is unchanged: it keeps the normal built-in list (now only Turns + TAK) and never gets this panel.
local StarterGui = game:GetService("StarterGui")

-- isMobile() (touch/no-keyboard OR small/portrait viewport) is defined at the top of this script and shared
-- with the event-toast feed (C) above.
if isMobile() then
	-- Hide the bulky built-in player list on mobile (it's what covers the play view); our compact panel
	-- replaces it. pcall: SetCoreGuiEnabled can transiently throw before the CoreGui is ready.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	local STAT_LABELS = { { key = "Turns", text = "Turns" }, { key = "TAK", text = "TAK" } }
	local rowH = G.mobileStatsRowHeight
	local panelH = rowH * #STAT_LABELS + 8   -- rows + a little vertical padding

	-- Right-anchored, top-right, just below the CoreGui topbar -- out of the central play view and clear of
	-- the top-LEFT KING chip / notice feed and the bottom camera toggle / stamina bar / Join button.
	-- IgnoreGuiInset is left FALSE so the panel sits under Roblox's top inset on a phone.
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
