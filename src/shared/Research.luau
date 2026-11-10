--!strict
-- Research: owns the project catalogue, additive effects and shared eligibility and timing
-- rules. Costs are paid by the server; crafting recipes (Shared/Crafting) name the project
-- that unlocks them, so a crafting project here has no effects of its own.
--
-- Each category is one upgrade tree: a single root project (no needs) and every other project
-- needing one in its own category first, so the Research window can draw it as branches. Only
-- Master reaches across trees, for its extra needs. A project's timer running out does not
-- finish it: the player completes it (Research.isReady), which is when its bonus applies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage.Shared.Inventory)

export type Stat =
	"beltSpeed"
	| "machineSpeed"
	| "harvesterSpeed"
	| "sprinklerRadius"
	| "cropYield"
	| "growSpeed"
	| "mutationChance"
	| "sellPrice"
	| "xpGain"
	| "seedStock"
	| "researchSpeed"
	| "chopYield"
	| "mineYield"
export type Category = "Farming" | "Automation" | "Economy" | "Tools" | "Crafting"
export type Project = {
	id: string,
	name: string,
	description: string,
	category: Category,
	level: number,
	coins: number,
	items: { [string]: number },
	seconds: number,
	needs: { string },
	effects: { [Stat]: number },
}
export type Active = { id: string, startedAt: number, seconds: number }
export type Saved = { done: { [string]: boolean }, active: Active? }
export type Snapshot = {
	done: { string },
	active: { id: string, endsAt: number, seconds: number }?,
	bonuses: { [Stat]: number },
}

local STATS: { [Stat]: string } = {
	beltSpeed = "Belt speed",
	machineSpeed = "Machine speed",
	harvesterSpeed = "Harvester and planter speed",
	sprinklerRadius = "Sprinkler reach",
	cropYield = "Harvest yield",
	growSpeed = "Crop growth",
	mutationChance = "Mutation chance",
	sellPrice = "Sale price",
	xpGain = "XP gain",
	seedStock = "Seed stock",
	researchSpeed = "Research speed",
	chopYield = "Wood yield",
	mineYield = "Mining yield",
}

local PROJECTS: { Project } = {
	{
		id = "Learn1",
		name = "Quick Learner I",
		description = "You earn 10% more XP.",
		category = "Economy",
		level = 2,
		coins = 150,
		items = {},
		seconds = 30,
		needs = {},
		effects = { xpGain = 0.1 },
	},
	{
		id = "Belts1",
		name = "Faster Belts I",
		description = "Belts on your plot run 10% faster.",
		category = "Automation",
		level = 3,
		coins = 300,
		items = {},
		seconds = 60,
		needs = {},
		effects = { beltSpeed = 0.1 },
	},
	{
		id = "Axe1",
		name = "Sharp Axe I",
		description = "Each tree you chop gives 1 extra Wood.",
		category = "Tools",
		level = 3,
		coins = 200,
		items = { Wood = 5 },
		seconds = 60,
		needs = {},
		effects = { chopYield = 1 },
	},
	{
		id = "CrateMaking",
		name = "Crate Making",
		description = "Unlocks the Crate Packer recipe at Machine Works.",
		category = "Crafting",
		level = 3,
		coins = 250,
		items = { Wood = 5 },
		seconds = 45,
		needs = {},
		effects = {},
	},
	{
		id = "Yield1",
		name = "Rich Soil I",
		description = "Harvests on your plot give 10% more produce on average.",
		category = "Farming",
		level = 4,
		coins = 600,
		items = { Wheat = 20 },
		seconds = 120,
		needs = {},
		effects = { cropYield = 0.1 },
	},
	{
		id = "Carpentry",
		name = "Carpentry",
		description = "Unlocks the Auto Collector recipe.",
		category = "Crafting",
		level = 4,
		coins = 400,
		items = { Wood = 10 },
		seconds = 60,
		needs = { "CrateMaking" },
		effects = {},
	},
	{
		id = "Haggle1",
		name = "Haggling I",
		description = "Your sales earn 5% more coins.",
		category = "Economy",
		level = 5,
		coins = 1000,
		items = {},
		seconds = 120,
		needs = { "Learn1" },
		effects = { sellPrice = 0.05 },
	},
	{
		id = "Pick1",
		name = "Strong Pickaxe I",
		description = "Each quarry rock you mine gives 1 extra of its main resource.",
		category = "Tools",
		level = 5,
		coins = 800,
		items = {},
		seconds = 120,
		needs = { "Axe1" },
		effects = { mineYield = 1 },
	},
	{
		id = "Growth1",
		name = "Green Thumb I",
		description = "Crops on your plot grow 5% faster while you play.",
		category = "Farming",
		level = 6,
		coins = 1500,
		items = {},
		seconds = 180,
		needs = { "Yield1" },
		effects = { growSpeed = 0.05 },
	},
	{
		id = "WoodenBelts",
		name = "Conveyor Ramps",
		description = "Unlocks the Conveyor Ramp recipes.",
		category = "Crafting",
		level = 6,
		coins = 1200,
		items = { WoodPlanks = 20 },
		seconds = 180,
		needs = { "Carpentry" },
		effects = {},
	},
	{
		id = "Reapers1",
		name = "Swift Reapers I",
		description = "Harvesters and Seed Planters on your plot work 15% faster.",
		category = "Automation",
		level = 7,
		coins = 2000,
		items = {},
		seconds = 240,
		needs = { "Belts1" },
		effects = { harvesterSpeed = 0.15 },
	},
	{
		id = "Belts2",
		name = "Faster Belts II",
		description = "Belts on your plot run 10% faster.",
		category = "Automation",
		level = 8,
		coins = 2500,
		items = {},
		seconds = 300,
		needs = { "Belts1" },
		effects = { beltSpeed = 0.1 },
	},
	{
		id = "Seeds1",
		name = "Seed Contacts I",
		description = "Each seed that restocks gets 1 extra in stock.",
		category = "Economy",
		level = 8,
		coins = 3000,
		items = {},
		seconds = 300,
		needs = { "Learn1" },
		effects = { seedStock = 1 },
	},
	{
		id = "HandTools",
		name = "Hand-Cut Gears",
		description = "Unlocks cutting Gears by hand.",
		category = "Crafting",
		level = 8,
		coins = 2500,
		items = {},
		seconds = 240,
		needs = { "Carpentry" },
		effects = {},
	},
	{
		id = "Machines1",
		name = "Quick Machines I",
		description = "Processors, Assemblers and Smelters on your plot work 10% faster.",
		category = "Automation",
		level = 9,
		coins = 3000,
		items = {},
		seconds = 300,
		needs = { "Belts1" },
		effects = { machineSpeed = 0.1 },
	},
	{
		id = "SprinklerPlans",
		name = "Sprinkler Mk II Plans",
		description = "Unlocks the Sprinkler Mk II recipe at Fabricator.",
		category = "Crafting",
		level = 9,
		coins = 4000,
		items = { TimberFrame = 4 },
		seconds = 480,
		needs = { "Carpentry" },
		effects = {},
	},
	{
		id = "Yield2",
		name = "Rich Soil II",
		description = "Harvests on your plot give 10% more produce on average.",
		category = "Farming",
		level = 10,
		coins = 4000,
		items = {},
		seconds = 480,
		needs = { "Yield1" },
		effects = { cropYield = 0.1 },
	},
	{
		id = "Study1",
		name = "Efficient Study I",
		description = "New research projects progress 15% faster.",
		category = "Economy",
		level = 10,
		coins = 5000,
		items = {},
		seconds = 360,
		needs = { "Learn1" },
		effects = { researchSpeed = 0.15 },
	},
	{
		id = "Luck1",
		name = "Lucky Harvest I",
		description = "Crops on your plot have a 20% greater chance of each mutation.",
		category = "Farming",
		level = 11,
		coins = 6000,
		items = {},
		seconds = 480,
		needs = { "Yield1" },
		effects = { mutationChance = 0.2 },
	},
	{
		id = "Sprinklers1",
		name = "Wide Sprinklers I",
		description = "Sprinklers on your plot reach 1 cell farther.",
		category = "Automation",
		level = 12,
		coins = 8000,
		items = { CopperWire = 4 },
		seconds = 600,
		needs = { "Belts1" },
		effects = { sprinklerRadius = 1 },
	},
	{
		id = "PlanterPlans",
		name = "Planter Mk II Plans",
		description = "Unlocks the Seed Planter Mk II recipe at Fabricator.",
		category = "Crafting",
		level = 12,
		coins = 8000,
		items = {},
		seconds = 600,
		needs = { "WoodenBelts" },
		effects = {},
	},
	{
		id = "RoasterPlans",
		name = "Roaster Plans",
		description = "Unlocks the Roaster recipe at Machine Works.",
		category = "Crafting",
		level = 13,
		coins = 9000,
		items = { Potato = 10 },
		seconds = 600,
		needs = { "CrateMaking" },
		effects = {},
	},
	{
		id = "Haggle2",
		name = "Haggling II",
		description = "Your sales earn 5% more coins.",
		category = "Economy",
		level = 13,
		coins = 8000,
		items = {},
		seconds = 600,
		needs = { "Haggle1" },
		effects = { sellPrice = 0.05 },
	},
	{
		id = "Growth2",
		name = "Green Thumb II",
		description = "Crops on your plot grow 5% faster while you play.",
		category = "Farming",
		level = 14,
		coins = 10000,
		items = {},
		seconds = 600,
		needs = { "Growth1" },
		effects = { growSpeed = 0.05 },
	},
	{
		id = "Learn2",
		name = "Quick Learner II",
		description = "You earn 10% more XP.",
		category = "Economy",
		level = 15,
		coins = 12000,
		items = {},
		seconds = 720,
		needs = { "Learn1" },
		effects = { xpGain = 0.1 },
	},
	{
		id = "Axe2",
		name = "Sharp Axe II",
		description = "Each tree you chop gives 1 extra Wood.",
		category = "Tools",
		level = 15,
		coins = 10000,
		items = { WoodPlanks = 20 },
		seconds = 600,
		needs = { "Axe1" },
		effects = { chopYield = 1 },
	},
	{
		id = "Belts3",
		name = "Faster Belts III",
		description = "Belts on your plot run 10% faster.",
		category = "Automation",
		level = 16,
		coins = 15000,
		items = { Gear = 10 },
		seconds = 900,
		needs = { "Belts2" },
		effects = { beltSpeed = 0.1 },
	},
	{
		id = "HarvesterPlans",
		name = "Harvester Mk II Plans",
		description = "Unlocks the Harvester Mk II recipe at Fabricator.",
		category = "Crafting",
		level = 17,
		coins = 18000,
		items = { Circuit = 2 },
		seconds = 900,
		needs = { "PlanterPlans" },
		effects = {},
	},
	{
		id = "KettlePlans",
		name = "Kettle Plans",
		description = "Unlocks the Preserving Kettle recipe at Machine Works.",
		category = "Crafting",
		level = 18,
		coins = 22000,
		items = { Tomato = 20 },
		seconds = 900,
		needs = { "RoasterPlans" },
		effects = {},
	},
	{
		id = "Yield3",
		name = "Rich Soil III",
		description = "Harvests on your plot give 10% more produce on average.",
		category = "Farming",
		level = 18,
		coins = 25000,
		items = { Corn = 10 },
		seconds = 1200,
		needs = { "Yield2" },
		effects = { cropYield = 0.1 },
	},
	{
		id = "Reapers2",
		name = "Swift Reapers II",
		description = "Harvesters and Seed Planters on your plot work 15% faster.",
		category = "Automation",
		level = 18,
		coins = 20000,
		items = {},
		seconds = 900,
		needs = { "Reapers1" },
		effects = { harvesterSpeed = 0.15 },
	},
	{
		id = "Pick2",
		name = "Strong Pickaxe II",
		description = "Each quarry rock you mine gives 1 extra of its main resource.",
		category = "Tools",
		level = 19,
		coins = 15000,
		items = { IronBar = 6 },
		seconds = 720,
		needs = { "Pick1" },
		effects = { mineYield = 1 },
	},
	{
		id = "Machines2",
		name = "Quick Machines II",
		description = "Processors, Assemblers and Smelters on your plot work 10% faster.",
		category = "Automation",
		level = 20,
		coins = 25000,
		items = { Gear = 6 },
		seconds = 1200,
		needs = { "Machines1" },
		effects = { machineSpeed = 0.1 },
	},
	{
		id = "RecipeBook1",
		name = "Recipe Book I",
		description = "Your Baking Ovens can bake Pizza and Pumpkin Pie.",
		category = "Crafting",
		level = 22,
		coins = 40000,
		items = { Flour = 10 },
		seconds = 1500,
		needs = { "KettlePlans" },
		effects = {},
	},
	{
		id = "Haggle3",
		name = "Haggling III",
		description = "Your sales earn 5% more coins.",
		category = "Economy",
		level = 22,
		coins = 40000,
		items = {},
		seconds = 1500,
		needs = { "Haggle2" },
		effects = { sellPrice = 0.05 },
	},
	{
		id = "Seeds2",
		name = "Seed Contacts II",
		description = "Each seed that restocks gets 1 extra in stock.",
		category = "Economy",
		level = 23,
		coins = 45000,
		items = {},
		seconds = 1500,
		needs = { "Seeds1" },
		effects = { seedStock = 1 },
	},
	{
		id = "Growth3",
		name = "Green Thumb III",
		description = "Crops on your plot grow 5% faster while you play.",
		category = "Farming",
		level = 24,
		coins = 50000,
		items = { Blueberry = 20 },
		seconds = 1800,
		needs = { "Growth2" },
		effects = { growSpeed = 0.05 },
	},
	{
		id = "Luck2",
		name = "Lucky Harvest II",
		description = "Crops on your plot have a 20% greater chance of each mutation.",
		category = "Farming",
		level = 25,
		coins = 60000,
		items = { Apple = 10 },
		seconds = 2100,
		needs = { "Luck1" },
		effects = { mutationChance = 0.2 },
	},
	{
		id = "RecipeBook2",
		name = "Recipe Book II",
		description = "Your Baking Ovens can bake Jam Tarts.",
		category = "Crafting",
		level = 26,
		coins = 70000,
		items = { StrawberryJam = 5 },
		seconds = 2400,
		needs = { "RecipeBook1" },
		effects = {},
	},
	{
		id = "Belts4",
		name = "Faster Belts IV",
		description = "Belts on your plot run 10% faster.",
		category = "Automation",
		level = 26,
		coins = 70000,
		items = {},
		seconds = 2400,
		needs = { "Belts3" },
		effects = { beltSpeed = 0.1 },
	},
	{
		id = "Study2",
		name = "Efficient Study II",
		description = "New research projects progress 15% faster.",
		category = "Economy",
		level = 27,
		coins = 75000,
		items = {},
		seconds = 1800,
		needs = { "Study1" },
		effects = { researchSpeed = 0.15 },
	},
	{
		id = "Yield4",
		name = "Rich Soil IV",
		description = "Harvests on your plot give 10% more produce on average.",
		category = "Farming",
		level = 28,
		coins = 100000,
		items = {},
		seconds = 2700,
		needs = { "Yield3" },
		effects = { cropYield = 0.1 },
	},
	{
		id = "Sprinklers2",
		name = "Wide Sprinklers II",
		description = "Sprinklers on your plot reach 1 cell farther.",
		category = "Automation",
		level = 28,
		coins = 80000,
		items = { Circuit = 4 },
		seconds = 2400,
		needs = { "Sprinklers1" },
		effects = { sprinklerRadius = 1 },
	},
	{
		id = "ChillerPlans",
		name = "Chiller Plans",
		description = "Unlocks the Chiller recipe at Fabricator.",
		category = "Crafting",
		level = 30,
		coins = 100000,
		items = { Circuit = 4 },
		seconds = 2700,
		needs = { "RecipeBook2" },
		effects = {},
	},
	{
		id = "Reapers3",
		name = "Swift Reapers III",
		description = "Harvesters and Seed Planters on your plot work 15% faster.",
		category = "Automation",
		level = 30,
		coins = 100000,
		items = { Circuit = 4 },
		seconds = 2700,
		needs = { "Reapers2" },
		effects = { harvesterSpeed = 0.15 },
	},
	{
		id = "Learn3",
		name = "Quick Learner III",
		description = "You earn 10% more XP.",
		category = "Economy",
		level = 32,
		coins = 120000,
		items = {},
		seconds = 2700,
		needs = { "Learn2" },
		effects = { xpGain = 0.1 },
	},
	{
		id = "Machines3",
		name = "Quick Machines III",
		description = "Processors, Assemblers and Smelters on your plot work 10% faster.",
		category = "Automation",
		level = 34,
		coins = 150000,
		items = { Circuit = 6, SteelFrame = 4 },
		seconds = 3600,
		needs = { "Machines2" },
		effects = { machineSpeed = 0.1 },
	},
	{
		id = "ProcessorPlans",
		name = "Heavy Processor Plans",
		description = "Unlocks the Fruit Press Mk II and Baking Oven Mk II recipes at Fabricator.",
		category = "Crafting",
		level = 35,
		coins = 175000,
		items = { Circuit = 6, SteelFrame = 4 },
		seconds = 3600,
		needs = { "ChillerPlans" },
		effects = {},
	},
	{
		id = "Growth4",
		name = "Green Thumb IV",
		description = "Crops on your plot grow 5% faster while you play.",
		category = "Farming",
		level = 36,
		coins = 200000,
		items = {},
		seconds = 3600,
		needs = { "Growth3" },
		effects = { growSpeed = 0.05 },
	},
	{
		id = "Belts5",
		name = "Faster Belts V",
		description = "Belts on your plot run 10% faster.",
		category = "Automation",
		level = 38,
		coins = 250000,
		items = { Circuit = 10 },
		seconds = 5400,
		needs = { "Belts4" },
		effects = { beltSpeed = 0.1 },
	},
	{
		id = "Haggle4",
		name = "Haggling IV",
		description = "Your sales earn 5% more coins.",
		category = "Economy",
		level = 40,
		coins = 300000,
		items = {},
		seconds = 4500,
		needs = { "Haggle3" },
		effects = { sellPrice = 0.05 },
	},
	{
		id = "Yield5",
		name = "Rich Soil V",
		description = "Harvests on your plot give 10% more produce on average.",
		category = "Farming",
		level = 42,
		coins = 400000,
		items = { Pumpkin = 10 },
		seconds = 5400,
		needs = { "Yield4" },
		effects = { cropYield = 0.1 },
	},
	{
		id = "Luck3",
		name = "Lucky Harvest III",
		description = "Crops on your plot have a 20% greater chance of each mutation.",
		category = "Farming",
		level = 44,
		coins = 500000,
		items = {},
		seconds = 5400,
		needs = { "Luck2" },
		effects = { mutationChance = 0.2 },
	},
	{
		id = "Study3",
		name = "Efficient Study III",
		description = "New research projects progress 15% faster.",
		category = "Economy",
		level = 45,
		coins = 600000,
		items = {},
		seconds = 5400,
		needs = { "Study2" },
		effects = { researchSpeed = 0.15 },
	},
	{
		id = "Master",
		name = "Master Gardener",
		description = "Your harvests give 10% more produce on average, crops grow 5% faster while you play, and sales earn 5% more coins.",
		category = "Economy",
		level = 50,
		coins = 1500000,
		items = { Circuit = 20, SteelFrame = 20 },
		seconds = 7200,
		needs = { "Yield5", "Growth4", "Haggle4" },
		effects = { cropYield = 0.1, growSpeed = 0.05, sellPrice = 0.05 },
	},
}

local byId: { [string]: Project } = {}
for _, project in PROJECTS do
	assert(not byId[project.id], `Research: duplicate project "{project.id}"`)
	byId[project.id] = project
	for itemId in project.items do
		assert(Inventory.find(itemId), `Research: unknown item "{itemId}"`)
	end
	for stat in project.effects do
		assert(STATS[stat], `Research: unknown stat "{stat}"`)
	end
end
for _, project in PROJECTS do
	for _, id in project.needs do
		assert(byId[id], `Research: unknown prerequisite "{id}"`)
	end
end

-- Every project but a category's root needs one in its own category, so each tab is one tree.
local roots: { [string]: string } = {}
for _, project in PROJECTS do
	local sameCategory = false
	for _, id in project.needs do
		sameCategory = sameCategory or byId[id].category == project.category
	end
	if not sameCategory then
		assert(not roots[project.category], `Research: "{project.id}" is a second root of {project.category}`)
		roots[project.category] = project.id
	end
end

local Research = { PROJECTS = PROJECTS, STATS = STATS }

function Research.get(id: string): Project?
	return byId[id]
end

function Research.bonuses(done: { [string]: boolean }): { [Stat]: number }
	local stats: { [Stat]: number } = {}
	for stat in STATS do
		stats[stat] = 0
	end
	for _, project in PROJECTS do
		if done[project.id] then
			for stat, amount in project.effects do
				stats[stat] += amount
			end
		end
	end
	return stats
end

function Research.blocker(project: Project, done: { [string]: boolean }, level: number, activeId: string?): string?
	if done[project.id] then
		return "Already researched"
	elseif activeId then
		return "Another project is running"
	elseif level < project.level then
		return `Needs level {project.level}`
	end
	for _, id in project.needs do
		if not done[id] then
			return `Needs {byId[id].name}`
		end
	end
	return nil
end

-- Whether a running project's timer has run out, so it can be completed. `now` and `endsAt`
-- are on the same clock; the server allows completing up to READY_EARLY seconds before, so a
-- press the moment a client's countdown ends is never refused.
Research.READY_EARLY = 0.5
function Research.isReady(endsAt: number, now: number): boolean
	return now >= endsAt
end

function Research.duration(project: Project, researchSpeed: number): number
	return math.max(1, math.round(project.seconds / (1 + researchSpeed)))
end

return Research
