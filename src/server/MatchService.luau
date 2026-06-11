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
	-- Floor RANK NUMBERS (replaces the M5.6 over-grid nameplates): a large painted-court number centred on
	-- each panel, facing UP, via a SurfaceGui on the panel's Top face. STATIC per cell (= rankForCell(cell)):
	-- centre C reads "1" (the King throne), then 2..9 outward. Built on a DEDICATED thin part per cell (NOT
	-- the Floor_ marker, which flashes red on a fault) -- CanCollide=false, CastShadow=false, OUTSIDE the
	-- ball/player collision sets. The part itself is invisible; only the SurfaceGui number renders.
	local numbers = Instance.new("Folder"); numbers.Name = "FloorNumbers"; numbers.Parent = root
	for name in pairs(G.cells) do
		local rank = G.rankForCell(name)
		if rank then
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
			p.Size = Vector3.new(G.squareSize - 0.5, 0.1, G.squareSize - 0.5)
			p.Position = G.cellCenter(name) + Vector3.new(0, G.floorNumberYOffset, 0)
			p.Transparency = 1  -- the panel is invisible; the SurfaceGui number is what shows
			p.Name = "FloorNum_" .. name; p.Parent = numbers

			local gui = Instance.new("SurfaceGui")
			gui.Name = "Number"; gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 50; gui.LightInfluence = 0
			gui.Adornee = p; gui.Parent = p

			local label = Instance.new("TextLabel")
			label.Name = "Label"; label.BackgroundTransparency = 1
			-- Centred, sized to a fraction of the panel so it fills most of the cell without overpowering the grid.
			label.AnchorPoint = Vector2.new(0.5, 0.5); label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.fromScale(G.floorNumberSizeFrac, G.floorNumberSizeFrac)
			label.Font = Enum.Font.GothamBlack; label.TextScaled = true
			label.TextColor3 = (rank == 1) and G.floorNumberKingColor or G.floorNumberColor
			label.TextTransparency = G.floorNumberTransparency
			label.Text = tostring(rank); label.Parent = gui
		end
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

	-- Cosmetic corner support posts so the overhead frame "stands on" the court instead of hovering.
	-- KEPT OUT of the Frame folder + CanCollide=false on purpose: BallController:_surfaces() collides the
	-- ball against every BasePart under NineSquare.Frame, so these legs must NOT live there (ball feel
	-- stays unchanged). Positions/size derive from GridConfig so they track tunable changes.
	local legs = Instance.new("Folder"); legs.Name = "FrameLegs"; legs.Parent = root
	local legOuter = 1.5 * G.squareSize  -- frame's outer corner offset on X and Z
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local leg = Instance.new("Part")
			leg.Anchored = true; leg.CanCollide = false; leg.CastShadow = true
			leg.Size = Vector3.new(G.legThickness, G.frameHeight, G.legThickness)
			leg.Position = G.origin + Vector3.new(sx * legOuter, G.frameHeight / 2, sz * legOuter)
			leg.Color = Color3.fromRGB(40, 40, 45); leg.Material = Enum.Material.SmoothPlastic
			leg.Name = "Leg_" .. (sx < 0 and "W" or "E") .. (sz < 0 and "N" or "S")
			leg.Parent = legs
		end
	end

	-- Painted grid lines on the floor: a renderer-independent "shadow" of the frame, so the grid
	-- reads on the floor in Play mode too (dynamic shadows often don't draw in Studio Play / low quality).
	local lines = Instance.new("Folder"); lines.Name = "GridLines"; lines.Parent = root
	-- Tuned to read as a soft SHADOW of the overhead frame, not bold paint: a slightly warm dark-grey
	-- on the warm tan WoodPlanks, held mostly-transparent + narrow so it's just a hint of the grid.
	local lineW = 0.5
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
			s.Color = Color3.fromRGB(64, 52, 40); s.Material = Enum.Material.SmoothPlastic; s.Transparency = 0.66
			s.Parent = lines
		end
	end

	-- SaveHighlight overlay: the overhead Frame beams are CONTINUOUS lines (not per-cell), so to light up
	-- only the LAST-SAVED square's pipes we keep a SEPARATE 4-segment neon outline that we reposition over
	-- the saved cell's border at frameHeight. Built hidden (Transparency=1); highlightSavedCell shows it.
	-- KEPT OUT of NineSquare.Frame + CanCollide=false on purpose: BallController:_surfaces() collides the
	-- ball against every BasePart under NineSquare.Frame, so this overlay must NOT live there (ball feel
	-- stays unchanged). 4 segments named N/S (E-W edges) and E/W (N-S edges) so highlightSavedCell can move them.
	local hi = Instance.new("Folder"); hi.Name = "SaveHighlight"; hi.Parent = root
	for _, seg in ipairs({ "N", "S", "E", "W" }) do
		local b = Instance.new("Part")
		b.Anchored = true; b.CanCollide = false; b.CastShadow = false
		b.Color = G.saveHighlightColor; b.Material = Enum.Material.Neon
		b.Transparency = 1                                   -- hidden until a save lights it
		b.Name = "Seg_" .. seg; b.Parent = hi
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
	local W, L, H = 70, 70, 50           -- square interior (x = z); height clears the camera
	local hx, hz, wy = W/2, L/2, H/2
	local wood = Color3.fromRGB(196, 152, 98)
	local wall = Color3.fromRGB(224, 216, 196)
	local ceil = Color3.fromRGB(150, 150, 162)
	-- the single visible floor: top flush at the logical floor (y=0), where the ball lands + players stand
	block("Floor", Vector3.new(W + 8, 1, L + 8), origin + Vector3.new(0, -0.5, 0), wood, Enum.Material.WoodPlanks)
	-- Ceiling with a rectangular OPENING over the court (the "window" spectators look down through). Built as
	-- a RING of 4 panels around the central hole instead of one solid slab so the gallery above sees the
	-- court. The opening matches the gallery floor opening (G.galleryOpening) so the sightline is unbroken.
	-- The ring panels stay CanCollide=true (overhead, far above play) -- they never enter the court collision
	-- (not under NineSquare.Frame) and the hole keeps them off the ball's arc.
	do
		local op = G.galleryOpening
		local cs = W + 8                                  -- full ceiling span (matches the old solid slab)
		local side = (cs - op) / 2                        -- width of each N/S panel band
		local Hy = H
		-- N / S panels run full width on X, fill the band beyond the opening on Z
		block("CeilingN", Vector3.new(cs, 1, side), origin + Vector3.new(0, Hy, -(op + side) / 2), ceil, Enum.Material.SmoothPlastic)
		block("CeilingS", Vector3.new(cs, 1, side), origin + Vector3.new(0, Hy,  (op + side) / 2), ceil, Enum.Material.SmoothPlastic)
		-- E / W panels fill the band beyond the opening on X, only as deep as the opening (corners covered by N/S)
		block("CeilingE", Vector3.new(side, 1, op), origin + Vector3.new( (op + side) / 2, Hy, 0), ceil, Enum.Material.SmoothPlastic)
		block("CeilingW", Vector3.new(side, 1, op), origin + Vector3.new(-(op + side) / 2, Hy, 0), ceil, Enum.Material.SmoothPlastic)
	end
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

	-- ---- M5.3 UPPER-FLOOR SPECTATOR GALLERY -------------------------------------------------------
	-- A second level above the gym ceiling with a RING floor (opening over the court), short perimeter
	-- walls, a roof, a spectator spawn, a railing around the opening, and creator-store decor. Spectators
	-- (M5.2) spawn here (GridConfig.specSpawnOffset) and watch the match straight down through the opening.
	-- Everything is environmental: the floor ring + walls collide (so you can stand/walk) but live OUTSIDE
	-- NineSquare.Frame, so the ball never collides with any of it (BallController._surfaces only collides
	-- parts under NineSquare.Frame). It sits ABOVE the gym (galleryFloorY > H) so it can't block a seated
	-- player's court camera or the wall-fade occlusion (those operate on the gym walls/ceiling below).
	MatchService.buildGallery(origin, gym, W, L)

	return gym
end

-- Build the upper-floor spectator gallery into `gym`. Separated so the dimensions/positions read clearly
-- and Scott can re-run just this from the GridConfig tunables. Idempotent within buildGym's build-once.
function MatchService.buildGallery(origin: Vector3, gym: Instance, W: number, L: number)
	local op = G.galleryOpening
	local fy = G.galleryFloorY
	local fth = G.galleryFloorThickness
	local cs = W + 8                                  -- gallery span = ceiling span (sits directly above)
	local side = (cs - op) / 2                        -- width of each N/S floor band beyond the opening
	local floorTop = fy
	local floorMid = floorTop - fth / 2               -- part centre so its TOP is at galleryFloorY
	local woodG = Color3.fromRGB(180, 140, 92)        -- gallery floor: a slightly cooler wood than the court
	local wallG = Color3.fromRGB(210, 204, 188)
	local roofG = Color3.fromRGB(140, 140, 152)

	local gallery = Instance.new("Folder"); gallery.Name = "Gallery"; gallery.Parent = gym
	local function gpart(name, size, pos, color, mat, collide)
		local p = Instance.new("Part"); p.Anchored = true; p.Name = name
		p.Size = size; p.Position = pos; p.Color = color; p.Material = mat
		p.CanCollide = collide; p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = gallery
		return p
	end

	-- Floor RING (4 panels around the opening) -- the walkable mezzanine. Collides so spectators stand on it.
	gpart("GalFloorN", Vector3.new(cs, fth, side), origin + Vector3.new(0, floorMid, -(op + side) / 2), woodG, Enum.Material.WoodPlanks, true)
	gpart("GalFloorS", Vector3.new(cs, fth, side), origin + Vector3.new(0, floorMid,  (op + side) / 2), woodG, Enum.Material.WoodPlanks, true)
	gpart("GalFloorE", Vector3.new(side, fth, op), origin + Vector3.new( (op + side) / 2, floorMid, 0), woodG, Enum.Material.WoodPlanks, true)
	gpart("GalFloorW", Vector3.new(side, fth, op), origin + Vector3.new(-(op + side) / 2, floorMid, 0), woodG, Enum.Material.WoodPlanks, true)

	-- Short perimeter walls + roof so the gallery reads as an enclosed upper room (not a floating slab).
	local wh = G.galleryWallHeight
	local wmid = floorTop + wh / 2
	gpart("GalWallE", Vector3.new(0.8, wh, cs), origin + Vector3.new(cs / 2, wmid, 0), wallG, Enum.Material.SmoothPlastic, true)
	gpart("GalWallW", Vector3.new(0.8, wh, cs), origin + Vector3.new(-cs / 2, wmid, 0), wallG, Enum.Material.SmoothPlastic, true)
	gpart("GalWallN", Vector3.new(cs, wh, 0.8), origin + Vector3.new(0, wmid, -cs / 2), wallG, Enum.Material.SmoothPlastic, true)
	gpart("GalWallS", Vector3.new(cs, wh, 0.8), origin + Vector3.new(0, wmid, cs / 2), wallG, Enum.Material.SmoothPlastic, true)
	gpart("GalRoof", Vector3.new(cs + 2, 1, cs + 2), origin + Vector3.new(0, floorTop + wh, 0), roofG, Enum.Material.SmoothPlastic, true)

	-- A couple of soft lights so the gallery isn't a dark box.
	for _, dx in ipairs({ -1, 1 }) do
		local lp = gpart("GalLight", Vector3.new(6, 0.4, 6), origin + Vector3.new(dx * (op / 2 + side / 2), floorTop + wh - 0.6, 0), Color3.fromRGB(255, 255, 235), Enum.Material.Neon, false)
		local pl = Instance.new("PointLight"); pl.Brightness = 1.4; pl.Range = 34; pl.Color = Color3.fromRGB(255, 250, 235); pl.Parent = lp
	end

	-- Railing ring around the OPENING so spectators don't walk off into the court below. Built from code as
	-- a fallback; if a creator-store railing TEMPLATE exists in ReplicatedStorage (inserted via the MCP and
	-- renamed), it's cloned along each edge instead for a nicer look. Either way it's CanCollide so it blocks
	-- the fall but is OUTSIDE NineSquare.Frame (never touches the ball).
	local rh = G.galleryRailHeight
	local rinset = G.galleryRailInset
	local railLen = op + 2 * rinset
	local railHalf = op / 2 + rinset
	local railMid = floorTop + rh / 2
	local railColor = Color3.fromRGB(90, 96, 110)
	local railTemplate = RS:FindFirstChild("GalleryRailTemplate")
	local benchTemplate = RS:FindFirstChild("GalleryBenchTemplate")
	local function buildRail(name, size, pos)
		if railTemplate then
			local r = railTemplate:Clone()
			r.Name = name
			if r:IsA("Model") and r.PrimaryPart then
				r:PivotTo(CFrame.new(pos))
			elseif r:IsA("BasePart") then
				r.Position = pos
			end
			r.Parent = gallery
		else
			gpart(name, size, pos, railColor, Enum.Material.Metal, true)
		end
	end
	-- 4 rail segments framing the opening (N/S run along X; E/W run along Z)
	buildRail("GalRailN", Vector3.new(railLen, rh, 0.4), origin + Vector3.new(0, railMid, -railHalf))
	buildRail("GalRailS", Vector3.new(railLen, rh, 0.4), origin + Vector3.new(0, railMid,  railHalf))
	buildRail("GalRailE", Vector3.new(0.4, rh, railLen), origin + Vector3.new( railHalf, railMid, 0))
	buildRail("GalRailW", Vector3.new(0.4, rh, railLen), origin + Vector3.new(-railHalf, railMid, 0))

	-- Bench/bleacher seating along the back (south) wall so spectators have somewhere to sit + watch. Uses a
	-- creator-store bench template if inserted (GalleryBenchTemplate); else a simple code bench. Non-colliding
	-- decor seating (CanCollide false so it never wedges a spectator) -- purely cosmetic.
	local benchZ = cs / 2 - 6
	for _, bx in ipairs({ -1, 0, 1 }) do
		if benchTemplate and benchTemplate:IsA("Model") and benchTemplate.PrimaryPart then
			-- creator-store bench: the template is normalized so its FEET sit at the model bottom; FootToPivotY
			-- (stored on the template when it was inserted) is the pivot's height above the feet, so placing the
			-- pivot at floorTop + FootToPivotY drops the bench cleanly onto the gallery floor. Face it toward the
			-- opening (look -Z, toward the court) so seated spectators look at the match.
			local lift = benchTemplate:GetAttribute("FootToPivotY") or 0
			local b = benchTemplate:Clone(); b.Name = "GalBench"
			b:PivotTo(CFrame.new(origin + Vector3.new(bx * 16, floorTop + lift, benchZ)) * CFrame.Angles(0, math.pi, 0))
			b.Parent = gallery
		else
			-- code fallback bench (used if the creator-store template wasn't inserted into ReplicatedStorage)
			local bpos = origin + Vector3.new(bx * 16, floorTop + 1.5, benchZ)
			gpart("GalBench", Vector3.new(10, 1, 2.4), bpos, Color3.fromRGB(150, 110, 70), Enum.Material.Wood, false)
			gpart("GalBenchBack", Vector3.new(10, 3, 0.5), bpos + Vector3.new(0, 1.7, -1.0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood, false)
		end
	end

	-- Spectator spawn IN the gallery: a SpawnLocation on the south floor band (clear of the opening) so M5.2
	-- spectators appear up here and can walk + watch through the opening. Neutral + non-team so it doesn't
	-- override the court spawn for seated players (the server teleports seated humans to their cell anyway;
	-- spectators are parked here by parkSpectator using the matching GridConfig.specSpawnOffset).
	local sspawn = Instance.new("SpawnLocation")
	sspawn.Name = "GallerySpawn"; sspawn.Anchored = true; sspawn.Neutral = true; sspawn.Enabled = false
	sspawn.Size = Vector3.new(8, 1, 6)
	sspawn.Position = origin + Vector3.new(0, floorTop + 0.5, op / 2 + side / 2)
	sspawn.Transparency = 1; sspawn.CanCollide = false
	sspawn.Parent = gallery

	return gallery
end

-- Per-cell flash generation tokens. Each flashCell call bumps the cell's token and captures it; only the
-- LATEST call's delayed hide is allowed to blank the panel. This lets the server RE-ASSERT a flash (e.g.
-- extend the OUT square's red through the land->rest settle) without an earlier, shorter hide clearing it.
local flashGen: { [string]: number } = {}

-- Flash a cell's floor panel red for `duration` seconds (default GridConfig.faultFlashDuration). The OUT
-- square stays red from the fault landing until the rotation runs at rest; re-asserting just extends it.
function MatchService.flashCell(cell: string?, duration: number?)
	if not cell then return end
	local ns = workspace:FindFirstChild("NineSquare")
	local floors = ns and ns:FindFirstChild("Floors")
	local f = floors and floors:FindFirstChild("Floor_" .. cell)
	if not f or not f:IsA("BasePart") then return end
	local gen = (flashGen[cell] or 0) + 1
	flashGen[cell] = gen
	f.Color = Color3.fromRGB(205, 45, 45)
	f.Transparency = 0.3
	task.delay(duration or G.faultFlashDuration, function()
		-- Only the most recent flash for this cell may hide it (a later re-assert wins).
		if f and f.Parent and flashGen[cell] == gen then f.Transparency = 1 end
	end)
end

-- Light up the overhead frame pipes of the LAST-SAVED square: reposition the 4 SaveHighlight edge
-- segments to outline `cell`'s border at frameHeight and make them visible. Persists until the next
-- call moves it to a new save. Visual only -- the overlay is non-colliding and out of _surfaces.
function MatchService.highlightSavedCell(cell: string?)
	if not cell then return end
	local ns = workspace:FindFirstChild("NineSquare")
	local hi = ns and ns:FindFirstChild("SaveHighlight")
	if not hi then return end
	local center = G.cellCenter(cell)
	local y = G.frameHeight + G.saveHighlightYOffset
	local half = G.squareSize / 2
	local th = G.saveHighlightThickness
	-- the cell's full edge length, slightly overlapped at the corners so the outline reads as a closed box
	local len = G.squareSize + th
	-- N/S = the two E-W edges (run along X, offset on Z); E/W = the two N-S edges (run along Z, offset on X)
	local segs = {
		N = { size = Vector3.new(len, th, th), pos = Vector3.new(center.X, y, center.Z - half) },
		S = { size = Vector3.new(len, th, th), pos = Vector3.new(center.X, y, center.Z + half) },
		E = { size = Vector3.new(th, th, len), pos = Vector3.new(center.X + half, y, center.Z) },
		W = { size = Vector3.new(th, th, len), pos = Vector3.new(center.X - half, y, center.Z) },
	}
	for name, s in pairs(segs) do
		local b = hi:FindFirstChild("Seg_" .. name)
		if b and b:IsA("BasePart") then
			b.Size = s.size; b.Position = s.pos; b.Color = G.saveHighlightColor
			b.Transparency = G.saveHighlightTransparency   -- dimmed: a faint "last save" glow, not a bright bar
		end
	end
end

-- Hide the SaveHighlight overlay (the last-saved pipe glow). Called on the re-serve / reset path so the
-- highlight only shows the last save of the CURRENT rally and doesn't linger into the next one. Visual only.
function MatchService.clearSaveHighlight()
	local ns = workspace:FindFirstChild("NineSquare")
	local hi = ns and ns:FindFirstChild("SaveHighlight")
	if not hi then return end
	for _, seg in ipairs({ "N", "S", "E", "W" }) do
		local b = hi:FindFirstChild("Seg_" .. seg)
		if b and b:IsA("BasePart") then b.Transparency = 1 end
	end
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
