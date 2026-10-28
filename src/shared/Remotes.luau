--!strict
-- Remotes: every RemoteEvent, looked up once so both sides name them the same way. The
-- instances are authored in default.project.json under ReplicatedStorage.Remotes; the
-- payload each one carries is documented beside it. Receivers validate everything a
-- client sends -- a payload comment is a contract, not a guarantee.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function get(name: string): RemoteEvent
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `Remotes.{name} must be a RemoteEvent`)
	return remote
end

return {
	-- server -> client: (snapshot: Inventory.Snapshot)
	InventorySync = get("InventorySync"),
	-- client -> server: (from: number, to: number) slot indices
	InventoryMove = get("InventoryMove"),
	-- client -> server: (index: number) hotbar index, 0 for an empty hand
	InventorySelect = get("InventorySelect"),
	-- client -> server: (origin: Vector3, rotation: number) a Build cell and 0-3 turns
	PlaceBlock = get("PlaceBlock"),
	-- client -> server: (model: Model) a block in Workspace.Placed
	PickUpBlock = get("PickUpBlock"),
}
