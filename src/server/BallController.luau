--!strict
-- ServerScriptService.NineSquare.BallController
-- Owns the single anchored ball. The ball hovers at a serve point (Live) until a player gets
-- under it and strikes it. The strike imparts a radial-impulse velocity (see HitResolver/Server)
-- and the ball follows a TRUE projectile arc (Flight) under gravity until it lands. Direction is
-- governed purely by the contact geometry; this controller just simulates the resulting physics.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

function BallController.new()
	local self = setmetatable({}, BallController)
	local ball = Instance.new("Part")
	ball.Name = "Ball"; ball.Shape = Enum.PartType.Ball; ball.Anchored = true; ball.CanCollide = false
	ball.Size = Vector3.new(G.ballRadius*2, G.ballRadius*2, G.ballRadius*2)
	ball.Color = Color3.fromRGB(255, 220, 60); ball.Material = Enum.Material.SmoothPlastic
	ball.Parent = workspace:WaitForChild("NineSquare")
	self.ball = ball
	self.gravity = workspace.Gravity
	self.phase = "Live"                 -- Live (hover) | Flight | Dead
	self.restPoint = G.cellFramePoint("C")
	self.p0 = self.restPoint
	self.v0 = Vector3.zero
	self.startT = 0
	self.lastHitT = -1
	self.targetCell = G.cellAtPosition(self.restPoint) or "C"
	ball.Position = self.restPoint
	return self
end

local function kindForPhase(phase: string): string
	if phase == "Live" then return "live"
	elseif phase == "Flight" then return "flight"
	else return "idle" end
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

-- Strike: launch from a contact point with an initial velocity (radial impulse from the hit).
function BallController:launch(fromPoint: Vector3, v0: Vector3)
	self.p0 = fromPoint; self.v0 = v0
	self.startT = workspace:GetServerTimeNow(); self.lastHitT = self.startT
	self.phase = "Flight"
	-- predict where it crosses the floor (y = ballRadius) for the highlight + fault check
	local g = self.gravity
	local A, B, C = -0.5*g, v0.Y, fromPoint.Y - G.ballRadius
	local disc = B*B - 4*A*C
	local tland = (disc >= 0) and math.max((-B + math.sqrt(disc))/(2*A), (-B - math.sqrt(disc))/(2*A)) or 0
	local land = fromPoint + v0*tland
	self.targetCell = G.cellAtPosition(Vector3.new(land.X, 0, land.Z))
	self:resync()
end

-- A served/flying ball can be struck, after a short cooldown so one jump fires once.
function BallController:isHittable(now: number): boolean
	return (self.phase == "Live" or self.phase == "Flight") and (now - self.lastHitT) >= G.hitCooldown
end

function BallController:step()
	if self.phase == "Live" then
		self.ball.Position = self.restPoint
	elseif self.phase == "Flight" then
		local t = workspace:GetServerTimeNow() - self.startT
		local g = self.gravity
		local pos = self.p0 + self.v0*t + Vector3.new(0, -0.5*g*t*t, 0)
		if pos.Y <= G.ballRadius then
			pos = Vector3.new(pos.X, G.ballRadius, pos.Z)
			self.ball.Position = pos
			self.phase = "Dead"
			self.targetCell = G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z))
			self:resync()
			task.delay(0.6, function() if self.phase == "Dead" then self:resetToServe() end end)
		else
			self.ball.Position = pos
		end
	end
end

return BallController
