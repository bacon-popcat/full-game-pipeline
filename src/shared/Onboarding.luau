--!strict
-- Onboarding: the ordered goals the Objective panel walks a garden through, and their coin
-- rewards. The saved step names the next goal; #STEPS + 1 means finished, and the panel then
-- shows the next level that opens something (Shared/Unlocks). Only the server completes goals.
-- The first eight teach farming by hand and the first sale (a named `condition` the server
-- observes); the rest lead through crafting and automation to the first Mk II machine, each a
-- `goal` checked against what the garden has (OnboardingService).
-- Appending a step needs no migration: a finished save holds the old #STEPS + 1, which is the
-- first new goal. Inserting one moves saved steps (DataService migrates them, as it did for the
-- order goal at step 23).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)

export type Condition =
	"SeedBought"
	| "Tilled"
	| "Planted"
	| "Harvested"
	| "StandSold"
	| "LevelTwo"
	| "BinBought"
	| "BinPlaced"
-- What a goal asks of the garden:
--   Had: any of `items` was crafted, made by a machine, placed or carried.
--   Placed: `items[1]` stands (or was just placed) on the plot.
--   Tier: crafting is at `tier` or past it.
--   Research: any research project is finished.
--   BinSales: Shipping Bins have sold `count` items.
--   Orders: an order has been filled.
export type Goal = {
	kind: "Had" | "Placed" | "Tier" | "Research" | "BinSales" | "Orders",
	items: { string }?,
	tier: number?,
	count: number?,
}
export type Step = { text: string, reward: number, condition: Condition?, goal: Goal? }
-- `detail` is the goal's progress in words ("12 / 50 sold"), "" when it has none, and nil in a
-- snapshot made from the step alone.
export type Snapshot = { step: number, total: number, text: string, done: boolean, detail: string? }

local function had(...: string): Goal
	return { kind = "Had", items = { ... } }
end

local function placed(item: string): Goal
	return { kind = "Placed", items = { item } }
end

local function tier(value: number): Goal
	return { kind = "Tier", tier = value }
end

local STEPS: { Step } = {
	{ text = "Open the Shop and buy some Carrot Seeds", reward = 10, condition = "SeedBought" },
	{ text = "Hold your Hoe and click the grass in your garden to till Farmland", reward = 10, condition = "Tilled" },
	{ text = "Hold your seeds and click the Farmland to plant them", reward = 10, condition = "Planted" },
	{ text = "Wait for a crop to ripen, then walk up and press F to harvest it", reward = 20, condition = "Harvested" },
	{ text = "Open Sell and sell your harvest for coins", reward = 20, condition = "StandSold" },
	{ text = "Reach level 2", reward = 30, condition = "LevelTwo" },
	{
		text = "Open Crafting and craft a Shipping Bin from 10 Wood Planks",
		reward = 20,
		condition = "BinBought",
	},
	{ text = "Place your Shipping Bin on your plot", reward = 50, condition = "BinPlaced" },
	-- Rewards from here are one to two minutes of income at the stage the balance model reaches
	-- each goal (docs/retention.md § Goal chain).
	{
		text = "Mine Stone at the quarry, then craft a Smelter from 16 Stone and 4 Wood Planks",
		reward = 100,
		goal = had("Smelter"),
	},
	{
		text = "Place the Smelter and load it with Iron Ore and Coal to smelt an Iron Bar",
		reward = 100,
		goal = had("IronBar"),
	},
	{ text = "Reach level 3, then upgrade crafting to Workshop in the Crafting window", reward = 250, goal = tier(2) },
	{ text = "Craft an Assembler and place it in your garden", reward = 250, goal = placed("Workbench") },
	{ text = "Load the Assembler with Iron Bars to make a Gear", reward = 150, goal = had("Gear") },
	{ text = "Craft a Seed Planter to sow your Farmland for you", reward = 300, goal = had("SeedPlanter") },
	{ text = "Open Research, start a project and complete it", reward = 200, goal = { kind = "Research" } },
	{ text = "Craft a Sprinkler to grow the crops round it faster", reward = 250, goal = had("Sprinkler") },
	{ text = "Craft a Rock Drill to dig ore in your own garden", reward = 250, goal = had("RockDrill") },
	{ text = "Reach level 6, then upgrade crafting to Machine Works", reward = 1000, goal = tier(3) },
	{ text = "Craft a Harvester and place it with your crops behind it", reward = 1000, goal = placed("Harvester") },
	{
		text = "Run a belt from the Harvester to a Shipping Bin and sell 50 items",
		reward = 500,
		goal = { kind = "BinSales", count = 50 },
	},
	{ text = "Craft a Grain Mill and feed it Wheat to mill Flour", reward = 750, goal = had("Flour") },
	{
		text = "Craft a Baking Oven and bake a pie from Flour and fruit",
		reward = 1500,
		goal = had("StrawberryPie", "BlueberryPie", "ApplePie"),
	},
	{ text = "Open Quests and deliver an order from the Orders tab", reward = 1000, goal = { kind = "Orders" } },
	{ text = "Reach level 9, then upgrade crafting to Fabricator", reward = 2500, goal = tier(4) },
	{
		text = "Build your first Mk II machine",
		reward = 4000,
		goal = had("SeedPlanterTier2", "SprinklerTier2", "MillTier2", "HarvesterTier2"),
	},
}

for index, step in STEPS do
	assert((step.condition ~= nil) ~= (step.goal ~= nil), `Onboarding: step {index} needs a condition or a goal`)
	local goal = step.goal
	if goal then
		local items: { string } = goal.items or {}
		for _, itemId in items do
			assert(Inventory.find(itemId), `Onboarding: step {index} names unknown item "{itemId}"`)
		end
		assert(
			goal.kind ~= "Tier" or (goal.tier ~= nil and Crafting.TIERS[goal.tier] ~= nil),
			`Onboarding: step {index} names an unknown crafting tier`
		)
	end
end

local Onboarding = { STEPS = STEPS }

function Onboarding.sanitize(value: unknown): number
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 1
	end
	return math.clamp(math.floor(value), 1, #STEPS + 1)
end

function Onboarding.snapshot(step: number, detail: string?): Snapshot
	local objective = STEPS[step]
	return {
		step = step,
		total = #STEPS,
		text = if objective then objective.text else "",
		done = objective == nil,
		detail = detail,
	}
end

return Onboarding
