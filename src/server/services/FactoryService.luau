-- FactoryService: runs every placed factory block (Shared/Factory). It registers a block
-- when it lands in Workspace.Placed, connects it to its neighbours by their ports, and
-- every frame moves items along lanes, through router hubs and into and out of machines.
-- Wood tubes form networks that carry sap and syrup between maple trees, sap boilers and
-- syrup bottlers. A Wood Tube joins the tube it is placed against and shapes itself to what
-- it joins (straight, corner, vertical or an elbow up or down), redrawn with that shape's art.
-- Players work machines only through their panel (load, collect, take
-- back), and take belt items and switch routers by hand, all through Interact.
--
-- Two ports connect when one block's exit and another's entry share a point and face each
-- other; there is no other wiring. Items only ever move on the server: clients get each
-- lane's item list when an item joins or leaves it (FactorySync) and slide items along
-- with the same Lane rule in between. Machines publish what they hold and why they are
-- idle as attributes on their model, for players to read.
--
-- Belts meet loose items too (DropService). An item reaching a lane end, or a machine's
-- output face, that connects to nothing is thrown off as a physical drop when the cell in
-- front is empty -- and waits, as at any blocked end, when something stands there. A
-- machine with belt art on its output face puts what it makes onto that belt (its own
-- lane, Factory.lanes), so its output rides out and falls off the end like any conveyor's. A drop
-- that touches any block's belt joins it where it touched, if there is room; one landing on
-- a machine's input end goes into the machine, if it takes it. A player walking over a
-- belt picks up the items under their feet.
--
-- A machine whose input face has belt art takes items only where that belt meets its port:
-- the belt is a lane of its own (Factory.lanes) that items ride in on, and the machine
-- takes the front one at its end. When it has no room for that one, it takes the first item
-- queued up behind it that it does take (pullQueued), so surplus fuel can't starve it of ore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Build = require(ReplicatedStorage.Shared.Build)
local Factory = require(ReplicatedStorage.Shared.Factory)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Machine = require(ServerScriptService.Libraries.Machine)
local DropService = require(script.Parent.DropService)
local InventoryService = require(script.Parent.InventoryService)
local WorldService = require(script.Parent.WorldService)

type Entry = {
	block: Block,
	-- The lane whose start this is, or nil for a machine's input face.
	lane: LaneState?,
	normal: Vector3,
}

type LaneState = {
	key: string,
	block: Block,
	index: number,
	def: Factory.LaneDef,
	points: { Vector3 },
	length: number,
	items: { Lane.Item },
	exitPort: Factory.Port?,
	-- Cached neighbour at the exit, valid while `version` matches the topology.
	target: Entry?,
	version: number,
}

type Network = {
	machines: { [Block]: boolean },
	trees: { [WorldService.Node]: boolean },
	tubes: { Block },
}

export type Block = {
	id: number,
	model: Model,
	itemId: string,
	def: Factory.Def,
	frame: CFrame,
	ext: Factory.Extents,
	origin: Vector3,
	footprint: Vector3,
	lanes: { LaneState },
	machine: Machine.State?,
	-- A machine's input belt (items ride it in) and output belt (its products ride it out).
	feedLane: LaneState?,
	outputLane: LaneState?,
	inputPort: Factory.Port?,
	outputPort: Factory.Port?,
	outputTarget: Entry?,
	outputVersion: number,
	-- Routers.
	filter: { [string]: boolean },
	powered: boolean,
	pulseUntil: number,
	-- Tubes: outward world directions of the openings, and whether sap or syrup has run
	-- through it (it shows its fluid only then).
	openings: { Vector3 },
	filled: boolean,
	-- Auto tubes (WoodTube): the directions it is joined to (at most two), and the art it is
	-- drawn with now ("<art>/<quarter turns>").
	links: { Vector3 },
	shape: string?,
	env: Machine.Env?,
}

-- Seconds between machine status refreshes.
local STATUS_EVERY = 0.25
-- Seconds between wood tube rounds, and between full network rebuilds (which catch trees
-- that grew or were chopped).
local TUBE_EVERY = 0.5
local TUBE_REBUILD_EVERY = 5
-- The shapes an auto tube takes: art in Assets.Blocks and its openings in its authored frame.
-- A tube is drawn with the first whose openings, turned some quarter turns, are its ends.
local TUBE_SHAPES = {
	{ art = "WoodTube", openings = { -Vector3.zAxis, Vector3.zAxis } },
	{ art = "WoodTubeCorner", openings = { -Vector3.zAxis, Vector3.xAxis } },
	{ art = "WoodTubeAscend", openings = { -Vector3.zAxis, Vector3.yAxis } },
	{ art = "WoodTubeDescend", openings = { -Vector3.zAxis, -Vector3.yAxis } },
	{ art = "WoodTubeVertical", openings = { -Vector3.yAxis, Vector3.yAxis } },
}
-- Seconds a sensor powers the split conveyors touching it.
local PULSE = 1
-- Seconds a sensor's light curtain shows after an item passes.
local FLASH = 0.4
-- Most items a filter conveyor filters.
local FILTER_MAX = 4
-- Seconds an open-end check stays good; the world in front can change without the topology.
local OPEN_RECHECK = 0.5
-- Studs from a lane's path within which a drop counts as touching the belt.
local CATCH_DISTANCE = 1.8
-- Upward studs per second an item thrown off an open end leaves with.
local THROW_LIFT = 1.5
-- Studs per second a machine pushes its output off an open face.
local MACHINE_THROW = 4
-- Studs above a block's hitbox a drop aimed at its belt appears.
local DROP_HEIGHT = 0.5
-- Most queued items a machine looks through past a front item it won't take.
local PULL_DEPTH = 12
-- Seconds between one player's interactions; caps how fast a client can spam remotes.
local COOLDOWN = 0.15
-- Seconds between checks for players walking over belt items.
local PICKUP_EVERY = 0.1
-- Studs across the belt from a player's feet within which they walk an item up.
local PICKUP_RADIUS = 1.75
-- Seconds an item caught off a player's drop rides before that player can walk it up, so
-- dropping onto a belt you stand on doesn't put the item straight back in your hand.
local PICKUP_GRACE = 1.5
local NEIGHBOURS = {
	Vector3.xAxis,
	-Vector3.xAxis,
	Vector3.yAxis,
	-Vector3.yAxis,
	Vector3.zAxis,
	-Vector3.zAxis,
}

local FactoryService = {}

local function placedFolder(): Folder
	local existing = workspace:FindFirstChild("Placed")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Placed"
	folder.Parent = workspace
	return folder
end

local placed = placedFolder()
local blocks: { [Model]: Block } = {}
local cellIndex: { [string]: Block } = {}
local entries: { [string]: { Entry } } = {}
local laneSet: { [LaneState]: boolean } = {}
-- The lanes whose front item moves on into each lane, valid while `feedersVersion` matches
-- the topology.
local feeders: { [LaneState]: { LaneState } } = {}
local feedersVersion = -1
local dirty: { [LaneState]: boolean } = {}
-- Lanes cleared since the last update, by key.
local cleared: { [string]: boolean } = {}
-- Random routers decide once per item, so a blocked item doesn't flip-flop.
local randomChoice: { [number]: number } = {}
local networks: { Network } = {}
local sapTimers: { [WorldService.Node]: number } = {}
local lastAction: { [Player]: number } = {}
-- Whether the cell past an unconnected port is empty, and when (os.clock()) that was seen.
local openCache: { [Factory.Port]: { open: boolean, checked: number } } = setmetatable({}, { __mode = "k" }) :: any
-- Item id -> the player who dropped it, and the os.clock() before which they can't walk it
-- up (PICKUP_GRACE).
local graces: { [number]: { dropper: Player, expires: number } } = {}
local pickupTimer = 0
local topology = 0
local overlapParams = Build.newOverlapParams()
local tubesStale = true
local nextBlockId = 0
local nextItemId = 0
local statusTimer = 0
local tubeTimer = 0
local rebuildTimer = 0

local function cellKey(cell: Vector3): string
	return `{cell.X},{cell.Y},{cell.Z}`
end

local function newItemId(): number
	nextItemId += 1
	return nextItemId
end

local function markDirty(lane: LaneState)
	dirty[lane] = true
end

local function eachCell(origin: Vector3, footprint: Vector3, visit: (Vector3) -> ())
	for x = 0, footprint.X - 1 do
		for y = 0, footprint.Y - 1 do
			for z = 0, footprint.Z - 1 do
				visit(origin + Vector3.new(x, y, z))
			end
		end
	end
end

local function cellOf(position: Vector3): Vector3
	local scaled = position / Build.GRID
	return Vector3.new(math.floor(scaled.X), math.floor(scaled.Y), math.floor(scaled.Z))
end

local function centreOf(block: Block): Vector3
	return Build.box(block.origin, block.footprint).Position
end

local function addEntry(port: Factory.Port, entry: Entry)
	local key = Factory.portKey(port.position)
	local list = entries[key]
	if not list then
		list = {}
		entries[key] = list
	end
	table.insert(list, entry)
end

-- The entry facing `port` at the same point, if a block offers one.
local function connect(port: Factory.Port): Entry?
	local list = entries[Factory.portKey(port.position)]
	if not list then
		return nil
	end
	for _, entry in list do
		if entry.normal:Dot(port.normal) < -0.9 then
			return entry
		end
	end
	return nil
end

local function laneTarget(lane: LaneState): Entry?
	local port = lane.exitPort
	if not port then
		return nil
	end
	if lane.version ~= topology then
		lane.target = connect(port)
		lane.version = topology
	end
	return lane.target
end

local function outputTarget(block: Block): Entry?
	local port = block.outputPort
	if not port then
		return nil
	end
	if block.outputVersion ~= topology then
		block.outputTarget = connect(port)
		block.outputVersion = topology
	end
	return block.outputTarget
end

local function isPowered(block: Block): boolean
	return block.powered or block.pulseUntil > workspace:GetServerTimeNow()
end

local function flash(block: Block)
	local curtain = block.model:FindFirstChild(`Mesh_{block.itemId}_LightCurtain`)
	if curtain and curtain:IsA("BasePart") then
		curtain.Transparency = 0.4
		task.delay(FLASH, function()
			curtain.Transparency = 1
		end)
	end
end

-- A sensor saw an item: flash, and power every split conveyor touching it.
local function pulse(sensor: Block)
	flash(sensor)
	local poweredUntil = workspace:GetServerTimeNow() + PULSE
	eachCell(sensor.origin, sensor.footprint, function(cell)
		for _, offset in NEIGHBOURS do
			local other = cellIndex[cellKey(cell + offset)]
			if other and other ~= sensor and other.def.route == "Split" then
				other.pulseUntil = poweredUntil
			end
		end
	end)
end

-- Hands an item to an entry. Returns whether it was taken.
local function deliver(entry: Entry, itemId: string, id: number): boolean
	local lane = entry.lane
	if lane then
		if not Lane.hasRoom(lane.items) then
			return false
		end
		table.insert(lane.items, { id = id, itemId = itemId, d = 0 })
		markDirty(lane)
		if entry.block.def.sensor then
			pulse(entry.block)
		end
		return true
	end
	local machine = entry.block.machine
	return machine ~= nil and Machine.insert(machine, itemId, 1) == 1
end

-- The out-lane an item at a router's hub goes to.
local function routeOut(block: Block, item: Lane.Item): LaneState?
	local route = block.def.route
	local lanes = block.lanes
	if route == "Merge" then
		return lanes[3]
	elseif route == "Split" then
		return if isPowered(block) then lanes[3] else lanes[2]
	elseif route == "Filter" then
		return if block.filter[item.itemId] then lanes[3] else lanes[2]
	end
	local choice = randomChoice[item.id]
	if not choice then
		choice = math.random(2, 3)
		randomChoice[item.id] = choice
	end
	return lanes[choice]
end

-- Whether nothing but characters and loose drops stands in the cell past an unconnected
-- port.
local function isOpen(port: Factory.Port): boolean
	local now = os.clock()
	local cached = openCache[port]
	if cached and now - cached.checked < OPEN_RECHECK then
		return cached.open
	end
	local centre, size = Build.box(cellOf(port.position + port.normal * (Build.GRID / 2)), Vector3.one)
	local open = true
	for _, part in workspace:GetPartBoundsInBox(centre, size, overlapParams) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not Build.isLoose(part) and (not model or not Players:GetPlayerFromCharacter(model)) then
			open = false
			break
		end
	end
	openCache[port] = { open = open, checked = now }
	return open
end

-- Sends an item flying off `port` at `speed` studs per second.
local function throwOff(port: Factory.Port, speed: number, itemId: string)
	local at = CFrame.lookAlong(port.position + port.normal * 0.6 + Vector3.yAxis * 0.6, port.normal)
	DropService.spawn(itemId, at, port.normal * speed + Vector3.yAxis * THROW_LIFT)
end

-- The stretch of belt just inside a machine's input face, from the face inwards.
local function inputBelt(port: Factory.Port): { Vector3 }
	return { port.position, port.position - port.normal * Build.GRID }
end

-- Whether a drop at `position` lies over a belt, at its height or above. Height is left
-- out of the distance: a drop resting on a router's hub cover, or on top of a machine with
-- no belt art over its input, still counts, as does one caught on the art's collision hull
-- before it settles.
local function isOver(points: { Vector3 }, position: Vector3): boolean
	local flat = {}
	for index, point in points do
		flat[index] = Vector3.new(point.X, position.Y, point.Z)
	end
	local d, distance = Lane.project(flat, position)
	local belt = Lane.pointAt(points, d * Lane.length(points) / math.max(Lane.length(flat), 1e-3))
	return distance <= CATCH_DISTANCE and position.Y >= belt.Y - 1
end

-- Puts one item a drop at `position` carries onto the belt it lies over, if there is room
-- there, or into the machine whose input end it lies on, if it takes it. Only the drop's
-- cell and the one just under it are looked at, so a belt never reaches through a block
-- above it. Returns whether it did.
local function catch(itemId: string, position: Vector3, dropper: Player?): boolean
	for _, cell in { cellOf(position), cellOf(position - Vector3.yAxis) } do
		local block = cellIndex[cellKey(cell)]
		if not block then
			continue
		end
		for _, lane in block.lanes do
			local d = Lane.project(lane.points, position)
			local item = { id = newItemId(), itemId = itemId, d = d }
			if isOver(lane.points, position) and Lane.insert(lane.items, item) then
				markDirty(lane)
				if dropper then
					graces[item.id] = { dropper = dropper, expires = os.clock() + PICKUP_GRACE }
				end
				return true
			end
		end
		-- A machine with no input belt to ride takes a drop lying on its input end directly.
		local machine = block.machine
		local port = if block.feedLane then nil else block.inputPort
		local onInput = port ~= nil and isOver(inputBelt(port), position)
		if machine and onInput and Machine.insert(machine, itemId, 1) == 1 then
			return true
		end
	end
	return false
end

-- Where a drop aimed at a placed block's belt appears: over its first lane, a cell's
-- half in from the start (the middle of a plain conveyor, and clear of a router's hub
-- cover), or over a machine's input end; nil for a block with no belt to drop onto.
local function dropPoint(model: Model): Vector3?
	local block = blocks[model]
	if not block then
		return nil
	end
	local box, size = Build.box(block.origin, block.footprint)
	local first = if block.machine then block.feedLane else block.lanes[1]
	local over: Vector3? = nil
	if first then
		over = Lane.pointAt(first.points, math.min(first.length / 2, Build.GRID / 2))
	elseif block.inputPort then
		over = block.inputPort.position - block.inputPort.normal * (Build.GRID / 2)
	end
	if not over then
		return nil
	end
	return Vector3.new(over.X, box.Position.Y + size.Y / 2 + DROP_HEIGHT, over.Z)
end

-- What moves into `lane`: lanes whose exit joins its start, and a merger's in-lanes for its
-- out-lane. Other routers decide per item, so the lanes into them are left out.
local function feedersOf(lane: LaneState): { LaneState }
	if feedersVersion ~= topology then
		feeders = {}
		local function add(from: LaneState, into: LaneState)
			local list = feeders[into]
			if not list then
				list = {}
				feeders[into] = list
			end
			table.insert(list, from)
		end
		for other in laneSet do
			if other.def.exit then
				local target = laneTarget(other)
				if target and target.lane then
					add(other, target.lane)
				end
			elseif other.block.def.route == "Merge" and other ~= other.block.lanes[3] then
				add(other, other.block.lanes[3])
			end
		end
		feedersVersion = topology
	end
	return feeders[lane] or {}
end

-- A machine whose front item at its input won't go in takes the first item queued up behind
-- it that will, so surplus fuel waits on the belt instead of starving it of ore. The queue
-- runs back over `lane` (past its front) and every lane backed up into it. Returns whether it
-- took one.
local function pullQueued(machine: Machine.State, lane: LaneState): boolean
	local looked = 0
	local visit = { lane }
	local seen = { [lane] = true }
	local at = 1
	while at <= #visit and looked < PULL_DEPTH do
		local current = visit[at]
		local queued = Lane.queued(current.items, current.length)
		for index = if current == lane then 2 else 1, queued do
			looked += 1
			if looked > PULL_DEPTH then
				return false
			end
			if Machine.insert(machine, current.items[index].itemId, 1) == 1 then
				randomChoice[current.items[index].id] = nil
				table.remove(current.items, index)
				markDirty(current)
				return true
			end
		end
		-- Lanes upstream only wait on this one when it is backed up all the way to its start.
		local last = current.items[queued]
		if queued > 0 and queued == #current.items and last.d < Lane.SPACING + 1e-3 then
			for _, from in feedersOf(current) do
				if not seen[from] then
					seen[from] = true
					table.insert(visit, from)
				end
			end
		end
		at += 1
	end
	return false
end

local function stepLanes(dt: number)
	for lane in laneSet do
		Lane.advance(lane.items, dt, lane.def.speed, lane.length)
	end
	for lane in laneSet do
		local front = Lane.waiting(lane.items, lane.length)
		if not front then
			continue
		end
		if lane.def.feeds then
			-- A machine's input belt: the item goes in once it reaches the port, or waits there
			-- while the machine takes what it can from behind it.
			local machine = lane.block.machine
			if machine and Machine.insert(machine, front.itemId, 1) == 1 then
				table.remove(lane.items, 1)
				markDirty(lane)
			elseif machine then
				pullQueued(machine, lane)
			end
		elseif lane.def.exit then
			local target = laneTarget(lane)
			if target and deliver(target, front.itemId, front.id) then
				table.remove(lane.items, 1)
				markDirty(lane)
			elseif target and not target.lane and target.block.machine then
				pullQueued(target.block.machine, lane)
			elseif not target and lane.exitPort and isOpen(lane.exitPort) then
				table.remove(lane.items, 1)
				markDirty(lane)
				throwOff(lane.exitPort, lane.def.speed, front.itemId)
			end
		else
			local out = routeOut(lane.block, front)
			if out and Lane.hasRoom(out.items) then
				table.remove(lane.items, 1)
				table.insert(out.items, { id = front.id, itemId = front.itemId, d = 0 })
				randomChoice[front.id] = nil
				markDirty(lane)
				markDirty(out)
			end
		end
	end
end

local function sourceNames(sources: { [string]: Factory.Source }, lookup: (string) -> string): string
	local names = {}
	for sourceType in sources do
		table.insert(names, lookup(sourceType))
	end
	table.sort(names)
	return table.concat(names, " or ")
end

local function withArticle(text: string): string
	return if string.find(text, "^[AEIOU]") then `an {text}` else `a {text}`
end

local function nodeName(nodeType: string): string
	return World.getNode(nodeType).name
end

local function animalName(animalType: string): string
	return World.getAnimal(animalType).name
end

local function treeCellOf(block: Block): Vector3?
	local treeCell = block.def.treeCell
	return if treeCell then cellOf(block.frame:PointToWorldSpace(treeCell(block.ext))) else nil
end

local function treeNode(block: Block): WorldService.Node?
	local produce = block.def.produce
	local cell = treeCellOf(block)
	local node = if cell then WorldService.nodeAt(cell) else nil
	return if node and produce and produce.sources[node.nodeType] then node else nil
end

-- What the world offers a producer right now, or nil and why not.
local function findSource(block: Block): (Factory.Source?, string?)
	local produce = block.def.produce
	if not produce then
		return nil, nil
	end
	local sources = produce.sources
	local radius = (produce.radius or 6) * Build.GRID
	if produce.where == "Below" then
		local below = block.origin - Vector3.yAxis
		for x = 0, block.footprint.X - 1 do
			for z = 0, block.footprint.Z - 1 do
				local node = WorldService.nodeAt(below + Vector3.new(x, 0, z))
				if node and sources[node.nodeType] then
					return sources[node.nodeType], nil
				end
			end
		end
		return nil, `Needs {withArticle(sourceNames(sources, nodeName))} below`
	elseif produce.where == "Near" then
		local node = WorldService.nodesNear(centreOf(block), radius, sources)[1]
		if node then
			return sources[node.nodeType], nil
		end
		return nil, `Needs {withArticle(sourceNames(sources, nodeName))} nearby`
	elseif produce.where == "Tree" then
		local node = treeNode(block)
		if node then
			return sources[node.nodeType], nil
		end
		return nil, `Needs {withArticle(sourceNames(sources, nodeName))} in front`
	end
	for _, animal in WorldService.animalsNear(centreOf(block), radius, sources) do
		if WorldService.isFed(animal) then
			return sources[animal.animalType], nil
		end
	end
	return nil, `Needs a fed {sourceNames(sources, animalName)} nearby`
end

local function envFor(block: Block): Machine.Env
	local existing = block.env
	if existing then
		return existing
	end
	local def = block.def
	local env: Machine.Env = {}
	if def.produce then
		env.source = function()
			return findSource(block)
		end
		env.chop = function()
			local node = treeNode(block)
			return if node then WorldService.chop(node) else nil
		end
		env.reap = function(source)
			local produce = def.produce
			if not produce then
				return false
			end
			local radius = (produce.radius or 6) * Build.GRID
			for _, node in WorldService.nodesNear(centreOf(block), radius, produce.sources) do
				if produce.sources[node.nodeType] == source and WorldService.reap(node) then
					return true
				end
			end
			return false
		end
	end
	if def.plants then
		env.canPlant = function(itemId)
			local cell = treeCellOf(block)
			return cell ~= nil and WorldService.canPlant(cell, itemId)
		end
		env.plant = function(itemId)
			local cell = treeCellOf(block)
			return cell ~= nil and WorldService.plant(cell, itemId)
		end
	end
	if def.feeds then
		env.feed = function(food)
			return WorldService.feedNear(centreOf(block), (def.feedRadius or 6) * Build.GRID, food)
		end
	end
	block.env = env
	return env
end

local function stepMachines(dt: number)
	for _, block in blocks do
		local machine = block.machine
		if not machine then
			continue
		end
		Machine.step(machine, dt, envFor(block))
		local itemId = Machine.peekOutput(machine)
		local belt = block.outputLane
		if belt then
			-- Onto its output belt, which hands it on or throws it off at the face (stepLanes).
			if itemId and Lane.hasRoom(belt.items) then
				Machine.popOutput(machine)
				table.insert(belt.items, { id = newItemId(), itemId = itemId, d = 0 })
				markDirty(belt)
			end
			continue
		end
		local port = block.outputPort
		local target = if itemId then outputTarget(block) else nil
		if itemId and target and deliver(target, itemId, newItemId()) then
			Machine.popOutput(machine)
		elseif itemId and port and not target and isOpen(port) then
			Machine.popOutput(machine)
			throwOff(port, MACHINE_THROW, itemId)
		end
	end
end

local function blockAt(cell: Vector3): Block?
	return cellIndex[cellKey(cell)]
end

local function tubeCell(block: Block): Vector3
	return block.origin
end

local function isTube(block: Block?): boolean
	return block ~= nil and block.def.kind == "Tube"
end

local function opensToward(openings: { Vector3 }, direction: Vector3): boolean
	for _, opening in openings do
		if opening:Dot(direction) > 0.9 then
			return true
		end
	end
	return false
end

local function hasOpening(block: Block, direction: Vector3): boolean
	return opensToward(block.openings, direction)
end

local function setFluidVisible(block: Block, visible: boolean)
	for _, part in block.model:GetChildren() do
		if part:IsA("BasePart") and string.sub(part.Name, -6) == "_Fluid" then
			part.Transparency = if visible then 0 else 1
		end
	end
end

local function isAuto(block: Block?): boolean
	return block ~= nil and block.def.auto == true
end

local function axis(vector: Vector3): Vector3
	return Vector3.new(math.round(vector.X), math.round(vector.Y), math.round(vector.Z))
end

-- An auto tube's two ends: its links, and for a missing one the end straight across from
-- the other (with no links, both ends along the way it was placed facing).
local function tubeEnds(block: Block): { Vector3 }
	local links = block.links
	if #links >= 2 then
		return table.clone(links)
	elseif #links == 1 then
		return { links[1], -links[1] }
	end
	local along = axis(block.frame.LookVector)
	return { along, -along }
end

local function shapeFor(ends: { Vector3 }): (string, number)
	for _, shape in TUBE_SHAPES do
		for turns = 0, 3 do
			local turn = CFrame.Angles(0, turns * math.pi / 2, 0)
			local matches = true
			for _, opening in shape.openings do
				if not opensToward(ends, axis(turn:VectorToWorldSpace(opening))) then
					matches = false
					break
				end
			end
			if matches then
				return shape.art, turns
			end
		end
	end
	return TUBE_SHAPES[1].art, 0
end

-- Replaces the tube's art with `art` turned `turns` quarter turns about its cell, keeping
-- its Hitbox (the model stays the WoodTube block it was placed as).
local function drawTube(block: Block, art: string, turns: number)
	local template = Build.getTemplate(art)
	local authored = if template then Factory.originFrame(template) else nil
	local copy = Build.copyArt(art)
	if not authored or not copy then
		return
	end
	for _, child in block.model:GetChildren() do
		if child:IsA("BasePart") and child ~= block.model.PrimaryPart then
			child:Destroy()
		end
	end
	local target = CFrame.new(block.frame.Position) * CFrame.Angles(0, turns * math.pi / 2, 0)
	copy:PivotTo(target * authored:ToObjectSpace(copy:GetPivot()))
	for _, part in copy:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.Parent = block.model
		end
	end
	copy:Destroy()
	setFluidVisible(block, block.filled)
end

-- Works out an auto tube's openings from its links and redraws it when its shape changed.
local function reshape(block: Block)
	block.openings = tubeEnds(block)
	local art, turns = shapeFor(block.openings)
	local shape = `{art}/{turns}`
	if block.shape ~= shape then
		block.shape = shape
		drawTube(block, art, turns)
	end
	tubesStale = true
end

-- Whether `other` takes a tube joining it from `direction` (pointing from it toward the
-- tube): an auto tube with an end to spare, a fixed tube opening that way, or a sap machine.
local function accepts(other: Block, direction: Vector3): boolean
	if isAuto(other) then
		return #other.links < 2 and not opensToward(other.links, direction)
	elseif isTube(other) then
		return opensToward(other.openings, direction)
	end
	return other.def.tubes == true
end

-- A new auto tube joins what it was placed against (`against` points from that block to
-- it) when that can take it: on top of a tube it goes up from it, beside one it turns
-- off it. Then it joins any neighbouring tube whose spare end already points at it,
-- until both its ends are used.
local function joinTube(block: Block, against: Vector3?)
	local cell = tubeCell(block)
	local function join(direction: Vector3)
		if #block.links >= 2 or opensToward(block.links, direction) then
			return
		end
		local other = blockAt(cell + direction)
		local node = WorldService.nodeAt(cell + direction)
		if other and other ~= block and accepts(other, -direction) then
			table.insert(block.links, direction)
			if isAuto(other) then
				table.insert(other.links, -direction)
				reshape(other)
			end
		elseif not other and node and World.getNode(node.nodeType).sap then
			table.insert(block.links, direction)
		end
	end
	if against then
		join(-against)
	end
	for _, direction in NEIGHBOURS do
		local other = blockAt(cell + direction)
		if other and isTube(other) and opensToward(other.openings, -direction) then
			join(direction)
		end
	end
	reshape(block)
end

-- A removed auto tube lets go of the auto tubes it was joined to, which reshape.
local function leaveTube(block: Block)
	for _, direction in block.links do
		local other = blockAt(tubeCell(block) + direction)
		if other and isAuto(other) then
			local index = table.find(other.links, -direction)
			if index then
				table.remove(other.links, index)
				reshape(other)
			end
		end
	end
end

-- Whether anything on the network puts fluid into it: a tapped maple tree, or a machine
-- that makes a fluid.
local function hasSource(network: Network): boolean
	if next(network.trees) then
		return true
	end
	for block in network.machines do
		for _, recipe in block.def.recipes or {} do
			if recipe.fluidOut then
				return true
			end
		end
	end
	return false
end

local function setFilled(network: Network, filled: boolean)
	for _, tube in network.tubes do
		if tube.filled ~= filled then
			tube.filled = filled
			setFluidVisible(tube, filled)
		end
	end
end

-- Regroups the tubes into networks, with the machines and maple trees each one touches.
-- Tubes show fluid only once some has run through their network (sendFluid), so a new line
-- starts empty; a network keeps it while something still feeds it, so a tube added to a
-- running line fills at once and a cut-off piece empties.
local function rebuildTubes()
	table.clear(networks)
	local seen: { [Block]: boolean } = {}
	for _, start in blocks do
		if not isTube(start) or seen[start] then
			continue
		end
		local network: Network = { machines = {}, trees = {}, tubes = {} }
		local queue = { start }
		seen[start] = true
		while #queue > 0 do
			local tube = queue[#queue]
			queue[#queue] = nil
			table.insert(network.tubes, tube)
			for _, direction in tube.openings do
				local cell = tubeCell(tube) + direction
				local other = blockAt(cell)
				local node = WorldService.nodeAt(cell)
				if other and isTube(other) and hasOpening(other, -direction) then
					if not seen[other] then
						seen[other] = true
						table.insert(queue, other)
					end
				elseif other and other.def.tubes then
					network.machines[other] = true
				elseif node and World.getNode(node.nodeType).sap then
					network.trees[node] = true
				end
			end
		end
		local filled = false
		if hasSource(network) then
			for _, tube in network.tubes do
				filled = filled or tube.filled
			end
		end
		setFilled(network, filled)
		table.insert(networks, network)
	end
	-- Forget trees no tube touches any more, so chopped trees don't pile up here.
	for tree in sapTimers do
		local tapped = false
		for _, network in networks do
			if network.trees[tree] then
				tapped = true
				break
			end
		end
		if not tapped then
			sapTimers[tree] = nil
		end
	end
	tubesStale = false
end

local function sendFluid(network: Network, fluid: string): boolean
	for block in network.machines do
		local machine = block.machine
		if machine and Machine.acceptsFluid(machine, fluid) then
			Machine.addFluid(machine, fluid)
			setFilled(network, true)
			return true
		end
	end
	return false
end

local function stepTubes(dt: number)
	rebuildTimer += dt
	if tubesStale or rebuildTimer >= TUBE_REBUILD_EVERY then
		rebuildTimer = 0
		rebuildTubes()
	end
	tubeTimer += dt
	if tubeTimer < TUBE_EVERY then
		return
	end
	local elapsed = tubeTimer
	tubeTimer = 0
	-- A tree touching several networks still fills once per tick; any of them can take it.
	local advanced: { [WorldService.Node]: boolean } = {}
	for _, network in networks do
		for tree in network.trees do
			local every = World.getNode(tree.nodeType).sap or math.huge
			local timer = sapTimers[tree] or 0
			if not advanced[tree] then
				advanced[tree] = true
				timer = math.min(timer + elapsed, every)
			end
			if timer >= every and sendFluid(network, "Sap") then
				timer = 0
			end
			sapTimers[tree] = timer
		end
		-- A boiler's syrup goes on to whichever machine on the same tubes takes it.
		for block in network.machines do
			local machine = block.machine
			local fluid = if machine then next(machine.fluidOut) else nil
			if machine and fluid and sendFluid(network, fluid) then
				Machine.takeFluid(machine)
			end
		end
	end
end

local function encode(counts: { [string]: number }): string
	local parts = {}
	for itemId, count in counts do
		table.insert(parts, `{itemId}:{count}`)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function countList(list: { string }): { [string]: number }
	local counts = {}
	for _, itemId in list do
		counts[itemId] = (counts[itemId] or 0) + 1
	end
	return counts
end

local function setAttribute(model: Model, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

local function refreshStatus(block: Block)
	local model = block.model
	local machine = block.machine
	if machine then
		setAttribute(model, "Status", machine.status)
		setAttribute(model, "Fuel", math.ceil(machine.fuel))
		setAttribute(model, "Contents", encode(machine.inputs))
		setAttribute(model, "Output", encode(countList(machine.outputs)))
		local fluids = table.clone(machine.fluidIn)
		for fluid, count in machine.fluidOut do
			fluids[fluid] = (fluids[fluid] or 0) + count
		end
		setAttribute(model, "Fluid", encode(fluids))
		setAttribute(model, "Progress", math.floor(Machine.progress(machine) * 10) / 10)
		if block.def.sells then
			setAttribute(model, "Sold", machine.sold)
		end
		if block.def.stores then
			setAttribute(model, "Slots", Machine.slotsUsed(machine))
		end
	elseif block.def.route == "Split" then
		setAttribute(model, "Powered", isPowered(block))
	elseif block.def.route == "Filter" then
		local filtered = {}
		for itemId in block.filter do
			table.insert(filtered, itemId)
		end
		table.sort(filtered)
		setAttribute(model, "Filter", table.concat(filtered, ","))
	end
end

local function snapshot(lane: LaneState): { Lane.Item }
	local items = table.create(#lane.items)
	for index, item in lane.items do
		items[index] = { id = item.id, itemId = item.itemId, d = item.d }
	end
	return items
end

local function replicate()
	if next(dirty) == nil and next(cleared) == nil then
		return
	end
	local lanes = {}
	for key in cleared do
		lanes[key] = {}
	end
	for lane in dirty do
		lanes[lane.key] = snapshot(lane)
	end
	table.clear(dirty)
	table.clear(cleared)
	Remotes.FactorySync:FireAllClients({ t = workspace:GetServerTimeNow(), lanes = lanes })
end

local function step(dt: number)
	stepLanes(dt)
	stepMachines(dt)
	stepTubes(dt)
	statusTimer += dt
	if statusTimer >= STATUS_EVERY then
		statusTimer = 0
		for _, block in blocks do
			refreshStatus(block)
		end
	end
	replicate()
end

local function register(model: Instance)
	if not model:IsA("Model") or blocks[model] then
		return
	end
	local itemId = model:GetAttribute("ItemId")
	local origin = model:GetAttribute("Origin")
	local rotation = model:GetAttribute("Rotation")
	if typeof(itemId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return
	end
	local def = Factory.get(itemId)
	local frame = Factory.originFrame(model)
	local ext = Factory.extents(itemId)
	local footprint = Build.footprint(itemId, rotation)
	if not def or not frame or not ext or not footprint then
		return
	end
	nextBlockId += 1
	local block: Block = {
		id = nextBlockId,
		model = model,
		itemId = itemId,
		def = def,
		frame = frame,
		ext = ext,
		origin = origin,
		footprint = footprint,
		lanes = {},
		machine = if def.kind == "Machine" then Machine.new(def) else nil,
		feedLane = nil,
		outputLane = nil,
		inputPort = nil,
		outputPort = nil,
		outputTarget = nil,
		outputVersion = -1,
		filter = {},
		powered = false,
		pulseUntil = 0,
		openings = {},
		filled = false,
		links = {},
		shape = nil,
		env = nil,
	}
	model:SetAttribute("BlockId", block.id)
	eachCell(origin, footprint, function(cell)
		cellIndex[cellKey(cell)] = block
	end)
	for index, laneDef in Factory.lanes(itemId) do
		local points = Factory.worldPoints(frame, laneDef.points)
		local entry, exit = Factory.laneEnds(frame, laneDef)
		local lane: LaneState = {
			key = `{block.id}/{index}`,
			block = block,
			index = index,
			def = laneDef,
			points = points,
			length = Lane.length(points),
			items = {},
			exitPort = if laneDef.exit then exit else nil,
			target = nil,
			version = -1,
		}
		if laneDef.entry then
			addEntry(entry, { block = block, lane = lane, normal = entry.normal })
		end
		if laneDef.feeds then
			block.feedLane = lane
		elseif laneDef.emits then
			block.outputLane = lane
		end
		block.lanes[index] = lane
		laneSet[lane] = true
	end
	if def.input then
		local port = Factory.facePort(frame, ext, def.input)
		block.inputPort = port
		-- With an input belt, items enter by riding it to the port (its lane's entry above).
		if not block.feedLane then
			addEntry(port, { block = block, lane = nil, normal = port.normal })
		end
	end
	if def.output then
		block.outputPort = Factory.facePort(frame, ext, def.output)
	end
	for _, opening in def.openings or {} do
		local direction = frame:VectorToWorldSpace(opening)
		table.insert(
			block.openings,
			Vector3.new(math.round(direction.X), math.round(direction.Y), math.round(direction.Z))
		)
	end
	if def.auto then
		local against = model:GetAttribute("Against")
		joinTube(block, if typeof(against) == "Vector3" then against else nil)
	end
	if def.kind == "Tube" then
		setFluidVisible(block, false)
	end
	if def.sensor then
		flash(block)
	end
	blocks[model] = block
	topology += 1
	tubesStale = true
end

local function unregister(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local block = blocks[model]
	if not block then
		return
	end
	blocks[model] = nil
	eachCell(block.origin, block.footprint, function(cell)
		if cellIndex[cellKey(cell)] == block then
			cellIndex[cellKey(cell)] = nil
		end
	end)
	if isAuto(block) then
		leaveTube(block)
	end
	for key, list in entries do
		for index = #list, 1, -1 do
			if list[index].block == block then
				table.remove(list, index)
			end
		end
		if #list == 0 then
			entries[key] = nil
		end
	end
	for _, lane in block.lanes do
		laneSet[lane] = nil
		dirty[lane] = nil
		cleared[lane.key] = true
	end
	topology += 1
	tubesStale = true
end

-- Everything a placed block holds -- items on its lanes, a machine's inputs and output --
-- removed from it, for the player picking it up.
function FactoryService.drain(model: Model): { [string]: number }
	local block = blocks[model]
	local counts: { [string]: number } = {}
	if not block then
		return counts
	end
	for _, lane in block.lanes do
		for _, item in lane.items do
			counts[item.itemId] = (counts[item.itemId] or 0) + 1
		end
		table.clear(lane.items)
		markDirty(lane)
	end
	local machine = block.machine
	if machine then
		for itemId, count in Machine.drain(machine) do
			counts[itemId] = (counts[itemId] or 0) + count
		end
	end
	return counts
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

-- Takes every item on `block`'s lanes lying under `feet` into the player's inventory, while
-- it has room. An item counts when it is within PICKUP_RADIUS across the belt and the feet
-- are on the belt or just above it, not on the floor beside it.
local function pickUpFrom(player: Player, block: Block, feet: Vector3)
	for _, lane in block.lanes do
		for index = #lane.items, 1, -1 do
			local item = lane.items[index]
			local at = Lane.pointAt(lane.points, item.d)
			local across = Vector3.new(at.X - feet.X, 0, at.Z - feet.Z).Magnitude
			local onBelt = feet.Y >= at.Y - 1 and feet.Y <= at.Y + 2
			local grace = graces[item.id]
			if across <= PICKUP_RADIUS and onBelt and not (grace and grace.dropper == player) then
				if InventoryService.give(player, item.itemId, 1) > 0 then
					return
				end
				table.remove(lane.items, index)
				randomChoice[item.id] = nil
				markDirty(lane)
			end
		end
	end
end

-- Players walking over belt items pick them up, as they do loose drops.
local function pickUpUnderfoot(dt: number)
	pickupTimer += dt
	if pickupTimer < PICKUP_EVERY then
		return
	end
	pickupTimer = 0
	local now = os.clock()
	for id, grace in graces do
		if grace.expires <= now then
			graces[id] = nil
		end
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local humanoid = if root and player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
		if not root or not humanoid then
			continue
		end
		local feet = root.Position - Vector3.yAxis * (root.Size.Y / 2 + humanoid.HipHeight)
		local under = cellOf(feet - Vector3.yAxis * 0.5)
		local seen: { [Block]: boolean } = {}
		for dx = -1, 1 do
			for dz = -1, 1 do
				local block = cellIndex[cellKey(under + Vector3.new(dx, 0, dz))]
				if block and not seen[block] then
					seen[block] = true
					pickUpFrom(player, block, feet)
				end
			end
		end
	end
end

local function ready(player: Player): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < COOLDOWN then
		return false
	end
	lastAction[player] = now
	return true
end

-- Sends `itemId` left at a filter conveyor, or stops sending it, up to FILTER_MAX items.
local function toggleFilter(block: Block, itemId: string)
	local count = 0
	for _ in block.filter do
		count += 1
	end
	if block.filter[itemId] then
		block.filter[itemId] = nil
	elseif count < FILTER_MAX then
		block.filter[itemId] = true
	end
end

-- Moves a machine's finished items into the player's inventory, while there is room.
local function collect(player: Player, machine: Machine.State)
	local itemId = Machine.peekOutput(machine)
	while itemId and InventoryService.give(player, itemId, 1) == 0 do
		Machine.popOutput(machine)
		itemId = Machine.peekOutput(machine)
	end
end

-- Toggles the held item in a filter. Machines are only worked through their panel
-- (`control`), never by hand.
local function use(player: Player, block: Block)
	local held = InventoryService.getHeldItemId(player)
	if held and block.def.route == "Filter" then
		toggleFilter(block, held)
		refreshStatus(block)
	end
end

-- An empty hand: take a conveyor's items, or switch a router. Machines are only worked
-- through their panel.
local function take(player: Player, block: Block)
	if InventoryService.getHeldItemId(player) or block.machine then
		return
	end
	if block.def.route == "Split" then
		block.powered = not block.powered
	elseif block.def.route == "Filter" then
		table.clear(block.filter)
	elseif block.def.kind == "Conveyor" then
		for _, lane in block.lanes do
			for index = #lane.items, 1, -1 do
				if InventoryService.give(player, lane.items[index].itemId, 1) > 0 then
					break
				end
				table.remove(lane.items, index)
				markDirty(lane)
			end
		end
	end
	refreshStatus(block)
end

-- The machine panel (UIController/MachinePanel): what its buttons and item cells ask for,
-- whatever the player is holding.
local function control(player: Player, block: Block, action: string, itemId: string?)
	local machine = block.machine
	local isSplit, isFilter = block.def.route == "Split", block.def.route == "Filter"
	if action == "Load" and machine and itemId and Factory.takesByHand(block.itemId, itemId) then
		-- From anywhere in the inventory, not just the hand.
		local taken = InventoryService.take(player, itemId, Machine.room(machine, itemId))
		Machine.insert(machine, itemId, taken)
	elseif action == "Collect" and machine then
		collect(player, machine)
	elseif action == "TakeBack" and machine then
		for inputId, count in Machine.takeInputs(machine) do
			Machine.putBack(machine, inputId, InventoryService.give(player, inputId, count))
		end
	elseif action == "TakeOut" and machine and itemId and block.def.stores then
		-- One item out of a chest: as many as the inventory holds.
		local count = Machine.takeInput(machine, itemId, math.huge)
		Machine.putBack(machine, itemId, InventoryService.give(player, itemId, count))
	elseif action == "Switch" and isSplit then
		block.powered = not block.powered
	elseif action == "Filter" and itemId and isFilter then
		toggleFilter(block, itemId)
	elseif action == "ClearFilter" and isFilter then
		table.clear(block.filter)
	end
	refreshStatus(block)
end

local PANEL_ACTIONS =
	{ Load = true, Collect = true, TakeBack = true, TakeOut = true, Switch = true, Filter = true, ClearFilter = true }

local function onInteract(player: Player, target: unknown, action: unknown, itemId: unknown)
	if typeof(target) ~= "Instance" or not target:IsA("Model") or target.Parent ~= placed then
		return
	end
	local block = blocks[target]
	local root = rootOf(player)
	local known = action == "Use" or action == "Take" or (typeof(action) == "string" and PANEL_ACTIONS[action])
	if not block or not root or not known or not ready(player) then
		return
	end
	if not Build.inReach(root.Position, block.origin, block.footprint) then
		return
	end
	-- An item id must name a real item; anything else is a malformed request.
	local item = if typeof(itemId) == "string" and pcall(Inventory.getItem, itemId) then itemId else nil
	if action == "Use" then
		use(player, block)
	elseif action == "Take" then
		take(player, block)
	elseif typeof(action) == "string" then
		control(player, block, action, item)
	end
end

-- Every lane's items, for a player who just joined.
local function sendAll(player: Player)
	local lanes = {}
	for lane in laneSet do
		if #lane.items > 0 then
			lanes[lane.key] = snapshot(lane)
		end
	end
	Remotes.FactorySync:FireClient(player, { t = workspace:GetServerTimeNow(), lanes = lanes })
end

function FactoryService.init()
	placed.ChildAdded:Connect(register)
	placed.ChildRemoved:Connect(unregister)
	for _, model in placed:GetChildren() do
		register(model)
	end
	Remotes.Interact.OnServerEvent:Connect(onInteract)
	Players.PlayerAdded:Connect(sendAll)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
	RunService.Heartbeat:Connect(pickUpUnderfoot)
	DropService.setBelts(catch, dropPoint)
end

return FactoryService
