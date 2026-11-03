-- CraftingService: the Crafting Bench. A player within reach of one of their own placed benches
-- sends Remotes.Craft(recipeId, times); the rules are Shared/Crafting's, checked again here against
-- the live inventory and the player's research (server/libraries/Bonuses). The trade is first
-- tried on a copy of the inventory, inputs out and then the output in, so the room the inputs
-- free counts and it happens whole or not at all; then it is applied without yielding.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Build = require(ReplicatedStorage.Shared.Build)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local InventoryService = require(script.Parent.InventoryService)

-- Seconds between one player's crafts.
local COOLDOWN = 0.25

local CraftingService = {}

local lastCraft: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Whether one of the player's own placed benches is within reach of where they stand.
local function atBench(player: Player, from: Vector3): boolean
	local placed = workspace:FindFirstChild("Placed")
	if not placed then
		return false
	end
	for _, model in placed:GetChildren() do
		local origin, rotation = model:GetAttribute("Origin"), model:GetAttribute("Rotation")
		if
			model:GetAttribute("ItemId") == Crafting.BENCH
			and model:GetAttribute("Owner") == player.UserId
			and typeof(origin) == "Vector3"
			and typeof(rotation) == "number"
		then
			local footprint = Build.footprint(Crafting.BENCH, rotation)
			if footprint and Build.inReach(from, origin, footprint) then
				return true
			end
		end
	end
	return false
end

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
	return Inventory.canAdd(probe, recipe.output, recipe.count * times)
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
	local root = rootOf(player)
	local slots = InventoryService.snapshot(player)
	if not recipe or not root or not slots then
		return
	end
	if not atBench(player, root.Position) then
		Remotes.Notify:FireClient(player, "Stand by your Crafting Bench to craft.")
		return
	end
	local done = {}
	if recipe.research and Bonuses.has(player, recipe.research) then
		done[recipe.research] = true
	end
	local blocked = Crafting.blocker(recipe, times, done, counter(slots))
	if blocked then
		Remotes.Notify:FireClient(player, `{blocked}.`)
		return
	end
	if not fits(slots, recipe, times) then
		Remotes.Notify:FireClient(player, "Your inventory is full.")
		return
	end
	for itemId, need in recipe.inputs do
		local taken = InventoryService.take(player, itemId, need * times)
		assert(taken == need * times, "CraftingService: the inventory changed during a craft")
	end
	local made = recipe.count * times
	InventoryService.give(player, recipe.output, made)
	Remotes.Notify:FireClient(player, `Crafted {made} {Inventory.getItem(recipe.output).name}.`)
	GardenEvents.Crafted:Fire(player, recipe.id, times)
end

function CraftingService.init()
	Remotes.Craft.OnServerEvent:Connect(craft)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastCraft[player] = nil
	end)
end

return CraftingService
