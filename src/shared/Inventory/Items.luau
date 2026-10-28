--!strict
-- Items: every item that can sit in an inventory, in catalogue order. Authored content
-- only; who holds what lives in InventoryService. Blocks and machines are both placed on
-- the build grid; tools are held and swung.

export type Kind = "Tool" | "Block" | "Machine"

export type Item = {
	id: string,
	name: string,
	kind: Kind,
	-- Most of this item one slot can hold.
	stack: number,
	description: string?,
	-- Tools only: swinging it at one of your placed blocks picks the block back up.
	picksUp: boolean?,
}

local BLOCK_STACK = 99
local CONVEYOR_STACK = 99
local MACHINE_STACK = 10

local function tool(id: string, name: string, description: string, picksUp: boolean?): Item
	return { id = id, name = name, kind = "Tool", stack = 1, description = description, picksUp = picksUp }
end

local function block(id: string, name: string, description: string): Item
	return { id = id, name = name, kind = "Block", stack = BLOCK_STACK, description = description }
end

local function machine(id: string, name: string, stack: number?): Item
	return { id = id, name = name, kind = "Machine", stack = stack or MACHINE_STACK }
end

local ITEMS: { Item } = {
	tool("Hammer", "Hammer", "Swing at a block you placed to pick it back up.", true),
	tool("Pickaxe", "Pickaxe", "Breaks rock and ore."),
	tool("Axe", "Axe", "Chops trees."),

	block("Grass", "Grass", "Soft ground with a green top."),
	block("Dirt", "Dirt", "Plain earth."),
	block("Stone", "Stone", "Solid grey rock."),
	block("WoodPlanks", "Wood Planks", "Sawn timber for floors and walls."),
	block("Bricks", "Bricks", "Fired clay, stacked tight."),
	block("Glass", "Glass", "See-through and surprisingly sturdy."),

	machine("ConveyorBelt", "Conveyor Belt", CONVEYOR_STACK),
	machine("ConveyorBeltLeft", "Conveyor Belt Left", CONVEYOR_STACK),
	machine("ConveyorBeltRight", "Conveyor Belt Right", CONVEYOR_STACK),
	machine("ConveyorBeltTier2", "Conveyor Belt Tier 2", CONVEYOR_STACK),
	machine("ConveyorBeltLeftTier2", "Conveyor Belt Left Tier 2", CONVEYOR_STACK),
	machine("ConveyorBeltRightTier2", "Conveyor Belt Right Tier 2", CONVEYOR_STACK),
	machine("ConveyorRamp", "Conveyor Ramp", CONVEYOR_STACK),
	machine("ConveyorRampDown", "Conveyor Ramp Down", CONVEYOR_STACK),
	machine("ConveyorRampTier2", "Conveyor Ramp Tier 2", CONVEYOR_STACK),
	machine("ConveyorRampDownTier2", "Conveyor Ramp Down Tier 2", CONVEYOR_STACK),
	machine("ConveyorSensor", "Conveyor Sensor", CONVEYOR_STACK),
	machine("FilterConveyor", "Filter Conveyor"),
	machine("SplitConveyor", "Split Conveyor"),
	machine("Merger", "Merger"),
	machine("Randomizer", "Randomizer"),
	machine("WoodTube", "Wood Tube", CONVEYOR_STACK),
	machine("WoodTubeCorner", "Wood Tube Corner", CONVEYOR_STACK),
	machine("WoodTubeAscend", "Wood Tube Ascend", CONVEYOR_STACK),
	machine("WoodTubeDescend", "Wood Tube Descend", CONVEYOR_STACK),
	machine("WoodTubeVertical", "Wood Tube Vertical", CONVEYOR_STACK),
	machine("WoodTubeMerger", "Wood Tube Merger", CONVEYOR_STACK),

	machine("Drill", "Drill"),
	machine("Pumpjack", "Pumpjack"),
	machine("IndustrialLumbermill", "Industrial Lumbermill"),
	machine("IndustrialSawmill", "Industrial Sawmill"),
	machine("IndustrialStonecutter", "Industrial Stonecutter"),
	machine("IndustrialSmelter", "Industrial Smelter"),
	machine("IndustrialPolishingStation", "Industrial Polishing Station"),
	machine("IndustrialWashingStation", "Industrial Washing Station"),
	machine("IndustrialOven", "Industrial Oven"),
	machine("IndustrialMilker", "Industrial Milker"),
	machine("IndustrialBerryBasket", "Industrial Berry Basket"),
	machine("IndustrialFlowerPicker", "Industrial Flower Picker"),
	machine("IndustrialTruffleBarrel", "Industrial Truffle Barrel"),
	machine("IndustrialMerchantTeleseller", "Industrial Merchant Teleseller"),
	machine("CopperPress", "Copper Press"),
	machine("SteelPress", "Steel Press"),
	machine("SteelMill", "Steel Mill"),
	machine("RedBronzeRefinery", "Red Bronze Refinery"),
	machine("OilRefinery", "Oil Refinery"),
	machine("PetroleumPetrifier", "Petroleum Petrifier"),
	machine("FuelBarrelFiller", "Fuel Barrel Filler"),
	machine("FuelBarrelExtractor", "Fuel Barrel Extractor"),
	machine("FoodProcessor", "Food Processor"),
	machine("CratePacker", "Crate Packer"),
	machine("CratePackerTier2", "Crate Packer Tier 2"),
	machine("PalletPacker", "Pallet Packer"),
	machine("SapBoiler", "Sap Boiler"),
	machine("SyrupBottler", "Syrup Bottler"),
	machine("SaplingAutomaticPlanter", "Sapling Automatic Planter"),
	machine("TreeFruitShaker", "Tree Fruit Shaker"),
	machine("AutomatedTrough", "Automated Trough"),
	machine("WoolVacuum", "Wool Vacuum"),
}

return ITEMS
