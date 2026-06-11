--!strict
-- ServerScriptService.NineSquare.BotController
-- PHYSICAL bot hitter (rework). Bots no longer "artificially" volley via bc:launch. Instead each bot that
-- intercepts a descending ball is given a REAL moving hit-sphere collider -- the SAME shape the human
-- carries (`{ center, radius = hitZoneRadius, vel }`) -- which the server drives to an OFF-CENTER stand
-- position relative to the incoming ball and then JUMPS up into the contact point with `botJumpVelocity`.
-- Those bot colliders are folded into the list passed to `bc:step(dt, colliders)` ALONGSIDE the human
-- colliders, so the EXISTING swept, velocity-proportional collision (`BallController:strikeVelocity`)
-- resolves the bot hit. No bc:launch.
--
-- AIM EMERGES FROM THE OFF-CENTER CONTACT. The outgoing ball leaves along the line of centres
-- `n = unit(ball - center)`. To send the ball toward an aim cell, the bot stands on the FAR side of the
-- ball from the aim, so its centre is `contactPoint - aimDir * offset` and `n` points toward the aim. The
-- jump velocity supplies the force (through hitGain). Outer bot aims at C; King bot (C) aims at a random
-- outer cell -- exactly like a player steering with off-centre contact.
--
-- Per Heartbeat (BEFORE bc:step) NineSquareServer calls BotController:update(dt); it returns the active bot
-- colliders to merge with the human's. The body is kept synced to the collider (move feet + leap) so the
-- bot reads as a real hitter. MISS (prob botMissChance): the bot under-jumps / mistimes so its collider
-- never reaches the ball -> no contact -> the ball falls -> the existing onLand floor fault -> rotation.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

export type BotCollider = { center: Vector3, radius: number, vel: Vector3, player: Player? }

local BotController = {}
BotController.__index = BotController

-- A bot's in-progress swing at one descent.
type Swing = {
	id: string,             -- the bot occupant id
	cell: string,           -- the square the swing defends
	startT: number,         -- the Flight arc's startT this swing is bound to (one swing per descent)
	tContact: number,       -- server time the ball reaches the contact height (descending)
	contactPoint: Vector3,  -- ball position at tContact (X, contactY, Z)
	standXZ: Vector3,        -- the off-centre stand position (XZ; Y = restY): collider/feet target
	aimDir: Vector3,        -- flattened aim direction (drive direction + body lean)
	restY: number,          -- collider Y at the ground/rest (the drive rises from here)
	launchPoint: Vector3,   -- where the collider starts its straight drive into the ball (far/low side)
	jumpDur: number,        -- seconds the drive takes (launchPoint -> contactPoint)
	prevCenter: Vector3,    -- last frame's collider centre (to derive vel)
	miss: boolean,          -- this descent is a deliberate miss (under-jump -> no contact)
	done: boolean,          -- the swing has finished (contact resolved or window passed) -> snap home
}

-- `rotation` is the RotationService instance (occupantAtCell / driveOccupant / restOccupant / occupantCell).
-- `bc` is the BallController.
function BotController.new(rotation, bc)
	local self = setmetatable({}, BotController)
	self._rotation = rotation
	self._bc = bc
	self._swings = {} :: { [string]: Swing }   -- bot id -> active swing (one at a time per bot)
	-- The startT of the Flight arc we last committed a swing for, so we arm exactly one swing per descent.
	self._lastCommittedStartT = nil :: number?
	-- Optional save hook (visual): fired with the bot's struck cell when its physical hit clears the ball
	-- out of its square. NineSquareServer wires it to the last-saved-square pipe highlight. (Notification
	-- only; the actual save signal is bc.onClear -- this is kept for back-compat but is now unused.)
	self.onVolley = nil :: ((cell: string) -> ())?
	return self
end

-- Solve for the server time at which the current Flight arc reaches height `y` on the DESCENDING leg.
-- Returns nil if the arc never reaches `y` going down (shouldn't happen for a normal volley arc).
function BotController._descentTimeToHeight(self, y: number): number?
	local bc = self._bc
	local g = bc.gravity
	-- pos.Y(t) = p0.Y + v0.Y * t - 0.5 g t^2, t measured from bc.startT.
	-- Solve 0.5 g t^2 - v0.Y t + (y - p0.Y) = 0 ; take the LATER root (descending).
	local A = 0.5 * g
	local B = -bc.v0.Y
	local C = y - bc.p0.Y
	local disc = B * B - 4 * A * C
	if disc < 0 then return nil end
	local sq = math.sqrt(disc)
	local tLate = (-B + sq) / (2 * A)   -- larger root = descending crossing
	if tLate <= 0 then return nil end
	return bc.startT + tLate
end

-- Ball position along the current arc at server time `tAbs`.
function BotController._ballPosAt(self, tAbs: number): Vector3
	local bc = self._bc
	local t = tAbs - bc.startT
	return bc.p0 + bc.v0 * t + Vector3.new(0, -0.5 * bc.gravity * t * t, 0)
end

-- Try to commit a NEW swing for this descent: the ball is in Flight, descending, predicted to land in a
-- BOT square. We plan the contact point + the off-centre stand + the aim, then drive it over the descent.
function BotController._tryCommit(self)
	local bc = self._bc
	if bc.phase ~= "Flight" then return end
	if self._lastCommittedStartT == bc.startT then return end   -- already committed this descent
	if bc:currentVelocity().Y >= 0 then return end              -- only plan once the ball is descending

	-- Which square will it land in? Prefer the live predicted landing cell.
	local cell = bc.targetCell
	if not cell then return end
	local occ = self._rotation:occupantAtCell(cell)
	if not occ or not occ.isDummy then return end               -- only BOT squares; the human volleys physically

	-- Predict the contact: where the ball crosses the contact height (frameHeight) on the way down.
	local contactY = G.frameHeight
	local tContact = self:_descentTimeToHeight(contactY)
	if not tContact then return end
	-- If we've already passed the contact time this descent, it's too late to plan a hit -> let it fall.
	if tContact <= bc:_serverNow() then
		self._lastCommittedStartT = bc.startT
		return
	end
	local contactPoint = self:_ballPosAt(tContact)
	contactPoint = Vector3.new(contactPoint.X, contactY, contactPoint.Z)

	-- Aim: outer bot -> centre (C); King bot (C) -> a random outer cell.
	local aimCell = (cell == "C") and G.outerCells[math.random(1, #G.outerCells)] or "C"
	local aimPoint = G.cellFramePoint(aimCell)
	local aimFlat = Vector3.new(aimPoint.X - contactPoint.X, 0, aimPoint.Z - contactPoint.Z)
	local aimDir = (aimFlat.Magnitude > 1e-3) and aimFlat.Unit or Vector3.new(0, 0, -1)

	-- Off-centre stand: the bot's centre must be on the FAR side of the ball from the aim, so the line of
	-- centres n = unit(ball - center) points toward the aim. offset is a fraction of (hitZoneRadius +
	-- ballRadius) -- clearly off-centre yet still overlapping so the swept collision strikes.
	local offset = G.botOffCenterFrac * (G.hitZoneRadius + G.ballRadius)
	local standXZ = Vector3.new(contactPoint.X - aimDir.X * offset, 0, contactPoint.Z - aimDir.Z * offset)

	local restY = G.cellCenter(cell).Y + G.botRestColliderY
	local miss = (math.random() < G.botMissChance)

	-- The bot doesn't just jump STRAIGHT up -- it DRIVES into the ball ALONG the aim line, so the collider's
	-- velocity (and thus the line-of-centres strike) carries a strong horizontal component toward the aim
	-- (a vertical-only pop barely bends the ball -> it falls back into the same square). We sweep the collider
	-- on a straight line from a launch point on the FAR/low side to the contact point, arriving at tContact:
	-- the launch point sits `botStandoff` behind the off-centre stand (further along -aimDir) and at restY,
	-- so colVel at contact points UP + toward the aim (+aimDir) -> the strike sends the ball over the pipe
	-- toward the aim cell.
	local rise = math.max(contactPoint.Y - restY, 0.5)
	local jumpDur = rise / math.max(G.botJumpVelocity, 1)             -- time to rise from restY to contactY
	local launchPoint = Vector3.new(
		standXZ.X - aimDir.X * G.botStandoff,
		restY,
		standXZ.Z - aimDir.Z * G.botStandoff)

	self._swings[occ.id] = {
		id = occ.id,
		cell = cell,
		startT = bc.startT,
		tContact = tContact,
		contactPoint = contactPoint,
		standXZ = standXZ,
		aimDir = aimDir,
		restY = restY,
		launchPoint = launchPoint,
		jumpDur = jumpDur,
		prevCenter = launchPoint,
		miss = miss,
		done = false,
	}
	self._lastCommittedStartT = bc.startT
	if miss then
		print(("[Bot] %s SWING(miss) defending %s (under-jump -> floor fault)"):format(occ.id, cell))
	else
		print(("[Bot] %s SWING defending %s -> aim %s (off-centre physical hit)"):format(occ.id, cell, aimCell))
	end
end

-- Advance one active swing this frame: reposition toward the launch point, then DRIVE the collider on a
-- straight sweep launchPoint -> contactPoint (up + toward the aim), arriving at tContact. Returns the bot's
-- live collider for this frame, or nil if the swing is idle/finished (no collider emitted). Also drives the
-- bot body to match (move feet + leap), and snaps it home when the swing ends.
function BotController._advance(self, sw: Swing, dt: number): BotCollider?
	local bc = self._bc
	-- The swing is bound to ONE descent. If a new arc started (a hit relaunched the ball, or a re-serve),
	-- the descent is over -> finish the swing.
	if bc.startT ~= sw.startT or bc.phase == "Rest" then
		sw.done = true
	end

	local now = bc:_serverNow()
	local prev = sw.prevCenter

	-- Drive timing: park at the launch point until `driveStart`, then sweep STRAIGHT to the contact point
	-- over `jumpDur`, arriving at tContact (minus an optional lead so the collider is still rising THROUGH
	-- the ball at contact). The sweep direction is up + toward the aim (the bot drives INTO the ball along
	-- the aim line), so the line-of-centres strike sends the ball over the pipe toward the aim cell.
	local driveStart = sw.tContact - sw.jumpDur - G.botJumpLeadTime

	local center: Vector3
	if now < driveStart then
		-- Reposition phase: visibly slide the feet toward the launch point (off-centre, on the aim's far side).
		local toLaunch = sw.launchPoint - prev
		local maxStep = G.botMoveSpeed * dt
		if toLaunch.Magnitude <= maxStep then
			center = sw.launchPoint
		else
			center = prev + toLaunch.Unit * maxStep
		end
	else
		-- Drive phase: linear sweep launchPoint -> contactPoint, parameter s in 0..1 by elapsed/jumpDur.
		local s = math.clamp((now - driveStart) / math.max(sw.jumpDur, 1e-3), 0, 1)
		-- MISS: under-drive -- stop the sweep well short of the ball so the spheres never overlap (no contact).
		if sw.miss then s = math.min(s, 0.3) end
		center = sw.launchPoint:Lerp(sw.contactPoint, s)
	end

	local vel = (dt > 1e-5) and ((center - prev) / dt) or Vector3.zero
	sw.prevCenter = center

	-- Drive the body so the player SEES the bot run-and-leap into the ball (head tracks the collider; lean +
	-- arm-raise ramp up as the collider nears the contact height). A miss still moves + half-leaps (mistimed).
	local raise = 0
	if sw.contactPoint.Y > sw.restY + 1e-3 then
		raise = math.clamp((center.Y - sw.restY) / (sw.contactPoint.Y - sw.restY), 0, 1)
	end
	local leanTarget = self:_ballPosAt(now)
	self._rotation:driveOccupant(sw.id, center, leanTarget, raise)

	-- Finish the swing once the contact window has clearly passed (ball well below the contact height) so
	-- a missed/late swing snaps home and stops emitting a collider.
	if now > sw.tContact + 0.25 then
		sw.done = true
	end

	if sw.done then
		self._rotation:restOccupant(sw.id)
		return nil
	end

	return { center = center, radius = G.hitZoneRadius, vel = vel, player = nil }
end

-- Per-Heartbeat driver. Call BEFORE bc:step each Heartbeat. Commits a new swing for a fresh descent toward
-- a bot square, advances every active swing, and RETURNS the active bot colliders to be merged with the
-- human colliders for bc:step (so the same swept collision resolves bot hits). NineSquareServer is
-- responsible for combining + passing them in.
function BotController.update(self, dt: number): { BotCollider }
	self:_tryCommit()

	local colliders: { BotCollider } = {}
	for id, sw in pairs(self._swings) do
		local col = self:_advance(sw, dt)
		if col then
			table.insert(colliders, col)
		end
		if sw.done then
			self._swings[id] = nil
		end
	end
	return colliders
end

return BotController
