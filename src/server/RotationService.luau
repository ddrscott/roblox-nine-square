--!strict
-- ServerScriptService.NineSquare.RotationService
-- M3 step 1 (FOUNDATION ONLY): the 9-rank occupancy model + dummy occupants + placeAll.
-- Holds byRank[rank] = { id, isDummy, rank } for exactly 9 occupants (1 human + 8 dummies), builds the
-- 8 cosmetic dummy parts, and places everyone at cellForRank(rank). NO rotation / serve / fault wiring
-- here yet -- rotateOnFault and the serve branch are later M3 steps.
--
-- The dummies are deliberately cosmetic + CanCollide=false and live in their OWN "Dummies" folder under
-- workspace.NineSquare (NOT under NineSquare.Frame), so BallController:_surfaces() never picks them up and
-- the ball physics is unchanged.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

export type Occupant = {
	id: string,        -- "human" or "dummy1".."dummy8"
	isDummy: boolean,
	rank: number,      -- 1..9 (King = 1)
}

local RotationService = {}
RotationService.__index = RotationService

export type RotationService = typeof(setmetatable(
	{} :: {
		byRank: { [number]: Occupant },
		_dummyParts: { [string]: BasePart },   -- id -> the dummy's part (human has none)
		_placeHuman: (cell: string) -> (),     -- injected: teleport the human's HRP to a cell
		onDethrone: ((newKing: Occupant) -> ())?,  -- optional: fires when the King (rank 1) faults
	},
	RotationService
))

local RANKS = 9

-- Build a fresh M3 occupancy: the human at rank 9 (entry square, PRD §7) and dummies at ranks 1..8
-- (so the King -- rank 1 / C -- starts as a dummy). placeHuman is how we teleport the human to a cell
-- (NineSquareServer injects its placeAtCell so RotationService stays decoupled from character handling).
function RotationService.new(placeHuman: (cell: string) -> ()): RotationService
	local self = setmetatable({
		byRank = {},
		_dummyParts = {},
		_placeHuman = placeHuman,
	}, RotationService)

	for rank = 1, RANKS do
		if rank == RANKS then
			self.byRank[rank] = { id = "human", isDummy = false, rank = rank }
		else
			self.byRank[rank] = { id = "dummy" .. rank, isDummy = true, rank = rank }
		end
	end

	self:_buildDummies()
	return self
end

-- Owns the 8 dummy parts in a dedicated Dummies folder (rebuilt fresh each call, like the arena builders).
function RotationService._buildDummies(self: RotationService)
	local ns = workspace:FindFirstChild("NineSquare")
	if not ns then
		warn("[Rotation] no workspace.NineSquare folder; build the arena before dummies")
		return
	end
	local old = ns:FindFirstChild("Dummies"); if old then old:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "Dummies"; folder.Parent = ns

	self._dummyParts = {}
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.isDummy then
			local d = Instance.new("Part")
			d.Name = "Dummy_rank" .. rank
			d.Shape = Enum.PartType.Cylinder
			d.Anchored = true
			d.CanCollide = false       -- never blocks the ball or players
			d.CastShadow = true
			-- Cylinder's length runs along its local X; rotate so it stands upright (length -> world Y).
			d.Size = Vector3.new(G.dummyHeight, G.dummyRadius * 2, G.dummyRadius * 2)
			d.Color = (rank == 1) and G.dummyKingColor or G.dummyColor
			d.Material = Enum.Material.SmoothPlastic
			d.Parent = folder
			self._dummyParts[occ.id] = d
		end
	end
end

-- Position one occupant (human or dummy) at the cell for its rank.
function RotationService._placeOccupant(self: RotationService, occ: Occupant)
	local cell = G.cellForRank(occ.rank)
	if occ.isDummy then
		local part = self._dummyParts[occ.id]
		if part then
			-- Stand the cylinder upright in the cell, base on the floor (y=0).
			local center = G.cellCenter(cell) + Vector3.new(0, G.dummyHeight / 2, 0)
			part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		end
	else
		self._placeHuman(cell)
	end
end

-- Put every occupant at cellForRank(rank). Re-placeable (M3 step 2 rotation re-calls this).
function RotationService.placeAll(self: RotationService)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ then self:_placeOccupant(occ) end
	end
end

-- Rotate the queue after a fault (PRD §4.3 / M3 design §4). The occupant who faulted at `faultRank`
-- is pushed to the tail (rank 9 / NW entry square) and every occupant at faultRank+1..9 advances ONE
-- rank toward the King (rank K takes rank K-1's cell). With the fixed 9 occupants this is exactly a
-- cyclic shift of ranks faultRank..9. A fault at rank 1 is a DETHRONE: the rank-2 occupant becomes the
-- new King (rank 1 / C) and onDethrone fires with them.
--
-- MECHANISM ONLY: this does not decide WHO faulted (that's step 3's fault attribution); the caller
-- passes the rank. After the shift it re-places everyone (incl. the human, via the injected teleport).
function RotationService.rotateOnFault(self: RotationService, faultRank: number)
	assert(faultRank >= 1 and faultRank <= RANKS, "faultRank out of range: " .. tostring(faultRank))

	local faulter = self.byRank[faultRank]
	-- Advance ranks faultRank+1..9 down one toward faultRank (each takes the slot below it).
	for r = faultRank, RANKS - 1 do
		local up = self.byRank[r + 1]
		self.byRank[r] = up
		up.rank = r
	end
	-- The faulter goes to the tail.
	self.byRank[RANKS] = faulter
	faulter.rank = RANKS

	print(("[Rotation] rotateOnFault(%d): %s -> rank 9; ranks %d..9 advanced toward King")
		:format(faultRank, faulter.id, faultRank + 1))

	self:placeAll()

	-- A King fault means a new King now sits at rank 1.
	if faultRank == 1 then
		local newKing = self.byRank[1]
		print(("[Rotation] DETHRONE: new King is %s (rank 1 / %s)"):format(newKing.id, G.cellForRank(1)))
		if self.onDethrone then self.onDethrone(newKing) end
	end
end

-- Place ONLY the human at their current cell (used on CharacterAdded, when the dummies already stand).
function RotationService.placeHuman(self: RotationService)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and not occ.isDummy then
			self:_placeOccupant(occ)
			return
		end
	end
end

-- The cell the human currently owns (for spawn placement / future HUD).
function RotationService.humanCell(self: RotationService): string?
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and not occ.isDummy then return G.cellForRank(occ.rank) end
	end
	return nil
end

-- The current King (rank 1 / C). Always present (fixed 9 occupants). Used by the serve branch.
function RotationService.kingOccupant(self: RotationService): Occupant
	return self.byRank[1]
end

-- Is the human currently King (rank 1)? Decides physical serve (human) vs auto-serve (dummy).
function RotationService.isHumanKing(self: RotationService): boolean
	return not self.byRank[1].isDummy
end

-- The occupant whose square is `cell` right now (reverse of placement). Used for fault attribution:
-- the ball landed in/was struck from `cell` -> who owns that square -> which rank faulted. nil if the
-- cell isn't a known rank cell (shouldn't happen for the 9 court squares).
function RotationService.occupantAtCell(self: RotationService, cell: string): Occupant?
	local rank = G.rankForCell(cell)
	if rank == nil then return nil end
	return self.byRank[rank]
end

return RotationService
