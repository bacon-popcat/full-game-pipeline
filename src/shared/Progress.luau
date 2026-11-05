--!strict
-- Progress: ordered lifetime stats, achievement tiers and the repeatable quest pool for one
-- garden. Rules here are pure; ProgressService owns counting, draws and one-time rewards.
-- Sanitization makes fresh, bounded save tables and never carries unknown content ids forward.

export type StatFormat = "count" | "coins" | "time"
export type Stat = { id: string, name: string, format: StatFormat }
export type Reward = { coins: number, xp: number }
export type Achievement = { id: string, name: string, description: string, stat: string, goal: number, reward: Reward }
export type Quest = { id: string, text: string, stat: string, goal: number, minLevel: number, reward: Reward }
export type Saved = {
	stats: { [string]: number },
	achievements: { [string]: boolean },
	quests: { { id: string, start: number } },
}

local Progress = {}

Progress.QUEST_SLOTS = 3
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
	{ id = "questsCompleted", name = "Quests completed", format = "count" },
	{ id = "achievementsUnlocked", name = "Achievements unlocked", format = "count" },
} :: { Stat }

Progress.ACHIEVEMENTS = {} :: { Achievement }

local NUMERALS = { "I", "II", "III" }

-- "5000" as "5,000", for goals in descriptions.
local function grouped(value: number): string
	local text = string.reverse(tostring(math.floor(value)))
	return (string.reverse((string.gsub(text, "(%d%d%d)", "%1,"))):gsub("^,", ""))
end

local function tiers(id: string, name: string, stat: string, goals: { number }, verb: string, noun: string): ()
	local coins = { 50, 250, 2000 }
	local xp = { 5, 15, 40 }
	for tier, goal in goals do
		table.insert(Progress.ACHIEVEMENTS, {
			id = `{id}{tier}`,
			name = `{name} {NUMERALS[tier]}`,
			description = `{verb} {grouped(goal)} {noun}.`,
			stat = stat,
			goal = goal,
			reward = { coins = coins[tier], xp = xp[tier] },
		})
	end
end

tiers("Harvest", "Green Thumb", "cropsHarvested", { 25, 250, 5000 }, "Harvest", "crops")
tiers("Mutation", "Garden Wonders", "mutatedHarvested", { 5, 50, 1000 }, "Harvest", "mutated crops")
tiers("Plant", "Seeds of Tomorrow", "seedsPlanted", { 25, 250, 5000 }, "Plant", "seeds")
tiers("Chop", "Lumberjack", "treesChopped", { 10, 100, 1000 }, "Chop", "trees")
tiers("Mine", "Stone by Stone", "rocksMined", { 25, 250, 2500 }, "Mine", "rocks or ground cells")
tiers("Craft", "Helping Hands", "itemsCrafted", { 20, 200, 2000 }, "Craft", "items at a Crafting Bench")
tiers("Sales", "Market Regular", "salesCoins", { 1000, 25000, 500000 }, "Earn", "coins from sales")
tiers("Research", "Curious Gardener", "researchDone", { 1, 5, 20 }, "Finish", "research projects")
tiers("Build", "A Place to Grow", "blocksPlaced", { 20, 200, 2000 }, "Place", "blocks")
tiers("Quest", "Little Adventures", "questsCompleted", { 3, 25, 250 }, "Complete", "quests")
table.insert(Progress.ACHIEVEMENTS, {
	id = "Playtime1",
	name = "A Quiet Hour",
	description = "Play for 1 hour.",
	stat = "playtime",
	goal = 3600,
	reward = { coins = 100, xp = 5 },
})
table.insert(Progress.ACHIEVEMENTS, {
	id = "Playtime2",
	name = "At Home in the Garden",
	description = "Play for 10 hours.",
	stat = "playtime",
	goal = 36000,
	reward = { coins = 1000, xp = 25 },
})

local function quest(
	id: string,
	text: string,
	stat: string,
	goal: number,
	minLevel: number,
	coins: number,
	xp: number
): Quest
	return { id = id, text = text, stat = stat, goal = goal, minLevel = minLevel, reward = { coins = coins, xp = xp } }
end

Progress.QUESTS = {
	quest("Harvest25", "Harvest 25 crops", "cropsHarvested", 25, 1, 30, 3),
	quest("Plant25", "Plant 25 seeds", "seedsPlanted", 25, 1, 30, 3),
	quest("Till20", "Till 20 ground cells", "groundTilled", 20, 1, 25, 3),
	quest("Water15", "Water crops 15 times", "cropsWatered", 15, 1, 25, 3),
	quest("Chop10", "Chop 10 trees", "treesChopped", 10, 1, 30, 3),
	quest("Mine25", "Mine 25 rocks or ground cells", "rocksMined", 25, 1, 30, 3),
	quest("Craft20", "Craft 20 items at a Crafting Bench", "itemsCrafted", 20, 1, 30, 3),
	quest("Sell500", "Earn 500 coins from sales", "salesCoins", 500, 1, 25, 3),
	quest("Place20", "Place 20 blocks", "blocksPlaced", 20, 1, 30, 3),
	quest("Buy20", "Buy 20 items", "itemsBought", 20, 1, 20, 3),
	quest("Mutation5", "Harvest 5 mutated crops", "mutatedHarvested", 5, 3, 30, 3),
	quest("Research1", "Finish 1 research project", "researchDone", 1, 3, 30, 3),
	quest("Harvest100", "Harvest 100 crops", "cropsHarvested", 100, 5, 80, 8),
	quest("Sell5000", "Earn 5,000 coins from sales", "salesCoins", 5000, 5, 75, 8),
	quest("Craft100", "Craft 100 items at a Crafting Bench", "itemsCrafted", 100, 5, 60, 8),
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

function Progress.getStat(id: string): Stat?
	return stats[id]
end

function Progress.getAchievement(id: string): Achievement?
	return achievements[id]
end

function Progress.getQuest(id: string): Quest?
	return quests[id]
end

function Progress.empty(): Saved
	local saved: Saved = { stats = {}, achievements = {}, quests = {} }
	for _, stat in Progress.STATS do
		saved.stats[stat.id] = 0
	end
	return saved
end

local function validNumber(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge
end

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
	local savedQuests = rawget(value, "quests")
	if typeof(savedQuests) == "table" then
		-- Keep slot order even when a damaged array has holes; never keep duplicate active ids.
		local indices: { number } = {}
		for index in next, savedQuests do
			if validNumber(index) and index >= 1 and index % 1 == 0 then
				table.insert(indices, index)
			end
		end
		table.sort(indices)
		local seen: { [string]: boolean } = {}
		for _, index in indices do
			local entry = rawget(savedQuests, index)
			if typeof(entry) == "table" then
				local id, start = rawget(entry, "id"), rawget(entry, "start")
				if
					typeof(id) == "string"
					and quests[id]
					and not seen[id]
					and typeof(start) == "number"
					and validNumber(start)
				then
					seen[id] = true
					table.insert(saved.quests, { id = id, start = start })
					if #saved.quests == Progress.QUEST_SLOTS then
						break
					end
				end
			end
		end
	end
	return saved
end

return Progress
