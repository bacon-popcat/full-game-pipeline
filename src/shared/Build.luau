--!strict
-- Build: the placement grid, shared so the client's ghost and the server's check agree.
--
-- The world is cut into GRID-stud cells from the world origin (the baseplate's top is
-- Y = 0). A placeable occupies a footprint of whole cells, sits on the floor of its
-- origin (minimum) cell, and turns in quarter steps about Y. A placement is legal when it
-- is within REACH of the placer and nothing queryable overlaps its box. That one
-- geometric test covers placed blocks, world props and characters alike, so there is no
-- occupancy map to fall out of sync with the world.
--
-- Templates live in ReplicatedStorage.Assets.Blocks, named by item id. A template's
-- PrimaryPart is its hitbox: a box of whole cells, so its size is the footprint and
-- placing it fills the placement's box. The template's pivot is read relative to the
-- hitbox, so it can sit wherever is convenient to hold it by. A machine's hitbox is an
-- invisible part named Hitbox around its art, which may poke past it by up to 0.15 studs
-- (docs/inventory.md); a plain cube is its own hitbox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Measure = {
	footprint: Vector3,
	-- The template's pivot relative to its hitbox (identity unless someone moved it).
	pivotOffset: CFrame,
}

local GRID = 3
-- Shrinks overlap boxes so blocks that only touch faces, or whose art pokes past its
-- hitbox by the 0.15 studs allowed, don't count as overlapping.
local TOUCH_MARGIN = 0.2
-- Cells from the origin a placement may name; keeps untrusted cells to sane numbers.
local MAX_CELL = 10000

local Build = {}

Build.GRID = GRID
-- Studs from the character's root to the nearest point of a target's box.
Build.REACH = 30

local measures: { [string]: Measure } = {}

function Build.getTemplate(itemId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local blocks = if assets then assets:FindFirstChild("Blocks") else nil
	local template = if blocks then blocks:FindFirstChild(itemId) else nil
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function measure(itemId: string): Measure?
	local cached = measures[itemId]
	if cached then
		return cached
	end
	local template = Build.getTemplate(itemId)
	local hitbox = if template then template.PrimaryPart else nil
	if not template or not hitbox then
		warn(`Build: "{itemId}" needs a template with a PrimaryPart hitbox in ReplicatedStorage.Assets.Blocks`)
		return nil
	end
	local cells = hitbox.Size / GRID
	local footprint = Vector3.new(math.round(cells.X), math.round(cells.Y), math.round(cells.Z))
	if (cells - footprint).Magnitude > 0.01 or math.min(footprint.X, footprint.Y, footprint.Z) < 1 then
		warn(`Build: "{itemId}"'s hitbox is {hitbox.Size}, not whole {GRID}-stud cells`)
		return nil
	end
	local result = {
		footprint = footprint,
		pivotOffset = hitbox.CFrame:ToObjectSpace(template:GetPivot()),
	}
	measures[itemId] = result
	return result
end

-- A copy of an item's art for display (icons, the hand): its template without the
-- invisible Hitbox, so only what can be seen is sized and framed. The pivot is kept.
function Build.copyArt(itemId: string): Model?
	local template = Build.getTemplate(itemId)
	if not template then
		return nil
	end
	local copy = template:Clone()
	local hitbox = copy:FindFirstChild("Hitbox")
	if hitbox then
		local pivot = copy:GetPivot()
		copy.PrimaryPart = nil
		copy.WorldPivot = pivot
		hitbox:Destroy()
	end
	return copy
end

-- For validating an untrusted cell: whole numbers within MAX_CELL of the origin.
function Build.isCell(value: Vector3): boolean
	for _, axis in { value.X, value.Y, value.Z } do
		if axis % 1 ~= 0 or math.abs(axis) > MAX_CELL then
			return false
		end
	end
	return true
end

-- For validating an untrusted rotation: a whole number of quarter turns, 0-3.
function Build.isRotation(value: number): boolean
	return value % 1 == 0 and value >= 0 and value <= 3
end

-- Footprint in cells after `rotation` quarter turns.
function Build.footprint(itemId: string, rotation: number): Vector3?
	local measured = measure(itemId)
	if not measured then
		return nil
	end
	local footprint = measured.footprint
	return if rotation % 2 == 1 then Vector3.new(footprint.Z, footprint.Y, footprint.X) else footprint
end

-- The cell a new block belongs in when the aim hits `position` on a surface facing
-- `normal`: half a cell out from the surface, so it lands against it, not inside it.
function Build.cellAt(position: Vector3, normal: Vector3): Vector3
	local scaled = (position + normal * (GRID / 2)) / GRID
	return Vector3.new(math.floor(scaled.X), math.floor(scaled.Y), math.floor(scaled.Z))
end

-- The origin (minimum cell) for a footprint aimed at `cell` on a surface facing
-- `normal`: it grows away from that surface, upward from the floor, and is centred on
-- the aimed cell along the remaining horizontal axes.
function Build.originFor(cell: Vector3, normal: Vector3, footprint: Vector3): Vector3
	local function horizontal(aimed: number, facing: number, size: number): number
		if facing > 0.5 then
			return aimed
		elseif facing < -0.5 then
			return aimed - size + 1
		end
		return aimed - math.floor((size - 1) / 2)
	end
	local y = if normal.Y < -0.5 then cell.Y - footprint.Y + 1 else cell.Y
	return Vector3.new(horizontal(cell.X, normal.X, footprint.X), y, horizontal(cell.Z, normal.Z, footprint.Z))
end

-- The box a placement fills, shrunk by TOUCH_MARGIN on every side.
function Build.box(origin: Vector3, footprint: Vector3): (CFrame, Vector3)
	local size = footprint * GRID
	return CFrame.new(origin * GRID + size / 2), size - Vector3.one * (TOUCH_MARGIN * 2)
end

-- Where a template's pivot goes for a placement: its hitbox fills the placement's box,
-- turned `rotation` quarter turns about Y.
function Build.pivotFor(itemId: string, origin: Vector3, rotation: number): CFrame?
	local measured = measure(itemId)
	local footprint = Build.footprint(itemId, rotation)
	if not measured or not footprint then
		return nil
	end
	local centre = Build.box(origin, footprint)
	return CFrame.new(centre.Position) * CFrame.Angles(0, rotation * math.pi / 2, 0) * measured.pivotOffset
end

function Build.inReach(from: Vector3, origin: Vector3, footprint: Vector3): boolean
	local centre, size = Build.box(origin, footprint)
	local offset = centre:PointToObjectSpace(from)
	local half = size / 2
	local nearest = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return (offset - nearest).Magnitude <= Build.REACH
end

-- OverlapParams for `isFree`. Terrain is always left out: its bounds cover the map.
function Build.newOverlapParams(): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Terrain }
	return params
end

-- Whether nothing queryable overlaps a placement's box.
function Build.isFree(origin: Vector3, footprint: Vector3, params: OverlapParams): boolean
	local centre, size = Build.box(origin, footprint)
	return #workspace:GetPartBoundsInBox(centre, size, params) == 0
end

return Build
