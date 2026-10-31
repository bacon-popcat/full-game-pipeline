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
	-- Studs its art sits above its cell: the starter Farmland lies one level under the ground,
	-- and this keeps its top just proud of the grass.
	lift: number?,
}

export type Crop = {
	name: string,
	seed: string,
	produce: string,
	yield: number,
	rarity: string,
	price: number,
	value: number,
	grow: number,
	every: number,
	regrow: number?,
	art: string,
	color: Color3,
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

local function defineCrop(
	name: string,
	rarity: string,
	price: number,
	value: number,
	grow: number,
	yield: number,
	regrow: number?,
	art: string,
	color: Color3
): Crop
	return {
		name = name,
		seed = name .. "Seeds",
		produce = name,
		rarity = rarity,
		price = price,
		value = value,
		grow = grow,
		every = grow / 4,
		yield = yield,
		regrow = regrow,
		art = art,
		color = color,
	}
end

local CROPS: { [string]: Crop } = {
	Carrot = defineCrop("Carrot", "Common", 10, 18, 60, 1, nil, "Carrot", Color3.fromRGB(240, 151, 80)),
	Wheat = defineCrop("Wheat", "Common", 15, 12, 75, 2, nil, "Wheat", Color3.fromRGB(234, 204, 112)),
	Strawberry = defineCrop("Strawberry", "Uncommon", 45, 15, 90, 3, 45, "Potato", Color3.fromRGB(232, 117, 133)),
	Potato = defineCrop("Potato", "Uncommon", 60, 70, 120, 1, nil, "Potato", Color3.fromRGB(202, 174, 128)),
	Tomato = defineCrop("Tomato", "Rare", 150, 35, 150, 2, 60, "Carrot", Color3.fromRGB(224, 113, 97)),
	Corn = defineCrop("Corn", "Rare", 250, 160, 240, 1, nil, "Wheat", Color3.fromRGB(244, 218, 113)),
	Blueberry = defineCrop("Blueberry", "Rare", 400, 30, 180, 4, 50, "Potato", Color3.fromRGB(131, 151, 221)),
	Pumpkin = defineCrop("Pumpkin", "Epic", 1200, 1100, 480, 1, nil, "Potato", Color3.fromRGB(232, 164, 97)),
	Apple = defineCrop("Apple", "Epic", 3000, 90, 360, 3, 90, "Carrot", Color3.fromRGB(221, 137, 130)),
	Watermelon = defineCrop(
		"Watermelon",
		"Legendary",
		6000,
		3500,
		600,
		1,
		nil,
		"Potato",
		Color3.fromRGB(143, 191, 127)
	),
	Grape = defineCrop("Grape", "Legendary", 10000, 260, 480, 4, 120, "Wheat", Color3.fromRGB(179, 141, 215)),
	Starfruit = defineCrop("Starfruit", "Mythic", 30000, 1800, 720, 2, 150, "Carrot", Color3.fromRGB(247, 228, 141)),
}

NODES.Farmland = {
	name = "Farmland",
	hint = "Tilled soil. Plant seeds on it, as on grass or dirt.",
	soil = true,
	lift = 0.1,
}

local PLANTS: { [string]: Plant } = {}

for cropId, crop in CROPS do
	PLANTS[crop.seed] = { node = cropId .. STAGES[1], soil = true }
	for stage, suffix in STAGES do
		local ripe = stage == #STAGES
		NODES[cropId .. suffix] = {
			name = if stage == 1 then `{crop.name} Sprout` else `{suffix} {crop.name}`,
			hint = if ripe
				then "Ripe. Harvest it empty-handed, or let a Harvester reap it."
				else "Growing. Dig it up empty-handed to get its seed back.",
			harvest = if ripe then { [crop.produce] = crop.yield } else { [crop.seed] = 1 },
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
