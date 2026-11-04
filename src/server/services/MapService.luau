-- MapService: builds the land round the gardens at startup from Shared/World/Map, all of it
-- anchored parts in Workspace.Map (no Terrain): a flat forest floor of grass past PlotService's
-- ground, out to the forest's edge, where World/Layout stands the choppable trees; dirt paths and
-- ponds with sandy rims through it; soft low-poly hills past the forest, triangles of wedges in
-- gently varied greens with rock on their bumpiest tops; an invisible wall at the very edge; and
-- a soft haze so the hills fade into the sky. Grass and dirt wear the game's own textures
-- (World/GroundLook), tiled like a garden's cubes, so the meadow carries on from the gardens'
-- ground without a seam. The floor is flat at y = 0, the level the trees and gardens stand at.
-- Nothing here is saved or belongs to anyone.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundLook = require(ReplicatedStorage.Shared.World.GroundLook)
local Map = require(ReplicatedStorage.Shared.World.Map)

-- Studs of floor under the forest.
local FLOOR = 16
-- Studs between the hills' grid lines (each square is two triangles), and the most they rise.
local HILL_STEP, HILL_TOP = 40, 184
-- Studs the hills rise by the map's edge, studs across their broad swells and small bumps.
local HILL_RISE, SWELL, BUMP = 130, 220, 70
-- Studs thick each hill triangle is, under its surface.
local HILL_THICKNESS = 2
-- Triangles a frame while the hills are built.
local HILL_BATCH = 200
local WALL_HEIGHT = 400
-- Paths stand this far proud of the floor, each the next one a little higher so crossings
-- never flicker. A texture is drawn with a depth bias that beats a surface a few hundredths of a
-- stud above it, so nothing lies closer than this over the textured floor.
local PATH_LIFT, PATH_STEP = 0.12, 0.03
local SAND = Color3.fromRGB(228, 212, 168)
local ROCK = Color3.fromRGB(158, 156, 150)
local WATER = Color3.fromRGB(96, 172, 176)
local POND_BED = Color3.fromRGB(70, 128, 120)
-- How far up the pond's water stands; it is a shallow wade, not a swim.
local WATER_DEPTH = 0.45

local MapService = {}

local folder = Instance.new("Folder")
folder.Name = "Map"

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance?): Part
	local block = Instance.new("Part")
	block.Name = name
	block.Size = size
	block.CFrame = cframe
	block.Color = color
	block.Material = Enum.Material.SmoothPlastic
	block.TopSurface = Enum.SurfaceType.Smooth
	block.BottomSurface = Enum.SurfaceType.Smooth
	block.Anchored = true
	block.CanTouch = false
	block.Parent = parent or folder
	return block
end

-- A flat disc lying on the ground, its top at `top`.
local function disc(name: string, centre: Vector2, radius: number, top: number, depth: number, color: Color3): Part
	local block = part(
		name,
		Vector3.new(depth, radius * 2, radius * 2),
		CFrame.new(centre.X, top - depth / 2, centre.Y) * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
	block.Shape = Enum.PartType.Cylinder
	return block
end

-- The forest floor: four strips of grass round PlotService's ground out to the forest's edge,
-- flush with it at y = 0.
local function floor()
	local g, f = Map.GROUND, Map.FOREST_EDGE
	local function strip(from: Vector2, to: Vector2)
		local size = Vector3.new(to.X - from.X, FLOOR, to.Y - from.Y)
		local block = part("Floor", size, CFrame.new((from.X + to.X) / 2, -FLOOR / 2, (from.Y + to.Y) / 2), Map.GRASS)
		GroundLook.grassy(block)
	end
	strip(Vector2.new(-f.X, -f.Y), Vector2.new(f.X, -g.Y))
	strip(Vector2.new(-f.X, g.Y), Vector2.new(f.X, f.Y))
	strip(Vector2.new(-f.X, -g.Y), Vector2.new(-g.X, g.Y))
	strip(Vector2.new(g.X, -g.Y), Vector2.new(f.X, g.Y))
end

-- Each path a strip of dirt just proud of the floor, rounded at its ends.
local function paths()
	for index, path in Map.PATHS do
		local top = PATH_LIFT + (index - 1) * PATH_STEP
		local from = Vector3.new(path.from.X, top, path.from.Y)
		local to = Vector3.new(path.to.X, top, path.to.Y)
		local length = (to - from).Magnitude
		if length > 0 then
			local middle = (from + to) / 2 - Vector3.yAxis * 0.25
			local strip = part(
				"Path",
				Vector3.new(path.width, 0.5, length),
				CFrame.lookAt(middle, middle + (to - from)),
				GroundLook.DIRT_COLOR
			)
			GroundLook.texture(strip, Enum.NormalId.Top, GroundLook.DIRT)
		end
		-- a hair under the strip, so where they overlap the strip's tiles show
		for _, at in { path.from, path.to } do
			local cap = disc("PathEnd", at, path.width / 2, top - 0.01, 0.5, GroundLook.DIRT_COLOR)
			GroundLook.texture(cap, Enum.NormalId.Right, GroundLook.DIRT)
		end
	end
end

-- Each pond a disc of sand, a darker bed and shallow water over it that can be waded through.
local function ponds()
	for _, pond in Map.PONDS do
		local r = pond.radius
		disc("Sand", pond.centre, r * 0.8 + 6, PATH_LIFT, 0.5, SAND)
		disc("PondBed", pond.centre, r * 0.78, PATH_LIFT + 0.04, 0.5, POND_BED)
		local water = disc("Water", pond.centre, r * 0.78 - 0.4, WATER_DEPTH, WATER_DEPTH - PATH_LIFT - 0.04, WATER)
		water.Transparency = 0.35
		water.Reflectance = 0.15
		water.CanCollide = false
		water.CanQuery = false
		water.CastShadow = false
	end
end

-- How far `x`, `z` lies into the hills: 0 at the forest's edge (or inside it), 1 at the map's
-- edge, measured from the forest's rectangle so its corners round off.
local function intoHills(x: number, z: number): number
	local inner = Map.FOREST_EDGE
	local outside = Vector2.new(math.max(math.abs(x) - inner.X, 0), math.max(math.abs(z) - inner.Y, 0))
	return outside.Magnitude / Map.HILLS
end

-- The hills' height at `x`, `z`: rising gently from the forest, steeper further out, in broad
-- swells with small bumps on them.
local function heightAt(x: number, z: number): number
	local into = intoHills(x, z)
	if into <= 0 then
		return 0
	end
	local rise = math.min(into, 1.2) ^ 1.6
	local swell = 0.7 + 0.6 * math.noise(x / SWELL, z / SWELL, 1.7)
	local bump = math.noise(x / BUMP, z / BUMP, 4.2) * 10 * math.min(1, into * 3)
	return math.clamp(rise * HILL_RISE * swell + bump, 0, HILL_TOP)
end

-- One flat triangle of the hills, as two wedges whose top faces are the triangle, sunk their
-- thickness under it.
local function triangle(a: Vector3, b: Vector3, c: Vector3, color: Color3, parent: Instance)
	-- a-b the longest side
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local normal = if right.Y >= 0 then right else -right
	local sink = -normal * HILL_THICKNESS / 2
	local first = Instance.new("WedgePart")
	first.Size = Vector3.new(HILL_THICKNESS, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2 + sink, right, up, back)
	local second = Instance.new("WedgePart")
	second.Size = Vector3.new(HILL_THICKNESS, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2 + sink, -right, up, -back)
	for _, wedge in { first, second } do
		wedge.Name = "Hill"
		wedge.Color = color
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Anchored = true
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.Parent = parent
	end
end

-- A hill triangle's colour: the meadow's green, a touch lighter or darker by a slow noise and
-- lighter up high, or rock on high, bumpy tops.
local function hillColor(centre: Vector3): Color3
	local rocky = centre.Y > 70 and math.noise(centre.X / 40, centre.Z / 40, 9.1) > 0.25
	if rocky then
		return ROCK:Lerp(Color3.new(1, 1, 1), 0.05 + 0.05 * math.noise(centre.X / 30, centre.Z / 30, 2.3))
	end
	local shade = math.noise(centre.X / 60, centre.Z / 60, 6.6) * 0.12
	local tint = Map.GRASS:Lerp(Color3.fromRGB(176, 206, 132), math.clamp(centre.Y / HILL_TOP, 0, 1) * 0.5)
	return if shade >= 0 then tint:Lerp(Color3.new(1, 1, 1), shade) else tint:Lerp(Color3.new(0, 0, 0), -shade)
end

-- Grid lines from -edge to edge, through -inner and inner, about HILL_STEP apart.
local function lines(inner: number, edge: number): { number }
	local out = {}
	local function run(from: number, to: number)
		local steps = math.max(1, math.round((to - from) / HILL_STEP))
		for step = 0, steps - 1 do
			table.insert(out, from + (to - from) * step / steps)
		end
	end
	run(-edge, -inner)
	run(-inner, inner)
	run(inner, edge)
	table.insert(out, edge)
	return out
end

-- The hills: a grid of squares over the whole map, skipping those inside the forest, each two
-- triangles lit from its four corners' heights. Built a batch of triangles a frame.
local function hills()
	local hillFolder = Instance.new("Folder")
	hillFolder.Name = "Hills"
	hillFolder.Parent = folder
	local inner, edge = Map.FOREST_EDGE, Map.EDGE
	local xs, zs = lines(inner.X, edge.X), lines(inner.Y, edge.Y)
	local function corner(i: number, j: number): Vector3
		local x, z = xs[i], zs[j]
		return Vector3.new(x, heightAt(x, z), z)
	end
	local batch = Instance.new("Folder")
	local count = 0
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			local middle = Vector2.new((xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2)
			if math.abs(middle.X) < inner.X and math.abs(middle.Y) < inner.Y then
				continue
			end
			local a, b, c, d = corner(i, j), corner(i + 1, j), corner(i + 1, j + 1), corner(i, j + 1)
			-- alternate the diagonal so the hills don't all lean one way
			if (i + j) % 2 == 0 then
				triangle(a, b, c, hillColor((a + b + c) / 3), batch)
				triangle(a, c, d, hillColor((a + c + d) / 3), batch)
			else
				triangle(a, b, d, hillColor((a + b + d) / 3), batch)
				triangle(b, c, d, hillColor((b + c + d) / 3), batch)
			end
			count += 2
			if count >= HILL_BATCH then
				count = 0
				batch.Parent = hillFolder
				batch = Instance.new("Folder")
				task.wait()
			end
		end
	end
	batch.Parent = hillFolder
end

-- An invisible wall round the map's edge, so nobody walks off the world.
local function walls()
	local edgeFolder = Instance.new("Folder")
	edgeFolder.Name = "MapEdge"
	local e = Map.EDGE
	for _, side in
		{
			{ Vector3.new(0, 0, -e.Y), Vector3.new(e.X * 2, 0, 2) },
			{ Vector3.new(0, 0, e.Y), Vector3.new(e.X * 2, 0, 2) },
			{ Vector3.new(-e.X, 0, 0), Vector3.new(2, 0, e.Y * 2) },
			{ Vector3.new(e.X, 0, 0), Vector3.new(2, 0, e.Y * 2) },
		}
	do
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Size = side[2] + Vector3.yAxis * WALL_HEIGHT
		wall.Position = side[1] + Vector3.yAxis * (WALL_HEIGHT / 2 - FLOOR)
		wall.Anchored = true
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Parent = edgeFolder
	end
	edgeFolder.Parent = workspace
end

local function haze()
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.22
		atmosphere.Offset = 0.25
		atmosphere.Color = Color3.fromRGB(206, 222, 236)
		atmosphere.Decay = Color3.fromRGB(140, 160, 180)
		atmosphere.Glare = 0
		atmosphere.Haze = 0.9
		atmosphere.Parent = Lighting
	end
end

function MapService.init()
	haze()
	floor()
	paths()
	ponds()
	folder.Parent = workspace
	walls()
	hills()
end

return MapService
