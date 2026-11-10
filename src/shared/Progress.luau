--!strict
-- Progress: ordered lifetime stats, achievement tiers, the daily quest pool and the rules for
-- orders, for one garden. Rules here are pure; ProgressService owns counting, draws and one-time
-- rewards. Sanitization makes fresh, bounded save tables and never carries unknown content ids
-- forward.
--
-- Daily quests: three a UTC day, drawn from QUESTS. A quest's goal and reward are fixed by the
-- level it was drawn at (saved with it), so levelling during the day never moves them.
-- Orders: ORDER_SLOTS requests to deliver an item from the inventory, sized to Economy.scale of
-- the level they were drawn at; they pay more than selling and never expire. A skipped order's
-- slot waits SKIP_SECONDS for the next one. Why these numbers: docs/retention.md § Orders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Inventory = require(ReplicatedStorage.Shared.Inventory)

export type StatFormat = "count" | "coins" | "time"
export type Stat = { id: string, name: string, format: StatFormat }
export type Reward = { coins: number, xp: number }
export type Achievement = { id: string, name: string, description: string, stat: string, goal: number, reward: Reward }
-- How a quest's goal grows with level: "machine" stats a factory can raise (by LEVEL_BANDS'
-- machine multiplier), "hand" actions (its gentler one), "sales" (coins, from Economy.scale) or
-- "none".
export type Growth = "machine" | "hand" | "sales" | "none"
-- `text` holds one %s for the goal.
export type Quest = { id: string, text: string, stat: string, goal: number, minLevel: number, growth: Growth }
export type Daily = { id: string, start: number, level: number, claimed: boolean }
-- An order slot: an item and count to deliver, or `waitUntil` (Unix seconds) after a skip.
export type Order = { item: string?, count: number?, waitUntil: number? }
export type Saved = {
	stats: { [string]: number },
	achievements: { [string]: boolean },
	-- `day` is the UTC day the quests belong to; `bonus` whether its all-three seed was given.
	daily: { day: number, quests: { Daily }, bonus: boolean },
	orders: { Order },
}

local Progress = {}

Progress.QUEST_SLOTS = 3
Progress.ORDER_SLOTS = 3
-- An order asks for this many of its item at least and at most.
Progress.ORDER_MIN = 3
Progress.ORDER_MAX = 200
-- A mutated crop is rare, so its orders ask for a fifth of the usual worth, ten at most.
Progress.ORDER_MUTATED_SHARE = 0.2
Progress.ORDER_MUTATED_MAX = 10
-- The share of orders that ask for a mutated crop the garden has found.
Progress.ORDER_MUTATED_CHANCE = 0.2
-- Coins an order pays over its goods' sell value, and the coins of goods per XP (a sale gives 1 per 10).
Progress.ORDER_PREMIUM = 1.5
Progress.ORDER_COINS_PER_XP = 5
-- Every this many orders filled adds a seed one rarity above the best crop discovered.
Progress.ORDER_BONUS_EVERY = 5
-- Seconds a skipped order's slot stays empty.
Progress.SKIP_SECONDS = 300
-- The seed rarity finishing all three daily quests gives, by chance (first guesses).
Progress.DAILY_BONUS = {
	{ rarity = "Rare", chance = 0.6 },
	{ rarity = "Epic", chance = 0.3 },
	{ rarity = "Legendary", chance = 0.09 },
	{ rarity = "Mythic", chance = 0.01 },
}
-- From `level` up, a daily quest's base goal is multiplied by these.
local LEVEL_BANDS = {
	{ level = 1, machine = 1, hand = 1 },
	{ level = 5, machine = 4, hand = 2 },
	{ level = 12, machine = 12, hand = 2 },
	{ level = 25, machine = 30, hand = 3 },
}

Progress.STATS = {
	{ id = "playtime", name = "Time played", format = "time" },
	{ id = "coinsEarned", name = "Coins earned", format = "coins" },
	{ id = "coinsSpent", name = "Coins spent", format = "coins" },
	{ id = "salesCoins", name = "Coins from sales", format = "coins" },
	{ id = "cropsHarvested", name = "Crops harvested", format = "count" },
	{ id = "mutatedHarvested", name = "Mutated crops harvested", format = "count" },
	{ id = "seedsPlanted", name = "Seeds planted", format = "count" },
	{ id = "groundTilled", name = "Ground tilled", format = "count" },
	{ id = "cropsWatered", name = "Crops watered", format = "count" },
	{ id = "treesChopped", name = "Trees chopped", format = "count" },
	{ id = "rocksMined", name = "Rocks mined", format = "count" },
	{ id = "itemsCrafted", name = "Items crafted", format = "count" },
	{ id = "researchDone", name = "Research finished", format = "count" },
	{ id = "blocksPlaced", name = "Blocks placed", format = "count" },
	{ id = "itemsBought", name = "Items bought", format = "count" },
	{ id = "sectionsBought", name = "Garden sections bought", format = "count" },
	{ id = "ordersFilled", name = "Orders filled", format = "count" },
	{ id = "questsCompleted", name = "Daily quests completed", format = "count" },
	{ id = "achievementsUnlocked", name = "Achievements unlocked", format = "count" },
} :: { Stat }

Progress.ACHIEVEMENTS = {} :: { Achievement }

local NUMERALS = { "I", "II", "III", "IV" }
-- A tier's reward. Tier III lands around hours 3-6, where a level costs 7,000-10,000 XP.
local TIER_COINS = { 100, 1500, 25000, 250000 }
local TIER_XP = { 10, 150, 2000, 10000 }

-- "5000" as "5,000", for goals in words.
local function grouped(value: number): string
	local text = string.reverse(tostring(math.floor(value)))
	return (string.reverse((string.gsub(text, "(%d%d%d)", "%1,"))):gsub("^,", ""))
end

-- One achievement per goal (three, or four where a factory can keep counting).
local function tiers(id: string, name: string, stat: string, goals: { number }, verb: string, noun: string): ()
	for tier, goal in goals do
		table.insert(Progress.ACHIEVEMENTS, {
			id = `{id}{tier}`,
			name = `{name} {NUMERALS[tier]}`,
			description = `{verb} {grouped(goal)} {noun}.`,
			stat = stat,
			goal = goal,
			reward = { coins = TIER_COINS[tier], xp = TIER_XP[tier] },
		})
	end
end

tiers("Harvest", "Green Thumb", "cropsHarvested", { 25, 250, 5000, 50000 }, "Harvest", "crops")
tiers("Mutation", "Garden Wonders", "mutatedHarvested", { 5, 50, 1000, 10000 }, "Harvest", "mutated crops")
tiers("Plant", "Seeds of Tomorrow", "seedsPlanted", { 25, 250, 5000 }, "Plant", "seeds")
tiers("Chop", "Lumberjack", "treesChopped", { 10, 100, 1000 }, "Chop", "trees")
tiers("Mine", "Stone by Stone", "rocksMined", { 25, 250, 2500 }, "Mine", "rocks or ground cells")
tiers("Craft", "Helping Hands", "itemsCrafted", { 20, 200, 2000, 20000 }, "Craft", "items")
tiers("Sales", "Market Regular", "salesCoins", { 1000, 25000, 500000, 5000000 }, "Earn", "coins from sales")
tiers("Research", "Curious Gardener", "researchDone", { 1, 5, 20, 45 }, "Finish", "research projects")
tiers("Build", "A Place to Grow", "blocksPlaced", { 20, 200, 2000 }, "Place", "blocks")
tiers("Quest", "Little Adventures", "questsCompleted", { 3, 25, 100 }, "Complete", "daily quests")
tiers("Order", "Special Delivery", "ordersFilled", { 3, 25, 250 }, "Fill", "orders")
table.insert(Progress.ACHIEVEMENTS, {
	id = "Playtime1",
	name = "A Quiet Hour",
	description = "Play for 1 hour.",
	stat = "playtime",
	goal = 3600,
	reward = { coins = 250, xp = 10 },
})
table.insert(Progress.ACHIEVEMENTS, {
	id = "Playtime2",
	name = "At Home in the Garden",
	description = "Play for 10 hours.",
	stat = "playtime",
	goal = 36000,
	reward = { coins = 10000, xp = 500 },
})

local function quest(id: string, text: string, stat: string, goal: number, minLevel: number, growth: Growth): Quest
	return { id = id, text = text, stat = stat, goal = goal, minLevel = minLevel, growth = growth }
end

Progress.QUESTS = {
	quest("Harvest25", "Harvest %s crops", "cropsHarvested", 25, 1, "machine"),
	quest("Plant25", "Plant %s seeds", "seedsPlanted", 25, 1, "hand"),
	quest("Till20", "Till %s ground cells", "groundTilled", 20, 1, "hand"),
	quest("Water15", "Water crops %s times", "cropsWatered", 15, 1, "hand"),
	quest("Chop10", "Chop %s trees", "treesChopped", 10, 1, "hand"),
	quest("Mine25", "Mine %s rocks or ground cells", "rocksMined", 25, 1, "hand"),
	quest("Craft20", "Craft %s items", "itemsCrafted", 20, 1, "machine"),
	quest("Sell500", "Earn %s coins from sales", "salesCoins", 500, 1, "sales"),
	quest("Place20", "Place %s blocks", "blocksPlaced", 20, 1, "hand"),
	quest("Buy20", "Buy %s items", "itemsBought", 20, 1, "hand"),
	quest("Mutation5", "Harvest %s mutated crops", "mutatedHarvested", 5, 3, "machine"),
	quest("Research1", "Finish %s research project", "researchDone", 1, 3, "none"),
} :: { Quest }

local stats: { [string]: Stat } = {}
local achievements: { [string]: Achievement } = {}
local quests: { [string]: Quest } = {}
for _, stat in Progress.STATS do
	assert(not stats[stat.id], `Progress: duplicate stat {stat.id}`)
	stats[stat.id] = stat
end
for _, achievement in Progress.ACHIEVEMENTS do
	assert(
		not achievements[achievement.id] and stats[achievement.stat],
		`Progress: invalid achievement {achievement.id}`
	)
	achievements[achievement.id] = achievement
end
for _, definition in Progress.QUESTS do
	assert(not quests[definition.id] and stats[definition.stat], `Progress: invalid quest {definition.id}`)
	quests[definition.id] = definition
end
assert(#Progress.QUESTS >= Progress.QUEST_SLOTS, "Progress: the quest pool cannot fill a day")

function Progress.getStat(id: string): Stat?
	return stats[id]
end

function Progress.getAchievement(id: string): Achievement?
	return achievements[id]
end

function Progress.getQuest(id: string): Quest?
	return quests[id]
end

-- The UTC day a Unix time falls in, and when that day ends.
function Progress.day(now: number): number
	return now // 86400
end

function Progress.dayEnd(day: number): number
	return (day + 1) * 86400
end

-- A daily quest's goal for a player who drew it at `level`.
function Progress.questGoal(definition: Quest, level: number): number
	if definition.growth == "none" then
		return definition.goal
	elseif definition.growth == "sales" then
		return math.max(definition.goal, 3 * Economy.scale(level))
	end
	local band = LEVEL_BANDS[1]
	for _, each in LEVEL_BANDS do
		if level >= each.level then
			band = each
		end
	end
	return definition.goal * (if definition.growth == "machine" then band.machine else band.hand)
end

-- "Harvest 300 crops".
function Progress.questText(definition: Quest, level: number): string
	return string.format(definition.text, grouped(Progress.questGoal(definition, level)))
end

-- What each daily quest pays at `level`: half the level's scale in coins and a twentieth of
-- the level's XP cost.
function Progress.questReward(level: number): Reward
	return {
		coins = math.round(Economy.scale(level) / 2),
		xp = math.max(3, math.round(Economy.required(level) * 0.05)),
	}
end

-- How many of an item worth `value` an order drawn at `level` asks for.
function Progress.orderCount(value: number, level: number, mutated: boolean): number
	local worth = Economy.scale(level)
	if mutated then
		return math.clamp(math.ceil(worth * Progress.ORDER_MUTATED_SHARE / value), 1, Progress.ORDER_MUTATED_MAX)
	end
	return math.clamp(math.ceil(worth / value), Progress.ORDER_MIN, Progress.ORDER_MAX)
end

-- What delivering `count` of an item worth `value` pays.
function Progress.orderReward(value: number, count: number): Reward
	local goods = value * count
	return { coins = math.floor(goods * Progress.ORDER_PREMIUM), xp = goods // Progress.ORDER_COINS_PER_XP }
end

-- Orders still to fill before one adds its bonus seed (1: the next one does).
function Progress.ordersToBonus(filled: number): number
	return Progress.ORDER_BONUS_EVERY - filled % Progress.ORDER_BONUS_EVERY
end

function Progress.empty(): Saved
	local saved: Saved = { stats = {}, achievements = {}, daily = { day = 0, quests = {}, bonus = false }, orders = {} }
	for _, stat in Progress.STATS do
		saved.stats[stat.id] = 0
	end
	return saved
end

local function validNumber(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge
end

local function whole(value: any): boolean
	return validNumber(value) and value % 1 == 0
end

-- A damaged array's entries in index order, holes skipped.
local function ordered(list: any): { any }
	local indices: { number } = {}
	for index in next, list do
		if whole(index) and index >= 1 then
			table.insert(indices, index)
		end
	end
	table.sort(indices)
	local entries = {}
	for _, index in indices do
		table.insert(entries, rawget(list, index))
	end
	return entries
end

-- Saves from before daily quests held `quests`, the endless slots; they are dropped.
function Progress.sanitize(value: any): Saved
	local saved = Progress.empty()
	if typeof(value) ~= "table" then
		return saved
	end
	local savedStats = rawget(value, "stats")
	if typeof(savedStats) == "table" then
		for id in stats do
			local amount = rawget(savedStats, id)
			if typeof(amount) == "number" and validNumber(amount) then
				saved.stats[id] = amount
			end
		end
	end
	local savedAchievements = rawget(value, "achievements")
	if typeof(savedAchievements) == "table" then
		for id in achievements do
			if rawget(savedAchievements, id) == true then
				saved.achievements[id] = true
			end
		end
	end
	local daily = rawget(value, "daily")
	if typeof(daily) == "table" and whole(rawget(daily, "day")) and typeof(rawget(daily, "quests")) == "table" then
		saved.daily.day = rawget(daily, "day") :: number
		saved.daily.bonus = rawget(daily, "bonus") == true
		-- Keep slot order; never keep duplicate ids.
		local seen: { [string]: boolean } = {}
		for _, entry in ordered(rawget(daily, "quests")) do
			if typeof(entry) ~= "table" or #saved.daily.quests == Progress.QUEST_SLOTS then
				continue
			end
			local id, start, level = rawget(entry, "id"), rawget(entry, "start"), rawget(entry, "level")
			if
				typeof(id) == "string"
				and quests[id]
				and not seen[id]
				and validNumber(start)
				and whole(level)
				and level >= 1
			then
				seen[id] = true
				table.insert(saved.daily.quests, {
					id = id,
					start = start :: number,
					level = level :: number,
					claimed = rawget(entry, "claimed") == true,
				})
			end
		end
	end
	local orders = rawget(value, "orders")
	if typeof(orders) == "table" then
		for _, entry in ordered(orders) do
			if typeof(entry) ~= "table" or #saved.orders == Progress.ORDER_SLOTS then
				continue
			end
			local itemId, count, waitUntil = rawget(entry, "item"), rawget(entry, "count"), rawget(entry, "waitUntil")
			local item = if typeof(itemId) == "string" then Inventory.find(itemId) else nil
			if item and item.value and whole(count) and count >= 1 and count <= Progress.ORDER_MAX then
				table.insert(saved.orders, { item = itemId, count = count })
			else
				-- An order for an item since cut, or a waiting slot: the slot waits (at once, if its time is unknown).
				table.insert(saved.orders, { waitUntil = if validNumber(waitUntil) then waitUntil else 0 })
			end
		end
	end
	return saved
end

return Progress
