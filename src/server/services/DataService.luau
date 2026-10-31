-- DataService: owns ProfileStore sessions and the load/save/release order. A player cannot
-- edit until inventory, economy and the whole plot are restored. Entries that no longer fit
-- are skipped (sanitize); a broken save or a full server releases the profile unchanged. Snapshots are plain data, relative to the assigned plot.
-- ProfileStore owns autosaving and locks; OnSave refreshes live state, also captured every
-- two minutes and before EndSession. The installed store uses its mock when Studio lacks API
-- access. Mock data lasts only for that Studio server. No sibling init is a load prerequisite.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local World = require(ReplicatedStorage.Shared.World)
local ProfileStore = require(ServerStorage.ServerPackages.ProfileStore)
local BuildService = require(script.Parent.BuildService)
local DropService = require(script.Parent.DropService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local OnboardingService = require(script.Parent.OnboardingService)
local PlotService = require(script.Parent.PlotService)
local GardenService = require(script.Parent.GardenService)
local GroundService = require(script.Parent.GroundService)
local WorldService = require(script.Parent.WorldService)

local SNAPSHOT_EVERY = 120
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
	-- placed soil stand on Farmland and it has a Hoe (migrate). Not in the template, so Reconcile
	-- never fills it in for an old save.
	plotLayout: number?,
	seedStock: { [string]: number },
	restockAt: number,
	discovered: { [string]: boolean },
	onboarding: number,
}
local starter = Inventory.emptySlots()
for _, stack in
	{
		{ itemId = "Hammer", count = 1 },
		{ itemId = "Pickaxe", count = 1 },
		{ itemId = "Hoe", count = 1 },
		{ itemId = "CarrotSeeds", count = 10 },
		{ itemId = "WheatSeeds", count = 5 },
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
	onboarding = 1,
}

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", SNAPSHOT_EVERY)
local store = ProfileStore.New("GardenFoundation_v1", PROFILE_TEMPLATE)
type Profile = { Data: Data, EndSession: (Profile) -> () }
type Session = { profile: Profile, loaded: boolean, closing: boolean }
local sessions: { [Player]: Session } = {}
local joining: { [Player]: boolean } = {}
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

-- Returns whether the save predates the Hoe.
local function migrate(data: any): boolean
	migrateLayout(data)
	sinkFarm(data)
	local owesHoe = tillPlacedSoil(data)
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
	assert(integer(data.coins) and integer(data.xp), "Invalid balances")
	assert(
		typeof(data.seedStock) == "table" and integer(data.restockAt) and typeof(data.discovered) == "table",
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
	local onboarding = OnboardingService.snapshot(player)
	assert(onboarding, "DataService: loaded session lost onboarding state")
	data.onboarding = onboarding
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
	InventoryService.release(player)
	EconomyService.release(player)
	GardenService.release(player)
	PlotService.release(player)
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
	session.profile:EndSession()
end

local function onPlayer(player: Player)
	if joining[player] or sessions[player] or closing then
		return
	end
	joining[player] = true
	player:SetAttribute("DataReady", false)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return closing or player.Parent ~= Players
		end,
	})
	joining[player] = nil
	if not profile then
		if player.Parent == Players then
			player:Kick("Your garden could not be loaded. Please rejoin.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	if closing or player.Parent ~= Players then
		profile:EndSession()
		return
	end
	local session: Session = { profile = profile, loaded = false, closing = false }
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
		clear(player)
		if player.Parent == Players then
			player:Kick("Your garden session ended. Please rejoin.")
		end
	end)
	local ok, message = pcall(function()
		sanitize(player, profile.Data)
		local index = PlotService.assign(player, profile.Data.plot.sections)
		assert(index, "All six gardens are occupied")
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
		GardenService.load(player, profile.Data.seedStock, profile.Data.restockAt, profile.Data.discovered)
		OnboardingService.load(player, profile.Data.onboarding)
	end)
	if not ok then
		warn(`DataService: restore failed for {player.UserId}: {message}`)
		release(player)
		player:Kick("Your garden could not be restored, or this server is full. Your save was kept. Please rejoin.")
		return
	end
	session.loaded = true
	player:SetAttribute("DataReady", true)
	local function spawnAtHub(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and sessions[player] == session then
			character:PivotTo(CFrame.new(0, 5, 0))
		end
	end
	player.CharacterAdded:Connect(spawnAtHub)
	local spawn = workspace.Plots:FindFirstChild("HubSpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
	if player.Character then
		task.spawn(spawnAtHub, player.Character)
	end
	if RunService:IsStudio() and ProfileStore.DataStoreState ~= "Access" then
		warn("DataService: Studio uses ProfileStore's mock; this garden will not persist after Stop.")
	end
end

function DataService.init()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(release)
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
