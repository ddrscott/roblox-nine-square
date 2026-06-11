--!strict
-- ServerScriptService.NineSquare.MatchService
-- M1 stub: builds the arena + gym and answers "which outer square is a player under?".
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local MatchService = {}

-- BUILD-ONCE / SELF-HEAL. buildArena no longer wipes + rebuilds NineSquare every Play -- the saved place is
-- the source of truth for how the court LOOKS, so manual Studio tweaks (color/size/material/position -- e.g.
-- Scott's solid-white GridLines) PERSIST. We only (re)build a sub-group when it's MISSING (a fresh/empty
-- place, or a deleted folder self-heals). `G.origin` IS still set every Play (runtime positioning reads it).
-- Each critical sub-group (Floors / FloorNumbers / Frame / FrameLegs / GridLines / SaveHighlight) is gated
-- by `ensureGroup`: if a folder by that name already exists under NineSquare we leave its children ALONE.
-- Housekeeping (drop Baseplate, disable stray spawns, ensure CourtSpawn) stays idempotent + non-clobbering.
local function ensureGroup(root: Instance, name: string, build: (Folder) -> ()): Folder
	local existing = root:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end  -- present -> preserve hand-tweaks
	local f = Instance.new("Folder"); f.Name = name; f.Parent = root
	build(f)
	return f
end

function MatchService.buildArena(origin: Vector3)
	-- ALWAYS set runtime state (cellCenter / cellAtPosition / ball + bot + player positioning read G.origin
	-- at runtime), even when nothing is rebuilt. Origin is the stable hardcoded (0,0,200) so persisted
	-- geometry always lines up with runtime positioning.
	G.origin = origin
	-- Get-or-create the root folder; NEVER destroy an existing one (that's what reverted tweaks before).
	local existingRoot = workspace:FindFirstChild("NineSquare")
	local root: Folder
	if existingRoot and existingRoot:IsA("Folder") then
		root = existingRoot
	else
		root = Instance.new("Folder"); root.Name = "NineSquare"; root.Parent = workspace
	end
	-- Per-cell markers: invisible, non-colliding, thin. The gym's WoodPlanks floor is the ONE visible
	-- floor; these only exist as the landing-highlight adornee + fault-flash target (BallController
	-- toggles them briefly visible). Sat just above the wood so a flash never z-fights the floor.
	ensureGroup(root, "Floors", function(floors)
	for name in pairs(G.cells) do
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CastShadow = false
		p.Size = Vector3.new(G.squareSize - 0.5, 0.1, G.squareSize - 0.5)
		p.Position = G.cellCenter(name) + Vector3.new(0, 0.06, 0)
		p.Transparency = 1; p.Color = Color3.fromRGB(205, 45, 45)  -- only seen during a fault flash
		p.Material = Enum.Material.SmoothPlastic; p.Name = "Floor_" .. name; p.Parent = floors
	end
	end)
	-- Floor RANK NUMBERS (replaces the M5.6 over-grid nameplates): a large painted-court number centred on
	-- each panel, facing UP, via a SurfaceGui on the panel's Top face. STATIC per cell (= rankForCell(cell)):
	-- centre C reads "1" (the King throne), then 2..9 outward. Built on a DEDICATED thin part per cell (NOT
	-- the Floor_ marker, which flashes red on a fault) -- CanCollide=false, CastShadow=false, OUTSIDE the
	-- ball/player collision sets. The part itself is invisible; only the SurfaceGui number renders.
	ensureGroup(root, "FloorNumbers", function(numbers)
	for name in pairs(G.cells) do
		local rank = G.rankForCell(name)
		if rank then
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
			p.Size = Vector3.new(G.squareSize - 0.5, 0.1, G.squareSize - 0.5)
			-- UPRIGHT from the default court camera (eye on +Z looking toward -Z): a Top-face SurfaceGui on an
			-- UNROTATED part renders its text with the digit's TOP toward world +Z. 270 deg about Y (a 180
			-- to face the far edge, then +90 CCW per Scott's eye) lands the digit upright on screen -- a clean
			-- in-plane spin, NOT a mirror (the SurfaceGui never mirrors). Verified against the court camera.
			p.CFrame = CFrame.new(G.cellCenter(name) + Vector3.new(0, G.floorNumberYOffset, 0))
				* CFrame.Angles(0, math.rad(270), 0)
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
	end)

	-- Frame: the overhead boundary beams. The ball COLLIDES against every BasePart under NineSquare.Frame
	-- (BallController:_surfaces), so this group is functional, not just cosmetic -- it self-heals if deleted.
	local span = 3 * G.squareSize
	ensureGroup(root, "Frame", function(frame)
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
	end)

	-- Cosmetic corner support posts so the overhead frame "stands on" the court instead of hovering.
	-- KEPT OUT of the Frame folder + CanCollide=false on purpose: BallController:_surfaces() collides the
	-- ball against every BasePart under NineSquare.Frame, so these legs must NOT live there (ball feel
	-- stays unchanged). Positions/size derive from GridConfig so they track tunable changes.
	local legOuter = 1.5 * G.squareSize  -- frame's outer corner offset on X and Z
	ensureGroup(root, "FrameLegs", function(legs)
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
	end)

	-- Painted grid lines on the floor: a renderer-independent "shadow" of the frame, so the grid
	-- reads on the floor in Play mode too (dynamic shadows often don't draw in Studio Play / low quality).
	-- Tuned to read as a soft SHADOW of the overhead frame, not bold paint: a slightly warm dark-grey
	-- on the warm tan WoodPlanks, held mostly-transparent + narrow so it's just a hint of the grid. With
	-- build-once these are now freely recolorable in Studio (Scott set them solid white) and the tweak STAYS.
	local lineW = 0.5
	ensureGroup(root, "GridLines", function(lines)
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
	end)

	-- SaveHighlight overlay: the overhead Frame beams are CONTINUOUS lines (not per-cell), so to light up
	-- only the LAST-SAVED square's pipes we keep a SEPARATE 4-segment neon outline that we reposition over
	-- the saved cell's border at frameHeight. Built hidden (Transparency=1); highlightSavedCell shows it.
	-- KEPT OUT of NineSquare.Frame + CanCollide=false on purpose: BallController:_surfaces() collides the
	-- ball against every BasePart under NineSquare.Frame, so this overlay must NOT live there (ball feel
	-- stays unchanged). 4 segments named N/S (E-W edges) and E/W (N-S edges) so highlightSavedCell can move them.
	ensureGroup(root, "SaveHighlight", function(hi)
	for _, seg in ipairs({ "N", "S", "E", "W" }) do
		local b = Instance.new("Part")
		b.Anchored = true; b.CanCollide = false; b.CastShadow = false
		b.Color = G.saveHighlightColor; b.Material = Enum.Material.Neon
		b.Transparency = 1                                   -- hidden until a save lights it
		b.Name = "Seg_" .. seg; b.Parent = hi
	end
	end)

	-- The default Baseplate's top sits at y=0, coplanar with the gym floor -> z-fighting + a gray
	-- 2048-stud plane poking past the court. Drop it far below (out of view); the enclosed gym is
	-- the real floor. Done here (buildArena runs every Play) so it self-heals on a fresh place.
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Position = Vector3.new(baseplate.Position.X, -100, baseplate.Position.Z)
	end

	-- Spawn pad at the center square, and disable any far/legacy spawns so players start in the court.
	-- Idempotent + non-clobbering: we disable every OTHER spawn each Play (housekeeping that doesn't fight
	-- tweaks), then self-heal the CourtSpawn only if it's missing -- so we never stack duplicate spawns and a
	-- hand-moved/recolored CourtSpawn survives (we only re-assert Enabled, never rebuild it when present).
	local existingSpawn = root:FindFirstChild("CourtSpawn")
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d ~= existingSpawn then d.Enabled = false end
	end
	local spawn: SpawnLocation
	if existingSpawn and existingSpawn:IsA("SpawnLocation") then
		spawn = existingSpawn
	else
		-- invisible, non-colliding spawn marker: you spawn at center and land on the center floor,
		-- with no visible platform and nothing to occlude the ball's floor shadow.
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "CourtSpawn"; spawn.Anchored = true; spawn.Neutral = true
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Position = G.cellCenter("C") + Vector3.new(0, 0.5, 0)
		spawn.Transparency = 1; spawn.CanCollide = false
		spawn.Parent = root
	end
	spawn.Enabled = true
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
	-- LOCK THE SHELL (build-once): the big enclosing parts (ceiling panels + walls) are set Locked=true at
	-- creation so they're CLICK-THROUGH in the Studio viewport -- you select the small interior objects behind
	-- them normally and pick the shell deliberately via the Explorer. Purely an editor convenience: Locked has
	-- NO runtime effect (collision/queries/physics are untouched), and the interior parts stay unlocked.
	-- A one-time MCP pass (see the task) also stamps Locked on the ALREADY-built/persisted shell in the saved
	-- place, since the world is build-once and this function won't re-run there.
	do
		local op = G.galleryOpening
		local cs = W + 8                                  -- full ceiling span (matches the old solid slab)
		local side = (cs - op) / 2                        -- width of each N/S panel band
		local Hy = H
		-- N / S panels run full width on X, fill the band beyond the opening on Z
		block("CeilingN", Vector3.new(cs, 1, side), origin + Vector3.new(0, Hy, -(op + side) / 2), ceil, Enum.Material.SmoothPlastic).Locked = true
		block("CeilingS", Vector3.new(cs, 1, side), origin + Vector3.new(0, Hy,  (op + side) / 2), ceil, Enum.Material.SmoothPlastic).Locked = true
		-- E / W panels fill the band beyond the opening on X, only as deep as the opening (corners covered by N/S)
		block("CeilingE", Vector3.new(side, 1, op), origin + Vector3.new( (op + side) / 2, Hy, 0), ceil, Enum.Material.SmoothPlastic).Locked = true
		block("CeilingW", Vector3.new(side, 1, op), origin + Vector3.new(-(op + side) / 2, Hy, 0), ceil, Enum.Material.SmoothPlastic).Locked = true
	end
	-- N/S end walls: plain solid slabs (no windows on these).
	block("WallN", Vector3.new(W, H, 0.8), origin + Vector3.new(0, wy, -hz), wall, Enum.Material.SmoothPlastic).Locked = true
	block("WallS", Vector3.new(W, H, 0.8), origin + Vector3.new(0, wy, hz), wall, Enum.Material.SmoothPlastic).Locked = true
	-- E/W SIDE WALLS with REAL window cut-outs: each is a FRAME of solid panels around a genuine gap (bottom +
	-- top + two Z-end panels), with a light-passing Glass pane INSIDE the gap -- no opaque part behind it, so
	-- outdoor light/sky reaches the interior. Panels carry the WallE/WallW name PREFIX so the camera wall-fade
	-- (prefix match) still fades the whole windowed wall when the eye clips it.
	MatchService.buildWindowedWall(gym, origin, "WallE", hx, wy, L, H, wall)
	MatchService.buildWindowedWall(gym, origin, "WallW", -hx, wy, L, H, wall)
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

	-- ---- OUTDOOR ENVIRONMENT (clear-day backdrop seen out the windows / through a faded wall) -------
	-- A grassy ground plane + gentle hills + scattered trees AROUND + BELOW the gym, so the side windows
	-- and the camera wall-fade reveal a park instead of void. Purely visual: every outdoor part is
	-- CanCollide=false + CanQuery=false and lives in its OWN Workspace.Outdoors folder (NOT under
	-- NineSquare.Frame), so it never enters the ball or player collision sets. Built once, alongside the gym.
	MatchService.buildOutdoors(origin)

	return gym
end

-- Build ONE side wall (E or W) with a REAL window cut-out. `prefix` is "WallE"/"WallW"; `xoff` is the wall's
-- X position (+/-W/2); `wy` is its vertical centre (H/2); `L`/`H` are the interior length/height; `color` is
-- the wall colour. The wall is a FRAME of solid panels (bottom + top + two Z-end panels) around a genuine
-- rectangular GAP centred at G.windowCenterY, G.windowHeight tall, G.windowLength long along Z -- with NO
-- opaque part behind the gap. A light-passing Glass pane is set inside the gap. Every panel + the glass is
-- named with the `prefix` (e.g. "WallE_Bottom", "WallE_Glass") so the camera wall-fade (prefix match) fades
-- the whole windowed wall when the eye clips it. Frame panels are Locked (click-through, like the shell);
-- the glass pane is left UNLOCKED so it's easy to tweak. The wall is purely a gym shell part: CanCollide
-- stays true (enclosure) but it lives OUTSIDE NineSquare.Frame, so the ball/player court collision is untouched.
function MatchService.buildWindowedWall(gym: Instance, origin: Vector3, prefix: string, xoff: number, wy: number, L: number, H: number, color: Color3)
	local th = 0.8                          -- wall thickness (matches the old solid side walls)
	local cy = G.windowCenterY              -- window opening centre Y
	local wh = G.windowHeight               -- window opening height
	local wl = G.windowLength               -- window opening length along Z
	local halfL, halfWl, halfWh = L / 2, wl / 2, wh / 2
	local winBot, winTop = cy - halfWh, cy + halfWh   -- opening bottom/top in Y
	local function panel(name: string, sizeYZ: Vector2, posYZ: Vector2)
		local p = Instance.new("Part"); p.Anchored = true; p.Name = prefix .. name
		p.Size = Vector3.new(th, sizeYZ.X, sizeYZ.Y)
		p.Position = origin + Vector3.new(xoff, posYZ.X, posYZ.Y)
		p.Color = color; p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Locked = true                     -- click-through in Studio, like the rest of the shell
		p.Parent = gym
		return p
	end
	-- BOTTOM panel: floor (y=0) up to the opening bottom; full length on Z.
	local botH = winBot
	panel("_Bottom", Vector2.new(botH, L), Vector2.new(botH / 2, 0))
	-- TOP panel: opening top up to the ceiling (y=H); full length on Z.
	local topH = H - winTop
	panel("_Top", Vector2.new(topH, L), Vector2.new(winTop + topH / 2, 0))
	-- Two Z-END panels: fill the corners beyond the opening along Z, only across the opening's Y band.
	local endLen = halfL - halfWl           -- length of each end panel along Z
	if endLen > 0 then
		panel("_EndN", Vector2.new(wh, endLen), Vector2.new(cy, -(halfWl + endLen / 2)))
		panel("_EndS", Vector2.new(wh, endLen), Vector2.new(cy,  (halfWl + endLen / 2)))
	end
	-- GLASS pane filling the gap: light-passing (transparency), CastShadow off so it doesn't darken the
	-- interior. Left UNLOCKED so it's easy to tweak. Named with the prefix so the wall-fade fades it too.
	local glass = Instance.new("Part"); glass.Anchored = true; glass.Name = prefix .. "_Glass"
	glass.Size = Vector3.new(0.3, wh, wl)
	glass.Position = origin + Vector3.new(xoff, cy, 0)
	glass.Color = G.windowGlassColor; glass.Material = Enum.Material.Glass
	glass.Transparency = G.windowGlassTransparency; glass.CastShadow = false
	glass.TopSurface = Enum.SurfaceType.Smooth; glass.BottomSurface = Enum.SurfaceType.Smooth
	glass.Parent = gym
	-- BALL-BARRIER across the gap (CONTAIN the ball). The glass is light-passing + EXCLUDED from the ball's
	-- surface collision and the frame panels only ring the opening, so a hard hit toward the window used to
	-- fly straight through into the outdoors (escape -> rally hang). This invisible slab fills the opening (+
	-- margin) so the ball bounces off the FULL wall extent: it is SmoothPlastic (so BallController._surfaces
	-- INCLUDES it -- only Glass/Neon + "Floor" are skipped) and named with the prefix (joins the wall-fade
	-- set). Transparency=1 + CastShadow=false keeps the window visually OPEN (light + view still pass);
	-- CanCollide=FALSE keeps it OUT of the PLAYER collision -- the ball collides anyway because _collide is a
	-- pure sphere-vs-box test that ignores CanCollide. Sized a hair larger than the gap (windowBarrierMargin)
	-- so there is no leak seam at the opening edges.
	local bMargin = G.windowBarrierMargin
	local barrier = Instance.new("Part"); barrier.Anchored = true; barrier.Name = prefix .. "_Barrier"
	barrier.Size = Vector3.new(G.windowBarrierThickness, wh + bMargin, wl + bMargin)
	barrier.Position = origin + Vector3.new(xoff, cy, 0)
	barrier.Material = Enum.Material.SmoothPlastic
	barrier.Transparency = 1; barrier.CastShadow = false
	barrier.CanCollide = false; barrier.CanQuery = false; barrier.CanTouch = false
	barrier.Locked = true
	barrier.Parent = gym
	-- PLAYER-BARRIER across the gap (SEAL the window to the CHARACTER). The ball-barrier above is
	-- CanCollide=false (ball-only), so the open window is PASSABLE to a player -- a dash(40)+flip can carry a
	-- court player up and OUT through it. This invisible slab fills the opening (+ a generous margin so a flip
	-- can't clear it over the top or slip past a Z end) and BLOCKS THE CHARACTER (CanCollide=TRUE) while staying
	-- OUT of the ball/court collision: it is NEON material, so BallController._surfaces SKIPS it (the ball never
	-- collides with it -> ball feel UNCHANGED), and it is named WindowGuard* with NO WallE/WallW prefix so the
	-- camera wall-fade never touches it (it stays invisible across the open window even when the eye is inside).
	-- Transparency=1 + CastShadow=false keeps the window visually OPEN (light + the view still pass through).
	local side = (prefix == "WallE") and "E" or "W"
	local pMargin = G.windowPlayerBarrierMargin
	local guard = Instance.new("Part"); guard.Anchored = true; guard.Name = "WindowGuard" .. side
	guard.Size = Vector3.new(G.windowPlayerBarrierThickness, wh + pMargin, wl + pMargin)
	guard.Position = origin + Vector3.new(xoff, cy, 0)
	guard.Material = Enum.Material.Neon                 -- Neon -> excluded from BallController._surfaces (ball never hits it)
	guard.Transparency = 1; guard.CastShadow = false    -- invisible: the window stays visually open
	guard.CanCollide = true                             -- but SOLID to the player character (seals the gap)
	guard.CanQuery = false                              -- don't intercept raycasts/queries (court below, wall-fade, etc.)
	guard.CanTouch = false
	guard.Locked = true
	guard.Parent = gym
	return gym
end

-- Build the grassy outdoor backdrop (ground + hills + trees) around/below the gym. Build-once. Everything is
-- non-colliding, non-queryable, OUTSIDE NineSquare.Frame, and the ground sits just BELOW the gym floor so it
-- never intrudes on the court/play surface. Scatter is DETERMINISTIC (fixed GridConfig.outdoorScatterSeed).
function MatchService.buildOutdoors(origin: Vector3)
	if workspace:FindFirstChild("Outdoors") then return workspace.Outdoors end  -- build once
	local out = Instance.new("Folder"); out.Name = "Outdoors"; out.Parent = workspace

	-- Visual-only part helper: anchored, NON-colliding, NON-queryable, no shadow cast (perf), under Outdoors.
	local function vpart(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part"); p.Anchored = true; p.Name = name
		p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Size = size; p.Position = pos; p.Color = color; p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = out
		return p
	end

	-- Flat grass ground plane: a big square slab whose TOP sits just below the gym floor (y=0). The gym's
	-- opaque wood floor covers the court footprint, so the grass is only ever seen OUTSIDE the gym.
	local ext = G.outdoorGroundExtent
	local gth = G.outdoorGroundThickness
	local groundTop = -G.outdoorGroundDrop
	vpart("Ground", Vector3.new(ext * 2, gth, ext * 2), origin + Vector3.new(0, groundTop - gth / 2, 0), G.outdoorGroundColor, Enum.Material.Grass)

	-- Gentle low hills: flattened spheres scattered on a ring well clear of the gym. Deterministic scatter
	-- (fixed seed) so the scene is stable across builds and Scott can predict tweaks.
	local rng = Random.new(G.outdoorScatterSeed)
	local hills = Instance.new("Folder"); hills.Name = "Hills"; hills.Parent = out
	for i = 1, G.outdoorHillCount do
		local ang = rng:NextNumber(0, 2 * math.pi)
		local dist = rng:NextNumber(G.outdoorHillRingMin, G.outdoorHillRingMax)
		local r = rng:NextNumber(G.outdoorHillRadiusMin, G.outdoorHillRadiusMax)
		local hpos = origin + Vector3.new(math.cos(ang) * dist, groundTop, math.sin(ang) * dist)
		-- a flattened sphere reading as a rolling rise; centre dropped so only the top dome shows above ground
		local hsphere = Instance.new("Part"); hsphere.Shape = Enum.PartType.Ball
		hsphere.Anchored = true; hsphere.CanCollide = false; hsphere.CanQuery = false; hsphere.CanTouch = false
		hsphere.CastShadow = false; hsphere.Name = "Hill_" .. i
		hsphere.Size = Vector3.new(r * 2, r * 2 * G.outdoorHillFlatten, r * 2)
		hsphere.Position = hpos + Vector3.new(0, -r * G.outdoorHillFlatten * 0.4, 0)
		hsphere.Color = G.outdoorHillColor; hsphere.Material = Enum.Material.Grass
		hsphere.Parent = hills
	end

	-- Scattered trees on a ring around the gym. Clone a creator-store tree TEMPLATE from ReplicatedStorage
	-- if present (OutdoorTreeTemplate); else build a simple code tree (trunk + foliage). Non-colliding decor.
	local treeTemplate = RS:FindFirstChild(G.outdoorTreeTemplateName)
	local trees = Instance.new("Folder"); trees.Name = "Trees"; trees.Parent = out
	local function stripCollision(inst: Instance)
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			end
		end
		if inst:IsA("BasePart") then
			inst.Anchored = true; inst.CanCollide = false; inst.CanQuery = false; inst.CanTouch = false; inst.CastShadow = false
		end
	end
	for i = 1, G.outdoorTreeCount do
		local ang = rng:NextNumber(0, 2 * math.pi)
		local dist = rng:NextNumber(G.outdoorTreeRingMin, G.outdoorTreeRingMax)
		local scale = rng:NextNumber(G.outdoorTreeScaleMin, G.outdoorTreeScaleMax)
		local yaw = rng:NextNumber(0, 2 * math.pi)
		local base = origin + Vector3.new(math.cos(ang) * dist, groundTop, math.sin(ang) * dist)
		if treeTemplate and (treeTemplate:IsA("Model") or treeTemplate:IsA("BasePart")) then
			local t = treeTemplate:Clone(); t.Name = "Tree_" .. i
			stripCollision(t)
			if t:IsA("Model") then
				if t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart") then
					-- normalize: drop the model's FEET (its bbox bottom) onto the ground, then yaw + scale.
					local cf, sz = t:GetBoundingBox()
					local footLift = sz.Y / 2  -- distance pivot is above the bbox bottom (assumes centred pivot)
					t:ScaleTo(scale)
					t:PivotTo(CFrame.new(base + Vector3.new(0, footLift * scale, 0)) * CFrame.Angles(0, yaw, 0))
				end
				t.Parent = trees
			elseif t:IsA("BasePart") then
				t.Size = t.Size * scale
				t.CFrame = CFrame.new(base + Vector3.new(0, t.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
				t.Parent = trees
			end
		else
			-- code tree: a brown trunk + two green foliage balls. Modest part count for perf.
			local trunkH = 10 * scale
			local model = Instance.new("Model"); model.Name = "Tree_" .. i; model.Parent = trees
			local trunk = Instance.new("Part"); trunk.Shape = Enum.PartType.Cylinder
			trunk.Anchored = true; trunk.CanCollide = false; trunk.CanQuery = false; trunk.CanTouch = false; trunk.CastShadow = false
			trunk.Size = Vector3.new(trunkH, 2.2 * scale, 2.2 * scale)
			-- cylinder's length runs along its local X; rotate so it stands upright
			trunk.CFrame = CFrame.new(base + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			trunk.Color = Color3.fromRGB(110, 78, 50); trunk.Material = Enum.Material.Wood
			trunk.Name = "Trunk"; trunk.Parent = model
			local foliageColor = Color3.fromRGB(64, 132, 64)
			for j, off in ipairs({ Vector3.new(0, trunkH + 4 * scale, 0), Vector3.new(2 * scale, trunkH + 1 * scale, 1 * scale) }) do
				local fol = Instance.new("Part"); fol.Shape = Enum.PartType.Ball
				fol.Anchored = true; fol.CanCollide = false; fol.CanQuery = false; fol.CanTouch = false; fol.CastShadow = false
				fol.Size = Vector3.new(12 * scale - j * 2 * scale, 12 * scale - j * 2 * scale, 12 * scale - j * 2 * scale)
				fol.Position = base + off
				fol.Color = foliageColor; fol.Material = Enum.Material.Grass
				fol.Name = "Foliage" .. j; fol.Parent = model
			end
			model.PrimaryPart = trunk
		end
	end

	return out
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

	-- Perimeter FALL-OUT walls + roof so a roaming spectator can't walk off the foyer / fall out, and the
	-- gallery reads as an enclosed upper room (not a floating slab). FALL-OUT AUDIT (verified by walking the
	-- edges/corners in Play): the floor RING tiles fully around the opening (the N/S bands run the full span on
	-- X, so the opening corners are floored), the OpeningBarrier caps the central hole flush with the floor, and
	-- these four perimeter walls run the FULL outer span (X=+/-cs/2, Z=+/-cs/2) at galleryWallHeight tall --
	-- well above a default ~7-stud spectator jump -- meeting the floor (wall bottom = floorTop) with no gap, and
	-- the roof closes the top. Net: the foyer is fully enclosed; a spectator stays contained everywhere. These
	-- live in the Gallery folder (OUTSIDE NineSquare.Frame), so they're NOT in the ball/player COURT collision
	-- set (the gallery sits above the court) -- they only block PLAYERS up here.
	local wh = G.galleryWallHeight
	local wmid = floorTop + wh / 2
	-- LOCK THE GALLERY SHELL (build-once): the perimeter walls + roof are click-through in Studio (Locked),
	-- like the gym shell, so they don't intercept clicks on interior gallery objects. Editor-only; no runtime
	-- effect. The walkable floor ring + railing + barrier stay UNLOCKED-or-as-needed below.
	gpart("GalWallE", Vector3.new(0.8, wh, cs), origin + Vector3.new(cs / 2, wmid, 0), wallG, Enum.Material.SmoothPlastic, true).Locked = true
	gpart("GalWallW", Vector3.new(0.8, wh, cs), origin + Vector3.new(-cs / 2, wmid, 0), wallG, Enum.Material.SmoothPlastic, true).Locked = true
	gpart("GalWallN", Vector3.new(cs, wh, 0.8), origin + Vector3.new(0, wmid, -cs / 2), wallG, Enum.Material.SmoothPlastic, true).Locked = true
	gpart("GalWallS", Vector3.new(cs, wh, 0.8), origin + Vector3.new(0, wmid, cs / 2), wallG, Enum.Material.SmoothPlastic, true).Locked = true
	gpart("GalRoof", Vector3.new(cs + 2, 1, cs + 2), origin + Vector3.new(0, floorTop + wh, 0), roofG, Enum.Material.SmoothPlastic, true).Locked = true

	-- INVISIBLE OPENING BARRIER (decided): a transparent (Transparency=1), collidable, anchored cap across the
	-- gallery floor opening at galleryFloorY. It blocks LOBBY WATCHERS from falling through the opening into the
	-- play area while preserving the downward sightline to the court (invisible). Teleporting a SEATED player
	-- DOWN to their cell is a CFrame set that bypasses collision, so they're unaffected. CanQuery=false so it
	-- doesn't intercept anything that raycasts/queries the court below; CastShadow=false so it casts no shadow.
	-- It lives in the Gallery folder (OUTSIDE NineSquare.Frame), so BallController._surfaces never collects it
	-- and the ball never perturbs it -- and the ball is already volume-clamped below gallery height anyway, so
	-- the barrier's real job is purely blocking PLAYERS. Sized to cover the full opening with a hair of overlap.
	local barrier = gpart("OpeningBarrier", Vector3.new(op + 1, 1, op + 1), origin + Vector3.new(0, floorTop - fth / 2, 0), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, true)
	barrier.Transparency = 1
	barrier.CanQuery = false

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
			-- The bench is DECOR only: disable its seats so a roaming spectator never auto-sits on spawn (which
			-- left them stuck unable to walk). Spectators roam the foyer freely.
			for _, d in ipairs(b:GetDescendants()) do
				if d:IsA("Seat") or d:IsA("VehicleSeat") then d.Disabled = true end
			end
			b:PivotTo(CFrame.new(origin + Vector3.new(bx * 16, floorTop + lift, benchZ)) * CFrame.Angles(0, math.pi, 0))
			b.Parent = gallery
		else
			-- code fallback bench (used if the creator-store template wasn't inserted into ReplicatedStorage)
			local bpos = origin + Vector3.new(bx * 16, floorTop + 1.5, benchZ)
			gpart("GalBench", Vector3.new(10, 1, 2.4), bpos, Color3.fromRGB(150, 110, 70), Enum.Material.Wood, false)
			gpart("GalBenchBack", Vector3.new(10, 3, 0.5), bpos + Vector3.new(0, 1.7, -1.0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood, false)
		end
	end

	-- Spectator spawn IN the gallery: a SpawnLocation on the NORTH floor band (bench-free -- the bench is on the
	-- SOUTH band -- and clear of the opening) so M5.2 spectators appear up here and can walk + watch ACROSS the
	-- opening. Kept consistent with GridConfig.specSpawnOffset (Z=-28) so the trailing Custom camera sits north
	-- over open floor, not on the bench. Neutral + non-team so it doesn't override the court spawn for seated
	-- players (the server teleports seated humans to their cell anyway; spectators are parked here by
	-- parkSpectator using the matching GridConfig.specSpawnOffset).
	local sspawn = Instance.new("SpawnLocation")
	sspawn.Name = "GallerySpawn"; sspawn.Anchored = true; sspawn.Neutral = true; sspawn.Enabled = false
	sspawn.Size = Vector3.new(8, 1, 6)
	sspawn.Position = origin + Vector3.new(0, floorTop + 0.5, G.specSpawnOffset.Z)
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
