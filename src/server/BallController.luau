--!strict
-- ServerScriptService.NineSquare.BallController
-- Owns the single anchored ball. The ball hovers at a rest point (Live) until a player gets under
-- it and strikes it. The strike imparts a radial-impulse velocity (server/HitResolver) and the ball
-- follows a TRUE projectile arc (Flight) under gravity. When it returns to strike height it settles:
--   * a DIFFERENT in-bounds square -> hover there (legal; rally continues)
--   * the SAME square it was struck from -> self-fault (didn't clear your square)
--   * outside the court -> out-of-bounds fault
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
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
	self.struckCell = "C"               -- square the ball was last struck from
	self.targetCell = "C"               -- predicted / current settle square (for highlight)
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

-- time for the projectile to return to its launch height (apex is at half this)
function BallController:_settleTime(): number
	return (2 * self.v0.Y) / self.gravity
end

-- Strike: launch from a contact point with an initial velocity (radial impulse from the hit).
function BallController:launch(fromPoint: Vector3, v0: Vector3)
	self.p0 = fromPoint; self.v0 = v0
	self.startT = workspace:GetServerTimeNow(); self.lastHitT = self.startT
	self.phase = "Flight"
	self.struckCell = G.cellAtPosition(fromPoint)
	local settle = fromPoint + v0 * self:_settleTime()
	self.targetCell = G.cellAtPosition(Vector3.new(settle.X, 0, settle.Z))
	self:resync()
end

-- A served/flying ball can be struck, after a short cooldown so one jump fires once.
function BallController:isHittable(now: number): boolean
	return (self.phase == "Live" or self.phase == "Flight") and (now - self.lastHitT) >= G.hitCooldown
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

function BallController:step()
	if self.phase == "Live" then
		self.ball.Position = self.restPoint
		return
	elseif self.phase == "Flight" then
		local t = workspace:GetServerTimeNow() - self.startT
		local g = self.gravity
		self.ball.Position = self.p0 + self.v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)
		if t >= self:_settleTime() then
			local settle = self.p0 + self.v0 * self:_settleTime()
			local point = Vector3.new(settle.X, G.frameHeight, settle.Z)
			local cell = G.cellAtPosition(point)
			if cell == nil then
				self:_fault(self.struckCell, "out-of-bounds")
			elseif cell == self.struckCell then
				self:_fault(cell, "self-square")
			else
				self:hoverAt(point)   -- legal: settle in a new square; rally continues
			end
		end
	end
end

return BallController
