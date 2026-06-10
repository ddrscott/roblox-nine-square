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

-- M3 rank occupancy: the human enters at rank 9 (NW) and 8 dummies hold ranks 1..8 (King = rank 1 / C).
-- RotationService owns the occupant model + the dummy parts; we inject how to teleport the human so the
-- service stays decoupled from character handling. (Rotation/serve wiring is a later M3 step.)
local function placeHumanAtAssignedCell(cell: string)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then placeAtCell(plr.Character, cell) end
	end
end
local rotation = RotationService.new(placeHumanAtAssignedCell)
-- M3 step 4: replicate the human's current rank to every player (server-authoritative). The single
-- human shares one rank in M3, so we mirror it onto all players' "Rank" attribute; the client HUD
-- (RankHud) observes the attribute and shows "Rank N" / "KING". (M4's real bots get per-player ranks.)
rotation._setHumanRank = function(rank: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		plr:SetAttribute("Rank", rank)
	end
end
rotation:placeAll()
print("[NineSquare] rotation occupancy ready (human rank 9 / " .. tostring(rotation:humanCell()) .. ", dummies ranks 1..8)")

-- M4 step 1: the bot volley resolver. Each Heartbeat (after bc:step) it intercepts a descending Flight
-- ball at the contact window over a BOT-occupied square and either volleys it onward (outer->C / King->
-- outer) or misses -> floor fault -> rotation. Server-authoritative; the human's physical volley is
-- untouched. Constructed here because it needs the live `rotation` + `bc`.
local bots = BotController.new(rotation, bc)

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
	if rotation:isHumanKing() then
		-- Human serves physically: park the ball hovering at C. rallyArmed flips true when they strike it.
		bc:resetToServe()
		print("[NineSquare] human is King -- hover-serve at C (jump-strike to serve)")
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

-- First floor contact of a rally: attribute the fault per PRD §6 and FLASH the OUT square red so everyone
-- immediately sees who's out -- but DO NOT rotate yet. The grid shift + re-serve are DEFERRED to onRest
-- (when the ball stops bouncing), which feels far less abrupt than snapping players to new squares while
-- the ball is still in the air. We only record the rank to rotate here. struck = square the ball was last
-- struck/served from; landed = square the ball first hit the floor in (nil = out of bounds).
bc.onLand = function(landed, struck)
	if not rallyArmed then return end          -- a stray landing outside an armed rally -> ignore
	rallyArmed = false

	-- Which square owns the fault (PRD §6)?
	local faultCell: string?
	if landed == nil then
		-- Out of bounds: the hitter (occupant of the struck square) faulted.
		faultCell = struck
		print("[NineSquare] FAULT (out-of-bounds) struck=" .. tostring(struck))
	elseif landed == struck then
		-- Self-square: the hitter failed to clear their own square.
		faultCell = struck
		print("[NineSquare] FAULT (self-square) cell=" .. landed)
	else
		-- Floor fault: the occupant of the landing square failed to return it (a dummy square always lands here).
		faultCell = landed
		print("[NineSquare] FAULT (floor / unreturned) cell=" .. landed)
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
	bc:step(dt, HitResolver.playerColliders())
	-- M4: after physics, let the bots resolve a volley/miss over their squares (server-authoritative).
	-- A bot volley calls bc:launch (keeps the rally armed); a miss lets the ball fall -> onLand fault.
	bots:resolve()
	-- Arm the rally the instant the ball enters Flight (a human King's physical jump-serve, or any volley):
	-- onLand only scores when a rally is armed. The dummy-King auto-serve arms itself in serveNextRally.
	if bc.phase == "Flight" and not rallyArmed then
		rallyArmed = true
	end
end)

-- Kick off the live loop: the starting King (a dummy at rank 1) serves the first rally.
serveNextRally()

-- Spawn placement: stand the human in their assigned ranked square (rank 9 = NW) plus a resync so the
-- late-loading client gets ball state.
local function placeAtCourtAndSync(char: Model)
	local cell = rotation:humanCell() or "NW"
	placeAtCell(char, cell)
	task.delay(1, function() bc:resync() end)
end
local function hook(plr: Player)
	-- Seed the rank attribute immediately so a (re)joining player's HUD shows their current rank, even
	-- before the next rotation pushes it. _syncHumanRank also re-asserts it on placeHuman/placeAll.
	plr:SetAttribute("Rank", rotation:humanRank())
	if plr.Character then placeAtCourtAndSync(plr.Character) end
	plr.CharacterAdded:Connect(placeAtCourtAndSync)
end
Players.PlayerAdded:Connect(hook)
for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
