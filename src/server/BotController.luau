--!strict
-- ServerScriptService.NineSquare.BotController
-- M4 step 1 (the core): make the 8 bot-occupied squares actually VOLLEY incoming balls (with a simple
-- aim rule) and MISS sometimes, so real rallies happen, faults rotate the grid, and a solo human climbs.
--
-- Server-authoritative + deterministic: the bot NEVER touches the ball physically (no hit-sphere). Each
-- Heartbeat, after bc:step, NineSquareServer calls BotController.resolve(...). When the ball is in Flight,
-- DESCENDING through the contact window (~frameHeight) over a BOT-occupied square, the bot resolves its
-- single touch ONCE per descent:
--   * Hit (prob 1 - botMissChance): launch the ball from its current point toward the aim target's frame
--     point -- outer bot -> center (C); King bot -> a random outer square -- reusing the M3 serve ballistic
--     (horizontal toward the target + an upward pop for hang time). That sends the ball ONWARD so the aim
--     square's occupant must then volley -> a real rally.
--   * Miss (prob botMissChance): do nothing -- the ball falls to the floor in the bot's square -> the
--     existing BallController.onLand -> floor fault -> RotationService.rotateOnFault (already wired in M3).
--
-- The HUMAN's square is NOT handled here (only `.isDummy` occupants); the human still volleys via the
-- physical swept collision in BallController:step. BallController physics/collision are untouched -- the
-- bot volley is just a computed bc:launch (same as the M3 King auto-serve).
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local BotController = {}
BotController.__index = BotController

-- `rotation` is the RotationService instance (for occupantAtCell). `bc` is the BallController.
function BotController.new(rotation, bc)
	local self = setmetatable({}, BotController)
	self._rotation = rotation
	self._bc = bc
	-- Debounce: the startT of the Flight arc we last resolved a bot touch on. A new bc:launch resets
	-- bc.startT, so a fresh descent always differs -> exactly one bot touch per descent.
	self._lastResolvedStartT = nil
	return self
end

-- Compute and launch a deterministic ballistic volley from `fromPoint` toward `targetCell`'s floor, peaking
-- `serveArcApex` above the launch point (so the ball clearly arcs up over the frame and drops into the aim
-- square). Mirrors NineSquareServer.serveToTarget but launches from the live contact point, not C. Reuses
-- bc:launch (M1 physics unchanged) -- we only compute the v0 that produces the arc.
function BotController._volley(self, fromPoint: Vector3, targetCell: string)
	local landCenter = G.cellCenter(targetCell)
	local to = Vector3.new(landCenter.X, G.ballRadius, landCenter.Z)   -- the floor-resting point in the aim square
	local g = workspace.Gravity
	local peakY = fromPoint.Y + G.serveArcApex
	local rise = math.max(peakY - fromPoint.Y, 1)
	local vy = math.sqrt(2 * g * rise)                                 -- vertical speed to reach `rise` above launch
	local tUp = vy / g
	local tDown = math.sqrt(2 * math.max(peakY - to.Y, 0) / g)
	local tTotal = math.max(tUp + tDown, 0.1)
	local horiz = Vector3.new(to.X - fromPoint.X, 0, to.Z - fromPoint.Z) / tTotal
	local v0 = Vector3.new(horiz.X, vy, horiz.Z)
	self._bc:launch(fromPoint, v0)
end

-- Per-Heartbeat resolver. Call AFTER bc:step each Heartbeat. Returns true if a bot took a touch this frame
-- (volley OR a deliberate miss were resolved), false otherwise. NineSquareServer uses the return only for
-- logging clarity; the rally loop reacts to bc:launch / onLand exactly as before.
function BotController.resolve(self): boolean
	local bc = self._bc
	if bc.phase ~= "Flight" then return false end

	-- One bot touch per descent: skip if we've already resolved THIS Flight arc (same launch startT).
	if self._lastResolvedStartT == bc.startT then return false end

	local vel = bc:currentVelocity()
	if vel.Y >= 0 then return false end                 -- only intercept while DESCENDING

	-- In the contact window? At/just around the frame height (a small band), like a real volley reach.
	local ballPos = bc.ball.Position
	if math.abs(ballPos.Y - G.frameHeight) > G.botContactBand then return false end

	-- Which square is the ball over right now? (Fall back to the predicted landing cell at the edges.)
	local cell = G.cellAtPosition(Vector3.new(ballPos.X, 0, ballPos.Z)) or bc.targetCell
	if not cell then return false end

	-- Only a BOT square resolves here. The human's square is left to the physical volley (`.isDummy` is
	-- false for the human), and an unknown/out-of-court XZ has no occupant.
	local occ = self._rotation:occupantAtCell(cell)
	if not occ or not occ.isDummy then return false end

	-- Arm: this descent is now resolved (whether we hit or miss), so we never double-touch one drop.
	self._lastResolvedStartT = bc.startT

	-- Miss (prob botMissChance): do nothing -> the ball falls to the floor in this square -> onLand fault.
	if math.random() < G.botMissChance then
		print(("[Bot] %s MISS in %s -> floor fault"):format(occ.id, cell))
		return true
	end

	-- Hit: aim outer -> center; King (C) -> a random outer square. Launch from the live contact point.
	local aimCell = (cell == "C") and G.outerCells[math.random(1, #G.outerCells)] or "C"
	self:_volley(ballPos, aimCell)
	-- Juice: LEAP the bot's body up to the live contact point so it visibly meets + strikes the ball
	-- (apex synced to this bc:launch). Cosmetic only -- CanCollide stays false; the hit is server-resolved.
	self._rotation:hopOccupant(occ.id, ballPos)
	print(("[Bot] %s VOLLEY %s -> %s"):format(occ.id, cell, aimCell))
	return true
end

return BotController
