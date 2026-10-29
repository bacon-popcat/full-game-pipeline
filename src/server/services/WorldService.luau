-- WorldService: owns quarry and soil nodes and planted crops. Quarry rocks respawn; crops
-- are confined to their owner's plot. Every crop keeps its wall-clock planting time across
-- stages and saves. GrowsAt stays a server-time deadline for the existing hover UI.
-- Plot farms and profile restoration call the same node spawning path as normal planting.
-- Removing placed soil uproots its crop; plot cleanup removes crops before their soil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Layout = require(ReplicatedStorage.Shared.World.Layout)
local Soil = require(ReplicatedStorage.Shared.World.Soil)
local DropService = require(script.Parent.DropService)
local InventoryService = require(script.Parent.InventoryService)

export type Node = {
	nodeType: string,
	cell: Vector3,
	footprint: Vector3,
	model: Model,
	-- Spawned by the world (respawns) rather than grown by a player.
	natural: boolean,
	plantedAt: number?,
	harvestCount: number,
	mutation: string?,
}

-- Seconds between one player's interactions; caps how fast a client can spam remotes.
local COOLDOWN = 0.15
-- Seconds a respawn waits before trying again when something stands in the way.
local RESPAWN_RETRY = 10
-- Missing art uses a one-cell block until the art phase.
local PLACEHOLDER_COLORS: { [string]: Color3 } = {
	CopperRock = Color3.fromRGB(196, 112, 64),
	StoneRock = Color3.fromRGB(150, 150, 150),
	CoalRock = Color3.fromRGB(70, 70, 70),
	IronRock = Color3.fromRGB(190, 160, 140),
	Farmland = Color3.fromRGB(110, 82, 54),
}
-- Studs per second a crop's harvest is tossed out at when its soil is taken away.
local UPROOT_SPEED = 8

local WorldService = {}

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local worldFolder = folder(workspace, "World")

local nodesByCell: { [string]: Node } = {}
local nodesByModel: { [Model]: Node } = {}
local lastAction: { [Player]: number } = {}
local warned: { [string]: boolean } = {}
local overlapParams = Build.newOverlapParams()
local random = Random.new()

local function cellKey(cell: Vector3): string
	return `{cell.X},{cell.Y},{cell.Z}`
end

local function template(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local holder = if assets then assets:FindFirstChild("World") else nil
	local found = if holder then holder:FindFirstChild(name) else nil
	return if found and found:IsA("Model") and found.PrimaryPart then found else nil
end

-- A one-cell coloured block standing in for missing art; its part is its own hitbox.
local function placeholder(name: string, size: Vector3): Model
	if not warned[name] then
		warned[name] = true
		warn(`WorldService: no model for "{name}" in ReplicatedStorage.Assets.World; drawing a placeholder`)
	end
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Name = "Hitbox"
	part.Size = size
	part.Color = PLACEHOLDER_COLORS[name] or Color3.new(1, 0, 1)
	part.Anchored = true
	part.Parent = model
	model.PrimaryPart = part
	return model
end

local function copyArt(name: string, placeholderSize: Vector3): Model
	local found = template(name)
	local model = if found then found:Clone() else placeholder(name, placeholderSize)
	model.Name = name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	return model
end

local function footprintOf(model: Model): Vector3
	local hitbox = model.PrimaryPart
	assert(hitbox, "WorldService: node art needs a PrimaryPart hitbox")
	local cells = hitbox.Size / Build.GRID
	return Vector3.new(
		math.max(1, math.round(cells.X)),
		math.max(1, math.round(cells.Y)),
		math.max(1, math.round(cells.Z))
	)
end

local function eachCell(node: Node, visit: (Vector3) -> ())
	for x = 0, node.footprint.X - 1 do
		for y = 0, node.footprint.Y - 1 do
			for z = 0, node.footprint.Z - 1 do
				visit(node.cell + Vector3.new(x, y, z))
			end
		end
	end
end

local function spawnNode(
	nodeType: string,
	cell: Vector3,
	natural: boolean,
	plantedAt: number?,
	harvestCount: number?,
	mutation: string?
): Node
	World.getNode(nodeType)
	local model = copyArt(nodeType, Vector3.one * Build.GRID)
	local footprint = footprintOf(model)
	local centre = Build.box(cell, footprint)
	-- A stable quarter turn per cell; only square
	-- footprints can turn without changing the cells they cover. Soil never turns, so a
	-- field's rows run straight across it.
	local turns = if footprint.X == footprint.Z and not World.getNode(nodeType).soil
		then (cell.X * 7 + cell.Z * 13) % 4
		else 0
	local hitbox = model.PrimaryPart
	assert(hitbox, "WorldService: node art needs a PrimaryPart hitbox")
	local pivotOffset = hitbox.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(CFrame.new(centre.Position) * CFrame.Angles(0, turns * math.pi / 2, 0) * pivotOffset)
	model:SetAttribute("NodeType", nodeType)
	model:SetAttribute("Cell", cell)
	local node: Node = {
		nodeType = nodeType,
		cell = cell,
		footprint = footprint,
		model = model,
		natural = natural,
		plantedAt = plantedAt,
		harvestCount = harvestCount or 0,
		mutation = mutation,
	}
	eachCell(node, function(each)
		nodesByCell[cellKey(each)] = node
	end)
	nodesByModel[model] = node
	model.Parent = worldFolder
	return node
end

-- Whether a node's cells are clear of other nodes and anything but characters.
local function cellsClear(cell: Vector3, footprint: Vector3, ignore: Node?): boolean
	for x = 0, footprint.X - 1 do
		for y = 0, footprint.Y - 1 do
			for z = 0, footprint.Z - 1 do
				local other = nodesByCell[cellKey(cell + Vector3.new(x, y, z))]
				if other and other ~= ignore then
					return false
				end
			end
		end
	end
	return Build.isFree(cell, footprint, overlapParams)
end

local function scheduleRespawn(nodeType: string, cell: Vector3, after: number)
	task.delay(after, function()
		local probe = template(nodeType)
		local footprint = if probe then footprintOf(probe) else Vector3.one
		if cellsClear(cell, footprint, nil) then
			spawnNode(nodeType, cell, true)
		else
			scheduleRespawn(nodeType, cell, RESPAWN_RETRY)
		end
	end)
end

local function removeNode(node: Node)
	if nodesByModel[node.model] ~= node then
		return
	end
	eachCell(node, function(each)
		if nodesByCell[cellKey(each)] == node then
			nodesByCell[cellKey(each)] = nil
		end
	end)
	nodesByModel[node.model] = nil
	node.model:Destroy()
	local respawn = World.getNode(node.nodeType).respawn
	if node.natural and respawn then
		scheduleRespawn(node.nodeType, node.cell, respawn)
	end
end

local function grow(node: Node)
	local def = World.getNode(node.nodeType)
	local crop = if def.crop then World.CROPS[def.crop] else nil
	if not crop or not def.crop then
		return
	end
	local plantedAt = node.plantedAt or os.time()
	node.plantedAt = plantedAt
	local stage = math.clamp(math.floor(math.max(0, os.time() - plantedAt) / crop.every) + 1, 1, #World.STAGES)
	if stage ~= def.stage then
		removeNode(node)
		grow(spawnNode(World.cropStage(def.crop, stage), node.cell, false, plantedAt, node.harvestCount, node.mutation))
		return
	end
	node.model:SetAttribute("PlantedAt", plantedAt)
	if stage == #World.STAGES then
		return
	end
	local remaining = math.max(0, plantedAt + stage * crop.every - os.time())
	node.model:SetAttribute("GrowsAt", workspace:GetServerTimeNow() + remaining)
	task.delay(math.max(0.1, remaining), function()
		if nodesByModel[node.model] == node then
			grow(node)
		end
	end)
end

-- The node covering `cell`, if any.
function WorldService.nodeAt(cell: Vector3): Node?
	return nodesByCell[cellKey(cell)]
end

-- Nodes of the given types within `radius` studs of `position`.
function WorldService.nodesNear(position: Vector3, radius: number, types: { [string]: any }): { Node }
	local found = {}
	for _, node in nodesByModel do
		if types[node.nodeType] and (node.model:GetPivot().Position - position).Magnitude <= radius then
			table.insert(found, node)
		end
	end
	return found
end

-- Whether `itemId` (a seed) could be planted in `cell`: nothing there, and soil
-- under it if it needs some.
function WorldService.canPlant(cell: Vector3, itemId: string): boolean
	return Plot.at(cell) ~= nil
		and World.PLANTS[itemId] ~= nil
		and cellsClear(cell, Vector3.one, nil)
		and Soil.canPlant(itemId, cell)
end

-- Plants a seed in `cell`. Returns whether it did.
function WorldService.plant(cell: Vector3, itemId: string): boolean
	if not WorldService.canPlant(cell, itemId) then
		return false
	end
	grow(spawnNode(World.PLANTS[itemId].node, cell, false))
	return true
end

-- Reaps a ripe crop for a machine: it starts again from a sprout in the same cell, so the
-- machine gets the produce without spending the seed. Returns whether it did.
function WorldService.reap(node: Node): boolean
	local def = World.getNode(node.nodeType)
	local crop = def.crop
	if nodesByModel[node.model] ~= node or not crop or not World.isRipe(def) then
		return false
	end
	removeNode(node)
	grow(spawnNode(World.cropStage(crop, 1), node.cell, node.natural, os.time(), node.harvestCount + 1))
	return true
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function ready(player: Player): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < COOLDOWN then
		return false
	end
	lastAction[player] = now
	return true
end

local function giveAll(player: Player, counts: { [string]: number })
	for itemId, count in counts do
		InventoryService.give(player, itemId, count)
	end
end

local function onInteract(player: Player, target: unknown, action: unknown)
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target.Parent ~= worldFolder then
		return
	end
	local node = nodesByModel[target]
	local root = rootOf(player)
	if not node or not root or player:GetAttribute("DataReady") ~= true or not ready(player) then
		return
	end
	if not Build.inReach(root.Position, node.cell, node.footprint) then
		return
	end
	local def = World.getNode(node.nodeType)
	if def.crop and not Build.canEdit(player, node.cell, node.footprint) then
		return
	end
	local held = InventoryService.getHeldItemId(player)
	if action == "Use" then
		if not def.tool or held ~= def.tool then
			return
		end
		local drops = def.drops or {}
		if not InventoryService.canGiveAll(player, drops) then
			return
		end
		removeNode(node)
		giveAll(player, drops)
	elseif action == "Take" and def.harvest then
		if held or not InventoryService.canGiveAll(player, def.harvest) then
			return
		end
		removeNode(node)
		giveAll(player, def.harvest)
	end
end

-- A crop whose soil block is picked up or broken is uprooted, its harvest tossed out as drops.
local function onUnplaced(model: Instance)
	local itemId = model:GetAttribute("ItemId")
	local origin = model:GetAttribute("Origin")
	if typeof(itemId) ~= "string" or not World.SOIL_BLOCKS[itemId] or typeof(origin) ~= "Vector3" then
		return
	end
	local node = nodesByCell[cellKey(origin + Vector3.yAxis)]
	local def = if node then World.getNode(node.nodeType) else nil
	if not node or not def or not def.crop then
		return
	end
	-- Deferred ChildRemoved can arrive after a profile has restored new soil in this cell.
	if Soil.isUnder(node.cell) then
		return
	end
	local at = node.model:GetPivot().Position + Vector3.yAxis
	removeNode(node)
	for dropId, count in def.harvest or {} do
		local toss = Vector3.new(random:NextNumber(-1, 1), 1.5, random:NextNumber(-1, 1)).Unit * UPROOT_SPEED
		DropService.spawn(dropId, CFrame.new(at), toss, count)
	end
end

-- PlotService calls this before assigning owners; soil has no harvesting action.
function WorldService.farmland(cell: Vector3)
	if not WorldService.nodeAt(cell) then
		spawnNode("Farmland", cell, false)
	end
end

function WorldService.snapshot(index: number): { Plot.SavedCrop }
	local crops: { Plot.SavedCrop } = {}
	for _, node in nodesByModel do
		local def = World.getNode(node.nodeType)
		if def.crop and Plot.at(node.cell) == index then
			table.insert(crops, {
				cropId = def.crop,
				cell = Plot.pack(Plot.toRelative(index, node.cell)),
				plantedAt = node.plantedAt or os.time(),
				harvestCount = node.harvestCount,
				mutation = node.mutation,
			})
		end
	end
	return crops
end

function WorldService.restore(index: number, saved: Plot.SavedCrop): boolean
	local crop = World.CROPS[saved.cropId]
	local relative = Plot.unpack(saved.cell)
	if
		not crop
		or not relative
		or not Build.isCell(relative)
		or not Plot.contains(index, Plot.toWorld(index, relative), Vector3.one)
	then
		return false
	end
	local cell = Plot.toWorld(index, relative)
	if cell.Y < 0 or cell.Y >= Plot.HEIGHT then
		return false
	end
	if not WorldService.canPlant(cell, crop.seed) then
		return false
	end
	if
		typeof(saved.plantedAt) ~= "number"
		or saved.plantedAt % 1 ~= 0
		or saved.plantedAt < 0
		or saved.plantedAt > os.time()
	then
		return false
	end
	if typeof(saved.harvestCount) ~= "number" or saved.harvestCount < 0 or saved.harvestCount % 1 ~= 0 then
		return false
	end
	if saved.mutation ~= nil and typeof(saved.mutation) ~= "string" then
		return false
	end
	grow(spawnNode(World.cropStage(saved.cropId, 1), cell, false, saved.plantedAt, saved.harvestCount, saved.mutation))
	return true
end

function WorldService.clearPlot(index: number)
	local remove = {}
	for _, node in nodesByModel do
		if World.getNode(node.nodeType).crop and Plot.at(node.cell) == index then
			table.insert(remove, node)
		end
	end
	for _, node in remove do
		removeNode(node)
	end
end

function WorldService.init()
	for _, spot in Layout.nodes do
		spawnNode(spot.node, spot.cell, true)
	end
	Remotes.Interact.OnServerEvent:Connect(onInteract)
	local placed = workspace:WaitForChild("Placed")
	placed.ChildRemoved:Connect(onUnplaced)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return WorldService
