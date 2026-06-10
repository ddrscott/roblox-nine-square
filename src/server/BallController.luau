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

local FRAME_RESTITUTION = 0.6   -- bounciness when the ball strikes a frame pipe or a gym wall/ceiling

function BallController.new()
	local self = setmetatable({}, BallController)
	local ball = Instance.new("Part")
	ball.Name = "Ball"; ball.Shape = Enum.PartType.Ball; ball.Anchored = true; ball.CanCollide = false
	ball.Size = Vector3.new(G.ballRadius*2, G.ballRadius*2, G.ballRadius*2)
	-- matte coral: a near-white color (old 255,220,60) trips the Lighting Bloom and glows like a light source
	ball.Color = Color3.fromRGB(235, 92, 74); ball.Material = Enum.Material.Plastic
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
	self.struckCell = G.cellAtPosition(fromPoint)
	if self.phase == "Settling" or self.phase == "Dead" then
		-- the rally is already scored: a hit on the dead ball just bats it around (no re-score), and
		-- moving it out of Dead cancels the pending reset. Keep it in Settling so it never re-resolves.
		self.phase = "Settling"
	else
		self.phase = "Flight"
		self.targetCell = self:_predictLandCell()
	end
	self:resync()
end

-- The ball can be struck in ANY phase (you can keep batting a dead ball around for fun); the
-- cooldown just debounces one jump into a single hit.
function BallController:isHittable(now: number): boolean
	return (now - self.lastHitT) >= G.hitCooldown
end

-- Barrier parts the ball bounces off: the overhead frame pipes + the gym walls and ceiling.
function BallController:_barriers(): { BasePart }
	local list = {}
	local frame = self.ball.Parent and self.ball.Parent:FindFirstChild("Frame")
	if frame then
		for _, b in ipairs(frame:GetChildren()) do if b:IsA("BasePart") then table.insert(list, b) end end
	end
	local gym = workspace:FindFirstChild("Gym")
	if gym then
		for _, nm in ipairs({ "WallE", "WallW", "WallN", "WallS", "Ceiling" }) do
			local p = gym:FindFirstChild(nm)
			if p and p:IsA("BasePart") then table.insert(list, p) end
		end
	end
	return list
end

-- Sphere-vs-(axis-aligned)-box test against every barrier. If the ball penetrates one while moving
-- into it, returns (true, correctedPos, reflectedVel); otherwise false.
function BallController:_collide(pos: Vector3, vel: Vector3)
	local r = G.ballRadius
	for _, part in ipairs(self:_barriers()) do
		local c, h = part.Position, part.Size / 2
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
	return false
end

function BallController:_flash(cell: string?)
	if not cell then return end
	local floors = self.ball.Parent and self.ball.Parent:FindFirstChild("Floors")
	local f = floors and floors:FindFirstChild("Floor_" .. cell)
	if not f then return end
	-- markers are invisible by default; flash one briefly visible-red on the faulted square
	f.Color = Color3.fromRGB(205, 45, 45)
	f.Transparency = 0.3
	task.delay(0.6, function() if f and f.Parent then f.Transparency = 1 end end)
end

function BallController:_faultSound()
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/uuhhh.mp3"; s.Volume = 1
	s.Parent = self.ball; s:Play()
	Debris:AddItem(s, 3)
end

-- First floor contact ends the rally and decides the square: legal land elsewhere, self-square fault,
-- or out-of-bounds. The flash + oof sound fire now -- but the ball is NOT frozen; it drops into
-- Settling and keeps bouncing/interacting until it comes to rest (see step()).
function BallController:_resolve(cell: string?)
	self.phase = "Settling"; self.targetCell = cell
	if cell == nil then
		print("[NineSquare] FAULT (out-of-bounds) struck=" .. tostring(self.struckCell))
		self:_flash(self.struckCell); self:_faultSound()
	elseif cell == self.struckCell then
		print("[NineSquare] FAULT (self-square) cell=" .. cell)
		self:_flash(cell); self:_faultSound()
	else
		print("[NineSquare] ball landed in " .. cell .. " (unreturned)")
	end
	self:resync()
end

-- The ball has bounced out its energy and come to rest: hold a beat, then re-serve from center.
function BallController:_rest()
	self.phase = "Dead"
	self:resync()
	task.delay(0.6, function() if self.phase == "Dead" then self:resetToServe() end end)
end

function BallController:step()
	if self.phase == "Live" then
		self.ball.Position = self.restPoint
		return
	elseif self.phase == "Flight" or self.phase == "Settling" then
		local now = workspace:GetServerTimeNow()
		local t = now - self.startT
		local g = self.gravity
		local vel = self.v0 + Vector3.new(0, -g * t, 0)
		local pos = self.p0 + self.v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)
		-- bounce off the frame pipes and the gym walls/ceiling (in flight AND while settling)
		local hit, newPos, newVel = self:_collide(pos, vel)
		if hit then
			self.p0 = newPos; self.v0 = newVel; self.startT = now
			self.ball.Position = newPos
			if self.phase == "Flight" then self.targetCell = self:_predictLandCell() end
			self:resync()
			return
		end
		if pos.Y <= G.ballRadius then
			-- first floor contact decides the rally (sound + red flash); thereafter the ball just bounces
			if self.phase == "Flight" then
				self:_resolve(G.cellAtPosition(Vector3.new(pos.X, 0, pos.Z)))
			end
			-- bounce off the floor: keep some vertical (restitution) + shed horizontal (friction)
			local up = -vel.Y * G.floorRestitution
			local horiz = Vector3.new(vel.X, 0, vel.Z) * G.floorFriction
			self.ball.Position = Vector3.new(pos.X, G.ballRadius, pos.Z)
			if up < G.restSpeedV and horiz.Magnitude < G.restSpeedH then
				self:_rest()                       -- come to rest -> re-serve after a beat
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
end

return BallController
