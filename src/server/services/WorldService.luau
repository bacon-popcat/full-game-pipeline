-- WorldService: the resource nodes and animals the world offers (Shared/World), spawned
-- where Shared/World/Layout says. Players mine nodes with the tool a node names and pick
-- bushes empty-handed; FactoryService asks this module what stands near a machine and
-- chops, plants and feeds through it, so every change to a node goes through here.
--
-- Nodes sit on whole cells in Workspace.World and are indexed by every cell they cover.
-- A node the world spawned comes back `respawn` seconds after it is broken, once its
-- cells are clear; a grown one (a planted sapling's tree) does not. Saplings and seeds a
-- player places become nodes at once (World.PLANTS): a sapling grows into an oak tree, a seed
-- into a crop that grows a stage at a time (each stage's GrowsAt attribute says when) until
-- it is ripe. An empty hand harvests a crop; a crop whose soil block is taken away is
-- uprooted and drops its harvest.
--
-- Animals wander their pen. The server moves an animal straight to each destination and
-- publishes the walk (WalkFrom, WalkTo, WalkStart, WalkTime attributes) for clients to
-- animate; it is only ever "near" a machine by where it is heading. Animal art has
-- CanQuery off, so animals never block a placement or catch an aim ray.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
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
	-- Server time a picked node can be picked again.
	pickedUntil: number,
}

export type Animal = {
	animalType: string,
	model: Model,
	-- Pen centre and radius, in studs.
	home: Vector3,
	radius: number,
	fedUntil: number,
}

-- Seconds between one player's interactions; caps how fast a client can spam remotes.
local COOLDOWN = 0.15
-- Seconds a respawn waits before trying again when something stands in the way.
local RESPAWN_RETRY = 10
-- Seconds an animal rests between walks.
local REST_MIN, REST_MAX = 3, 8
-- Name suffix of the parts a picked node hides until it regrows (berries, flowers).
local FRUIT_SUFFIX = "_Fruit"
-- Placeholder colours for any node or animal with no art yet.
local PLACEHOLDER_COLORS: { [string]: Color3 } = {
	CopperDeposit = Color3.fromRGB(196, 112, 64),
	GoldDeposit = Color3.fromRGB(230, 190, 60),
	OilDeposit = Color3.fromRGB(40, 40, 46),
	StoneRock = Color3.fromRGB(150, 150, 150),
	CoalRock = Color3.fromRGB(70, 70, 70),
	IronRock = Color3.fromRGB(190, 160, 140),
	OakTree = Color3.fromRGB(80, 140, 60),
	MapleTree = Color3.fromRGB(200, 90, 40),
	AppleTree = Color3.fromRGB(120, 170, 70),
	Sapling = Color3.fromRGB(110, 170, 80),
	BerryBush = Color3.fromRGB(60, 110, 150),
	FlowerPatch = Color3.fromRGB(220, 110, 160),
	Cow = Color3.fromRGB(240, 240, 240),
	Sheep = Color3.fromRGB(230, 230, 220),
	Pig = Color3.fromRGB(240, 170, 170),
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
local animalFolder = folder(worldFolder, "Animals")

local nodesByCell: { [string]: Node } = {}
local nodesByModel: { [Model]: Node } = {}
local animals: { Animal } = {}
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

local function setFruitVisible(node: Node, visible: boolean)
	for _, part in node.model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, -#FRUIT_SUFFIX) == FRUIT_SUFFIX then
			part.Transparency = if visible then 0 else 1
		end
	end
end

local function spawnNode(nodeType: string, cell: Vector3, natural: boolean): Node
	World.getNode(nodeType)
	local model = copyArt(nodeType, Vector3.one * Build.GRID)
	local footprint = footprintOf(model)
	local centre = Build.box(cell, footprint)
	-- A stable quarter turn per cell, so a grove doesn't look stamped; only square
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
		pickedUntil = 0,
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
	local grows = World.getNode(node.nodeType).grows
	if not grows then
		return
	end
	node.model:SetAttribute("GrowsAt", workspace:GetServerTimeNow() + grows.after)
	task.delay(grows.after, function()
		if nodesByModel[node.model] ~= node then
			return -- chopped or harvested before it grew
		end
		removeNode(node)
		grow(spawnNode(grows.into, node.cell, node.natural))
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

-- Breaks a node for a machine (a lumbermill) and returns its drops.
function WorldService.chop(node: Node): { [string]: number }?
	if nodesByModel[node.model] ~= node then
		return nil
	end
	local drops = World.getNode(node.nodeType).drops
	removeNode(node)
	return drops
end

-- Whether `itemId` (a sapling or seed) could be planted in `cell`: nothing there, and soil
-- under it if it needs some.
function WorldService.canPlant(cell: Vector3, itemId: string): boolean
	return World.PLANTS[itemId] ~= nil and cellsClear(cell, Vector3.one, nil) and Soil.canPlant(itemId, cell)
end

-- Plants a sapling or seed in `cell`. Returns whether it did.
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
	grow(spawnNode(World.cropStage(crop, 1), node.cell, node.natural))
	return true
end

-- Animals of the given types within `radius` studs of `position`.
function WorldService.animalsNear(position: Vector3, radius: number, types: { [string]: any }): { Animal }
	local found = {}
	for _, animal in animals do
		if types[animal.animalType] and (animal.model:GetPivot().Position - position).Magnitude <= radius then
			table.insert(found, animal)
		end
	end
	return found
end

function WorldService.isFed(animal: Animal): boolean
	return animal.fedUntil > workspace:GetServerTimeNow()
end

-- Feeds up to `food` animals within `radius` studs of `position` that are hungry or about
-- to be. Returns how many ate.
function WorldService.feedNear(position: Vector3, radius: number, food: number): number
	local now = workspace:GetServerTimeNow()
	local eaten = 0
	for _, animal in animals do
		if eaten >= food then
			break
		end
		local hungry = animal.fedUntil - now < World.FED_FOR / 2
		if hungry and (animal.model:GetPivot().Position - position).Magnitude <= radius then
			animal.fedUntil = now + World.FED_FOR
			animal.model:SetAttribute("FedUntil", animal.fedUntil)
			eaten += 1
		end
	end
	return eaten
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
	if not node or not root or not ready(player) then
		return
	end
	if not Build.inReach(root.Position, node.cell, node.footprint) then
		return
	end
	local def = World.getNode(node.nodeType)
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
	elseif action == "Take" then
		local pick = def.pick
		local now = workspace:GetServerTimeNow()
		if held or not pick or now < node.pickedUntil then
			return
		end
		if InventoryService.give(player, pick.item, 1) > 0 then
			return
		end
		node.pickedUntil = now + pick.regrow
		setFruitVisible(node, false)
		task.delay(pick.regrow, function()
			if nodesByModel[node.model] == node then
				setFruitVisible(node, true)
			end
		end)
	end
end

-- A sapling or seed a player places becomes the node it plants as (BuildService has already
-- checked the cell and the soil).
local function onPlaced(model: Instance)
	local itemId = model:GetAttribute("ItemId")
	local plant = if typeof(itemId) == "string" then World.PLANTS[itemId] else nil
	if not model:IsA("Model") or not plant then
		return
	end
	local origin = model:GetAttribute("Origin")
	task.defer(function()
		model:Destroy()
		if typeof(origin) == "Vector3" then
			grow(spawnNode(plant.node, origin, false))
		end
	end)
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
	local at = node.model:GetPivot().Position + Vector3.yAxis
	removeNode(node)
	for dropId, count in def.harvest or {} do
		local toss = Vector3.new(random:NextNumber(-1, 1), 1.5, random:NextNumber(-1, 1)).Unit * UPROOT_SPEED
		DropService.spawn(dropId, CFrame.new(at), toss, count)
	end
end

local function walk(animal: Animal)
	local def = World.getAnimal(animal.animalType)
	local model = animal.model
	while model.Parent do
		task.wait(random:NextNumber(REST_MIN, REST_MAX))
		local from = model:GetPivot()
		local angle = random:NextNumber(0, math.pi * 2)
		local reach = random:NextNumber(0, animal.radius)
		local target = animal.home + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		target = Vector3.new(target.X, from.Position.Y, target.Z)
		local offset = target - from.Position
		if offset.Magnitude < 1 then
			continue
		end
		local time = offset.Magnitude / def.speed
		local to = CFrame.lookAt(target, target + offset.Unit)
		model:SetAttribute("WalkFrom", from)
		model:SetAttribute("WalkTo", to)
		model:SetAttribute("WalkTime", time)
		model:SetAttribute("WalkStart", workspace:GetServerTimeNow())
		model:PivotTo(to)
		task.wait(time)
	end
end

local function spawnAnimal(animalType: string, centre: Vector3, radius: number)
	World.getAnimal(animalType)
	local model = copyArt(animalType, Vector3.new(2, 2, 3))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local hitbox = model.PrimaryPart
	assert(hitbox, "WorldService: animal art needs a PrimaryPart hitbox")
	local home = (centre + Vector3.new(0.5, 0, 0.5)) * Build.GRID
	local angle = random:NextNumber(0, math.pi * 2)
	local start = home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(0, radius * Build.GRID)
	local pivotOffset = hitbox.CFrame:ToObjectSpace(model:GetPivot())
	model:PivotTo(CFrame.new(start + Vector3.yAxis * hitbox.Size.Y / 2) * CFrame.Angles(0, angle, 0) * pivotOffset)
	model:SetAttribute("AnimalType", animalType)
	model.Parent = animalFolder
	local animal: Animal = {
		animalType = animalType,
		model = model,
		home = home,
		radius = radius * Build.GRID,
		fedUntil = 0,
	}
	table.insert(animals, animal)
	task.spawn(walk, animal)
end

function WorldService.init()
	for _, spot in Layout.nodes do
		spawnNode(spot.node, spot.cell, true)
	end
	for _, pen in Layout.pens do
		for _ = 1, pen.count do
			spawnAnimal(pen.animal, pen.centre, pen.radius)
		end
	end
	Remotes.Interact.OnServerEvent:Connect(onInteract)
	local placed = workspace:WaitForChild("Placed")
	placed.ChildAdded:Connect(onPlaced)
	placed.ChildRemoved:Connect(onUnplaced)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return WorldService
