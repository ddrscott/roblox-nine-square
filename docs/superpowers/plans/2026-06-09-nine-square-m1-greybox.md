# 9 Square — Milestone 1 (Greybox Readability) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a greybox 3×3 arena where one player can serve a ball into the square they stand under, then jump to physically volley it, proving the shadow/descent-ring telegraph and reflection-based contact are readable and feel good.

**Architecture:** Server-authoritative, deterministic ball arcs. Luau modules live in `src/` (git source of truth) and are pushed into Roblox Studio via the `robloxstudio` MCP `set_script_source`. The server owns an anchored ball it moves each Heartbeat; clients render shadow/ring/camera and send only a Serve intent. For M1, contact (overlap + steering) is resolved by reading **replicated character state** (position + `Humanoid.MoveDirection`) server-side — full client-intent validation + anti-cheat is deferred to M5.

**Tech Stack:** Roblox Luau, `robloxstudio` MCP (`set_script_source`, `create_object`, `execute_luau`, `start_playtest`/`stop_playtest`, `capture_screenshot`), git on `main`.

---

## Deployment model (how `src/` reaches Studio)

No Rojo for M1. Each source file maps to one Studio instance. To **DEPLOY** a file: read the `src/` file, then call MCP `set_script_source` on its instance path with the full file contents. Instances are created once in Task 2.

| `src/` file | Studio instance (path) | Class |
|---|---|---|
| `src/shared/GridConfig.luau` | `ReplicatedStorage.GridConfig` | ModuleScript |
| `src/server/BallController.luau` | `ServerScriptService.NineSquare.BallController` | ModuleScript |
| `src/server/MatchService.luau` | `ServerScriptService.NineSquare.MatchService` | ModuleScript |
| `src/server/HitResolver.luau` | `ServerScriptService.NineSquare.HitResolver` | ModuleScript |
| `src/server/NineSquareServer.server.luau` | `ServerScriptService.NineSquareServer` | Script |
| `src/client/NineSquareClient.client.luau` | `StarterPlayer.StarterPlayerScripts.NineSquareClient` | LocalScript |

Remotes: `ReplicatedStorage.NineSquareRemotes` (Folder) containing RemoteEvents `Serve` (client→server) and `BallSync` (server→clients).

## Testing approach in Roblox

- **Pure logic** (GridConfig math, reflection/steer): tested by MCP `execute_luau` that `require`s the module and asserts, returning `"PASS"` or `"FAIL: ..."`.
- **Visual/feel** (telegraph readability, contact feel): verified by `start_playtest` + `capture_screenshot` against named checkpoints. These are explicit, not skippable.

## A note before starting

The leftover `Workspace.Obby` folder from earlier is unrelated; leave it. All M1 geometry lives under `Workspace.NineSquare` so it can be rebuilt/cleared independently.

---

## Task 1: GridConfig — dimensions + pure grid math

**Files:**
- Create: `src/shared/GridConfig.luau`

- [ ] **Step 1: Write GridConfig**

```lua
--!strict
-- ReplicatedStorage.GridConfig
-- Tunable dimensions + pure grid/contact math for 9 Square M1. No side effects.
local GridConfig = {}

-- Dimensions (studs / seconds). All tunable; values are greybox starting points.
GridConfig.squareSize = 14          -- one square edge
GridConfig.floorThickness = 1
GridConfig.frameHeight = 13         -- contact plane = measured jump reach (tuned in Task 2)
GridConfig.beamThickness = 0.5
GridConfig.ballRadius = 1
GridConfig.apexHeight = 16          -- extra bulge above the serve chord midpoint
GridConfig.serveTravel = 1.1        -- seconds, center -> target square arrival
GridConfig.descentWindow = 0.8      -- seconds before arrival that the ring actively shrinks
GridConfig.hitZoneRadius = 2.5      -- avatar hit-zone sphere radius
GridConfig.hitZoneYOffset = 2.0     -- hit-zone center above HumanoidRootPart (hands/head)
GridConfig.contactDwell = 0.15      -- (reserved for M2 tier scoring; steering read at contact)
GridConfig.steerConeDeg = 15        -- max horizontal steer nudge
GridConfig.lobTravel = 1.0          -- seconds for a volley lob arc
GridConfig.lobDistance = 14         -- horizontal studs a centered volley travels

-- Court center on the floor; set at runtime by the server.
GridConfig.origin = Vector3.new(0, 0, 0)

-- Cell -> (dx, dz) in {-1,0,1}. +X = East, +Z = South (Roblox conventions).
GridConfig.cells = {
	NW = { dx = -1, dz = -1 }, N = { dx = 0, dz = -1 }, NE = { dx = 1, dz = -1 },
	W  = { dx = -1, dz =  0 }, C = { dx = 0, dz =  0 }, E  = { dx = 1, dz =  0 },
	SW = { dx = -1, dz =  1 }, S = { dx = 0, dz =  1 }, SE = { dx = 1, dz =  1 },
}
GridConfig.outerCells = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

function GridConfig.cellCenter(cell: string): Vector3
	local c = GridConfig.cells[cell]
	assert(c, "unknown cell " .. tostring(cell))
	return GridConfig.origin + Vector3.new(c.dx * GridConfig.squareSize, 0, c.dz * GridConfig.squareSize)
end

function GridConfig.cellFramePoint(cell: string): Vector3
	return GridConfig.cellCenter(cell) + Vector3.new(0, GridConfig.frameHeight, 0)
end

-- Which cell is a world position under? Returns cell name or nil if outside the 3x3 court.
function GridConfig.cellAtPosition(pos: Vector3): string?
	local rel = pos - GridConfig.origin
	local function idx(v: number): number?
		local i = math.floor(v / GridConfig.squareSize + 0.5)
		if i < -1 or i > 1 then return nil end
		return i
	end
	local ix, iz = idx(rel.X), idx(rel.Z)
	if not ix or not iz then return nil end
	for name, c in pairs(GridConfig.cells) do
		if c.dx == ix and c.dz == iz then return name end
	end
	return nil
end

-- Base horizontal volley direction: ball deflects from contact toward ball center, i.e.
-- (ball - hitZoneCenter) flattened. Off-center contact => deflect that way; centered => zero.
function GridConfig.reflectDir(ballPos: Vector3, hitZoneCenter: Vector3): Vector3
	local d = ballPos - hitZoneCenter
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 1e-3 then return Vector3.zero end
	return flat.Unit
end

-- Rotate baseDir toward steerDir by at most steerConeDeg (about Y). Centered base (zero) snaps to steer.
function GridConfig.applySteer(baseDir: Vector3, steerDir: Vector3?): Vector3
	local s = steerDir and Vector3.new(steerDir.X, 0, steerDir.Z) or Vector3.zero
	if baseDir.Magnitude < 1e-3 then
		return s.Magnitude < 1e-3 and Vector3.zero or s.Unit
	end
	local b = baseDir.Unit
	if s.Magnitude < 1e-3 then return b end
	s = s.Unit
	local ang = math.acos(math.clamp(b:Dot(s), -1, 1))
	local maxAng = math.rad(GridConfig.steerConeDeg)
	if ang <= maxAng then return s end
	-- rotate b toward s by maxAng; sign from the Y of (b x s)
	local crossY = b.Z * s.X - b.X * s.Z
	local theta = (crossY >= 0 and 1 or -1) * maxAng
	local cosT, sinT = math.cos(theta), math.sin(theta)
	return Vector3.new(b.X * cosT + b.Z * sinT, 0, -b.X * sinT + b.Z * cosT).Unit
end

return GridConfig
```

- [ ] **Step 2: Commit**

```bash
git add src/shared/GridConfig.luau
git commit -m "feat(gridconfig): add M1 dimensions and pure grid/contact math"
```

- [ ] **Step 3: Deploy + test in Studio (run after Task 2 creates the instance)**

This task's logic test runs once the `ReplicatedStorage.GridConfig` instance exists (Task 2, Step 2). DEPLOY `src/shared/GridConfig.luau`, then run via MCP `execute_luau`:

```lua
local G = require(game.ReplicatedStorage.GridConfig)
G.origin = Vector3.new(0,0,0)
local out = {}
local function check(name, cond) out[#out+1] = (cond and "PASS " or "FAIL ")..name end
-- cell lookup round-trips
check("center is C", G.cellAtPosition(Vector3.new(0,0,0)) == "C")
check("east is E", G.cellAtPosition(Vector3.new(G.squareSize,0,0)) == "E")
check("north is N", G.cellAtPosition(Vector3.new(0,0,-G.squareSize)) == "N")
check("outside is nil", G.cellAtPosition(Vector3.new(0,0,3*G.squareSize)) == nil)
-- reflect: ball up-right of hands => dir up-right (+X,-Z)
local d = G.reflectDir(Vector3.new(1,13,-1), Vector3.new(0,11,0))
check("reflect points +X", d.X > 0)
check("reflect points -Z", d.Z < 0)
-- centered contact => zero base dir
check("centered reflect is zero", G.reflectDir(Vector3.new(0,13,0), Vector3.new(0,11,0)).Magnitude < 1e-3)
-- steer within cone snaps to steer
local s = G.applySteer(Vector3.new(1,0,0), Vector3.new(1,0,0.05))
check("small steer snaps", (s - Vector3.new(1,0,0.05).Unit).Magnitude < 1e-3)
-- steer beyond cone is clamped (angle <= cone+eps)
local b = Vector3.new(1,0,0)
local big = G.applySteer(b, Vector3.new(-1,0,0))
local angDeg = math.deg(math.acos(math.clamp(b.Unit:Dot(big.Unit), -1, 1)))
check("big steer clamped to cone", angDeg <= G.steerConeDeg + 0.5)
return table.concat(out, "\n")
```

Expected: every line begins `PASS`. If any `FAIL`, fix `src/shared/GridConfig.luau`, re-commit, re-DEPLOY, re-run. (Note: `applySteer` rotation sign is handedness-sensitive — if "big steer clamped" passes but in-game steer feels mirrored during Task 6, flip the `crossY` sign.)

---

## Task 2: Studio scaffold + greybox arena + measure frame height

**Files:** none (Studio-side scaffolding via MCP). Creates the instances all later DEPLOY steps target, and tunes `GridConfig.frameHeight`.

- [ ] **Step 1: Create the instance skeleton** via MCP `create_object` (or one `execute_luau`):

```lua
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local function ensure(parent, name, class)
	local x = parent:FindFirstChild(name)
	if not x then x = Instance.new(class); x.Name = name; x.Parent = parent end
	return x
end
ensure(RS, "GridConfig", "ModuleScript")
local remotes = ensure(RS, "NineSquareRemotes", "Folder")
ensure(remotes, "Serve", "RemoteEvent")
ensure(remotes, "BallSync", "RemoteEvent")
local nsFolder = ensure(SSS, "NineSquare", "Folder")
ensure(nsFolder, "BallController", "ModuleScript")
ensure(nsFolder, "MatchService", "ModuleScript")
ensure(nsFolder, "HitResolver", "ModuleScript")
ensure(SSS, "NineSquareServer", "Script")
local sp = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
ensure(sp, "NineSquareClient", "LocalScript")
return "instances ensured"
```

- [ ] **Step 2: DEPLOY `src/shared/GridConfig.luau`** into `ReplicatedStorage.GridConfig`, then run Task 1 Step 3 tests. Expected: all `PASS`.

- [ ] **Step 3: Build the greybox arena.** DEPLOY is not needed; run this `execute_luau` (idempotent — rebuilds under `Workspace.NineSquare`). The server will also call an identical builder on init (Task 5), so this is just for immediate visual scaffolding:

```lua
local G = require(game.ReplicatedStorage.GridConfig)
G.origin = Vector3.new(0, 0, 200)  -- place court away from the Obby
local old = workspace:FindFirstChild("NineSquare"); if old then old:Destroy() end
local root = Instance.new("Folder"); root.Name = "NineSquare"; root.Parent = workspace
local floors = Instance.new("Folder"); floors.Name = "Floors"; floors.Parent = root
for name, _ in pairs(G.cells) do
	local p = Instance.new("Part")
	p.Anchored = true; p.Size = Vector3.new(G.squareSize - 0.5, G.floorThickness, G.squareSize - 0.5)
	p.Position = G.cellCenter(name) - Vector3.new(0, G.floorThickness/2, 0)
	p.Color = (name == "C") and Color3.fromRGB(70,70,80) or Color3.fromRGB(150,150,160)
	p.Material = Enum.Material.SmoothPlastic; p.TopSurface = Enum.SurfaceType.Smooth
	p.Name = "Floor_" .. name; p.Parent = floors
end
-- thin overhead frame beams at frameHeight: the 4 grid lines each way
local frame = Instance.new("Folder"); frame.Name = "Frame"; frame.Parent = root
local span = 3 * G.squareSize
for i = -1, 1 do
	local offs = (i) * G.squareSize + G.squareSize/2  -- between-cell lines at +/-0.5, 1.5
	for _, line in ipairs({
		{Vector3.new(span, G.beamThickness, G.beamThickness), Vector3.new(0,0,offs)},  -- E-W beam
		{Vector3.new(G.beamThickness, G.beamThickness, span), Vector3.new(offs,0,0)},  -- N-S beam
	}) do
		local b = Instance.new("Part"); b.Anchored = true; b.Size = line[1]
		b.Position = G.origin + line[2] + Vector3.new(0, G.frameHeight, 0)
		b.Color = Color3.fromRGB(40,40,45); b.Material = Enum.Material.Neon; b.Parent = frame
	end
end
return "arena built at "..tostring(G.origin)
```

- [ ] **Step 4: Measure jump reach (playtest checkpoint).** `start_playtest`. In the play session, run via `execute_luau` (target `"client-1"` or read server-side) a probe that walks the local character to the court and samples the hit-zone apex while jumping:

```lua
local Players = game:GetService("Players")
local plr = Players:GetPlayers()[1]
local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
if not hrp then return "no character yet" end
-- report standing hit-zone height and theoretical jump apex
local standY = hrp.Position.Y + 2.0
local jumpH = hum and hum.JumpHeight or (hum and hum.UseJumpPower and (hum.JumpPower^2)/(2*workspace.Gravity)) or 7.2
return ("standZone=%.1f  jumpHeight=%.1f  predictedApexZone=%.1f"):format(standY, jumpH, standY + jumpH)
```

Read `predictedApexZone`. **Set `GridConfig.frameHeight` to ~that value** (so a full jump's hands reach the frame). Update `src/shared/GridConfig.luau`, commit, re-DEPLOY, rebuild arena (Step 3). `capture_screenshot` to confirm a jumping avatar's hands reach the frame beams. `stop_playtest`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/GridConfig.luau
git commit -m "chore(arena): scaffold Studio instances and tune frameHeight to measured jump reach"
```

---

## Task 3: BallController — serve arc, phase machine, replication

**Files:**
- Create: `src/server/BallController.luau`

- [ ] **Step 1: Write BallController**

```lua
--!strict
-- ServerScriptService.NineSquare.BallController
-- Owns the single anchored ball. Computes deterministic arcs, advances them each tick,
-- and broadcasts arc params to clients for telegraph rendering.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)
local BallSync = RS.NineSquareRemotes.BallSync

local BallController = {}
BallController.__index = BallController

export type Arc = {
	origin: Vector3, target: Vector3, apex: number,
	startT: number, travel: number, kind: string, targetCell: string,
}

function BallController.new()
	local self = setmetatable({}, BallController)
	local ball = Instance.new("Part")
	ball.Name = "Ball"; ball.Shape = Enum.PartType.Ball; ball.Anchored = true
	ball.Size = Vector3.new(G.ballRadius*2, G.ballRadius*2, G.ballRadius*2)
	ball.Color = Color3.fromRGB(255, 220, 60); ball.Material = Enum.Material.SmoothPlastic
	ball.Parent = workspace:WaitForChild("NineSquare")
	self.ball = ball
	self.arc = nil :: Arc?
	self.phase = "Idle"      -- Idle | InFlight | Descending | Resolved
	self.onArrive = nil :: ((Arc) -> ())?
	ball.Position = G.cellFramePoint("C")
	return self
end

-- y along a parabola: endpoints lerp + 4*apex*u*(1-u) bulge.
local function arcPos(arc: Arc, now: number): (Vector3, number)
	local u = math.clamp((now - arc.startT) / arc.travel, 0, 1)
	local flat = arc.origin:Lerp(arc.target, u)
	local y = arc.origin.Y + (arc.target.Y - arc.origin.Y) * u + 4 * arc.apex * u * (1 - u)
	return Vector3.new(flat.X, y, flat.Z), u
end

function BallController:_broadcast()
	local a = self.arc
	if not a then return end
	BallSync:FireAllClients({
		origin = a.origin, target = a.target, apex = a.apex,
		startT = a.startT, travel = a.travel, kind = a.kind, targetCell = a.targetCell,
		descentWindow = G.descentWindow,
	})
end

-- Launch a serve arc from center to a target cell's frame point.
function BallController:serve(targetCell: string)
	local arc: Arc = {
		origin = G.cellFramePoint("C"), target = G.cellFramePoint(targetCell),
		apex = G.apexHeight, startT = workspace:GetServerTimeNow(),
		travel = G.serveTravel, kind = "serve", targetCell = targetCell,
	}
	self.arc = arc; self.phase = "InFlight"
	self:_broadcast()
end

-- Launch a volley lob from a contact point along a horizontal direction (M1: lands, no occupant).
function BallController:volley(fromPoint: Vector3, horizDir: Vector3)
	local dir = horizDir.Magnitude > 1e-3 and horizDir.Unit or Vector3.zero
	local target = fromPoint + dir * G.lobDistance
	target = Vector3.new(target.X, G.cellFramePoint("C").Y, target.Z)
	local landCell = G.cellAtPosition(target) or "C"
	local arc: Arc = {
		origin = fromPoint, target = target, apex = G.apexHeight * 0.6,
		startT = workspace:GetServerTimeNow(), travel = G.lobTravel,
		kind = "volley", targetCell = landCell,
	}
	self.arc = arc; self.phase = "InFlight"
	self:_broadcast()
end

function BallController:reset()
	self.arc = nil; self.phase = "Idle"
	self.ball.Position = G.cellFramePoint("C")
	BallSync:FireAllClients({ kind = "idle" })
end

-- Called every Heartbeat. Moves the ball; fires onArrive once when an arc completes.
function BallController:step()
	local a = self.arc
	if not a then return end
	local now = workspace:GetServerTimeNow()
	local pos, u = arcPos(a, now)
	self.ball.Position = pos
	if self.phase == "InFlight" and (now - a.startT) >= (a.travel - G.descentWindow) then
		self.phase = "Descending"
	end
	if u >= 1 and self.phase ~= "Resolved" then
		self.phase = "Resolved"
		if self.onArrive then self.onArrive(a) end
	end
end

return BallController
```

- [ ] **Step 2: Commit**

```bash
git add src/server/BallController.luau
git commit -m "feat(ball): deterministic serve/volley arcs with anchored ball and BallSync broadcast"
```

(Functional verification happens in Task 5 once the server bootstrap drives it.)

---

## Task 4: ClientRender — telegraph + camera (readability checkpoint)

**Files:**
- Create: `src/client/NineSquareClient.client.luau` (render + camera now; Serve/steer added in Tasks 5–6)

- [ ] **Step 1: Write the client (render + camera portion)**

```lua
--!strict
-- StarterPlayer.StarterPlayerScripts.NineSquareClient
-- Renders the ball shadow, shrinking descent ring, target-square highlight, and locks an angled court camera.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)
local Remotes = RS:WaitForChild("NineSquareRemotes")
local BallSync = Remotes:WaitForChild("BallSync")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- Sync the client's idea of origin with the server's by reading the built floor (C floor sits at origin).
local function courtOrigin(): Vector3
	local ns = workspace:FindFirstChild("NineSquare")
	local cFloor = ns and ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_C")
	if cFloor then return Vector3.new(cFloor.Position.X, 0, cFloor.Position.Z) end
	return G.origin
end

-- Telegraph visuals (created once)
local shadow = Instance.new("Part")
shadow.Anchored = true; shadow.CanCollide = false; shadow.Size = Vector3.new(G.ballRadius*3, 0.1, G.ballRadius*3)
shadow.Shape = Enum.PartType.Cylinder; shadow.Color = Color3.new(0,0,0); shadow.Transparency = 0.4
shadow.Orientation = Vector3.new(0,0,90); shadow.Parent = workspace
local ringGui = Instance.new("BillboardGui")
ringGui.Size = UDim2.fromScale(6,6); ringGui.AlwaysOnTop = false; ringGui.Parent = shadow
local ring = Instance.new("ImageLabel")
ring.BackgroundTransparency = 1; ring.Size = UDim2.fromScale(1,1)
ring.Image = "rbxassetid://5028857084"; ring.ImageColor3 = Color3.fromRGB(255,80,80); ring.Parent = ringGui
local highlight = Instance.new("SelectionBox")
highlight.LineThickness = 0.08; highlight.Color3 = Color3.fromRGB(255,210,80); highlight.Parent = workspace
local function setHidden(h: boolean)
	shadow.Transparency = h and 1 or 0.4; ring.ImageTransparency = h and 1 or 0
end
setHidden(true)

local state: any = nil
BallSync.OnClientEvent:Connect(function(data) state = data; if data.kind=="idle" then setHidden(true) end end)

-- Lock an angled camera south of and above the court, looking north and up at the grid.
local function updateCamera()
	local o = courtOrigin()
	local depth = 3 * G.squareSize
	local eye = o + Vector3.new(0, G.frameHeight + 20, depth * 0.9)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt(eye, o + Vector3.new(0, G.frameHeight * 0.6, 0))
end

RunService.RenderStepped:Connect(function()
	updateCamera()
	local ns = workspace:FindFirstChild("NineSquare")
	local ball = ns and ns:FindFirstChild("Ball")
	if not state or not ball or state.kind == "idle" then setHidden(true); highlight.Adornee = nil; return end
	setHidden(false)
	-- shadow tracks ball XZ on the floor
	local o = courtOrigin()
	shadow.Position = Vector3.new(ball.Position.X, o.Y + 0.06, ball.Position.Z)
	-- ring shrinks from 1.0 -> min over the descent window, min at arrival
	local now = workspace:GetServerTimeNow()
	local tToArrive = (state.startT + state.travel) - now
	local k = math.clamp(tToArrive / state.descentWindow, 0, 1)  -- 1 far out, 0 at arrival
	local scale = 1.2 + 4.0 * k
	ringGui.Size = UDim2.fromScale(scale, scale)
	ring.ImageColor3 = (k < 0.12) and Color3.fromRGB(120,255,120) or Color3.fromRGB(255,80,80)
	-- highlight the target square floor
	local tcell = state.targetCell
	local tfloor = ns:FindFirstChild("Floors") and ns.Floors:FindFirstChild("Floor_" .. tostring(tcell))
	highlight.Adornee = tfloor
end)
```

- [ ] **Step 2: Commit**

```bash
git add src/client/NineSquareClient.client.luau
git commit -m "feat(client): ball shadow, shrinking descent ring, target highlight, angled court camera"
```

- [ ] **Step 3: Readability checkpoint (playtest).** DEPLOY GridConfig, BallController, and NineSquareClient. Temporarily drive a serve so there is a ball to read: `start_playtest`, then `execute_luau` (server target):

```lua
local RS = game:GetService("ReplicatedStorage")
local BallController = require(game.ServerScriptService.NineSquare.BallController)
local G = require(RS.GridConfig)
_G.__bc = _G.__bc or BallController.new()
game:GetService("RunService").Heartbeat:Connect(function() _G.__bc:step() end)
task.spawn(function()
	while true do _G.__bc:serve("N"); task.wait(G.serveTravel + 1.0); _G.__bc:reset(); task.wait(0.5) end
end)
return "looping serve into N"
```

`capture_screenshot` mid-descent. **Verify:** the shadow sits in square N, the ring is visibly shrinking, and you can tell where/when the ball will arrive. If not readable, tune `apexHeight`, `serveTravel`, `descentWindow`, ring scale, or camera in the respective files; commit each tuning change. `stop_playtest`.

---

## Task 5: MatchService + Serve input + server bootstrap (serve into your square)

**Files:**
- Create: `src/server/MatchService.luau`
- Create: `src/server/NineSquareServer.server.luau`
- Modify: `src/client/NineSquareClient.client.luau` (add Serve input)

- [ ] **Step 1: Write MatchService**

```lua
--!strict
-- ServerScriptService.NineSquare.MatchService
-- M1 stub: builds the arena and answers "which outer square is a player under?".
local RS = game:GetService("ReplicatedStorage")
local G = require(RS.GridConfig)

local MatchService = {}

function MatchService.buildArena(origin: Vector3)
	G.origin = origin
	local old = workspace:FindFirstChild("NineSquare"); if old then old:Destroy() end
	local root = Instance.new("Folder"); root.Name = "NineSquare"; root.Parent = workspace
	local floors = Instance.new("Folder"); floors.Name = "Floors"; floors.Parent = root
	for name in pairs(G.cells) do
		local p = Instance.new("Part")
		p.Anchored = true; p.Size = Vector3.new(G.squareSize - 0.5, G.floorThickness, G.squareSize - 0.5)
		p.Position = G.cellCenter(name) - Vector3.new(0, G.floorThickness/2, 0)
		p.Color = (name == "C") and Color3.fromRGB(70,70,80) or Color3.fromRGB(150,150,160)
		p.Material = Enum.Material.SmoothPlastic; p.Name = "Floor_" .. name; p.Parent = floors
	end
	local frame = Instance.new("Folder"); frame.Name = "Frame"; frame.Parent = root
	local span = 3 * G.squareSize
	for i = -1, 1 do
		local offs = i * G.squareSize + G.squareSize/2
		local beams = {
			{ Vector3.new(span, G.beamThickness, G.beamThickness), Vector3.new(0,0,offs) },
			{ Vector3.new(G.beamThickness, G.beamThickness, span), Vector3.new(offs,0,0) },
		}
		for _, ln in ipairs(beams) do
			local b = Instance.new("Part"); b.Anchored = true; b.Size = ln[1]
			b.Position = G.origin + ln[2] + Vector3.new(0, G.frameHeight, 0)
			b.Color = Color3.fromRGB(40,40,45); b.Material = Enum.Material.Neon; b.Parent = frame
		end
	end
	return root
end

-- Outer square a player currently stands under, or nil.
function MatchService.playerCell(plr: Player): string?
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local cell = G.cellAtPosition(hrp.Position)
	if cell and cell ~= "C" then return cell end
	return nil
end

return MatchService
```

- [ ] **Step 2: Write the server bootstrap**

```lua
--!strict
-- ServerScriptService.NineSquareServer
-- Wires the arena, ball, serve handling, and the Heartbeat loop.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local G = require(RS.GridConfig)
local ns = game.ServerScriptService:WaitForChild("NineSquare")
local BallController = require(ns.BallController)
local MatchService = require(ns.MatchService)
local Serve = RS.NineSquareRemotes.Serve

MatchService.buildArena(Vector3.new(0, 0, 200))
local bc = BallController.new()

bc.onArrive = function(arc)
	-- Task 6 replaces this with HitResolver. For now: whiff -> reset after a beat.
	task.delay(0.4, function() bc:reset() end)
end

Serve.OnServerEvent:Connect(function(plr)
	if bc.phase ~= "Idle" then return end
	local cell = MatchService.playerCell(plr)
	if cell then bc:serve(cell) end
end)

RunService.Heartbeat:Connect(function() bc:step() end)
```

- [ ] **Step 3: Add Serve input to the client.** Append to `src/client/NineSquareClient.client.luau`:

```lua
-- Serve input: PC = E key / click, mobile = a button, console = ButtonY.
local UIS = game:GetService("UserInputService")
local Serve = Remotes:WaitForChild("Serve")
local function tryServe() Serve:FireServer() end
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonY then tryServe() end
end)
do
	local btn = Instance.new("ScreenGui"); btn.Name = "NineSquareHUD"; btn.ResetOnSpawn = false; btn.Parent = plr:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton"); b.Size = UDim2.fromOffset(160,64); b.Position = UDim2.new(0.5,-80,1,-100)
	b.Text = "SERVE"; b.TextScaled = true; b.Parent = btn
	b.Activated:Connect(tryServe)
end
```

- [ ] **Step 4: Commit**

```bash
git add src/server/MatchService.luau src/server/NineSquareServer.server.luau src/client/NineSquareClient.client.luau
git commit -m "feat(serve): match-service square lookup, server bootstrap, and client serve input"
```

- [ ] **Step 5: Playtest verify.** DEPLOY MatchService, NineSquareServer, NineSquareClient (and ensure GridConfig/BallController deployed). `start_playtest`. Walk under square N, press **E** (or SERVE). **Verify:** ball serves from center into N; walk under E, serve again → it goes into E. Serving while a ball is live does nothing. `capture_screenshot`. `stop_playtest`.

---

## Task 6: HitResolver — contact volley (contact checkpoint)

**Files:**
- Create: `src/server/HitResolver.luau`
- Modify: `src/server/NineSquareServer.server.luau` (use HitResolver on arrive)

- [ ] **Step 1: Write HitResolver**

```lua
--!strict
-- ServerScriptService.NineSquare.HitResolver
-- At ball arrival, decide contact vs whiff from replicated character state, and compute the volley.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local G = require(RS.GridConfig)

local HitResolver = {}

-- hit-zone center = above the player's HumanoidRootPart (hands/head at jump apex).
local function hitZoneCenter(plr: Player): Vector3?
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position + Vector3.new(0, G.hitZoneYOffset, 0)
end

local function steerOf(plr: Player): Vector3
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum.MoveDirection or Vector3.zero
end

export type Result = { contact: boolean, point: Vector3, dir: Vector3, player: Player? }

-- arc has .target (contact point) and .targetCell. Find the occupant under targetCell and test overlap.
function HitResolver.resolve(arc: any): Result
	local ballPos = arc.target
	for _, plr in ipairs(Players:GetPlayers()) do
		local cell = (function()
			local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			return hrp and G.cellAtPosition(hrp.Position) or nil
		end)()
		if cell == arc.targetCell then
			local hz = hitZoneCenter(plr)
			if hz and (ballPos - hz).Magnitude <= (G.hitZoneRadius + G.ballRadius) then
				local base = G.reflectDir(ballPos, hz)
				local dir = G.applySteer(base, steerOf(plr))
				return { contact = true, point = ballPos, dir = dir, player = plr }
			end
		end
	end
	return { contact = false, point = ballPos, dir = Vector3.zero, player = nil }
end

return HitResolver
```

- [ ] **Step 2: Use it in the bootstrap.** Replace the `bc.onArrive` block in `src/server/NineSquareServer.server.luau`:

```lua
local HitResolver = require(ns.HitResolver)
bc.onArrive = function(arc)
	local res = HitResolver.resolve(arc)
	if res.contact then
		bc:volley(res.point, res.dir)          -- volley re-enters InFlight; lands (no occupant in M1)
		task.delay(G.lobTravel + 0.4, function() if bc.phase == "Resolved" then bc:reset() end end)
	else
		task.delay(0.4, function() bc:reset() end)  -- whiff
	end
end
```

- [ ] **Step 3: Unit-test the reflection decision** via `execute_luau` (no playtest needed — uses a fake arc + a real player if present, else asserts pure pieces):

```lua
local G = require(game.ReplicatedStorage.GridConfig)
local out = {}
local function check(n,c) out[#out+1]=(c and "PASS " or "FAIL ")..n end
-- contact just inside radius resolves to contact; just outside resolves to whiff (geometry only)
local ball = Vector3.new(0, G.frameHeight, 200)
local nearHands = ball - Vector3.new(0, G.hitZoneRadius*0.5, 0)
local farHands  = ball - Vector3.new(0, G.hitZoneRadius + G.ballRadius + 3, 0)
check("near overlaps", (ball - nearHands).Magnitude <= G.hitZoneRadius + G.ballRadius)
check("far misses", (ball - farHands).Magnitude > G.hitZoneRadius + G.ballRadius)
-- off-center contact yields nonzero horizontal direction
check("offset gives dir", G.reflectDir(ball, ball - Vector3.new(1.5,2,0)).Magnitude > 0.5)
return table.concat(out,"\n")
```

Expected: all `PASS`.

- [ ] **Step 4: Commit**

```bash
git add src/server/HitResolver.luau src/server/NineSquareServer.server.luau
git commit -m "feat(contact): hit-zone overlap + reflection/steer volley resolution"
```

- [ ] **Step 5: Contact checkpoint (playtest).** DEPLOY HitResolver + NineSquareServer. `start_playtest`. Stand under N, serve, and **jump** as the ring bottoms out. **Verify:** a well-timed jump volleys the ball back up; a mistimed jump (too early/late, or no jump) whiffs and resets. Then test direction: contact the ball off-center / hold a movement direction during the jump and confirm the **outgoing direction changes** with where you strike it. `capture_screenshot` of a successful volley. If steer feels mirrored, flip the `crossY` sign in `GridConfig.applySteer` (Task 1 note), commit. `stop_playtest`.

---

## Task 7: M1 acceptance pass + tag

**Files:** none (verification + tag)

- [ ] **Step 1: Run the full acceptance loop (playtest)** against the spec's §1 success criteria:
  1. Standing under any outer square, shadow + ring make where/when **readable**.
  2. A timed **jump** lands a volley (reach + touch both required).
  3. **Contact point visibly changes outgoing direction** (off-center deflects; steer nudges).
  4. Key numbers live in `GridConfig` and were tuned live.

  Capture one screenshot per criterion as evidence.

- [ ] **Step 2: Record results.** Append a short "M1 acceptance" note (date, pass/fail per criterion, final tuned values) to `docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md` under a new `## M1 Acceptance` heading.

- [ ] **Step 3: Commit + tag**

```bash
git add docs/superpowers/specs/2026-06-09-nine-square-m1-greybox-design.md
git commit -m "docs(m1): record greybox acceptance results and final tuned values"
git tag -a m1-greybox -m "Milestone 1: greybox readability prototype complete"
```

- [ ] **Step 4: Go/no-go.** If all four criteria pass, M1 is done — proceed to plan M2 (timing tiers + scatter on this same contact). If any fail, file the specific tuning/work needed and iterate before tagging.

---

## Self-review notes (author)

- **Spec coverage:** arena/dimensions (Task 2), server-authoritative deterministic ball (Task 3), shadow+ring+highlight+camera telegraph (Task 4), free movement + serve-into-current-square (Task 5), jump+touch contact with reflection+steer and whiff (Task 6), GridConfig tunables (Task 1), success-criteria gate (Task 7). All §-sections of the M1 spec map to a task.
- **M1 simplification (intentional, flagged):** contact reads replicated character state (position + `Humanoid.MoveDirection`) instead of timestamped client intents; strict intent validation + anti-cheat is deferred to M5 per the PRD. Serve is the only client→server intent.
- **Type/name consistency:** `serve`, `volley`, `reset`, `step`, `onArrive`, `BallController.new`, `MatchService.buildArena`/`playerCell`, `HitResolver.resolve`, `GridConfig.cellCenter`/`cellFramePoint`/`cellAtPosition`/`reflectDir`/`applySteer` are used consistently across tasks.
- **Known tunables likely to need playtest adjustment:** `frameHeight` (measured in Task 2), `apexHeight`/`serveTravel`/`descentWindow` (Task 4), `hitZoneRadius`/`hitZoneYOffset`/`lobDistance` (Task 6), and the `applySteer` rotation sign.
