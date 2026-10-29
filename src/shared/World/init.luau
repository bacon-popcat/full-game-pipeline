--!strict
-- World: the resource nodes and animals the world offers, as data. WorldService spawns and
-- runs them; FactoryService asks it what stands near a machine; clients read the hints to
-- tell players what a node is for. Where each one spawns is World/Layout.
--
-- Node art lives in ReplicatedStorage.Assets.World, named by node type, with a hitbox
-- PrimaryPart like a block's (docs/inventory.md), so a node sits on whole cells and a
-- machine finds it by cell. Animal art lives there too, named by animal type.
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
	-- An empty-handed click picks this, then it needs `regrow` seconds before the next.
	pick: { item: string, regrow: number }?,
	-- A sapling grows into `into` after `after` seconds.
	grows: { into: string, after: number }?,
	-- Seconds per unit of sap it gives a wood tube touching it.
	sap: number?,
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

export type Animal = {
	name: string,
	hint: string,
	-- Studs per second while it wanders.
	speed: number,
}

local NODES: { [string]: Node } = {
	CopperDeposit = { name = "Copper Deposit", hint = "Place a Drill on top and fuel it to mine copper ore." },
	GoldDeposit = { name = "Gold Deposit", hint = "Place a Drill on top and fuel it to mine gold ore." },
	OilDeposit = { name = "Oil Deposit", hint = "Place a Pumpjack on top and fuel it to pump oil." },
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
	OakTree = {
		name = "Oak Tree",
		hint = "Chop it with an Axe or an Industrial Lumbermill.",
		tool = "Axe",
		drops = { Log = 3, Sapling = 1 },
		respawn = 60,
	},
	MapleTree = {
		name = "Maple Tree",
		hint = "Run Wood Tubes from it to a Sap Boiler for sap.",
		tool = "Axe",
		drops = { Log = 3 },
		respawn = 60,
		sap = 8,
	},
	AppleTree = {
		name = "Apple Tree",
		hint = "A Tree Fruit Shaker harvests its apples.",
		tool = "Axe",
		drops = { Log = 2, Apple = 2 },
		respawn = 60,
	},
	Sapling = {
		name = "Sapling",
		hint = "Growing into an oak tree.",
		tool = "Axe",
		drops = { Sapling = 1 },
		grows = { into = "OakTree", after = 60 },
	},
	BerryBush = {
		name = "Berry Bush",
		hint = "Pick blueberries empty-handed, or let an Industrial Berry Basket gather them.",
		pick = { item = "Blueberry", regrow = 20 },
	},
	FlowerPatch = {
		name = "Flower Patch",
		hint = "Pick tulips empty-handed, or let an Industrial Flower Picker gather them.",
		pick = { item = "Tulip", regrow = 20 },
	},
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

local PLANTS: { [string]: Plant } = {
	Sapling = { node = "Sapling", soil = false },
}

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
			grows = if ripe then nil else { into = cropId .. STAGES[stage + 1], after = crop.every },
			crop = cropId,
			stage = stage,
		}
	end
end

local ANIMALS: { [string]: Animal } = {
	Cow = { name = "Cow", hint = "Feed it from an Automated Trough; an Industrial Milker milks it.", speed = 3 },
	Sheep = { name = "Sheep", hint = "Feed it from an Automated Trough; a Wool Vacuum shears it.", speed = 3 },
	Pig = {
		name = "Pig",
		hint = "Feed it from an Automated Trough; it digs truffles for an Industrial Truffle Barrel.",
		speed = 3.5,
	},
}

local World = {}

-- Seconds an animal stays fed after eating once.
World.FED_FOR = 60
World.NODES = NODES
World.ANIMALS = ANIMALS
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

function World.getAnimal(animalType: string): Animal
	local animal = ANIMALS[animalType]
	assert(animal, `World.getAnimal: unknown animal type "{animalType}"`)
	return animal
end

-- The node type of a crop's stage.
function World.cropStage(cropId: string, stage: number): string
	return cropId .. STAGES[stage]
end

function World.isRipe(node: Node): boolean
	return node.crop ~= nil and node.stage == #STAGES
end

return World
