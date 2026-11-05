-- ProgressService: lifetime progress for the loaded garden, observed only from authoritative
-- live actions while DataReady. Rewards mark completion before publishing economy events.
-- Save restoration adds no action counts; load checks saved totals for newly added milestones.
-- Deferred syncs belong to one state identity, so switching save files cannot publish old data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)

local SYNC_INTERVAL = 0.5
local PLAYTIME_SYNC_INTERVAL = 30
local CLAIM_COOLDOWN = 0.2
local random = Random.new()

type State = {
	saved: Progress.Saved,
	done: { [string]: boolean },
	changed: { [string]: boolean },
	checking: boolean,
	batching: boolean,
	urgent: boolean,
	lastSync: number,
	syncAt: number?,
	syncTicket: number,
	lastClaim: number,
	clockAt: number,
	readiness: RBXScriptConnection?,
}
local states: { [Player]: State } = {}
local achievementsByStat: { [string]: { Progress.Achievement } } = {}
for _, stat in Progress.STATS do
	achievementsByStat[stat.id] = {}
end
for _, achievement in Progress.ACHIEVEMENTS do
	table.insert(achievementsByStat[achievement.stat], achievement)
end
local started = false
local ProgressService = {}

local function questProgress(state: State, entry: { id: string, start: number }, quest: Progress.Quest): number
	return math.clamp(state.saved.stats[quest.stat] - entry.start, 0, quest.goal)
end

local function sync(player: Player, state: State): ()
	state.syncTicket += 1
	state.syncAt = nil
	state.lastSync = os.clock()
	local quests = {}
	for _, entry in state.saved.quests do
		local quest = Progress.getQuest(entry.id)
		assert(quest, "ProgressService: active quest lost its definition")
		local amount = questProgress(state, entry, quest)
		table.insert(quests, { id = entry.id, progress = amount, goal = quest.goal, done = amount >= quest.goal })
	end
	Remotes.ProgressSync:FireClient(player, {
		stats = table.clone(state.saved.stats),
		achievements = table.clone(state.saved.achievements),
		quests = quests,
		syncedAt = workspace:GetServerTimeNow(),
	})
end

local function requestSync(player: Player, state: State, playtimeOnly: boolean): ()
	if state.batching then
		return
	end
	local interval = if playtimeOnly then PLAYTIME_SYNC_INTERVAL else SYNC_INTERVAL
	local due = math.max(os.clock(), state.lastSync + interval)
	if state.syncAt and state.syncAt <= due then
		return
	end
	state.syncAt = due
	state.syncTicket += 1
	local ticket = state.syncTicket
	task.delay(math.max(0, due - os.clock()), function()
		if states[player] ~= state or state.syncTicket ~= ticket then
			return
		end
		state.syncAt = nil
		if player:GetAttribute("DataReady") == true then
			sync(player, state)
		end
	end)
end

local function draw(player: Player, state: State, slot: number?, previous: string?): { id: string, start: number }?
	local economy = EconomyService.get(player)
	if not economy then
		return nil
	end
	local active: { [string]: boolean } = {}
	for index, entry in state.saved.quests do
		if index ~= slot then
			active[entry.id] = true
		end
	end
	local choices: { Progress.Quest } = {}
	local fallback: Progress.Quest? = nil
	for _, quest in Progress.QUESTS do
		if quest.minLevel <= economy.level and not active[quest.id] then
			if quest.id == previous then
				fallback = quest
			else
				table.insert(choices, quest)
			end
		end
	end
	local chosen = if #choices > 0 then choices[random:NextInteger(1, #choices)] else fallback
	return if chosen then { id = chosen.id, start = state.saved.stats[chosen.stat] } else nil
end

local function increment(state: State, stat: string, amount: number): ()
	state.saved.stats[stat] += amount
	state.changed[stat] = true
end

local function check(player: Player, state: State): ()
	if state.checking then
		return
	end
	state.checking = true
	-- Rewards emit Earned and may cross another milestone. Drain their changes together so
	-- each achievement pays once and the client only sees the settled result.
	while next(state.changed) do
		local changed = state.changed
		state.changed = {}
		for stat in changed do
			for _, achievement in achievementsByStat[stat] do
				if not state.saved.achievements[achievement.id] and state.saved.stats[stat] >= achievement.goal then
					state.saved.achievements[achievement.id] = true
					increment(state, "achievementsUnlocked", 1)
					state.urgent = true
					EconomyService.add(player, achievement.reward.coins)
					EconomyService.addXp(player, achievement.reward.xp)
					Remotes.Notify:FireClient(
						player,
						`Achievement unlocked! {achievement.name} +{achievement.reward.coins} coins`,
						"Achievement"
					)
				end
			end
		end
	end
	for _, entry in state.saved.quests do
		local quest = Progress.getQuest(entry.id)
		if quest and not state.done[entry.id] and questProgress(state, entry, quest) >= quest.goal then
			state.done[entry.id] = true
			state.urgent = true
			Remotes.Notify:FireClient(player, `Quest done! {quest.text}. Claim it in Quests.`, "Quest")
		end
	end
	state.checking = false
end

local function observe(player: Player, stat: string, amount: number): ()
	local state = states[player]
	if not state or player:GetAttribute("DataReady") ~= true or amount <= 0 then
		return
	end
	increment(state, stat, amount)
	state.urgent = state.urgent or stat ~= "playtime"
	if state.checking then
		return
	end
	check(player, state)
	requestSync(player, state, not state.urgent)
	state.urgent = false
end

local function claim(player: Player, action: unknown, slot: unknown): ()
	local state = states[player]
	if
		not state
		or state.batching
		or player:GetAttribute("DataReady") ~= true
		or typeof(action) ~= "string"
		or action ~= "ClaimQuest"
		or typeof(slot) ~= "number"
		or slot % 1 ~= 0
		or slot < 1
		or slot > Progress.QUEST_SLOTS
	then
		return
	end
	local now = os.clock()
	if now - state.lastClaim < CLAIM_COOLDOWN then
		return
	end
	state.lastClaim = now
	local entry = state.saved.quests[slot]
	local quest = if entry then Progress.getQuest(entry.id) else nil
	if not entry or not quest or questProgress(state, entry, quest) < quest.goal then
		return
	end
	state.batching = true
	state.done[entry.id] = true
	EconomyService.add(player, quest.reward.coins)
	EconomyService.addXp(player, quest.reward.xp)
	observe(player, "questsCompleted", 1)
	Remotes.Notify:FireClient(player, `Quest complete! +{quest.reward.coins} coins`, "Reward")
	local replacement = draw(player, state, slot, entry.id)
	assert(replacement, "ProgressService: quest pool cannot refill a claimed slot")
	state.saved.quests[slot] = replacement
	state.done[entry.id] = nil
	state.done[replacement.id] = nil
	state.batching = false
	sync(player, state)
end

function ProgressService.release(player: Player): ()
	local state = states[player]
	if state and state.readiness then
		state.readiness:Disconnect()
	end
	states[player] = nil
end

function ProgressService.load(player: Player, saved: Progress.Saved): ()
	ProgressService.init()
	ProgressService.release(player)
	local state: State = {
		saved = Progress.sanitize(saved),
		done = {},
		changed = {},
		checking = false,
		batching = true,
		urgent = false,
		lastSync = 0,
		syncAt = nil,
		syncTicket = 0,
		lastClaim = -math.huge,
		clockAt = os.clock(),
		readiness = nil,
	}
	states[player] = state
	state.readiness = player:GetAttributeChangedSignal("DataReady"):Connect(function()
		-- Loading time and time in the save menu never belong to a garden's playtime.
		state.clockAt = os.clock()
	end)
	for _, entry in state.saved.quests do
		local quest = Progress.getQuest(entry.id)
		if quest and questProgress(state, entry, quest) >= quest.goal then
			state.done[entry.id] = true
		end
	end
	while #state.saved.quests < Progress.QUEST_SLOTS do
		local entry = draw(player, state)
		if not entry then
			break
		end
		table.insert(state.saved.quests, entry)
	end
	for _, stat in Progress.STATS do
		state.changed[stat.id] = true
	end
	check(player, state)
	state.urgent = false
	state.batching = false
	sync(player, state)
end

function ProgressService.snapshot(player: Player): Progress.Saved?
	local state = states[player]
	return if state then Progress.sanitize(state.saved) else nil
end

function ProgressService.init(): ()
	if started then
		return
	end
	started = true
	for signal, stat in
		{
			[GardenEvents.Planted] = "seedsPlanted",
			[GardenEvents.Tilled] = "groundTilled",
			[GardenEvents.Watered] = "cropsWatered",
			[GardenEvents.Chopped] = "treesChopped",
			[GardenEvents.Mined] = "rocksMined",
			[GardenEvents.ResearchDone] = "researchDone",
			[GardenEvents.Placed] = "blocksPlaced",
			[GardenEvents.SectionBought] = "sectionsBought",
		}
	do
		signal:Connect(function(player: Player)
			observe(player, stat, 1)
		end)
	end
	GardenEvents.Harvested:Connect(function(player: Player, _: string, mutation: string?)
		observe(player, "cropsHarvested", 1)
		if mutation ~= nil then
			observe(player, "mutatedHarvested", 1)
		end
	end)
	GardenEvents.Crafted:Connect(function(player: Player, recipeId: string, times: number)
		local recipe = Crafting.get(recipeId)
		if recipe then
			observe(player, "itemsCrafted", recipe.count * times)
		end
	end)
	GardenEvents.Bought:Connect(function(player: Player, _: string, count: number)
		observe(player, "itemsBought", count)
	end)
	for signal, stat in
		{
			[GardenEvents.Sold] = "salesCoins",
			[GardenEvents.Earned] = "coinsEarned",
			[GardenEvents.Spent] = "coinsSpent",
		}
	do
		signal:Connect(function(player: Player, coins: number)
			observe(player, stat, coins)
		end)
	end
	Remotes.Progress.OnServerEvent:Connect(claim)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, state in states do
				if player:GetAttribute("DataReady") == true then
					local seconds = math.floor(now - state.clockAt)
					state.clockAt += seconds
					observe(player, "playtime", seconds)
				else
					state.clockAt = now
				end
			end
		end
	end)
end

return ProgressService
