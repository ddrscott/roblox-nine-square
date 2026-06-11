--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, physical contact detection, the Heartbeat loop, and court spawn.
-- Serving is physical: the ball hovers at center; a player gets under it and jumps to strike it.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local G = require(RS.GridConfig)
local ns = game.ServerScriptService:WaitForChild("NineSquare")
local BallController = require(ns.BallController)
local MatchService = require(ns.MatchService)
local HitResolver = require(ns.HitResolver)
local RotationService = require(ns.RotationService)
local BotController = require(ns.BotController)

-- Overhead noon sun so the frame casts straight-down grid shadows on the floor.
local function setupLighting()
	local L = game:GetService("Lighting")
	L.GeographicLatitude = 23.5   -- cancels Roblox's ~23.5deg sun tilt: noon sun ends up at the zenith
	L.ClockTime = 12
	L.GlobalShadows = true
	L.Brightness = 3
	L.Ambient = Color3.fromRGB(150, 150, 160)        -- lift interior light (the gym ceiling blocks the sun)
	L.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	-- Raise the Bloom threshold so only true light sources (the Neon ceiling fixtures) bloom.
	-- At the default Threshold = 2 the lit ball exceeded it and rendered as a glowing white halo.
	-- Self-heals on a fresh place: set it if a Bloom child exists.
	local bloom = L:FindFirstChildWhichIsA("BloomEffect")
	if bloom then bloom.Threshold = 3.5 end
	-- NOTE: Lighting.Technology (ShadowMap/Future) cannot be set by scripts; set it once in Studio Properties.
end

print("[NineSquare] server starting")
setupLighting()
MatchService.buildGym(Vector3.new(0, 0, 200))
MatchService.buildArena(Vector3.new(0, 0, 200))
local bc = BallController.new()
print("[NineSquare] arena + ball ready")

-- The ball reports physics events; the game owns the rules, feedback, and re-serve timing.
local function playOof()
	local s = Instance.new("Sound"); s.SoundId = "rbxasset://sounds/uuhhh.mp3"; s.Volume = 1
	s.Parent = bc.ball; s:Play(); Debris:AddItem(s, 3)
end

-- Impact SFX on EVERY player strike (human + all 8 bots): both go through bc.onPlayerHit, so playing it
-- there covers everyone. Server-side + parented to the ball -> it replicates to all clients and is 3D/
-- positional (emitted from the ball). We CLONE a template per hit (each plays on its own instance) so a
-- fast rally never cuts the previous bump off; Debris reaps the clone after its tail. A tiny PlaybackSpeed
-- jitter, seeded from a monotonic hit counter (NOT math.random in the hot loop), adds liveliness
-- deterministically. Tunables (id/volume/range/jitter) live in GridConfig. Audio only -- no physics touched.
local impactTemplate = Instance.new("Sound")
impactTemplate.Name = "ImpactSound"
impactTemplate.SoundId = G.impactSoundId
impactTemplate.Volume = G.impactSoundVolume
impactTemplate.RollOffMaxDistance = G.impactSoundRange
impactTemplate.RollOffMode = Enum.RollOffMode.InverseTapered
local impactHitCount = 0
local function playImpact()
	impactHitCount += 1
	local s = impactTemplate:Clone()
	-- deterministic pitch jitter from the hit counter: maps the counter onto [-jitter, +jitter]
	if G.impactPitchJitter > 0 then
		local phase = ((impactHitCount * 0.6180339887) % 1) * 2 - 1   -- golden-ratio walk over (-1, 1)
		s.PlaybackSpeed = 1 + phase * G.impactPitchJitter
	end
	s.Parent = bc.ball
	s:Play()
	Debris:AddItem(s, math.max(2, s.TimeLength + 0.5))
end

-- Both the human's strikes and the bots' volleys resolve through the SAME BallController collision and fire
-- onPlayerHit (serve + mid-flight return alike), so this one hook gives every player a bump. Notification
-- only -- the ball's physics are unchanged.
bc.onPlayerHit = function(_struckCell, _targetCell, _wasServe)
	playImpact()
end

-- NOTE: the rally loop (onLand -> fault attribution -> rotation -> next King serve, and onRest -> serve)
-- is wired below, AFTER the RotationService exists -- it needs `rotation` and `serveNextRally`.

-- The default SpawnLocation is by the old Obby (z~0), but the court is at z=200.
-- Teleport a character's HRP to a given cell (M3 generalizes the old always-centre placement so the
-- human can stand in their ranked square, not just "C").
local function placeAtCell(char: Model, cell: string)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then
		hrp.CFrame = CFrame.new(G.cellCenter(cell) + Vector3.new(0, 5, 0))
		print(("[NineSquare] placed %s at %s (%s)"):format(char.Name, cell, tostring(hrp.Position)))
	else
		warn("[NineSquare] no HumanoidRootPart to place: " .. char.Name)
	end
end

-- M5.1 occupancy: HUMANS fill seats as they join, BOTS backfill the rest -- always a full 9-square. The
-- service starts all 9 seats as bots; PlayerAdded seats each joiner at the entry rank (displacing a bot),
-- PlayerRemoving backfills (spectator-hook -> bot). RotationService owns the occupant model + rig parts;
-- we inject how to teleport a SPECIFIC seated player so the service stays decoupled from character handling.
local function placeOnePlayer(player: Player, cell: string)
	if player.Character then placeAtCell(player.Character, cell) end
end
local rotation = RotationService.new(placeOnePlayer)
-- Replicate EACH seated player's OWN rank (server-authoritative; per-player now -- a human/bot mix means
-- every human reads ITS seat). The client HUD (RankHud) observes the player's "Rank" attribute and shows
-- "Rank N" / "KING".
rotation._setHumanRank = function(player: Player, rank: number)
	player:SetAttribute("Rank", rank)
end
-- M5.1 leave-backfill hook: M5.2's spectator queue will set rotation._backfillHook to seat the longest-
-- waiting spectator into a freed seat. Until then it stays nil and unseatHuman falls through to a fresh bot
-- (so a leaving human never leaves a rank empty). Left intentionally unset here.
rotation:placeAll()
print(("[NineSquare] rotation occupancy ready (full 9-square: all bots until humans join; King = %s)")
	:format(tostring(rotation:kingOccupant().id)))

-- Bot hitter (physical rework). Each Heartbeat (BEFORE bc:step) the bots driver commits a swing for a
-- descent toward a bot square, slides the bot's hit-sphere collider to an OFF-CENTER stand position and
-- jumps it into the ball; those bot colliders are merged with the human's and fed to bc:step, so the SAME
-- swept, velocity-proportional collision resolves bot hits. The aim emerges from the off-center contact
-- (outer bot -> C / King -> outer); a miss under-jumps -> no contact -> floor fault -> rotation. No
-- artificial bc:launch. Constructed here because it needs the live `rotation` + `bc`.
local bots = BotController.new(rotation, bc)

-- Last-saved-square pipe highlight (visual). A "save" = the ball LEGALLY clears the hitter's square OVER a
-- pipe (ownership transfers off the struck square). This is the SAME over-pipe signal the fault path uses,
-- so the highlight and the fault logic agree: a low deflect that slides UNDER a pipe is NOT a save (it never
-- clears), and the King's first serve out of C still counts (it clears C over a pipe). On each save we light
-- up the cleared square's overhead frame pipes (MatchService.highlightSavedCell); it persists until the next.
local lastSavedCell: string? = nil
local function creditSave(cell: string?)
	if not cell then return end
	lastSavedCell = cell
	MatchService.highlightSavedCell(cell)
	print("[NineSquare] SAVE -> " .. cell .. " (cleared over a pipe; last-saved pipes highlighted)")
end
-- The King's SERVE technically clears C over a pipe, but (per the save-highlight task) a serve is not a
-- "save" -- a save is a RETURN. This guard consumes the serve's own clear so only subsequent volleys light
-- the pipes. Set true wherever a rally is served (human jump-serve / dummy auto-serve), cleared on its clear.
local serveClearPending = false
-- The authoritative save: the ball cleared the hitter's square over a pipe (a human or bot RETURN). onClear
-- fires once, when ownership first leaves the struck square, so a low deflect never credits a save. The
-- King's serve clear is swallowed by serveClearPending so it isn't mistaken for a save.
bc.onClear = function(struckCell, _ownerCell)
	if serveClearPending then
		serveClearPending = false   -- this clear is the serve itself, not a return -> not a save
		return
	end
	creditSave(struckCell)
end

-- M3 step 4 -- the dethrone moment: when the King (rank 1) faults, the rank-2 occupant takes the
-- throne. Make it unmistakable: flash the King square (C), play a distinct chime, and log who's King.
-- (Full banner/VFX is M6; this is the M3-legibility stub.)
local function playDethrone()
	local s = Instance.new("Sound"); s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	s.Volume = 1.2; s.Parent = bc.ball; s:Play(); Debris:AddItem(s, 3)
end
rotation.onDethrone = function(newKing)
	print("[NineSquare] DETHRONED -- " .. newKing.id .. " takes the throne (rank 1 / C)")
	MatchService.flashCell("C")
	playDethrone()
end

-- ============================================================================================
-- M3 step 3 -- the live king-of-the-hill loop: King serve -> rally -> fault attribution -> rotation
-- -> the new King serves. Server-authoritative; clients send no fault/rotation/serve decisions.
-- ============================================================================================

-- One rally is "in flight" at a time. `rallyArmed` is true once a serve puts the ball into play and
-- guards the loop so each rally faults + rotates EXACTLY once (onLand fires once per rally; onRest may
-- also fire, and a dead ball can be batted around -- none of that should re-fault or double-serve).
local rallyArmed = false

-- Deferred rotation: on a fault we mark the OUT square red AT THE LANDING (onLand) so everyone sees who's
-- out, but we DON'T rotate yet -- we record the rank to rotate here and run the shift only once the ball
-- comes to REST (onRest). Survives a dead ball being batted around mid-settle: it stays set until onRest
-- consumes it, so rotation happens exactly once, when the ball finally stops.
local pendingFaultRank: number? = nil

-- Auto-serve: launch the ball from the King square (C) frame point so it ARCS DOWN INTO the target
-- square and lands on its floor (where onLand will report `targetCell` -> that dummy faults). The arc
-- peaks `serveArcApex` above the launch height, then falls to the target square's floor (y = ballRadius).
-- Reuses bc:launch (M1 physics unchanged) -- we only compute the v0 that produces the arc.
local function serveToTarget(targetCell: string)
	local from = G.cellFramePoint("C")
	local landCenter = G.cellCenter(targetCell)
	local to = Vector3.new(landCenter.X, G.ballRadius, landCenter.Z)  -- the floor-resting point in the target square
	local g = workspace.Gravity
	-- Peak height above the launch point so the ball clearly arcs up over the frame and drops in.
	local peakY = from.Y + G.serveArcApex
	local rise = math.max(peakY - from.Y, 1)
	local vy = math.sqrt(2 * g * rise)                 -- vertical speed to reach `rise` above the launch point
	-- Flight time: up to the apex, then down to the (lower) floor target. Solve the fall from apex to to.Y.
	local tUp = vy / g
	local tDown = math.sqrt(2 * math.max(peakY - to.Y, 0) / g)
	local tTotal = math.max(tUp + tDown, 0.1)
	local horiz = Vector3.new(to.X - from.X, 0, to.Z - from.Z) / tTotal
	local v0 = Vector3.new(horiz.X, vy, horiz.Z)
	bc:launch(from, v0)
	print(("[NineSquare] dummy-King auto-serve C -> %s (v0=%s)"):format(targetCell, tostring(v0)))
end

-- Serve the next rally for the CURRENT King (rank 1 / C). Human King -> hover at C for a physical M1
-- jump-strike (rally arms on first contact, in bc:step). Dummy King -> auto-serve after serveDelay to a
-- random outer square. Idempotent-ish: we only serve when the ball is idle (Rest/Live), not mid-rally.
local function serveNextRally()
	rallyArmed = false
	serveClearPending = true   -- the upcoming serve's over-pipe clear is the serve itself, not a save -> swallow it
	-- Clear last rally's save highlight so the pipe glow only ever shows the last save of the CURRENT rally.
	lastSavedCell = nil
	MatchService.clearSaveHighlight()
	if rotation:isHumanKing() then
		-- Human King serves physically: park the ball hovering at C. rallyArmed flips true when the human
		-- King strikes it. Keyed off byRank[1] (the SPECIFIC human King), not a hard-coded single human.
		bc:resetToServe()
		local king = rotation:kingPlayer()
		print(("[NineSquare] human King (%s) -- hover-serve at C (jump-strike to serve)")
			:format(king and king.Name or "?"))
	else
		-- Dummy King: wind up, then auto-serve to a random outer square.
		local target = G.outerCells[math.random(1, #G.outerCells)]
		bc:resetToServe()                       -- park at C so it visibly sits at the throne during wind-up
		print(("[NineSquare] dummy King winds up -- auto-serving to %s in %.1fs"):format(target, G.serveDelay))
		task.delay(G.serveDelay, function()
			-- Only serve if nothing else has put the ball in play in the meantime.
			if not rallyArmed and (bc.phase == "Live" or bc.phase == "Rest") then
				rallyArmed = true
				serveToTarget(target)
			end
		end)
	end
end

-- First floor contact of a rally: attribute the fault per PRD §6 (corrected for over-the-pipe ownership)
-- and FLASH the OUT square red so everyone immediately sees who's out -- but DO NOT rotate yet. The grid
-- shift + re-serve are DEFERRED to onRest (when the ball stops bouncing), which feels far less abrupt than
-- snapping players to new squares while the ball is still in the air. We only record the rank to rotate
-- here. struck = square the ball was last struck/served from; landed = square the ball first hit the floor
-- in (nil = out of bounds); owner = the square the ball LEGALLY belongs to (it only transfers when the ball
-- clears a pipe -- so a low deflect under a pipe into a neighbour keeps owner == struck and faults the
-- HITTER, not the neighbour). We attribute by owner, NOT the raw landing XZ.
bc.onLand = function(landed, struck, owner)
	if not rallyArmed then return end          -- a stray landing outside an armed rally -> ignore
	rallyArmed = false

	-- Which square owns the fault (PRD §6, corrected for over-the-pipe ownership)?
	local faultCell: string?
	if landed == nil then
		-- Out of bounds: the hitter (occupant of the struck square) faulted. OOB is always on the hitter.
		faultCell = struck
		print(("[NineSquare] FAULT (out-of-bounds) struck=%s owner=%s"):format(tostring(struck), tostring(owner)))
	elseif owner == struck then
		-- The ball never LEGALLY left the hitter's square: it either landed back in it, or was deflected LOW
		-- into a neighbour WITHOUT clearing a pipe. Either way the hitter failed to clear -> hitter faults.
		-- (Bug fix: the low-deflected neighbour `landed` is NOT knocked out.)
		faultCell = struck
		print(("[NineSquare] FAULT (never cleared over a pipe) struck=%s landed=%s owner=%s")
			:format(tostring(struck), tostring(landed), tostring(owner)))
	else
		-- The ball legally cleared a pipe into `owner`'s square; its occupant failed to return it -> they fault.
		faultCell = owner
		print(("[NineSquare] FAULT (floor / unreturned) owner=%s landed=%s"):format(tostring(owner), tostring(landed)))
	end

	-- Flash the OUT square red and hold it through the land->rest settle (faultFlashDuration covers the
	-- bounce-out window), plus the oof. This is the immediate "who's out" read; the rotation comes later.
	MatchService.flashCell(faultCell, G.faultFlashDuration); playOof()

	local faultRank = faultCell and G.rankForCell(faultCell)
	if faultRank then
		local occ = rotation:occupantAtCell(faultCell)
		print(("[NineSquare] fault marked (rotation deferred to rest): cell=%s rank=%d occupant=%s")
			:format(tostring(faultCell), faultRank, occ and occ.id or "?"))
		pendingFaultRank = faultRank          -- rotate at onRest, not now
	else
		warn("[NineSquare] could not attribute fault (no rank for cell " .. tostring(faultCell) .. ")")
	end
end

-- Ball has bounced out its energy and stopped. NOW we run the deferred rotation (if a fault is pending):
-- rotate everyone toward the King (placeAll re-places them), THEN after a beat the new King serves the
-- next rally. This is the moment the OUT player rotates -- the red panel has been showing who's out the
-- whole settle. (If a dead ball got batted mid-settle, the pending fault still stands and rotates here.)
bc.onRest = function()
	if pendingFaultRank then
		local faultRank = pendingFaultRank
		pendingFaultRank = nil
		print(("[NineSquare] ball at rest -- applying deferred rotation (rank %d)"):format(faultRank))
		rotation:rotateOnFault(faultRank)
	end
	task.delay(G.serveDelay, function()
		if bc.phase == "Rest" and not rallyArmed then
			serveNextRally()
		end
	end)
end

-- Physical contact is now a real collision inside the ball's step: each Heartbeat we gather the
-- players' moving hit-spheres and hand them to bc:step, which resolves a hit only on penetration +
-- approach (so a descending player can't pull a rising ball down) and bounces the ball off the sphere
-- exactly like it bounces off the pipes/walls/floor. No more proximity trigger or time cooldown.
RunService.Heartbeat:Connect(function(dt)
	-- First drive the bots: each active swing slides its hit-sphere to its off-center stand + jumps into
	-- the ball, returning this frame's bot colliders. We combine them with the human's moving hit-spheres
	-- and hand the WHOLE list to bc:step, so the same swept collision resolves both. A bot hit thus flies
	-- via the real physical strike (no bc:launch); a missed/under-jumped swing makes no contact -> the ball
	-- falls -> onLand fault. The human's volley is unchanged.
	local colliders = HitResolver.playerColliders()
	for _, c in ipairs(bots:update(dt)) do
		table.insert(colliders, c)
	end
	bc:step(dt, colliders)
	-- Lifelike idle: AFTER the swing update + bc:step, drive every NON-receiver bot's idle ready-stance
	-- (toe-bob + weight-sway + occasional ready steps) and lean it toward the LIVE ball, so the whole grid
	-- reads as alive instead of frozen. Receivers (mid-swing) are skipped inside update_idle -- their
	-- intercept + jump stays the dominant motion. Ball is "live" for tracking during Flight/Settling.
	local ballLive = (bc.phase == "Flight" or bc.phase == "Settling")
	local ballXZ = ballLive and Vector3.new(bc.ball.Position.X, 0, bc.ball.Position.Z) or nil
	bots:update_idle(dt, ballXZ)
	-- Arm the rally the instant the ball enters Flight (a human King's physical jump-serve, or any volley):
	-- onLand only scores when a rally is armed. The dummy-King auto-serve arms itself in serveNextRally.
	if bc.phase == "Flight" and not rallyArmed then
		rallyArmed = true
	end
end)

-- Kick off the live loop: the starting King (a dummy at rank 1) serves the first rally.
serveNextRally()

-- ============================================================================================
-- M5.1 -- JOIN / LEAVE wiring. Humans fill seats (entry rank, displacing a bot), bots backfill on leave.
-- Each seated human binds its OWN client (camera / RankHud / movement / hit-sphere) to ITS server-assigned
-- seat via the per-player "Rank" attribute (RotationService._setHumanRank) + the per-player spawn cell;
-- HitResolver already feeds EVERY player's hit collider to bc:step, so each seated human strikes from its
-- own square. Spectator overflow (humans > 9) is M5.2 -- here seatHuman just returns nil and we log it.
-- ============================================================================================

-- Spawn / respawn a SEATED player into their current ranked square. Late-loading clients also get a ball
-- resync. A player with no seat (overflow / spectator, M5.2) is left at the default spawn for now.
local function placeAtCourtAndSync(plr: Player, char: Model)
	local cell = rotation:cellOfPlayer(plr)
	if cell then
		placeAtCell(char, cell)
	end
	task.delay(1, function() bc:resync() end)
end

local function onJoin(plr: Player)
	-- Seat the joiner at the entry rank (displaces the lowest-status bot). seatHuman also places them +
	-- pushes their "Rank" attribute. nil = overflow (all 9 seats human) -> M5.2 spectator queue.
	local rank = rotation:seatHuman(plr)
	if rank then
		print(("[NineSquare] %s joined -> seated at rank %d (%s)"):format(plr.Name, rank, tostring(rotation:cellOfPlayer(plr))))
	else
		-- Overflow: no seat. Seed a benign attribute so the HUD isn't blank; M5.2 owns the spectator path.
		plr:SetAttribute("Rank", 0)
		print(("[NineSquare] %s joined -> NO SEAT (overflow; spectator queue is M5.2)"):format(plr.Name))
	end
	-- Bind this player's character to its seat on (re)spawn.
	if plr.Character then placeAtCourtAndSync(plr, plr.Character) end
	plr.CharacterAdded:Connect(function(char) placeAtCourtAndSync(plr, char) end)
end

local function onLeave(plr: Player)
	-- Backfill the freed seat (spectator hook -> bot) so a rank is never empty + the game never wedges.
	local repl = rotation:unseatHuman(plr)
	if repl then
		print(("[NineSquare] %s left -> seat backfilled with %s %s"):format(plr.Name, repl.kind, repl.id))
	end
end

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
-- Seat any players already connected at boot (Studio Play seats the local player here).
for _, plr in ipairs(Players:GetPlayers()) do onJoin(plr) end
