--!strict
-- StarterPlayer.StarterPlayerScripts.Movement
--
-- Client-side movement skill moves that raise the skill ceiling and feed the velocity-proportional
-- strike. The server's HitResolver reports the LOCAL character's replicated HumanoidRootPart
-- AssemblyLinearVelocity as the player hit-sphere's velocity, which BallController folds into its
-- moving-sphere collision, so every burst applied here flows straight into the strike rebound with
-- NO server change and NO strike-formula change (per M1; anti-cheat is M5).
--
--   * Dash        -- double-tap a movement key (W/A/S/D) within doubleTapWindow -> a brief horizontal
--                    velocity burst in that (camera-relative) direction. Horizontal only, so it can't
--                    fling you up or out of the gym. Gated + costed by stamina.
--   * Flip jump   -- double-tap Space while airborne -> ONE extra mid-air jump with a cosmetic forward
--                    flip; sets upward velocity (reach higher / spike) + a small forward boost. Resets
--                    on landing. Gated + costed by stamina.
--   * Stamina     -- shared 0..max pool; dash/flip cost a chunk, regenerates over time when idle.
--                    Shown as a simple HUD bar.
--
-- All numbers live in ReplicatedStorage.GridConfig.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local G = require(RS.GridConfig)

local player = Players.LocalPlayer

-- ---------------------------------------------------------------------------------------------------
-- Stamina (shared energy pool for dash + flip)
-- ---------------------------------------------------------------------------------------------------
local stamina = G.staminaMax

local function canSpend(cost: number): boolean
	return stamina >= cost
end

local function spend(cost: number)
	stamina = math.max(0, stamina - cost)
end

-- ---------------------------------------------------------------------------------------------------
-- HUD: a simple stamina bar bottom-centre
-- ---------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MovementHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local barBg = Instance.new("Frame")
barBg.Name = "StaminaBar"; barBg.AnchorPoint = Vector2.new(0.5, 1)
barBg.Position = UDim2.new(0.5, 0, 1, -24); barBg.Size = UDim2.fromOffset(260, 16)
barBg.BackgroundColor3 = Color3.fromRGB(20, 22, 28); barBg.BackgroundTransparency = 0.25
barBg.BorderSizePixel = 0; barBg.Parent = gui
local bgCorner = Instance.new("UICorner"); bgCorner.CornerRadius = UDim.new(0, 8); bgCorner.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"; barFill.Position = UDim2.fromOffset(2, 2)
barFill.Size = UDim2.new(1, -4, 1, -4); barFill.BorderSizePixel = 0
barFill.BackgroundColor3 = Color3.fromRGB(120, 220, 255); barFill.Parent = barBg
local fillCorner = Instance.new("UICorner"); fillCorner.CornerRadius = UDim.new(0, 6); fillCorner.Parent = barFill

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1; label.Size = UDim2.fromScale(1, 1)
label.Font = Enum.Font.GothamBold; label.TextSize = 11; label.Text = "STAMINA"
label.TextColor3 = Color3.fromRGB(235, 240, 245); label.TextTransparency = 0.15; label.Parent = barBg

local function updateHud()
	local frac = stamina / G.staminaMax
	barFill.Size = UDim2.new(frac, -4 * frac, 1, -4)
	-- dim toward red when low, blue when full
	barFill.BackgroundColor3 = (frac < 0.34) and Color3.fromRGB(255, 110, 90) or Color3.fromRGB(120, 220, 255)
end

-- ---------------------------------------------------------------------------------------------------
-- Character handles (refreshed on respawn)
-- ---------------------------------------------------------------------------------------------------
local hrp: BasePart? = nil
local humanoid: Humanoid? = nil
local usedAirJump = false       -- one extra air-jump per airtime
local dashUntil = 0             -- while > now, the dash burst is being held

local function bindCharacter(char: Model)
	hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	usedAirJump = false
	dashUntil = 0
	-- reset the extra jump whenever we touch ground
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			usedAirJump = false
		end
	end)
end

if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

-- ---------------------------------------------------------------------------------------------------
-- Dash -- double-tap W/A/S/D for a camera-relative horizontal burst
-- ---------------------------------------------------------------------------------------------------
-- screen-direction for each movement key (relative to the camera's flattened look vector)
local DIRS: { [Enum.KeyCode]: Vector3 } = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
}
local lastTap: { [Enum.KeyCode]: number } = {}

local function cameraRelative(screenDir: Vector3): Vector3
	local cam = workspace.CurrentCamera
	if not cam then return screenDir end
	local look = cam.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = (fwd.Magnitude > 1e-3) and fwd.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)   -- camera-right on the XZ plane (90 deg CW of fwd)
	local dir = right * screenDir.X + fwd * (-screenDir.Z)
	return (dir.Magnitude > 1e-3) and dir.Unit or fwd
end

local function dash(screenDir: Vector3)
	if not hrp then return end
	if not canSpend(G.dashCost) then return end
	spend(G.dashCost)
	local dir = cameraRelative(screenDir)
	-- horizontal burst only; keep the character's current vertical velocity (don't yank them down/up)
	local cur = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(dir.X * G.dashSpeed, cur.Y, dir.Z * G.dashSpeed)
	dashUntil = os.clock() + G.dashDuration
end

-- ---------------------------------------------------------------------------------------------------
-- Flip jump -- double-tap Space while airborne -> one extra jump + cosmetic forward flip
-- ---------------------------------------------------------------------------------------------------
local function isAirborne(): boolean
	if not humanoid then return false end
	local st = humanoid:GetState()
	return st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping
end

local function flipSpin()
	if not hrp then return end
	-- cosmetic: spin the root forward once around its local right axis. Purely visual; physics velocity
	-- (set below) is what reaches the ball. Skipped silently if the character despawns mid-tween.
	local h = hrp
	local startCF = h.CFrame
	local axis = startCF.RightVector
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not h.Parent then conn:Disconnect(); return end
		local a = (os.clock() - t0) / G.flipSpinTime
		if a >= 1 then conn:Disconnect(); return end
		-- offset is cosmetic on top of wherever the character now is; rebuild from current position
		local ang = a * math.pi * 2
		h.CFrame = CFrame.new(h.Position) * CFrame.fromAxisAngle(axis, ang) * (startCF - startCF.Position)
	end)
end

local function flipJump()
	if not hrp or not humanoid then return end
	if usedAirJump or not isAirborne() then return end
	if not canSpend(G.flipCost) then return end
	spend(G.flipCost)
	usedAirJump = true
	local fwd = hrp.CFrame.LookVector
	local horiz = Vector3.new(fwd.X, 0, fwd.Z)
	horiz = (horiz.Magnitude > 1e-3) and horiz.Unit or Vector3.zero
	local cur = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity =
		Vector3.new(cur.X + horiz.X * G.flipForwardBoost, G.flipUpVelocity, cur.Z + horiz.Z * G.flipForwardBoost)
	flipSpin()
end

-- ---------------------------------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------------------------------
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space then
		-- a normal first jump is handled by the default controller; double-tap = the extra flip
		local now = os.clock()
		if lastTap[key] and (now - lastTap[key]) <= G.doubleTapWindow then
			flipJump()
			lastTap[key] = nil
		else
			lastTap[key] = now
		end
		return
	end
	local screenDir = DIRS[key]
	if screenDir then
		local now = os.clock()
		if lastTap[key] and (now - lastTap[key]) <= G.doubleTapWindow then
			dash(screenDir)
			lastTap[key] = nil
		else
			lastTap[key] = now
		end
	end
end)

-- ---------------------------------------------------------------------------------------------------
-- Per-frame: hold the dash velocity for its short window, regenerate stamina, update HUD
-- ---------------------------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	if hrp and os.clock() < dashUntil then
		-- re-assert the horizontal burst (Humanoid control would otherwise damp it) while keeping gravity Y
		local v = hrp.AssemblyLinearVelocity
		-- re-derive the horizontal direction from current velocity and re-assert the burst magnitude
		local h = Vector3.new(v.X, 0, v.Z)
		if h.Magnitude > 1e-3 then
			local dir = h.Unit
			hrp.AssemblyLinearVelocity = Vector3.new(dir.X * G.dashSpeed, v.Y, dir.Z * G.dashSpeed)
		end
	end
	if stamina < G.staminaMax then
		stamina = math.min(G.staminaMax, stamina + G.staminaRegen * dt)
	end
	updateHud()
end)

updateHud()
