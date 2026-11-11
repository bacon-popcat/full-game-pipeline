-- ProgressService: lifetime progress for the loaded garden, observed only from authoritative
-- live actions while DataReady. Rewards mark completion before publishing economy events.
-- Save restoration adds no action counts; load checks saved totals for newly added milestones.
-- Deferred syncs belong to one state identity, so switching save files cannot publish old data.
--
-- Daily quests: three a UTC day (Shared/Progress). A new day, on load or as the clock passes
-- midnight, pays any quest that was done and unclaimed, then draws three more.
-- Orders: Progress.ORDER_SLOTS requests for an item the garden can make (a discovered crop, a
-- product whose machine it has had, sometimes a mutated crop it has found). Delivering takes the
-- items from the inventory in one step, pays and draws the next; a skip leaves the slot waiting.
-- GardenService must be loaded first: orders read its discoveries and Index.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Products = require(ReplicatedStorage.Shared.Factory.Products)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)
local GardenService = require(script.Parent.GardenService)
local InventoryService = require(script.Parent.InventoryService)

local SYNC_INTERVAL = 0.5
local PLAYTIME_SYNC_INTERVAL = 30
local ACTION_COOLDOWN = 0.2
-- The crops every garden can grow from the start: their seeds are always in stock.
local STARTER_CROPS = { "Carrot", "Wheat" }
local random = Random.new()

type State = {
	saved: Progress.Saved,
	-- Daily quest ids already announced as done.
	done: { [string]: boolean },
	changed: { [string]: boolean },
	checking: boolean,
	batching: boolean,
	urgent: boolean,
	lastSync: number,
	syncAt: number?,
	syncTicket: number,
	lastAction: number,
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
local cropsByRarity: { [number]: { World.Crop } } = {}
for _, crop in World.CROPS do
	local order = Content.RARITIES[crop.rarity].order
	cropsByRarity[order] = cropsByRarity[order] or {}
	table.insert(cropsByRarity[order], crop)
end
local rarityOrder: { [string]: number } = {}
local topRarity = 1
for name, rarity in Content.RARITIES do
	rarityOrder[name] = rarity.order
	topRarity = math.max(topRarity, rarity.order)
end
local started = false
local ProgressService = {}

local function questProgress(state: State, entry: Progress.Daily, quest: Progress.Quest): (number, number)
	local goal = Progress.questGoal(quest, entry.level)
	return math.clamp(state.saved.stats[quest.stat] - entry.start, 0, goal), goal
end

local function sync(player: Player, state: State): ()
	state.syncTicket += 1
	state.syncAt = nil
	state.lastSync = os.clock()
	-- Deadlines travel on the server clock every client shares, not on Unix time.
	local now = workspace:GetServerTimeNow()
	local offset = now - os.time()
	local quests = {}
	for _, entry in state.saved.daily.quests do
		local quest = Progress.getQuest(entry.id)
		assert(quest, "ProgressService: a daily quest lost its definition")
		local amount, goal = questProgress(state, entry, quest)
		table.insert(quests, {
			id = entry.id,
			text = Progress.questText(quest, entry.level),
			progress = amount,
			goal = goal,
			done = amount >= goal,
			claimed = entry.claimed,
			reward = Progress.questReward(entry.level),
		})
	end
	local orders: { any } = {}
	for _, entry in state.saved.orders do
		local item = if entry.item then Inventory.find(entry.item) else nil
		if entry.item and entry.count and item and item.value then
			table.insert(
				orders,
				{ item = entry.item, count = entry.count, reward = Progress.orderReward(item.value, entry.count) }
			)
		else
			table.insert(orders, { waitUntil = (entry.waitUntil or 0) + offset })
		end
	end
	Remotes.ProgressSync:FireClient(player, {
		stats = table.clone(state.saved.stats),
		achievements = table.clone(state.saved.achievements),
		daily = {
			quests = quests,
			resetsAt = Progress.dayEnd(state.saved.daily.day) + offset,
			bonus = state.saved.daily.bonus,
		},
		orders = orders,
		ordersToBonus = Progress.ordersToBonus(state.saved.stats.ordersFilled),
		syncedAt = now,
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
						`{achievement.name}! +{achievement.reward.coins} coins`,
						"Achievement",
						{ open = "Achievements" }
					)
				end
			end
		end
	end
	for _, entry in state.saved.daily.quests do
		local quest = Progress.getQuest(entry.id)
		if quest and not entry.claimed and not state.done[entry.id] then
			local amount, goal = questProgress(state, entry, quest)
			if amount >= goal then
				state.done[entry.id] = true
				state.urgent = true
				Remotes.Notify:FireClient(
					player,
					`Daily quest done! {Progress.questText(quest, entry.level)}. Claim it in Quests.`,
					"Quest",
					{ open = "Quests" }
				)
			end
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

-- Adds to a stat during load or a reward, where `observe` would refuse (DataReady) or re-enter.
local function count(player: Player, state: State, stat: string, amount: number): ()
	increment(state, stat, amount)
	check(player, state)
end

local function seedOf(order: number): string
	local crops = cropsByRarity[math.clamp(order, 1, topRarity)]
	return crops[random:NextInteger(1, #crops)].seed
end

---------------------------------------------------------------- daily quests

local function drawDaily(player: Player, state: State): ()
	local economy = EconomyService.get(player)
	local level = if economy then economy.level else 1
	local pool: { Progress.Quest } = {}
	for _, quest in Progress.QUESTS do
		if quest.minLevel <= level then
			table.insert(pool, quest)
		end
	end
	local quests: { Progress.Daily } = {}
	while #quests < Progress.QUEST_SLOTS and #pool > 0 do
		local quest = table.remove(pool, random:NextInteger(1, #pool)) :: Progress.Quest
		table.insert(quests, { id = quest.id, start = state.saved.stats[quest.stat], level = level, claimed = false })
	end
	state.saved.daily = { day = Progress.day(os.time()), quests = quests, bonus = false }
	state.done = {}
end

-- Pays one daily quest. The last of the day also gives the bonus seed, which must fit: a
-- player's claim is refused until it does, while `auto` (the day ending) pays without it.
local function claimDaily(player: Player, state: State, slot: number, auto: boolean): boolean
	local daily = state.saved.daily
	local entry = daily.quests[slot]
	local quest = if entry then Progress.getQuest(entry.id) else nil
	if not entry or not quest or entry.claimed then
		return false
	end
	local amount, goal = questProgress(state, entry, quest)
	if amount < goal then
		return false
	end
	local last = not daily.bonus
	for index, other in daily.quests do
		if index ~= slot and not other.claimed then
			last = false
		end
	end
	local seed: string? = nil
	if last then
		local roll = random:NextNumber()
		local rarity = Progress.DAILY_BONUS[#Progress.DAILY_BONUS].rarity
		for _, each in Progress.DAILY_BONUS do
			if roll < each.chance then
				rarity = each.rarity
				break
			end
			roll -= each.chance
		end
		local rolled = seedOf(rarityOrder[rarity])
		seed = rolled
		if not InventoryService.canGive(player, rolled, 1) then
			if not auto then
				Remotes.Notify:FireClient(player, "Make room in your inventory for the bonus seed first.", "Error")
				return false
			end
			seed = nil
		end
	end
	-- Mark before paying; a reward's own events cannot pay it again.
	entry.claimed = true
	state.done[entry.id] = true
	local reward = Progress.questReward(entry.level)
	EconomyService.add(player, reward.coins)
	EconomyService.addXp(player, reward.xp)
	count(player, state, "questsCompleted", 1)
	Remotes.Notify:FireClient(player, `Daily quest complete! +{reward.coins} coins`, "Reward")
	if seed then
		daily.bonus = true
		InventoryService.give(player, seed, 1)
		Remotes.Notify:FireClient(player, `All three done! Bonus {Inventory.getItem(seed).name}`, "Rare", { item = seed })
	end
	return true
end

-- Moves the garden to today's quests when its saved ones are from another day.
local function rollDay(player: Player, state: State): boolean
	if state.saved.daily.day == Progress.day(os.time()) and #state.saved.daily.quests > 0 then
		return false
	end
	for slot in state.saved.daily.quests do
		claimDaily(player, state, slot, true)
	end
	drawDaily(player, state)
	return true
end

---------------------------------------------------------------- orders

-- What the garden can be asked for: plain items it can make, and mutated crops it has found.
local function candidates(player: Player): ({ string }, { string })
	local garden = GardenService.snapshot(player)
	local discovered = if garden then garden.discovered else {}
	local indexed = if garden then garden.indexed else {}
	local available: { [string]: boolean } = {}
	local produce: { [string]: boolean } = {}
	for _, cropId in STARTER_CROPS do
		discovered[cropId] = true
	end
	for cropId, crop in World.CROPS do
		if discovered[cropId] then
			available[crop.produce] = true
			produce[crop.produce] = true
		end
	end
	-- A product is available once the garden has had its machine, finished the research its
	-- recipe needs, and can make every input.
	local grew = true
	while grew do
		grew = false
		for _, product in Products do
			if
				product.value
				and not available[product.id]
				and (indexed[product.machine] or indexed[product.machine .. "Tier2"])
			then
				local makeable = product.research == nil or Bonuses.has(player, product.research)
				for itemId in product.inputs do
					makeable = makeable and available[itemId] == true
				end
				if makeable then
					available[product.id] = true
					grew = true
				end
			end
		end
	end
	local plain: { string } = {}
	for itemId in available do
		table.insert(plain, itemId)
	end
	local mutated: { string } = {}
	for itemId in indexed do
		local base = string.split(itemId, "+")[1]
		if base ~= itemId and produce[base] and Inventory.find(itemId) then
			table.insert(mutated, itemId)
		end
	end
	-- Sorted, so a draw depends on the roll alone.
	table.sort(plain)
	table.sort(mutated)
	return plain, mutated
end

-- A new order for the slot, or a wait when everything the garden can make is already asked for.
local function drawOrder(player: Player, state: State, slot: number): Progress.Order
	local economy = EconomyService.get(player)
	local level = if economy then economy.level else 1
	local active: { [string]: boolean } = {}
	for index, entry in state.saved.orders do
		if index ~= slot and entry.item then
			active[entry.item] = true
		end
	end
	local plain, mutated = candidates(player)
	local worth = Economy.scale(level)
	local wantMutated = #mutated > 0 and random:NextNumber() < Progress.ORDER_MUTATED_CHANCE
	for _, pool in { if wantMutated then mutated else plain, plain } do
		-- Prefer an item whose count is not pushed up or down to the limits.
		local free: { string } = {}
		local fitting: { string } = {}
		for _, itemId in pool do
			local value = Inventory.getItem(itemId).value
			if value and not active[itemId] then
				table.insert(free, itemId)
				local asked = worth / value
				if pool == mutated or (asked >= Progress.ORDER_MIN and asked <= Progress.ORDER_MAX) then
					table.insert(fitting, itemId)
				end
			end
		end
		local choices = if #fitting > 0 then fitting else free
		if #choices > 0 then
			local itemId = choices[random:NextInteger(1, #choices)]
			local value = Inventory.getItem(itemId).value :: number
			return { item = itemId, count = Progress.orderCount(value, level, pool == mutated) }
		end
	end
	return { waitUntil = os.time() + Progress.SKIP_SECONDS }
end

-- Fills empty slots and slots whose wait is over; returns whether anything changed.
local function refillOrders(player: Player, state: State): boolean
	local changed = false
	for slot = 1, Progress.ORDER_SLOTS do
		local entry = state.saved.orders[slot]
		if not entry or (not entry.item and (entry.waitUntil or 0) <= os.time()) then
			state.saved.orders[slot] = drawOrder(player, state, slot)
			changed = true
		end
	end
	return changed
end

-- The seed the next bonus order gives: one rarity above the best crop the garden has discovered.
local function bonusSeed(player: Player): string
	local garden = GardenService.snapshot(player)
	local best = 1
	for cropId, found in if garden then garden.discovered else {} do
		if found and World.CROPS[cropId] then
			best = math.max(best, rarityOrder[World.CROPS[cropId].rarity])
		end
	end
	return seedOf(best + 1)
end

local function deliver(player: Player, state: State, slot: number): ()
	local entry = state.saved.orders[slot]
	local itemId, asked = entry and entry.item, entry and entry.count
	local item = if itemId then Inventory.find(itemId) else nil
	if not itemId or not asked or not item or not item.value then
		return
	end
	local have = 0
	local slots: { any } = InventoryService.snapshot(player) or {}
	for _, stack in slots do
		if stack and stack.itemId == itemId then
			have += stack.count
		end
	end
	if have < asked then
		Remotes.Notify:FireClient(player, `You need {asked} {item.name} in your inventory.`, "Error", { item = itemId })
		return
	end
	local seed = if Progress.ordersToBonus(state.saved.stats.ordersFilled) == 1 then bonusSeed(player) else nil
	if seed and not InventoryService.canGive(player, seed, 1) then
		Remotes.Notify:FireClient(player, "Make room in your inventory for the bonus seed first.", "Error")
		return
	end
	-- Checked above; nothing yields from here to the last line.
	local taken = InventoryService.take(player, itemId, asked)
	assert(taken == asked, "ProgressService: the inventory changed during a delivery")
	local reward = Progress.orderReward(item.value, asked)
	state.saved.orders[slot] = { waitUntil = 0 }
	EconomyService.add(player, reward.coins)
	EconomyService.addXp(player, reward.xp)
	count(player, state, "ordersFilled", 1)
	Remotes.Notify:FireClient(player, `Order filled! +{reward.coins} coins`, "Reward")
	if seed then
		InventoryService.give(player, seed, 1)
		Remotes.Notify:FireClient(player, `Bonus {Inventory.getItem(seed).name} for your fifth order!`, "Rare", { item = seed })
	end
	GardenEvents.OrderFilled:Fire(player, itemId, asked)
	state.saved.orders[slot] = drawOrder(player, state, slot)
end

---------------------------------------------------------------- requests

local function act(player: Player, action: unknown, slot: unknown): ()
	local state = states[player]
	if
		not state
		or state.batching
		or player:GetAttribute("DataReady") ~= true
		or typeof(action) ~= "string"
		or typeof(slot) ~= "number"
		or slot % 1 ~= 0
		or slot < 1
	then
		return
	end
	local now = os.clock()
	if now - state.lastAction < ACTION_COOLDOWN then
		return
	end
	state.lastAction = now
	state.batching = true
	if action == "ClaimDaily" and slot <= Progress.QUEST_SLOTS then
		claimDaily(player, state, slot, false)
	elseif action == "DeliverOrder" and slot <= Progress.ORDER_SLOTS then
		deliver(player, state, slot)
	elseif action == "SkipOrder" and slot <= Progress.ORDER_SLOTS then
		local entry = state.saved.orders[slot]
		if entry and entry.item then
			state.saved.orders[slot] = { waitUntil = os.time() + Progress.SKIP_SECONDS }
		end
	end
	state.batching = false
	-- Every request is answered, so a pending button always wakes.
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
		lastAction = -math.huge,
		clockAt = os.clock(),
		readiness = nil,
	}
	states[player] = state
	state.readiness = player:GetAttributeChangedSignal("DataReady"):Connect(function()
		-- Loading time and time in the save menu never belong to a garden's playtime.
		state.clockAt = os.clock()
	end)
	rollDay(player, state)
	for _, entry in state.saved.daily.quests do
		local quest = Progress.getQuest(entry.id)
		if quest then
			local amount, goal = questProgress(state, entry, quest)
			-- Already done when saved: claimable, without announcing it again.
			state.done[entry.id] = entry.claimed or amount >= goal
		end
	end
	refillOrders(player, state)
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
	GardenEvents.Bought:Connect(function(player: Player, _: string, bought: number)
		observe(player, "itemsBought", bought)
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
	-- In Studio, a line in the output at each level: how long the garden has been played and
	-- what it has earned, for timing a fresh garden against the balance model (economy.md §
	-- Balance). Play time is the saved stat, so the lines carry on across sittings.
	if RunService:IsStudio() then
		GardenEvents.LevelUp:Connect(function(player: Player, level: number)
			local state = states[player]
			if state then
				local stats = state.saved.stats
				print(
					string.format(
						"Pace: level %d at %d:%02d played, %d coins earned, %d crops harvested",
						level,
						stats.playtime // 60,
						stats.playtime % 60,
						stats.coinsEarned,
						stats.cropsHarvested
					)
				)
			end
		end)
	end
	Remotes.Progress.OnServerEvent:Connect(act)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, state in states do
				if player:GetAttribute("DataReady") ~= true then
					state.clockAt = now
					continue
				end
				local seconds = math.floor(now - state.clockAt)
				state.clockAt += seconds
				observe(player, "playtime", seconds)
				if not state.batching then
					-- A new day's quests, and orders whose wait is over.
					state.batching = true
					local rolled = rollDay(player, state)
					local refilled = refillOrders(player, state)
					state.batching = false
					if rolled or refilled then
						sync(player, state)
					end
				end
			end
		end
	end)
end

return ProgressService
