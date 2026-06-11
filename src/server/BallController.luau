--!strict
-- ServerScriptService.NineSquare.BallController
--
-- Owns the single anchored ball and ALL of its motion. This object is pure physics + replication --
-- it knows nothing about game rules (scoring, faults, sounds, square highlights, when to re-serve).
-- It reports what happened through two optional callbacks and lets the game react.
--
-- Public contract
--   BallController.new() -> BallController
--   :hoverAt(point: Vector3)        park the ball, hovering in place (phase "Live")
--   :resetToServe()                 hover at the serve point (centre, frame height)
--   :launch(fromPoint, v0)          strike: begin a projectile arc (phase "Flight")
--   :step(playerColliders?)         advance the simulation one tick; call every Heartbeat. Pass the
--                                   players' moving hit-spheres (from HitResolver) so a contact is a
--                                   real penetration+rebound collision, resolved alongside the surfaces.
--   :resync()                       replicate the current ball state to clients
--   .ball: Part                     the rendered ball (read-only)
--   .phase: string                  "Live" | "Flight" | "Settling" | "Rest" (read-only)
--   .struckCell / .targetCell       last struck square / predicted landing square (read-only)
--   .ownerCell                      the square the ball LEGALLY belongs to (read-only). Reset to struckCell
--                                   on each launch; transfers to a new cell ONLY when the ball crosses a
--                                   cell boundary ABOVE the pipe (centre Y >= G.pipeClearHeight). A low
--                                   deflect that slides UNDER a pipe into a neighbour does NOT transfer it,
--                                   so the fault path can keep the ball on the hitter (no wrong knock-out).
--   .onLand: ((landedCell: string?, struckCell: string?, ownerCell: string?) -> ())?
--                                   fires ONCE, on the first floor contact after a launch. The game
--                                   classifies legal / self-fault / out-of-bounds (using ownerCell, NOT the
--                                   raw landing XZ) and plays feedback.
--   .onRest: (() -> ())?            fires ONCE, when the ball has bounced out its energy and stopped.
--                                   The game decides if/when to re-serve.
--   .onPlayerHit: ((struckCell: string?, targetCell: string?, wasServe: boolean) -> ())?
--                                   fires after a PLAYER contact launches the ball (NOT a bot/auto volley,
--                                   which goes through :launch directly). `wasServe` is true when the hit
--                                   put a parked Live ball into play (the human King's jump-serve) vs a
--                                   mid-flight return. Notification only -- physics is unchanged.
--   .onClear: ((struckCell: string?, ownerCell: string?) -> ())?
--                                   fires ONCE per launch, the moment the ball LEGALLY clears its hitter's
--                                   square over a pipe (ownerCell first transfers off struckCell). This is
--                                   the authoritative "save" signal: a low deflect under a pipe never fires
--                                   it (ownership doesn't transfer), so the save highlight agrees with the
--                                   fault attribution. Notification only.
--
-- Motion: a true projectile arc under gravity that reflects off EVERY solid surface in the arena --
-- the overhead frame pipes, the gym walls, ceiling, backboards/rims, and the floor. Floor contacts
-- additionally shed horizontal speed (ground friction) and, once slow enough, park the ball at rest.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

export type PlayerCollider = { center: Vector3, radius: number, vel: Vector3, player: Player }

local SURFACE_RESTITUTION = 0.6   -- bounciness off the rigid surfaces (frame pipes, walls, ceiling, hoops)

function BallController.new()
	local self = setmetatable({}, BallController)
	local ball = Instance.new("Part")
	ball.Name = "Ball"; ball.Shape = Enum.PartType.Ball; ball.Anchored = true; ball.CanCollide = false
	ball.Size = Vector3.new(G.ballRadius*2, G.ballRadius*2, G.ballRadius*2)
	-- matte coral: a near-white colour trips the scene Bloom and glows like a light source
	ball.Color = Color3.fromRGB(235, 92, 74); ball.Material = Enum.Material.Plastic
	ball.Parent = workspace:WaitForChild("NineSquare")
	self.ball = ball
	self.gravity = workspace.Gravity
	self.phase = "Live"                 -- Live (hover) | Flight (rally) | Settling (post-land bounce) | Rest
	self.restPoint = G.cellFramePoint("C")
	self.p0 = self.restPoint
	self.v0 = Vector3.zero
	self.startT = 0
	self.struckCell = "C"               -- square the ball was last struck from
	self.targetCell = "C"               -- predicted / current landing square (for the client highlight)
	self.ownerCell = "C"                -- square the ball legally belongs to (over-pipe entry); see contract
	self._lastCell = "C"                -- the ball's XZ cell on the previous step (to detect boundary crossings)
	self.onLand = nil :: ((string?, string?, string?) -> ())?   -- game wires these; see the contract above
	self.onRest = nil :: (() -> ())?
	self.onPlayerHit = nil :: ((string?, string?, boolean) -> ())?
	self.onClear = nil :: ((string?, string?) -> ())?
	ball.Position = self.restPoint
	return self
end

local function kindForPhase(phase: string): string
	if phase == "Live" then return "live"
	elseif phase == "Flight" then return "flight"
	else return "idle" end              -- Settling / Rest: ball still renders, but no strike telegraph
end

function BallController:resync()
	BallSync:FireAllClients({ kind = kindForPhase(self.phase), targetCell = self.targetCell, frameHeight = G.frameHeight })
end

function BallController:hoverAt(point: Vector3)
	self.phase = "Live"; self.restPoint = point; self.v0 = Vector3.zero
	self.ball.Position = point
	self.targetCell = G.cellAtPosition(point) or "C"
	self:resync()
end

function BallController:resetToServe()
	self:hoverAt(G.cellFramePoint("C"))
end

-- predicted floor-landing square for the current p0/v0 (ignores future bounces)
function BallController:_predictLandCell(): string?
	local A, B, C = -0.5 * self.gravity, self.v0.Y, self.p0.Y - G.ballRadius
	local disc = B*B - 4*A*C
	if disc < 0 then return nil end
	local t = math.max((-B + math.sqrt(disc))/(2*A), (-B - math.sqrt(disc))/(2*A))
	local land = self.p0 + self.v0 * t
	return G.cellAtPosition(Vector3.new(land.X, 0, land.Z))
end

-- Strike: launch from a contact point with an initial velocity. A strike on a live ball (Live/Flight)
-- starts/continues a rally; a strike on an already-resolved ball (Settling/Rest) just bats it around
-- again -- no new landing is reported, so the rally is not re-scored and any pending re-serve is moot.
function BallController:launch(fromPoint: Vector3, v0: Vector3)
	self.p0 = fromPoint; self.v0 = v0
	self.startT = workspace:GetServerTimeNow()
	self.struckCell = G.cellAtPosition(fromPoint)
	-- A fresh strike resets ownership to the hitter's square: the ball is the hitter's responsibility until
	-- it legally clears a pipe into another square. _lastCell seeds the boundary-crossing tracker at the
	-- launch XZ so the first over-pipe crossing is detected cleanly.
	self.ownerCell = self.struckCell
	self._lastCell = self.struckCell
	if self.phase == "Settling" or self.phase == "Rest" then
		self.phase = "Settling"
	else
		self.phase = "Flight"
		self.targetCell = self:_predictLandCell()
	end
	self:resync()
end

-- The server clock the ball's motion is parameterised on (== the startT reference). Exposed so the bot
-- driver can time its jump against the ball's arc using the exact same clock. Read-only; no physics change.
function BallController:_serverNow(): number
	return workspace:GetServerTimeNow()
end

-- The ball's instantaneous velocity right now (zero unless it's in motion).
function BallController:currentVelocity(): Vector3
	if self.phase == "Flight" or self.phase == "Settling" then
		return self.v0 + Vector3.new(0, -self.gravity * (workspace:GetServerTimeNow() - self.startT), 0)
	end
	return Vector3.zero
end

-- Bias a contact normal upward so a clean bump tends to arc the ball up and over: clamp its vertical
-- component to at least minLift, keeping it unit length. Mirrors the old HitResolver bias.
local function liftNormal(n: Vector3): Vector3
	if n.Y >= G.minLift then return n.Unit end
	local h = Vector3.new(n.X, 0, n.Z)
	h = (h.Magnitude > 1e-3) and h.Unit or Vector3.zero
	return (h * math.sqrt(1 - G.minLift * G.minLift) + Vector3.new(0, G.minLift, 0)).Unit
end

-- The outgoing ball velocity from a contact along the line of centres `n`. The impulse is split in two
-- so energy only comes from the player's MOTION, never from a still body:
--   * passive rebound -- the ball's own incoming velocity reflects off the player with ballRestitution
--     (<= 1), so a motionless player behaves like a surface and the ball leaves SLOWER than it arrived.
--   * active power     -- the player's approach speed toward the ball (its component along n) adds
--     hitGain * that speed along n, so a faster drive hits harder (a still player adds nothing).
-- hitMinPop floors the outgoing speed only for an intentional strike (approach > strikeMoveThreshold),
-- so a clean drive always stays in play while a passive/glancing contact just bounces naturally.
local function strikeVelocity(vBall: Vector3, n: Vector3, playerVel: Vector3): Vector3
	local ballPart = vBall - (1 + G.ballRestitution) * (vBall:Dot(n)) * n   -- passive: never gains energy
	local into = math.max(0, playerVel:Dot(n))                              -- player's approach speed toward the ball
	local vOut = ballPart + G.hitGain * into * n                            -- active power, proportional to motion
	if into > G.strikeMoveThreshold then                                    -- only an intentional strike gets the floor
		local along = vOut:Dot(n)
		if along < G.hitMinPop then vOut = vOut + (G.hitMinPop - along) * n end
	end
	return vOut
end

-- Every rigid surface the ball bounces off EXCEPT the floor (the floor is a robust ground plane in
-- step() -- a thin floor box would let a fast-descending ball tunnel straight through). Includes the
-- frame pipes + the gym's rigid parts (ceiling, walls, backboards, rims); glass + neon pass through.
function BallController:_surfaces(): { BasePart }
	local list = {}
	local ns = self.ball.Parent
	local frame = ns and ns:FindFirstChild("Frame")
	if frame then
		for _, b in ipairs(frame:GetChildren()) do if b:IsA("BasePart") then table.insert(list, b) end end
	end
	local gym = workspace:FindFirstChild("Gym")
	if gym then
		for _, p in ipairs(gym:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "Floor"
				and p.Material ~= Enum.Material.Glass and p.Material ~= Enum.Material.Neon then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- Sphere-vs-(axis-aligned)-box test against the rigid surfaces (not the floor). Returns the resolved
-- position + reflected velocity for the first surface the ball is penetrating while moving into it,
-- or nil. These surfaces all bounce elastically; the floor is handled as a ground plane in step().
function BallController:_collide(pos: Vector3, vel: Vector3): ({ pos: Vector3, vel: Vector3 })?
	local r = G.ballRadius
	for _, part in ipairs(self:_surfaces()) do
		local c, h = part.Position, part.Size / 2
		local closest = Vector3.new(
			math.clamp(pos.X, c.X - h.X, c.X + h.X),
			math.clamp(pos.Y, c.Y - h.Y, c.Y + h.Y),
			math.clamp(pos.Z, c.Z - h.Z, c.Z + h.Z))
		local delta = pos - closest
		local dist = delta.Magnitude
		if dist < r and dist > 1e-4 and vel:Dot(delta.Unit) < 0 then
			local n = delta.Unit
			local out = vel - (1 + SURFACE_RESTITUTION) * vel:Dot(n) * n
			return { pos = closest + n * (r + 0.05), vel = out }
		end
	end
	return nil
end

-- A player's hit-sphere is a MOVING-sphere collider, resolved by a SWEPT (continuous) test so a fast
-- ball -- or a fast jump into the ball -- can't tunnel through it between frames (point sampling only
-- the frame's end position misses fast/glancing passes). We sweep the ball's path this frame (A -> B)
-- against the sphere's path (relative motion over `dt`) and resolve at the EARLIEST entry point, but
-- ONLY when the two are approaching along the contact normal (a descending player over a rising/
-- receding ball does NOT resolve -> it can never pull the ball down). On a hit the ball is repositioned
-- onto the sphere surface (one hit per approach) and gets the velocity-proportional rebound (a still
-- player adds no energy). Earliest contact across players wins.
function BallController:_collidePlayers(A: Vector3, B: Vector3, vel: Vector3, dt: number, colliders: { PlayerCollider }?): ({ pos: Vector3, vel: Vector3, player: Player })?
	if not colliders then return nil end
	local r = G.ballRadius
	local best: ({ pos: Vector3, vel: Vector3, player: Player })? = nil
	local bestTau = math.huge
	for _, col in ipairs(colliders) do
		local sum = col.radius + r
		local sphereDelta = col.vel * dt                  -- the sphere moves this frame too
		local r0 = (A - col.center) + sphereDelta          -- relative position at the start of the frame
		local rd = (B - A) - sphereDelta                   -- relative displacement over the frame
		local a = rd:Dot(rd)
		local c = r0:Dot(r0) - sum * sum
		local tau: number? = nil
		if a < 1e-8 then
			if c < 0 then tau = 0 end                      -- already overlapping, negligible relative motion
		else
			local b = 2 * r0:Dot(rd)
			local disc = b * b - 4 * a * c
			if disc >= 0 then
				local sq = math.sqrt(disc)
				local t0 = (-b - sq) / (2 * a)             -- entry
				local t1 = (-b + sq) / (2 * a)             -- exit
				if t1 >= 0 and t0 <= 1 then tau = math.max(t0, 0) end
			end
		end
		if tau and tau < bestTau then
			local ballAt = A + (B - A) * tau
			local sphereAt = (col.center - sphereDelta) + sphereDelta * tau
			local d = ballAt - sphereAt
			local n = (d.Magnitude > 1e-4) and d.Unit or Vector3.new(0, 1, 0)
			if (vel - col.vel):Dot(n) < 0 then             -- approaching only -> never pulls the ball down
				bestTau = tau
				best = { pos = col.center + n * (sum + 0.05), vel = strikeVelocity(vel, liftNormal(n), col.vel), player = col.player }
			end
		end
	end
	return best
end

function BallController:step(dt: number, playerColliders: { PlayerCollider }?)
	-- Parked phases (Live hover, Rest): the ball is stationary, but a player can still drive into it.
	-- Run the same swept moving-sphere collision against the parked position (the sphere's own motion is
	-- swept, so a fast jump into the ball is caught); a hit serves (Live -> Flight) or bats the dead ball
	-- (Rest -> Settling). No hit -> sit still.
	if self.phase == "Live" or self.phase == "Rest" then
		local parked = (self.phase == "Live") and self.restPoint or self.ball.Position
		local h = self:_collidePlayers(parked, parked, Vector3.zero, dt, playerColliders)
		if h then
			local wasServe = (self.phase == "Live")   -- a Live->Flight hit is the human King's jump-serve
			self.ball.Position = h.pos
			self.phase = (self.phase == "Live") and "Flight" or "Settling"
			self:launch(h.pos, h.vel)
			if self.onPlayerHit then self.onPlayerHit(self.struckCell, self.targetCell, wasServe) end
			return
		end
		if self.phase == "Live" then self.ball.Position = self.restPoint end
		return                                    -- Rest: sit still until re-served or struck
	elseif self.phase ~= "Flight" and self.phase ~= "Settling" then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = now - self.startT
	local g = self.gravity
	local vel = self.v0 + Vector3.new(0, -g * t, 0)
	local pos = self.p0 + self.v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)

	-- a player's hit-sphere is resolved first, as a SWEPT moving-sphere collision over this frame's path
	-- (self.ball.Position -> pos) so a fast ball can't tunnel through it -- same resolve-style as below.
	local hp = self:_collidePlayers(self.ball.Position, pos, vel, dt, playerColliders)
	if hp then
		self.ball.Position = hp.pos
		self:launch(hp.pos, hp.vel)   -- Flight stays Flight, Settling stays Settling (re-predicts land cell in Flight)
		if self.onPlayerHit then self.onPlayerHit(self.struckCell, self.targetCell, false) end
		return
	end

	-- bounce off the rigid surfaces (frame pipes, walls, ceiling, hoops) -- in flight AND while settling
	local c = self:_collide(pos, vel)
	if c then
		self.p0 = c.pos; self.v0 = c.vel; self.startT = now
		self.ball.Position = c.pos
		if self.phase == "Flight" then self.targetCell = self:_predictLandCell() end
		self:resync()
		return
	end

	-- Over-the-pipe ownership: detect a cell-boundary crossing this frame and transfer ownership ONLY if
	-- the ball cleared the pipe (centre Y at/above G.pipeClearHeight) on the way over. A crossing BELOW
	-- that height is an illegal low deflect under the pipe -> ownership stays with the previous square
	-- (the hitter), so the fault path won't wrongly knock out the neighbour. We track every true XZ
	-- transition (update _lastCell each time) but only move ownerCell on the high (legal) ones.
	local nowCell = G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z))
	if nowCell and nowCell ~= self._lastCell then
		if pos.Y >= G.pipeClearHeight then
			-- A legal over-pipe entry: the ball now belongs to this square. The FIRST such transfer off the
			-- hitter's struck square is the authoritative "clear" (save) -- fire onClear once for it.
			local firstClear = (self.ownerCell == self.struckCell) and (nowCell ~= self.struckCell)
			self.ownerCell = nowCell
			if firstClear and self.onClear then self.onClear(self.struckCell, self.ownerCell) end
		end
		self._lastCell = nowCell       -- record the transition either way (so each boundary counts once)
	end

	-- floor: a robust ground-plane test (the ball rests at y = ballRadius). The first floor contact of
	-- a rally is the "landing"; afterwards it just bounces with restitution + ground friction til rest.
	if pos.Y <= G.ballRadius then
		if self.phase == "Flight" then
			self.phase = "Settling"
			if self.onLand then self.onLand(G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z)), self.struckCell, self.ownerCell) end
		end
		local up = -vel.Y * G.floorRestitution
		local horiz = Vector3.new(vel.X, 0, vel.Z) * G.floorFriction
		self.ball.Position = Vector3.new(pos.X, G.ballRadius, pos.Z)
		if up < G.restSpeedV and horiz.Magnitude < G.restSpeedH then
			self.phase = "Rest"
			self.v0 = Vector3.zero
			self:resync()
			if self.onRest then self.onRest() end
		else
			self.p0 = self.ball.Position
			self.v0 = Vector3.new(horiz.X, up, horiz.Z)
			self.startT = now
			self:resync()
		end
	else
		self.ball.Position = pos
	end
end

return BallController
