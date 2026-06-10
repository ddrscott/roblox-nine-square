--!strict
-- ServerScriptService.NineSquare.RotationService
-- M3 step 1 / M4 step 2: the 9-rank occupancy model + BOT bodies + placeAll (and rotateOnFault).
-- Holds byRank[rank] = { id, isDummy, rank } for exactly 9 occupants (1 human + 8 bots), builds the
-- 8 stylised bot bodies, and places everyone at cellForRank(rank).
--
-- M4 step 2: the bot occupants are now cheap STYLISED HUMANOID bodies (a Model: anchored torso + head +
-- arms with a PrimaryPart), not cylinders -- so they read as players and can HOP on a volley
-- (hopOccupant pivots the Model up + back down). They are deliberately cosmetic + CanCollide=false and
-- live in their OWN "Dummies" folder under workspace.NineSquare (NOT under NineSquare.Frame), so
-- BallController:_surfaces() never picks them up and the ball physics / contact stays server-resolved.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
		_dummyParts: { [string]: Model },       -- id -> the bot's body Model (human has none)
		_placeHuman: (cell: string) -> (),     -- injected: teleport the human's HRP to a cell
		_setHumanRank: ((rank: number) -> ())?,  -- injected: replicate the human's current rank (player attribute)
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

-- Build one stylised bot body: a small Model (anchored torso + head + two arms) with the torso as the
-- PrimaryPart so the whole body can be CFramed/tweened as a unit. All parts CanCollide=false + Anchored
-- and live OUTSIDE NineSquare.Frame, so the ball never collides with a bot (the hit stays server-resolved).
-- The body is built around a local origin (torso centre at y=0); _placeOccupant CFrames the PrimaryPart so
-- the FEET sit on the floor of the cell.
local function buildBotBody(name: string, bodyColor: Color3): Model
	local model = Instance.new("Model"); model.Name = name
	local function part(pname: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = pname
		if shape then p.Shape = shape end
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = true
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = CFrame.new(offset)   -- relative to the torso centre (set absolutely in _placeOccupant)
		p.Parent = model
		return p
	end
	local torso = part("Torso", G.botTorsoSize, Vector3.new(0, 0, 0), bodyColor)
	local headOff = G.botTorsoSize.Y / 2 + G.botHeadSize / 2 + 0.15
	part("Head", Vector3.new(G.botHeadSize, G.botHeadSize, G.botHeadSize), Vector3.new(0, headOff, 0), G.botSkinColor)
	local armX = G.botTorsoSize.X / 2 + G.botArmSize.X / 2 + 0.1
	local armY = G.botTorsoSize.Y / 2 - G.botArmSize.Y / 2
	part("ArmL", G.botArmSize, Vector3.new(-armX, armY, 0), bodyColor)
	part("ArmR", G.botArmSize, Vector3.new(armX, armY, 0), bodyColor)
	model.PrimaryPart = torso
	return model
end

-- The y-offset (from the cell floor up to the torso centre) that puts a bot's feet on the floor.
local function botTorsoY(): number
	local armBottom = (G.botTorsoSize.Y / 2 - G.botArmSize.Y / 2) - G.botArmSize.Y / 2  -- lowest point (arm tip)
	return -armBottom
end

-- Owns the 8 bot bodies in a dedicated Dummies folder (rebuilt fresh each call, like the arena builders).
function RotationService._buildDummies(self: RotationService)
	local ns = workspace:FindFirstChild("NineSquare")
	if not ns then
		warn("[Rotation] no workspace.NineSquare folder; build the arena before bot bodies")
		return
	end
	local old = ns:FindFirstChild("Dummies"); if old then old:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "Dummies"; folder.Parent = ns

	self._dummyParts = {}
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.isDummy then
			local color = (rank == 1) and G.botKingColor or G.botBodyColor
			local body = buildBotBody("Bot_rank" .. rank, color)
			body.Parent = folder
			self._dummyParts[occ.id] = body
		end
	end
end

-- Stand a bot body in the centre of its cell with the feet on the floor (re-colours by current rank so
-- whoever holds rank 1 reads as the gold King). Returns the floor-standing torso CFrame.
function RotationService._standBot(self: RotationService, body: Model, cell: string, rank: number): CFrame
	local center = G.cellCenter(cell) + Vector3.new(0, botTorsoY(), 0)
	local cf = CFrame.new(center)
	if body.PrimaryPart then body:PivotTo(cf) end
	-- Recolour torso + arms by rank (King = gold) so the body's colour tracks its rank after rotation.
	local color = (rank == 1) and G.botKingColor or G.botBodyColor
	for _, child in ipairs(body:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Head" then
			child.Color = color
		end
	end
	return cf
end

-- Position one occupant (human or bot) at the cell for its rank.
function RotationService._placeOccupant(self: RotationService, occ: Occupant)
	local cell = G.cellForRank(occ.rank)
	if occ.isDummy then
		local body = self._dummyParts[occ.id]
		if body then self:_standBot(body, cell, occ.rank) end
	else
		self._placeHuman(cell)
	end
end

-- Juice: pop a bot up and settle it back down so a volley reads visually. Server-driven (called by
-- BotController on a hit). The bot body is a Model of separate anchored parts (no Motor6D), so we can't
-- hand it to TweenService directly -- we drive the whole-Model pivot on Heartbeat (cheap: <=8 bots, and a
-- hop fires only on a volley). Always hops from the bot's CURRENT standing pose so it never drifts, and
-- snaps exactly back to rest at the end. CanCollide stays false; purely cosmetic.
function RotationService.hopOccupant(self: RotationService, id: string)
	local body = self._dummyParts[id]
	if not body or not body.PrimaryPart then return end
	local rest = body:GetPivot()
	local peak = rest + Vector3.new(0, G.botHopHeight, 0)
	local upDur, downDur = G.botHopUpTime, G.botHopDownTime
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not body.Parent then conn:Disconnect(); return end
		local elapsed = os.clock() - t0
		if elapsed < upDur then
			body:PivotTo(rest:Lerp(peak, elapsed / upDur))                  -- rise
		elseif elapsed < upDur + downDur then
			body:PivotTo(peak:Lerp(rest, (elapsed - upDur) / downDur))      -- settle
		else
			body:PivotTo(rest)                                              -- snap home
			conn:Disconnect()
		end
	end)
end

-- Replicate the human's CURRENT rank to their client (server-authoritative; the client only displays).
-- Finds the human occupant and pushes its rank via the injected setter (a player attribute in the server).
function RotationService._syncHumanRank(self: RotationService)
	if not self._setHumanRank then return end
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and not occ.isDummy then
			self._setHumanRank(occ.rank)
			return
		end
	end
end

-- Put every occupant at cellForRank(rank). Re-placeable (M3 step 2 rotation re-calls this).
function RotationService.placeAll(self: RotationService)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ then self:_placeOccupant(occ) end
	end
	self:_syncHumanRank()
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
			self:_syncHumanRank()
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

-- The human's current rank (1..9), or 9 if somehow absent. Used to seed a (re)joining player's HUD.
function RotationService.humanRank(self: RotationService): number
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and not occ.isDummy then return occ.rank end
	end
	return RANKS
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
