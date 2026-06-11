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
local StatsService = require(ns.StatsService)

-- Clear-day midday sun. The gym is enclosed (interior lit by the Neon ceiling fixtures + Ambient), but the
-- side windows + the camera wall-fade now reveal the outdoor park, so we set a bright clear-day Sky + a sun-up
-- ClockTime here. Interior gym lighting is UNCHANGED (same Ambient lift + Bloom threshold that keep the gym
-- readable and stop the lit ball blooming). Sky/Atmosphere live in GridConfig so they're tunable.
-- BUILD-ONCE / APPLY-ONCE. Like buildArena/buildGym, lighting is now stamped ONCE so manual Studio tweaks to
-- Lighting / Sky / Atmosphere PERSIST across Play instead of being re-clobbered every run. A sentinel attribute
-- (Lighting.NineSquareLit) records that we've applied the clear-day look; once set we return early and leave
-- everything tweakable. A fresh place (no sentinel) still self-builds the full lighting + Sky + Atmosphere.
local function setupLighting()
	local L = game:GetService("Lighting")
	-- Apply-once sentinel: if we've already set the clear-day look, leave Lighting/Sky/Atmosphere alone so
	-- hand-tweaks (e.g. a custom Sky or brightness) survive Play. Self-heal still covers a missing Sky/Atmosphere.
	if L:GetAttribute("NineSquareLit") then
		if not L:FindFirstChildWhichIsA("Sky") then
			local sky = Instance.new("Sky"); sky.Name = "ClearDaySky"
			sky.SunAngularSize = G.skySunAngularSize; sky.SkyboxOrientation = Vector3.new(0, 0, 0)
			sky.CelestialBodiesShown = true; sky.Parent = L
		end
		if not L:FindFirstChildWhichIsA("Atmosphere") then
			local atmos = Instance.new("Atmosphere")
			atmos.Density = G.atmosphereDensity; atmos.Haze = G.atmosphereHaze
			atmos.Color = G.skyColorBottom; atmos.Decay = Color3.fromRGB(106, 112, 125); atmos.Parent = L
		end
		return
	end
	-- Zenith sun: GeographicLatitude 23.5 (cancels Roblox's baked ~23.5deg axial tilt) + ClockTime 12 (solar
	-- noon) puts the sun directly overhead, so Lighting:GetSunDirection() reads (0, 1, 0) (verified in Studio)
	-- and shadows fall straight down -- the overhead frame's shadow lands centered on the court, not skewed.
	L.GeographicLatitude = G.sunLatitude   -- 23.5: cancels the axial tilt so noon sun sits at the zenith
	L.ClockTime = G.outdoorClockTime       -- 12: solar noon, sun at its highest (straight overhead)
	L.GlobalShadows = true
	L.Brightness = 3
	L.Ambient = Color3.fromRGB(150, 150, 160)        -- lift interior light (the gym ceiling blocks the sun)
	L.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	-- Raise the Bloom threshold so only true light sources (the Neon ceiling fixtures) bloom.
	-- At the default Threshold = 2 the lit ball exceeded it and rendered as a glowing white halo.
	-- Self-heals on a fresh place: set it if a Bloom child exists.
	local bloom = L:FindFirstChildWhichIsA("BloomEffect")
	if bloom then bloom.Threshold = 3.5 end

	-- Clear-day Sky: bright blue gradient, a visible sun disc, soft default clouds. Build-once -- create the
	-- Sky only if one isn't already present, so a manual Sky tweak isn't clobbered on the first applied run.
	-- Roblox's default Sky textures give the soft clouds; we tune sun size for a bright, readable clear day.
	if not L:FindFirstChildWhichIsA("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "ClearDaySky"
		sky.SunAngularSize = G.skySunAngularSize
		sky.SkyboxOrientation = Vector3.new(0, 0, 0)
		-- bright clear-day cloud/sky gradient (uses Roblox's built-in skybox faces -> always load, no asset perms)
		sky.CelestialBodiesShown = true
		sky.Parent = L
	end

	-- Subtle Atmosphere for horizon depth/haze so the distant ground/hills read as far away (kept light so the
	-- day stays clear, not foggy). Idempotent: reuse an existing Atmosphere if present.
	local atmos = L:FindFirstChildWhichIsA("Atmosphere")
	if not atmos then atmos = Instance.new("Atmosphere"); atmos.Parent = L end
	atmos.Density = G.atmosphereDensity
	atmos.Haze = G.atmosphereHaze
	atmos.Color = G.skyColorBottom
	atmos.Decay = Color3.fromRGB(106, 112, 125)
	-- NOTE: Lighting.Technology (ShadowMap/Future) cannot be set by scripts; set it once in Studio Properties.
	-- Mark the clear-day look applied. Future Plays return early (above) and leave Lighting/Sky/Atmosphere
	-- tweakable. Delete this attribute in Studio to force a one-time re-stamp of the defaults.
	L:SetAttribute("NineSquareLit", true)
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

-- JUMP SQUEAK SFX (this task). A short squeak on EVERY human jump, emitted from the JUMPING player at a
-- VARIED playback speed each jump -- so everyone hears it positionally (mirrors the impact-SFX pattern, but
-- parented to the jumper's HumanoidRootPart instead of the ball). Server-side: we hook each human character's
-- `Humanoid.Jumping` (wired in onJoin -> CharacterAdded below) so the Sound replicates to all clients and is
-- 3D/positional. We CLONE a template per jump (so two quick jumps don't cut each other off), set a RANDOM
-- PlaybackSpeed in [jumpSoundPitchMin, jumpSoundPitchMax] for the "varied play speeds" feel, and Debris-reap
-- the clone after its tail. The repeating Humanoid.Jumping event is DEBOUNCED with a short per-character
-- cooldown (jumpSoundDebounce) so one jump = one sound. Driven by GridConfig.jumpSoundId -- a built-in
-- placeholder now; swapping in Scott's uploaded rubber-squeak.wav asset id is a one-value change. Bots jump
-- via a server-driven collider (no Humanoid jump), so they're excluded by design. Audio only -- no physics.
local jumpTemplate = Instance.new("Sound")
jumpTemplate.Name = "JumpSound"
jumpTemplate.SoundId = G.jumpSoundId
jumpTemplate.Volume = G.jumpSoundVolume
jumpTemplate.RollOffMaxDistance = G.jumpSoundRange
jumpTemplate.RollOffMode = Enum.RollOffMode.InverseTapered
local function playJump(hrp: BasePart)
	local s = jumpTemplate:Clone()
	-- Random PlaybackSpeed per jump (the "varied play speeds"): one-shot per jump, so math.random here is fine
	-- (not a hot per-frame loop like the impact jitter). lerp min..max.
	s.PlaybackSpeed = G.jumpSoundPitchMin + math.random() * (G.jumpSoundPitchMax - G.jumpSoundPitchMin)
	s.Parent = hrp
	s:Play()
	Debris:AddItem(s, math.max(2, s.TimeLength + 0.5))
end

-- Hook a single human character's jump: play the squeak from its HRP on each Humanoid.Jumping, debounced to
-- one-per-jump (the event fires repeatedly while rising). Called per CharacterAdded. Cleans up with the
-- character (the Humanoid is destroyed on respawn/leave, so the connection drops with it).
local function hookJumpSound(char: Model)
	local humanoid = char:WaitForChild("Humanoid", 5)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if not (humanoid and humanoid:IsA("Humanoid") and hrp and hrp:IsA("BasePart")) then return end
	local lastJumpT = 0
	humanoid.Jumping:Connect(function(active: boolean)
		if not active then return end                 -- Jumping fires (active=false) when the jump ends too
		local now = os.clock()
		if now - lastJumpT < G.jumpSoundDebounce then return end   -- debounce the repeating event -> one sound/jump
		lastJumpT = now
		playJump(hrp)
	end)
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

-- ============================================================================================
-- M5.6 -- HUD EVENT FEED. Brief, non-spammy on-screen feedback for the lobby moments a player needs to
-- read: a player joined/left, a spectator was auto-seated, someone was dethroned, someone took the King.
-- Server-authoritative: the server decides WHEN these fire (off the same occupancy model that drives
-- nameplates + rotation), and the client only renders a short-lived toast. We add a `HudEvent`
-- RemoteEvent under the existing NineSquareRemotes folder (self-healed here so a fresh place still works).
--   payload = { kind = "join"|"leave"|"seated"|"dethrone"|"king"|"rank", text = string, tone = string? }
-- `tone` ("good"|"bad"|"neutral") just colours the toast. fireHud(plr) targets one client; broadcastHud()
-- goes to everyone (join/leave the whole table should see). Pure notification -- no rules ride on it.
local Remotes = RS:WaitForChild("NineSquareRemotes")
local HudEvent = Remotes:FindFirstChild("HudEvent")
if not HudEvent then
	HudEvent = Instance.new("RemoteEvent")
	HudEvent.Name = "HudEvent"
	HudEvent.Parent = Remotes
end
-- LOBBY / TAP-TO-JOIN (this task): players no longer auto-seat on join -- they spawn in the gallery LOBBY
-- watching the live (bot) game, and explicitly REQUEST to enter the court by tapping a "Join Game" button.
-- The button fires this RemoteEvent; the SERVER decides (seat-from-a-bot at the entry rank, or enqueue when
-- all 9 seats are humans) -- server-authoritative, the client only requests. Self-healed so a fresh place works.
local JoinRequest = Remotes:FindFirstChild("JoinRequest")
if not JoinRequest then
	JoinRequest = Instance.new("RemoteEvent")
	JoinRequest.Name = "JoinRequest"
	JoinRequest.Parent = Remotes
end
-- LEAVE-TO-SPECTATE (this task): the counterpart to JoinRequest. A SEATED human taps a "Leave" button to
-- step off the court back into the gallery lobby. The button fires this RemoteEvent; the SERVER frees their
-- seat (unseatHuman -> the _backfillHook seats a queued spectator, else a bot, so the rank is never empty),
-- parks them as a lobby watcher (Spectating=true, no rank), and re-serves if they were the King -- so the
-- loop never wedges. Server-authoritative: the client only requests. Self-healed so a fresh place works.
local LeaveRequest = Remotes:FindFirstChild("LeaveRequest")
if not LeaveRequest then
	LeaveRequest = Instance.new("RemoteEvent")
	LeaveRequest.Name = "LeaveRequest"
	LeaveRequest.Parent = Remotes
end
local function fireHud(plr: Player, kind: string, text: string, tone: string?)
	if plr and plr.Parent then HudEvent:FireClient(plr, { kind = kind, text = text, tone = tone }) end
end
local function broadcastHud(kind: string, text: string, tone: string?)
	HudEvent:FireAllClients({ kind = kind, text = text, tone = tone })
end
-- Replicate EACH seated player's OWN rank (server-authoritative; per-player now -- a human/bot mix means
-- every human reads ITS seat). The client HUD (RankHud) observes the player's "Rank" attribute and shows
-- "Rank N" / "KING".
rotation._setHumanRank = function(player: Player, rank: number)
	player:SetAttribute("Rank", rank)
end
-- ============================================================================================
-- M5.2 -- SPECTATOR OVERFLOW QUEUE + AUTO-JOIN. Spectators exist ONLY when humans > 9 seats: a joiner
-- beyond the 9 seats is parked in SPECTATOR state (no seat, no ball collider, spawned clear of the court)
-- and pushed onto a server FIFO queue. Whenever a seat could be filled -- a human leaves (the M5.1
-- _backfillHook fires), OR a spectator is waiting while a BOT still holds a seat (the proactive sweep) --
-- the LONGEST-WAITING spectator is auto-seated at the entry rank (displacing a bot). Net: bots only ever
-- hold seats no human (seated or queued) wants; a freed seat goes to a spectator before a bot. FIFO order
-- is stable; a spectator disconnecting leaves the queue cleanly. Spectators NEVER affect the ball (they're
-- excluded from the colliders fed to bc:step) and never score. Server-authoritative throughout.
-- ============================================================================================

-- The FIFO spectator queue: index 1 is the LONGEST-waiting (next to be seated). Players only; bots never
-- queue. A `Spectating` flag + `QueuePos` (1-based line position) are replicated to each spectator's client
-- as attributes (the client shows the overlook camera + a "Spectating -- #N in line" HUD off these).
local spectatorQueue: { Player } = {}

local function isSpectator(plr: Player): boolean
	return table.find(spectatorQueue, plr) ~= nil
end

-- Re-replicate every spectator's 1-based queue position (and the seated/clear flag) after any queue change,
-- so each waiting client's HUD shows the right "#N in line". A seated/removed player has Spectating=false.
local function syncSpectatorAttrs()
	for i, plr in ipairs(spectatorQueue) do
		plr:SetAttribute("Spectating", true)
		plr:SetAttribute("QueuePos", i)
	end
end

-- Park a spectator's character clear of the court (a temporary overlook; the real gallery spawn is M5.3) so
-- it never sits in a square / feeds the ball. Idempotent + safe to call on (re)spawn.
local function parkSpectator(plr: Player)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local pos = G.origin + G.specSpawnOffset
		-- Face the court centre (horizontally) so the default (Custom) spectator camera starts looking toward
		-- the play area. The gallery bench is decorative (its seats are disabled), so the player can roam freely.
		local lookAt = Vector3.new(G.origin.X, pos.Y, G.origin.Z)
		hrp.CFrame = (pos - lookAt).Magnitude > 1e-3 and CFrame.lookAt(pos, lookAt) or CFrame.new(pos)
	end
end

-- Put a non-seated human into the LOBBY WATCHER state (this task): parked at the gallery spawn, watching the
-- live game, with the spectator camera/HUD on (Spectating=true) but NOT in the FIFO join queue (QueuePos=0,
-- so the client shows the "Join Game" button rather than "In queue #N"). This is the DEFAULT state on join:
-- the player watches until they tap Join. Idempotent + safe to call on (re)spawn. A lobby watcher has no rank,
-- so the Heartbeat collider filter already excludes it from the ball (it can't strike/score while watching).
local function parkLobbyWatcher(plr: Player)
	plr:SetAttribute("Rank", 0)
	plr:SetAttribute("Spectating", true)
	plr:SetAttribute("QueuePos", 0)
	parkSpectator(plr)
end

-- Enqueue a player as a spectator (overflow: all 9 seats are humans). FIFO -- appended at the tail.
local function enqueueSpectator(plr: Player)
	if isSpectator(plr) then return end
	table.insert(spectatorQueue, plr)
	syncSpectatorAttrs()
	parkSpectator(plr)
	print(("[NineSquare] SPECTATOR: %s queued at #%d (overflow -- all 9 seats are humans)")
		:format(plr.Name, #spectatorQueue))
end

-- Remove a player from the queue (they got seated, or disconnected). Clears their spectator flags and
-- re-indexes everyone behind them so the FIFO line stays contiguous + stable. Returns true if removed.
local function dequeueSpectatorPlayer(plr: Player): boolean
	local i = table.find(spectatorQueue, plr)
	if not i then return false end
	table.remove(spectatorQueue, i)
	plr:SetAttribute("Spectating", false)
	plr:SetAttribute("QueuePos", 0)
	syncSpectatorAttrs()   -- re-index the remaining line (#N shifts up)
	return true
end

-- The M5.1 leave-backfill hook: when a seated human leaves, seat the LONGEST-waiting spectator into the
-- freed rank (returns a human Occupant for RotationService to install) instead of spawning a bot. The
-- spectator is popped off the FIFO head, flipped out of spectator state, and bound to its new seat (its
-- character is teleported to the cell by _placeOccupant). Returns nil when the queue is empty -> a bot
-- backfills (M5.1 default). The returned occupant's rank/cell are stamped by unseatHuman.
rotation._backfillHook = function(rank: number, cell: string): any
	local nextPlr = spectatorQueue[1]
	if not nextPlr then return nil end                 -- no spectator waiting -> fall through to a bot
	dequeueSpectatorPlayer(nextPlr)                     -- pop the head + re-index the line
	nextPlr:SetAttribute("Rank", rank)                 -- replicate its new seat to the (now seated) client
	print(("[NineSquare] AUTO-SEAT: %s (longest-waiting spectator) -> freed rank %d (%s)")
		:format(nextPlr.Name, rank, cell))
	-- M5.6 HUD feed: tell the auto-seated spectator they're in (personal) + the table they joined the court.
	fireHud(nextPlr, "seated", "You're in! Seated at Rank " .. tostring(rank), "good")
	broadcastHud("seated", nextPlr.DisplayName .. " joined the court from the queue", "neutral")
	return {
		kind = "human", player = nextPlr, id = "human_" .. tostring(nextPlr.UserId),
		isDummy = false, rank = rank, cell = cell,
	}
end

-- PROACTIVE SWEEP -- DISABLED (lobby / tap-to-join, this task). Previously this auto-seated queued spectators
-- into ANY bot-held seat (humans always outrank bots). That behaviour is INTENTIONALLY OFF now: entry is
-- button-driven, so a lobby watcher must NOT be yanked into the court without tapping "Join Game". A player
-- who tapped Join while all 9 seats were human is enqueued (FIFO) and auto-seated ONLY on the next human-seat
-- freeing (the M5.1 _backfillHook, kept). Bots may sit under lobby watchers indefinitely -- by design, they
-- watch until they choose to enter. Kept as a no-op so any existing call site is harmless.
local function trySeatSpectatorsFromBots()
	return false
end

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
	-- M5.6 HUD feed: tell the new King they took the throne (personal "good"), and let the table know who
	-- reigns now (broadcast). The old King's "you were dethroned" nudge fires from the rotation feed below.
	local kingName = (newKing.kind == "human" and newKing.player) and newKing.player.DisplayName or "A bot"
	if newKing.kind == "human" and newKing.player then
		fireHud(newKing.player, "king", "You're the KING! \u{1F451}", "good")
	end
	broadcastHud("dethrone", kingName .. " takes the throne", "neutral")
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

-- BALL-ESCAPE / NON-SETTLE WATCHDOG state. `rallyStartT` is the server time the CURRENT rally entered play
-- (a serve / first Flight). The watchdog (in the Heartbeat) force-resolves a rally that has left the sane
-- play volume OR has not reached rest within G.ballSettleTimeout -- so a runaway ball (the documented
-- degenerate pipe reflection) can never wedge the loop by never firing onRest. `resolvingRally` guards
-- against double-resolving (a forced resolve + a late onLand/onRest in the same beat).
local rallyStartT: number? = nil
local resolvingRally = false

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
	resolvingRally = false     -- a fresh serve clears the watchdog's resolve guard for the new rally
	rallyStartT = nil          -- (re)armed when the serve actually puts the ball into play (below / Heartbeat)
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
				rallyStartT = workspace:GetServerTimeNow()   -- arm the settle watchdog from the serve moment
				serveToTarget(target)
			end
		end)
	end
end

-- Attribute the fault for a rally (PRD §6, corrected for over-the-pipe ownership), flash the OUT square,
-- and RECORD the rank to rotate at rest. Shared by the normal landing (onLand) AND the escape watchdog
-- (a runaway ball that never lands is treated as an OOB fault on the hitter, exactly like a real OOB
-- landing). `landed` = the square the ball first hit the floor in (nil = out of bounds / escaped); `struck`
-- = the square it was last struck/served from; `owner` = the square it LEGALLY belongs to. Sets
-- pendingFaultRank (consumed by applyDeferredRotation at rest / by the watchdog). Idempotent-safe: only the
-- caller's rallyArmed/resolve guards decide WHEN this runs.
local function attributeFault(landed: string?, struck: string?, owner: string?)
	local faultCell: string?
	if landed == nil then
		faultCell = struck
		print(("[NineSquare] FAULT (out-of-bounds) struck=%s owner=%s"):format(tostring(struck), tostring(owner)))
	elseif owner == struck then
		faultCell = struck
		print(("[NineSquare] FAULT (never cleared over a pipe) struck=%s landed=%s owner=%s")
			:format(tostring(struck), tostring(landed), tostring(owner)))
	else
		faultCell = owner
		print(("[NineSquare] FAULT (floor / unreturned) owner=%s landed=%s"):format(tostring(owner), tostring(landed)))
	end

	MatchService.flashCell(faultCell, G.faultFlashDuration); playOof()

	local faultRank = faultCell and G.rankForCell(faultCell)
	if faultRank then
		local occ = rotation:occupantAtCell(faultCell)
		print(("[NineSquare] fault marked (rotation deferred to rest): cell=%s rank=%d occupant=%s")
			:format(tostring(faultCell), faultRank, occ and occ.id or "?"))
		pendingFaultRank = faultRank
	else
		warn("[NineSquare] could not attribute fault (no rank for cell " .. tostring(faultCell) .. ")")
	end
end

-- Run the deferred rotation if a fault is pending: snapshot each human's rank, rotate everyone toward the
-- King, then push the per-player stats + HUD nudges. Shared by onRest (the normal path, when the ball has
-- settled) AND the escape watchdog (which forces it for a ball that will never settle). Consumes
-- pendingFaultRank so it runs EXACTLY once per rally.
local function applyDeferredRotation()
	if not pendingFaultRank then return end
	local faultRank = pendingFaultRank
	pendingFaultRank = nil
	print(("[NineSquare] applying deferred rotation (rank %d)"):format(faultRank))
	local before: { [Player]: number } = {}
	for r = 1, 9 do
		local o = rotation.byRank[r]
		if o and o.kind == "human" and o.player then before[o.player] = r end
	end
	-- STATS: this rally is a completed "turn" for EVERY seated human -- credit it at the rank they held
	-- DURING the rally (the pre-rotation `before` snapshot). recordRally: totalTurns++, turnsAtBest++ if
	-- at their best rank, kingTurns++ if they were King (rank 1). Bots are excluded inside StatsService.
	for plr, rank in pairs(before) do
		StatsService.recordRally(plr, rank)
	end
	rotation:rotateOnFault(faultRank)
	for r = 1, 9 do
		local o = rotation.byRank[r]
		if o and o.kind == "human" and o.player then
			local was = before[o.player]
			StatsService.noteRank(o.player, r)
			if was and r ~= was then
				if r == 9 and was ~= 9 then
					fireHud(o.player, "rank", "Faulted \u{2014} back to Rank 9", "bad")
				elseif r < was and r ~= 1 then
					fireHud(o.player, "rank", "Moved up \u{2014} now Rank " .. tostring(r), "good")
				end
			end
		end
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
	attributeFault(landed, struck, owner)
end

-- Ball has bounced out its energy and stopped. NOW we run the deferred rotation (if a fault is pending):
-- rotate everyone toward the King (placeAll re-places them), THEN after a beat the new King serves the
-- next rally. This is the moment the OUT player rotates -- the red panel has been showing who's out the
-- whole settle. (If a dead ball got batted mid-settle, the pending fault still stands and rotates here.)
bc.onRest = function()
	if resolvingRally then return end          -- the watchdog already force-resolved this rally -> don't double-run
	rallyStartT = nil                           -- rally settled cleanly -> disarm the watchdog timeout
	applyDeferredRotation()
	task.delay(G.serveDelay, function()
		if bc.phase == "Rest" and not rallyArmed then
			serveNextRally()
		end
	end)
end

-- ============================================================================================
-- BALL-ESCAPE / NON-SETTLE WATCHDOG. The wedge fix: a runaway ball (the documented degenerate pipe/corner
-- reflection) can rocket out of the arena and NEVER settle, so onRest never fires and the deferred rotation
-- never runs -> the rally loop hangs forever. This watchdog GUARANTEES recovery. Each Heartbeat, while a
-- rally is armed, it checks two escape signals:
--   * out-of-volume: the ball left the sane play volume (above the gym ceiling + margin, below the floor,
--     or |XZ| past the court + margin) -- it's gone and won't come back as a normal landing.
--   * non-settle:    a rally has run past G.ballSettleTimeout without reaching rest (covers a ball stuck
--     re-reflecting at speed, or one whose huge arc would take far too long to fall).
-- On either, it FORCE-RESOLVES exactly like the normal OOB path: if no fault was attributed yet (the ball
-- escaped before landing) it attributes an OOB fault to the hitter (bc.struckCell / ownerCell, same model as
-- onLand's `landed == nil` branch), then applies the deferred rotation and re-serves. resolvingRally guards
-- against double-resolving with a late onLand/onRest. The clamp (ballMaxSpeed) makes the escape rare; this
-- makes it impossible to wedge even if one slips through. Normal play never trips it (peak ~32 << ceiling,
-- rallies settle in ~2-4s << timeout).
local function forceResolveRally(reason: string)
	if resolvingRally then return end
	resolvingRally = true
	rallyArmed = false
	rallyStartT = nil
	warn(("[NineSquare] WATCHDOG force-resolving rally (%s) -- ball pos=%s phase=%s")
		:format(reason, tostring(bc.ball.Position), tostring(bc.phase)))
	-- If onLand never fired (escaped mid-flight), attribute an OOB fault to the hitter exactly like the
	-- normal out-of-bounds path. If a fault was already pending (landed, then ran away while settling), keep it.
	if not pendingFaultRank then
		attributeFault(nil, bc.struckCell, bc.ownerCell)
	end
	applyDeferredRotation()
	-- Re-serve for the (new) King so the loop continues. serveNextRally clears resolvingRally + parks/serves
	-- the ball, so a stuck/escaped ball is replaced by a fresh serve and the game NEVER hangs.
	serveNextRally()
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
	-- TRUST BOUNDARY (M5.4): HitResolver.playerColliders() has already VALIDATED each player's PROPOSED
	-- position/velocity -- it clamps the collider velocity to a plausible max (maxStrikeSpeed), caps the
	-- per-frame centre jump (anti-teleport: maxFrameDisplacement) and bounds the contribution against a
	-- server-mirrored stamina pool -- so a spoofed HRP can't manufacture a super-hit or warp into the ball.
	-- The deterministic ball physics + strike formula are UNTOUCHED (inputs only), so legit play is identical.
	-- SPECTATORS NEVER AFFECT THE BALL (M5.2): drop any collider for a player who isn't seated. A seated
	-- human has a rank in the occupancy model; a queued spectator (or any unseated player) does not -> its
	-- (validated) hit-sphere is excluded here so it can't strike, deflect, or score, re-enforced every frame
	-- off the live occupancy model. (Bots feed their own server-driven colliders below; they're always seated.)
	local colliders = {}
	for _, c in ipairs(HitResolver.playerColliders()) do
		if rotation:rankOfPlayer(c.player) then
			table.insert(colliders, c)
		end
	end
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
		rallyStartT = workspace:GetServerTimeNow()   -- arm the settle watchdog from the moment it enters play
	end

	-- ESCAPE / NON-SETTLE WATCHDOG: recover the rally if the ball left the sane play volume (the GYM INTERIOR
	-- now) OR has run past the settle timeout without resting -- so a runaway/escaped ball can never wedge the
	-- loop by never firing onRest. Two guards, deliberately split so the phase/rallyArmed quirk can't let an
	-- escaped ball slip past:
	--   * OUT-OF-VOLUME is checked for any in-motion OR mid-resolve ball (Flight/Settling) REGARDLESS of
	--     rallyArmed. A ball that left the gym must ALWAYS force-resolve: even if a stray onLand on the global
	--     floor plane outside the gym already cleared rallyArmed (leaving a Settling ball bouncing in the
	--     outdoors), this still catches it and recovers -- the escaped ball is never left to fall/bounce away.
	--   * NON-SETTLE timeout only applies to an ARMED rally (a real in-play rally that should have ended).
	-- An idle/parked ball (Live/Rest) is skipped; resolvingRally guards against double-resolving.
	if not resolvingRally and (bc.phase == "Flight" or bc.phase == "Settling") then
		if G.ballOutOfPlayVolume(bc.ball.Position) then
			forceResolveRally("ball left play volume")
		elseif rallyArmed and rallyStartT and (workspace:GetServerTimeNow() - rallyStartT) > G.ballSettleTimeout then
			forceResolveRally("rally exceeded settle timeout")
		end
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

-- Spawn / respawn a player into the right place: a SEATED player goes to its ranked square; an overflow
-- SPECTATOR (M5.2) is parked clear of the court at the temporary overlook (the real gallery spawn is M5.3).
-- Late-loading clients also get a ball resync.
local function placeAtCourtAndSync(plr: Player, char: Model)
	local cell = rotation:cellOfPlayer(plr)
	if cell then
		placeAtCell(char, cell)
	else
		-- Not seated -> in the gallery: a queued joiner (FIFO) or a lobby watcher. Either way park them on the
		-- gallery floor (clear of the opening, on top of the invisible barrier) so they watch from above and
		-- can't fall through. parkSpectator uses the same gallery offset for both.
		parkSpectator(plr)
	end
	task.delay(1, function() bc:resync() end)
end

local function onJoin(plr: Player)
	-- STATS: load this human's PERSISTENT profile (DataStore, pcall-guarded -> in-memory fallback) and build
	-- their leaderstats ("Best" / "King Turns" / "Turns") BEFORE seating, so the player-list stats exist the
	-- moment they're in. (Bots never reach onJoin -- only real Players fire PlayerAdded / are in GetPlayers.)
	StatsService.onPlayerAdded(plr)
	-- LOBBY / TAP-TO-JOIN (this task): do NOT auto-seat on join. The player spawns in the gallery LOBBY,
	-- watching the live (bot) game from above, until they tap "Join Game". With 0 humans seated the 9 bots
	-- play a full, watchable match. Entry is request-driven (the JoinRequest handler below decides seat vs
	-- queue) -- a watcher is never pulled into the court without tapping.
	parkLobbyWatcher(plr)
	print(("[NineSquare] %s joined -> LOBBY watcher in the gallery (tap Join to enter)"):format(plr.Name))
	-- M5.6 HUD feed: welcome the watcher + tell the table someone is in the lobby.
	fireHud(plr, "join", "Watching from the gallery \u{2014} tap Join Game to play", "neutral")
	broadcastHud("join", plr.DisplayName .. " is watching from the gallery", "neutral")
	-- Bind this player's character to its seat on (re)spawn, and hook its jump squeak (this task) -- the
	-- Humanoid.Jumping handler plays the positional jump sound from the HRP for every jump (debounced).
	if plr.Character then placeAtCourtAndSync(plr, plr.Character); hookJumpSound(plr.Character) end
	plr.CharacterAdded:Connect(function(char) placeAtCourtAndSync(plr, char); hookJumpSound(char) end)
end

local function onLeave(plr: Player)
	-- STATS: flush this human's profile to the DataStore (pcall-guarded -> no-op/in-memory on failure) and
	-- drop their live session state, so a re-joiner reloads fresh from the store. Covers BOTH the spectator
	-- and seated leave paths (it runs before either branch). Server-authoritative; bots never get here.
	StatsService.onPlayerRemoving(plr)
	-- M5.4: drop this player's server-side validation state (anti-teleport last-centre + mirrored stamina)
	-- so a re-joiner with the same UserId starts fresh and we never leak per-player state on churn.
	HitResolver.forgetPlayer(plr)
	-- A QUEUED JOINER leaving just exits the FIFO queue cleanly (no seat to free, the line re-indexes) -- it
	-- never held a seat so there's nothing to backfill.
	if isSpectator(plr) then
		dequeueSpectatorPlayer(plr)
		print(("[NineSquare] %s left the join queue (line re-indexed; %d still waiting)")
			:format(plr.Name, #spectatorQueue))
		broadcastHud("leave", plr.DisplayName .. " left the queue", "neutral")
		return
	end
	-- A LOBBY WATCHER leaving (this task): a non-seated, non-queued human just watching from the gallery. No
	-- seat to free, not in the queue -> nothing to backfill; just note it. (Without this guard a watcher would
	-- fall through to the seated-leave path and wrongly broadcast "left the game" + run unseatHuman for nothing.)
	if not rotation:rankOfPlayer(plr) then
		print(("[NineSquare] %s (lobby watcher) left -- was never seated, nothing to backfill"):format(plr.Name))
		broadcastHud("leave", plr.DisplayName .. " left the gallery", "neutral")
		return
	end
	-- M5.6 HUD feed: a seated human left -> tell the table (the auto-seat/backfill nudge for whoever fills
	-- the seat fires from the backfill hook above).
	broadcastHud("leave", plr.DisplayName .. " left the game", "neutral")
	-- M5.4 lifecycle robustness: was THIS leaver the current King? Capture it BEFORE the backfill so we can
	-- recover a wedged hover-serve below (the King left while the ball hovered at C waiting for its
	-- jump-serve that will now never come). Mid-rally/mid-settle leaves are already safe: the onLand/onRest
	-- loop keeps running and the new occupant just inherits the seat.
	local wasKing = (rotation:kingPlayer() == plr)

	-- A SEATED human leaving frees its rank: the _backfillHook seats the longest-waiting spectator if one
	-- is queued, else a fresh bot -- so a rank is never empty + the game never wedges.
	local repl = rotation:unseatHuman(plr)
	if repl then
		print(("[NineSquare] %s left -> seat backfilled with %s %s"):format(plr.Name, repl.kind, repl.id))
	end
	-- Defensive: if (somehow) a bot still holds a seat while spectators wait, sweep them into it now.
	trySeatSpectatorsFromBots()

	-- RE-SERVE RECOVERY: if the King left while the ball was parked for a (human) hover-serve -- i.e. the
	-- ball is Live/Rest and no rally is in flight -- the new King must serve, or the ball would hover
	-- forever. Re-run serveNextRally for whoever now holds the throne (a human re-hovers; a bot auto-serves).
	-- Guarded on the idle phases + not rallyArmed so it never interrupts a live rally or double-serves.
	if wasKing and not rallyArmed and (bc.phase == "Live" or bc.phase == "Rest") then
		print("[NineSquare] King left mid-serve -> re-serving for the new King (no wedge)")
		serveNextRally()
	end
end

-- TAP-TO-JOIN handler (this task). A non-seated human's "Join Game" button fires JoinRequest; the SERVER
-- decides (server-authoritative -- the client only requests):
--   * A BOT seat exists  -> seatHuman seats them at the ENTRY rank (the highest bot seat), displacing that
--     bot, and teleports them to their court cell (the existing seatHuman path). They leave the lobby
--     (Spectating=false) and the seated camera/HUD takes over on the client off the replicated Rank.
--   * All 9 seats are humans -> enqueue (FIFO). The longest-waiting queued joiner is auto-seated on the next
--     human-seat freeing (the M5.1 _backfillHook, kept). The client shows "In queue (#N)".
-- Idempotent + defensive: a request from an already-seated or already-queued player is ignored. STATS note +
-- HUD feed mirror the old onJoin seating path so a tapped-in player still gets their entry-rank credit/welcome.
local function onJoinRequest(plr: Player)
	if not plr or not plr.Parent then return end
	if rotation:rankOfPlayer(plr) then return end       -- already seated -> ignore
	if isSpectator(plr) then return end                 -- already queued -> ignore (button shows "In queue")

	local rank = rotation:seatHuman(plr)
	if rank then
		-- Seated from a bot at the entry rank: leave the lobby, credit the entry rank, place + welcome.
		plr:SetAttribute("Spectating", false)
		plr:SetAttribute("QueuePos", 0)
		StatsService.noteRank(plr, rank)
		print(("[NineSquare] JOIN REQUEST: %s seated at entry rank %d (%s) -- displaced a bot")
			:format(plr.Name, rank, tostring(rotation:cellOfPlayer(plr))))
		fireHud(plr, "seated", "You're in! Seated at Rank " .. tostring(rank) .. " \u{2014} climb to the throne!", "good")
		broadcastHud("seated", plr.DisplayName .. " joined the court", "neutral")
		-- Make sure their live character sits in the new cell now (placeOnePlayer in seatHuman already did, but
		-- re-bind defensively if the character is mid-respawn).
		if plr.Character then placeAtCourtAndSync(plr, plr.Character) end
	else
		-- All 9 seats are humans -> enqueue (FIFO). enqueueSpectator sets Spectating/QueuePos + parks them.
		enqueueSpectator(plr)
		print(("[NineSquare] JOIN REQUEST: %s -> all 9 seats are humans, queued at #%d"):format(plr.Name, #spectatorQueue))
		fireHud(plr, "join", "All 9 seats full \u{2014} you're #" .. tostring(#spectatorQueue) .. " in line", "neutral")
		broadcastHud("join", plr.DisplayName .. " is in the join queue (#" .. tostring(#spectatorQueue) .. ")", "neutral")
	end
end
JoinRequest.OnServerEvent:Connect(onJoinRequest)

-- LEAVE-TO-SPECTATE handler (this task). A SEATED human's "Leave" button fires LeaveRequest; the SERVER frees
-- their seat back to the gallery lobby (server-authoritative -- the client only requests):
--   * Free their rank via unseatHuman -> the _backfillHook seats the longest-waiting queued spectator if one
--     is waiting, else a fresh bot -- so the freed rank is NEVER empty (same backfill as a disconnect).
--   * Park them as a LOBBY WATCHER (parkLobbyWatcher: Spectating=true, Rank=0, QueuePos=0) so the roam camera
--     + the Join Game button come back. They re-enter later via Join (entry rank, the existing fairness).
--   * If they were the KING and the ball was parked for a (now-gone) hover-serve, re-serve for the NEW King --
--     the same wedge guard as the disconnect path -- so the loop never hangs.
-- Idempotent + defensive: a request from an unseated player (lobby watcher / queued spectator) is ignored.
local function onLeaveRequest(plr: Player)
	if not plr or not plr.Parent then return end
	if not rotation:rankOfPlayer(plr) then return end   -- not seated (already a watcher / queued) -> ignore
	-- Capture King-ness BEFORE the backfill, exactly like the disconnect path, so we can re-serve for the new
	-- King if this leaver was mid-(hover-)serve.
	local wasKing = (rotation:kingPlayer() == plr)

	local repl = rotation:unseatHuman(plr)            -- free + backfill (queued spectator -> else bot; never empty)
	if repl then
		print(("[NineSquare] LEAVE REQUEST: %s left the court -> seat backfilled with %s %s")
			:format(plr.Name, repl.kind, repl.id))
	end
	-- Defensive: if (somehow) a bot still holds a seat while spectators wait, sweep them in (no-op while the
	-- proactive sweep is disabled, but kept symmetric with the disconnect path).
	trySeatSpectatorsFromBots()

	-- Back to the gallery LOBBY: roam camera, Join Game available again (no rank, Spectating=true, not queued).
	parkLobbyWatcher(plr)
	-- Re-place their live character up in the gallery now (parkLobbyWatcher -> parkSpectator teleports the HRP).
	if plr.Character then parkSpectator(plr) end
	fireHud(plr, "leave", "Back in the gallery \u{2014} tap Join Game to return", "neutral")
	broadcastHud("leave", plr.DisplayName .. " left the court to spectate", "neutral")

	-- RE-SERVE RECOVERY (same as the disconnect path): if the King left this way while the ball was parked for
	-- a human hover-serve, re-serve for whoever now holds the throne so the ball doesn't hover forever.
	if wasKing and not rallyArmed and (bc.phase == "Live" or bc.phase == "Rest") then
		print("[NineSquare] King left to spectate mid-serve -> re-serving for the new King (no wedge)")
		serveNextRally()
	end
end
LeaveRequest.OnServerEvent:Connect(onLeaveRequest)

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
-- STATS: start the periodic autosave loop + game:BindToClose flush (every store call pcall-guarded inside
-- StatsService). getPlayers feeds it the live human list to persist.
StatsService.start(function() return Players:GetPlayers() end)
-- Seat any players already connected at boot (Studio Play seats the local player here).
for _, plr in ipairs(Players:GetPlayers()) do onJoin(plr) end
