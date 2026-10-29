--!strict
-- Items: every item that can sit in an inventory, in catalogue order. Authored content
-- only; who holds what lives in InventoryService, what a machine does with an item lives
-- in Shared/Factory/Blocks. Blocks and machines are placed on the build grid, tools are
-- held and swung, resources are what the world and the machines produce.

export type Kind = "Tool" | "Block" | "Machine" | "Resource"

export type Item = {
	id: string,
	name: string,
	kind: Kind,
	-- Most of this item one slot can hold.
	stack: number,
	description: string?,
	-- Tools only: swinging it at one of your placed blocks picks the block back up.
	picksUp: boolean?,
	-- Blocks only: the tool that breaks a placed one back into your inventory.
	breaksWith: string?,
}

local BLOCK_STACK = 99
local CONVEYOR_STACK = 99
local MACHINE_STACK = 10
local RESOURCE_STACK = 99

local function tool(id: string, name: string, description: string, picksUp: boolean?): Item
	return { id = id, name = name, kind = "Tool", stack = 1, description = description, picksUp = picksUp }
end

local function block(id: string, name: string, description: string, breaksWith: string): Item
	return {
		id = id,
		name = name,
		kind = "Block",
		stack = BLOCK_STACK,
		description = description,
		breaksWith = breaksWith,
	}
end

local function machine(id: string, name: string, description: string, stack: number?): Item
	return { id = id, name = name, kind = "Machine", stack = stack or MACHINE_STACK, description = description }
end

local function resource(id: string, name: string, description: string): Item
	return { id = id, name = name, kind = "Resource", stack = RESOURCE_STACK, description = description }
end

local ITEMS: { Item } = {
	tool("Hammer", "Hammer", "Swing at a block you placed to pick it back up, contents and all.", true),
	tool("Pickaxe", "Pickaxe", "Mines rocks, and breaks stone, glass and earth blocks you placed."),
	tool("Axe", "Axe", "Chops trees and saplings, and breaks wooden blocks you placed."),

	block("Grass", "Grass", "Soft ground with a green top.", "Pickaxe"),
	block("Dirt", "Dirt", "Plain earth.", "Pickaxe"),
	block("Stone", "Stone", "Solid grey rock. Cut it, polish it, or build with it.", "Pickaxe"),
	block("SmoothStone", "Smooth Stone", "Stone polished flat by an Industrial Polishing Station.", "Pickaxe"),
	block("StoneBricks", "Stone Bricks", "Stone cut into bricks by an Industrial Stonecutter.", "Pickaxe"),
	block("WoodPlanks", "Wood Planks", "Sawn timber for floors and walls.", "Axe"),
	block("Bricks", "Bricks", "Fired clay, stacked tight.", "Pickaxe"),
	block("Glass", "Glass", "See-through and surprisingly sturdy.", "Pickaxe"),
	block("Sapling", "Sapling", "Plant it and it grows into an oak tree in a minute.", "Axe"),

	machine("ConveyorBelt", "Conveyor Belt", "Carries items forward.", CONVEYOR_STACK),
	machine("ConveyorBeltLeft", "Conveyor Belt Left", "Turns items to the left.", CONVEYOR_STACK),
	machine("ConveyorBeltRight", "Conveyor Belt Right", "Turns items to the right.", CONVEYOR_STACK),
	machine("ConveyorBeltTier2", "Conveyor Belt Tier 2", "Carries items forward at twice the speed.", CONVEYOR_STACK),
	machine("ConveyorBeltLeftTier2", "Conveyor Belt Left Tier 2", "A fast left turn.", CONVEYOR_STACK),
	machine("ConveyorBeltRightTier2", "Conveyor Belt Right Tier 2", "A fast right turn.", CONVEYOR_STACK),
	machine("ConveyorRamp", "Conveyor Ramp", "Lifts items up one block.", CONVEYOR_STACK),
	machine("ConveyorRampDown", "Conveyor Ramp Down", "Lowers items one block.", CONVEYOR_STACK),
	machine("ConveyorRampTier2", "Conveyor Ramp Tier 2", "Lifts items up one block, fast.", CONVEYOR_STACK),
	machine("ConveyorRampDownTier2", "Conveyor Ramp Down Tier 2", "Lowers items one block, fast.", CONVEYOR_STACK),
	machine(
		"ConveyorSensor",
		"Conveyor Sensor",
		"Flashes when an item passes and powers split conveyors touching it for a moment.",
		CONVEYOR_STACK
	),
	machine(
		"FilterConveyor",
		"Filter Conveyor",
		"Click it holding an item to send that item left; anything unfiltered goes straight on. Click empty-handed to clear."
	),
	machine(
		"SplitConveyor",
		"Split Conveyor",
		"Sends items straight on, or to the side while powered by a sensor. Click empty-handed to switch it."
	),
	machine("Merger", "Merger", "Merges the conveyors at its back and front into the one at its side."),
	machine("Randomizer", "Randomizer", "Sends each item straight on or to the side at random."),
	machine(
		"WoodTube",
		"Wood Tube",
		"Carries maple sap and syrup. Place it against a tube to join it: beside it to turn, on or under it to go up or down.",
		CONVEYOR_STACK
	),
	machine("WoodTubeMerger", "Wood Tube Merger", "Joins a branch into a wood tube line.", CONVEYOR_STACK),

	machine("Drill", "Drill", "Place it on a copper or gold deposit and fuel it with coal to mine ore."),
	machine("Pumpjack", "Pumpjack", "Place it on an oil deposit and fuel it with coal to pump oil."),
	machine(
		"IndustrialLumbermill",
		"Industrial Lumbermill",
		"Fuelled with coal, it chops the tree just past its tower and outputs the logs and a sapling."
	),
	machine("IndustrialSawmill", "Industrial Sawmill", "Saws logs into wood planks. Runs on coal."),
	machine("IndustrialStonecutter", "Industrial Stonecutter", "Cuts stone into stone bricks. Runs on coal."),
	machine("IndustrialSmelter", "Industrial Smelter", "Smelts iron, copper and gold ore into bars. Runs on coal."),
	machine(
		"IndustrialPolishingStation",
		"Industrial Polishing Station",
		"Polishes stone into smooth stone. Runs on coal."
	),
	machine("IndustrialWashingStation", "Industrial Washing Station", "Washes the dirt off truffles. Runs on coal."),
	machine("IndustrialOven", "Industrial Oven", "Bakes berry dough into berry bread. Runs on coal."),
	machine("IndustrialMilker", "Industrial Milker", "Milks fed cows near it."),
	machine("IndustrialBerryBasket", "Industrial Berry Basket", "Gathers blueberries from bushes near it."),
	machine(
		"IndustrialFlowerPicker",
		"Industrial Flower Picker",
		"Picks tulips from flower patches near it. Runs on petroleum."
	),
	machine("IndustrialTruffleBarrel", "Industrial Truffle Barrel", "Collects the truffles fed pigs near it dig up."),
	machine(
		"IndustrialMerchantTeleseller",
		"Industrial Merchant Teleseller",
		"Sells the resources fed into it, one a second."
	),
	machine("CopperPress", "Copper Press", "Presses copper bars into copper plates."),
	machine("SteelPress", "Steel Press", "Presses steel bars into steel plates."),
	machine("SteelMill", "Steel Mill", "Turns iron bars into steel bars. Runs on coal."),
	machine("RedBronzeRefinery", "Red Bronze Refinery", "Refines copper and gold bars into red bronze. Runs on coal."),
	machine("OilRefinery", "Oil Refinery", "Refines oil into petroleum."),
	machine("PetroleumPetrifier", "Petroleum Petrifier", "Turns petroleum into petrified petroleum, a strong fuel."),
	machine("FuelBarrelFiller", "Fuel Barrel Filler", "Fills a barrel from six oil or six petroleum."),
	machine("FuelBarrelExtractor", "Fuel Barrel Extractor", "Empties a fuel barrel back into six oil or petroleum."),
	machine("FoodProcessor", "Food Processor", "Mixes blueberries and milk into berry dough."),
	machine("CratePacker", "Crate Packer", "Packs 20 apples or blueberries into a fruit crate."),
	machine("CratePackerTier2", "Crate Packer Tier 2", "Packs 50 apples or blueberries into a large fruit crate."),
	machine("PalletPacker", "Pallet Packer", "Packs 10 wood planks into a pallet."),
	machine("SapBoiler", "Sap Boiler", "Boils maple sap from wood tubes into syrup, sent on through the tubes."),
	machine("SyrupBottler", "Syrup Bottler", "Bottles syrup from wood tubes into maple syrup."),
	machine(
		"SaplingAutomaticPlanter",
		"Sapling Automatic Planter",
		"Plants saplings just past its forks. Runs on petroleum."
	),
	machine(
		"TreeFruitShaker",
		"Tree Fruit Shaker",
		"Shakes apples off the apple tree just past its forks. Runs on petroleum."
	),
	machine("AutomatedTrough", "Automated Trough", "Feeds apples or blueberries to cows, sheep and pigs near it."),
	machine("WoolVacuum", "Wool Vacuum", "Shears fed sheep near it."),

	resource("Log", "Log", "Oak wood. Saw it into planks."),
	resource("Coal", "Coal", "Fuel for most machines."),
	resource("IronOre", "Iron Ore", "Smelt it into an iron bar."),
	resource("CopperOre", "Copper Ore", "Smelt it into a copper bar."),
	resource("GoldOre", "Gold Ore", "Smelt it into a gold bar."),
	resource("IronBar", "Iron Bar", "A steel mill turns it into steel."),
	resource("CopperBar", "Copper Bar", "Press it into a plate, or refine it with gold."),
	resource("GoldBar", "Gold Bar", "Refine it with copper into red bronze."),
	resource("SteelBar", "Steel Bar", "Press it into a steel plate."),
	resource("RedBronzeBar", "Red Bronze Bar", "A prized alloy of copper and gold."),
	resource("CopperPlate", "Copper Plate", "A pressed copper part."),
	resource("SteelPlate", "Steel Plate", "A pressed steel part."),
	resource("Apple", "Apple", "Shaken from apple trees. Animals love them."),
	resource("Blueberry", "Blueberry", "Picked from berry bushes."),
	resource("Tulip", "Tulip", "Picked from flower patches."),
	resource("Truffle", "Truffle", "Dug up by pigs. Still muddy."),
	resource("CleanTruffle", "Clean Truffle", "A washed truffle, ready to sell."),
	resource("Wool", "Wool", "Vacuumed from sheep."),
	resource("MilkBucket", "Milk Bucket", "Fresh from a cow."),
	resource("BerryDough", "Berry Dough", "Bake it into berry bread."),
	resource("BerryBread", "Berry Bread", "Warm from the oven."),
	resource("FruitCrate", "Fruit Crate", "Twenty pieces of fruit, packed."),
	resource("LargeFruitCrate", "Large Fruit Crate", "Fifty pieces of fruit, packed."),
	resource("Pallet", "Pallet", "Ten planks, packed for shipping."),
	resource("Oil", "Oil", "Crude oil from a pumpjack. Refine it into petroleum."),
	resource("Petroleum", "Petroleum", "Refined oil. Fuel for planters, pickers and shakers."),
	resource("PetrifiedPetroleum", "Petrified Petroleum", "Solid fuel that burns twice as long as coal."),
	resource("OilBarrel", "Oil Barrel", "Six oil in one barrel."),
	resource("PetroleumBarrel", "Petroleum Barrel", "Six petroleum in one barrel."),
	resource("MapleSyrup", "Maple Syrup", "Bottled syrup from maple sap."),
}

return ITEMS
