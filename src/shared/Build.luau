--!strict
-- Build: the placement grid, shared so the client's ghost and the server's check agree.
--
-- The world is cut into GRID-stud cells from the world origin (the baseplate's top is
-- Y = 0). A placeable occupies a footprint of whole cells -- its template's bounding box
-- rounded up -- sits on the floor of its origin (minimum) cell, and turns in quarter
-- steps about Y. A placement is legal when it is within REACH of the placer and nothing
-- queryable overlaps its box. That one geometric test covers placed blocks, world props
-- and characters alike, so there is no occupancy map to fall out of sync with the world.
--
-- Templates live in ReplicatedStorage.Assets.Blocks, named by item id. Their footprints
-- are measured once and cached.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Measure = {
	footprint: Vector3,
	-- The template's pivot relative to the bottom-centre of its bounding box.
	pivotOffset: CFrame,
}

local GRID = 3
-- Studs a model may poke past a cell edge and still count as fitting the cell.
local FIT_TOLERANCE = 0.15
-- Shrinks overlap boxes so blocks that only touch faces don't count as overlapping.
local TOUCH_MARGIN = 0.1
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

local function cells(studs: number): number
	return math.max(1, math.ceil((studs - FIT_TOLERANCE) / GRID))
end

local function measure(itemId: string): Measure?
	local cached = measures[itemId]
	if cached then
		return cached
	end
	local template = Build.getTemplate(itemId)
	if not template then
		warn(`Build: no template for "{itemId}" in ReplicatedStorage.Assets.Blocks`)
		return nil
	end
	local box, size = template:GetBoundingBox()
	local bottom = box * CFrame.new(0, -size.Y / 2, 0)
	local result = {
		footprint = Vector3.new(cells(size.X), cells(size.Y), cells(size.Z)),
		pivotOffset = bottom:ToObjectSpace(template:GetPivot()),
	}
	measures[itemId] = result
	return result
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

-- Where a template's pivot goes for a placement.
function Build.pivotFor(itemId: string, origin: Vector3, rotation: number): CFrame?
	local measured = measure(itemId)
	local footprint = Build.footprint(itemId, rotation)
	if not measured or not footprint then
		return nil
	end
	local size = footprint * GRID
	local bottomCentre = origin * GRID + Vector3.new(size.X / 2, 0, size.Z / 2)
	return CFrame.new(bottomCentre) * CFrame.Angles(0, rotation * math.pi / 2, 0) * measured.pivotOffset
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
