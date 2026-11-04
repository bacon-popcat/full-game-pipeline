--!strict
-- GroundLook: the game's own dirt and grass textures, drawn by tools/textures/ground.py and uploaded
-- as images, so no ground uses Roblox's Grass or Ground material look. The Grass and Dirt
-- building cubes are a cube mesh carrying an atlas (GRASS_ATLAS: grass on top, dirt with grass
-- hanging over its top edge on the sides, dirt underneath; DIRT_ATLAS: dirt all round), set up in
-- Assets.Blocks by tools/textures/studio_cubes.luau, so a garden's ground (copies of them) gets
-- them too. Large flat parts (the meadow, paths, the ground round the gardens, Farmland) get
-- Texture objects, one tile per TILE studs, the size of a cube's face, so they match the cubes.

local GroundLook = {}

-- Studs one tile covers: a building cube's face.
GroundLook.TILE = 3
GroundLook.DIRT = "rbxassetid://101219562773882"
GroundLook.GRASS_TOP = "rbxassetid://93448050326812"
GroundLook.GRASS_SIDE = "rbxassetid://90328153402776"
GroundLook.GRASS_ATLAS = "rbxassetid://112773042872535"
GroundLook.DIRT_ATLAS = "rbxassetid://132915726710250"
-- The dirt texture's overall colour: a dirt part's own colour, seen while the texture loads and in
-- the distance, and what Farmland's ridges are painted.
GroundLook.DIRT_COLOR = Color3.fromRGB(164, 116, 70)

-- Covers `face` of `part` with `image`, tiled every TILE studs, tinted by `tint` (white leaves it
-- as drawn; darker shades it). Returns the Texture so its tint can change later.
function GroundLook.texture(part: BasePart, face: Enum.NormalId, image: string, tint: Color3?): Texture
	local texture = Instance.new("Texture")
	texture.Name = face.Name
	texture.Face = face
	texture.Texture = image
	texture.StudsPerTileU = GroundLook.TILE
	texture.StudsPerTileV = GroundLook.TILE
	texture.Color3 = tint or Color3.new(1, 1, 1)
	texture.Parent = part
	return texture
end

-- Grass on top and dirt on the four sides of `part` (the bottom is never seen).
function GroundLook.grassy(part: BasePart)
	part.Material = Enum.Material.SmoothPlastic
	GroundLook.texture(part, Enum.NormalId.Top, GroundLook.GRASS_TOP)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		GroundLook.texture(part, face, GroundLook.DIRT)
	end
end

return GroundLook
