--!strict
-- ServerScriptService.NineSquare.BallController
-- Owns the single anchored ball. Computes deterministic arcs, advances them each tick,
-- and broadcasts arc params to clients for telegraph rendering.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

export type Arc = {
	origin: Vector3, target: Vector3, apex: number,
	startT: number, travel: number, kind: string, targetCell: string,
}

function BallController.new()
	local self = setmetatable({}, BallController)
	local ball = Instance.new("Part")
	ball.Name = "Ball"; ball.Shape = Enum.PartType.Ball; ball.Anchored = true
	ball.Size = Vector3.new(G.ballRadius*2, G.ballRadius*2, G.ballRadius*2)
	ball.Color = Color3.fromRGB(255, 220, 60); ball.Material = Enum.Material.SmoothPlastic
	ball.Parent = workspace:WaitForChild("NineSquare")
	self.ball = ball
	self.arc = nil :: Arc?
	self.phase = "Idle"      -- Idle | InFlight | Descending | Resolved
	self.onArrive = nil :: ((Arc) -> ())?
	ball.Position = G.cellFramePoint("C")
	return self
end

-- y along a parabola: endpoints lerp + 4*apex*u*(1-u) bulge.
local function arcPos(arc: Arc, now: number): (Vector3, number)
	local u = math.clamp((now - arc.startT) / arc.travel, 0, 1)
	local flat = arc.origin:Lerp(arc.target, u)
	local y = arc.origin.Y + (arc.target.Y - arc.origin.Y) * u + 4 * arc.apex * u * (1 - u)
	return Vector3.new(flat.X, y, flat.Z), u
end

function BallController:_broadcast()
	local a = self.arc
	if not a then return end
	BallSync:FireAllClients({
		origin = a.origin, target = a.target, apex = a.apex,
		startT = a.startT, travel = a.travel, kind = a.kind, targetCell = a.targetCell,
		descentWindow = G.descentWindow,
	})
end

-- Launch a serve arc from center to a target cell's frame point.
function BallController:serve(targetCell: string)
	local arc: Arc = {
		origin = G.cellFramePoint("C"), target = G.cellFramePoint(targetCell),
		apex = G.apexHeight, startT = workspace:GetServerTimeNow(),
		travel = G.serveTravel, kind = "serve", targetCell = targetCell,
	}
	self.arc = arc; self.phase = "InFlight"
	self:_broadcast()
end

-- Launch a volley lob from a contact point along a horizontal direction (M1: lands, no occupant).
function BallController:volley(fromPoint: Vector3, horizDir: Vector3)
	local dir = horizDir.Magnitude > 1e-3 and horizDir.Unit or Vector3.zero
	local target = fromPoint + dir * G.lobDistance
	target = Vector3.new(target.X, G.cellFramePoint("C").Y, target.Z)
	local landCell = G.cellAtPosition(target) or "C"
	local arc: Arc = {
		origin = fromPoint, target = target, apex = G.apexHeight * 0.6,
		startT = workspace:GetServerTimeNow(), travel = G.lobTravel,
		kind = "volley", targetCell = landCell,
	}
	self.arc = arc; self.phase = "InFlight"
	self:_broadcast()
end

function BallController:reset()
	self.arc = nil; self.phase = "Idle"
	self.ball.Position = G.cellFramePoint("C")
	BallSync:FireAllClients({ kind = "idle" })
end

-- Called every Heartbeat. Moves the ball; fires onArrive once when an arc completes.
function BallController:step()
	local a = self.arc
	if not a then return end
	local now = workspace:GetServerTimeNow()
	local pos, u = arcPos(a, now)
	self.ball.Position = pos
	if self.phase == "InFlight" and (now - a.startT) >= (a.travel - G.descentWindow) then
		self.phase = "Descending"
	end
	if u >= 1 and self.phase ~= "Resolved" then
		self.phase = "Resolved"
		if self.onArrive then self.onArrive(a) end
	end
end

return BallController
