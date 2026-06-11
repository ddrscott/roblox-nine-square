--!strict
-- StarterPlayer.StarterPlayerScripts.RankHud
-- BINDS state to the STANDARD, StarterGui-authored HUD (no layout is built here anymore -- see HudBuilder).
-- This script owns:
--   (A) the responsive UIScale driver (HudBuilder.applyScale off the live viewport),
--   (B) the KING chip (label, top-left) -- shown ONLY while THIS player holds rank 1,
--   (C) the King-square 3D indicator on cell C (a glowing box on the court -- not a GUI),
--   (D) the transient toast feed (top-left, see-through, fade-in/hold/fade-out) off HudEvent,
--   (E) the scoreboard (Turns + TAK) -- mirrors the server-owned leaderstats IntValues,
--   (F) hiding the bulky built-in PlayerList on phones (the authored Scoreboard replaces it there).
-- All HUD GUI is the StarterGui `NineSquareHUD` tree (Studio-editable; self-healed by HudBuilder if absent);
-- this script WaitForChilds the named components + binds (text / Visible / scoreboard values). No Instance.new
-- of HUD layout.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local G = require(RS.GridConfig)
local HudBuilder = require(RS:WaitForChild("HudBuilder"))
local Remotes = RS:WaitForChild("NineSquareRemotes")
local LocalPlayer = Players.LocalPlayer
local UI = G.uiStyle

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local hud = HudBuilder.get(playerGui)           -- the authored StarterGui HUD (self-healed if absent)
local topLeft = hud:WaitForChild("TopLeft")
local kingChip = topLeft:WaitForChild("KingChip")
local toastHolder = topLeft:WaitForChild("ToastHolder")
local scoreboard = hud:WaitForChild("TopRight"):WaitForChild("Scoreboard")

-- ── (A) Responsive UIScale: drive the top-level HudScale off the live viewport so ONE layout scales across
-- phones + desktop (no per-device fixed-pixel swaps). Re-applied whenever the viewport changes.
local function refreshScale()
	local cam = workspace.CurrentCamera
	if cam then HudBuilder.applyScale(hud, cam.ViewportSize) end
end
refreshScale()
do
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale) end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		refreshScale()
		local c = workspace.CurrentCamera
		if c then c:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale) end
	end)
end

-- "Mobile" = a touch session without a keyboard, OR a small/portrait viewport. Used only to hide the bulky
-- built-in PlayerList on phones (the authored Scoreboard panel reads the same leaderstats either way).
local function isMobile(): boolean
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return true end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and vp.Y > 0 and (vp.X / vp.Y) <= G.mobileStatsAspectMax then return true end
	return false
end

-- ── (B) KING chip ──────────────────────────────────────────────────────────────────────────────────
-- Shown ONLY while THIS seated player holds rank 1; hidden for every other rank + while spectating.
local function isSpectating(): boolean
	return LocalPlayer:GetAttribute("Spectating") == true
end
local function renderKing()
	local rank = LocalPlayer:GetAttribute("Rank") :: number?
	kingChip.Visible = (not isSpectating()) and type(rank) == "number" and rank <= 1
end
renderKing()
LocalPlayer:GetAttributeChangedSignal("Rank"):Connect(renderKing)
LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(renderKing)

-- ── (C) King-square 3D indicator (court adornment, not GUI) ──────────────────────────────────────────
local kingBox = Instance.new("SelectionBox")
kingBox.Name = "KingSquare"; kingBox.LineThickness = 0.12
kingBox.Color3 = UI.accentKing; kingBox.SurfaceColor3 = UI.accentKing
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

-- ── (D) Transient toast feed ─────────────────────────────────────────────────────────────────────────
-- The server trims HudEvent to the few moments that matter. Each note FADES IN, holds, FADES OUT + is
-- destroyed -- a brief corner flash that never persistently blocks the court. The holder + its UIListLayout
-- are authored under TopLeft (so toasts stack + reflow under the KING chip); we only add/remove lines.
local HudEvent = Remotes:FindFirstChild("HudEvent") or Remotes:WaitForChild("HudEvent", 10)
if HudEvent then
	local mobile = isMobile()
	local TOAST_TEXTSIZE = mobile and G.toastTextSizeMobile or G.toastTextSizeDesktop
	local MAX_TOASTS = mobile and G.toastMaxLinesMobile or G.toastMaxLinesDesktop
	local TOAST_SECONDS = mobile and G.toastSecondsMobile or G.toastSecondsDesktop
	local FADE_TIME = G.toastFadeTime
	local BG_VISIBLE = G.toastBgTransparency
	local TXT_VISIBLE = G.toastTextTransparency
	local TONE_COLOR = { good = UI.accentGood, bad = UI.accentBad, neutral = UI.accentNeutral }
	local seq = 0

	local function showToast(text: string, tone: string?)
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
		toast.LayoutOrder = seq
		toast.AutomaticSize = Enum.AutomaticSize.Y; toast.Size = UDim2.new(1, 0, 0, 0)
		toast.BackgroundColor3 = UI.labelBg; toast.BorderSizePixel = 0
		toast.Font = UI.labelFont; toast.TextSize = TOAST_TEXTSIZE
		toast.TextWrapped = true; toast.TextColor3 = TONE_COLOR[tone or "neutral"] or TONE_COLOR.neutral
		toast.TextXAlignment = Enum.TextXAlignment.Left
		toast.BackgroundTransparency = 1; toast.TextTransparency = 1     -- start invisible -> fade in
		toast.Text = text; toast.Parent = toastHolder
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, UI.labelCorner); corner.Parent = toast
		local tPad = Instance.new("UIPadding")
		tPad.PaddingLeft = UDim.new(0, 10); tPad.PaddingRight = UDim.new(0, 10)
		tPad.PaddingTop = UDim.new(0, 3); tPad.PaddingBottom = UDim.new(0, 3); tPad.Parent = toast

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

-- ── (E) Scoreboard (Turns + TAK) -- mirror the server-owned leaderstats IntValues into the authored panel.
-- (F) On phones, hide the bulky built-in PlayerList (the authored Scoreboard replaces it there).
if isMobile() then
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) end)
end
task.spawn(function()
	local ls = LocalPlayer:WaitForChild("leaderstats", 30)
	if not ls then return end
	for _, key in ipairs({ "Turns", "TAK" }) do
		local row = scoreboard:FindFirstChild("Row_" .. key)
		local valLbl = row and row:FindFirstChild("Value")
		local iv = ls:WaitForChild(key, 10) :: IntValue?
		if iv and valLbl and valLbl:IsA("TextLabel") then
			local function sync() (valLbl :: TextLabel).Text = tostring(iv.Value) end
			sync()
			iv.Changed:Connect(sync)
		end
	end
end)
