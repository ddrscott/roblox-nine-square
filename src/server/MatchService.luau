--!strict
-- ServerScriptService.NineSquare.MatchService
-- M1 stub: builds the arena and answers "which outer square is a player under?".
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local MatchService = {}

function MatchService.buildArena(origin: Vector3)
	G.origin = origin
	local old = workspace:FindFirstChild("NineSquare"); if old then old:Destroy() end
	local root = Instance.new("Folder"); root.Name = "NineSquare"; root.Parent = workspace
	local floors = Instance.new("Folder"); floors.Name = "Floors"; floors.Parent = root
	for name in pairs(G.cells) do
		local p = Instance.new("Part")
		p.Anchored = true; p.Size = Vector3.new(G.squareSize - 0.5, G.floorThickness, G.squareSize - 0.5)
		p.Position = G.cellCenter(name) - Vector3.new(0, G.floorThickness/2, 0)
		p.Color = (name == "C") and Color3.fromRGB(70,70,80) or Color3.fromRGB(150,150,160)
		p.Material = Enum.Material.SmoothPlastic; p.Name = "Floor_" .. name; p.Parent = floors
	end
	local frame = Instance.new("Folder"); frame.Name = "Frame"; frame.Parent = root
	local span = 3 * G.squareSize
	-- four boundary lines per axis at the cell edges: +/-0.5 and +/-1.5 squares
	for _, m in ipairs({ -1.5, -0.5, 0.5, 1.5 }) do
		local offs = m * G.squareSize
		local beams = {
			{ Vector3.new(span, G.beamThickness, G.beamThickness), Vector3.new(0, 0, offs) },  -- E-W beam
			{ Vector3.new(G.beamThickness, G.beamThickness, span), Vector3.new(offs, 0, 0) },  -- N-S beam
		}
		for _, ln in ipairs(beams) do
			local b = Instance.new("Part"); b.Anchored = true; b.Size = ln[1]
			b.Position = G.origin + ln[2] + Vector3.new(0, G.frameHeight, 0)
			b.Color = Color3.fromRGB(40,40,45); b.Material = Enum.Material.Neon; b.Parent = frame
		end
	end

	-- Painted grid lines on the floor: a renderer-independent "shadow" of the frame, so the grid
	-- reads on the floor in Play mode too (dynamic shadows often don't draw in Studio Play / low quality).
	local lines = Instance.new("Folder"); lines.Name = "GridLines"; lines.Parent = root
	local lineW = 0.6
	for _, m in ipairs({ -1.5, -0.5, 0.5, 1.5 }) do
		local offs = m * G.squareSize
		local strips = {
			{ Vector3.new(span, 0.1, lineW), Vector3.new(0, 0, offs) },   -- E-W line
			{ Vector3.new(lineW, 0.1, span), Vector3.new(offs, 0, 0) },   -- N-S line
		}
		for _, ln in ipairs(strips) do
			local s = Instance.new("Part"); s.Anchored = true; s.CanCollide = false; s.CastShadow = false
			s.Size = ln[1]
			s.Position = G.origin + ln[2] + Vector3.new(0, 0.06, 0)
			s.Color = Color3.fromRGB(45, 45, 55); s.Material = Enum.Material.SmoothPlastic; s.Transparency = 0.1
			s.Parent = lines
		end
	end

	-- Spawn pad at the center square, and disable any far/legacy spawns so players start in the court.
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then d.Enabled = false end
	end
	-- invisible, non-colliding spawn marker: you spawn at center and land on the center floor,
	-- with no visible platform and nothing to occlude the ball's floor shadow.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CourtSpawn"; spawn.Anchored = true; spawn.Neutral = true; spawn.Enabled = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = G.cellCenter("C") + Vector3.new(0, 0.5, 0)
	spawn.Transparency = 1; spawn.CanCollide = false
	spawn.Parent = root
	return root
end

-- Outer square a player currently stands under, or nil.
function MatchService.playerCell(plr: Player): string?
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local cell = G.cellAtPosition(hrp.Position)
	if cell and cell ~= "C" then return cell end
	return nil
end

return MatchService
