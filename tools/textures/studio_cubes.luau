--[[
Gives the Grass and Dirt building cubes in ReplicatedStorage.Assets.Blocks the game's own textures
(Shared/World/GroundLook): each cube becomes a MeshPart of one cube mesh whose faces map onto a
three-tile atlas (tools/textures/ground.py): the top onto the first tile, the four sides onto the
second, the bottom onto the third. The Grass cube wears GRASS_ATLAS (grass on top, dirt with grass
hanging over the top edge on the sides, dirt underneath); the Dirt cube DIRT_ATLAS. One mesh with
its texture keeps a garden's ground at one instance per cell, where Texture objects would add six.

The mesh is uploaded once to the logged-in account (AssetService:CreateAssetAsync) and its id kept
as the GroundCubeMesh attribute of Assets.Blocks, so a rerun reuses it. Each cube keeps its name,
size, pivot, attributes and children; its colour is the texture's overall colour, which is what
Farmland's ridges and anything else reading the cube's Color get.

Run it through the Studio MCP (execute_luau, Edit datamodel), then save the place.
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundLook = require(ReplicatedStorage.Shared.World.GroundLook)
local Map = require(ReplicatedStorage.Shared.World.Map)

-- The atlas's layout (tools/textures/ground.py): TILE-pixel tiles, each in a cell GUTTER pixels
-- bigger all round, side by side.
local TILE, GUTTER, CELLS = 256, 8, 3
local CELL = TILE + GUTTER * 2
local WIDTH, HEIGHT = CELL * CELLS, CELL
local HALF = 1.5

local CUBES = {
	Grass = { atlas = GroundLook.GRASS_ATLAS, color = Map.GRASS },
	Dirt = { atlas = GroundLook.DIRT_ATLAS, color = GroundLook.DIRT_COLOR },
}

-- The UV of a point (u, v from 0 to 1) inside atlas tile `index` (0-based).
local function uv(index: number, u: number, v: number): Vector2
	return Vector2.new((index * CELL + GUTTER + u * TILE) / WIDTH, (GUTTER + v * TILE) / HEIGHT)
end

local function cubeMesh(): EditableMesh
	local mesh = AssetService:CreateEditableMesh()
	-- Each face: its normal, the directions of the texture's right (u) and down (v) as seen from
	-- outside, and its atlas tile.
	local faces = {
		{ Vector3.yAxis, Vector3.xAxis, Vector3.zAxis, 0 },
		{ -Vector3.yAxis, Vector3.xAxis, -Vector3.zAxis, 2 },
		{ Vector3.zAxis, Vector3.xAxis, -Vector3.yAxis, 1 },
		{ -Vector3.zAxis, -Vector3.xAxis, -Vector3.yAxis, 1 },
		{ Vector3.xAxis, -Vector3.zAxis, -Vector3.yAxis, 1 },
		{ -Vector3.xAxis, Vector3.zAxis, -Vector3.yAxis, 1 },
	}
	for _, face in faces do
		local normal, right, down, tile = face[1], face[2], face[3], face[4]
		local nid = mesh:AddNormal(normal)
		local corners = {}
		for _, at in { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } do
			local position = (normal + right * (at[1] * 2 - 1) + down * (at[2] * 2 - 1)) * HALF
			table.insert(corners, { mesh:AddVertex(position), mesh:AddUV(uv(tile, at[1], at[2])) })
		end
		-- counter-clockwise seen from outside: top-left, bottom-left, bottom-right, top-right
		for _, triangle in { { 1, 4, 3 }, { 1, 3, 2 } } do
			local a, b, c = corners[triangle[1]], corners[triangle[2]], corners[triangle[3]]
			local fid = mesh:AddTriangle(a[1], b[1], c[1])
			mesh:SetFaceUVs(fid, { a[2], b[2], c[2] })
			mesh:SetFaceNormals(fid, { nid, nid, nid })
		end
	end
	return mesh
end

local blocks = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Blocks")
local meshId = blocks:GetAttribute("GroundCubeMesh")
if not meshId then
	local ok, result, id = pcall(
		AssetService.CreateAssetAsync,
		AssetService,
		cubeMesh(),
		Enum.AssetType.Mesh,
		{ Name = "GroundCube", Description = "A 3-stud cube mapped onto a three-tile atlas: top, sides, bottom." }
	)
	assert(ok and result == Enum.CreateAssetResult.Success, `upload failed: {result} {id}`)
	meshId = id
	blocks:SetAttribute("GroundCubeMesh", meshId)
end

local template: MeshPart? = nil
for _ = 1, 30 do -- a new asset can take a few seconds before it loads
	local ok, part = pcall(AssetService.CreateMeshPartAsync, AssetService, Content.fromAssetId(meshId), {
		CollisionFidelity = Enum.CollisionFidelity.Box,
	})
	if ok then
		template = part
		break
	end
	task.wait(2)
end
assert(template, `mesh {meshId} would not load`)

local done = {}
for name, look in CUBES do
	local model = blocks:FindFirstChild(name)
	local old = if model and model:IsA("Model") then model.PrimaryPart else nil
	if not model or not old then
		table.insert(done, `{name}: no template`)
		continue
	end
	local cube = template:Clone()
	cube.Name = old.Name
	cube.Size = old.Size
	cube.CFrame = old.CFrame
	cube.TextureID = look.atlas
	cube.Color = look.color
	cube.Material = Enum.Material.SmoothPlastic
	for _, property in { "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow" } do
		(cube :: any)[property] = (old :: any)[property]
	end
	for key, value in old:GetAttributes() do
		cube:SetAttribute(key, value)
	end
	for _, child in old:GetChildren() do
		child.Parent = cube
	end
	cube.Parent = model
	model.PrimaryPart = cube
	if old ~= cube then
		old:Destroy()
	end
	table.insert(done, `{name}: mesh {meshId}, {look.atlas}`)
end
return table.concat(done, "; ")
