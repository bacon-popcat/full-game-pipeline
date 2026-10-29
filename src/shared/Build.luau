--!strict
-- Build: the placement grid, shared so the client's ghost and the server's check agree.
--
-- The world is cut into GRID-stud cells from the world origin (the baseplate's top is
-- Y = 0). A placeable occupies a footprint of whole cells, sits on the floor of its
-- origin (minimum) cell, and turns in quarter steps about Y. A placement is legal when it
-- is within REACH of the placer, nothing queryable but characters overlaps its box, and
-- the block's own parts don't clip a character. Those geometric tests cover placed blocks,
-- world props and characters alike, so there is no occupancy map to fall out of sync with
-- the world. Characters are tested against the art, not the box, so a player can stand in
-- the empty corner of a machine's cells, or on a conveyor's floor cell beside its belt.
--
-- Templates live in ReplicatedStorage.Assets.Blocks, named by item id. A template's
-- PrimaryPart is its hitbox: a box of whole cells, so its size is the footprint and
-- placing it fills the placement's box. The template's pivot is read relative to the
-- hitbox, so it can sit wherever is convenient to hold it by. A machine's hitbox is an
-- invisible part named Hitbox around its art, which may poke past it by up to 0.15 studs
-- (docs/inventory.md); a plain cube is its own hitbox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plot = require(ReplicatedStorage.Shared.Plot)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)

type Measure = {
	footprint: Vector3,
	-- The template's pivot relative to its hitbox (identity unless someone moved it).
	pivotOffset: CFrame,
}

local GRID = 3
-- Shrinks overlap boxes so blocks that only touch faces, or whose art pokes past its
-- hitbox by the 0.15 studs allowed, don't count as overlapping.
local TOUCH_MARGIN = 0.2
-- Studs each art part shrinks by on every side before testing it against characters, so a
-- character merely brushing a block's surface doesn't count as clipping it.
local CLIP_MARGIN = 0.1
-- Cells from the origin a placement may name; keeps untrusted cells to sane numbers.
local MAX_CELL = 10000

local Build = {}

Build.GRID = GRID
-- Studs from the character's root to the nearest point of a target's box.
Build.REACH = 30

-- Ownership covers the entire footprint, including its last cell. The replicated plot
-- owner is the authority on both sides; DataReady gates edits while a profile is loading.
function Build.owns(player: Player, origin: Vector3, footprint: Vector3): boolean
	local index = Plot.at(origin)
	local plots = workspace:FindFirstChild("Plots")
	local model = if index and plots then plots:FindFirstChild(tostring(index)) else nil
	return index ~= nil
		and model ~= nil
		and model:GetAttribute("Owner") == player.UserId
		and origin.Y >= 0
		and origin.Y + footprint.Y <= Plot.HEIGHT
		and Plot.contains(index, origin, footprint)
end

function Build.canEdit(player: Player, origin: Vector3, footprint: Vector3): boolean
	return player:GetAttribute("DataReady") == true and Build.owns(player, origin, footprint)
end

local measures: { [string]: Measure } = {}
-- A shrunken copy of each template's colliding art, kept out of the world, moved to a
-- placement and tested against characters (`clipsCharacter`).
local probes: { [string]: { model: Model, parts: { BasePart } } } = {}
local characterParams = OverlapParams.new()
characterParams.FilterType = Enum.RaycastFilterType.Include

function Build.getTemplate(itemId: string): Model?
	return ItemArt.blockTemplate(itemId)
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
	return ItemArt.blockArt(itemId)
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

-- Whether `part` belongs to an item lying loose in Workspace.Drops. Drops collide, and
-- CanQuery only hides parts that don't, so queries have to skip them by hand.
function Build.isLoose(part: Instance): boolean
	local drops = workspace:FindFirstChild("Drops")
	return drops ~= nil and part:IsDescendantOf(drops)
end

-- Whether `part` belongs to a player's character, including what it wears and holds.
function Build.isCharacter(part: Instance): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if Players:GetPlayerFromCharacter(model) then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- Whether nothing queryable but characters and loose drops overlaps a placement's box.
-- Characters are `clipsCharacter`'s to judge, against the block's art.
function Build.isFree(origin: Vector3, footprint: Vector3, params: OverlapParams): boolean
	local centre, size = Build.box(origin, footprint)
	for _, part in workspace:GetPartBoundsInBox(centre, size, params) do
		if not Build.isLoose(part) and not Build.isCharacter(part) then
			return false
		end
	end
	return true
end

local function probe(itemId: string): { model: Model, parts: { BasePart } }?
	local cached = probes[itemId]
	if cached then
		return cached
	end
	local template = Build.getTemplate(itemId)
	if not template then
		return nil
	end
	local model = template:Clone()
	local parts = {}
	for _, part in model:GetDescendants() do
		-- A plain cube is its own hitbox, so only a part named Hitbox is left out.
		if part:IsA("BasePart") and part.Name ~= "Hitbox" and part.CanCollide then
			part.Size = (part.Size - Vector3.one * (CLIP_MARGIN * 2)):Max(Vector3.one * 0.05)
			table.insert(parts, part)
		end
	end
	local result = { model = model, parts = parts }
	probes[itemId] = result
	return result
end

-- Whether any colliding part of the block's art, with its pivot at `pivot`, would clip a
-- player's character. Tests the parts' real shapes, so empty space inside the block's
-- cells is free to stand in.
function Build.clipsCharacter(itemId: string, pivot: CFrame): boolean
	local art = probe(itemId)
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	if not art or #characters == 0 then
		return false
	end
	characterParams.FilterDescendantsInstances = characters
	art.model:PivotTo(pivot)
	for _, part in art.parts do
		if #workspace:GetPartsInPart(part, characterParams) > 0 then
			return true
		end
	end
	return false
end

return Build
