--!strict
-- Factory: the shared half of the factory. Blocks says what each block does, Lane how
-- items move along a conveyor path, and this module turns a block's authored lanes and
-- ports into world positions. FactoryService simulates with it; FactoryController draws
-- with it, so both put an item in the same place.
--
-- A block's authored frame comes from its hitbox's AuthoredOrigin attribute (set by the
-- Islands pipeline): its conveyor runs down that frame's x = 0. Ports sit on
-- hitbox faces, so two blocks connect exactly when one's exit and the other's entry share
-- a point and face each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Blocks = require(ReplicatedStorage.Shared.Factory.Blocks)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)

export type Def = Blocks.Def
export type LaneDef = Blocks.LaneDef
export type Recipe = Blocks.Recipe
export type Source = Blocks.Source
export type Extents = Blocks.Extents
export type Face = Blocks.Face
export type Port = { position: Vector3, normal: Vector3 }

-- Belt surface height above a block's floor, where machine ports meet conveyors.
local BELT = 1.59
-- Studs per second items ride a machine's input and output belts (a tier 1 conveyor's speed).
local MACHINE_BELT_SPEED = 4
-- Shortest machine belt worth riding; a port closer to the face than this takes items in,
-- or puts them out, right at the face.
local MIN_BELT = 0.5
local NO_RECIPES: { Recipe } = {}

local Factory = {}

Factory.Lane = Lane

local extentsCache: { [string]: Extents } = {}
local lanesCache: { [string]: { LaneDef } } = {}

function Factory.get(itemId: string): Def?
	return Blocks[itemId]
end

-- Whether the block has a panel of controls (UIController/MachinePanel): every machine,
-- and the routers with a setting (split and filter conveyors).
function Factory.hasControls(itemId: string): boolean
	local def = Blocks[itemId]
	return def ~= nil and (def.kind == "Machine" or def.route == "Split" or def.route == "Filter")
end

-- Whether a dropped item can land on the block's belt: a conveyor or router's lanes, or a
-- machine's input end.
function Factory.hasBelt(itemId: string): boolean
	local def = Blocks[itemId]
	return def ~= nil and (def.lanes ~= nil or def.input ~= nil)
end

-- The world frame a block's lanes and ports are authored in, from a placed block or a
-- template. Nil when the block has no authored origin (plain cubes).
function Factory.originFrame(model: Model): CFrame?
	local hitbox = model.PrimaryPart
	local offset = if hitbox then hitbox:GetAttribute("AuthoredOrigin") else nil
	if not hitbox or typeof(offset) ~= "CFrame" then
		return nil
	end
	return hitbox.CFrame * offset
end

-- The block's hitbox in its authored frame, read once from its template.
function Factory.extents(itemId: string): Extents?
	local cached = extentsCache[itemId]
	if cached then
		return cached
	end
	local template = Build.getTemplate(itemId)
	local frame = if template then Factory.originFrame(template) else nil
	local hitbox = if template then template.PrimaryPart else nil
	if not frame or not hitbox then
		return nil
	end
	local centre = frame:PointToObjectSpace(hitbox.Position)
	local half = hitbox.Size / 2
	local result = { min = centre - half, max = centre + half }
	extentsCache[itemId] = result
	return result
end

-- Studs from a machine's `face` to where its belt runs into the machine's port, from its
-- template's hitbox (PortDepthBack / PortDepthFront, measured by the Islands pipeline's
-- studio_blocks.luau). Nil when the
-- face has no belt worth riding.
local function portDepth(itemId: string, face: Face): number?
	local template = Build.getTemplate(itemId)
	local hitbox = if template then template.PrimaryPart else nil
	local depth = if hitbox
		then hitbox:GetAttribute(if face == "+Z" then "PortDepthFront" else "PortDepthBack")
		else nil
	return if typeof(depth) == "number" and depth >= MIN_BELT then depth else nil
end

-- A machine's belt along `face`, `depth` studs deep: into the machine (toward its port) or
-- out of it (from the port to the face).
local function machineBelt(ext: Extents, face: Face, depth: number, into: boolean): LaneDef
	local z, inward = if face == "+Z" then ext.max.Z else ext.min.Z, if face == "+Z" then -1 else 1
	local outer, inner = Vector3.new(0, BELT, z), Vector3.new(0, BELT, z + inward * depth)
	return {
		points = if into then { outer, inner } else { inner, outer },
		speed = MACHINE_BELT_SPEED,
		entry = into,
		exit = not into,
		feeds = if into then true else nil,
		emits = if into then nil else true,
	}
end

-- The block's lanes in its authored frame: a conveyor's or router's own, or a machine's
-- belts: its input belt carries items from its input face to its port before they go in,
-- and its output belt carries what it makes from its port out to its output face.
function Factory.lanes(itemId: string): { LaneDef }
	local cached = lanesCache[itemId]
	if cached then
		return cached
	end
	local def = Blocks[itemId]
	local ext = Factory.extents(itemId)
	local result = if def and def.lanes and ext then def.lanes(ext) else {}
	if def and ext then
		local inDepth = if def.input then portDepth(itemId, def.input) else nil
		if def.input and inDepth then
			table.insert(result, machineBelt(ext, def.input, inDepth, true))
		end
		local outDepth = if def.output then portDepth(itemId, def.output) else nil
		if def.output and outDepth then
			table.insert(result, machineBelt(ext, def.output, outDepth, false))
		end
	end
	lanesCache[itemId] = result
	return result
end

function Factory.worldPoints(frame: CFrame, points: { Vector3 }): { Vector3 }
	local result = table.create(#points)
	for index, point in points do
		result[index] = frame:PointToWorldSpace(point)
	end
	return result
end

-- Which way a lane end at `from` -> `to` faces: level, since ports sit on a hitbox's upright
-- faces. A ramp's belt climbs, but its ends still face a flat conveyor's straight on.
local function facing(from: Vector3, to: Vector3): Vector3
	local along = to - from
	local level = Vector3.new(along.X, 0, along.Z)
	return if level.Magnitude > 1e-3 then level.Unit else along.Unit
end

-- A lane's entry (its start, facing back out) and exit (its end, facing on), in world space.
function Factory.laneEnds(frame: CFrame, lane: LaneDef): (Port, Port)
	local points = Factory.worldPoints(frame, lane.points)
	local first, second = points[1], points[2]
	local last, before = points[#points], points[#points - 1]
	return { position = first, normal = facing(second, first) }, { position = last, normal = facing(before, last) }
end

-- A machine's port on its -Z or +Z hitbox face, in world space.
function Factory.facePort(frame: CFrame, ext: Extents, face: Face): Port
	local z = if face == "+Z" then ext.max.Z else ext.min.Z
	local normal = if face == "+Z" then Vector3.zAxis else -Vector3.zAxis
	return { position = frame:PointToWorldSpace(Vector3.new(0, BELT, z)), normal = frame:VectorToWorldSpace(normal) }
end

-- A key two coincident ports share, robust to floating error (half-stud grid).
function Factory.portKey(position: Vector3): string
	return `{math.round(position.X * 2)},{math.round(position.Y * 2)},{math.round(position.Z * 2)}`
end

-- Whether a block would take `itemId` from a player's hand, ignoring how full it is. A
-- filter takes anything (it sets the filter); a machine takes what a recipe uses, its
-- fuel, what it plants, and any resource if it sells.
function Factory.takesByHand(blockItemId: string, itemId: string): boolean
	local def = Blocks[blockItemId]
	if not def then
		return false
	end
	if def.route == "Filter" then
		return true
	end
	if def.kind ~= "Machine" then
		return false
	end
	if (def.fuel and def.fuel[itemId]) or (def.plants and table.find(def.plants, itemId)) then
		return true
	end
	if def.sells and Inventory.getItem(itemId).kind == "Resource" then
		return true
	end
	for _, recipe in def.recipes or NO_RECIPES do
		if recipe.inputs[Inventory.getItem(itemId).base or itemId] then
			return true
		end
	end
	return false
end

return Factory
