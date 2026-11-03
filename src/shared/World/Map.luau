--!strict
-- Map: where the land round the gardens and the hub lies, in studs on the ground plane (X, Z),
-- built outward from the gardens' own extent (Shared/Plot), so moving a garden moves the map
-- with it. PlotService lays exact grass ground over the gardens and GROUND_MARGIN past them.
-- MapService grows Terrain past that: a flat forest ring FOREST wide, where World/Layout stands
-- the choppable trees, crossed by paths and dotted with ponds that the trees keep clear of; then
-- HILLS of soft hills closing the view, with a wall at the very edge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)

export type Path = { from: Vector2, to: Vector2, width: number }
export type Pond = { centre: Vector2, radius: number }

local Map = {}

-- Studs of PlotService's grass round the gardens on every side.
Map.GROUND_MARGIN = 36
-- The meadow grass of the ground round the gardens and the Terrain past it, one colour so the
-- seam between them doesn't show.
Map.GRASS = Color3.fromRGB(142, 186, 112)
-- Studs of flat forest past that ground, then of hills past the forest.
Map.FOREST = 150
Map.HILLS = 240

local reach = Vector2.zero
for index = 1, Plot.COUNT do
	local a = Plot.pointToWorld(index, Vector3.zero) * Build.GRID
	local b = Plot.pointToWorld(index, Vector3.new(Plot.WIDTH, 0, Plot.DEPTH)) * Build.GRID
	reach = reach:Max(Vector2.new(math.max(math.abs(a.X), math.abs(b.X)), math.max(math.abs(a.Z), math.abs(b.Z))))
end
-- Half extents of the gardens' ground, the forest's outer edge and the map's edge.
Map.GROUND = reach + Vector2.one * Map.GROUND_MARGIN
Map.FOREST_EDGE = Map.GROUND + Vector2.one * Map.FOREST
Map.EDGE = Map.FOREST_EDGE + Vector2.one * Map.HILLS

local ground, forest = Map.GROUND, Map.FOREST_EDGE
local middle = (ground + forest) / 2
-- Dirt paths: from each end of the hub road out into the woods, and a loop round the middle of
-- the forest that they join.
Map.PATHS = {
	{ from = Vector2.new(ground.X - 8, 0), to = Vector2.new(middle.X, 0), width = 12 },
	{ from = Vector2.new(-ground.X + 8, 0), to = Vector2.new(-middle.X, 0), width = 12 },
	{ from = Vector2.new(-middle.X, -middle.Y), to = Vector2.new(middle.X, -middle.Y), width = 9 },
	{ from = Vector2.new(-middle.X, middle.Y), to = Vector2.new(middle.X, middle.Y), width = 9 },
	{ from = Vector2.new(-middle.X, -middle.Y), to = Vector2.new(-middle.X, middle.Y), width = 9 },
	{ from = Vector2.new(middle.X, -middle.Y), to = Vector2.new(middle.X, middle.Y), width = 9 },
} :: { Path }

-- Ponds: two in the forest's far corners, past the loop, and a small one between the loop and
-- the gardens; each clear of the paths.
Map.PONDS = {
	{ centre = Vector2.new(forest.X - 34, -(forest.Y - 36)), radius = 26 },
	{ centre = Vector2.new(-(forest.X - 36), forest.Y - 34), radius = 24 },
	{ centre = Vector2.new(-210, -(ground.Y + 37)), radius = 18 },
} :: { Pond }

-- Distance from `point` to the segment a-b.
local function toSegment(point: Vector2, a: Vector2, b: Vector2): number
	local along = b - a
	local t = if along.Magnitude > 0 then math.clamp((point - a):Dot(along) / along:Dot(along), 0, 1) else 0
	return (point - (a + along * t)).Magnitude
end

-- Whether `point` is in the forest ring, at least `pad` studs inside its edges.
function Map.inForest(point: Vector2, pad: number): boolean
	local x, z = math.abs(point.X), math.abs(point.Y)
	local insideOuter = x <= forest.X - pad and z <= forest.Y - pad
	local outsideGround = x >= ground.X + pad or z >= ground.Y + pad
	return insideOuter and outsideGround
end

-- Whether `point` is at least `pad` studs clear of every path and pond.
function Map.isClear(point: Vector2, pad: number): boolean
	for _, path in Map.PATHS do
		if toSegment(point, path.from, path.to) < path.width / 2 + pad then
			return false
		end
	end
	for _, pond in Map.PONDS do
		if (point - pond.centre).Magnitude < pond.radius + pad then
			return false
		end
	end
	return true
end

return Map
