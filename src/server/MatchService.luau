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
