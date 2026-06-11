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
local LocalPlayer = Players.LocalPlayer

-- ── (A) Rank readout ────────────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "RankHud"; gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Top-centre pill, styled to match the stamina bar (Gotham, rounded, semi-transparent dark).
local pill = Instance.new("Frame")
pill.Name = "RankPill"; pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 16); pill.Size = UDim2.fromOffset(140, 40)
pill.BackgroundColor3 = Color3.fromRGB(20, 22, 28); pill.BackgroundTransparency = 0.2
pill.BorderSizePixel = 0; pill.Parent = gui
local pillCorner = Instance.new("UICorner"); pillCorner.CornerRadius = UDim.new(0, 10); pillCorner.Parent = pill
local pillStroke = Instance.new("UIStroke"); pillStroke.Thickness = 1.5
pillStroke.Color = Color3.fromRGB(120, 220, 255); pillStroke.Transparency = 0.4; pillStroke.Parent = pill

local rankLabel = Instance.new("TextLabel")
rankLabel.Name = "RankLabel"; rankLabel.BackgroundTransparency = 1
rankLabel.Size = UDim2.fromScale(1, 1); rankLabel.Font = Enum.Font.GothamBold
rankLabel.TextSize = 20; rankLabel.TextColor3 = Color3.fromRGB(235, 240, 245)
rankLabel.Text = "Rank ?"; rankLabel.Parent = pill

local KING_COLOR = Color3.fromRGB(255, 210, 80)
local NORMAL_COLOR = Color3.fromRGB(120, 220, 255)

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
	if rank <= 1 then
		rankLabel.Text = "KING"
		rankLabel.TextColor3 = KING_COLOR
		pillStroke.Color = KING_COLOR
	else
		rankLabel.Text = "Rank " .. tostring(rank)
		rankLabel.TextColor3 = Color3.fromRGB(235, 240, 245)
		pillStroke.Color = NORMAL_COLOR
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
