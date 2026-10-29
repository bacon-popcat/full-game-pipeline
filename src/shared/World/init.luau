--!strict
-- World: the quarry and crop nodes the world offers, as data. WorldService spawns and
-- runs them; FactoryService asks it what stands near a machine; clients read the hints to
-- tell players what a node is for. Where each one spawns is World/Layout.
--
-- Node art lives in ReplicatedStorage.Assets.World, named by node type, with a hitbox
-- PrimaryPart like a block's (docs/inventory.md), so a node sits on whole cells and a
-- machine finds it by cell.
--
-- Crops are nodes too: one node type per growth stage (<Crop><Stage>, WheatSprout ...
-- WheatRipe), each growing into the next, built from CROPS below. PLANTS says which node an
-- item plants as and whether it needs soil under it (World/Soil); docs/farming.md has the flow.

export type Node = {
	name: string,
	-- Shown when a player looks at it.
	hint: string,
	-- The tool that breaks it, and what that gives.
	tool: string?,
	drops: { [string]: number }?,
	-- Seconds until a broken node the world spawned comes back. Grown ones don't.
	respawn: number?,
	-- An empty-handed click uproots it for these: a crop's seed back, or when ripe its harvest.
	harvest: { [string]: number }?,
	-- A crop stage: which crop (a CROPS key), and its stage, 1 to #STAGES (the last is ripe).
	crop: string?,
	stage: number?,
	-- Crops can be planted on top of it.
	soil: boolean?,
}

export type Crop = {
	name: string,
	seed: string,
	-- What harvesting it ripe gives, by hand. A machine reaping it gets `reaped` of the
	-- produce instead and the crop starts again from a sprout, so its seed is kept.
	harvest: { [string]: number },
	produce: string,
	reaped: number,
	-- Seconds each stage takes to grow into the next.
	every: number,
}

-- What a placed item turns into: the node it plants as, and whether that needs soil below.
export type Plant = { node: string, soil: boolean }

local NODES: { [string]: Node } = {
	StoneRock = {
		name = "Stone Rock",
		hint = "Mine it with a Pickaxe.",
		tool = "Pickaxe",
		drops = { Stone = 2 },
		respawn = 30,
	},
	CoalRock = {
		name = "Coal Rock",
		hint = "Mine it with a Pickaxe for coal.",
		tool = "Pickaxe",
		drops = { Coal = 2, Stone = 1 },
		respawn = 30,
	},
	IronRock = {
		name = "Iron Rock",
		hint = "Mine it with a Pickaxe for iron ore.",
		tool = "Pickaxe",
		drops = { IronOre = 2, Stone = 1 },
		respawn = 45,
	},
}

NODES.CopperRock = {
	name = "Copper Rock",
	hint = "Mine it with a Pickaxe for copper ore.",
	tool = "Pickaxe",
	drops = { CopperOre = 2, Stone = 1 },
	respawn = 45,
}

local STAGES = { "Sprout", "Young", "Mature", "Ripe" }

local CROPS: { [string]: Crop } = {
	Wheat = {
		name = "Wheat",
		seed = "WheatSeeds",
		harvest = { Wheat = 1, WheatSeeds = 2 },
		produce = "Wheat",
		reaped = 1,
		every = 15,
	},
	Carrot = {
		name = "Carrot",
		seed = "CarrotSeeds",
		harvest = { Carrot = 2, CarrotSeeds = 1 },
		produce = "Carrot",
		reaped = 2,
		every = 20,
	},
	Potato = {
		name = "Potato",
		seed = "PotatoSeeds",
		harvest = { Potato = 3, PotatoSeeds = 1 },
		produce = "Potato",
		reaped = 3,
		every = 25,
	},
}

NODES.Farmland = {
	name = "Farmland",
	hint = "Tilled soil. Plant seeds on it, as on grass or dirt.",
	soil = true,
}

local PLANTS: { [string]: Plant } = {}

for cropId, crop in CROPS do
	PLANTS[crop.seed] = { node = cropId .. STAGES[1], soil = true }
	for stage, suffix in STAGES do
		local ripe = stage == #STAGES
		NODES[cropId .. suffix] = {
			name = if stage == 1 then `{crop.name} Sprout` else `{suffix} {crop.name}`,
			hint = if ripe
				then "Ripe. Harvest it empty-handed, or let an Industrial Flower Picker reap it."
				else "Growing. Dig it up empty-handed to get its seed back.",
			harvest = if ripe then crop.harvest else { [crop.seed] = 1 },
			crop = cropId,
			stage = stage,
		}
	end
end

local World = {}

World.NODES = NODES
World.CROPS = CROPS
World.STAGES = STAGES
World.PLANTS = PLANTS
-- Placed blocks a crop can grow on, as well as nodes marked `soil`.
World.SOIL_BLOCKS = { Grass = true, Dirt = true }

function World.getNode(nodeType: string): Node
	local node = NODES[nodeType]
	assert(node, `World.getNode: unknown node type "{nodeType}"`)
	return node
end

-- The node type of a crop's stage.
function World.cropStage(cropId: string, stage: number): string
	return cropId .. STAGES[stage]
end

function World.isRipe(node: Node): boolean
	return node.crop ~= nil and node.stage == #STAGES
end

return World
