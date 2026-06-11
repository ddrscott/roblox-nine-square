--!strict
-- ServerScriptService.NineSquare.HitResolver
-- Geometry/state provider for the players' hit-spheres + the SERVER-AUTHORITY clamp choke point (M5.4).
--
-- Each character carries a body-sized contact sphere (centre = Head + hitZoneYOffset, radius =
-- hitZoneRadius) that moves with the player's current velocity. BallController folds these in as
-- MOVING-sphere colliders during its collision step (alongside the pipes/walls/floor) so a contact is a
-- real penetration+rebound, not a one-shot proximity trigger. This module owns no ball logic; it reports
-- where the spheres are -- but, because a client could SPOOF its replicated HumanoidRootPart, it is also
-- the TRUST BOUNDARY: the client only PROPOSES its character position/velocity, and the server VALIDATES
-- it here before it can ever reach bc:step.
--
-- M5.4 server-authority hardening (clamp the INPUTS, never the deterministic ball physics or the strike
-- formula -- legitimate play, always under these ceilings, is untouched; the clamps only bite on cheating):
--   * VELOCITY CLAMP -- the collider velocity magnitude is capped to GridConfig.maxStrikeSpeed, derived
--     from the movement tunables, so a spoofed 1000-stud HRP velocity can't manufacture a super-hit.
--   * ANTI-TELEPORT -- the collider CENTRE may move at most GridConfig.maxFrameDisplacement studs per
--     frame from its last validated centre, so a client can't warp the collider straight into the ball.
--     The clamped position also bounds the effective velocity (we don't trust a warp's velocity).
--   * SERVER STAMINA ECONOMY -- the server mirrors each player's stamina pool (regen + spend, same
--     formula as the client). With an empty pool a client can't legitimately dash/flip, so its burst can't
--     exceed run/jump motion; we then clamp that player's collider velocity to the lower
--     maxStrikeSpeedNoStamina ceiling. A spend is inferred when the (already velocity-clamped) burst
--     exceeds plain movement -- a dash/flip-magnitude frame debits a dash cost. So a client can't fake
--     stamina to keep dashing into every hit and cheat the velocity-proportional strike.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local HitResolver = {}

export type PlayerCollider = { center: Vector3, radius: number, vel: Vector3, player: Player }

-- Per-player server-side validation state, keyed by UserId (survives respawns; reaped on leave).
--   lastCenter -- the last VALIDATED collider centre (for the anti-teleport per-frame displacement cap)
--   lastTime   -- os.clock() of the last validation (real dt for stamina regen + displacement timing)
--   stamina    -- server-mirrored stamina pool (0..staminaMax); regenerates over time, debited on a burst
type PlayerState = { lastCenter: Vector3?, lastTime: number?, stamina: number }
local state: { [number]: PlayerState } = {}

-- A speed at/above which the frame's burst could only have come from a dash/flip (not plain run+jump).
-- Used to INFER a server-side stamina spend: if the validated velocity is this fast and the pool can pay,
-- debit a dash cost; if the pool is empty the velocity is additionally clamped to the no-stamina ceiling.
local BURST_INFER_SPEED = G.maxStrikeSpeedNoStamina

local function getState(userId: number): PlayerState
	local s = state[userId]
	if not s then
		s = { lastCenter = nil, lastTime = nil, stamina = G.staminaMax }
		state[userId] = s
	end
	return s
end

-- Clear a leaver's validation state so a re-joiner with the same UserId starts fresh (and we don't leak).
function HitResolver.forgetPlayer(plr: Player)
	state[plr.UserId] = nil
end

-- Clamp a vector's magnitude to `maxMag` (preserving direction). Zero/near-zero passes through.
local function clampMagnitude(v: Vector3, maxMag: number): Vector3
	local m = v.Magnitude
	if m <= maxMag or m < 1e-6 then return v end
	return v * (maxMag / m)
end

-- One moving-sphere collider per player that has a character with a HumanoidRootPart, AFTER server-side
-- validation of the proposed position + velocity. Centre is the hit-zone (Head raised by hitZoneYOffset);
-- velocity is the (clamped) HRP assembly velocity. BallController decides penetration/approach + rebound.
-- The CALLER (NineSquareServer) is responsible for only feeding SEATED players' colliders to bc:step
-- (spectators/unseated players never affect the ball); this function reports every player's validated
-- sphere, and the seat filter happens at the call site.
function HitResolver.playerColliders(): { PlayerCollider }
	local list: { PlayerCollider } = {}
	local now = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local head = char and char:FindFirstChild("Head")
		local base = (head and head:IsA("BasePart") and head) or hrp   -- centre the contact sphere on the head
		if base and base:IsA("BasePart") and hrp and hrp:IsA("BasePart") then
			local s = getState(plr.UserId)
			local dt = (s.lastTime and (now - s.lastTime)) or 0
			s.lastTime = now

			-- ----- SERVER STAMINA ECONOMY: regenerate the mirrored pool over real time (same formula as the
			-- client). Spends are inferred below from the (clamped) burst velocity. -----
			if dt > 0 and s.stamina < G.staminaMax then
				s.stamina = math.min(G.staminaMax, s.stamina + G.staminaRegen * dt)
			end

			-- ----- ANTI-TELEPORT: clamp the proposed collider CENTRE to at most maxFrameDisplacement studs
			-- from the last validated centre, so a warp can't drop the collider inside the ball in one frame.
			-- The first sample (no lastCenter) is trusted as-is (spawn/respawn). -----
			local proposed = base.Position + Vector3.new(0, G.hitZoneYOffset, 0)
			local center = proposed
			if s.lastCenter then
				local delta = proposed - s.lastCenter
				if delta.Magnitude > G.maxFrameDisplacement then
					center = s.lastCenter + delta.Unit * G.maxFrameDisplacement
				end
			end
			s.lastCenter = center

			-- ----- VELOCITY CLAMP: cap the proposed HRP velocity to the plausible-strike ceiling derived
			-- from the movement tunables, so a spoofed velocity can't manufacture a super-hit. -----
			local vel = clampMagnitude(hrp.AssemblyLinearVelocity, G.maxStrikeSpeed)

			-- ----- STAMINA-GATED BURST: a burst this fast could only be a dash/flip. If the mirrored pool can
			-- pay, debit a dash cost (the spend). If it's empty, the client can't legitimately have dashed --
			-- clamp its velocity to the lower no-stamina ceiling so an empty pool can't cheat the strike. -----
			if vel.Magnitude >= BURST_INFER_SPEED then
				if s.stamina >= G.dashCost then
					s.stamina = math.max(0, s.stamina - G.dashCost)
				else
					vel = clampMagnitude(vel, G.maxStrikeSpeedNoStamina)
				end
			end

			plr:SetAttribute("ServerStamina", s.stamina)   -- (debug/inspection) the server's authoritative pool

			table.insert(list, {
				center = center,
				radius = G.hitZoneRadius,
				vel = vel,
				player = plr,
			})
		end
	end
	return list
end

return HitResolver
