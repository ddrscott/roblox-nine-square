--!strict
-- ServerScriptService.NineSquare.RotationService
-- The 9-rank occupancy model + BOT rigs + placeAll (and rotateOnFault).
-- Holds byRank[rank] = { id, isDummy, rank } for exactly 9 occupants (1 human + 8 bots), builds the
-- 8 bot bodies, and places everyone at cellForRank(rank).
--
-- The bot occupants are now REAL R15 rigs (default blocky "Rig Builder" dummy): one template
-- (ReplicatedStorage.BotRigTemplate, built once in Studio) cloned 8x, one per rank. The rig is
-- COSMETIC + server-authoritative -- its HumanoidRootPart is anchored and CFrame-driven by the server
-- (the SAME intercept slide / jump / procedural idle the stylised body used; NO Humanoid:MoveTo /
-- pathfinding / self-locomotion). Every rig part is CanCollide=false + Massless, and the rigs live in
-- their OWN "Dummies" folder under workspace.NineSquare (NOT under NineSquare.Frame), so
-- BallController:_surfaces() never picks them up: the ball strikes the abstract hit-sphere collider
-- (BotController), never the rig, and the ball physics / contact stays server-resolved.
--
-- ANIMATION: the procedural idle (sway / ready-steps / ball-lean) still drives the ROOT translation;
-- stock R15 animation tracks (idle/walk/run/jump) are LAYERED on top via each rig's Animator -- gated
-- by the body's ACTUAL per-frame speed (computed from the driven HRP delta) so the legs match the
-- motion, and a one-shot jump track fires when the bot drives its collider up to strike.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local G = require(RS.GridConfig)

-- A collision group the bot rigs live in that collides with NOTHING. The R15 Humanoid re-enables
-- CanCollide on its limbs at runtime, so CanCollide=false alone isn't enough -- this group GUARANTEES the
-- rigs never physically perturb the ball, the player, or each other. (The ball never even sees the rigs:
-- they live OUTSIDE NineSquare.Frame, which is the only thing BallController:_surfaces() collects.)
local BOT_RIG_COLLISION_GROUP = "BotRig"
do
	local ok = pcall(function() PhysicsService:RegisterCollisionGroup(BOT_RIG_COLLISION_GROUP) end)
	if ok then
		-- Don't collide with the default group, and don't collide with itself.
		pcall(function() PhysicsService:CollisionGroupSetCollidable(BOT_RIG_COLLISION_GROUP, "Default", false) end)
		pcall(function() PhysicsService:CollisionGroupSetCollidable(BOT_RIG_COLLISION_GROUP, BOT_RIG_COLLISION_GROUP, false) end)
	end
end

export type Occupant = {
	id: string,        -- "human" or "dummy1".."dummy8"
	isDummy: boolean,
	rank: number,      -- 1..9 (King = 1)
}

-- Per-rig animation + drive state (so we can gate idle/walk/run from the real body speed and fire jump).
type RigState = {
	humanoid: Humanoid,
	animator: Animator,
	idle: AnimationTrack,
	walk: AnimationTrack,
	run: AnimationTrack,
	jump: AnimationTrack,
	moveState: string,        -- "idle" | "walk" | "run": the currently-playing locomotion track
	lastPos: Vector3?,        -- last driven HRP position (to derive body speed for the walk gate)
	lastTime: number?,        -- os.clock() of the last drive (real dt for the speed calc)
	jumpedAt: number,         -- os.clock() of the last jump one-shot (debounce so it fires once per strike)
}

local RotationService = {}
RotationService.__index = RotationService

export type RotationService = typeof(setmetatable(
	{} :: {
		byRank: { [number]: Occupant },
		_dummyParts: { [string]: Model },       -- id -> the bot's rig Model (human has none)
		_rigState: { [string]: RigState },      -- id -> animation/drive state for that rig
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
		_rigState = {},
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

-- The y-offset (from the cell floor up to the rig's HumanoidRootPart centre) that puts the rig's feet
-- on the floor. Measured off the default R15 blocky rig (GridConfig.botRigFootToRoot).
local function botTorsoY(): number
	return G.botRigFootToRoot
end

-- Recolour the rig's body parts by rank (King = gold). The head keeps its skin tone; the arms/torso/legs
-- take the body colour so whoever holds rank 1 reads as the gold King after a rotation.
local function recolourRig(rig: Model, rank: number)
	local color = (rank == 1) and G.botKingColor or G.botBodyColor
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Head" and d.Name ~= "HumanoidRootPart" then
			d.Color = color
			d.Material = Enum.Material.SmoothPlastic
		end
	end
end

-- Load one looped/one-shot animation track onto a rig's Animator.
local function loadTrack(animator: Animator, id: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	track.Looped = looped
	track.Priority = priority
	return track
end

-- Build the per-rig animation state (idle/walk/run/jump tracks on the rig's Animator) and start the
-- looped idle so a resting rig is alive from frame one.
local function buildRigState(rig: Model): RigState?
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if not hum then warn("[Rotation] rig has no Humanoid: " .. rig.Name); return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then animator = Instance.new("Animator"); animator.Parent = hum end

	local idle = loadTrack(animator, G.botAnimIdleId, true, Enum.AnimationPriority.Idle)
	local walk = loadTrack(animator, G.botAnimWalkId, true, Enum.AnimationPriority.Movement)
	local run  = loadTrack(animator, G.botAnimRunId,  true, Enum.AnimationPriority.Movement)
	local jump = loadTrack(animator, G.botAnimJumpId, false, Enum.AnimationPriority.Action)

	idle:Play(G.botAnimFadeTime)

	return {
		humanoid = hum,
		animator = animator,
		idle = idle, walk = walk, run = run, jump = jump,
		moveState = "idle",
		lastPos = nil,
		lastTime = nil,
		jumpedAt = 0,
	}
end

-- Owns the 8 bot rigs in a dedicated Dummies folder (rebuilt fresh each call, like the arena builders).
-- Clones the R15 template (ReplicatedStorage.BotRigTemplate) once per rank, recolours it, and wires its
-- animation tracks. If the template is missing, warns once -- bots simply won't appear (physics intact).
function RotationService._buildDummies(self: RotationService)
	local ns = workspace:FindFirstChild("NineSquare")
	if not ns then
		warn("[Rotation] no workspace.NineSquare folder; build the arena before bot rigs")
		return
	end
	local template = RS:FindFirstChild(G.botRigTemplateName)
	if not template then
		warn("[Rotation] no ReplicatedStorage." .. G.botRigTemplateName .. " rig template; bots will not render")
		self._dummyParts = {}
		self._rigState = {}
		return
	end

	local old = ns:FindFirstChild("Dummies"); if old then old:Destroy() end
	local folder = Instance.new("Folder"); folder.Name = "Dummies"; folder.Parent = ns

	self._dummyParts = {}
	self._rigState = {}
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.isDummy then
			local rig = template:Clone()
			rig.Name = "Bot_rank" .. rank
			recolourRig(rig, rank)
			rig.Parent = folder
			-- Put every rig part in the non-colliding BotRig group (the Humanoid flips CanCollide back on at
			-- runtime, so the group is what actually guarantees the rig never perturbs the ball/player/rigs).
			for _, d in ipairs(rig:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					pcall(function() d.CollisionGroup = BOT_RIG_COLLISION_GROUP end)
				end
			end
			self._dummyParts[occ.id] = rig
			local st = buildRigState(rig)
			if st then self._rigState[occ.id] = st end
		end
	end
end

-- Drive a rig: place its anchored HumanoidRootPart at `hrpCF` and update the layered animation from the
-- body's ACTUAL frame speed. `striking` (true while the bot drives its collider up to a strike) fires a
-- one-shot jump track. All cosmetic -- the rig never collides; the hit is the abstract collider's.
function RotationService._driveRig(self: RotationService, id: string, hrpCF: CFrame, striking: boolean)
	local rig = self._dummyParts[id]
	if not rig or not rig.PrimaryPart then return end
	rig:PivotTo(hrpCF)

	local st = self._rigState[id]
	if not st then return end

	-- Body speed from the driven HRP delta over real wall-clock dt (the procedural root translation IS the
	-- locomotion signal). XZ only, so a vertical jump doesn't read as "walking".
	local pos = hrpCF.Position
	local now = os.clock()
	local speed = 0
	if st.lastPos and st.lastTime then
		local dt = now - st.lastTime
		if dt > 1e-4 then
			local d = pos - st.lastPos
			speed = Vector3.new(d.X, 0, d.Z).Magnitude / dt
		end
	end
	st.lastPos = pos
	st.lastTime = now

	-- Locomotion gate: idle < walk < run by the body's real speed (smooth crossfades).
	local want = "idle"
	if speed >= G.botAnimRunSpeed then want = "run"
	elseif speed >= G.botAnimWalkSpeed then want = "walk" end
	if want ~= st.moveState then
		if st.moveState == "idle" then st.idle:Stop(G.botAnimFadeTime)
		elseif st.moveState == "walk" then st.walk:Stop(G.botAnimFadeTime)
		elseif st.moveState == "run" then st.run:Stop(G.botAnimFadeTime) end
		if want == "idle" then st.idle:Play(G.botAnimFadeTime)
		elseif want == "walk" then st.walk:Play(G.botAnimFadeTime)
		elseif want == "run" then st.run:Play(G.botAnimFadeTime) end
		st.moveState = want
	end
	-- Map body speed onto the walk/run cycle rate so the legs track the actual translation.
	if want == "walk" then st.walk:AdjustSpeed(math.clamp(speed * G.botAnimWalkRate / math.max(G.botAnimWalkSpeed, 0.1), 0.4, 2.5))
	elseif want == "run" then st.run:AdjustSpeed(math.clamp(speed * G.botAnimWalkRate / math.max(G.botAnimRunSpeed, 0.1), 0.6, 2.0)) end

	-- Jump one-shot on a strike (debounced so it fires once per swing, not every frame mid-jump).
	if striking and (now - st.jumpedAt) > 0.5 then
		st.jump:Play(0.08)
		st.jumpedAt = now
	end
end

-- Stand a bot rig in the centre of its cell with the feet on the floor (re-colours by current rank so
-- whoever holds rank 1 reads as the gold King). Returns the floor-standing HRP CFrame. This is a SNAP
-- (placement / rest), so we reset the rig's speed tracking to zero so the snap never reads as "running".
function RotationService._standBot(self: RotationService, rig: Model, cell: string, rank: number): CFrame
	local center = G.cellCenter(cell) + Vector3.new(0, botTorsoY(), 0)
	local cf = CFrame.new(center)
	if rig.PrimaryPart then rig:PivotTo(cf) end
	recolourRig(rig, rank)

	-- Reset the animation drive so the snapped position is the new rest (no spurious walk/run from the jump).
	local st = self._rigState[self:_idForRig(rig)]
	if st then
		st.lastPos = center
		st.lastTime = os.clock()
		if st.moveState ~= "idle" then
			if st.moveState == "walk" then st.walk:Stop(G.botAnimFadeTime)
			elseif st.moveState == "run" then st.run:Stop(G.botAnimFadeTime) end
			st.idle:Play(G.botAnimFadeTime)
			st.moveState = "idle"
		end
	end
	return cf
end

-- Reverse-lookup a rig's occupant id (for fetching its RigState from a Model handle).
function RotationService._idForRig(self: RotationService, rig: Model): string?
	for id, r in pairs(self._dummyParts) do
		if r == rig then return id end
	end
	return nil
end

-- Position one occupant (human or bot) at the cell for its rank.
function RotationService._placeOccupant(self: RotationService, occ: Occupant)
	local cell = G.cellForRank(occ.rank)
	if occ.isDummy then
		local rig = self._dummyParts[occ.id]
		if rig then self:_standBot(rig, cell, occ.rank) end
	else
		self._placeHuman(cell)
	end
end

-- R15 head sits this far above the HumanoidRootPart centre (measured off the default blocky rig). To put
-- the rig's HEAD at a world point we place the HRP this far below it.
local BOT_HEAD_ABOVE_HRP = 1.586

-- LEGACY in-place hop (back-compat). BotController no longer calls this -- it drives the rig via
-- driveOccupant/restOccupant. With R15 rigs the limb motion comes from the layered jump anim track, so
-- this just bobs the rig's anchored HRP up and back down (the Animator handles the legs). Kept so any old
-- caller still works. `contactPos` is ignored for the R15 path (the strike pose is the jump anim).
function RotationService.hopOccupant(self: RotationService, id: string, contactPos: Vector3?)
	local rig = self._dummyParts[id]
	if not rig or not rig.PrimaryPart then return end
	local rest = rig:GetPivot()
	local peak = rest + Vector3.new(0, G.botHopHeight, 0)
	local upDur, downDur = G.botHopUpTime, G.botHopDownTime
	-- Fire the jump anim once at the start of the hop.
	local st = self._rigState[id]
	if st and (os.clock() - st.jumpedAt) > 0.5 then st.jump:Play(0.08); st.jumpedAt = os.clock() end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not rig.Parent then conn:Disconnect(); return end
		local elapsed = os.clock() - t0
		if elapsed < upDur then
			rig:PivotTo(rest:Lerp(peak, elapsed / upDur))
		elseif elapsed < upDur + downDur then
			rig:PivotTo(peak:Lerp(rest, (elapsed - upDur) / downDur))
		else
			rig:PivotTo(rest); conn:Disconnect()
		end
	end)
end

-- PHYSICAL-HIT body drive (bot hit rework). The bot is a REAL physical hitter: BotController drives a
-- moving hit-sphere collider (center, vel) to an off-centre stand position and jumps it into the ball, and
-- the SAME swept collision the human uses resolves the strike. This method keeps the R15 RIG synced to that
-- collider so the player SEES the bot run its feet + leap into the ball: it places the rig's HEAD at the
-- collider centre `headWorld` (so the rig rises with the jump), faces it toward `leanTarget` (the ball) and
-- pitches it into the strike. The R15 jump anim (fired by _driveRig when `armRaise` is high) gives the limb
-- life -- no manual arm CFrames. Cosmetic only (CanCollide stays false) -- the hit is the collider's.
function RotationService.driveOccupant(self: RotationService, id: string, headWorld: Vector3, leanTarget: Vector3?, armRaise: number?)
	local rig = self._dummyParts[id]
	if not rig or not rig.PrimaryPart then return end

	-- Place the HRP so the rig's HEAD sits at the collider centre (head tracks the collider through the jump).
	local hrpPos = headWorld - Vector3.new(0, BOT_HEAD_ABOVE_HRP, 0)

	-- Face the ball (XZ) and pitch INTO the strike, so the rig reads as a reach not a stiff float.
	local cf = CFrame.new(hrpPos)
	if leanTarget then
		local horiz = Vector3.new(leanTarget.X - headWorld.X, 0, leanTarget.Z - headWorld.Z)
		if horiz.Magnitude > 1e-3 then
			local leanDir = horiz.Unit
			cf = CFrame.lookAt(hrpPos, hrpPos + leanDir)
			-- A small forward pitch toward the ball at the apex (scales with the strike's armRaise).
			local raise = math.clamp(armRaise or 0, 0, 1)
			cf = cf * CFrame.Angles(math.rad(G.botLeapTiltDeg) * raise, 0, 0)
		end
	end

	-- A high armRaise == we're at/near the strike -> _driveRig fires the one-shot jump anim.
	local striking = (math.clamp(armRaise or 0, 0, 1) > 0.6)
	self:_driveRig(id, cf, striking)
end

-- Snap a bot rig back to its resting stand in its current cell (feet on the floor). Called when a swing
-- ends so the rig never drifts from the collider's rest pose.
function RotationService.restOccupant(self: RotationService, id: string)
	local rig = self._dummyParts[id]
	if not rig then return end
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.id == id then
			self:_standBot(rig, G.cellForRank(occ.rank), occ.rank)
			return
		end
	end
end

-- IDLE ready-stance + anticipatory tracking (lifelike bot motion). Drives a bot body that is NOT the active
-- receiver so it reads as ALIVE instead of frozen: it pivots the body to its home stand plus a small XZ
-- `offsetXZ` (the sway + ready-step + ball-lean, computed deterministically per bot in BotController) and a
-- vertical `bobY` (the toe-bob), optionally tilting the torso toward `leanTarget` (the live ball) so the body
-- subtly faces the rally. BotController clamps `offsetXZ` inside the cell, so the body never drifts out of its
-- square. Cosmetic only (CanCollide stays false); yields cleanly to driveOccupant/restOccupant when this bot
-- becomes the receiver (those overwrite the pivot the same frame). Arms are left at their rest offsets.
function RotationService.idleOccupant(self: RotationService, id: string, offsetXZ: Vector3, bobY: number, leanTarget: Vector3?)
	local rig = self._dummyParts[id]
	if not rig or not rig.PrimaryPart then return end
	-- Find the bot's home HRP position (feet on the floor of its current cell), same as _standBot.
	local cell = self:occupantCell(id)
	if not cell then return end
	local home = G.cellCenter(cell) + Vector3.new(0, botTorsoY(), 0)
	local hrpPos = home + Vector3.new(offsetXZ.X, bobY, offsetXZ.Z)

	-- Face the live ball (XZ) so the rig subtly turns toward the rally; a faint pitch reads as an idle lean.
	local cf = CFrame.new(hrpPos)
	if leanTarget then
		local horiz = Vector3.new(leanTarget.X - hrpPos.X, 0, leanTarget.Z - hrpPos.Z)
		if horiz.Magnitude > 1e-3 then
			local leanDir = horiz.Unit
			cf = CFrame.lookAt(hrpPos, hrpPos + leanDir) * CFrame.Angles(math.rad(G.botIdleLeanDeg), 0, 0)
		end
	end

	-- Drive the rig (idle/walk anim gates off the per-frame speed of this small sway/ready-step motion; the
	-- ready-step pushes the body fast enough to flip to the walk track, then back to idle when it returns).
	self:_driveRig(id, cf, false)
end

-- The world cell the bot `id` currently stands in (for the collider's rest position). nil if not a bot.
function RotationService.occupantCell(self: RotationService, id: string): string?
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.id == id then return G.cellForRank(occ.rank) end
	end
	return nil
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
