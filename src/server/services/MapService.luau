-- MapService: grows the land round the gardens at startup, from Shared/World/Map: Terrain meadow
-- grass past PlotService's ground (also under that ground's edge, below its top, so the seam never
-- shows a gap), dirt paths and ponds with sandy rims through the forest ring that World/Layout
-- fills with trees, smooth rolling hills past the forest with rock on their bumpiest tops, an
-- invisible wall at the very edge, and a soft haze so the hills fade into the sky. The meadow and
-- the forest floor are flat at y = 0, the level the trees and gardens stand at. Nothing here is
-- saved or belongs to anyone; the place's own Terrain is only added to.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(ReplicatedStorage.Shared.World.Map)

-- Studs of Terrain under the meadow, and how far it reaches in under PlotService's ground.
local FLOOR, TUCK = 16, 8
-- Voxel size, studs of hills written per chunk (one chunk a frame), and the most they rise.
local RES, CHUNK, HILL_TOP = 4, 64, 184
-- Studs the hills rise by the map's edge, studs across their broad swells and small bumps.
local HILL_RISE, SWELL, BUMP = 130, 220, 70
local WALL_HEIGHT = 400
local PATH = Color3.fromRGB(190, 156, 112)
local SAND = Color3.fromRGB(228, 212, 168)
local ROCK = Color3.fromRGB(158, 156, 150)
local WATER = Color3.fromRGB(96, 172, 176)

local MapService = {}

local terrain = workspace.Terrain

-- A block of `material` between two corners on the ground plane, its top at `top`.
local function slab(from: Vector2, to: Vector2, top: number, depth: number, material: Enum.Material)
	local size = Vector3.new(math.abs(to.X - from.X), depth, math.abs(to.Y - from.Y))
	if size.X > 0 and size.Z > 0 then
		terrain:FillBlock(CFrame.new((from.X + to.X) / 2, top - depth / 2, (from.Y + to.Y) / 2), size, material)
	end
end

-- The meadow: four strips round PlotService's ground out to the edge, flush with it at y = 0,
-- then a ring tucked under the ground's edge below its top, where its parts hide it.
local function meadow()
	local g, e = Map.GROUND, Map.EDGE
	local grass = Enum.Material.Grass
	slab(Vector2.new(-e.X, -e.Y), Vector2.new(e.X, -g.Y), 0, FLOOR, grass)
	slab(Vector2.new(-e.X, g.Y), Vector2.new(e.X, e.Y), 0, FLOOR, grass)
	slab(Vector2.new(-e.X, -g.Y), Vector2.new(-g.X, g.Y), 0, FLOOR, grass)
	slab(Vector2.new(g.X, -g.Y), Vector2.new(e.X, g.Y), 0, FLOOR, grass)
	local t = TUCK
	slab(Vector2.new(-g.X, -g.Y), Vector2.new(g.X, -g.Y + t), -1, FLOOR, grass)
	slab(Vector2.new(-g.X, g.Y - t), Vector2.new(g.X, g.Y), -1, FLOOR, grass)
	slab(Vector2.new(-g.X, -g.Y), Vector2.new(-g.X + t, g.Y), -1, FLOOR, grass)
	slab(Vector2.new(g.X - t, -g.Y), Vector2.new(g.X, g.Y), -1, FLOOR, grass)
end

-- Each path a strip of dirt in the meadow's top, rounded at its ends. Fills are a whole voxel
-- deep: a thinner one leaves the meadow's grass showing on top.
local function paths()
	for _, path in Map.PATHS do
		local from = Vector3.new(path.from.X, -RES / 2, path.from.Y)
		local to = Vector3.new(path.to.X, -RES / 2, path.to.Y)
		local length = (to - from).Magnitude
		if length > 0 then
			local middle = (from + to) / 2
			terrain:FillBlock(
				CFrame.lookAt(middle, middle + (to - from)),
				Vector3.new(path.width, RES, length),
				Enum.Material.Ground
			)
		end
		for _, at in { from, to } do
			terrain:FillCylinder(CFrame.new(at), RES, path.width / 2, Enum.Material.Ground)
		end
	end
end

-- Each pond a shallow bowl of water with a sandy rim.
local function ponds()
	for _, pond in Map.PONDS do
		local centre = Vector3.new(pond.centre.X, 0, pond.centre.Y)
		local r = pond.radius
		terrain:FillCylinder(CFrame.new(centre - Vector3.yAxis * RES / 2), RES, r * 0.8 + 6, Enum.Material.Sand)
		-- A ball above the ground carves a bowl 0.4 r deep, 0.8 r across at the top.
		terrain:FillBall(centre + Vector3.yAxis * r * 0.6, r, Enum.Material.Air)
		local depth = r * 0.4
		terrain:FillCylinder(
			CFrame.new(centre - Vector3.yAxis * (1.2 + depth / 2)),
			depth,
			r * 0.78,
			Enum.Material.Water
		)
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
	return math.clamp(rise * HILL_RISE * swell + bump, 0, HILL_TOP - RES)
end

-- The hills as one smooth heightmap, written a chunk a frame. Each column's top voxel is only
-- partly filled, so slopes come out smooth rather than stepped. Rock shows on the high, bumpy
-- tops.
local function hills()
	local inner, edge = Map.FOREST_EDGE, Map.EDGE
	local low = Vector2.new(math.floor(-edge.X / CHUNK) * CHUNK, math.floor(-edge.Y / CHUNK) * CHUNK)
	local layers = HILL_TOP // RES
	local columns = CHUNK // RES
	for cx = low.X, edge.X, CHUNK do
		for cz = low.Y, edge.Y, CHUNK do
			-- Chunks wholly inside the forest have no hills to write.
			local far =
				Vector2.new(math.max(math.abs(cx), math.abs(cx + CHUNK)), math.max(math.abs(cz), math.abs(cz + CHUNK)))
			if far.X <= inner.X and far.Y <= inner.Y then
				continue
			end
			local materials, occupancies = {}, {}
			for ix = 1, columns do
				materials[ix], occupancies[ix] = {}, {}
				for iy = 1, layers do
					materials[ix][iy], occupancies[ix][iy] = {}, {}
				end
				for iz = 1, columns do
					local x, z = cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES
					local height = heightAt(x, z)
					local rocky = height > 70 and math.noise(x / 40, z / 40, 9.1) > 0.25
					for iy = 1, layers do
						local fill = math.clamp((height - (iy - 1) * RES) / RES, 0, 1)
						materials[ix][iy][iz] = if fill <= 0
							then Enum.Material.Air
							elseif rocky and height - (iy - 1) * RES < RES * 2 then Enum.Material.Rock
							else Enum.Material.Grass
						occupancies[ix][iy][iz] = fill
					end
				end
			end
			local region = Region3.new(Vector3.new(cx, 0, cz), Vector3.new(cx + CHUNK, layers * RES, cz + CHUNK))
			terrain:WriteVoxels(region, RES, materials, occupancies)
			task.wait()
		end
	end
end

-- An invisible wall round the map's edge, so nobody walks off the world.
local function walls()
	local folder = Instance.new("Folder")
	folder.Name = "MapEdge"
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
		wall.Parent = folder
	end
	folder.Parent = workspace
end

local function look()
	terrain:SetMaterialColor(Enum.Material.Grass, Map.GRASS)
	terrain:SetMaterialColor(Enum.Material.Ground, PATH)
	terrain:SetMaterialColor(Enum.Material.Sand, SAND)
	terrain:SetMaterialColor(Enum.Material.Rock, ROCK)
	terrain.WaterColor = WATER
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local haze = Instance.new("Atmosphere")
		haze.Density = 0.22
		haze.Offset = 0.25
		haze.Color = Color3.fromRGB(206, 222, 236)
		haze.Decay = Color3.fromRGB(140, 160, 180)
		haze.Glare = 0
		haze.Haze = 0.9
		haze.Parent = Lighting
	end
end

function MapService.init()
	look()
	meadow()
	paths()
	ponds()
	walls()
	hills()
end

return MapService
