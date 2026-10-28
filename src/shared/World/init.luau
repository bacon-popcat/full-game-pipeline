--!strict
-- World: the resource nodes and animals the world offers, as data. WorldService spawns and
-- runs them; FactoryService asks it what stands near a machine; clients read the hints to
-- tell players what a node is for. Where each one spawns is World/Layout.
--
-- Node art lives in ReplicatedStorage.Assets.World, named by node type, with a hitbox
-- PrimaryPart like a block's (docs/inventory.md), so a node sits on whole cells and a
-- machine finds it by cell. Animal art lives there too, named by animal type.

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
}

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

return World
