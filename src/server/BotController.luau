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

-- DETERMINISTIC LANDING PREDICTION (server-authoritative; mirrors BallController, changes NO physics).
-- Given an off-centre `offset` and a `standoff` for a planned contact, reproduce EXACTLY the velocity the
-- existing swept collision (`strikeVelocity` + `liftNormal`) would impart, then ballistically solve where
-- that arc returns to the floor. Returns the resolved outgoing velocity, the line-of-centres normal `n`,
-- and the predicted floor-landing XZ -- so the caller can steepen the contact when the landing would be OOB.
-- This does not touch the ball; it only forecasts what the real strike will do, so the actual hit is still
-- resolved by bc:step's swept collision unchanged.

-- liftNormal mirror (BallController.liftNormal): bias the normal up to at least minLift, unit length.
local function liftNormal(n: Vector3): Vector3
	if n.Y >= G.minLift then return n.Unit end
	local h = Vector3.new(n.X, 0, n.Z)
	h = (h.Magnitude > 1e-3) and h.Unit or Vector3.zero
	return (h * math.sqrt(1 - G.minLift * G.minLift) + Vector3.new(0, G.minLift, 0)).Unit
end

-- strikeVelocity mirror (BallController.strikeVelocity): passive rebound + velocity-proportional active power.
local function strikeVelocity(vBall: Vector3, n: Vector3, playerVel: Vector3): Vector3
	local ballPart = vBall - (1 + G.ballRestitution) * (vBall:Dot(n)) * n
	local into = math.max(0, playerVel:Dot(n))
	local vOut = ballPart + G.hitGain * into * n
	if into > G.strikeMoveThreshold then
		local along = vOut:Dot(n)
		if along < G.hitMinPop then vOut = vOut + (G.hitMinPop - along) * n end
	end
	return vOut
end

-- For a planned contact (ball at `contactPoint`, descending `vBall`, aim `aimDir`, a given `offset` +
-- `standoff`), forecast the resolved strike velocity, the predicted floor-landing XZ, and the arc's PEAK
-- height. The contact normal is taken along the COLLIDER's drive direction (colVel) -- this is what the real
-- swept collision sees, because at contact the rising collider sits just behind/below the ball so
-- n = unit(ball - colliderCentre) ~= unit(colVel). (A purely geometric horizontal stand normal badly
-- under-predicts the vertical launch; this colVel normal matches reality, so the loop steers the TRUE arc.)
function BotController._forecast(self, contactPoint: Vector3, vBall: Vector3, aimDir: Vector3, offset: number, standoff: number, restY: number, jumpDur: number): (Vector3, Vector3, number)
	-- The collider velocity at contact = the straight sweep launchPoint -> contactPoint over jumpDur. The
	-- launch point sits `offset+standoff` behind the contact along -aimDir at restY, so colVel is up + toward
	-- the aim; its direction is the contact normal the swept collision resolves along.
	local launchPoint = Vector3.new(
		contactPoint.X - aimDir.X * (offset + standoff),
		restY,
		contactPoint.Z - aimDir.Z * (offset + standoff))
	local colVel = (contactPoint - launchPoint) / math.max(jumpDur, 1e-3)
	local n = (colVel.Magnitude > 1e-4) and liftNormal(colVel.Unit) or Vector3.new(0, 1, 0)

	local vOut = strikeVelocity(vBall, n, colVel)

	-- Ballistic arc from contactPoint with vOut: peak height + where it returns to the floor (y = ballRadius).
	local g = self._bc.gravity
	local peakY = contactPoint.Y + (vOut.Y > 0 and (vOut.Y * vOut.Y) / (2 * g) or 0)
	local A, B, C = -0.5 * g, vOut.Y, contactPoint.Y - G.ballRadius
	local landXZ = Vector3.new(contactPoint.X, 0, contactPoint.Z)
	local disc = B * B - 4 * A * C
	if disc >= 0 then
		local t = math.max((-B + math.sqrt(disc)) / (2 * A), (-B - math.sqrt(disc)) / (2 * A))
		if t > 0 then
			landXZ = Vector3.new(contactPoint.X + vOut.X * t, 0, contactPoint.Z + vOut.Z * t)
		end
	end
	return vOut, landXZ, peakY
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

	-- Aim: outer bot -> the King (C). King bot (C) -> a random OUTER cell, but NEVER the one that just hit the
	-- ball to us (bc.struckCell) -> breaks the 2-player C<->outer ping-pong so different outers get pulled in
	-- instead of the ball funnelling back to the same player. Aim at the cell CENTRE pulled an in-bounds margin
	-- toward the COURT centre (botAimInsetFrac of a half-square), so a clean return lands a margin INSIDE the
	-- court boundary rather than on the far edge where a small error sprays it OOB.
	local aimCell
	if cell == "C" then
		local sender = bc.struckCell                          -- the outer cell that just struck the ball to us
		local choices = {}
		for _, oc in ipairs(G.outerCells) do
			if oc ~= sender then choices[#choices + 1] = oc end
		end
		aimCell = choices[math.random(1, #choices)]           -- a DIFFERENT outer than the sender (no ping-pong)
	else
		aimCell = "C"                                         -- outer bots keep attacking the King
	end
	local aimCtr = G.cellCenter(aimCell)                                  -- XZ at the floor (cell centre)
	local toCourt = Vector3.new(G.origin.X - aimCtr.X, 0, G.origin.Z - aimCtr.Z)
	local inset = G.botAimInsetFrac * (G.squareSize / 2)
	if toCourt.Magnitude > 1e-3 then aimCtr = aimCtr + toCourt.Unit * inset end
	local aimFlat = Vector3.new(aimCtr.X - contactPoint.X, 0, aimCtr.Z - contactPoint.Z)
	local aimDir = (aimFlat.Magnitude > 1e-3) and aimFlat.Unit or Vector3.new(0, 0, -1)

	-- Hits shouldn't be robotically perfect: jitter the aim by a small random yaw so returns scatter naturally
	-- around the target (sometimes near a cell edge, occasionally nicking a neighbour). The in-bounds forecast
	-- below still reins in any spill past the court, so jitter adds life without spraying it OOB.
	if G.botAimJitterDeg and G.botAimJitterDeg > 0 then
		local ang = (math.random() * 2 - 1) * math.rad(G.botAimJitterDeg)
		local cs, sn = math.cos(ang), math.sin(ang)
		aimDir = Vector3.new(aimDir.X * cs - aimDir.Z * sn, 0, aimDir.X * sn + aimDir.Z * cs)
	end

	local restY = G.cellCenter(cell).Y + G.botRestColliderY
	local rise = math.max(contactPoint.Y - restY, 0.5)
	local jumpDur = rise / math.max(G.botJumpVelocity, 1)                 -- time to rise from restY to contactY
	local vBall = bc:currentVelocity()                                   -- the descending ball velocity at contact

	-- DETERMINISTIC CORRECTION (mirrors BallController; no physics change). Forecast the resolved strike's arc
	-- and adjust the contact so it BOTH stays under the ceiling AND lands in the court. Two opposing levers on
	-- the drive flatness (standoff): a STEEPER drive peaks higher but lands shorter; a FLATTER drive peaks lower
	-- but lands longer. We resolve the tension in priority order each pass, up to botLandPredictIters:
	--   1) PEAK first -- if the forecast arc would near the gym ceiling (peak > botLandPeakCap), FLATTEN
	--      (raise standoff) to shed vertical energy sideways. The ceiling fix is non-negotiable.
	--   2) then BOUNDS -- if it would leave the court, STEEPEN (shrink standoff + offset) to drop it in-cell.
	-- No Math.random. The hit itself is still resolved by bc:step's swept collision; this only picks the
	-- offset/standoff. (botJumpVelocity caps the raw energy so the peak stays reachable without the ceiling.)
	local offset = G.botOffCenterFrac * (G.hitZoneRadius + G.ballRadius)
	local standoff = G.botStandoff
	local courtExtent = 1.5 * G.squareSize
	local safeExtent = courtExtent - G.botLandMarginFrac * (G.squareSize / 2)
	local minOffset = G.botMinOffCenterFrac * (G.hitZoneRadius + G.ballRadius)
	for _ = 1, math.max(G.botLandPredictIters, 0) do
		local _vOut, landXZ, peakY = self:_forecast(contactPoint, vBall, aimDir, offset, standoff, restY, jumpDur)
		local overCeiling = peakY > G.botLandPeakCap
		local outOfBounds = math.abs(landXZ.X) > safeExtent or math.abs(landXZ.Z) > safeExtent
		if not overCeiling and not outOfBounds then break end
		if overCeiling then
			standoff /= G.botLandSteepenStep                       -- flatten: a lower, longer arc (shed vertical)
		else
			offset = math.max(offset * G.botLandSteepenStep, minOffset)
			standoff *= G.botLandSteepenStep                       -- steepen: a tighter, shorter arc (pull in-bounds)
		end
	end

	-- Off-centre stand: the bot's centre is on the FAR side of the ball from the aim, so the line of centres
	-- n = unit(ball - center) points toward the aim (using the corrected, possibly-steepened offset).
	local standXZ = Vector3.new(contactPoint.X - aimDir.X * offset, 0, contactPoint.Z - aimDir.Z * offset)

	local miss = (math.random() < G.botMissChance)

	-- The bot doesn't just jump STRAIGHT up -- it DRIVES into the ball ALONG the aim line, so the collider's
	-- velocity (and thus the line-of-centres strike) carries a strong horizontal component toward the aim
	-- (a vertical-only pop barely bends the ball -> it falls back into the same square). We sweep the collider
	-- on a straight line from a launch point on the FAR/low side to the contact point, arriving at tContact:
	-- the launch point sits the (corrected) `standoff` behind the off-centre stand (further along -aimDir) and
	-- at restY, so colVel at contact points UP + toward the aim (+aimDir) -> the strike sends the ball over the
	-- pipe toward the aim cell. (rise/jumpDur were computed above for the landing forecast; reuse them.)
	local launchPoint = Vector3.new(
		standXZ.X - aimDir.X * standoff,
		restY,
		standXZ.Z - aimDir.Z * standoff)

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

-- LIFELIKE IDLE motion (idle ready-stance + anticipatory ball tracking). Call AFTER :update each Heartbeat.
-- For every bot occupant that is NOT mid-swing (the active receiver, handled by :update/driveOccupant), this
-- drives a cheap, DETERMINISTIC "alive" motion via rotation:idleOccupant so the whole grid reads as live, not
-- just the receiver:
--   * a continuous toe-bob (vertical) + an elliptical weight-sway (XZ) around the bot's home stand, and
--   * an occasional READY STEP -- a short out-and-back shuffle to a spot ~botIdleStepDist from home, and
--   * an anticipatory LEAN/step toward the live ball's XZ (a fraction of the budget) so the grid reacts.
-- Every phase is seeded from the bot's RANK (no Math.random / os.time randomness in the loop -- just a
-- continuous clock for the oscillation), so bots don't move in lockstep. The XZ offset is CLAMPED to
-- (squareSize/2 - botIdleClampMargin) so a bot never drifts out of its square / over a pipe. `ballXZ` is the
-- live ball's XZ (or nil when the ball is dead) -- tracking only engages while the ball is live.
function BotController.update_idle(self, dt: number, ballXZ: Vector3?)
	local rotation = self._rotation
	local now = os.clock()
	local clampMax = G.squareSize / 2 - G.botIdleClampMargin

	for rank = 1, 9 do
		local occ = rotation.byRank[rank]
		if occ and occ.isDummy and not self._swings[occ.id] then
			-- Per-bot deterministic phase seed from the rank so the 8 bots are out of sync.
			local seed = occ.rank * 1.2345

			-- Continuous toe-bob (raised |sin| so the body bobs UP from rest, never sinks below the floor).
			local bob = math.abs(math.sin(now * G.botIdleBobSpeed + seed)) * G.botIdleBobHeight

			-- Elliptical weight-sway around home (different X/Z rates for an organic shift, not a circle).
			local sx = math.sin(now * G.botIdleSwaySpeed + seed) * G.botIdleSwayRadius
			local sz = math.cos(now * G.botIdleSwaySpeed * 0.8 + seed * 1.7) * G.botIdleSwayRadius

			-- Ready step: a short out-and-back shuffle once per botIdleStepInterval. The step direction is
			-- derived deterministically from the (advancing) step index + rank, so feet actually move to a new
			-- spot and return -- no RNG. Within the step window we ease out then back (sin over 0..pi).
			local cycle = now / G.botIdleStepInterval + seed
			local stepIdx = math.floor(cycle)
			local frac = cycle - stepIdx                     -- 0..1 through the current interval
			local stepX, stepZ = 0, 0
			local stepWindow = G.botIdleStepDur / G.botIdleStepInterval
			if frac < stepWindow then
				local s = math.sin((frac / stepWindow) * math.pi)   -- 0 -> 1 -> 0 out-and-back
				-- Deterministic direction for this step from the step index + rank (8 compass-ish dirs).
				local ang = (stepIdx * 2.39996 + seed)               -- golden-angle-ish spread, deterministic
				stepX = math.cos(ang) * G.botIdleStepDist * s
				stepZ = math.sin(ang) * G.botIdleStepDist * s
			end

			local offX = sx + stepX
			local offZ = sz + stepZ

			-- Anticipatory ball-tracking: bias a fraction of the budget toward the live ball's XZ so the bot
			-- leans/steps INTO the rally. Capped so tracking never alone pushes the bot out of its square.
			local leanTarget: Vector3? = nil
			if ballXZ then
				local home = G.cellCenter(G.cellForRank(occ.rank))
				local toBall = Vector3.new(ballXZ.X - home.X, 0, ballXZ.Z - home.Z)
				if toBall.Magnitude > 1e-3 then
					local dir = toBall.Unit
					offX += dir.X * G.botTrackLeanFrac * clampMax
					offZ += dir.Z * G.botTrackLeanFrac * clampMax
					leanTarget = ballXZ
				end
			end

			-- Clamp the XZ offset inside the cell so the bot can never drift over a pipe / out of position.
			offX = math.clamp(offX, -clampMax, clampMax)
			offZ = math.clamp(offZ, -clampMax, clampMax)

			rotation:idleOccupant(occ.id, Vector3.new(offX, 0, offZ), bob, leanTarget)
		end
	end
end

return BotController
