-- GroundService: the gardens' ground, cell by cell, which players dig and till. Every owned
-- section is solid from the grass at y = -1 down to Plot.FLOOR, layered as Shared/World/Ground
-- says; per plot only the cells that differ from that are kept (`changes`: dug out, or tilled
-- into Farmland), saved plot-relative, so a garden nobody touched saves nothing. Locked land,
-- the ground between gardens and the bedrock under them are PlotService's solid parts.
--
-- Only exposed cells (a face open to the air) stand as WorldService nodes, so a garden is a
-- layer of grass, not a block of thousands of cells, and digging uncovers the cells around the
-- hole. Every cell that can be aimed at or overlapped is therefore a real part: a ray from the
-- air meets an exposed cell before a buried one, and so does any footprint holding an air cell,
-- which keeps Build's overlap test and the client's ghost right without any ground map of
-- their own. The server still checks (`isClear`) that a placement takes no solid ground.
--
-- The owner mines ground with the Pickaxe for the block it is (World.NODES drops; Farmland gives
-- the Dirt it was tilled from), uprooting any crop on it, and tills grass and dirt with the Hoe:
-- ground, or a placed Grass or Dirt block (World.TILLABLE_BLOCKS), which becomes Farmland in the
-- same cell. Farmland is wet while a sprinkler covers the crop cell above it or it is raining,
-- and dries Ground.WET_FOR seconds after neither does. Wetness is a look (GroundArt) and a
-- `Wet` attribute for the hover panel; it is not saved.
--
-- Dirt with open air above it grows over into grass after GRASS_MIN..GRASS_MAX seconds (saved
-- as a change, "Grassed", like digging and tilling); anything solid landing on top restarts it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Build = require(ReplicatedStorage.Shared.Build)
local Ground = require(ReplicatedStorage.Shared.World.Ground)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local GroundArt = require(ServerScriptService.Libraries.GroundArt)
local InventoryService = require(script.Parent.InventoryService)
local WeatherService = require(script.Parent.WeatherService)
local WorldService = require(script.Parent.WorldService)

-- Seconds between one player's ground actions; caps how fast a client can spam remotes.
local COOLDOWN = 0.15
-- Seconds between checks of which Farmland is wet and which dirt has grown over.
local WET_TICK = 1
-- Seconds bare dirt takes to grow over into grass, picked at random between these.
local GRASS_MIN = 60
local GRASS_MAX = 120
local NEIGHBOURS = {
	Vector3.xAxis,
	-Vector3.xAxis,
	Vector3.yAxis,
	-Vector3.yAxis,
	Vector3.zAxis,
	-Vector3.zAxis,
}

type Change = "Dug" | "Tilled" | "Grassed"
-- A cell's ground, by its node type; SOLID for ground that never stands as a node (locked land,
-- off the garden, under the floor); nil for air.
local SOLID = "Solid"

local GroundService = {}

-- Per plot: plot-relative cells ("x,y,z") whose ground differs from Ground.natural.
local changes: { [number]: { [string]: Change? } } = {}
-- Per plot: its ground nodes, by world cell.
local standing: { [number]: { [string]: WorldService.Node } } = {}
-- Ground nodes by model, with their plot, for the hand.
local byModel: { [Model]: { index: number, node: WorldService.Node } } = {}
-- Every Farmland node, and until when (os.clock) it stays wet, or 0 when dry.
local fields: { [WorldService.Node]: number } = {}
-- Every dirt node, with its plot, and when (os.clock) it grows over, or 0 while covered.
local bare: { [WorldService.Node]: { index: number, at: number } } = {}
local lastAction: { [Player]: number } = {}
local random = Random.new()

local function key(cell: Vector3): string
	return `{cell.X},{cell.Y},{cell.Z}`
end

local function parse(text: unknown): Vector3?
	if typeof(text) ~= "string" then
		return nil
	end
	local x, y, z = string.match(text, "^(%-?%d+),(%-?%d+),(%-?%d+)$")
	local cx, cy, cz = tonumber(x), tonumber(y), tonumber(z)
	return if cx and cy and cz then Vector3.new(cx, cy, cz) else nil
end

local function plotChanges(index: number): { [string]: Change? }
	local list = changes[index]
	if not list then
		list = {}
		changes[index] = list
	end
	return list
end

local function plotNodes(index: number): { [string]: WorldService.Node }
	local list = standing[index]
	if not list then
		list = {}
		standing[index] = list
	end
	return list
end

-- Whether a plot-relative cell is in a section the plot owns.
local function owned(index: number, relative: Vector3): boolean
	if relative.X < 0 or relative.X >= Plot.WIDTH or relative.Z < 0 or relative.Z >= Plot.DEPTH then
		return false
	end
	local x, z = Plot.sectionOf(relative)
	return Plot.owns(index, x, z)
end

-- What fills a world cell of a plot's ground: a node type, SOLID or nil for air.
local function groundAt(index: number, cell: Vector3): string?
	local relative = Plot.toRelative(index, cell)
	if relative.Y < Plot.FLOOR or (relative.Y < 0 and not owned(index, relative)) then
		return SOLID
	elseif not owned(index, relative) then
		return nil
	end
	local change = plotChanges(index)[key(relative)]
	if change == "Dug" then
		return nil
	elseif change == "Tilled" then
		return "Farmland"
	elseif change == "Grassed" then
		return "GrassGround"
	end
	return Ground.natural(relative)
end

local function exposed(index: number, cell: Vector3): boolean
	for _, step in NEIGHBOURS do
		if not groundAt(index, cell + step) then
			return true
		end
	end
	return false
end

local function paint(node: WorldService.Node, wet: boolean)
	GroundArt.paint(node.model, wet)
	node.model:SetAttribute("Wet", if wet then true else nil)
end

local function unstand(index: number, cellKey: string, node: WorldService.Node)
	plotNodes(index)[cellKey] = nil
	byModel[node.model] = nil
	fields[node] = nil
	bare[node] = nil
	WorldService.removeGround(node)
end

-- Makes a cell's node match its ground: there when the ground is a node type and exposed.
local function refresh(index: number, cell: Vector3)
	local kind = groundAt(index, cell)
	local wanted = if kind and kind ~= SOLID and exposed(index, cell) then kind else nil
	local cellKey = key(cell)
	local node = plotNodes(index)[cellKey]
	if node and node.nodeType == wanted then
		return
	end
	if node then
		unstand(index, cellKey, node)
	end
	if wanted then
		local spawned = WorldService.spawnGround(wanted, cell)
		plotNodes(index)[cellKey] = spawned
		byModel[spawned.model] = { index = index, node = spawned }
		if wanted == "Farmland" then
			fields[spawned] = 0
		elseif wanted == "DirtGround" then
			bare[spawned] = { index = index, at = 0 }
		end
	end
end

local function refreshAround(index: number, cell: Vector3)
	refresh(index, cell)
	for _, step in NEIGHBOURS do
		refresh(index, cell + step)
	end
end

-- Stands every exposed cell of a plot's owned land: its top, and everything around a change.
local function raise(index: number)
	for x = 0, Plot.SECTIONS_X - 1 do
		for z = 0, Plot.SECTIONS_Z - 1 do
			if Plot.owns(index, x, z) then
				for cx = x * Plot.SECTION, (x + 1) * Plot.SECTION - 1 do
					for cz = z * Plot.SECTION, (z + 1) * Plot.SECTION - 1 do
						refresh(index, Plot.toWorld(index, Vector3.new(cx, Ground.SURFACE, cz)))
					end
				end
			end
		end
	end
	for relativeKey in plotChanges(index) do
		local relative = parse(relativeKey)
		if relative then
			refreshAround(index, Plot.toWorld(index, relative))
		end
	end
end

-- Records how a world cell of a plot differs from its natural ground (nil: not at all), then
-- brings it and its neighbours up to date.
local function change(index: number, cell: Vector3, to: Change?)
	local relative = Plot.toRelative(index, cell)
	local natural = Ground.natural(relative)
	if
		(to == "Dug" and not natural)
		or (to == "Tilled" and natural == "Farmland")
		or (to == "Grassed" and natural == "GrassGround")
	then
		to = nil
	end
	plotChanges(index)[key(relative)] = to
	refreshAround(index, cell)
end

-- Builds a garden's untouched ground. PlotService calls this for every garden as it builds them.
function GroundService.build(index: number)
	raise(index)
end

-- Stands the ground of sections a garden has just bought.
function GroundService.extend(index: number)
	raise(index)
end

-- Back to untouched ground over the start block only, for a garden that has just been freed.
-- Its crops and blocks are gone already.
function GroundService.reset(index: number)
	for cellKey, node in plotNodes(index) do
		unstand(index, cellKey, node)
	end
	changes[index] = {}
	raise(index)
end

-- Whether no solid ground takes any cell of a footprint at `origin`.
function GroundService.isClear(origin: Vector3, footprint: Vector3): boolean
	for x = 0, footprint.X - 1 do
		for y = 0, footprint.Y - 1 do
			for z = 0, footprint.Z - 1 do
				local cell = origin + Vector3.new(x, y, z)
				local index = Plot.at(cell)
				if index and groundAt(index, cell) then
					return false
				end
			end
		end
	end
	return true
end

function GroundService.snapshot(index: number): Plot.SavedGround
	local saved: Plot.SavedGround = { dug = {}, tilled = {}, grassed = {} }
	local lists = { Dug = saved.dug, Tilled = saved.tilled, Grassed = saved.grassed }
	for relativeKey, kind in plotChanges(index) do
		if kind then
			table.insert(lists[kind], relativeKey)
		end
	end
	for _, list in lists do
		table.sort(list)
	end
	return saved
end

-- Applies a saved garden's dug and tilled cells, after its sections and before its blocks and
-- crops. Cells that no longer make sense (off its land, out of range, tilled stone) are skipped.
function GroundService.restore(index: number, saved: Plot.SavedGround)
	local list = plotChanges(index)
	local function apply(entries: unknown, kind: Change)
		if typeof(entries) ~= "table" then
			return
		end
		for _, entry in entries :: { unknown } do
			local relative = parse(entry)
			if not relative or not owned(index, relative) or relative.Y < Plot.FLOOR or relative.Y >= Plot.HEIGHT then
				warn(`GroundService: skipped a saved {kind} cell in garden {index}`)
				continue
			end
			local natural = Ground.natural(relative)
			local fits = if kind == "Dug"
				then natural ~= nil
				elseif kind == "Grassed" then natural == "DirtGround"
				else natural == nil or World.getNode(natural).tills
			if fits then
				list[key(relative)] = kind
			end
		end
	end
	apply(saved.dug, "Dug")
	apply(saved.tilled, "Tilled")
	apply(saved.grassed, "Grassed")
	raise(index)
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

-- Whether `player` may work the cell: their loaded plot, within reach.
local function canWork(player: Player, cell: Vector3): boolean
	local root = rootOf(player)
	return root ~= nil and Build.canEdit(player, cell, Vector3.one) and Build.inReach(root.Position, cell, Vector3.one)
end

local function mine(player: Player, index: number, node: WorldService.Node)
	local drops = World.getNode(node.nodeType).drops or {}
	if not InventoryService.canGiveAll(player, drops) then
		Remotes.Notify:FireClient(player, "Your inventory is full.")
		return
	end
	local cell = node.cell
	WorldService.uproot(cell + Vector3.yAxis)
	change(index, cell, "Dug")
	for itemId, count in drops do
		InventoryService.give(player, itemId, count)
	end
end

-- A placed Grass or Dirt block of the player's, tilled where it stands.
local function tillPlaced(player: Player, model: Model)
	local itemId = model:GetAttribute("ItemId")
	local origin = model:GetAttribute("Origin")
	if
		typeof(itemId) ~= "string"
		or not World.TILLABLE_BLOCKS[itemId]
		or typeof(origin) ~= "Vector3"
		or model:GetAttribute("Owner") ~= player.UserId
		or not canWork(player, origin)
	then
		return
	end
	local index = Plot.at(origin)
	if not index then
		return
	end
	model:Destroy()
	change(index, origin, "Tilled")
end

local function onInteract(player: Player, target: unknown, action: unknown)
	if
		action ~= "Use"
		or typeof(target) ~= "Instance"
		or not target:IsA("Model")
		or player:GetAttribute("DataReady") ~= true
	then
		return
	end
	local held = InventoryService.getHeldItemId(player)
	local item = if held then Inventory.find(held) else nil
	local placed = workspace:FindFirstChild("Placed")
	if item and item.tills and placed and target.Parent == placed then
		if ready(player) then
			tillPlaced(player, target)
		end
		return
	end
	local entry = byModel[target]
	if not entry or not item or not ready(player) or not canWork(player, entry.node.cell) then
		return
	end
	local def = World.getNode(entry.node.nodeType)
	if item.tills and def.tills then
		change(entry.index, entry.node.cell, "Tilled")
	elseif def.tool == item.id then
		mine(player, entry.index, entry.node)
	end
end

local function raining(): boolean
	local event = WeatherService.current()
	return event == "Rain" or event == "Thunderstorm"
end

-- Wets Farmland under a sprinkler or rain, and dries what neither has reached for WET_FOR.
local function water()
	local now = os.clock()
	local rain = raining()
	for node, wetUntil in fields do
		if rain or WorldService.speedAt(node.cell + Vector3.yAxis) > 1 then
			if wetUntil == 0 then
				paint(node, true)
			end
			fields[node] = now + Ground.WET_FOR
		elseif wetUntil ~= 0 and now >= wetUntil then
			fields[node] = 0
			paint(node, false)
		end
	end
end

-- Grows grass over dirt that has had open air above it long enough.
local function spread()
	local now = os.clock()
	local grown = {}
	for node, entry in bare do
		if groundAt(entry.index, node.cell + Vector3.yAxis) then
			entry.at = 0
		elseif entry.at == 0 then
			entry.at = now + random:NextNumber(GRASS_MIN, GRASS_MAX)
		elseif now >= entry.at then
			table.insert(grown, entry.index)
			table.insert(grown, node.cell)
		end
	end
	for i = 1, #grown, 2 do
		change(grown[i], grown[i + 1], "Grassed")
	end
end

function GroundService.init()
	Remotes.Interact.OnServerEvent:Connect(onInteract)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(WET_TICK)
			water()
			spread()
		end
	end)
end

return GroundService
