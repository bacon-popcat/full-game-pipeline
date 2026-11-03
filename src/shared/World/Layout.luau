--!strict
-- Layout: the world's shared nodes, in Build cells: the quarry's rocks in the hub, and the forest's
-- trees through Shared/World/Map's forest ring. Plot farms belong to PlotService.
--
-- Trees stand on a jittered grid, thicker in groves (a slow noise field), kept clear of the
-- forest's paths and ponds. The scatter is seeded, so every server grows the same forest and a
-- chopped tree grows back where it stood. Pines lean north, birches south, oaks east and west.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Map = require(ReplicatedStorage.Shared.World.Map)

export type Spot = { node: string, cell: Vector3 }
local NODES: { Spot } = {}
for index, node in { "StoneRock", "CoalRock", "IronRock", "CopperRock" } do
	for row = 0, 2 do
		table.insert(NODES, { node = node, cell = Vector3.new(24 + index * 4, 0, -8 + row * 5) })
	end
end

-- Studs between grid points, and how far each tree may wander off its point.
local SPACING, JITTER = 34, 10
-- Studs a tree keeps from the forest's edges, and from its paths and ponds.
local EDGE_PAD, CLEAR_PAD = 8, 7
-- Studs across a grove, in the noise that thickens and thins the wood.
local GROVE = 150
local SEED = 1228

-- Species weights (oak, pine, birch) by side of the map.
local function species(point: Vector2, roll: number): string
	local oak, pine = 0.5, 0.25
	if point.Y < -Map.GROUND.Y then
		oak, pine = 0.25, 0.55
	elseif point.Y > Map.GROUND.Y then
		oak, pine = 0.35, 0.2
	end
	return if roll < oak then "ForestOak" elseif roll < oak + pine then "ForestPine" else "ForestBirch"
end

local random = Random.new(SEED)
local forest = Map.FOREST_EDGE
for x = -forest.X, forest.X, SPACING do
	for z = -forest.Y, forest.Y, SPACING do
		local point = Vector2.new(x + random:NextNumber(-JITTER, JITTER), z + random:NextNumber(-JITTER, JITTER))
		local grove = math.clamp(0.5 + math.noise(point.X / GROVE, point.Y / GROVE, 0.37), 0, 1)
		local keep, roll = random:NextNumber(), random:NextNumber()
		if Map.inForest(point, EDGE_PAD) and Map.isClear(point, CLEAR_PAD) and keep < 0.15 + 0.5 * grove then
			local cell = Vector3.new(math.floor(point.X / Build.GRID), 0, math.floor(point.Y / Build.GRID))
			table.insert(NODES, { node = species(point, roll), cell = cell })
		end
	end
end

return { nodes = NODES }
