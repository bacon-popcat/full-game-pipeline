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

local function buy(player: Player, seedId: unknown, count: unknown)
	local state = states[player]
	if not state then
		return
	end
	restock(state)
	local message = "Choose a valid seed amount."
	if typeof(seedId) == "string" and typeof(count) == "number" and count % 1 == 0 and count >= 1 and seeds[seedId] then
		local crop = seeds[seedId]
		local reason = refusal(player, "SeedShop")
		if reason then
			message = reason
		elseif count > (state.seedStock[seedId] or 0) then
			message = "Not enough seeds in stock."
		elseif not InventoryService.canGive(player, seedId, count) then
			message = "Your inventory is full."
		elseif not EconomyService.trySpend(player, crop.price * count) then
			message = "You need more coins."
		else
			InventoryService.give(player, seedId, count)
			state.seedStock[seedId] -= count
			message = `Bought {count} {crop.name} Seeds`
		end
	end
	sync(player, state)
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
