-- GardenService: per-player seed stock, discoveries, the Index and stall transactions.
-- DataService loads/snapshots this state. `discovered` holds crops harvested (onboarding reads
-- it); `indexed` holds every item id the player has had in their inventory or harvested, which
-- the client's Index shows (IndexSync). Purchases and sales never yield between validation and mutation.
-- Values in Items already include mutation multipliers; selling must not multiply twice.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Hub = require(ReplicatedStorage.Shared.Hub)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local World = require(ReplicatedStorage.Shared.World)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local GardenEvents = require(game:GetService("ServerScriptService").Libraries.GardenEvents)
local Bonuses = require(game:GetService("ServerScriptService").Libraries.Bonuses)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
-- A harvest whose mutations multiply its value at least this much (Shocked and up) gets a notice.
local RARE_MULTIPLIER = 10
type State = {
	seedStock: { [string]: number },
	restockAt: number,
	discovered: { [string]: boolean },
	indexed: { [string]: boolean },
}
local states: { [Player]: State } = {}
local lastAction: { [Player]: number } = {}
local seeds: { [string]: World.Crop } = {}
local random = Random.new()
for _, crop in World.CROPS do
	seeds[crop.seed] = crop
end
local GardenService = {}

local function restock(player: Player, state: State): boolean
	local nextAt = (math.floor(os.time() / Content.RESTOCK_SECONDS) + 1) * Content.RESTOCK_SECONDS
	if state.restockAt == nextAt then
		return false
	end
	state.restockAt = nextAt
	state.seedStock = {}
	for seed, crop in seeds do
		local band = Content.RARITIES[crop.rarity]
		state.seedStock[seed] = if random:NextNumber() < band.chance then random:NextInteger(band.min, band.max) else 0
		if state.seedStock[seed] > 0 then
			state.seedStock[seed] += Bonuses.get(player, "seedStock")
		end
	end
	return true
end

local function sync(player: Player, state: State)
	Remotes.ShopSync:FireClient(player, { restockAt = state.restockAt, stock = table.clone(state.seedStock) })
end

local function syncIndex(player: Player, state: State)
	local ids = {}
	for itemId in state.indexed do
		table.insert(ids, itemId)
	end
	Remotes.IndexSync:FireClient(player, ids)
end

-- Adds an item to the player's Index the first time they get it.
function GardenService.discover(player: Player, itemId: string)
	local state = states[player]
	if state and not state.indexed[itemId] and Inventory.find(itemId) then
		state.indexed[itemId] = true
		syncIndex(player, state)
	end
end

function GardenService.load(
	player: Player,
	stock: { [string]: number },
	restockAt: number,
	discovered: { [string]: boolean },
	indexed: { [string]: boolean }
)
	local state: State = { seedStock = {}, restockAt = restockAt, discovered = {}, indexed = {} }
	for seed, crop in seeds do
		local amount = stock[seed]
		state.seedStock[seed] = if typeof(amount) == "number"
				and amount % 1 == 0
				and amount >= 0
				and amount <= Content.RARITIES[crop.rarity].max + Bonuses.get(player, "seedStock")
			then amount
			else 0
	end
	for cropId in World.CROPS do
		state.discovered[cropId] = discovered[cropId] == true
	end
	for itemId, had in indexed do
		if had == true and typeof(itemId) == "string" and Inventory.find(itemId) then
			state.indexed[itemId] = true
		end
	end
	-- What the player holds now counts too, so saves from before the Index start with it.
	for _, stack in InventoryService.snapshot(player) or {} do
		if stack then
			state.indexed[stack.itemId] = true
		end
	end
	states[player] = state
	restock(player, state)
	sync(player, state)
	syncIndex(player, state)
end

function GardenService.snapshot(player: Player): State?
	local state = states[player]
	return if state
		then {
			seedStock = table.clone(state.seedStock),
			restockAt = state.restockAt,
			discovered = table.clone(state.discovered),
			indexed = table.clone(state.indexed),
		}
		else nil
end

function GardenService.release(player: Player)
	states[player] = nil
	lastAction[player] = nil
end

function GardenService.harvest(player: Player, cropId: string, mutation: string?)
	local state = states[player]
	if not state or player:GetAttribute("DataReady") ~= true then
		return
	end
	state.discovered[cropId] = true
	GardenService.discover(player, World.CROPS[cropId].produce .. (if mutation then "+" .. mutation else ""))
	EconomyService.addXp(player, Content.RARITIES[World.CROPS[cropId].rarity].xp)
	-- Only a rare mutation is worth a notice; Wet comes with every sprinkler.
	local names = if mutation then Mutations.parse(mutation) else nil
	if names and Mutations.multiplier(names) >= RARE_MULTIPLIER then
		Remotes.Notify:FireClient(
			player,
			`{Inventory.getItem(World.CROPS[cropId].produce .. "+" .. mutation).name}!`,
			"Rare"
		)
	end
end

-- Shops and selling work from anywhere (their HUD windows), so reach is not checked.
local function refusal(player: Player): string?
	if player:GetAttribute("DataReady") ~= true or not states[player] then
		return "Your garden is still loading."
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.2 then
		return "Please wait a moment."
	end
	lastAction[player] = now
	return nil
end

local function countOf(player: Player, itemId: string): number
	local count = 0
	for _, stack in InventoryService.snapshot(player) or Inventory.emptySlots() do
		if stack and stack.itemId == itemId then
			count += stack.count
		end
	end
	return count
end

-- "4 Gear and 2 Steel Frame": the parts an offer needs, in words.
local function partsText(parts: { [string]: number }): string
	local names = {}
	for itemId, count in parts do
		table.insert(names, `{count} {Inventory.getItem(itemId).name}`)
	end
	table.sort(names)
	return if #names > 1 then table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names] else names[1]
end

-- Why a Gear or Machine Shop purchase can't go ahead, or nil once it is paid for.
local function buyOffer(player: Player, offer: Shops.Offer, count: number): string?
	local item = Inventory.getItem(offer.itemId)
	local economy = EconomyService.get(player)
	if not economy or economy.level < offer.level then
		return `Reach level {offer.level} to buy this.`
	elseif item.kind == "Tool" and (count ~= 1 or countOf(player, offer.itemId) > 0) then
		return `You already have a {item.name}.`
	elseif not InventoryService.canGive(player, offer.itemId, count) then
		return "Your inventory is full."
	end
	local parts = offer.parts or {}
	local needed: { [string]: number } = {}
	for itemId, each in parts do
		needed[itemId] = each * count
	end
	for itemId, amount in needed do
		if countOf(player, itemId) < amount then
			return `You need {partsText(needed)}.`
		end
	end
	if not EconomyService.trySpend(player, offer.price * count) then
		return "You need more coins."
	end
	for itemId, amount in needed do
		InventoryService.take(player, itemId, amount)
	end
	InventoryService.give(player, offer.itemId, count)
	GardenEvents.Bought:Fire(player, offer.itemId, count)
	return nil
end

local function buy(player: Player, shopId: unknown, itemId: unknown, count: unknown)
	local state = states[player]
	if not state or typeof(shopId) ~= "string" or not Hub.STALLS[shopId] then
		return
	end
	restock(player, state)
	local message = "Choose a valid amount."
	local bought = false
	if typeof(itemId) == "string" and typeof(count) == "number" and count % 1 == 0 and count >= 1 and count <= 99 then
		local reason = refusal(player)
		local crop = if shopId == "SeedShop" then seeds[itemId] else nil
		local offer = Shops.find(shopId, itemId)
		if reason then
			message = reason
		elseif crop then
			if count > (state.seedStock[itemId] or 0) then
				message = "Not enough seeds in stock."
			elseif not InventoryService.canGive(player, itemId, count) then
				message = "Your inventory is full."
			elseif not EconomyService.trySpend(player, crop.price * count) then
				message = "You need more coins."
			else
				InventoryService.give(player, itemId, count)
				state.seedStock[itemId] -= count
				GardenEvents.Bought:Fire(player, itemId, count)
				message = `Bought {count} {crop.name} Seeds`
				bought = true
			end
		elseif offer then
			local refused = buyOffer(player, offer, count)
			message = refused or `Bought {Inventory.getItem(itemId).name}`
			bought = refused == nil
		end
	end
	if shopId == "SeedShop" then
		sync(player, state)
	end
	Remotes.Notify:FireClient(player, message, if bought then "Success" else "Error")
end

local function sell(player: Player, mode: unknown)
	if mode ~= "Held" and mode ~= "All" then
		return
	end
	local reason = refusal(player)
	if reason then
		InventoryService.resync(player)
		Remotes.Notify:FireClient(player, reason, "Error")
		return
	end
	local sold = InventoryService.takeWhere(player, mode == "Held", function(id: string): boolean
		return Inventory.getItem(id).value ~= nil
	end)
	local coins = 0
	for id, count in sold do
		coins += (Inventory.getItem(id).value or 0) * count
	end
	coins = math.floor(coins * (1 + Bonuses.get(player, "sellPrice")) + 1e-9)
	EconomyService.add(player, coins)
	EconomyService.addXp(player, math.floor(coins / 10))
	if coins > 0 then
		Remotes.Notify:FireClient(player, `Sold for {coins} coins`, "Success")
	else
		Remotes.Notify:FireClient(player, "Hold a crop or product to sell it.", "Error")
	end
	if coins > 0 then
		GardenEvents.Sold:Fire(player, coins, nil)
	end
end
function GardenService.init()
	InventoryService.setGainedHandler(GardenService.discover)
	Remotes.ShopBuy.OnServerEvent:Connect(buy)
	Remotes.Sell.OnServerEvent:Connect(sell)
	-- Prompts refresh the opening screen even if its initial load sync preceded HUD binding.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local counter = prompt.Parent
		local stall = if counter then counter.Parent else nil
		local state = states[player]
		if
			state
			and stall
			and stall.Name == "SeedShop"
			and stall.Parent == workspace:FindFirstChild("Hub")
			and prompt.Name == "Prompt"
			and player:GetAttribute("DataReady") == true
			and Hub.inReach(player, "SeedShop")
		then
			restock(player, state)
			sync(player, state)
		end
	end)
	while true do
		task.wait(1)
		for player, state in states do
			if player.Parent == Players and restock(player, state) then
				sync(player, state)
			end
		end
	end
end
return GardenService
