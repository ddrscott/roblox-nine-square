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
GridConfig.apexHeight = 16          -- extra bulge above the serve chord midpoint
GridConfig.serveTravel = 1.1        -- seconds, center -> target square arrival
GridConfig.descentWindow = 0.8      -- seconds before arrival that the ring actively shrinks
GridConfig.hitZoneRadius = 2.5      -- avatar hit-zone sphere radius
GridConfig.hitZoneYOffset = 2.0     -- hit-zone center above HumanoidRootPart (hands/head)
GridConfig.contactDwell = 0.25      -- hover/contact window at the target before a whiff
GridConfig.steerConeDeg = 15        -- max horizontal steer nudge
GridConfig.lobTravel = 1.0          -- seconds for a volley lob arc
GridConfig.lobDistance = 14         -- horizontal studs a centered volley travels

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

-- Base horizontal volley direction: ball deflects from contact toward ball center, i.e.
-- (ball - hitZoneCenter) flattened. Off-center contact => deflect that way; centered => zero.
function GridConfig.reflectDir(ballPos: Vector3, hitZoneCenter: Vector3): Vector3
	local d = ballPos - hitZoneCenter
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 1e-3 then return Vector3.zero end
	return flat.Unit
end

-- Rotate baseDir toward steerDir by at most steerConeDeg (about Y). Centered base (zero) snaps to steer.
function GridConfig.applySteer(baseDir: Vector3, steerDir: Vector3?): Vector3
	local s = steerDir and Vector3.new(steerDir.X, 0, steerDir.Z) or Vector3.zero
	if baseDir.Magnitude < 1e-3 then
		return s.Magnitude < 1e-3 and Vector3.zero or s.Unit
	end
	local b = baseDir.Unit
	if s.Magnitude < 1e-3 then return b end
	s = s.Unit
	local ang = math.acos(math.clamp(b:Dot(s), -1, 1))
	local maxAng = math.rad(GridConfig.steerConeDeg)
	if ang <= maxAng then return s end
	-- rotate b toward s by maxAng; sign from the Y of (b x s)
	local crossY = b.Z * s.X - b.X * s.Z
	local theta = (crossY >= 0 and 1 or -1) * maxAng
	local cosT, sinT = math.cos(theta), math.sin(theta)
	return Vector3.new(b.X * cosT + b.Z * sinT, 0, -b.X * sinT + b.Z * cosT).Unit
end

return GridConfig
