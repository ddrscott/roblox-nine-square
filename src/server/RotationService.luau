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

-- Cubic ease-out (fast start, soft stop) -- for the rise to the strike.
local function easeOutCubic(t: number): number
	local u = 1 - t
	return 1 - u * u * u
end
-- Cubic ease-in (soft start, fast finish) -- for the fall back down.
local function easeInCubic(t: number): number
	return t * t * t
end

-- LEAP-TO-BALL juice (M4 visual fix). Server-driven, called by BotController the instant it resolves a
-- volley (so the apex coincides with bc:launch). `contactPos` is the ball's world position at the strike
-- (~frameHeight at the ball's XZ). The bot body LEAPS from its floor stand UP toward `contactPos` -- rising
-- to ~the ball's height and leaning toward the ball's XZ (capped) -- so it visibly meets + strikes the ball,
-- raises its near arm + tilts in at the apex (the reach), holds briefly, then arcs back down and snaps home.
--
-- The body is a Model of separate ANCHORED parts (no Motor6D), so we drive it on Heartbeat (cheap: <=8 bots,
-- fires only on a volley): the whole-Model pivot carries position + lean; the near arm is re-CFramed each
-- frame relative to the live torso for the overhead reach. Always leaps from the CURRENT rest pose so it
-- never drifts, and snaps exactly back to rest (arms restored) at the end. CanCollide stays false; cosmetic.
--
-- `contactPos` is optional for back-compat: with no contact point it falls back to the legacy in-place hop.
function RotationService.hopOccupant(self: RotationService, id: string, contactPos: Vector3?)
	local body = self._dummyParts[id]
	if not body or not body.PrimaryPart then return end
	local rest = body:GetPivot()

	-- Capture each arm's rest CFrame *relative to the torso* so we can swing one up and restore both exactly.
	local armL = body:FindFirstChild("ArmL") :: BasePart?
	local armR = body:FindFirstChild("ArmR") :: BasePart?
	local restInv = rest:Inverse()
	local armLLocal = armL and (restInv * armL.CFrame) or nil
	local armRLocal = armR and (restInv * armR.CFrame) or nil

	-- Restore arms + the model to rest in one place (used on land and on early-out).
	local function snapHome()
		body:PivotTo(rest)
		if armL and armLLocal then armL.CFrame = rest * armLLocal end
		if armR and armRLocal then armR.CFrame = rest * armRLocal end
	end

	-- No contact point -> legacy in-place hop (back-compat; keeps old callers working).
	if not contactPos then
		local peak = rest + Vector3.new(0, G.botHopHeight, 0)
		local upDur, downDur = G.botHopUpTime, G.botHopDownTime
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not body.Parent then conn:Disconnect(); return end
			local elapsed = os.clock() - t0
			if elapsed < upDur then
				body:PivotTo(rest:Lerp(peak, elapsed / upDur))
			elseif elapsed < upDur + downDur then
				body:PivotTo(peak:Lerp(rest, (elapsed - upDur) / downDur))
			else
				snapHome(); conn:Disconnect()
			end
		end)
		return
	end

	-- Apex target: travel `botLeapReachFrac` of the way from the rest torso toward the contact point, with
	-- the horizontal lean toward the ball's XZ capped (`botLeapMaxLeanXZ`) so an edge contact never flings
	-- the body out of its square. Vertically we go (almost) all the way up so the body meets the ball.
	local restPos = rest.Position
	local frac = G.botLeapReachFrac
	local riseY = (contactPos.Y - restPos.Y) * frac
	local leanXZ = Vector3.new(contactPos.X - restPos.X, 0, contactPos.Z - restPos.Z) * frac
	local leanMag = leanXZ.Magnitude
	if leanMag > G.botLeapMaxLeanXZ then
		leanXZ = leanXZ * (G.botLeapMaxLeanXZ / leanMag)
	end
	local apexPos = restPos + Vector3.new(leanXZ.X, math.max(riseY, 0), leanXZ.Z)

	-- Lean direction (toward the ball, in XZ) -> pick the near arm + tilt axis for the strike.
	local horiz = Vector3.new(contactPos.X - restPos.X, 0, contactPos.Z - restPos.Z)
	local leanDir = (horiz.Magnitude > 1e-3) and horiz.Unit or Vector3.new(0, 0, -1)
	-- Tilt axis = perpendicular to lean (so positive lean pitches the torso top toward the ball).
	local tiltAxis = Vector3.new(0, 1, 0):Cross(leanDir)
	if tiltAxis.Magnitude < 1e-3 then tiltAxis = Vector3.new(1, 0, 0) end
	tiltAxis = tiltAxis.Unit
	local tiltMax = math.rad(G.botLeapTiltDeg)
	-- Near arm = the one on the side the body leans toward (its local +X is right). Default to right arm.
	local nearArm, nearLocal = armR, armRLocal
	if armL and armLLocal then
		local rightDot = rest.RightVector:Dot(leanDir)
		if rightDot < 0 then nearArm, nearLocal = armL, armLLocal end
	end
	local armRaiseMax = math.rad(G.botLeapArmRaiseDeg)

	local upDur, holdDur, downDur = G.botLeapUpTime, G.botLeapHoldTime, G.botLeapDownTime
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not body.Parent then conn:Disconnect(); return end
		local elapsed = os.clock() - t0

		-- s = 0..1 leap progress (1 = fully extended at the strike); reach/tilt scale with s.
		local s: number
		local atApex = false
		if elapsed < upDur then
			s = easeOutCubic(elapsed / upDur)                         -- ease-out up to the strike
		elseif elapsed < upDur + holdDur then
			s = 1; atApex = true                                      -- brief hold at contact
		elseif elapsed < upDur + holdDur + downDur then
			s = 1 - easeInCubic((elapsed - upDur - holdDur) / downDur) -- ease-in back down
		else
			snapHome(); conn:Disconnect(); return
		end

		-- Position: rest -> apex by s, with a touch of upward stretch as it extends toward the strike
		-- (squash-stretch: the body looks like it reaches a hair past the apex for the ball).
		local stretchY = G.botLeapSquashFrac * (atApex and 1 or s * 0.6)
		local pos = restPos:Lerp(apexPos, s) + Vector3.new(0, stretchY, 0)
		-- Torso pitches toward the ball, peaking at the apex (the lean-in on the strike).
		local cf = CFrame.new(pos) * CFrame.fromAxisAngle(tiltAxis, tiltMax * s)
		body:PivotTo(cf)

		-- The near arm swings up overhead (the reach), restoring on the way down. Swung about the shoulder
		-- line (the arm's local X axis) off the LIVE torso CFrame so it tracks the lean + position.
		if nearArm and nearLocal then
			local swing = CFrame.fromAxisAngle(Vector3.new(1, 0, 0), -armRaiseMax * s)
			nearArm.CFrame = cf * (nearLocal * swing)
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
