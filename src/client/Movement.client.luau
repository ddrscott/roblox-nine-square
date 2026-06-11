--!strict
-- StarterPlayer.StarterPlayerScripts.Movement
--
-- Client-side movement skill moves that raise the skill ceiling and feed the velocity-proportional
-- strike. The server's HitResolver reports the LOCAL character's replicated HumanoidRootPart
-- AssemblyLinearVelocity as the player hit-sphere's velocity, which BallController folds into its
-- moving-sphere collision, so every burst applied here flows straight into the strike rebound with
-- NO strike-formula change.
--
-- M5.4 ANTI-CHEAT: this client logic is now a PROPOSAL only -- the stamina pool + dash/flip gating here
-- are for local feel/feedback, but they are NOT trusted. The server (HitResolver) independently CLAMPS
-- the replicated velocity to a plausible max, caps per-frame position jumps (anti-teleport) and MIRRORS
-- the stamina pool server-side, so a tampered client that removes the gating below, spoofs its HRP
-- velocity, or warps cannot manufacture a super-hit or warp the collider into the ball. Server-authoritative.
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
-- HUD: BIND the stamina fill to the StarterGui-authored stamina bar (no layout built here). The bar is
-- authored in the `NineSquareHUD` TopRight cluster (StaminaBar > Track > Fill, with a readable caption),
-- laid out + scaled by the standard HUD system (HudBuilder). This script only drives the Fill's width +
-- colour off the local stamina pool -- the dash/flip/stamina LOGIC below is unchanged. If the authored
-- bar is absent (fresh place) HudBuilder self-heals the default tree, so this binding always resolves.
-- ---------------------------------------------------------------------------------------------------
local HudBuilder = require(RS:WaitForChild("HudBuilder"))
local playerGui = player:WaitForChild("PlayerGui")
local hud = HudBuilder.get(playerGui)
local track = hud:WaitForChild("TopRight"):WaitForChild("StaminaBar"):WaitForChild("Track")
local barFill = track:WaitForChild("Fill") :: Frame

local function updateHud()
	local frac = stamina / G.staminaMax
	barFill.Size = UDim2.fromScale(frac, 1)
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
local dashHorizVel: Vector3? = nil  -- the dash's horizontal velocity (X/Z, Y=0); carried through a jump
                                    -- arc (re-asserted each airborne frame to beat air control) and
                                    -- released on landing so normal ground control resumes.

-- keep the local avatar upright through dash bursts and flip landings: the sharp velocity changes
-- here (and finishing a flip mid-rotation) otherwise stumble the Humanoid into its trip/ragdoll states.
-- States reset per character, so this is re-applied on every CharacterAdded via bindCharacter.
local function disableTripStates(h: Humanoid)
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end

-- More force to the ball: boost the local character's jump velocity by jumpVelocityMult (~+30%). The
-- velocity-proportional strike folds the HRP's upward velocity into the rebound, so a faster jump =
-- a harder jump-strike. We scale the Humanoid's OWN default JumpPower (UseJumpPower=true) -- each fresh
-- character starts at the engine default, so reading-then-scaling here never compounds across respawns.
local function boostJump(h: Humanoid)
	h.UseJumpPower = true
	h.JumpPower = h.JumpPower * G.jumpVelocityMult
end

local function bindCharacter(char: Model)
	hrp = char:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	disableTripStates(humanoid)
	boostJump(humanoid)
	usedAirJump = false
	dashUntil = 0
	dashHorizVel = nil
	-- reset the extra jump AND release carried dash momentum whenever we touch ground, so normal
	-- ground walking resumes (no infinite slide).
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			usedAirJump = false
			dashHorizVel = nil
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
	-- remember the dash's HORIZONTAL velocity; if we go airborne (jump mid-dash), the Heartbeat
	-- maintainer re-asserts this each frame through the jump arc so the dash momentum carries.
	dashHorizVel = Vector3.new(dir.X * G.dashSpeed, 0, dir.Z * G.dashSpeed)
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
		if a >= 1 then
			conn:Disconnect()
			-- land UPRIGHT: keep current position + facing yaw, zero pitch/roll so the spin never
			-- finishes tilted (which would stumble the avatar). Re-flatten the look vector to a yaw.
			local look = h.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			flat = (flat.Magnitude > 1e-3) and flat.Unit or Vector3.new(0, 0, -1)
			h.CFrame = CFrame.lookAt(h.Position, h.Position + flat)
			return
		end
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
	local newX = cur.X + horiz.X * G.flipForwardBoost
	local newZ = cur.Z + horiz.Z * G.flipForwardBoost
	hrp.AssemblyLinearVelocity = Vector3.new(newX, G.flipUpVelocity, newZ)
	-- if we're carrying dash momentum, fold the flip's forward boost into it so the maintainer keeps
	-- the composed horizontal (dash -> jump -> flip preserves + adds to the dash horizontal).
	if dashHorizVel then
		dashHorizVel = Vector3.new(newX, 0, newZ)
	end
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
	elseif hrp and dashHorizVel then
		if isAirborne() then
			-- the dash burst window has ended but we're still airborne carrying its momentum: pin the
			-- dash's HORIZONTAL each frame to beat Roblox air control, leaving Y to the jump/flip + gravity.
			-- Released on landing (StateChanged) so normal ground walking resumes.
			local v = hrp.AssemblyLinearVelocity
			local hv = dashHorizVel :: Vector3
			hrp.AssemblyLinearVelocity = Vector3.new(hv.X, v.Y, hv.Z)
		else
			-- dash ended while grounded (a plain ground dash, never jumped): drop the carry so a LATER
			-- unrelated jump doesn't inherit stale dash momentum.
			dashHorizVel = nil
		end
	end
	if stamina < G.staminaMax then
		stamina = math.min(G.staminaMax, stamina + G.staminaRegen * dt)
	end
	updateHud()
end)

updateHud()
