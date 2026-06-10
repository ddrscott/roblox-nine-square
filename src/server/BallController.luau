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
--   :isHittable(now): boolean       may a contact strike it right now? (cooldown only)
--   :step()                         advance the simulation one tick; call every Heartbeat
--   :resync()                       replicate the current ball state to clients
--   .ball: Part                     the rendered ball (read-only)
--   .phase: string                  "Live" | "Flight" | "Settling" | "Rest" (read-only)
--   .struckCell / .targetCell       last struck square / predicted landing square (read-only)
--   .onLand: ((landedCell: string?, struckCell: string?) -> ())?
--                                   fires ONCE, on the first floor contact after a launch. The game
--                                   classifies legal / self-fault / out-of-bounds and plays feedback.
--   .onRest: (() -> ())?            fires ONCE, when the ball has bounced out its energy and stopped.
--                                   The game decides if/when to re-serve.
--
-- Motion: a true projectile arc under gravity that reflects off EVERY solid surface in the arena --
-- the overhead frame pipes, the gym walls, ceiling, backboards/rims, and the floor. Floor contacts
-- additionally shed horizontal speed (ground friction) and, once slow enough, park the ball at rest.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

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
	self.lastHitT = -1
	self.struckCell = "C"               -- square the ball was last struck from
	self.targetCell = "C"               -- predicted / current landing square (for the client highlight)
	self.onLand = nil :: ((string?, string?) -> ())?   -- game wires these; see the contract above
	self.onRest = nil :: (() -> ())?
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
	self.startT = workspace:GetServerTimeNow(); self.lastHitT = self.startT
	self.struckCell = G.cellAtPosition(fromPoint)
	if self.phase == "Settling" or self.phase == "Rest" then
		self.phase = "Settling"
	else
		self.phase = "Flight"
		self.targetCell = self:_predictLandCell()
	end
	self:resync()
end

-- The ball can be struck in any phase (you can keep batting a dead ball); the cooldown debounces a jump.
function BallController:isHittable(now: number): boolean
	return (now - self.lastHitT) >= G.hitCooldown
end

-- The ball's instantaneous velocity right now (zero unless it's in motion).
function BallController:currentVelocity(): Vector3
	if self.phase == "Flight" or self.phase == "Settling" then
		return self.v0 + Vector3.new(0, -self.gravity * (workspace:GetServerTimeNow() - self.startT), 0)
	end
	return Vector3.zero
end

-- A player strikes the ball: model the player as a sphere moving at `playerVel` hitting the ball
-- sphere, and transfer momentum along the line of centres `n` (a simple frictionless sphere bounce).
-- The impact is therefore proportional to the player's velocity TOWARD the ball; hitMinPop floors the
-- outgoing speed so a clean contact (even at the near-motionless jump apex) always stays in play.
function BallController:strike(point: Vector3, n: Vector3, playerVel: Vector3)
	local vBall = self:currentVelocity()
	local closing = (vBall - playerVel):Dot(n)
	local vOut = vBall - (1 + G.hitRestitution) * closing * n
	local along = vOut:Dot(n)
	if along < G.hitMinPop then vOut = vOut + (G.hitMinPop - along) * n end
	self:launch(point, vOut)
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

function BallController:step()
	if self.phase == "Live" then
		self.ball.Position = self.restPoint
		return
	elseif self.phase ~= "Flight" and self.phase ~= "Settling" then
		return                                    -- Rest: sit still until re-served or struck
	end
	local now = workspace:GetServerTimeNow()
	local t = now - self.startT
	local g = self.gravity
	local vel = self.v0 + Vector3.new(0, -g * t, 0)
	local pos = self.p0 + self.v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)

	-- bounce off the rigid surfaces (frame pipes, walls, ceiling, hoops) -- in flight AND while settling
	local c = self:_collide(pos, vel)
	if c then
		self.p0 = c.pos; self.v0 = c.vel; self.startT = now
		self.ball.Position = c.pos
		if self.phase == "Flight" then self.targetCell = self:_predictLandCell() end
		self:resync()
		return
	end

	-- floor: a robust ground-plane test (the ball rests at y = ballRadius). The first floor contact of
	-- a rally is the "landing"; afterwards it just bounces with restitution + ground friction til rest.
	if pos.Y <= G.ballRadius then
		if self.phase == "Flight" then
			self.phase = "Settling"
			if self.onLand then self.onLand(G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z)), self.struckCell) end
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
