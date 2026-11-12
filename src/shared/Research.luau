--!strict
-- Research: owns the project catalogue, additive effects and shared eligibility and timing
-- rules. Costs are paid by the server; crafting recipes (Shared/Crafting) name the project
-- that unlocks them, so a crafting project here has no effects of its own.
--
-- Each category is one upgrade tree: a single root project (no needs) and every other project
-- needing one in its own category first, so the Research window can draw it as branches. Only
-- Master reaches across trees, for its extra needs. A project's timer running out does not
-- finish it: the player completes it (Research.isReady), which is when its bonus applies.
--
-- A `ranked` project (each tree's Mastery) is never done: every completion adds a rank, each
-- rank adds its effects again and costs more than the last (Research.price).
--
-- The queue: one project runs (`active`); more can be lined up behind it, paid when lined up.
-- When the running one's timer runs out the next starts (Research.advance) and the finished one
-- waits in `ready` for its Complete. Projects waiting and queued share the line's room
-- (Research.room), so a player who never completes cannot pile them up.

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
	| "offlineShare"
	| "offlineCap"
	| "rewardBonus"
	| "waterPower"
	| "seedSaver"
	| "luckyDrop"
	| "researchQueue"
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
	-- Repeatable: completing it adds a rank instead of finishing it.
	ranked: boolean?,
}
export type Active = { id: string, startedAt: number, seconds: number }
-- A project lined up behind the running one: its duration (fixed when lined up) and the Unix
-- second it was lined up, before which it cannot start.
export type Queued = { id: string, seconds: number, at: number }
export type Saved = {
	done: { [string]: boolean },
	ranks: { [string]: number },
	active: Active?,
	queue: { Queued },
	ready: { string },
}
export type Snapshot = {
	done: { string },
	ranks: { [string]: number },
	active: { id: string, endsAt: number, seconds: number }?,
	queue: { { id: string, seconds: number } },
	ready: { string },
	-- How many projects can wait in the line (queued and ready together).
	room: number,
	bonuses: { [Stat]: number },
}
-- What a project (at a rank, for ranked ones) costs to line up.
export type Price = { coins: number, items: { [string]: number }, seconds: number }

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
	offlineShare = "Offline coin share",
	offlineCap = "Offline minutes",
	rewardBonus = "Quest and order coins",
	waterPower = "Watering can strength",
	seedSaver = "Seed saving chance",
	luckyDrop = "Double drop chance",
	researchQueue = "Research queue",
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
		id = "Water1",
		name = "Deep Watering I",
		description = "Watering a crop takes an extra 5% off what's left of its growing stage.",
		category = "Farming",
		level = 7,
		coins = 2500,
		items = {},
		seconds = 240,
		needs = { "Growth1" },
		effects = { waterPower = 0.05 },
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
		needs = { "Haggle1" },
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
		id = "Lucky1",
		name = "Lucky Swing I",
		description = "Each tree you chop and rock you mine has a 10% chance to give its drops twice.",
		category = "Tools",
		level = 10,
		coins = 4500,
		items = { Wood = 20 },
		seconds = 360,
		needs = { "Axe1" },
		effects = { luckyDrop = 0.1 },
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
		id = "Night1",
		name = "Night Shift I",
		description = "While you're away, your Shipping Bins earn 5% more of their rate, for up to 1 more hour.",
		category = "Economy",
		level = 11,
		coins = 6000,
		items = {},
		seconds = 480,
		needs = { "Haggle1" },
		effects = { offlineShare = 0.05, offlineCap = 60 },
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
		needs = { "Reapers1" },
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
		id = "Contract1",
		name = "Contracts I",
		description = "Daily quests and orders pay 15% more coins.",
		category = "Economy",
		level = 12,
		coins = 7000,
		items = {},
		seconds = 480,
		needs = { "Seeds1" },
		effects = { rewardBonus = 0.15 },
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
		id = "Notebook1",
		name = "Lab Notebook I",
		description = "Line up 1 more research project behind the one running.",
		category = "Economy",
		level = 14,
		coins = 12000,
		items = { WoodPlanks = 20 },
		seconds = 720,
		needs = { "Study1" },
		effects = { researchQueue = 1 },
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
		id = "Saver1",
		name = "Seed Saver I",
		description = "Seeds you plant, by hand or with a Seed Planter, have a 10% chance not to be used up.",
		category = "Farming",
		level = 16,
		coins = 14000,
		items = { Corn = 15 },
		seconds = 900,
		needs = { "Yield2" },
		effects = { seedSaver = 0.1 },
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
		id = "Lucky2",
		name = "Lucky Swing II",
		description = "Each tree you chop and rock you mine has a 10% greater chance to give its drops twice.",
		category = "Tools",
		level = 21,
		coins = 30000,
		items = { IronBar = 4 },
		seconds = 1500,
		needs = { "Lucky1" },
		effects = { luckyDrop = 0.1 },
	},
	{
		id = "Night2",
		name = "Night Shift II",
		description = "While you're away, your Shipping Bins earn 5% more of their rate, for up to 1 more hour.",
		category = "Economy",
		level = 21,
		coins = 35000,
		items = {},
		seconds = 1500,
		needs = { "Night1" },
		effects = { offlineShare = 0.05, offlineCap = 60 },
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
		needs = { "Contract1" },
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
		needs = { "Notebook1" },
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
		id = "Axe3",
		name = "Sharp Axe III",
		description = "Each tree you chop gives 1 extra Wood.",
		category = "Tools",
		level = 30,
		coins = 110000,
		items = { WoodPlanks = 40 },
		seconds = 2700,
		needs = { "Axe2" },
		effects = { chopYield = 1 },
	},
	{
		id = "Water2",
		name = "Deep Watering II",
		description = "Watering a crop takes an extra 5% off what's left of its growing stage.",
		category = "Farming",
		level = 31,
		coins = 120000,
		items = { Tomato = 30 },
		seconds = 2700,
		needs = { "Water1" },
		effects = { waterPower = 0.05 },
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
		id = "Pick3",
		name = "Strong Pickaxe III",
		description = "Each quarry rock you mine gives 1 extra of its main resource.",
		category = "Tools",
		level = 33,
		coins = 140000,
		items = { IronBar = 12 },
		seconds = 3000,
		needs = { "Pick2" },
		effects = { mineYield = 1 },
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
		id = "Saver2",
		name = "Seed Saver II",
		description = "Seeds you plant, by hand or with a Seed Planter, have a 10% greater chance not to be used up.",
		category = "Farming",
		level = 34,
		coins = 160000,
		items = { Blueberry = 20 },
		seconds = 3000,
		needs = { "Saver1" },
		effects = { seedSaver = 0.1 },
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
		id = "Contract2",
		name = "Contracts II",
		description = "Daily quests and orders pay 15% more coins.",
		category = "Economy",
		level = 36,
		coins = 200000,
		items = {},
		seconds = 3600,
		needs = { "Seeds2" },
		effects = { rewardBonus = 0.15 },
	},
	{
		id = "Lucky3",
		name = "Lucky Swing III",
		description = "Each tree you chop and rock you mine has a 10% greater chance to give its drops twice.",
		category = "Tools",
		level = 37,
		coins = 220000,
		items = { SteelFrame = 4 },
		seconds = 3600,
		needs = { "Lucky2" },
		effects = { luckyDrop = 0.1 },
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
		id = "Notebook2",
		name = "Lab Notebook II",
		description = "Line up 1 more research project behind the one running.",
		category = "Economy",
		level = 38,
		coins = 250000,
		items = { Circuit = 6 },
		seconds = 3600,
		needs = { "Study2" },
		effects = { researchQueue = 1 },
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
		id = "CraftMastery",
		name = "Crafting Mastery",
		description = "Each rank: new research projects progress 3% faster.",
		category = "Crafting",
		level = 40,
		coins = 250000,
		items = { Circuit = 4 },
		seconds = 3600,
		needs = { "ProcessorPlans" },
		effects = { researchSpeed = 0.03 },
		ranked = true,
	},
	{
		id = "Night3",
		name = "Night Shift III",
		description = "While you're away, your Shipping Bins earn 5% more of their rate, for up to 1 more hour.",
		category = "Economy",
		level = 41,
		coins = 350000,
		items = {},
		seconds = 4500,
		needs = { "Night2" },
		effects = { offlineShare = 0.05, offlineCap = 60 },
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
		id = "AutoMastery",
		name = "Automation Mastery",
		description = "Each rank: processors, Assemblers and Smelters on your plot work 2% faster.",
		category = "Automation",
		level = 42,
		coins = 300000,
		items = { Circuit = 4 },
		seconds = 3600,
		needs = { "Belts5" },
		effects = { machineSpeed = 0.02 },
		ranked = true,
	},
	{
		id = "ToolMastery",
		name = "Tools Mastery",
		description = "Each rank: chopping and mining have a 1% greater chance to give their drops twice.",
		category = "Tools",
		level = 42,
		coins = 250000,
		items = { IronBar = 10 },
		seconds = 3600,
		needs = { "Lucky3" },
		effects = { luckyDrop = 0.01 },
		ranked = true,
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
		needs = { "Notebook2" },
		effects = { researchSpeed = 0.15 },
	},
	{
		id = "FarmMastery",
		name = "Farming Mastery",
		description = "Each rank: harvests on your plot give 2% more produce on average.",
		category = "Farming",
		level = 46,
		coins = 300000,
		items = { Pumpkin = 10 },
		seconds = 3600,
		needs = { "Yield5" },
		effects = { cropYield = 0.02 },
		ranked = true,
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
	{
		id = "EconMastery",
		name = "Economy Mastery",
		description = "Each rank: your sales earn 1% more coins.",
		category = "Economy",
		level = 50,
		coins = 600000,
		items = {},
		seconds = 3600,
		needs = { "Master" },
		effects = { sellPrice = 0.01 },
		ranked = true,
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

-- A ranked project is never done, so nothing may need one.
for _, project in PROJECTS do
	for _, id in project.needs do
		assert(not byId[id].ranked, `Research: "{project.id}" needs the ranked "{id}"`)
	end
end

local Research = { PROJECTS = PROJECTS, STATS = STATS }

-- Each rank of a ranked project costs this many times the last (to two significant figures) and
-- takes this share of its first rank's time longer, up to this many times as long.
Research.RANK_COST_GROWTH = 1.25
Research.RANK_TIME_GROWTH = 0.1
Research.RANK_TIME_MOST = 2
-- Projects that can wait in the line (queued, or finished and waiting for Complete) before any
-- `researchQueue` bonus.
Research.ROOM = 1

function Research.get(id: string): Project?
	return byId[id]
end

-- 468,750 -> 470,000.
local function twoFigures(value: number): number
	if value < 100 then
		return math.round(value)
	end
	local step = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.round(value / step) * step
end

-- What `project` costs at `rank` (1 for the first; unranked projects have only that).
function Research.price(project: Project, rank: number): Price
	if not project.ranked or rank <= 1 then
		return { coins = project.coins, items = project.items, seconds = project.seconds }
	end
	return {
		coins = twoFigures(project.coins * Research.RANK_COST_GROWTH ^ (rank - 1)),
		items = project.items,
		seconds = math.round(
			project.seconds * math.min(Research.RANK_TIME_MOST, 1 + Research.RANK_TIME_GROWTH * (rank - 1))
		),
	}
end

-- How many times each project is in the line: running, queued or waiting for Complete.
function Research.lined(activeId: string?, queue: { { id: string } }, ready: { string }): { [string]: number }
	local counts: { [string]: number } = {}
	if activeId then
		counts[activeId] = 1
	end
	for _, entry in queue do
		counts[entry.id] = (counts[entry.id] or 0) + 1
	end
	for _, id in ready do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

-- The rank lining `project` up now would buy: past its finished ranks and those already lined.
function Research.nextRank(project: Project, ranks: { [string]: number }, lined: { [string]: number }): number
	return (ranks[project.id] or 0) + (lined[project.id] or 0) + 1
end

-- Whether another project fits: the running slot is free, or the line has room behind it.
function Research.fits(running: boolean, waiting: number, room: number): boolean
	return not running or waiting < room
end

function Research.bonuses(done: { [string]: boolean }, ranks: { [string]: number }?): { [Stat]: number }
	local stats: { [Stat]: number } = {}
	for stat in STATS do
		stats[stat] = 0
	end
	for _, project in PROJECTS do
		local times = if project.ranked
			then (if ranks then ranks[project.id] or 0 else 0)
			elseif done[project.id] then 1
			else 0
		if times > 0 then
			for stat, amount in project.effects do
				stats[stat] += amount * times
			end
		end
	end
	return stats
end

-- What stops `project` being lined up now, or nil. A need counts once it is done or lined up
-- (`lined`, from Research.lined); `full` says the line has no room, which the window leaves out
-- when it colours tiles.
function Research.blocker(
	project: Project,
	done: { [string]: boolean },
	level: number,
	lined: { [string]: number }?,
	full: boolean?
): string?
	if not project.ranked and done[project.id] then
		return "Already researched"
	elseif not project.ranked and lined and lined[project.id] then
		return "Already lined up"
	elseif level < project.level then
		return `Needs level {project.level}`
	end
	for _, id in project.needs do
		if not done[id] and not (lined and lined[id]) then
			return `Needs {byId[id].name}`
		end
	end
	if full then
		return "Your research queue is full"
	end
	return nil
end

-- Moves the line along at `now` (Unix seconds): while the running project's timer has run out
-- and another is queued, the finished one waits in `ready` and the next starts where it ended
-- (or when it was lined up, if later). Returns whether anything moved.
function Research.advance(saved: Saved, now: number): boolean
	local moved = false
	while saved.active and #saved.queue > 0 and now >= saved.active.startedAt + saved.active.seconds do
		local finished = saved.active
		local nextUp = table.remove(saved.queue, 1) :: Queued
		table.insert(saved.ready, finished.id)
		saved.active = {
			id = nextUp.id,
			startedAt = math.max(finished.startedAt + finished.seconds, nextUp.at),
			seconds = nextUp.seconds,
		}
		moved = true
	end
	return moved
end

-- Whether a running project's timer has run out, so it can be completed. `now` and `endsAt`
-- are on the same clock; the server allows completing up to READY_EARLY seconds before, so a
-- press the moment a client's countdown ends is never refused.
Research.READY_EARLY = 0.5
function Research.isReady(endsAt: number, now: number): boolean
	return now >= endsAt
end

-- How long `seconds` of research (Research.price) takes at a research-speed bonus.
function Research.duration(seconds: number, researchSpeed: number): number
	return math.max(1, math.round(seconds / (1 + researchSpeed)))
end

return Research
