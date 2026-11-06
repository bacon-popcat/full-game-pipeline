-- DataService: owns ProfileStore sessions and the load/save/release order. A player cannot
-- edit until inventory, economy and the whole plot are restored. Entries that no longer fit
-- are skipped (sanitize); a broken save or a full server releases the profile unchanged. Snapshots are plain data, relative to the assigned plot.
-- ProfileStore owns autosaving and locks; OnSave refreshes live state, also captured every
-- two minutes and before EndSession. The installed store uses its mock when Studio lacks API
-- access. Mock data lasts only for that Studio server. No sibling init is a load prerequisite.
--
-- Each player has SLOTS save files, each its own profile key; nothing loads until the player
-- picks one in the save menu (Remotes.SaveMenu), and quitting to the menu saves and releases
-- the garden exactly as leaving does. Slot 1's key is the one every save had before slots, so
-- a garden from then is Slot 1. A key whose session is still ending is waited on before it
-- is read, reopened or removed, so a quick quit-and-reload sees the garden just saved. On join
-- the slot played last (its saved `loadedAt`, else its last save time) opens by itself; the
-- menu shows only while it loads, after a failure, or when every slot is empty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Research = require(ReplicatedStorage.Shared.Research)
local Progress = require(ReplicatedStorage.Shared.Progress)
local World = require(ReplicatedStorage.Shared.World)
local ProfileStore = require(ServerStorage.ServerPackages.ProfileStore)
local BuildService = require(script.Parent.BuildService)
local CraftingService = require(script.Parent.CraftingService)
local DropService = require(script.Parent.DropService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local MonetizationService = require(script.Parent.MonetizationService)
local OnboardingService = require(script.Parent.OnboardingService)
local PlotService = require(script.Parent.PlotService)
local ResearchService = require(script.Parent.ResearchService)
local ProgressService = require(script.Parent.ProgressService)
local GardenService = require(script.Parent.GardenService)
local GroundService = require(script.Parent.GroundService)
local WorldService = require(script.Parent.WorldService)

local SNAPSHOT_EVERY = 120
local SLOTS = 3
-- Seconds a key's ending session is waited on before going ahead anyway.
local END_WAIT = 15
type Data = {
	coins: number,
	xp: number,
	inventory: Inventory.Slots,
	plot: {
		sections: { string },
		ground: Plot.SavedGround,
		blocks: { Plot.SavedBlock },
		crops: { Plot.SavedCrop },
	},
	-- 2 once the plot is laid out in sections, 3 once its starter farm is sunk, 4 once crops on
	-- placed soil stand on Farmland and it has a Hoe, 5 once its starter farm is saved as tilled
	-- ground (migrate). Not in the template, so Reconcile never fills it in for an old save.
	plotLayout: number?,
	seedStock: { [string]: number },
	restockAt: number,
	discovered: { [string]: boolean },
	-- Item ids the player has had, for the Index.
	indexed: { [string]: boolean },
	onboarding: number,
	research: Research.Saved,
	progress: Progress.Saved,
	-- The Crafting Bench tier (Shared/Crafting.TIERS) every bench in this garden works at.
	benchTier: number,
	-- PurchaseIds of Robux packs already granted (MonetizationService).
	receipts: { string },
	-- Unix seconds this save was last opened, so a join reopens the one played last (zero: never).
	loadedAt: number,
}
local starter = Inventory.emptySlots()
for _, stack in
	{
		{ itemId = "Hammer", count = 1 },
		{ itemId = "Pickaxe", count = 1 },
		{ itemId = "Hoe", count = 1 },
		{ itemId = "CraftingBench", count = 1 },
	}
do
	Inventory.add(starter, stack.itemId, stack.count)
end
local PROFILE_TEMPLATE: Data = {
	coins = 50,
	xp = 0,
	inventory = starter,
	plot = { sections = {}, ground = { dug = {}, tilled = {}, grassed = {} }, blocks = {}, crops = {} },
	seedStock = {},
	restockAt = 0,
	discovered = {},
	indexed = {},
	onboarding = 1,
	research = { done = {}, active = nil },
	progress = Progress.empty(),
	benchTier = 1,
	receipts = {},
	loadedAt = 0,
}

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", SNAPSHOT_EVERY)
local store = ProfileStore.New("GardenFoundation_v1", PROFILE_TEMPLATE)
type Profile = { Data: Data, EndSession: (Profile) -> (), IsActive: (Profile) -> boolean }
type Session = {
	profile: Profile,
	key: string,
	loaded: boolean,
	closing: boolean,
	spawning: RBXScriptConnection?,
}
local sessions: { [Player]: Session } = {}
-- Players with a save menu request (load, delete or quit) under way.
local busy: { [Player]: boolean } = {}
-- Profiles whose session was ended here, by key, until their last save lands.
local ending: { [string]: Profile } = {}
local closing = false
local knownItems: { [string]: Inventory.Item } = {}
for _, item in Inventory.ITEMS do
	knownItems[item.id] = item
end

local DataService = {}

local function integer(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0
end

local function countsValid(counts: any): boolean
	if typeof(counts) ~= "table" then
		return false
	end
	for itemId, count in counts do
		if not knownItems[itemId] or not integer(count) or count > 10000 then
			return false
		end
	end
	return true
end

local function contentsValid(contents: any): boolean
	if typeof(contents) ~= "table" or not countsValid(contents.inputs) or not countsValid(contents.outputs) then
		return false
	end
	if
		typeof(contents.lanes) ~= "table"
		or typeof(contents.filter) ~= "table"
		or typeof(contents.powered) ~= "boolean"
	then
		return false
	end
	if not integer(contents.sold) or typeof(contents.fuel) ~= "number" or contents.fuel < 0 or contents.fuel > 30 then
		return false
	end
	for _, counts in contents.lanes do
		if not countsValid(counts) then
			return false
		end
	end
	if contents.filterRight ~= nil and typeof(contents.filterRight) ~= "table" then
		return false
	end
	if contents.filterMutations ~= nil and typeof(contents.filterMutations) ~= "table" then
		return false
	end
	for _, encoded in contents.filterMutations or {} do
		if typeof(encoded) ~= "string" or not string.match(encoded, "^[^:]+:%a+$") then
			return false
		end
	end
	for _, list in { contents.filter, contents.filterRight or {} } do
		for _, itemId in list do
			if not knownItems[itemId] then
				return false
			end
		end
	end
	return true
end

-- Balances and the save's shape must hold. A stack, block or machine's contents that no longer
-- check out (an item renamed or cut since it was saved) is dropped with a warning, so content
-- changes never lock a player out of their garden.
-- Machines the Automation phase renamed; a save from before keeps them under their new ids.
local RENAMED: { [string]: string } = {
	IndustrialFlowerPicker = "Harvester",
	SaplingAutomaticPlanter = "SeedPlanter",
	IndustrialMerchantTeleseller = "ShippingBin",
	IndustrialChest = "StorageChest",
	FoodProcessor = "Juicer",
	IndustrialOven = "Oven",
	CratePackerTier2 = "CratePacker",
	IndustrialSmelter = "Smelter",
}

local function renameCounts(counts: any)
	if typeof(counts) ~= "table" then
		return
	end
	for old, new in RENAMED do
		local count = counts[old]
		if typeof(count) == "number" then
			counts[old] = nil
			counts[new] = (if typeof(counts[new]) == "number" then counts[new] else 0) + count
		end
	end
end

-- The garden size each old expansion tier had (the sign tiers, before sections).
local OLD_TIER_SIZES = { 36, 42, 48 }

-- Moves a save from before sections into the section grid, once. The old garden was a square
-- measured from its corner; that corner is now the start block's (Plot.START_OFFSET), so every
-- saved cell shifts by it, and an old expansion becomes the sections that cover what it had.
local function migrateLayout(data: any)
	if typeof(data.plotLayout) == "number" and data.plotLayout >= 2 then
		return
	end
	local plot = if typeof(data.plot) == "table" then data.plot else {}
	local shift = Plot.START_OFFSET
	for _, list in { plot.blocks, plot.crops } do
		for _, entry in if typeof(list) == "table" then list else {} do
			local cell = if typeof(entry) == "table" then Plot.unpack(entry.cell) else nil
			if cell then
				entry.cell = Plot.pack(cell + shift)
			end
		end
	end
	local size = OLD_TIER_SIZES[if typeof(plot.expansion) == "number" then plot.expansion else 0]
	if size then
		local bought = {}
		for x = Plot.START.x0, (shift.X + size - 1) // Plot.SECTION do
			for z = Plot.START.z0, (shift.Z + size - 1) // Plot.SECTION do
				bought[Plot.key(x, z)] = true
			end
		end
		plot.sections = Plot.encode(bought)
	end
	plot.expansion = nil
	data.plotLayout = 2
end

-- Whether a footprint at `cell` stands over the starter farm, in plot-relative cells.
local function overFarm(cell: Vector3, footprint: Vector3): boolean
	return cell.X <= Plot.FARM_HIGH.X
		and cell.X + footprint.X - 1 >= Plot.FARM_LOW.X
		and cell.Z <= Plot.FARM_HIGH.Z
		and cell.Z + footprint.Z - 1 >= Plot.FARM_LOW.Z
end

-- Sinks a save's starter farm one level, once: its Farmland used to stand at y = 0 with
-- crops on it at y = 1, and now lies at y = -1 (Plot.FARM_LOW). Crops on it, and every
-- block standing over it at y >= 1 (so a stack keeps its shape), move down one.
local function sinkFarm(data: any)
	if typeof(data.plotLayout) == "number" and data.plotLayout >= 3 then
		return
	end
	local plot = if typeof(data.plot) == "table" then data.plot else {}
	for _, crop in if typeof(plot.crops) == "table" then plot.crops else {} do
		local cell = if typeof(crop) == "table" then Plot.unpack(crop.cell) else nil
		if cell and cell.Y == 1 and overFarm(cell, Vector3.one) then
			crop.cell = Plot.pack(cell - Vector3.yAxis)
		end
	end
	for _, block in if typeof(plot.blocks) == "table" then plot.blocks else {} do
		local cell = if typeof(block) == "table" then Plot.unpack(block.cell) else nil
		local footprint = if cell
				and typeof(block.itemId) == "string"
				and typeof(block.rotation) == "number"
				and Build.isRotation(block.rotation)
			then Build.footprint(block.itemId, block.rotation)
			else nil
		if cell and footprint and cell.Y >= 1 and overFarm(cell, footprint) then
			block.cell = Plot.pack(cell - Vector3.yAxis)
		end
	end
	data.plotLayout = 3
end

-- Crops used to grow on placed Grass and Dirt blocks too; now only on Farmland, which a Hoe
-- makes. Once, a placed Grass or Dirt block under a saved crop becomes tilled ground in its cell
-- (GroundService), so the crop keeps its soil. Returns whether it ran, so sanitize can give an
-- old save the Hoe the starter kit now has.
local function tillPlacedSoil(data: any): boolean
	if typeof(data.plotLayout) == "number" and data.plotLayout >= 4 then
		return false
	end
	local plot = if typeof(data.plot) == "table" then data.plot else {}
	local ground = if typeof(plot.ground) == "table" then plot.ground else { dug = {}, tilled = {} }
	plot.ground = ground
	ground.tilled = if typeof(ground.tilled) == "table" then ground.tilled else {}
	local under: { [string]: boolean } = {}
	for _, crop in if typeof(plot.crops) == "table" then plot.crops else {} do
		local cell = if typeof(crop) == "table" then Plot.unpack(crop.cell) else nil
		if cell then
			local below = cell - Vector3.yAxis
			under[`{below.X},{below.Y},{below.Z}`] = true
		end
	end
	local blocks = {}
	for _, block in if typeof(plot.blocks) == "table" then plot.blocks else {} do
		local cell = if typeof(block) == "table" then Plot.unpack(block.cell) else nil
		local cellKey = if cell then `{cell.X},{cell.Y},{cell.Z}` else nil
		if cellKey and under[cellKey] and World.TILLABLE_BLOCKS[block.itemId] then
			table.insert(ground.tilled, cellKey)
		else
			table.insert(blocks, block)
		end
	end
	if typeof(plot.blocks) == "table" then
		plot.blocks = blocks
	end
	data.plotLayout = 4
	return true
end

-- Gardens used to start with a farm of Farmland (Plot.FARM_LOW/FARM_HIGH); now they are all
-- grass and players till their own. Once, an old save keeps its farm as tilled ground (except
-- cells it dug out), and its onboarding step moves past the till step inserted at step 2.
local function keepFarm(data: any, fresh: boolean)
	if typeof(data.plotLayout) == "number" and data.plotLayout >= 5 then
		return
	end
	data.plotLayout = 5
	if fresh then
		return
	end
	local plot = if typeof(data.plot) == "table" then data.plot else {}
	local ground = if typeof(plot.ground) == "table" then plot.ground else nil
	if ground and typeof(ground.tilled) == "table" then
		local skip: { [string]: boolean } = {}
		for _, list in { ground.tilled, if typeof(ground.dug) == "table" then ground.dug else {} } do
			for _, entry in list do
				if typeof(entry) == "string" then
					skip[entry] = true
				end
			end
		end
		for x = Plot.FARM_LOW.X, Plot.FARM_HIGH.X do
			for z = Plot.FARM_LOW.Z, Plot.FARM_HIGH.Z do
				local cellKey = `{x},{Plot.FARM_LOW.Y},{z}`
				if not skip[cellKey] then
					table.insert(ground.tilled, cellKey)
				end
			end
		end
	end
	if typeof(data.onboarding) == "number" and data.onboarding >= 2 then
		data.onboarding += 1
	end
end

-- Returns whether the save predates the Hoe.
local function migrate(data: any): boolean
	-- A profile ProfileStore just made from the template has no layout version and nothing on it.
	local saved = if typeof(data.plot) == "table" then data.plot else {}
	local fresh = data.plotLayout == nil
		and data.xp == 0
		and typeof(saved.crops) == "table"
		and #saved.crops == 0
		and typeof(saved.blocks) == "table"
		and #saved.blocks == 0
	migrateLayout(data)
	sinkFarm(data)
	local owesHoe = tillPlacedSoil(data)
	keepFarm(data, fresh)
	for _, stack in if typeof(data.inventory) == "table" then data.inventory else {} do
		if typeof(stack) == "table" and RENAMED[stack.itemId] then
			stack.itemId = RENAMED[stack.itemId]
		end
	end
	local plot = if typeof(data.plot) == "table" then data.plot else {}
	for _, block in if typeof(plot.blocks) == "table" then plot.blocks else {} do
		if typeof(block) ~= "table" then
			continue
		end
		block.itemId = RENAMED[block.itemId] or block.itemId
		local contents = block.contents
		if typeof(contents) == "table" then
			renameCounts(contents.inputs)
			renameCounts(contents.outputs)
			for _, counts in if typeof(contents.lanes) == "table" then contents.lanes else {} do
				renameCounts(counts)
			end
		end
	end
	return owesHoe
end

local function sanitize(player: Player, data: any)
	local owesHoe = migrate(data)
	data.onboarding = Onboarding.sanitize(data.onboarding)
	data.progress = Progress.sanitize(data.progress)
	assert(integer(data.coins) and integer(data.xp), "Invalid balances")
	assert(
		typeof(data.seedStock) == "table"
			and integer(data.restockAt)
			and typeof(data.discovered) == "table"
			and typeof(data.indexed) == "table",
		"Invalid garden state"
	)
	assert(typeof(data.inventory) == "table" and #data.inventory == Inventory.SLOT_COUNT, "Invalid inventory")
	assert(
		typeof(data.plot) == "table" and typeof(data.plot.blocks) == "table" and typeof(data.plot.crops) == "table",
		"Invalid plot"
	)
	data.plot.sections = Plot.encode(Plot.decode(data.plot.sections))
	local ground = data.plot.ground
	if
		typeof(ground) ~= "table"
		or typeof(ground.dug) ~= "table"
		or typeof(ground.tilled) ~= "table"
		or (ground.grassed ~= nil and typeof(ground.grassed) ~= "table")
	then
		warn(`DataService: reset {player.UserId}'s dug and tilled ground, which was not a valid save`)
		data.plot.ground = { dug = {}, tilled = {}, grassed = {} }
	end
	for index, stack in data.inventory do
		local item = if typeof(stack) == "table" then knownItems[stack.itemId] else nil
		if stack ~= false and not (item and integer(stack.count) and stack.count > 0 and stack.count <= item.stack) then
			warn(`DataService: dropped an invalid stack from {player.UserId}'s inventory`)
			data.inventory[index] = false
		end
	end
	-- A fresh profile runs every migration too, and its starter kit has a Hoe already.
	for _, stack in data.inventory do
		if stack and stack.itemId == "Hoe" then
			owesHoe = false
		end
	end
	if owesHoe and Inventory.add(data.inventory, "Hoe", 1) > 0 then
		warn(`DataService: no room for {player.UserId}'s Hoe; the Gear Shop sells one`)
	end
	-- Machines are crafted only, so a garden with no Crafting Bench, placed or carried, gets one
	-- (saves from when the Machine Shop sold them may have none).
	local hasBench = false
	for _, stack in data.inventory do
		hasBench = hasBench or (stack and stack.itemId == Crafting.BENCH)
	end
	for _, block in data.plot.blocks do
		hasBench = hasBench or (typeof(block) == "table" and block.itemId == Crafting.BENCH)
	end
	if not hasBench and Inventory.add(data.inventory, Crafting.BENCH, 1) > 0 then
		warn(`DataService: no room for {player.UserId}'s Crafting Bench`)
	end
	local blocks = {}
	for _, block in data.plot.blocks do
		local item = if typeof(block) == "table" then knownItems[block.itemId] else nil
		if
			item
			and Inventory.isPlaceable(item)
			and not World.PLANTS[item.id]
			and Plot.unpack(block.cell)
			and integer(block.rotation)
			and block.rotation <= 3
		then
			if block.contents and not contentsValid(block.contents) then
				warn(`DataService: dropped the contents of {player.UserId}'s {item.id}`)
				block.contents = nil
			end
			table.insert(blocks, block)
		else
			warn(`DataService: dropped an invalid block from {player.UserId}'s plot`)
		end
	end
	data.plot.blocks = blocks
end

local function snapshot(player: Player, session: Session)
	if not session.loaded then
		return
	end
	local index = PlotService.get(player)
	local inventory = InventoryService.snapshot(player)
	local economy = EconomyService.get(player)
	assert(index and inventory and economy, "DataService: loaded session lost its state")
	local data = session.profile.Data
	data.inventory = inventory
	data.coins = economy.coins
	data.xp = economy.xp
	local garden = GardenService.snapshot(player)
	assert(garden, "DataService: loaded session lost garden state")
	data.seedStock = garden.seedStock
	data.restockAt = garden.restockAt
	data.discovered = garden.discovered
	data.indexed = garden.indexed
	local onboarding = OnboardingService.snapshot(player)
	assert(onboarding, "DataService: loaded session lost onboarding state")
	data.onboarding = onboarding
	local research = ResearchService.snapshot(player)
	assert(research, "DataService: loaded session lost research state")
	data.research = research
	data.benchTier = CraftingService.snapshot(player) or data.benchTier
	data.receipts = MonetizationService.snapshot(player) or data.receipts
	local progress = ProgressService.snapshot(player)
	assert(progress, "DataService: loaded session lost progress state")
	data.progress = progress
	data.plot = {
		sections = PlotService.sections(index),
		ground = GroundService.snapshot(index),
		blocks = BuildService.snapshot(player, index),
		crops = WorldService.snapshot(index),
	}
end

local function clear(player: Player)
	player:SetAttribute("DataReady", false)
	local index = PlotService.get(player)
	if index then
		WorldService.clearPlot(index)
	end
	BuildService.clear(player)
	DropService.clear(player)
	OnboardingService.release(player)
	ProgressService.release(player)
	InventoryService.release(player)
	EconomyService.release(player)
	GardenService.release(player)
	ResearchService.release(player)
	CraftingService.release(player)
	MonetizationService.release(player)
	PlotService.release(player)
end

local function keyFor(player: Player, slot: number): string
	return if slot == 1 then tostring(player.UserId) else `{player.UserId}_{slot}`
end

-- Waits until a session this server ended on `key` has saved for the last time; ProfileStore
-- won't reopen a key it still holds, and a read before then would miss that save.
local function settle(key: string)
	local profile = ending[key]
	local started = os.clock()
	while profile and profile:IsActive() and os.clock() - started < END_WAIT do
		task.wait(0.1)
	end
	ending[key] = nil
end

local function toHub(player: Player)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(CFrame.new(0, 5, 0))
	end
end

-- What each save file holds, for the menu, and which filled slot was played last: the latest
-- `loadedAt`, or for a save from before it was kept, the latest save.
local function readSlots(player: Player): ({ any }, number?)
	local slots = {}
	local last: number?, lastAt = nil, -1
	for slot = 1, SLOTS do
		local key = keyFor(player, slot)
		settle(key)
		local profile = store:GetAsync(key)
		local data = if profile then profile.Data else nil
		if typeof(data) == "table" then
			local info = profile.KeyInfo
			local savedAt = if info then info.UpdatedTime / 1000 else nil
			slots[slot] = {
				empty = false,
				level = (Economy.progress(if typeof(data.xp) == "number" then data.xp else 0)),
				coins = if typeof(data.coins) == "number" then data.coins else 0,
				savedAt = savedAt,
			}
			local playedAt = if typeof(data.loadedAt) == "number" and data.loadedAt > 0
				then data.loadedAt
				else savedAt or 0
			if playedAt > lastAt then
				last, lastAt = slot, playedAt
			end
		else
			slots[slot] = { empty = true }
		end
	end
	return slots, last
end

-- Sends the player what each save file holds, for the menu; `loading` is a slot already opening.
local function sendSlots(player: Player, message: string?, loading: number?, slots: { any }?)
	local list = slots or (readSlots(player))
	if player.Parent == Players then
		Remotes.SaveSlots:FireClient(player, { slots = list, message = message, loading = loading })
	end
end

local function release(player: Player)
	local session = sessions[player]
	if not session or session.closing then
		return
	end
	session.closing = true
	snapshot(player, session)
	session.loaded = false
	clear(player)
	sessions[player] = nil
	if session.spawning then
		session.spawning:Disconnect()
	end
	ending[session.key] = session.profile
	session.profile:EndSession()
end

-- Starts save file `slot`'s session and restores its garden. On a failure the player is back at
-- the menu with the reason.
local function load(player: Player, slot: number)
	if sessions[player] or closing then
		return
	end
	local key = keyFor(player, slot)
	settle(key)
	player:SetAttribute("DataReady", false)
	local profile = store:StartSessionAsync(key, {
		Cancel = function()
			return closing or player.Parent ~= Players
		end,
	})
	if not profile then
		if player.Parent == Players then
			sendSlots(player, "That garden couldn't be opened. Please try again.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	if closing or player.Parent ~= Players then
		profile:EndSession()
		return
	end
	local session: Session = { profile = profile, key = key, loaded = false, closing = false }
	sessions[player] = session
	profile.OnSave:Connect(function()
		snapshot(player, session)
	end)
	profile.OnSessionEnd:Connect(function()
		if sessions[player] ~= session then
			return
		end
		sessions[player] = nil
		session.loaded = false
		if session.spawning then
			session.spawning:Disconnect()
		end
		clear(player)
		if player.Parent == Players then
			sendSlots(player, "Your garden was opened somewhere else.")
		end
	end)
	local ok, message = pcall(function()
		sanitize(player, profile.Data)
		local index = PlotService.assign(player, profile.Data.plot.sections)
		assert(index, "All six gardens are occupied")
		ResearchService.load(player, profile.Data.research)
		CraftingService.load(player, profile.Data.benchTier)
		MonetizationService.load(player, profile.Data.receipts)
		-- Ground first, so blocks can stand in the holes dug in it and crops find their Farmland.
		GroundService.restore(index, profile.Data.plot.ground)
		for _, block in profile.Data.plot.blocks do
			if not BuildService.restore(player, index, block) then
				warn(`DataService: could not restore {player.UserId}'s {block.itemId}`)
			end
		end
		for _, crop in profile.Data.plot.crops do
			if not WorldService.restore(index, crop) then
				warn(`DataService: could not restore {player.UserId}'s {crop.cropId}`)
			end
		end
		InventoryService.load(player, profile.Data.inventory)
		EconomyService.load(player, profile.Data.coins, profile.Data.xp)
		ProgressService.load(player, profile.Data.progress)
		GardenService.load(
			player,
			profile.Data.seedStock,
			profile.Data.restockAt,
			profile.Data.discovered,
			profile.Data.indexed
		)
		OnboardingService.load(player, profile.Data.onboarding)
	end)
	if not ok then
		warn(`DataService: restore failed for {player.UserId}: {message}`)
		release(player)
		sendSlots(player, "Your garden could not be restored, or this server is full. Your save was kept.")
		return
	end
	session.loaded = true
	profile.Data.loadedAt = os.time()
	player:SetAttribute("DataReady", true)
	session.spawning = player.CharacterAdded:Connect(function(character: Model)
		if character:WaitForChild("HumanoidRootPart", 10) and sessions[player] == session then
			toHub(player)
		end
	end)
	local spawn = workspace.Plots:FindFirstChild("HubSpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
	toHub(player)
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		warn("DataService: Studio uses ProfileStore's mock; this garden will not persist after Stop.")
	end
end

local function quit(player: Player)
	local session = sessions[player]
	if not session or not session.loaded then
		return
	end
	release(player)
	toHub(player)
	sendSlots(player)
end

local function delete(player: Player, slot: number)
	if sessions[player] then
		return
	end
	local key = keyFor(player, slot)
	settle(key)
	store:RemoveAsync(key)
	sendSlots(player)
end

local function onSaveMenu(player: Player, action: unknown, slot: unknown)
	if busy[player] or closing then
		return
	end
	local valid = typeof(slot) == "number" and slot % 1 == 0 and slot >= 1 and slot <= SLOTS
	local work: (() -> ())? = if action == "Quit"
		then function()
			quit(player)
		end
		elseif action == "Load" and valid then function()
			load(player, slot :: number)
		end
		elseif action == "Delete" and valid then function()
			delete(player, slot :: number)
		end
		else nil
	if not work then
		return
	end
	busy[player] = true
	local ok, message = pcall(work)
	busy[player] = nil
	if not ok then
		warn(`DataService: save menu {action} failed for {player.UserId}: {message}`)
		sendSlots(player, "Something went wrong. Please try again.")
	end
end

-- A join opens the save played last straight away, as a menu request would, so the menu
-- ignores clicks until it lands; a player with no save yet picks a slot.
local function onPlayer(player: Player)
	player:SetAttribute("DataReady", false)
	busy[player] = true
	local ok, message = pcall(function()
		local slots, last = readSlots(player)
		sendSlots(player, nil, last, slots)
		if last then
			load(player, last)
		end
	end)
	busy[player] = nil
	if not ok then
		warn(`DataService: opening {player.UserId}'s last garden failed: {message}`)
		sendSlots(player, "Something went wrong. Please try again.")
	end
end

function DataService.init()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		release(player)
		busy[player] = nil
	end)
	Remotes.SaveMenu.OnServerEvent:Connect(onSaveMenu)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	task.spawn(function()
		while not closing do
			task.wait(SNAPSHOT_EVERY)
			for player, session in sessions do
				snapshot(player, session)
			end
		end
	end)
	game:BindToClose(function()
		closing = true
		for player in sessions do
			release(player)
		end
	end)
end

return DataService
