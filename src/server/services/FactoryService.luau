-- FactoryService: runs every placed factory block (Shared/Factory). It registers a block
-- when it lands in Workspace.Placed, connects it to its neighbours by their ports, and
-- every frame moves items along lanes, through router hubs and into and out of machines.
-- Interactions require the owning loaded plot; sources, ports, sensors and caught drops
-- stay within that plot. Snapshot/restore preserves counts and settings without duplicating
-- runtime identities. Registration is idempotent and can run before init during profile load.
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
local Plot = require(ReplicatedStorage.Shared.Plot)
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
	env: Machine.Env?,
}

-- Seconds between machine status refreshes.
local STATUS_EVERY = 0.25
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
local lastAction: { [Player]: number } = {}
-- Whether the cell past an unconnected port is empty, and when (os.clock()) that was seen.
local openCache: { [Factory.Port]: { open: boolean, checked: number } } = setmetatable({}, { __mode = "k" }) :: any
-- Item id -> the player who dropped it, and the os.clock() before which they can't walk it
-- up (PICKUP_GRACE).
local graces: { [number]: { dropper: Player, expires: number } } = {}
local pickupTimer = 0
local topology = 0
local overlapParams = Build.newOverlapParams()
local nextBlockId = 0
local nextItemId = 0
local statusTimer = 0

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
local function connect(port: Factory.Port, origin: Vector3): Entry?
	local list = entries[Factory.portKey(port.position)]
	if not list then
		return nil
	end
	for _, entry in list do
		if entry.normal:Dot(port.normal) < -0.9 and Plot.same(origin, entry.block.origin) then
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
		lane.target = connect(port, lane.block.origin)
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
		block.outputTarget = connect(port, block.origin)
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
			if other and other ~= sensor and other.def.route == "Split" and Plot.same(sensor.origin, other.origin) then
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
local function throwOff(block: Block, port: Factory.Port, speed: number, itemId: string)
	local at = CFrame.lookAlong(port.position + port.normal * 0.6 + Vector3.yAxis * 0.6, port.normal)
	local userId = block.model:GetAttribute("Owner")
	local owner = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	DropService.spawn(itemId, at, port.normal * speed + Vector3.yAxis * THROW_LIFT, 1, owner)
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
		if not block or not dropper or not Build.canEdit(dropper, block.origin, block.footprint) then
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
				throwOff(lane.block, lane.exitPort, lane.def.speed, front.itemId)
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

-- Every source lookup and completed harvest stays inside the machine's plot.
local function sourcesFor(block: Block): { WorldService.Node }
	local produce = block.def.produce
	local found = {}
	if not produce then
		return found
	end
	for _, node in WorldService.nodesNear(centreOf(block), (produce.radius or 6) * Build.GRID, produce.sources) do
		if Plot.same(block.origin, node.cell) then
			table.insert(found, node)
		end
	end
	return found
end

local function plantCellOf(block: Block): Vector3?
	local rule = block.def.plantCell
	local cell = if rule then cellOf(block.frame:PointToWorldSpace(rule(block.ext))) else nil
	return if cell and Plot.same(block.origin, cell) then cell else nil
end

local function envFor(block: Block): Machine.Env
	if block.env then
		return block.env
	end
	local def = block.def
	local env: Machine.Env = {}
	if def.produce then
		local selected: WorldService.Node? = nil
		env.source = function()
			local node = sourcesFor(block)[1]
			selected = node
			if node and def.produce then
				local source = table.clone(def.produce.sources[node.nodeType])
				if node.mutation then
					source.item ..= "+" .. node.mutation
				end
				return source
			end
			return nil, "Needs a ripe crop nearby on this plot"
		end
		env.reap = function(_: Factory.Source)
			local node = selected
			return node ~= nil and Plot.same(block.origin, node.cell) and WorldService.reap(node)
		end
	end
	if def.plants then
		env.canPlant = function(itemId)
			local cell = plantCellOf(block)
			return cell ~= nil and WorldService.canPlant(cell, itemId)
		end
		env.plant = function(itemId)
			local cell = plantCellOf(block)
			return cell ~= nil and WorldService.plant(cell, itemId)
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
			throwOff(block, port, MACHINE_THROW, itemId)
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
	if def.sensor then
		flash(block)
	end
	blocks[model] = block
	topology += 1
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
end

function FactoryService.register(model: Model): boolean
	register(model)
	return blocks[model] ~= nil
end

function FactoryService.unregister(model: Model)
	unregister(model)
end

-- Counts preserve the input/output boundary; active recipe inputs are refunded for restart.
-- Belt counts restore to their original lane at legal spacing, with fresh runtime item ids.
function FactoryService.snapshot(model: Model): Plot.Contents?
	local block = blocks[model]
	if not block then
		return nil
	end
	local saved: Plot.Contents =
		{ inputs = {}, outputs = {}, lanes = {}, fuel = 0, sold = 0, filter = {}, powered = block.powered }
	for itemId in block.filter do
		table.insert(saved.filter, itemId)
	end
	for _, lane in block.lanes do
		local counts: Plot.Counts = {}
		for _, item in lane.items do
			counts[item.itemId] = (counts[item.itemId] or 0) + 1
		end
		table.insert(saved.lanes, counts)
	end
	local machine = block.machine
	if machine then
		saved.inputs = Machine.inputCounts(machine)
		saved.outputs = countList(machine.outputs)
		saved.fuel = machine.fuel
		saved.sold = machine.sold
	end
	return saved
end

function FactoryService.restore(model: Model, saved: Plot.Contents): boolean
	register(model)
	local block = blocks[model]
	if not block then
		return false
	end
	block.powered = saved.powered
	for _, itemId in saved.filter do
		block.filter[itemId] = true
	end
	for index, counts in saved.lanes do
		local lane = block.lanes[index]
		if not lane then
			return false
		end
		local distance = lane.length
		for itemId, count in counts do
			for _ = 1, count do
				table.insert(lane.items, { id = newItemId(), itemId = itemId, d = math.max(0, distance) })
				distance -= Lane.SPACING
			end
		end
		markDirty(lane)
	end
	local machine = block.machine
	if machine then
		machine.inputs = table.clone(saved.inputs)
		for itemId, count in saved.outputs do
			for _ = 1, count do
				table.insert(machine.outputs, itemId)
			end
		end
		machine.fuel = saved.fuel
		machine.sold = saved.sold
	end
	refreshStatus(block)
	return true
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
	if not Build.canEdit(player, block.origin, block.footprint) then
		return
	end
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
	if
		not block
		or not root
		or not known
		or not ready(player)
		or not Build.canEdit(player, block.origin, block.footprint)
	then
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
