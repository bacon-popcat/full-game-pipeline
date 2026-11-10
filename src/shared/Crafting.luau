--!strict
-- Crafting: the crafting tiers and recipes, as data, in the order the Crafting window (opened from
-- the side Crafting button, anywhere) lists them. Crafting is the only way to get a machine,
-- conveyor or router: no shop sells them. A craft trades a recipe's inputs from the player's
-- inventory for its output at once (CraftingService); the window predicts with the same rules
-- (`blocker`) and the server checks them again.
--
-- Gates, all checked by `blocker`:
--   * `tier`: the player's crafting tier (saved per garden, CraftingService). Upgrading is a recipe
--     of its own (`upgrade`), made in the window, that spends its inputs and raises the tier by
--     one, from the level the tier names. Ids and the saved field still say "bench", from when
--     crafting needed a placed Crafting Bench.
--   * `research`: a Shared/Research project that must be done first. This table, not Research,
--     says which project unlocks which recipe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Research = require(ReplicatedStorage.Shared.Research)

export type Recipe = {
	id: string,
	-- What one craft makes, and how many. An upgrade shows its output (the tier's `icon`) but makes none.
	output: string,
	count: number,
	inputs: { [string]: number },
	-- The crafting tier it needs.
	tier: number,
	-- The research project that unlocks it; nil when the tier alone does.
	research: string?,
	-- Upgrades only: the tier it raises crafting to, and the name the window shows for it.
	upgrade: number?,
	name: string?,
}

export type Tier = {
	-- What this tier is called.
	name: string,
	-- The item that stands for the tier, as its upgrade recipe's output.
	icon: string,
	-- The level the upgrade to it needs (tier 1 is where every garden starts).
	level: number,
	-- What the upgrade to it costs.
	inputs: { [string]: number },
	description: string,
}

local Crafting = {}

-- Most times one request may craft a recipe.
Crafting.MAX_TIMES = 10

Crafting.TIERS = {
	{
		name = "Hand Crafting",
		level = 1,
		inputs = {},
		description = "Saws planks and builds the first machines: belts, the Smelter, bins and chests.",
		icon = "WoodPlanks",
	},
	{
		name = "Workshop",
		level = 3,
		inputs = { WoodPlanks = 40, Stone = 30, IronBar = 8 },
		description = "Adds the Assembler, Seed Planter, Sprinkler, mills, presses, belt routers and the Auto Collector.",
		icon = "Workbench",
	},
	{
		name = "Machine Works",
		level = 6,
		inputs = { TimberFrame = 8, IronBar = 20, CopperBar = 12, Gear = 10 },
		description = "Adds the Harvester, Oven, Crate Packer, Rock Drill, Auto Crafter and fast conveyors.",
		icon = "Harvester",
	},
	{
		name = "Fabricator",
		level = 9,
		inputs = { SteelFrame = 8, Circuit = 6, Gear = 12, CopperWire = 10 },
		description = "Builds the Mk II machines out of the ones you have.",
		icon = "SteelFrame",
	},
} :: { Tier }

local function define(id: string, count: number, inputs: { [string]: number }, tier: number, research: string?): Recipe
	return { id = id, output = id, count = count, inputs = inputs, tier = tier, research = research }
end

local RECIPES: { Recipe } = {
	-- Tier 1: Hand Crafting. Wood from the forest, stone and ore from the quarry.
	define("WoodPlanks", 4, { Wood = 1 }, 1),
	define("TimberFrame", 1, { WoodPlanks = 4, IronBar = 1 }, 1),
	define("Smelter", 1, { Stone = 16, WoodPlanks = 4 }, 1),
	define("ShippingBin", 1, { WoodPlanks = 10 }, 1),
	define("Chest", 1, { WoodPlanks = 8 }, 1),
	define("ConveyorBelt", 4, { WoodPlanks = 3, IronBar = 1 }, 1),
	define("ConveyorBeltLeft", 4, { WoodPlanks = 3, IronBar = 1 }, 1),
	define("ConveyorBeltRight", 4, { WoodPlanks = 3, IronBar = 1 }, 1),
	define("ConveyorRamp", 2, { WoodPlanks = 4, IronBar = 1 }, 1, "WoodenBelts"),
	define("ConveyorRampDown", 2, { WoodPlanks = 4, IronBar = 1 }, 1, "WoodenBelts"),
	define("Gear", 1, { IronBar = 2 }, 1, "HandTools"),

	-- Tier 2: Workshop. Gears come from the Assembler (or by hand with Hand-Cut Gears).
	define("Workbench", 1, { TimberFrame = 2, IronBar = 6, CopperBar = 2 }, 2),
	define("SeedPlanter", 1, { TimberFrame = 2, Gear = 3, IronBar = 2 }, 2),
	define("Sprinkler", 1, { CopperBar = 4, IronBar = 2, Gear = 1 }, 2),
	define("Mill", 1, { Stone = 20, TimberFrame = 2, Gear = 2 }, 2),
	define("Juicer", 1, { IronBar = 6, Gear = 2, Glass = 4 }, 2),
	define("SplitConveyor", 1, { ConveyorBelt = 2, Gear = 1, IronBar = 1 }, 2),
	define("Merger", 1, { ConveyorBelt = 2, Gear = 1, IronBar = 1 }, 2),
	define("Randomizer", 1, { ConveyorBelt = 2, Gear = 2 }, 2),
	define("StorageChest", 1, { Chest = 1, ConveyorBelt = 2, Gear = 2, CopperWire = 2 }, 2, "Carpentry"),
	define("FilterConveyor", 1, { ConveyorBelt = 2, Gear = 1, CopperWire = 2 }, 2),
	define("ConveyorSensor", 2, { ConveyorBelt = 2, CopperWire = 2, Glass = 1 }, 2),

	-- Tier 3: Machine Works. Circuits and steel frames come from the Assembler.
	define("Harvester", 1, { TimberFrame = 4, Gear = 4, Circuit = 2 }, 3),
	define("Oven", 1, { Bricks = 20, IronBar = 6, CopperBar = 2 }, 3),
	define("CratePacker", 1, { TimberFrame = 4, Gear = 4, IronBar = 4 }, 3, "CrateMaking"),
	define("AutoCrafter", 1, { Workbench = 1, TimberFrame = 2, Circuit = 2, Gear = 4 }, 3),
	define("RockDrill", 1, { SteelFrame = 2, Gear = 4, CopperWire = 4 }, 3),
	define("ConveyorBeltTier2", 4, { ConveyorBelt = 4, Gear = 2 }, 3),
	define("ConveyorBeltLeftTier2", 4, { ConveyorBeltLeft = 4, Gear = 2 }, 3),
	define("ConveyorBeltRightTier2", 4, { ConveyorBeltRight = 4, Gear = 2 }, 3),
	define("ConveyorRampTier2", 2, { ConveyorRamp = 2, Gear = 1 }, 3),
	define("ConveyorRampDownTier2", 2, { ConveyorRampDown = 2, Gear = 1 }, 3),

	-- Tier 4: Fabricator. Each Mk II is built on the machine it replaces.
	define("SeedPlanterTier2", 1, { SeedPlanter = 1, SteelFrame = 3, Gear = 6 }, 4, "PlanterPlans"),
	define("SprinklerTier2", 1, { Sprinkler = 1, Circuit = 4, CopperWire = 6 }, 4, "SprinklerPlans"),
	define("MillTier2", 1, { Mill = 1, SteelFrame = 2, Gear = 8 }, 4),
	define("HarvesterTier2", 1, { Harvester = 1, SteelFrame = 3, Circuit = 6 }, 4, "HarvesterPlans"),
}

-- One upgrade recipe per tier past the first, listed first so the window shows the next one on top.
local upgrades: { Recipe } = {}
for tier = 2, #Crafting.TIERS do
	local each = Crafting.TIERS[tier]
	table.insert(upgrades, {
		id = `BenchTier{tier}`,
		output = each.icon,
		count = 0,
		inputs = each.inputs,
		tier = tier - 1,
		upgrade = tier,
		name = `Upgrade to {each.name}`,
	})
end
table.move(RECIPES, 1, #RECIPES, #upgrades + 1, upgrades)
Crafting.RECIPES = upgrades

local byId: { [string]: Recipe } = {}
for _, each in Crafting.RECIPES do
	assert(not byId[each.id], `Crafting: recipe "{each.id}" is listed twice`)
	assert(Inventory.find(each.output), `Crafting: "{each.id}" makes unknown item "{each.output}"`)
	assert(Crafting.TIERS[each.tier], `Crafting: "{each.id}" needs unknown crafting tier {each.tier}`)
	for itemId in each.inputs do
		assert(Inventory.find(itemId), `Crafting: "{each.id}" needs unknown item "{itemId}"`)
	end
	assert(
		each.research == nil or Research.get(each.research),
		`Crafting: "{each.id}" is unlocked by unknown research "{each.research}"`
	)
	byId[each.id] = each
end

function Crafting.get(id: string): Recipe?
	return byId[id]
end

-- What a recipe is called in the window: its own name, or its output's.
function Crafting.nameOf(recipe: Recipe): string
	return recipe.name or Inventory.getItem(recipe.output).name
end

-- A saved or replicated tier, made whole and in range.
function Crafting.sanitizeTier(value: unknown): number
	if typeof(value) ~= "number" or value ~= value then
		return 1
	end
	return math.clamp(math.floor(value), 1, #Crafting.TIERS)
end

-- The recipes a research project unlocks, for its description in the Research window.
function Crafting.unlockedBy(researchId: string): { Recipe }
	local found = {}
	for _, each in Crafting.RECIPES do
		if each.research == researchId then
			table.insert(found, each)
		end
	end
	return found
end

-- Whether research or the crafting tier still keeps it from being crafted at all (not the inputs).
function Crafting.locked(recipe: Recipe, done: { [string]: boolean }, tier: number): boolean
	return (recipe.research ~= nil and not done[recipe.research]) or tier < recipe.tier
end

-- Why `times` crafts of `recipe` can't happen now, or nil when they can: it's locked by research,
-- the crafting `tier` or the player's `level`, or the inventory (`count(itemId)`) is short of an
-- input. Room for the output is the server's to judge, since the inputs it frees count.
function Crafting.blocker(
	recipe: Recipe,
	times: number,
	done: { [string]: boolean },
	count: (string) -> number,
	tier: number,
	level: number
): string?
	if recipe.upgrade then
		local target = Crafting.TIERS[recipe.upgrade]
		if tier >= recipe.upgrade then
			return `Crafting is already at {Crafting.TIERS[tier].name}`
		elseif tier < recipe.tier then
			return `Upgrade to {Crafting.TIERS[recipe.tier].name} first`
		elseif level < target.level then
			return `Reach level {target.level} first`
		elseif times ~= 1 then
			return "Upgrade one tier at a time"
		end
	elseif tier < recipe.tier then
		return `Upgrade crafting to {Crafting.TIERS[recipe.tier].name} first`
	end
	if recipe.research and not done[recipe.research] then
		local project = Research.get(recipe.research)
		return `Research {if project then project.name else recipe.research} first`
	end
	for itemId, need in recipe.inputs do
		if count(itemId) < need * times then
			return `Needs {need * times} {Inventory.getItem(itemId).name}`
		end
	end
	return nil
end

return Crafting
