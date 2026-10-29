--!strict
-- Items: every item that can sit in an inventory, in catalogue order. Authored content
-- only; who holds what lives in InventoryService, what a machine does with an item lives
-- in Shared/Factory/Blocks. Blocks and machines are placed on the build grid, tools are
-- held and swung, resources are what the world and the machines produce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Products = require(ReplicatedStorage.Shared.Factory.Products)
local World = require(ReplicatedStorage.Shared.World)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)

export type Kind = "Tool" | "Block" | "Machine" | "Resource"

export type Item = {
	id: string,
	name: string,
	kind: Kind,
	-- Most of this item one slot can hold.
	stack: number,
	description: string?,
	value: number?,
	base: string?,
	mutation: string?,
	-- The template its art borrows (Assets.Blocks for placeables, Assets.Items for resources)
	-- when it has none of its own, tinted `color` when given. ItemArt resolves it.
	art: string?,
	color: Color3?,
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

-- Seeds are blocks only so the hand places them with a ghost; a placed seed becomes a crop at once
-- (WorldService), so it never sits on the grid to be broken.
local function seed(id: string, name: string, description: string): Item
	return { id = id, name = name, kind = "Block", stack = BLOCK_STACK, description = description }
end

local function machine(id: string, name: string, description: string, stack: number?, art: string?): Item
	return {
		id = id,
		name = name,
		kind = "Machine",
		stack = stack or MACHINE_STACK,
		description = description,
		art = art,
	}
end

local function resource(id: string, name: string, description: string): Item
	return { id = id, name = name, kind = "Resource", stack = RESOURCE_STACK, description = description }
end

local ITEMS: { Item } = {
	tool("Hammer", "Hammer", "Swing at a block you placed to pick it back up, contents and all.", true),
	tool("Pickaxe", "Pickaxe", "Mines rocks, and breaks stone, glass and earth blocks you placed."),
	tool(
		"WateringCan",
		"Watering Can",
		"Splash a growing crop on your plot to take a fifth off what's left of its stage."
	),

	block("Grass", "Grass", "Soft ground with a green top.", "Pickaxe"),
	block("Dirt", "Dirt", "Plain earth.", "Pickaxe"),
	block("Stone", "Stone", "Solid grey rock to build with.", "Pickaxe"),
	block("WoodPlanks", "Wood Planks", "Wooden boards for floors and walls.", "Pickaxe"),
	block("Bricks", "Bricks", "Fired clay, stacked tight.", "Pickaxe"),
	block("Glass", "Glass", "See-through and surprisingly sturdy.", "Pickaxe"),

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

	machine("IndustrialSmelter", "Industrial Smelter", "Smelts iron and copper ore into bars. Runs on coal."),
	machine(
		"SeedPlanter",
		"Seed Planter",
		"Plants the seeds in its hopper into empty soil, 3 wide and 5 deep, in front of it.",
		nil,
		"SaplingAutomaticPlanter"
	),
	machine("Sprinkler", "Sprinkler", "Crops within 3 cells grow a quarter faster, and sometimes come out Wet."),
	machine(
		"Harvester",
		"Harvester",
		"Harvests ripe crops within 4 cells onto its output belt, and replants the ones that need it.",
		nil,
		"IndustrialFlowerPicker"
	),
	machine("Mill", "Mill", "Grinds 2 wheat into flour.", nil, "IndustrialSawmill"),
	machine(
		"Juicer",
		"Juicer",
		"Presses 3 strawberries, blueberries, grapes, apples or tomatoes into juice.",
		nil,
		"FoodProcessor"
	),
	machine("Oven", "Oven", "Bakes flour and 2 strawberries, blueberries or apples into a pie.", nil, "IndustrialOven"),
	machine("CratePacker", "Crate Packer", "Packs 10 of any crop into its crate, worth more than the crops alone."),
	machine(
		"ShippingBin",
		"Shipping Bin",
		"Sells whatever a belt brings it, one a second, and pays you for it.",
		nil,
		"IndustrialMerchantTeleseller"
	),
	machine(
		"StorageChest",
		"Storage Chest",
		"Collects whatever a conveyor brings it, 12 slots of it. Open it to take the items out.",
		nil,
		"IndustrialChest"
	),

	resource("Coal", "Coal", "Fuel for the Industrial Smelter."),
	resource("IronOre", "Iron Ore", "Smelt it into an iron bar."),
	resource("CopperOre", "Copper Ore", "Smelt it into a copper bar."),
	resource("IronBar", "Iron Bar", "Smelted iron for future crafting."),
	resource("CopperBar", "Copper Bar", "Smelted copper for future crafting."),
}

local cropIds: { string } = {}
for cropId in World.CROPS do
	table.insert(cropIds, cropId)
end
table.sort(cropIds)
local mutationNames: { string } = {}
for name in Mutations.ALL do
	table.insert(mutationNames, name)
end
table.sort(mutationNames)
for _, cropId in cropIds do
	local crop = World.CROPS[cropId]
	table.insert(ITEMS, seed(crop.seed, crop.name .. " Seeds", "Plant on grass, dirt or farmland."))
	local produce = resource(crop.produce, crop.name, "Harvested from your garden.")
	produce.value = crop.value
	table.insert(ITEMS, produce)
	for _, name in mutationNames do
		local mutation = Mutations.ALL[name]
		local variant = resource(crop.produce .. "+" .. name, name .. " " .. crop.name, "A mutated garden harvest.")
		variant.base = crop.produce
		variant.mutation = name
		variant.value = crop.value * mutation.multiplier
		table.insert(ITEMS, variant)
	end
end
for _, product in Products do
	local item = resource(product.id, product.name, product.description)
	item.value = product.value
	item.art = product.art
	item.color = product.color
	table.insert(ITEMS, item)
end

return ITEMS
