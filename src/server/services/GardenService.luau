-- GardenService: per-player seed stock, discoveries and stall transactions. DataService
-- loads/snapshots this state. Purchases and sales never yield between validation and mutation.
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
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
type State = { seedStock: { [string]: number }, restockAt: number, discovered: { [string]: boolean } }
local states: { [Player]: State } = {}
local lastAction: { [Player]: number } = {}
local seeds: { [string]: World.Crop } = {}
local random = Random.new()
for _, crop in World.CROPS do
	seeds[crop.seed] = crop
end
local GardenService = {}

local function restock(state: State): boolean
	local nextAt = (math.floor(os.time() / Content.RESTOCK_SECONDS) + 1) * Content.RESTOCK_SECONDS
	if state.restockAt == nextAt then
		return false
	end
	state.restockAt = nextAt
	state.seedStock = {}
	for seed, crop in seeds do
		local band = Content.RARITIES[crop.rarity]
		state.seedStock[seed] = if random:NextNumber() < band.chance then random:NextInteger(band.min, band.max) else 0
	end
	return true
end

local function sync(player: Player, state: State)
	Remotes.ShopSync:FireClient(player, { restockAt = state.restockAt, stock = table.clone(state.seedStock) })
end

function GardenService.load(
	player: Player,
	stock: { [string]: number },
	restockAt: number,
	discovered: { [string]: boolean }
)
	local state: State = { seedStock = {}, restockAt = restockAt, discovered = {} }
	for seed, crop in seeds do
		local amount = stock[seed]
		state.seedStock[seed] = if typeof(amount) == "number"
				and amount % 1 == 0
				and amount >= 0
				and amount <= Content.RARITIES[crop.rarity].max
			then amount
			else 0
	end
	for cropId in World.CROPS do
		state.discovered[cropId] = discovered[cropId] == true
	end
	states[player] = state
	restock(state)
	sync(player, state)
end

function GardenService.snapshot(player: Player): State?
	local state = states[player]
	return if state
		then {
			seedStock = table.clone(state.seedStock),
			restockAt = state.restockAt,
			discovered = table.clone(state.discovered),
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
	EconomyService.addXp(player, Content.RARITIES[World.CROPS[cropId].rarity].xp)
	if mutation then
		Remotes.Notify:FireClient(player, `{mutation} {World.CROPS[cropId].name}!`)
	end
end

local function refusal(player: Player, stall: string): string?
	if player:GetAttribute("DataReady") ~= true or not states[player] then
		return "Your garden is still loading."
	end
	if not Hub.inReach(player, stall) then
		return "Move closer to the stall."
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
	return nil
end

local function buy(player: Player, shopId: unknown, itemId: unknown, count: unknown)
	local state = states[player]
	if not state or typeof(shopId) ~= "string" or not Hub.STALLS[shopId] then
		return
	end
	restock(state)
	local message = "Choose a valid amount."
	if typeof(itemId) == "string" and typeof(count) == "number" and count % 1 == 0 and count >= 1 and count <= 99 then
		local reason = refusal(player, shopId)
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
				message = `Bought {count} {crop.name} Seeds`
			end
		elseif offer then
			message = buyOffer(player, offer, count) or `Bought {Inventory.getItem(itemId).name}`
		end
	end
	if shopId == "SeedShop" then
		sync(player, state)
	end
	Remotes.Notify:FireClient(player, message)
end

local function sell(player: Player, mode: unknown)
	if mode ~= "Held" and mode ~= "All" then
		return
	end
	local reason = refusal(player, "SellStand")
	if reason then
		InventoryService.resync(player)
		Remotes.Notify:FireClient(player, reason)
		return
	end
	local sold = InventoryService.takeWhere(player, mode == "Held", function(id: string): boolean
		return Inventory.getItem(id).value ~= nil
	end)
	local coins = 0
	for id, count in sold do
		coins += (Inventory.getItem(id).value or 0) * count
	end
	EconomyService.add(player, coins)
	EconomyService.addXp(player, math.floor(coins / 10))
	Remotes.Notify:FireClient(player, if coins > 0 then `+{coins} coins` else "Hold a crop or product to sell it.")
end
function GardenService.init()
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
			restock(state)
			sync(player, state)
		end
	end)
	while true do
		task.wait(1)
		for player, state in states do
			if player.Parent == Players and restock(state) then
				sync(player, state)
			end
		end
	end
end
return GardenService
