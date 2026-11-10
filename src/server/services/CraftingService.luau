-- CraftingService: crafting and its tier. The Crafting window (opened from the side Crafting button,
-- anywhere) sends Remotes.Craft(recipeId, times); the rules are Shared/Crafting's, checked again
-- here against the live inventory, the player's research (server/libraries/Bonuses), level and
-- crafting tier. The tier is saved per garden (DataService loads and snapshots it) and replicates
-- as the player's BenchTier attribute; an upgrade recipe spends its inputs and raises it. The trade is first
-- tried on a copy of the inventory, inputs out and then the output in, so the room the inputs
-- free counts and it happens whole or not at all; then it is applied without yielding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)

-- Seconds between one player's crafts.
local COOLDOWN = 0.25

local CraftingService = {}

local lastCraft: { [Player]: number } = {}
local tiers: { [Player]: number } = {}

local function counter(slots: Inventory.Slots): (string) -> number
	return function(itemId: string): number
		local total = 0
		for index = 1, Inventory.SLOT_COUNT do
			local stack = Inventory.stackAt(slots, index)
			if stack and stack.itemId == itemId then
				total += stack.count
			end
		end
		return total
	end
end

-- Whether the trade fits: the inputs taken from a copy the way InventoryService.take takes
-- them (backpack first), then the output added.
local function fits(slots: Inventory.Slots, recipe: Crafting.Recipe, times: number): boolean
	local probe = table.clone(slots)
	for itemId, need in recipe.inputs do
		local left = need * times
		for index = Inventory.SLOT_COUNT, 1, -1 do
			if left <= 0 then
				break
			end
			left -= Inventory.take(probe, index, itemId, left)
		end
		if left > 0 then
			return false
		end
	end
	return recipe.count == 0 or Inventory.canAdd(probe, recipe.output, recipe.count * times)
end

local function craft(player: Player, recipeId: unknown, times: unknown)
	local now = os.clock()
	if
		typeof(recipeId) ~= "string"
		or typeof(times) ~= "number"
		or times % 1 ~= 0
		or times < 1
		or times > Crafting.MAX_TIMES
		or player:GetAttribute("DataReady") ~= true
		or now - (lastCraft[player] or 0) < COOLDOWN
	then
		return
	end
	lastCraft[player] = now
	local recipe = Crafting.get(recipeId)
	local slots = InventoryService.snapshot(player)
	local tier = tiers[player]
	local economy = EconomyService.get(player)
	if not recipe or not slots or not tier or not economy then
		return
	end
	local done = {}
	if recipe.research and Bonuses.has(player, recipe.research) then
		done[recipe.research] = true
	end
	local blocked = Crafting.blocker(recipe, times, done, counter(slots), tier, economy.level)
	if blocked then
		Remotes.Notify:FireClient(player, `{blocked}.`, "Error")
		return
	end
	if not fits(slots, recipe, times) then
		Remotes.Notify:FireClient(player, "Your inventory is full.", "Error")
		return
	end
	for itemId, need in recipe.inputs do
		local taken = InventoryService.take(player, itemId, need * times)
		assert(taken == need * times, "CraftingService: the inventory changed during a craft")
	end
	if recipe.upgrade then
		tiers[player] = recipe.upgrade
		player:SetAttribute("BenchTier", recipe.upgrade)
		Remotes.Notify:FireClient(player, `Crafting upgraded to {Crafting.TIERS[recipe.upgrade].name}!`, "Reward")
		GardenEvents.Crafted:Fire(player, recipe.id, times)
		return
	end
	local made = recipe.count * times
	InventoryService.give(player, recipe.output, made)
	Remotes.Notify:FireClient(player, `Crafted {made} {Inventory.getItem(recipe.output).name}.`, "Success")
	GardenEvents.Crafted:Fire(player, recipe.id, times)
end

function CraftingService.init()
	Remotes.Craft.OnServerEvent:Connect(craft)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCraft[player] = nil
		tiers[player] = nil
	end)
end

function CraftingService.load(player: Player, tier: unknown)
	local loaded = Crafting.sanitizeTier(tier)
	tiers[player] = loaded
	player:SetAttribute("BenchTier", loaded)
end

function CraftingService.snapshot(player: Player): number?
	return tiers[player]
end

function CraftingService.release(player: Player)
	tiers[player] = nil
	player:SetAttribute("BenchTier", nil)
end

return CraftingService
