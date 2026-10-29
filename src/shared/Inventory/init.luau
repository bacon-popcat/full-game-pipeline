--!strict
-- Inventory: the shape of a player's inventory and the pure rules that change it. The
-- server runs these rules to decide; the client runs the same ones to predict its own
-- moves, so the UI answers at once and the next snapshot only ever corrects a miss.
--
-- Slots 1..HOTBAR_SIZE are the hotbar, the rest are the backpack. An empty slot is
-- `false`, never nil, so the list stays dense through a RemoteEvent (nil holes cut
-- arrays short in transit). `selected` is a hotbar index, 0 for an empty hand.
--
-- Item art is keyed by id; Shared/ItemArt owns where each kind keeps it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Items = require(ReplicatedStorage.Shared.Inventory.Items)

export type Kind = Items.Kind
export type Item = Items.Item
export type Stack = { itemId: string, count: number }
export type Slots = { Stack | false }
export type Snapshot = { slots: Slots, selected: number }

local HOTBAR_SIZE = 9
local BACKPACK_SIZE = 81

local byId: { [string]: Item } = {}
for _, item in Items do
	assert(byId[item.id] == nil, `Inventory: duplicate item id "{item.id}"`)
	byId[item.id] = item
end

local Inventory = {}

Inventory.HOTBAR_SIZE = HOTBAR_SIZE
Inventory.BACKPACK_SIZE = BACKPACK_SIZE
Inventory.SLOT_COUNT = HOTBAR_SIZE + BACKPACK_SIZE
-- Every item, in catalogue order.
Inventory.ITEMS = Items

function Inventory.getItem(itemId: string): Item
	local item = byId[itemId]
	assert(item, `Inventory.getItem: unknown item "{itemId}"`)
	return item
end

function Inventory.isPlaceable(item: Item): boolean
	return item.kind == "Block" or item.kind == "Machine"
end

-- For validating untrusted indices: a whole number naming a real slot.
function Inventory.isSlotIndex(value: number): boolean
	return value % 1 == 0 and value >= 1 and value <= Inventory.SLOT_COUNT
end

function Inventory.emptySlots(): Slots
	local slots: Slots = {}
	for index = 1, Inventory.SLOT_COUNT do
		slots[index] = false
	end
	return slots
end

-- The stack in slot `index`, or nil when it is empty. Read slots through this: the type
-- checker narrows `Stack | false` by truthiness to `Stack | true`, but `typeof` holds.
function Inventory.stackAt(slots: Slots, index: number): Stack?
	local slot = slots[index]
	return if typeof(slot) == "table" then slot else nil
end

-- Moves the stack in `from` onto `to`: tops up a stack of the same item as far as it
-- will go, otherwise swaps the two slots. Returns whether anything changed.
function Inventory.move(slots: Slots, from: number, to: number): boolean
	local source = Inventory.stackAt(slots, from)
	if from == to or not source then
		return false
	end
	local target = Inventory.stackAt(slots, to)
	if target and target.itemId == source.itemId then
		local room = Inventory.getItem(source.itemId).stack - target.count
		if room <= 0 then
			return false
		end
		local moved = math.min(room, source.count)
		slots[to] = { itemId = target.itemId, count = target.count + moved }
		slots[from] = if source.count > moved then { itemId = source.itemId, count = source.count - moved } else false
		return true
	end
	slots[from] = target or false
	slots[to] = source
	return true
end

-- Adds up to `count` of an item: tops up existing stacks first, then fills empty slots
-- in order (hotbar before backpack). Returns how many did not fit.
function Inventory.add(slots: Slots, itemId: string, count: number): number
	local limit = Inventory.getItem(itemId).stack
	local left = count
	for index = 1, #slots do
		local stack = Inventory.stackAt(slots, index)
		if left <= 0 then
			break
		end
		if stack and stack.itemId == itemId and stack.count < limit then
			local moved = math.min(left, limit - stack.count)
			slots[index] = { itemId = itemId, count = stack.count + moved }
			left -= moved
		end
	end
	for index = 1, #slots do
		if left <= 0 then
			break
		end
		if not Inventory.stackAt(slots, index) then
			local moved = math.min(left, limit)
			slots[index] = { itemId = itemId, count = moved }
			left -= moved
		end
	end
	return left
end

-- Whether `count` more of an item would fit without any left over.
function Inventory.canAdd(slots: Slots, itemId: string, count: number): boolean
	-- add() replaces stacks rather than mutating them, so a shallow copy is a safe probe.
	return Inventory.add(table.clone(slots), itemId, count) == 0
end

-- Whether every item in `counts` would fit at once, each sharing room with the others.
function Inventory.canAddAll(slots: Slots, counts: { [string]: number }): boolean
	local probe = table.clone(slots)
	for itemId, count in counts do
		if Inventory.add(probe, itemId, count) > 0 then
			return false
		end
	end
	return true
end

-- Takes up to `max` of `itemId` out of slot `index`. Returns how many it took.
function Inventory.take(slots: Slots, index: number, itemId: string, max: number): number
	local stack = Inventory.stackAt(slots, index)
	if not stack or stack.itemId ~= itemId or max < 1 then
		return 0
	end
	local taken = math.min(math.floor(max), stack.count)
	slots[index] = if stack.count > taken then { itemId = itemId, count = stack.count - taken } else false
	return taken
end

-- Takes one `itemId` out of slot `index`. Returns whether it was there to take.
function Inventory.takeOne(slots: Slots, index: number, itemId: string): boolean
	return Inventory.take(slots, index, itemId, 1) == 1
end

return Inventory
