--!strict
-- ServerScriptService.NineSquare.BallController
-- Owns the single anchored ball. The ball hovers at a rest point (Live) until a player gets under
-- it and strikes it. The strike imparts a velocity (server/HitResolver) and the ball follows a TRUE
-- projectile arc (Flight) under gravity, BOUNCING off the overhead frame pipes it hits, until it
-- lands on the floor. On landing it resolves: different square = legal, same square = self-fault,
-- outside the court = out-of-bounds fault.
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

local FRAME_RESTITUTION = 0.6   -- bounciness when the ball strikes a frame pipe

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
	self.struckCell = "C"               -- square the ball was last struck from
	self.targetCell = "C"               -- predicted / current landing square (for highlight)
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

-- predicted floor-landing square for the current p0/v0 (ignores future bounces)
function BallController:_predictLandCell(): string?
	local A, B, C = -0.5 * self.gravity, self.v0.Y, self.p0.Y - G.ballRadius
	local disc = B*B - 4*A*C
	if disc < 0 then return nil end
	local t = math.max((-B + math.sqrt(disc))/(2*A), (-B - math.sqrt(disc))/(2*A))
	local land = self.p0 + self.v0 * t
	return G.cellAtPosition(Vector3.new(land.X, 0, land.Z))
end

-- Strike: launch from a contact point with an initial velocity.
function BallController:launch(fromPoint: Vector3, v0: Vector3)
	self.p0 = fromPoint; self.v0 = v0
	self.startT = workspace:GetServerTimeNow(); self.lastHitT = self.startT
	self.phase = "Flight"
	self.struckCell = G.cellAtPosition(fromPoint)
	self.targetCell = self:_predictLandCell()
	self:resync()
end

-- A served/flying ball can be struck, after a short cooldown so one jump fires once.
function BallController:isHittable(now: number): boolean
	return (self.phase == "Live" or self.phase == "Flight") and (now - self.lastHitT) >= G.hitCooldown
end

-- Sphere-vs-frame-pipe test. If the ball penetrates a (axis-aligned) frame bar while moving into it,
-- returns (true, correctedPos, reflectedVel); otherwise false.
function BallController:_collideFrame(pos: Vector3, vel: Vector3)
	local frame = self.ball.Parent and self.ball.Parent:FindFirstChild("Frame")
	if not frame then return false end
	local r = G.ballRadius
	for _, beam in ipairs(frame:GetChildren()) do
		if beam:IsA("BasePart") then
			local c, h = beam.Position, beam.Size / 2
			local closest = Vector3.new(
				math.clamp(pos.X, c.X - h.X, c.X + h.X),
				math.clamp(pos.Y, c.Y - h.Y, c.Y + h.Y),
				math.clamp(pos.Z, c.Z - h.Z, c.Z + h.Z))
			local delta = pos - closest
			local dist = delta.Magnitude
			if dist < r and dist > 1e-4 and vel:Dot(delta.Unit) < 0 then
				local n = delta.Unit
				local newVel = vel - (1 + FRAME_RESTITUTION) * vel:Dot(n) * n
				local newPos = closest + n * (r + 0.05)
				return true, newPos, newVel
			end
		end
	end
	return false
end

function BallController:_flash(cell: string?)
	if not cell then return end
	local floors = self.ball.Parent and self.ball.Parent:FindFirstChild("Floors")
	local f = floors and floors:FindFirstChild("Floor_" .. cell)
	if not f then return end
	local orig = f.Color
	f.Color = Color3.fromRGB(205, 45, 45)
	task.delay(0.6, function() if f and f.Parent then f.Color = orig end end)
end

function BallController:_faultSound()
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/uuhhh.mp3"; s.Volume = 1
	s.Parent = self.ball; s:Play()
	Debris:AddItem(s, 3)
end

function BallController:_fault(cell: string?, kind: string)
	self.phase = "Dead"; self.targetCell = cell
	self:resync()
	print(("[NineSquare] FAULT (%s) cell=%s"):format(kind, tostring(cell)))
	self:_flash(cell)
	self:_faultSound()
	task.delay(0.9, function() if self.phase == "Dead" then self:resetToServe() end end)
end

-- Legal landing in another square that nobody returned: rally ends, re-serve from center.
function BallController:_land(cell: string)
	self.phase = "Dead"; self.targetCell = cell
	self:resync()
	print("[NineSquare] ball landed in " .. cell .. " (unreturned)")
	task.delay(0.7, function() if self.phase == "Dead" then self:resetToServe() end end)
end

function BallController:step()
	if self.phase == "Live" then
		self.ball.Position = self.restPoint
		return
	elseif self.phase == "Flight" then
		local now = workspace:GetServerTimeNow()
		local t = now - self.startT
		local g = self.gravity
		local vel = self.v0 + Vector3.new(0, -g * t, 0)
		local pos = self.p0 + self.v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)
		-- bounce off the overhead frame pipes
		local hit, newPos, newVel = self:_collideFrame(pos, vel)
		if hit then
			self.p0 = newPos; self.v0 = newVel; self.startT = now
			self.ball.Position = newPos
			self.targetCell = self:_predictLandCell()
			self:resync()
			return
		end
		if pos.Y <= G.ballRadius then
			pos = Vector3.new(pos.X, G.ballRadius, pos.Z)
			self.ball.Position = pos
			local cell = G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z))
			if cell == nil then
				self:_fault(self.struckCell, "out-of-bounds")
			elseif cell == self.struckCell then
				self:_fault(cell, "self-square")
			else
				self:_land(cell)
			end
		else
			self.ball.Position = pos
		end
	end
end

return BallController
