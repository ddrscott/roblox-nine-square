--!strict
-- ReplicatedStorage.GridConfig
-- Tunable dimensions + pure grid/contact math for 9 Square M1. No side effects.
local GridConfig = {}

-- Dimensions (studs / seconds). All tunable; values are greybox starting points.
GridConfig.squareSize = 14          -- one square edge
GridConfig.floorThickness = 1
GridConfig.frameHeight = 11         -- contact plane = measured jump reach (apex ~11.2; std-jump 7.2 + hit-zone ~4)
GridConfig.beamThickness = 0.5
GridConfig.legThickness = 1.0       -- cosmetic corner support posts (floor->frame); a touch thicker than beamThickness
GridConfig.ballRadius = 2           -- ball sphere radius (4-stud diameter)
GridConfig.apexHeight = 16          -- (legacy) extra bulge for the old lerp-arc serve
GridConfig.serveTravel = 1.1        -- (legacy)
GridConfig.descentWindow = 0.8      -- (legacy)
GridConfig.hitZoneRadius = 1.6      -- contact sphere radius (covers the head; you volley with your head)
GridConfig.showHitSphere = true     -- debug: render the local player's contact sphere (HitSphereView client) so you can see it
GridConfig.hitZoneYOffset = 0       -- contact sphere offset above the Head part (0 = centred on the head)
                                    --   reach at std-jump apex ~= Head_Y + yOffset + radius + ballRadius
                                    --   ~= (7.2 + ~1.5) + 0 + 1.6 + 2 ~= 12.3 >= frameHeight(11): still hittable
GridConfig.ballRestitution = 0.6    -- PASSIVE bounce: how much of the ball's own incoming speed it keeps
                                    --   off a still player. <= 1 so a motionless player NEVER adds energy
                                    --   (the ball rebounds slower than it arrived, like any surface).
GridConfig.hitGain = 2.5            -- ACTIVE power: outgoing speed added along the normal per stud/s of the
                                    --   player's approach speed toward the ball -> faster hit = harder strike.
GridConfig.strikeMoveThreshold = 8  -- min approach speed (studs/s) to count as an intentional strike; only
                                    --   above this does hitMinPop apply (a still/glancing contact just bounces).
GridConfig.hitMinPop = 55           -- floor on the outgoing speed of an ACTIVE strike so a clean drive stays in play
GridConfig.hitSpeedH = 22           -- (legacy) fixed horizontal launch speed; superseded by the velocity-proportional strike
GridConfig.hitSpeedV = 72           -- (legacy) fixed vertical launch speed; superseded by the velocity-proportional strike
GridConfig.hitCooldown = 0.30       -- (legacy) old proximity-trigger debounce; the moving-sphere collision now
                                    --   repositions the ball out of the hit-sphere, so one approach = one hit (no timer)
GridConfig.minLift = 0.30           -- floor on the contact normal's vertical part (biases a clean bump upward)
GridConfig.floorRestitution = 0.55  -- ground bounciness: fraction of vertical speed kept per floor bounce
GridConfig.floorFriction = 0.72     -- horizontal speed kept per floor bounce (so it rolls to a stop)
GridConfig.restSpeedV = 8           -- settle once a floor bounce would rise slower than this (studs/s)
GridConfig.restSpeedH = 4           -- ...and horizontal speed is below this
GridConfig.steerConeDeg = 15        -- (legacy)
GridConfig.lobTravel = 1.0          -- (legacy)
GridConfig.lobDistance = 14         -- (legacy)

-- Movement skill moves (client-side; M1 reads replicated HRP velocity, so these velocities feed the
-- velocity-proportional strike directly -- no strike-formula change). All tunable.
GridConfig.doubleTapWindow = 0.25   -- max seconds between two taps to count as a double-tap (dash & flip)
GridConfig.dashSpeed = 40           -- horizontal burst speed applied to the character during a dash (studs/s); 2x distance over dashDuration for a longer hop
GridConfig.dashDuration = 0.18      -- how long the dash burst is held before control returns (s)
GridConfig.flipUpVelocity = 38      -- upward velocity set on the double-jump flip (studs/s); halved from 75 for a lower flip arc
GridConfig.flipForwardBoost = 26    -- horizontal velocity added in the facing direction on the flip (studs/s)
GridConfig.flipSpinTime = 0.45      -- duration of the cosmetic forward-flip rotation (s)
GridConfig.staminaMax = 100         -- energy pool ceiling
GridConfig.staminaRegen = 28        -- energy regained per second while not spending
GridConfig.dashCost = 30            -- energy spent per dash (must have >= this to dash)
GridConfig.flipCost = 35            -- energy spent per double-jump flip (must have >= this to flip)

-- Court camera: a fixed high view the player can zoom with the mouse wheel. Zoom lerps between the
-- "out" and "in" offsets below (relative to the court origin); zooming IN also raises the look target
-- so the pitch flattens and you see less floor. zoom 0 = full out (default), 1 = full in.
GridConfig.camZoomStep = 0.12       -- zoom change per mouse-wheel notch
GridConfig.camFarEye = Vector3.new(0, 42, 38)   -- camera offset when zoomed OUT (the default view)
GridConfig.camFarLook = Vector3.new(0, 7, 0)    -- look-at offset when zoomed out (steeper, more floor)
GridConfig.camNearEye = Vector3.new(0, 24, 24)  -- camera offset when zoomed IN (closer + lower)
GridConfig.camNearLook = Vector3.new(0, 15, 0)  -- look-at offset when zoomed in (raised -> pitch up, less floor)
-- Shift toggles FOLLOW mode: the camera centres on the player instead of the court. Tighter, gym-safe
-- offsets (so it doesn't clip the walls when following an edge square), zoom-lerped like the court cam.
GridConfig.camFollowSmooth = 0.15   -- per-frame lerp toward the focus point (higher = snappier follow / toggle)
GridConfig.camFollowFarEye = Vector3.new(0, 26, 22)   -- follow camera offset from the player, zoomed OUT
GridConfig.camFollowFarLook = Vector3.new(0, 8, 0)
GridConfig.camFollowNearEye = Vector3.new(0, 16, 14)  -- follow offset zoomed IN (closer + pitched up)
GridConfig.camFollowNearLook = Vector3.new(0, 10, 0)
-- Camera wall fade (occlusion): the Scriptable cam skips Roblox's built-in auto-transparency, so we fade
-- the gym walls/ceiling ourselves when the camera eye crosses to their outside (would block/clip the view).
-- Whitelisted occluders only (WallE/W/N/S, Ceiling); never the floor, grid, frame, ball, player, or Glass.
GridConfig.camWallFadeTransparency = 1.0   -- target transparency for an obstructing wall/ceiling (fully transparent)
GridConfig.camWallFadeSpeed = 10           -- lerp rate per second toward the target (higher = snappier, no pop)
GridConfig.camWallFadeMargin = 6           -- studs of slack so a wall fades just BEFORE the eye reaches its plane

-- Court center on the floor; set at runtime by the server.
GridConfig.origin = Vector3.new(0, 0, 0)

-- Cell -> (dx, dz) in {-1,0,1}. +X = East, +Z = South (Roblox conventions).
GridConfig.cells = {
	NW = { dx = -1, dz = -1 }, N = { dx = 0, dz = -1 }, NE = { dx = 1, dz = -1 },
	W  = { dx = -1, dz =  0 }, C = { dx = 0, dz =  0 }, E  = { dx = 1, dz =  0 },
	SW = { dx = -1, dz =  1 }, S = { dx = 0, dz =  1 }, SE = { dx = 1, dz =  1 },
}
GridConfig.outerCells = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Rank -> cell (PRD §4.2 / M3 design §3): index = rank (1..9). King = rank 1 = "C", then the
-- clockwise ring outward. The human enters at rank 9 (NW); dummies hold ranks 1..8. Config-driven:
-- change this table and placement follows (cellForRank just indexes it).
GridConfig.rankCells = { "C", "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- Dummy occupant look (M3 placeholders for the 8 non-human squares). Cosmetic + non-colliding so they
-- never touch the ball; clearly-non-player coloured capsules standing in their cell.
GridConfig.dummyHeight = 5          -- cylinder height (studs)
GridConfig.dummyRadius = 1.3        -- cylinder radius (studs)
GridConfig.dummyColor = Color3.fromRGB(120, 90, 210)   -- a clearly-non-player violet
GridConfig.dummyKingColor = Color3.fromRGB(225, 185, 60) -- the King (rank 1 / C) stands out gold

function GridConfig.cellForRank(rank: number): string
	local cell = GridConfig.rankCells[rank]
	assert(cell, "no cell for rank " .. tostring(rank))
	return cell
end

-- Cell -> rank (reverse of cellForRank). Returns the rank whose square is `cell`, or nil if unknown.
-- M3 step 3 needs this to attribute a fault (the ball landed in cell X) to the occupant at that rank.
function GridConfig.rankForCell(cell: string): number?
	for rank, c in ipairs(GridConfig.rankCells) do
		if c == cell then return rank end
	end
	return nil
end

function GridConfig.cellCenter(cell: string): Vector3
	local c = GridConfig.cells[cell]
	assert(c, "unknown cell " .. tostring(cell))
	return GridConfig.origin + Vector3.new(c.dx * GridConfig.squareSize, 0, c.dz * GridConfig.squareSize)
end

function GridConfig.cellFramePoint(cell: string): Vector3
	return GridConfig.cellCenter(cell) + Vector3.new(0, GridConfig.frameHeight, 0)
end

-- Which cell is a world position under? Returns cell name or nil if outside the 3x3 court.
function GridConfig.cellAtPosition(pos: Vector3): string?
	local rel = pos - GridConfig.origin
	local function idx(v: number): number?
		local i = math.floor(v / GridConfig.squareSize + 0.5)
		if i < -1 or i > 1 then return nil end
		return i
	end
	local ix, iz = idx(rel.X), idx(rel.Z)
	if not ix or not iz then return nil end
	for name, c in pairs(GridConfig.cells) do
		if c.dx == ix and c.dz == iz then return name end
	end
	return nil
end

return GridConfig
