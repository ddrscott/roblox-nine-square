--!strict
-- ReplicatedStorage.GridConfig
-- Tunable dimensions + pure grid/contact math for 9 Square M1. No side effects.
local GridConfig = {}

-- Dimensions (studs / seconds). All tunable; values are greybox starting points.
GridConfig.squareSize = 14          -- one square edge
GridConfig.floorThickness = 1
GridConfig.frameHeight = 11         -- contact plane = measured jump reach (apex ~11.2; std-jump 7.2 + hit-zone ~4)
GridConfig.beamThickness = 0.5
GridConfig.ballRadius = 2           -- ball sphere radius (4-stud diameter)
GridConfig.apexHeight = 16          -- (legacy) extra bulge for the old lerp-arc serve
GridConfig.serveTravel = 1.1        -- (legacy)
GridConfig.descentWindow = 0.8      -- (legacy)
GridConfig.hitZoneRadius = 1.6      -- avatar hit-zone sphere radius (upper-body sized; volley with head/shoulders/hands)
GridConfig.showHitSphere = true     -- debug: render the local player's contact sphere (HitSphereView client) so you can see it
GridConfig.hitZoneYOffset = 2.9     -- hit-zone center above HumanoidRootPart (raised to head/upper torso)
                                    --   reach at std-jump apex = HRP_Y + yOffset + radius + ballRadius
                                    --   = 7.2 + 2.9 + 1.6 + 2 = 13.7 >= frameHeight(11): frame plane stays hittable
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
GridConfig.hitCooldown = 0.30       -- min seconds between contacts (debounce one jump)
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
GridConfig.dashSpeed = 20           -- horizontal burst speed applied to the character during a dash (studs/s); ~1/4 of the original 80 for a short hop
GridConfig.dashDuration = 0.18      -- how long the dash burst is held before control returns (s)
GridConfig.flipUpVelocity = 75      -- upward velocity set on the double-jump flip (studs/s) -> reach higher + spike
GridConfig.flipForwardBoost = 26    -- horizontal velocity added in the facing direction on the flip (studs/s)
GridConfig.flipSpinTime = 0.45      -- duration of the cosmetic forward-flip rotation (s)
GridConfig.staminaMax = 100         -- energy pool ceiling
GridConfig.staminaRegen = 28        -- energy regained per second while not spending
GridConfig.dashCost = 30            -- energy spent per dash (must have >= this to dash)
GridConfig.flipCost = 35            -- energy spent per double-jump flip (must have >= this to flip)

-- Court center on the floor; set at runtime by the server.
GridConfig.origin = Vector3.new(0, 0, 0)

-- Cell -> (dx, dz) in {-1,0,1}. +X = East, +Z = South (Roblox conventions).
GridConfig.cells = {
	NW = { dx = -1, dz = -1 }, N = { dx = 0, dz = -1 }, NE = { dx = 1, dz = -1 },
	W  = { dx = -1, dz =  0 }, C = { dx = 0, dz =  0 }, E  = { dx = 1, dz =  0 },
	SW = { dx = -1, dz =  1 }, S = { dx = 0, dz =  1 }, SE = { dx = 1, dz =  1 },
}
GridConfig.outerCells = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

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
