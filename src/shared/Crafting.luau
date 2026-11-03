--!strict
-- Crafting: the Crafting Bench's recipes, as data, in the order its window lists them. A craft
-- trades a recipe's inputs from the player's inventory for its output at once (CraftingService);
-- the window predicts with the same rules (`blocker`) and the server checks them again. A recipe
-- with `research` stays locked until that project (Shared/Research) is done, so this table, not
-- Research, says which project unlocks which recipe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Research = require(ReplicatedStorage.Shared.Research)

export type Recipe = {
	id: string,
	-- What one craft makes, and how many.
	output: string,
	count: number,
	inputs: { [string]: number },
	-- The research project that unlocks it; nil when every bench knows it.
	research: string?,
}

local Crafting = {}

-- The placeable block whose window crafts.
Crafting.BENCH = "CraftingBench"
-- Most times one request may craft a recipe.
Crafting.MAX_TIMES = 10

local function define(
	id: string,
	output: string,
	count: number,
	inputs: { [string]: number },
	research: string?
): Recipe
	return { id = id, output = output, count = count, inputs = inputs, research = research }
end

Crafting.RECIPES = {
	define("WoodPlanks", "WoodPlanks", 4, { Wood = 1 }),
	define("TimberFrame", "TimberFrame", 1, { WoodPlanks = 4, IronBar = 1 }),
	define("ShippingBin", "ShippingBin", 1, { WoodPlanks = 10 }, "CrateMaking"),
	define("StorageChest", "StorageChest", 1, { WoodPlanks = 12, IronBar = 1 }, "Carpentry"),
	define("ConveyorBelt", "ConveyorBelt", 8, { WoodPlanks = 4, IronBar = 1 }, "WoodenBelts"),
	define("Gear", "Gear", 1, { IronBar = 2 }, "HandTools"),
	define("Sprinkler", "Sprinkler", 1, { TimberFrame = 2, CopperBar = 3 }, "SprinklerPlans"),
	define("SeedPlanter", "SeedPlanter", 1, { TimberFrame = 3, Gear = 2 }, "PlanterPlans"),
	define("Harvester", "Harvester", 1, { TimberFrame = 4, Circuit = 2 }, "HarvesterPlans"),
} :: { Recipe }

local byId: { [string]: Recipe } = {}
for _, each in Crafting.RECIPES do
	assert(not byId[each.id], `Crafting: recipe "{each.id}" is listed twice`)
	assert(Inventory.find(each.output), `Crafting: "{each.id}" makes unknown item "{each.output}"`)
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

-- Why `times` crafts of `recipe` can't happen now, or nil when they can: it's locked, or the
-- inventory (`count(itemId)`) is short of an input. Room for the output is the server's to judge,
-- since the inputs it frees count.
function Crafting.blocker(
	recipe: Recipe,
	times: number,
	done: { [string]: boolean },
	count: (string) -> number
): string?
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
