--!strict
-- Factory: the shared half of the factory. Blocks says what each block does, Lane how
-- items move along a conveyor path, and this module turns a block's authored lanes and
-- ports into world positions. FactoryService simulates with it; FactoryController draws
-- with it, so both put an item in the same place.
--
-- A block's authored frame comes from its hitbox's AuthoredOrigin attribute (set by the
-- Islands pipeline): its conveyor or tube runs down that frame's x = 0. Ports sit on
-- hitbox faces, so two blocks connect exactly when one's exit and the other's entry share
-- a point and face each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Blocks = require(script.Blocks)
local Lane = require(script.Lane)

export type Def = Blocks.Def
export type LaneDef = Blocks.LaneDef
export type Recipe = Blocks.Recipe
export type Source = Blocks.Source
export type Extents = Blocks.Extents
export type Face = Blocks.Face
export type Port = { position: Vector3, normal: Vector3 }

-- Belt surface height above a block's floor, where machine ports meet conveyors.
local BELT = 1.59
local NO_RECIPES: { Recipe } = {}

local Factory = {}

Factory.Lane = Lane

local extentsCache: { [string]: Extents } = {}
local lanesCache: { [string]: { LaneDef } } = {}

function Factory.get(itemId: string): Def?
	return Blocks[itemId]
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

-- The block's lanes in its authored frame.
function Factory.lanes(itemId: string): { LaneDef }
	local cached = lanesCache[itemId]
	if cached then
		return cached
	end
	local def = Blocks[itemId]
	local ext = Factory.extents(itemId)
	local result = if def and def.lanes and ext then def.lanes(ext) else {}
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

-- A lane's entry (its start, facing back out) and exit (its end, facing on), in world space.
function Factory.laneEnds(frame: CFrame, lane: LaneDef): (Port, Port)
	local points = Factory.worldPoints(frame, lane.points)
	local first, second = points[1], points[2]
	local last, before = points[#points], points[#points - 1]
	return { position = first, normal = (first - second).Unit }, { position = last, normal = (last - before).Unit }
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
-- fuel, its feed, what it plants, and any resource if it sells.
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
	if (def.fuel and def.fuel[itemId]) or (def.feeds and def.feeds[itemId]) or def.plants == itemId then
		return true
	end
	if def.sells and Inventory.getItem(itemId).kind == "Resource" then
		return true
	end
	for _, recipe in def.recipes or NO_RECIPES do
		if recipe.inputs[itemId] then
			return true
		end
	end
	return false
end

return Factory
