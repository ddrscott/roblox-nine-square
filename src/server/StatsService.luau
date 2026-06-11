--!strict
-- ServerScriptService.NineSquare.StatsService
-- Server-authoritative, PERSISTENT per-human stats (DataStore) -- best rank reached + turns held.
--
-- WHAT IT TRACKS (per HUMAN, keyed by UserId -- bots are excluded; they have no UserId and never persist):
--   bestRank     -- the highest rank reached = the LOWEST rank number ever held (1 = King = best).
--   turnsAtBest  -- rallies (turns) held at that best rank (how long they lasted in their peak spot).
--   kingTurns    -- total rallies held as King (rank 1) -- the marquee stat.
--   totalTurns   -- total rallies played while seated.
-- A "TURN" = one rally (a serve->fault cycle) the player participated in WHILE SEATED. NineSquareServer
-- calls recordRally() once per completed rally with the CURRENT (pre-rotation) seating, so each seated
-- human's counters tick for the rally they just played; bestRank/turnsAtBest then update from the seating
-- AFTER rotation via noteRank().
--
-- PERSISTENCE (robust): DataStoreService keyed per UserId under `<storeName>_<version>`. Loaded on join,
-- saved on leave + a periodic autosave + game:BindToClose. EVERY DataStore call is wrapped in pcall with an
-- IN-MEMORY FALLBACK: if the store is unavailable (Studio without "Enable Studio Access to API Services",
-- or a transient failure) the game NEVER errors or blocks -- it just runs on the live in-memory profile and
-- logs a clear note once. So play is identical whether or not persistence is actually writing.
--
-- DISPLAY: a standard Roblox `leaderstats` folder per human (auto-shows in the player list for everyone):
--   "Best" (best rank reached, lower = better), "King Turns", "Turns". The values update LIVE as the player
--   climbs / holds / rotates. Server-authoritative: the client never writes these.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

export type Profile = {
	bestRank: number,     -- lowest rank number ever held (1 = King; 9 = entry/back). Lower is better.
	turnsAtBest: number,  -- rallies held at bestRank
	kingTurns: number,    -- rallies held as King (rank 1)
	totalTurns: number,   -- rallies played seated
}

local StatsService = {}

-- live in-memory profiles keyed by UserId (the single source of truth during a session; DataStore is the
-- backing store loaded on join / flushed on leave). A bot never appears here (no UserId).
local profiles: { [number]: Profile } = {}
-- per-UserId leaderstats IntValues so we can push updates without re-walking the player tree each rally.
local stats: { [number]: { best: IntValue, kingTurns: IntValue, turns: IntValue } } = {}
-- guard so the "DataStore unavailable -> in-memory fallback" note is logged once, not every call.
local fallbackNoted = false

-- The versioned DataStore. Acquiring it can itself throw in some contexts, so even GetDataStore is pcall'd;
-- if it fails we operate purely in-memory (store stays nil).
local STORE_NAME = G.statsStoreName .. "_" .. G.statsStoreVersion
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Stats] GetDataStore failed (" .. tostring(result) .. ") -- running stats IN-MEMORY only")
	end
end

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

-- Note the in-memory fallback exactly once (so a Studio session without API access, or a transient outage,
-- says so clearly but doesn't spam the log every save/load).
local function noteFallback(reason: string)
	if fallbackNoted then return end
	fallbackNoted = true
	warn(("[Stats] DataStore unavailable (%s) -- FALLING BACK to in-memory stats for this session "
		.. "(persistence requires a published place, or Studio's \"Enable Studio Access to API Services\")")
		:format(reason))
end

local function freshProfile(): Profile
	-- Start bestRank at the worst possible (one past the back) so the FIRST observed rank always improves it.
	return { bestRank = 10, turnsAtBest = 0, kingTurns = 0, totalTurns = 0 }
end

-- Coerce whatever came back from the DataStore (possibly nil / partial / wrong types) into a valid Profile.
local function sanitize(raw: any): Profile
	local p = freshProfile()
	if type(raw) == "table" then
		if type(raw.bestRank) == "number" then p.bestRank = math.clamp(math.floor(raw.bestRank), 1, 10) end
		if type(raw.turnsAtBest) == "number" then p.turnsAtBest = math.max(0, math.floor(raw.turnsAtBest)) end
		if type(raw.kingTurns) == "number" then p.kingTurns = math.max(0, math.floor(raw.kingTurns)) end
		if type(raw.totalTurns) == "number" then p.totalTurns = math.max(0, math.floor(raw.totalTurns)) end
	end
	return p
end

-- Build the leaderstats folder + IntValues for a player and bind them to its live profile. "Best" shows the
-- best (lowest) rank reached; before any rank is held bestRank is 10 (sentinel) -> we show 0 so the player
-- list reads cleanly ("no rank yet") rather than a bogus 10.
local function buildLeaderstats(player: Player, p: Profile)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function ensure(name: string): IntValue
		local v = ls:FindFirstChild(name) :: IntValue?
		if not v then
			v = Instance.new("IntValue")
			v.Name = name
			v.Parent = ls
		end
		return v
	end
	local best = ensure("Best")
	local kingTurns = ensure("King Turns")
	local turns = ensure("Turns")
	stats[player.UserId] = { best = best, kingTurns = kingTurns, turns = turns }
end

-- Push the live profile onto the player's leaderstats (called after every change).
local function pushLeaderstats(userId: number)
	local s = stats[userId]
	local p = profiles[userId]
	if not s or not p then return end
	-- bestRank 10 is the "never seated" sentinel -> show 0 (no rank yet).
	s.best.Value = (p.bestRank >= 10) and 0 or p.bestRank
	s.kingTurns.Value = p.kingTurns
	s.turns.Value = p.totalTurns
end

-- Load a human's profile from the DataStore (pcall-guarded; in-memory fresh profile on any failure) and set
-- up its leaderstats. Idempotent: re-loading an already-live player just re-pushes the leaderstats. Bots
-- never reach here (NineSquareServer only calls onPlayerAdded for real Players).
function StatsService.onPlayerAdded(player: Player)
	local userId = player.UserId
	local loaded: Profile
	if store then
		local ok, result = pcall(function()
			return store:GetAsync(key(userId))
		end)
		if ok then
			loaded = sanitize(result)
		else
			noteFallback("GetAsync error: " .. tostring(result))
			loaded = freshProfile()
		end
	else
		noteFallback("no DataStore handle")
		loaded = freshProfile()
	end
	profiles[userId] = loaded
	buildLeaderstats(player, loaded)
	pushLeaderstats(userId)
	print(("[Stats] loaded %s (UserId %d): bestRank=%s kingTurns=%d turns=%d")
		:format(player.Name, userId, tostring(loaded.bestRank), loaded.kingTurns, loaded.totalTurns))
end

-- Persist a human's profile (pcall-guarded; a failure just logs the fallback note -- the in-memory profile
-- stays authoritative so the session is unaffected). Safe if the player has no live profile (no-op).
function StatsService.save(player: Player)
	local userId = player.UserId
	local p = profiles[userId]
	if not p then return end
	if not store then
		noteFallback("no DataStore handle")
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(key(userId), {
			bestRank = p.bestRank,
			turnsAtBest = p.turnsAtBest,
			kingTurns = p.kingTurns,
			totalTurns = p.totalTurns,
		})
	end)
	if ok then
		print(("[Stats] saved %s (UserId %d)"):format(player.Name, userId))
	else
		noteFallback("SetAsync error: " .. tostring(err))
	end
end

-- A human left: flush their profile, then drop the live session state (so a re-joiner reloads fresh from
-- the store and we never leak per-player tables on churn).
function StatsService.onPlayerRemoving(player: Player)
	StatsService.save(player)
	profiles[player.UserId] = nil
	stats[player.UserId] = nil
end

-- Observe a seated human at `rank` and improve their best (lowest) rank reached. When a NEW best is reached,
-- bestRank updates and turnsAtBest resets to 0 (we then accrue turnsAtBest per rally held at that new best,
-- via recordRally). Called after seating/rotation so the leaderstats "Best" climbs live. No-op for ranks
-- that don't beat the stored best. Bots (no live profile) are ignored.
function StatsService.noteRank(player: Player, rank: number)
	local p = profiles[player.UserId]
	if not p then return end
	if rank < p.bestRank then
		p.bestRank = rank
		p.turnsAtBest = 0   -- fresh peak spot: start counting turns held here from zero
		pushLeaderstats(player.UserId)
	end
end

-- Record ONE completed rally (a "turn") for a single seated human at the rank they held DURING that rally.
-- totalTurns always ticks; turnsAtBest ticks only while sitting at their best rank; kingTurns ticks only at
-- rank 1 (the throne). Bots are excluded (no live profile). Pushes the leaderstats so the player list ticks
-- up live each rally.
function StatsService.recordRally(player: Player, rank: number)
	local p = profiles[player.UserId]
	if not p then return end
	p.totalTurns += 1
	if rank == p.bestRank then
		p.turnsAtBest += 1
	end
	if rank == 1 then
		p.kingTurns += 1
	end
	pushLeaderstats(player.UserId)
end

-- Read-only snapshot of a human's live profile (nil if not loaded / a bot). For tests + any future HUD.
function StatsService.getProfile(player: Player): Profile?
	local p = profiles[player.UserId]
	if not p then return nil end
	return { bestRank = p.bestRank, turnsAtBest = p.turnsAtBest, kingTurns = p.kingTurns, totalTurns = p.totalTurns }
end

-- Periodic autosave + game:BindToClose so a long session and a server shutdown both persist. Wired once by
-- NineSquareServer (start()). The autosave loop and BindToClose both pcall every store call (via save()).
local started = false
function StatsService.start(getPlayers: () -> { Player })
	if started then return end
	started = true

	-- Periodic autosave: every statsAutosaveInterval seconds, flush every live human (so a crash/timeout
	-- loses at most one interval of progress). Each save() is independently pcall-guarded.
	task.spawn(function()
		while true do
			task.wait(G.statsAutosaveInterval)
			for _, plr in ipairs(getPlayers()) do
				StatsService.save(plr)
			end
		end
	end)

	-- On shutdown, flush everyone. BindToClose blocks shutdown briefly for the writes; pcall-guarded so a
	-- store outage never wedges the close. Skipped in Studio edit (RunService:IsStudio + no players) anyway.
	game:BindToClose(function()
		for _, plr in ipairs(getPlayers()) do
			StatsService.save(plr)
		end
		-- A tiny settle so queued SetAsync calls flush before the process exits (no-op if in-memory).
		if not RunService:IsStudio() then
			task.wait(1)
		end
	end)
end

return StatsService
