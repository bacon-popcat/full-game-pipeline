-- WorldService: owns world nodes: quarry rocks, planted crops, and the cells of the gardens'
-- ground, which GroundService decides (spawn/remove) and answers the hand for. Quarry rocks
-- respawn; crops are confined to their owner's plot. Every crop keeps its wall-clock planting
-- time across stages and saves. GrowsAt stays a server-time deadline for the existing hover UI.
-- Profile restoration calls the same node spawning path as normal planting. Digging a crop's
-- soil uproots it (uproot); plot cleanup removes crops before their soil. Ground can run to
-- thousands of nodes, so everything that walks nodes walks only the rest (`living`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local GardenEvents = require(game:GetService("ServerScriptService").Libraries.GardenEvents)
local Bonuses = require(game:GetService("ServerScriptService").Libraries.Bonuses)
local GroundArt = require(game:GetService("ServerScriptService").Libraries.GroundArt)
local GardenService = require(script.Parent.GardenService)
local WeatherService = require(script.Parent.WeatherService)
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
	-- The ripe crop's mutations as a Mutations key ("Wet+Golden"), nil for plain.
	mutation: string?,
	mutationRolled: boolean,
	growthBonus: number,
	weatherClock: number,
	-- Wall time growth was last banked into growthBonus.
	bankedAt: number,
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
	GrassGround = Color3.fromRGB(120, 178, 92),
	DirtGround = Color3.fromRGB(150, 108, 72),
	StoneGround = Color3.fromRGB(150, 150, 150),
	ForestOak = Color3.fromRGB(120, 170, 96),
	ForestPine = Color3.fromRGB(92, 146, 110),
	ForestBirch = Color3.fromRGB(170, 200, 120),
}
-- Studs per second a crop's harvest is tossed out at when its soil is taken away.
local UPROOT_SPEED = 8
-- A watering can splash takes this share off what's left of a crop's stage.
local WATER_SHARE = 0.2
-- Seconds between one player's splashes.
local WATER_COOLDOWN = 1.5

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
local stumpFolder = folder(workspace, "Stumps")

local nodesByCell: { [string]: Node } = {}
local nodesByModel: { [Model]: Node } = {}
-- Every node that isn't ground.
local living: { [Model]: Node } = {}
-- Stumps of chopped trees waiting to grow back, by cell key.
local stumps: { [string]: Model } = {}
local lastAction: { [Player]: number } = {}
local lastWatered: { [Player]: number } = {}
local warned: { [string]: boolean } = {}
local overlapParams = Build.newOverlapParams()
local random = Random.new()

local function wallTime(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

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

-- Tree crops keep a column of World.CROPS `height` cells from the moment they're planted, so
-- their hitbox is that column: placement tests then refuse any block in it, on the server and
-- in the placing ghost. The art's hitboxes are one cell, as the import makes every crop's, so
-- each stage's template (every look) is stretched up here once, its bottom where it was and its
-- pivot kept; clones, morph and clients (the templates replicate) all see the same box.
local function reserveColumns()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local holder = if assets then assets:FindFirstChild("World") else nil
	if not holder then
		return
	end
	for cropId, crop in World.CROPS do
		if crop.height <= 1 then
			continue
		end
		local tall = crop.height * Build.GRID
		for _, stage in World.STAGES do
			for _, art in holder:GetChildren() do
				local hitbox = if art:IsA("Model") then art.PrimaryPart else nil
				local name = cropId .. stage
				local look = art.Name == name or string.match(art.Name, `^{name}Variant%d+$`) ~= nil
				if not look or not hitbox or math.abs(hitbox.Size.Y - tall) < 0.01 then
					continue
				end
				local pivot = (art :: Model):GetPivot()
				local bottom = hitbox.CFrame * CFrame.new(0, -hitbox.Size.Y / 2, 0)
				hitbox.Size = Vector3.new(hitbox.Size.X, tall, hitbox.Size.Z)
				hitbox.CFrame = bottom * CFrame.new(0, tall / 2, 0)
				hitbox.PivotOffset = hitbox.CFrame:ToObjectSpace(pivot)
			end
		end
	end
end
reserveColumns()

-- A crop stage's art can come in looks: <Stage>, then <Stage>Variant2, Variant3 ... with no
-- gaps. Each cell keeps one look, picked from its position (no save needed, the same after a
-- rejoin), and the same pick for every stage, so one plant grows as itself.
local function variantOf(name: string, cell: Vector3): Model?
	local count = 1
	while template(`{name}Variant{count + 1}`) do
		count += 1
	end
	local pick = math.floor(math.abs(math.sin(cell.X * 12.9898 + cell.Z * 78.233 + cell.Y * 37.719)) * 43758.5453)
			% count
		+ 1
	return if pick == 1 then template(name) else template(`{name}Variant{pick}`)
end

local function copyArt(name: string, placeholderSize: Vector3, cell: Vector3?): Model
	local def = World.NODES[name]
	-- Crops and forest trees come in looks; a node with only one look finds just that.
	local found = if def and def.ground
		then GroundArt.copy(name)
		elseif def and cell then variantOf(name, cell)
		else template(name)
	local crop = if def and def.crop then World.CROPS[def.crop] else nil
	local fallback = not found and crop ~= nil
	if not found and crop and def and def.stage then
		found = template(crop.art .. World.STAGES[def.stage])
	end
	local model = if not found
		then placeholder(name, placeholderSize)
		elseif def and def.ground then found
		else found:Clone()
	if fallback and crop then
		ItemArt.tint(model, crop.color)
	end
	-- Which look it is (Assets.World), for effects drawn from its art after it's gone.
	model:SetAttribute("Look", if found and not (def and def.ground) then found.Name else nil)
	model.Name = name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	return model
end

-- The art key of a crop part: the `_<Key>` suffix of its name (Crop, Fruit, Bark ...).
local function keyOf(part: Instance): string?
	return string.match(part.Name, "_(%a+)$")
end

-- Turns a standing crop's model into stage `name`'s art in place, when the two looks share
-- their other parts exactly (a multi crop's Mature is its Ripe without the fruit): parts whose
-- key the new art lacks go, and the new art's extra parts are added where it has them. Returns
-- false, changing nothing, when they differ in more than that.
-- Why not swap the model: the new stage's leaves are their own mesh, and a mesh drawn for the
-- first time blinks for a moment on the client even when preloaded, so every first harvest did.
local function morph(model: Model, name: string, cell: Vector3): boolean
	local art = variantOf(name, cell)
	local hitbox, artHitbox = model.PrimaryPart, if art then art.PrimaryPart else nil
	if not art or not hitbox or not artHitbox then
		return false
	end
	local own: { [string]: BasePart } = {}
	for _, part in model:GetChildren() do
		local key = keyOf(part)
		if part:IsA("BasePart") and part ~= hitbox and key then
			if own[key] then
				return false
			end
			own[key] = part
		end
	end
	local adding: { BasePart } = {}
	local kept: { [string]: boolean } = {}
	for _, part in art:GetChildren() do
		local key = keyOf(part)
		if not part:IsA("BasePart") or part == artHitbox or not key then
			continue
		end
		local mine = own[key]
		if not mine then
			table.insert(adding, part)
		elseif
			mine.Size ~= part.Size
			or not hitbox.CFrame:ToObjectSpace(mine.CFrame):FuzzyEq(artHitbox.CFrame:ToObjectSpace(part.CFrame), 1e-3)
		then
			return false
		end
		kept[key] = true
	end
	for key, part in own do
		if not kept[key] then
			part:Destroy()
		end
	end
	local toWorld = hitbox.CFrame * artHitbox.CFrame:Inverse()
	for _, part in adding do
		local copy = part:Clone()
		copy.CFrame = toWorld * part.CFrame
		copy.Anchored = true
		copy.Parent = model
	end
	return true
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
	mutation: string?,
	growthBonus: number?,
	mutationRolled: boolean?,
	-- A model already standing in `cell` that morph made this node's art.
	standing: Model?
): Node
	local def = World.getNode(nodeType)
	local model = standing or copyArt(nodeType, Vector3.one * Build.GRID, cell)
	local footprint = footprintOf(model)
	if not standing then
		local centre = Build.box(cell, footprint)
		-- A stable quarter turn per cell; only square
		-- footprints can turn without changing the cells they cover. Ground never turns, so a
		-- field's rows run straight across it.
		local turns = if footprint.X == footprint.Z and not def.ground then (cell.X * 7 + cell.Z * 13) % 4 else 0
		local hitbox = model.PrimaryPart
		assert(hitbox, "WorldService: node art needs a PrimaryPart hitbox")
		local pivotOffset = hitbox.CFrame:ToObjectSpace(model:GetPivot())
		model:PivotTo(CFrame.new(centre.Position) * CFrame.Angles(0, turns * math.pi / 2, 0) * pivotOffset)
	end
	model.Name = nodeType
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
		mutationRolled = mutationRolled or mutation ~= nil,
		growthBonus = growthBonus or 0,
		weatherClock = WeatherService.bonusNow(),
		bankedAt = wallTime(),
	}
	eachCell(node, function(each)
		nodesByCell[cellKey(each)] = node
	end)
	nodesByModel[model] = node
	if not def.ground then
		living[model] = node
	end
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

-- A broken node's stump (World.Node `stump`), standing in its cell until it respawns. Scenery:
-- it doesn't collide or answer queries, so it never blocks the respawn or a placement.
local function standStump(def: World.Node, node: Node)
	local art = if def.stump then template(def.stump) else nil
	if not art then
		return
	end
	local stump = art:Clone()
	for _, part in stump:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local floor = Build.box(node.cell, Vector3.new(1, 0, 1)).Position
	stump:PivotTo(CFrame.new(floor) * node.model:GetPivot().Rotation)
	stump.Parent = stumpFolder
	stumps[cellKey(node.cell)] = stump
end

local function scheduleRespawn(nodeType: string, cell: Vector3, after: number)
	task.delay(after, function()
		local probe = template(nodeType)
		local footprint = if probe then footprintOf(probe) else Vector3.one
		if cellsClear(cell, footprint, nil) then
			local stump = stumps[cellKey(cell)]
			stumps[cellKey(cell)] = nil
			if stump then
				stump:Destroy()
			end
			spawnNode(nodeType, cell, true)
		else
			scheduleRespawn(nodeType, cell, RESPAWN_RETRY)
		end
	end)
end

-- `keepModel` leaves the model standing, for the node that morph made it into.
local function removeNode(node: Node, keepModel: boolean?)
	if nodesByModel[node.model] ~= node then
		return
	end
	eachCell(node, function(each)
		if nodesByCell[cellKey(each)] == node then
			nodesByCell[cellKey(each)] = nil
		end
	end)
	nodesByModel[node.model] = nil
	living[node.model] = nil
	local def = World.getNode(node.nodeType)
	local respawns = node.natural and def.respawn ~= nil
	-- Before the model goes, while its turn can still be read.
	if respawns then
		standStump(def, node)
	end
	if not keepModel then
		node.model:Destroy()
	end
	if respawns and def.respawn then
		scheduleRespawn(node.nodeType, node.cell, def.respawn)
	end
end

-- Phase 3 registers cell modifiers here without giving the growth clock a sprinkler dependency.
local cellModifiers: (Vector3) -> Mutations.Chances = function(_: Vector3): Mutations.Chances
	return { wet = 0, shocked = 0, golden = 0 }
end

function WorldService.setChanceModifiers(provider: (Vector3) -> Mutations.Chances)
	cellModifiers = provider
end

-- How many times as fast a crop in a cell grows (sprinklers); FactoryService registers it.
local cellSpeed: (Vector3) -> number = function(_: Vector3): number
	return 1
end

function WorldService.setSpeedModifier(provider: (Vector3) -> number)
	cellSpeed = provider
end

-- How many times as fast a crop in `cell` would grow for the sprinklers over it.
function WorldService.speedAt(cell: Vector3): number
	return cellSpeed(cell)
end

-- GroundService reads speedAt for wet soil; research alone must not wet the ground.
local function growthSpeed(cell: Vector3): number
	return cellSpeed(cell) * (1 + Bonuses.at(cell, "growSpeed"))
end

function WorldService.chanceModifiers(cell: Vector3, offline: boolean?): Mutations.Chances
	local modifiers = if offline then { wet = 0, shocked = 0, golden = 0 } else cellModifiers(cell)
	local weather = if offline then "" else WeatherService.current()
	return {
		wet = modifiers.wet + (if weather == "Rain" or weather == "Thunderstorm" then 0.25 else 0),
		shocked = modifiers.shocked + (if weather == "Thunderstorm" then 0.05 else 0),
		golden = modifiers.golden + (if weather == "Golden Hour" then 0.05 else 0.01),
		multiplier = 1 + Bonuses.at(cell, "mutationChance"),
	}
end

-- Banks the extra growth since the last bank: rain's (WeatherService's clock) and the cell's
-- sprinkler/research speed, multiplied together. Called every grow tick, so a sprinkler placed or
-- removed changes a crop's speed within half a second.
local function bankGrowth(node: Node)
	local clock = WeatherService.bonusNow()
	local now = wallTime()
	if not World.isRipe(World.getNode(node.nodeType)) then
		local speed = growthSpeed(node.cell)
		node.growthBonus += (clock - node.weatherClock) * speed + (now - node.bankedAt) * (speed - 1)
	end
	node.weatherClock = clock
	node.bankedAt = now
end

type Timing = { regrowing: boolean, duration: number, elapsed: number, phase: number, nextAt: number }

-- Where a crop is in its growth, in growth seconds, as of its last bank.
local function timing(node: Node, crop: World.Crop): Timing
	local regrowing = crop.regrow ~= nil and node.harvestCount > 0
	local duration = if regrowing then crop.regrow or crop.grow else crop.grow
	local elapsed = math.max(0, wallTime() - (node.plantedAt or wallTime())) + node.growthBonus
	-- Four equal growth quarters; the last is fruit ripening, using Mature art until harvestable.
	local phase = math.clamp(math.floor(elapsed / crop.every) + 1, 1, 4)
	local nextAt = if regrowing then duration else math.min(phase * crop.every, duration)
	return { regrowing = regrowing, duration = duration, elapsed = elapsed, phase = phase, nextAt = nextAt }
end

local function grow(node: Node, offline: boolean?)
	local def = World.getNode(node.nodeType)
	local crop = if def.crop then World.CROPS[def.crop] else nil
	if not crop or not def.crop then
		return
	end
	bankGrowth(node)
	local plantedAt = node.plantedAt or wallTime()
	node.plantedAt = plantedAt
	local now = timing(node, crop)
	local regrowing, duration, elapsed, phase = now.regrowing, now.duration, now.elapsed, now.phase
	local stage = if elapsed >= duration then 4 elseif regrowing then 3 else math.min(phase, 3)
	if stage == 4 and not node.mutationRolled then
		node.mutation = Mutations.roll(random, WorldService.chanceModifiers(node.cell, offline))
		node.mutationRolled = true
	end
	if stage ~= def.stage then
		local nodeType = World.cropStage(def.crop, stage)
		local kept = morph(node.model, nodeType, node.cell)
		removeNode(node, kept)
		grow(
			spawnNode(
				nodeType,
				node.cell,
				false,
				plantedAt,
				node.harvestCount,
				node.mutation,
				node.growthBonus,
				node.mutationRolled,
				if kept then node.model else nil
			),
			offline
		)
		return
	end
	node.model:SetAttribute("PlantedAt", plantedAt)
	node.model:SetAttribute("HarvestCount", node.harvestCount)
	node.model:SetAttribute("Regrowing", regrowing and stage ~= 4)
	node.model:SetAttribute("Ripening", not regrowing and phase == 4 and stage ~= 4)
	node.model:SetAttribute("Mutation", node.mutation)
	if stage == 4 then
		node.model:SetAttribute("GrowsAt", nil)
		return
	end
	local nextAt = now.nextAt
	local remaining = math.max(0, nextAt - elapsed) / (WeatherService.speed() * growthSpeed(node.cell))
	local deadline = workspace:GetServerTimeNow() + remaining
	local previous = node.model:GetAttribute("GrowsAt")
	-- Clock sampling must not turn an unchanged deadline into a stream of attribute updates.
	if typeof(previous) ~= "number" or math.abs(previous - deadline) > 0.1 then
		node.model:SetAttribute("GrowsAt", deadline)
	end
end

-- One yield roll shared by the capacity check and the committed hand or machine harvest.
function WorldService.harvestCount(node: Node): number
	local def = World.getNode(node.nodeType)
	local crop = if def.crop then World.CROPS[def.crop] else nil
	assert(crop and World.isRipe(def), "WorldService.harvestCount: crop must be ripe")
	local amount = crop.yield * (1 + Bonuses.at(node.cell, "cropYield"))
	local whole = math.floor(amount)
	local fraction = amount - whole
	return whole + (if fraction > 0 and random:NextNumber() < fraction then 1 else 0)
end

local function harvestItems(node: Node, boosted: boolean?): { [string]: number }
	local def = World.getNode(node.nodeType)
	if def.crop and World.isRipe(def) then
		local crop = World.CROPS[def.crop]
		local id = crop.produce .. (if node.mutation then "+" .. node.mutation else "")
		return { [id] = if boosted then WorldService.harvestCount(node) else crop.yield }
	end
	return def.harvest or {}
end

local function awardHarvest(node: Node)
	local def = World.getNode(node.nodeType)
	local player = Bonuses.ownerAt(node.cell)
	if player and def.crop then
		GardenService.harvest(player, def.crop, node.mutation)
		GardenEvents.Harvested:Fire(player, def.crop, node.mutation, node.cell)
	end
end
-- The node covering `cell`, if any.
function WorldService.nodeAt(cell: Vector3): Node?
	return nodesByCell[cellKey(cell)]
end

-- Nodes of the given types within `radius` studs of `position`.
function WorldService.nodesNear(position: Vector3, radius: number, types: { [string]: any }): { Node }
	local found = {}
	for _, node in living do
		if types[node.nodeType] and (node.model:GetPivot().Position - position).Magnitude <= radius then
			table.insert(found, node)
		end
	end
	return found
end

-- Whether `itemId` (a seed) could stand in `cell`: in a garden, soil under it if it needs some,
-- and nothing in the way: its own cell, or with `column` the whole column a tree keeps clear
-- above it (World.plantColumn), all of it in the garden.
local function canStand(cell: Vector3, itemId: string, column: boolean): boolean
	local reserve = World.plantColumn(itemId)
	if not reserve or Plot.at(cell) == nil or not Soil.canPlant(itemId, cell) then
		return false
	end
	local size = if column then reserve else Vector3.one
	return Plot.at(cell + Vector3.yAxis * (size.Y - 1)) ~= nil and cellsClear(cell, size, nil)
end

-- Whether `itemId` (a seed) could be planted in `cell`: nothing in its column, and soil under it
-- if it needs some.
function WorldService.canPlant(cell: Vector3, itemId: string): boolean
	return canStand(cell, itemId, true)
end

-- Plants a seed in `cell`. Returns whether it did.
function WorldService.plant(cell: Vector3, itemId: string): boolean
	if not WorldService.canPlant(cell, itemId) then
		return false
	end
	grow(spawnNode(World.PLANTS[itemId].node, cell, false))
	return true
end

-- A multi harvest keeps the plant; a machine also keeps a single crop by restarting it.
function WorldService.reap(node: Node): boolean
	local def = World.getNode(node.nodeType)
	local crop = def.crop
	if nodesByModel[node.model] ~= node or not crop or not World.isRipe(def) then
		return false
	end
	local stage = if World.CROPS[crop].regrow then 3 else 1
	local nodeType = World.cropStage(crop, stage)
	local kept = morph(node.model, nodeType, node.cell)
	removeNode(node, kept)
	awardHarvest(node)
	grow(
		spawnNode(
			nodeType,
			node.cell,
			node.natural,
			wallTime(),
			node.harvestCount + 1,
			nil,
			nil,
			nil,
			if kept then node.model else nil
		)
	)
	return true
end

local function splash(node: Node)
	local hitbox = node.model.PrimaryPart
	if not hitbox then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, hitbox.Size.Y / 2, 0)
	local drops = Instance.new("ParticleEmitter")
	drops.Color = ColorSequence.new(Color3.fromRGB(170, 214, 240))
	drops.Size = NumberSequence.new(0.18, 0.05)
	drops.Transparency = NumberSequence.new(0.2, 1)
	drops.Lifetime = NumberRange.new(0.4, 0.7)
	drops.Speed = NumberRange.new(4, 7)
	drops.SpreadAngle = Vector2.new(35, 35)
	drops.Acceleration = Vector3.new(0, -30, 0)
	drops.Rate = 0
	drops.Parent = attachment
	attachment.Parent = hitbox
	drops:Emit(16)
	task.delay(1, function()
		attachment:Destroy()
	end)
end

-- A watering can splash: a fifth off what's left of a growing crop's stage.
local function water(player: Player, node: Node)
	local def = World.getNode(node.nodeType)
	local crop = if def.crop then World.CROPS[def.crop] else nil
	local now = os.clock()
	if not crop or World.isRipe(def) or now - (lastWatered[player] or 0) < WATER_COOLDOWN then
		return
	end
	lastWatered[player] = now
	bankGrowth(node)
	local at = timing(node, crop)
	node.growthBonus += math.max(0, at.nextAt - at.elapsed) * WATER_SHARE
	splash(node)
	GardenEvents.Watered:Fire(player, node.cell)
	grow(node)
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
	-- Ground answers to GroundService.
	if def.ground or (def.crop and not Build.canEdit(player, node.cell, node.footprint)) then
		return
	end
	local held = InventoryService.getHeldItemId(player)
	if action == "Use" and held == "WateringCan" then
		water(player, node)
	elseif action == "Use" then
		if not def.tool or held ~= def.tool then
			return
		end
		local drops = table.clone(def.drops or {})
		if def.boost then
			local boost = def.boost
			drops[boost.item] = (drops[boost.item] or 0) + Bonuses.get(player, boost.stat)
		end
		if not InventoryService.canGiveAll(player, drops) then
			return
		end
		local look = node.model:GetAttribute("Look")
		local pivot = node.model:GetPivot()
		removeNode(node)
		giveAll(player, drops)
		if def.tool == "Axe" then
			GardenEvents.Chopped:Fire(
				player,
				node.nodeType,
				node.cell,
				if typeof(look) == "string" then look else node.nodeType,
				pivot
			)
		else
			GardenEvents.Mined:Fire(player, node.nodeType, node.cell)
		end
	elseif action == "Take" and def.harvest then
		if held then
			return
		end
		local harvest = harvestItems(node, true)
		if not InventoryService.canGiveAll(player, harvest) then
			Remotes.Notify:FireClient(player, "Your inventory is full.", "Error")
			return
		end
		if def.crop and World.isRipe(def) then
			if World.CROPS[def.crop].regrow then
				WorldService.reap(node)
			else
				awardHarvest(node)
				removeNode(node)
			end
		else
			removeNode(node)
		end
		giveAll(player, harvest)
	end
end

-- A crop whose soil is dug away is uprooted, its harvest tossed out as drops: its seed back, or
-- when ripe its produce.
function WorldService.uproot(cell: Vector3)
	local node = nodesByCell[cellKey(cell)]
	if not node or not World.getNode(node.nodeType).crop then
		return
	end
	local at = node.model:GetPivot().Position + Vector3.yAxis
	removeNode(node)
	for dropId, count in harvestItems(node) do
		local toss = Vector3.new(random:NextNumber(-1, 1), 1.5, random:NextNumber(-1, 1)).Unit * UPROOT_SPEED
		DropService.spawn(dropId, CFrame.new(at), toss, count)
	end
end

-- A ground node, for GroundService, which owns where ground stands.
function WorldService.spawnGround(nodeType: string, cell: Vector3): Node
	assert(World.getNode(nodeType).ground, `WorldService.spawnGround: "{nodeType}" is not ground`)
	return spawnNode(nodeType, cell, false)
end

function WorldService.removeGround(node: Node)
	assert(World.getNode(node.nodeType).ground, "WorldService.removeGround: not a ground node")
	removeNode(node)
end

function WorldService.snapshot(index: number): { Plot.SavedCrop }
	local crops: { Plot.SavedCrop } = {}
	for _, node in living do
		local def = World.getNode(node.nodeType)
		if def.crop and Plot.at(node.cell) == index then
			bankGrowth(node)
			table.insert(crops, {
				cropId = def.crop,
				cell = Plot.pack(Plot.toRelative(index, node.cell)),
				plantedAt = node.plantedAt or wallTime(),
				harvestCount = node.harvestCount,
				mutation = node.mutation,
				mutationRolled = node.mutationRolled,
				growthBonus = node.growthBonus,
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
	if cell.Y <= Plot.FLOOR or cell.Y >= Plot.HEIGHT then
		return false
	end
	-- Only its own cell: a tree saved before trees kept their column clear may have blocks built
	-- above it, and keeps growing through them rather than being lost.
	if not canStand(cell, crop.seed, false) then
		return false
	end
	if typeof(saved.plantedAt) ~= "number" or not (saved.plantedAt >= 0 and saved.plantedAt <= wallTime()) then
		return false
	end
	if typeof(saved.harvestCount) ~= "number" or saved.harvestCount < 0 or saved.harvestCount % 1 ~= 0 then
		return false
	end
	if saved.mutation ~= nil and (typeof(saved.mutation) ~= "string" or not Mutations.parse(saved.mutation)) then
		return false
	end
	if
		saved.growthBonus ~= nil
		and (typeof(saved.growthBonus) ~= "number" or not (saved.growthBonus >= 0 and saved.growthBonus < math.huge))
	then
		return false
	end
	if saved.mutationRolled ~= nil and typeof(saved.mutationRolled) ~= "boolean" then
		return false
	end
	grow(
		spawnNode(
			World.cropStage(saved.cropId, 1),
			cell,
			false,
			saved.plantedAt,
			saved.harvestCount,
			saved.mutation,
			saved.growthBonus,
			saved.mutationRolled
		),
		true
	)
	return true
end

function WorldService.clearPlot(index: number)
	local remove = {}
	for _, node in living do
		if World.getNode(node.nodeType).crop and Plot.at(node.cell) == index then
			table.insert(remove, node)
		end
	end
	for _, node in remove do
		removeNode(node)
	end
end

function WorldService.init()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local growing = {}
			for _, node in living do
				if World.getNode(node.nodeType).crop and not World.isRipe(World.getNode(node.nodeType)) then
					table.insert(growing, node)
				end
			end
			for _, node in growing do
				grow(node)
			end
		end
	end)
	for _, spot in Layout.nodes do
		spawnNode(spot.node, spot.cell, true)
	end
	Remotes.Interact.OnServerEvent:Connect(onInteract)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		lastWatered[player] = nil
	end)
end

return WorldService
