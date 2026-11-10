-- WelcomeService: the daily gift, the welcome-back summary and offline coins for a loaded
-- garden (rules and numbers: Shared/Welcome). On load it counts a new day played, works out
-- coins for the time away from the saved bin rate, and tells the client what to greet the
-- player with; nothing is paid until the player collects, and what is owed is saved, so closing
-- the card or leaving loses nothing. While the garden is open it keeps Shipping Bin coins in
-- buckets for the next rate. DataService loads it after the plot, research and economy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local Welcome = require(ReplicatedStorage.Shared.Welcome)
local World = require(ReplicatedStorage.Shared.World)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local BuildService = require(script.Parent.BuildService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local ResearchService = require(script.Parent.ResearchService)
local WorldService = require(script.Parent.WorldService)

local COLLECT_COOLDOWN = 0.5
local BIN = "ShippingBin"

type State = {
	saved: Welcome.Saved,
	index: number,
	-- Seconds since the garden was last saved open, as found at load.
	away: number,
	-- Finished buckets of bin coins, oldest first, and the one filling now.
	buckets: { number },
	bucket: number,
	bucketAt: number,
	lastCollect: number,
}
local states: { [Player]: State } = {}
local seedsByRarity: { [string]: { string } } = {}
for _, crop in World.CROPS do
	seedsByRarity[crop.rarity] = seedsByRarity[crop.rarity] or {}
	table.insert(seedsByRarity[crop.rarity], crop.seed)
end
for _, seeds in seedsByRarity do
	table.sort(seeds)
end
local random = Random.new()
local started = false
local WelcomeService = {}

-- The research project whose timer has run out and waits for Complete, by name.
local function readyResearch(player: Player): string?
	local research = ResearchService.snapshot(player)
	local active = if research then research.active else nil
	local project = if active then Research.get(active.id) else nil
	if active and project and Research.isReady(active.startedAt + active.seconds, os.time()) then
		return project.name
	end
	return nil
end

-- `greet` asks the client to show the card; only the load sync does.
local function sync(player: Player, state: State, greet: boolean): ()
	local economy = EconomyService.get(player)
	local level = if economy then economy.level else 1
	local owed = state.saved.giftOwed
	local gift = if owed > 0 then Welcome.gift(owed) else nil
	Remotes.WelcomeSync:FireClient(player, {
		greet = greet,
		away = state.away,
		ripe = WorldService.ripeCount(state.index),
		research = readyResearch(player),
		coins = state.saved.coinsOwed,
		gift = if gift
			then {
				day = (owed - 1) % #Welcome.GIFTS + 1,
				coins = Welcome.giftCoins(gift, level),
				rarity = gift.rarity,
				count = gift.count,
			}
			else nil,
	})
end

local function collect(player: Player, action: unknown): ()
	local state = states[player]
	if not state or action ~= "Collect" or player:GetAttribute("DataReady") ~= true then
		return
	end
	local now = os.clock()
	if now - state.lastCollect < COLLECT_COOLDOWN then
		return
	end
	state.lastCollect = now
	local saved = state.saved
	local economy = EconomyService.get(player)
	local gift = if saved.giftOwed > 0 then Welcome.gift(saved.giftOwed) else nil
	local seed: string? = nil
	if gift and gift.rarity then
		local seeds = seedsByRarity[gift.rarity]
		local picked = seeds[random:NextInteger(1, #seeds)]
		seed = picked
		-- All or nothing: a seed that cannot fit leaves the gift and the coins owed.
		if not InventoryService.canGive(player, picked, gift.count or 1) then
			Remotes.Notify:FireClient(player, "Make room in your inventory for your gift first.", "Error")
			sync(player, state, false)
			return
		end
	end
	-- Clear what is owed before paying; nothing below yields.
	local coins = saved.coinsOwed
	saved.coinsOwed = 0
	saved.giftOwed = 0
	if gift then
		coins += Welcome.giftCoins(gift, if economy then economy.level else 1)
	end
	if coins > 0 then
		EconomyService.add(player, coins)
		Remotes.Notify:FireClient(player, `Collected! +{coins} coins`, "Reward")
	end
	if gift and seed then
		local count = gift.count or 1
		InventoryService.give(player, seed, count)
		Remotes.Notify:FireClient(player, `Daily gift! {Inventory.getItem(seed).name} x{count}`, "Rare")
	end
	sync(player, state, false)
end

function WelcomeService.load(player: Player, value: unknown, index: number): ()
	WelcomeService.init()
	local saved = Welcome.sanitize(value)
	local now = os.time()
	local today = Progress.day(now)
	local away = if saved.leftAt > 0 then math.max(0, now - saved.leftAt) else 0
	if saved.leftAt == 0 and saved.giftDay == 0 then
		-- A garden's first day (or its first since gifts existed) has no gift; they start tomorrow.
		saved.giftDay = today
	elseif saved.giftDay ~= today then
		saved.giftDay = today
		-- A gift still waiting is kept, and the count waits with it, so none is skipped.
		if saved.giftOwed == 0 then
			saved.days += 1
			saved.giftOwed = saved.days
		end
	end
	if away >= Welcome.AWAY_MIN and saved.binRate > 0 then
		for _, block in BuildService.snapshot(player, index) do
			if block.itemId == BIN then
				saved.coinsOwed += Welcome.offlineCoins(saved.binRate, away)
				break
			end
		end
	end
	local state: State = {
		saved = saved,
		index = index,
		away = away,
		buckets = {},
		bucket = 0,
		bucketAt = os.clock(),
		lastCollect = -math.huge,
	}
	states[player] = state
	sync(player, state, saved.giftOwed > 0 or saved.coinsOwed > 0 or away >= Welcome.AWAY_MIN)
end

-- What to save now: the garden is open, so this moment is when it was last seen.
function WelcomeService.snapshot(player: Player): Welcome.Saved?
	local state = states[player]
	if not state then
		return nil
	end
	local saved = table.clone(state.saved)
	saved.leftAt = os.time()
	saved.binRate = Welcome.rate(state.buckets) or saved.binRate
	return saved
end

function WelcomeService.release(player: Player): ()
	states[player] = nil
end

function WelcomeService.init(): ()
	if started then
		return
	end
	started = true
	GardenEvents.Sold:Connect(function(player: Player, coins: number, at: Vector3?)
		local state = states[player]
		if state and at ~= nil and coins > 0 then
			state.bucket += coins
		end
	end)
	Remotes.Welcome.OnServerEvent:Connect(collect)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, state in states do
				if player:GetAttribute("DataReady") ~= true then
					-- The save menu's time is not play: start the bucket over.
					state.bucket = 0
					state.bucketAt = now
				elseif now - state.bucketAt >= Welcome.BUCKET_SECONDS then
					table.insert(state.buckets, state.bucket)
					if #state.buckets > Welcome.BUCKETS then
						table.remove(state.buckets, 1)
					end
					state.bucket = 0
					state.bucketAt = now
				end
			end
		end
	end)
end

-- The seed rarities gifts use must have crops.
for _, gift in Welcome.GIFTS do
	assert(
		not gift.rarity or (Content.RARITIES[gift.rarity] and seedsByRarity[gift.rarity]),
		"Welcome: a gift's rarity has no seeds"
	)
end
assert(seedsByRarity[Welcome.GRAND_RARITY], "Welcome: the grand gift's rarity has no seeds")

return WelcomeService
