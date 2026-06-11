--!strict
-- ServerScriptService.NineSquare.RotationService
-- The 9-seat occupancy model + BOT rigs + placeAll / rotateOnFault / join+leave (M5.1).
--
-- A SEAT = a rank 1..9 <-> cell (King = rank 1 = C, then the clockwise ring outward). Each seat's
-- occupant is either a HUMAN Player or a BOT. `byRank[1..9]` is the SINGLE SOURCE OF TRUTH:
--   byRank[rank] = { kind = "human"|"bot", player?, id, rank, cell, isDummy }
-- `isDummy` is kept as an alias for `kind == "bot"` so every existing bot-square check (BotController,
-- placement, idle) keeps working unchanged.
--
-- OCCUPANCY POLICY (M5.1): HUMANS fill seats as they join, BOTS backfill the rest -> it is ALWAYS a full
-- 9-square. A joining human takes the ENTRY rank (the highest-numbered seat farthest from the King) by
-- DISPLACING the bot there (that bot's rig is destroyed). Multiple humans each take the next-highest open
-- seat; humans always outrank bots (bots are pure backfill). A leaving human's seat is BACKFILLED via an
-- injected hook (M5.2 spectator queue overrides it; the default is a fresh bot) so a rank is never empty.
--
-- The bot occupants are REAL R15 rigs (default blocky "Rig Builder" dummy): one template
-- (ReplicatedStorage.BotRigTemplate, built once in Studio) cloned per bot, recoloured + animation-wired,
-- created/destroyed as bots are spawned/displaced. The rig is COSMETIC + server-authoritative -- its
-- HumanoidRootPart is anchored and CFrame-driven by the server (the SAME intercept slide / jump /
-- procedural idle; NO Humanoid:MoveTo / pathfinding / self-locomotion). Every rig part is CanCollide=false
-- + in the non-colliding BotRig group, and the rigs live in their OWN "Dummies" folder under
-- workspace.NineSquare (NOT under NineSquare.Frame), so BallController:_surfaces() never picks them up:
-- the ball strikes the abstract hit-sphere collider (BotController), never the rig.
--
-- ANIMATION: the procedural idle (sway / ready-steps / ball-lean) drives the ROOT translation; stock R15
-- animation tracks (idle/walk/run/jump) are LAYERED on top via each rig's Animator -- gated by the body's
-- ACTUAL per-frame speed (computed from the driven HRP delta) so the legs match the motion, and a one-shot
-- jump track fires when the bot drives its collider up to strike.
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
	kind: string,        -- "human" | "bot"
	player: Player?,     -- the seated Player (humans only)
	id: string,          -- stable occupant id: humans "human_<userId>", bots "bot#<n>" (unique per rig)
	isDummy: boolean,    -- alias for kind == "bot" (back-compat: every existing bot-square check reads this)
	rank: number,        -- 1..9 (King = 1)
	cell: string,        -- cellForRank(rank); kept in sync on placement/rotation
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

-- How the server seats / replicates a HUMAN. Injected by NineSquareServer so the service stays decoupled
-- from character handling + remotes.
--   placeHuman(player, cell): teleport THAT player's HRP to the cell.
--   setHumanRank(player, rank): replicate that player's current rank (its own "Rank" attribute).
--   backfillHook(rank, cell): OPTIONAL leave-backfill override (M5.2 spectator queue). Returns an
--     Occupant to seat at the freed rank, or nil to fall through to a fresh bot. Default: nil -> bot.
export type RotationService = typeof(setmetatable(
	{} :: {
		byRank: { [number]: Occupant },
		_dummyParts: { [string]: Model },       -- bot id -> the bot's rig Model (humans have none)
		_rigState: { [string]: RigState },      -- bot id -> animation/drive state for that rig
		_botSeq: number,                         -- monotonic counter -> unique bot ids (no rig id reuse)
		_placeHuman: (player: Player, cell: string) -> (),       -- injected: teleport a player's HRP to a cell
		_setHumanRank: ((player: Player, rank: number) -> ())?,  -- injected: replicate a player's rank
		_backfillHook: ((rank: number, cell: string) -> Occupant?)?, -- injected: M5.2 leave override (default bot)
		_dummyFolder: Folder?,                   -- workspace.NineSquare.Dummies (holds every bot rig)
		_botLetters: { [string]: string },       -- bot id -> stable jersey letter (A, B, C, ...) while on the board
		_letterSeq: number,                      -- monotonic counter -> the next bot jersey letter
		_botColors: { [string]: Color3 },         -- bot id -> stable palette body colour while on the board (King-gold overrides at rank 1)
		_jerseyConns: { [Player]: RBXScriptConnection }?,  -- per-human CharacterAdded -> re-attach the jersey on respawn
		onDethrone: ((newKing: Occupant) -> ())?,  -- optional: fires when the King (rank 1) faults
	},
	RotationService
))

local RANKS = 9

-- Build a fresh full 9-square: ALL seats start as bots (the King -- rank 1 / C -- is a bot until a human
-- earns it). Humans are seated later via seatHuman as they join. placeHuman/setHumanRank are how we drive a
-- seated player (NineSquareServer injects them so the service stays decoupled from character handling).
function RotationService.new(placeHuman: (player: Player, cell: string) -> ()): RotationService
	local self = setmetatable({
		byRank = {},
		_dummyParts = {},
		_rigState = {},
		_botSeq = 0,
		_placeHuman = placeHuman,
		_dummyFolder = nil,
		_botLetters = {},
		_letterSeq = 0,
		_botColors = {},
		_jerseyConns = {},
	}, RotationService)

	-- Fresh "Dummies" folder for the rigs (rebuilt each construction, like the arena builders).
	local ns = workspace:FindFirstChild("NineSquare")
	if ns then
		local old = ns:FindFirstChild("Dummies"); if old then old:Destroy() end
		local folder = Instance.new("Folder"); folder.Name = "Dummies"; folder.Parent = ns
		self._dummyFolder = folder
	else
		warn("[Rotation] no workspace.NineSquare folder; build the arena before bot rigs")
	end

	-- Seed all 9 seats with bots (each gets its own rig + jersey letter).
	for rank = 1, RANKS do
		self.byRank[rank] = self:_makeBot(rank)
	end

	-- Mark the King jersey (rank 1) now that all seats are filled.
	self:_refreshJerseys()
	return self
end

-- ============================================================================================
-- OCCUPANT JERSEY LABELS (replaces the M5.6 over-grid nameplates). A BillboardGui "jersey" is attached
-- to each occupant's RIG (a human's character Head or a bot's rig Head), so the label MOVES with the
-- occupant as it rotates through cells (no per-cell relabel -- it's on the occupant, not the square).
-- HUMANS show their DisplayName; BOTS show a stable LETTER (A, B, C, ...) assigned per bot so it's
-- consistent while that bot is on the board. The KING (rank 1) is marked clearly (gold tint + crown glyph).
-- Server-built + server-authoritative off `byRank`, so it replicates to every client (players + gallery
-- spectators) and never trusts the client. Cosmetic only: the BillboardGui is non-colliding GUI, OUTSIDE
-- the ball/player collision sets.
-- ============================================================================================

-- Assign the next stable jersey LETTER (A, B, C, ... then AA, AB, ... past 26) to a bot id. Stable while
-- the bot is on the board (kept in _botLetters until the bot is destroyed/displaced), so its label never
-- changes mid-game as it rotates ranks.
function RotationService._assignBotLetter(self: RotationService, id: string): string
	local existing = self._botLetters[id]
	if existing then return existing end
	local n = self._letterSeq
	self._letterSeq += 1
	-- bijective base-26: 0->A, 25->Z, 26->AA, ...
	local letter = ""
	repeat
		letter = string.char(65 + (n % 26)) .. letter
		n = math.floor(n / 26) - 1
	until n < 0
	self._botLetters[id] = letter
	return letter
end

-- Assign (once) + fetch a bot's STABLE palette body colour. Cycled deterministically by the bot's creation
-- sequence (the numeric suffix of its "bot#<n>" id) over GridConfig.botColors, so it's distinct from its
-- neighbours, STABLE while the bot is on the board, and travels with the bot through rotations (the colour is
-- keyed to the bot id, not its rank/cell). King-gold still overrides at rank 1 in recolourRig; this is the
-- colour the bot reverts to when it's not King. Falls back to botBodyColor if the palette is empty.
function RotationService._botColor(self: RotationService, id: string): Color3
	local existing = self._botColors[id]
	if existing then return existing end
	local palette = G.botColors
	local color: Color3
	if palette and #palette > 0 then
		local seq = tonumber(string.match(id, "%d+")) or 1
		local idx = ((seq - 1) % #palette) + 1
		color = palette[idx]
	else
		color = G.botBodyColor
	end
	self._botColors[id] = color
	return color
end

-- Find the Head (or PrimaryPart) of an occupant's rig/character to adorn the jersey to. Bots use their
-- rig Model; humans use their live Character. nil if the rig/character isn't present yet.
local function occupantHead(occ: Occupant, rig: Model?): BasePart?
	local model: Model? = nil
	if occ.kind == "bot" then
		model = rig
	elseif occ.player then
		model = occ.player.Character
	end
	if not model then return nil end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head end
	return model.PrimaryPart
end

-- Create (or fetch) the jersey BillboardGui parented to `head`. One per rig/character; reused on refresh.
local function ensureJersey(head: BasePart): TextLabel
	local gui = head:FindFirstChild("Jersey") :: BillboardGui?
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Jersey"
		gui.Size = UDim2.fromScale(G.jerseySize.X, G.jerseySize.Y)
		gui.StudsOffset = Vector3.new(0, G.jerseyHeight, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = G.jerseyMaxDistance
		gui.LightInfluence = 0
		gui.Adornee = head
		gui.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Label"; label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1); label.Font = Enum.Font.GothamBold
		label.TextScaled = true; label.Text = ""
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5; stroke.Color = Color3.fromRGB(10, 12, 16); stroke.Transparency = 0.15
		stroke.Parent = label
	end
	return gui:FindFirstChild("Label") :: TextLabel
end

-- (Re)label ONE occupant's jersey from its rank: human -> DisplayName, bot -> its stable letter; the King
-- (rank 1) gets a crown glyph prefix + gold text so the throne reads at a glance. Safe if the rig/character
-- isn't present yet (a human awaiting CharacterAdded) -- it relabels on the next refresh.
function RotationService._refreshJerseyFor(self: RotationService, occ: Occupant)
	local rig = (occ.kind == "bot") and self._dummyParts[occ.id] or nil
	local head = occupantHead(occ, rig)
	if not head then return end
	local label = ensureJersey(head)

	local who: string
	if occ.kind == "human" and occ.player then
		who = occ.player.DisplayName
	else
		who = self:_assignBotLetter(occ.id)
	end

	if occ.rank == 1 then
		label.Text = "\u{1F451} " .. who          -- crown glyph + occupant on the throne
		label.TextColor3 = G.jerseyKingColor
	else
		label.Text = who
		label.TextColor3 = (occ.kind == "human") and G.jerseyHumanColor or G.jerseyBotColor
	end
end

-- Relabel EVERY occupant's jersey (King mark, human names, bot letters). Called on any occupancy/rank
-- change (placeAll / join / leave / auto-seat / rotation) so the King mark follows the throne.
function RotationService._refreshJerseys(self: RotationService)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ then self:_refreshJerseyFor(occ) end
	end
end

-- The y-offset (from the cell floor up to the rig's HumanoidRootPart centre) that puts the rig's feet
-- on the floor. Measured off the default R15 blocky rig (GridConfig.botRigFootToRoot).
local function botTorsoY(): number
	return G.botRigFootToRoot
end

-- Recolour the rig's body parts (King = gold; otherwise this bot's own palette colour `bodyColor`). The head
-- keeps its skin tone; the arms/torso/legs take the body colour so whoever holds rank 1 reads as the gold
-- King after a rotation, and every non-King bot keeps its own distinct palette colour (set per bot in
-- _makeBot). `bodyColor` falls back to the legacy single botBodyColor if a per-bot colour wasn't supplied.
local function recolourRig(rig: Model, rank: number, bodyColor: Color3?)
	local color = (rank == 1) and G.botKingColor or (bodyColor or G.botBodyColor)
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

-- Spawn ONE bot occupant for `rank`: build its rig from the template (recoloured + animation-wired) and
-- return the occupant record. The rig is created in the Dummies folder under a UNIQUE id (no rig reuse, so
-- displace/backfill never collides with a stale rig). If the template is missing, the bot still occupies
-- the seat (occupant record) but has no rig (warned once) -- the abstract collider + physics are intact.
function RotationService._makeBot(self: RotationService, rank: number): Occupant
	self._botSeq += 1
	local id = "bot#" .. tostring(self._botSeq)
	local occ: Occupant = {
		kind = "bot", player = nil, id = id, isDummy = true,
		rank = rank, cell = G.cellForRank(rank),
	}

	local folder = self._dummyFolder
	local template = RS:FindFirstChild(G.botRigTemplateName)
	if not folder then
		warn("[Rotation] no Dummies folder; bot " .. id .. " has no rig")
		return occ
	end
	if not template then
		warn("[Rotation] no ReplicatedStorage." .. G.botRigTemplateName .. " rig template; bots will not render")
		return occ
	end

	local rig = template:Clone()
	rig.Name = "Bot_" .. id
	recolourRig(rig, rank, self:_botColor(id))
	rig.Parent = folder
	-- Put every rig part in the non-colliding BotRig group (the Humanoid flips CanCollide back on at runtime,
	-- so the group is what actually guarantees the rig never perturbs the ball/player/rigs).
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			pcall(function() d.CollisionGroup = BOT_RIG_COLLISION_GROUP end)
		end
	end
	self._dummyParts[id] = rig
	local st = buildRigState(rig)
	if st then self._rigState[id] = st end
	return occ
end

-- Destroy a bot's rig + animation state (called when a human DISPLACES the bot at the entry rank). The
-- occupant record itself is overwritten by the caller; here we just reap its rig so it stops rendering.
function RotationService._destroyBot(self: RotationService, occ: Occupant)
	if occ.kind ~= "bot" then return end
	local rig = self._dummyParts[occ.id]
	if rig then rig:Destroy() end
	self._dummyParts[occ.id] = nil
	self._rigState[occ.id] = nil
	self._botLetters[occ.id] = nil   -- free this bot's jersey letter (it's off the board)
	self._botColors[occ.id] = nil    -- free this bot's palette colour (it's off the board)
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

-- Stand a bot rig in the centre of its cell with the feet on the floor (re-colours: King-gold at rank 1,
-- otherwise this bot's own stable palette colour, so whoever holds rank 1 reads as the gold King and every
-- non-King bot keeps its distinct colour after a rotation). Returns the floor-standing HRP CFrame. This is a
-- SNAP (placement / rest), so we reset the rig's speed tracking to zero so the snap never reads as "running".
function RotationService._standBot(self: RotationService, rig: Model, cell: string, rank: number): CFrame
	local center = G.cellCenter(cell) + Vector3.new(0, botTorsoY(), 0)
	local cf = CFrame.new(center)
	if rig.PrimaryPart then rig:PivotTo(cf) end
	local id = self:_idForRig(rig)
	recolourRig(rig, rank, id and self:_botColor(id) or nil)

	-- Reset the animation drive so the snapped position is the new rest (no spurious walk/run from the jump).
	local st = id and self._rigState[id]
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

-- Position one occupant (human or bot) at the cell for its rank. Keeps occ.cell in sync.
function RotationService._placeOccupant(self: RotationService, occ: Occupant)
	local cell = G.cellForRank(occ.rank)
	occ.cell = cell
	if occ.kind == "bot" then
		local rig = self._dummyParts[occ.id]
		if rig then self:_standBot(rig, cell, occ.rank) end
	elseif occ.player then
		self._placeHuman(occ.player, cell)
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

-- The world cell the bot `id` currently stands in (for the collider's rest position). nil if not found.
function RotationService.occupantCell(self: RotationService, id: string): string?
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.id == id then return G.cellForRank(occ.rank) end
	end
	return nil
end

-- Replicate EACH seated human's CURRENT rank to its OWN client (server-authoritative; the client only
-- displays). Per-human now (M5.1): each player gets its own "Rank" attribute via the injected setter, so
-- with a human/bot mix every human reads ITS seat -- not a single shared rank.
function RotationService._syncHumanRank(self: RotationService)
	if not self._setHumanRank then return end
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.kind == "human" and occ.player then
			self._setHumanRank(occ.player, occ.rank)
		end
	end
end

-- Put every occupant at cellForRank(rank). Re-placeable (rotation re-calls this).
function RotationService.placeAll(self: RotationService)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ then self:_placeOccupant(occ) end
	end
	self:_syncHumanRank()
	self:_refreshJerseys()
end

-- ============================================================================================
-- JOIN / LEAVE (M5.1): humans fill seats, bots backfill -- always a full 9-square.
-- ============================================================================================

-- Is `player` already seated? Returns its current rank, or nil. (Idempotent join guard.)
function RotationService.rankOfPlayer(self: RotationService, player: Player): number?
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.kind == "human" and occ.player == player then return rank end
	end
	return nil
end

-- The ENTRY rank for a joining human: the HIGHEST-numbered seat currently held by a BOT (farthest from the
-- King). Humans always outrank bots, so a joiner displaces the lowest-status bot. Returns nil if all 9
-- seats are humans (caller should route the player to the spectator queue -- M5.2).
function RotationService._entryRankForJoin(self: RotationService): number?
	for rank = RANKS, 1, -1 do
		local occ = self.byRank[rank]
		if occ and occ.kind == "bot" then return rank end
	end
	return nil
end

-- JOIN: seat `player` at the entry rank by DISPLACING the bot there (its rig is destroyed). Idempotent: if
-- the player already holds a seat, just returns that rank. Returns the assigned rank, or nil when all 9
-- seats are humans (overflow -> the M5.2 spectator queue owns the player; we leave occupancy untouched).
function RotationService.seatHuman(self: RotationService, player: Player): number?
	local existing = self:rankOfPlayer(player)
	if existing then return existing end

	local rank = self:_entryRankForJoin()
	if not rank then
		print(("[Rotation] JOIN overflow: %s -- all 9 seats are humans (spectator queue owns this player)"):format(player.Name))
		return nil
	end

	local displaced = self.byRank[rank]
	self:_destroyBot(displaced)
	local occ: Occupant = {
		kind = "human", player = player, id = "human_" .. tostring(player.UserId),
		isDummy = false, rank = rank, cell = G.cellForRank(rank),
	}
	self.byRank[rank] = occ
	print(("[Rotation] JOIN: %s seated at entry rank %d (%s); displaced bot %s")
		:format(player.Name, rank, occ.cell, displaced.id))
	self:_placeOccupant(occ)
	-- (Re)attach this human's jersey on every (re)spawn: the BillboardGui lives on the character Head,
	-- so a fresh character needs the label re-created. The occupant record is the live `byRank` slot, so
	-- whatever rank/cell this player holds when a character spawns is reflected (incl. the King mark).
	-- A label attach only -- never touches placement/seating/rotation. Connected once per seated player.
	if not self._jerseyConns then self._jerseyConns = {} end
	if not self._jerseyConns[player] then
		self._jerseyConns[player] = player.CharacterAdded:Connect(function(char)
			char:WaitForChild("Head", 5)
			local current = self:rankOfPlayer(player)
			if current then self:_refreshJerseyFor(self.byRank[current]) end
		end)
	end
	if player.Character then self:_refreshJerseyFor(occ) end
	self:_syncHumanRank()
	self:_refreshJerseys()
	return rank
end

-- LEAVE: free `player`'s seat and BACKFILL it so the rank is never empty. Backfill priority:
--   (1) the injected _backfillHook (M5.2 spectator queue -> seats the longest-waiting spectator), else
--   (2) a fresh bot.
-- The backfilled occupant inherits the leaver's rank/cell (no shifting -- rotation stays a separate
-- mechanism). Returns the occupant now holding the freed rank, or nil if the player wasn't seated.
function RotationService.unseatHuman(self: RotationService, player: Player): Occupant?
	local rank = self:rankOfPlayer(player)
	if not rank then return nil end
	local cell = G.cellForRank(rank)

	-- Drop this human's jersey CharacterAdded hook (the character/jersey go with the leaver).
	if self._jerseyConns and self._jerseyConns[player] then
		self._jerseyConns[player]:Disconnect()
		self._jerseyConns[player] = nil
	end

	-- (1) Hook first (spectator queue). It returns a ready occupant to seat, or nil to fall through to a bot.
	local replacement: Occupant? = nil
	if self._backfillHook then
		replacement = self._backfillHook(rank, cell)
		if replacement then
			replacement.rank = rank
			replacement.cell = cell
			replacement.isDummy = (replacement.kind == "bot")
		end
	end
	-- (2) Default: a fresh bot.
	if not replacement then
		replacement = self:_makeBot(rank)
	end

	self.byRank[rank] = replacement
	print(("[Rotation] LEAVE: %s left rank %d (%s); backfilled with %s %s")
		:format(player.Name, rank, cell, replacement.kind, replacement.id))
	self:_placeOccupant(replacement)
	self:_syncHumanRank()
	self:_refreshJerseys()
	return replacement
end

-- Rotate the queue after a fault (PRD §4.3 / M3 design §4). The occupant who faulted at `faultRank`
-- is pushed to the tail (rank 9 / NW entry square) and every occupant at faultRank+1..9 advances ONE
-- rank toward the King (rank K takes rank K-1's cell). With the fixed 9 occupants this is exactly a
-- cyclic shift of ranks faultRank..9. A fault at rank 1 is a DETHRONE: the rank-2 occupant becomes the
-- new King (rank 1 / C) and onDethrone fires with them. Works for ANY occupant mix (human or bot).
--
-- MECHANISM ONLY: this does not decide WHO faulted (that's fault attribution); the caller passes the rank.
-- After the shift it re-places everyone (incl. seated humans, via the injected per-player teleport).
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

-- Place ONLY one player at their current cell (used on CharacterAdded, when the others already stand).
-- Re-asserts that player's rank attribute too.
function RotationService.placePlayer(self: RotationService, player: Player)
	for rank = 1, RANKS do
		local occ = self.byRank[rank]
		if occ and occ.kind == "human" and occ.player == player then
			self:_placeOccupant(occ)
			if self._setHumanRank then self._setHumanRank(player, occ.rank) end
			self:_refreshJerseyFor(occ)   -- (re)attach the jersey to the fresh character Head
			return
		end
	end
end

-- The cell a seated player currently owns (for spawn placement). nil if not seated.
function RotationService.cellOfPlayer(self: RotationService, player: Player): string?
	local rank = self:rankOfPlayer(player)
	return rank and G.cellForRank(rank) or nil
end

-- The current King (rank 1 / C). Always present (a full 9-square). Used by the serve branch.
function RotationService.kingOccupant(self: RotationService): Occupant
	return self.byRank[1]
end

-- Is the CURRENT King (rank 1) a human? Decides physical serve (human) vs auto-serve (bot). The serve
-- branch keys off this occupant -- NOT a hard-coded single human -- so any human King serves physically
-- and any bot King auto-serves.
function RotationService.isHumanKing(self: RotationService): boolean
	return self.byRank[1].kind == "human"
end

-- The Player currently King (rank 1), or nil if a bot holds the throne. Lets the server hover-serve for the
-- SPECIFIC human King (feed its collider / target its client) rather than "the human".
function RotationService.kingPlayer(self: RotationService): Player?
	local king = self.byRank[1]
	return (king.kind == "human") and king.player or nil
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
