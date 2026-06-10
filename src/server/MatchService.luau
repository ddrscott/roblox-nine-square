--!strict
-- ServerScriptService.NineSquare.MatchService
-- M1 stub: builds the arena + gym and answers "which outer square is a player under?".
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local MatchService = {}

function MatchService.buildArena(origin: Vector3)
	G.origin = origin
	local old = workspace:FindFirstChild("NineSquare"); if old then old:Destroy() end
	local root = Instance.new("Folder"); root.Name = "NineSquare"; root.Parent = workspace
	-- Per-cell markers: invisible, non-colliding, thin. The gym's WoodPlanks floor is the ONE visible
	-- floor; these only exist as the landing-highlight adornee + fault-flash target (BallController
	-- toggles them briefly visible). Sat just above the wood so a flash never z-fights the floor.
	local floors = Instance.new("Folder"); floors.Name = "Floors"; floors.Parent = root
	for name in pairs(G.cells) do
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CastShadow = false
		p.Size = Vector3.new(G.squareSize - 0.5, 0.1, G.squareSize - 0.5)
		p.Position = G.cellCenter(name) + Vector3.new(0, 0.06, 0)
		p.Transparency = 1; p.Color = Color3.fromRGB(205, 45, 45)  -- only seen during a fault flash
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

	-- The default Baseplate's top sits at y=0, coplanar with the gym floor -> z-fighting + a gray
	-- 2048-stud plane poking past the court. Drop it far below (out of view); the enclosed gym is
	-- the real floor. Done here (buildArena runs every Play) so it self-heals on a fresh place.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Position = Vector3.new(baseplate.Position.X, -100, baseplate.Position.Z)
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

-- A simple enclosed gymnasium around the court: wood floor, walls, ceiling, windows, hoops, lights.
function MatchService.buildGym(origin: Vector3)
	if workspace:FindFirstChild("Gym") then return workspace.Gym end  -- build once; preserve manual tweaks
	local gym = Instance.new("Folder"); gym.Name = "Gym"; gym.Parent = workspace
	local function block(name, size, pos, color, mat, transp)
		local p = Instance.new("Part"); p.Anchored = true; p.Name = name
		p.Size = size; p.Position = pos; p.Color = color; p.Material = mat
		p.Transparency = transp or 0
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = gym
		return p
	end
	local W, L, H = 70, 100, 50          -- interior width (x), length (z), height (ceiling clears the camera)
	local hx, hz, wy = W/2, L/2, H/2
	local wood = Color3.fromRGB(196, 152, 98)
	local wall = Color3.fromRGB(224, 216, 196)
	local ceil = Color3.fromRGB(150, 150, 162)
	-- the single visible floor: top flush at the logical floor (y=0), where the ball lands + players stand
	block("Floor", Vector3.new(W + 8, 1, L + 8), origin + Vector3.new(0, -0.5, 0), wood, Enum.Material.WoodPlanks)
	block("Ceiling", Vector3.new(W + 8, 1, L + 8), origin + Vector3.new(0, H, 0), ceil, Enum.Material.SmoothPlastic)
	block("WallE", Vector3.new(0.8, H, L), origin + Vector3.new(hx, wy, 0), wall, Enum.Material.SmoothPlastic)
	block("WallW", Vector3.new(0.8, H, L), origin + Vector3.new(-hx, wy, 0), wall, Enum.Material.SmoothPlastic)
	block("WallN", Vector3.new(W, H, 0.8), origin + Vector3.new(0, wy, -hz), wall, Enum.Material.SmoothPlastic)
	block("WallS", Vector3.new(W, H, 0.8), origin + Vector3.new(0, wy, hz), wall, Enum.Material.SmoothPlastic)
	-- cosmetic window strips on the side walls
	local glass = Color3.fromRGB(170, 205, 230)
	block("WindowE", Vector3.new(0.3, 7, L - 20), origin + Vector3.new(hx - 0.5, 30, 0), glass, Enum.Material.Glass, 0.5)
	block("WindowW", Vector3.new(0.3, 7, L - 20), origin + Vector3.new(-hx + 0.5, 30, 0), glass, Enum.Material.Glass, 0.5)
	-- two simple basketball hoops on the end walls
	for _, zsign in ipairs({ -1, 1 }) do
		block("Backboard", Vector3.new(7, 4, 0.4), origin + Vector3.new(0, 22, zsign * (hz - 0.7)), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic)
		block("Rim", Vector3.new(2.6, 0.3, 1.8), origin + Vector3.new(0, 20.4, zsign * (hz - 1.8)), Color3.fromRGB(235, 120, 40), Enum.Material.SmoothPlastic)
	end
	-- ceiling light fixtures
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 0, 1 }) do
			local lp = block("Light", Vector3.new(8, 0.4, 8), origin + Vector3.new(dx * 18, H - 0.6, dz * 28), Color3.fromRGB(255, 255, 235), Enum.Material.Neon)
			-- Brightness/Range kept modest: at 4/55 these 6 lights over-exposed the ball at court
			-- center, blowing its highlight to white and tripping the scene Bloom into a glow halo.
			local pl = Instance.new("PointLight"); pl.Brightness = 1.8; pl.Range = 45; pl.Color = Color3.fromRGB(255, 250, 235); pl.Parent = lp
		end
	end
	return gym
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
