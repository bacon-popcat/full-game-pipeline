-- InventoryService: owns every player's inventory and what their hand holds. Clients
-- send intents -- move a stack, pick a hotbar slot -- which are validated and applied
-- with the shared Inventory rules; every intent answers with a full snapshot, so a
-- rejected one also undoes the client's prediction.
--
-- The hand always holds the stack in the selected hotbar slot. Rather than tracking it
-- separately, `refreshHeld` re-derives the hand after anything that can change that
-- slot, swapping the Tool only when the item actually changed.
--
-- DataService supplies slots after opening the profile and snapshots them before release.
-- Player-facing mutations and grants wait for DataReady; this service never grants a test kit.

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
	return if state and player:GetAttribute("DataReady") == true then selectedItemId(state) else nil
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

-- Removes whole matching stacks in one transaction and publishes one final inventory.
-- Sell Stand supplies the predicate; pricing and currency stay outside inventory ownership.
function InventoryService.takeWhere(
	player: Player,
	heldOnly: boolean,
	accepts: (string) -> boolean
): { [string]: number }
	local state = states[player]
	local counts: { [string]: number } = {}
	if not state or player:GetAttribute("DataReady") ~= true then
		return counts
	end
	local first = if heldOnly then state.selected else 1
	local last = if heldOnly then state.selected else Inventory.SLOT_COUNT
	for index = first, last do
		local stack = Inventory.stackAt(state.slots, index)
		if stack and accepts(stack.itemId) then
			counts[stack.itemId] = (counts[stack.itemId] or 0) + stack.count
			state.slots[index] = false
		end
	end
	sync(player, state)
	refreshHeld(player, state)
	return counts
end

function InventoryService.resync(player: Player)
	local state = states[player]
	if state then
		sync(player, state)
	end
end

function InventoryService.canGive(player: Player, itemId: string, count: number): boolean
	local state = states[player]
	return player:GetAttribute("DataReady") == true and state ~= nil and Inventory.canAdd(state.slots, itemId, count)
end

-- Whether all of `counts` fits together, so a multi-item drop is given whole or not at all.
function InventoryService.canGiveAll(player: Player, counts: { [string]: number }): boolean
	local state = states[player]
	return state ~= nil and Inventory.canAddAll(state.slots, counts)
end

-- Adds items to the player's inventory. Returns how many did not fit.
function InventoryService.give(player: Player, itemId: string, count: number): number
	local state = states[player]
	if not state or player:GetAttribute("DataReady") ~= true then
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
	if player:GetAttribute("DataReady") ~= true then
		return
	end
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
	if player:GetAttribute("DataReady") ~= true then
		return
	end
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

function InventoryService.load(player: Player, slots: Inventory.Slots)
	local state: State = { slots = slots, selected = 1, held = nil, heldItemId = nil }
	states[player] = state

	local function onCharacter(character: Model)
		character:WaitForChild("Humanoid")
		if states[player] ~= state then
			return
		end
		refreshHeld(player, state)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	sync(player, state)
end

function InventoryService.release(player: Player)
	local state = states[player]
	if state and state.held then
		state.held:Destroy()
	end
	states[player] = nil
end

function InventoryService.snapshot(player: Player): Inventory.Slots?
	local state = states[player]
	if not state then
		return nil
	end
	local slots = Inventory.emptySlots()
	for index = 1, Inventory.SLOT_COUNT do
		local stack = Inventory.stackAt(state.slots, index)
		slots[index] = if stack then table.clone(stack) else false
	end
	return slots
end

function InventoryService.init()
	Remotes.InventoryMove.OnServerEvent:Connect(onMove)
	Remotes.InventorySelect.OnServerEvent:Connect(onSelect)
end

return InventoryService
