-- InventoryService: owns every player's inventory and what their hand holds. Clients
-- send intents -- move a stack, pick a hotbar slot -- which are validated and applied
-- with the shared Inventory rules; every intent answers with a full snapshot, so a
-- rejected one also undoes the client's prediction.
--
-- The hand always holds the stack in the selected hotbar slot. Rather than tracking it
-- separately, `refreshHeld` re-derives the hand after anything that can change that
-- slot, swapping the Tool only when the item actually changed.
--
-- Not persisted: a player starts with one full stack of every tool, block and machine (a
-- test kit) and loses it all on leaving. Resources are never handed out: they come from
-- the world (WorldService) and the machines (FactoryService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HeldItem = require(ServerScriptService.Libraries.HeldItem)

type State = {
	slots: Inventory.Slots,
	selected: number,
	held: Tool?,
	heldItemId: string?,
}

local InventoryService = {}

local states: { [Player]: State } = {}

local function sync(player: Player, state: State)
	Remotes.InventorySync:FireClient(player, { slots = state.slots, selected = state.selected })
end

local function selectedItemId(state: State): string?
	local stack = if state.selected > 0 then Inventory.stackAt(state.slots, state.selected) else nil
	return if stack then stack.itemId else nil
end

local function refreshHeld(player: Player, state: State)
	local wanted = selectedItemId(state)
	local character = player.Character
	local current = state.held
	if current and current.Parent == character and state.heldItemId == wanted then
		return
	end
	if current then
		current:Destroy()
	end
	state.held = nil
	state.heldItemId = nil

	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not wanted or not humanoid or humanoid.Health <= 0 then
		return
	end
	local tool = HeldItem.create(wanted)
	if not tool then
		return
	end
	state.held = tool
	state.heldItemId = wanted
	humanoid:EquipTool(tool)
end

-- The item in the player's hand, or nil.
function InventoryService.getHeldItemId(player: Player): string?
	local state = states[player]
	return if state then selectedItemId(state) else nil
end

-- Uses up one of the held item if the hand still holds `itemId`. Returns whether it did.
function InventoryService.consumeHeld(player: Player, itemId: string): boolean
	local state = states[player]
	if not state or state.selected == 0 or not Inventory.takeOne(state.slots, state.selected, itemId) then
		return false
	end
	sync(player, state)
	refreshHeld(player, state)
	return true
end

-- Takes up to `max` of the held item if the hand still holds `itemId`. Returns how many
-- it took.
function InventoryService.takeHeld(player: Player, itemId: string, max: number): number
	local state = states[player]
	if not state or state.selected == 0 then
		return 0
	end
	local taken = Inventory.take(state.slots, state.selected, itemId, max)
	if taken > 0 then
		sync(player, state)
		refreshHeld(player, state)
	end
	return taken
end

-- Takes up to `max` of `itemId` from anywhere in the inventory, backpack first so the hand
-- is the last thing emptied. Returns how many it took.
function InventoryService.take(player: Player, itemId: string, max: number): number
	local state = states[player]
	if not state then
		return 0
	end
	local taken = 0
	for index = Inventory.SLOT_COUNT, 1, -1 do
		if taken >= max then
			break
		end
		taken += Inventory.take(state.slots, index, itemId, max - taken)
	end
	if taken > 0 then
		sync(player, state)
		refreshHeld(player, state)
	end
	return taken
end

function InventoryService.canGive(player: Player, itemId: string, count: number): boolean
	local state = states[player]
	return state ~= nil and Inventory.canAdd(state.slots, itemId, count)
end

-- Adds items to the player's inventory. Returns how many did not fit.
function InventoryService.give(player: Player, itemId: string, count: number): number
	local state = states[player]
	if not state then
		return count
	end
	local left = Inventory.add(state.slots, itemId, count)
	if left < count then
		sync(player, state)
		refreshHeld(player, state)
	end
	return left
end

local function onMove(player: Player, from: unknown, to: unknown)
	local state = states[player]
	if not state or typeof(from) ~= "number" or typeof(to) ~= "number" then
		return
	end
	if Inventory.isSlotIndex(from) and Inventory.isSlotIndex(to) and Inventory.move(state.slots, from, to) then
		refreshHeld(player, state)
	end
	sync(player, state)
end

local function onSelect(player: Player, index: unknown)
	local state = states[player]
	if not state or typeof(index) ~= "number" then
		return
	end
	if index % 1 == 0 and index >= 0 and index <= Inventory.HOTBAR_SIZE then
		state.selected = index
		refreshHeld(player, state)
	end
	sync(player, state)
end

local function onPlayerAdded(player: Player)
	local slots = Inventory.emptySlots()
	for _, item in Inventory.ITEMS do
		if item.kind ~= "Resource" then
			Inventory.add(slots, item.id, item.stack)
		end
	end
	local state: State = { slots = slots, selected = 1, held = nil, heldItemId = nil }
	states[player] = state

	local function onCharacter(character: Model)
		character:WaitForChild("Humanoid")
		refreshHeld(player, state)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	sync(player, state)
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if state and state.held then
		state.held:Destroy()
	end
	states[player] = nil
end

function InventoryService.init()
	Remotes.InventoryMove.OnServerEvent:Connect(onMove)
	Remotes.InventorySelect.OnServerEvent:Connect(onSelect)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return InventoryService
