--!strict
-- InventoryClient: this client's view of its own inventory. Holds the last snapshot from
-- InventoryService and predicts the player's own moves and hotbar picks with the shared
-- Inventory rules, so the UI answers at once. The next snapshot always wins, which is
-- how a rejected prediction corrects itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

local InventoryClient = {}

-- Fires after any change, predicted or from the server.
InventoryClient.changed = Signal.new()

local slots: Inventory.Slots = Inventory.emptySlots()
local selected = 0

Remotes.InventorySync.OnClientEvent:Connect(function(snapshot: Inventory.Snapshot)
	slots = snapshot.slots
	selected = snapshot.selected
	InventoryClient.changed:Fire()
end)

-- The stack in slot `index`, or nil when it is empty.
function InventoryClient.getSlot(index: number): Inventory.Stack?
	return Inventory.stackAt(slots, index)
end

-- The selected hotbar index, 0 for an empty hand.
function InventoryClient.getSelected(): number
	return selected
end

function InventoryClient.move(from: number, to: number)
	if Inventory.move(slots, from, to) then
		InventoryClient.changed:Fire()
		Remotes.InventoryMove:FireServer(from, to)
	end
end

function InventoryClient.select(index: number)
	if index == selected then
		return
	end
	selected = index
	InventoryClient.changed:Fire()
	Remotes.InventorySelect:FireServer(index)
end

return InventoryClient
