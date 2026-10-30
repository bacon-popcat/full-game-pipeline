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
	-- server -> client: ({ restockAt: number, stock: { [seedId: string]: number } });
	-- restockAt is the next Unix restock boundary. Sent on load, prompt, restock and purchase response.
	ShopSync = get("ShopSync"),
	-- client -> server: (shopId: string, itemId: string, count: number). shopId is a hub stall
	-- (SeedShop, GearShop, MachineShop) in reach; count is a positive integer, within your own
	-- stock for seeds, and the server checks level, coins and room. Answered with Notify.
	ShopBuy = get("ShopBuy"),
	-- client -> server: (mode: "Held" | "All"), checked against server inventory and stall reach.
	Sell = get("Sell"),
	-- server -> client: (message: string), a short transaction or rare-harvest toast.
	Notify = get("Notify"),
	-- server -> client: (fx: { kind: "Plant" | "Harvest" | "Sell" | "Buy" | "LevelUp", position: Vector3?,
	-- itemId: string?, mutation: string?, amount: number? }) a moment to show and sound (FxService ->
	-- FxController). Cosmetic only: nothing the client does with it changes the game.
	Fx = get("Fx"),
	-- server -> client: (objective: { step: number, total: number, text: string, done: boolean })
	-- the player's current onboarding objective (OnboardingService); sent on load and each step.
	Objective = get("Objective"),
	-- server -> client: (snapshot: { coins: number, xp: number, level: number }); XP is
	-- lifetime XP (Shared/Economy derives progress). Sent on profile load and balance changes.
	EconomySync = get("EconomySync"),
	-- server -> client: (snapshot: Inventory.Snapshot)
	InventorySync = get("InventorySync"),
	-- client -> server: (from: number, to: number) slot indices
	InventoryMove = get("InventoryMove"),
	-- client -> server: (index: number) hotbar index, 0 for an empty hand
	InventorySelect = get("InventorySelect"),
	-- client -> server: (origin: Vector3, rotation: number, against: Vector3?) a Build cell, 0-3
	-- turns, and the axis the aimed surface faces (the block placed against is at origin - against)
	PlaceBlock = get("PlaceBlock"),
	-- client -> server: (model: Model) a block in Workspace.Placed, to pick up with the
	-- Hammer or break with the tool its item names
	PickUpBlock = get("PickUpBlock"),
	-- client -> server: (target: Model, action: string, itemId: string?) a placed factory
	-- block or a world node. "Use" applies the held item (feed a machine, set a filter, mine
	-- a rock); "Take" is an empty hand (collect output, pick berries, switch a split
	-- conveyor). The machine panel sends the rest, whatever is held: "Load" (itemId, from
	-- anywhere in the inventory), "Collect", "TakeBack", "Switch", "Filter" (itemId: moves it
	-- on from straight to left to right and back), "Mutation" (not an item id but "Left:Golden",
	-- ticking or unticking a mutation on that side of a filter) and "ClearFilter".
	Interact = get("Interact"),
	-- server -> client: (update: { t: number, lanes: { [string]: { Lane.Item } } }) the items
	-- on every lane that gained or lost one, keyed "<BlockId>/<lane index>", as of server
	-- time `t`. An empty list clears a lane.
	FactorySync = get("FactorySync"),
	-- client -> server: (onto: Model?) drop one of the held item: onto a placed conveyor
	-- within reach, or in front of the player when `onto` is nil
	DropItem = get("DropItem"),
	-- server -> client: (drop: Model, target: BasePart | Vector3, whole: boolean) a loose drop
	-- in Workspace.Drops was picked up by the character whose root is `target`, merged into the
	-- stack whose root it is, or pulled onto a belt at that point. `whole` means the drop is gone (it lingers briefly, out of play,
	-- for the animation); false means part of a stack went and the drop stays. Cosmetic only.
	DropCollected = get("DropCollected"),
}
