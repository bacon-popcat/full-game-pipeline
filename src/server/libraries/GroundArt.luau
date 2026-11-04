--!strict
-- GroundArt: the art of a garden's ground nodes (World `ground`). Grass, dirt and stone are copies
-- of the building block they dig into (Assets.Blocks, named by the node's `art`), so the ground
-- and the blocks a player builds with look alike. Farmland is built here: a cube of the game's
-- dirt texture (World/GroundLook) shaded down into furrows, with RIDGES raised bands across its
-- top in the dirt's own colour, so tilled earth reads as the dirt it came from. Wet Farmland
-- (GroundService) is the same art darkened, and paints back when it dries.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundLook = require(ReplicatedStorage.Shared.World.GroundLook)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local World = require(ReplicatedStorage.Shared.World)

local GRID = 3
-- How dark the furrows between the ridges are against the dirt, and how much darker wet earth is.
local FURROW_SHADE = 0.72
local WET_SHADE = 0.6
local RIDGES = 3
local RIDGE_WIDTH = 0.6
-- Studs a ridge stands proud of the cell's top; within the 0.15 art may poke past a hitbox.
local RIDGE_HEIGHT = 0.12

local GroundArt = {}

local function shade(color: Color3, by: number): Color3
	return Color3.new(color.R * by, color.G * by, color.B * by)
end

local function farmland(): Model
	local model = Instance.new("Model")
	local soil = Instance.new("Part")
	soil.Name = "Soil"
	soil.Size = Vector3.one * GRID
	soil.Material = Enum.Material.SmoothPlastic
	soil.TopSurface = Enum.SurfaceType.Smooth
	soil.BottomSurface = Enum.SurfaceType.Smooth
	for _, face in
		{ Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
	do
		GroundLook.texture(soil, face, GroundLook.DIRT)
	end
	soil.Parent = model
	model.PrimaryPart = soil
	for index = 1, RIDGES do
		local ridge = Instance.new("Part")
		ridge.Name = "Ridge"
		ridge.Size = Vector3.new(GRID, RIDGE_HEIGHT, RIDGE_WIDTH)
		ridge.CFrame = CFrame.new(0, (GRID + RIDGE_HEIGHT) / 2, (index - (RIDGES + 1) / 2) * GRID / RIDGES)
		ridge.TopSurface = Enum.SurfaceType.Smooth
		ridge.BottomSurface = Enum.SurfaceType.Smooth
		ridge.CanCollide = false
		ridge.CanQuery = false
		ridge.CanTouch = false
		ridge.CastShadow = false
		ridge.Parent = model
	end
	GroundArt.paint(model, false)
	return model
end

-- A fresh copy of a ground node's art, or nil when its block has no template.
function GroundArt.copy(nodeType: string): Model?
	if nodeType == "Farmland" then
		return farmland()
	end
	local art = World.getNode(nodeType).art
	local template = if art then ItemArt.blockTemplate(art) else nil
	return if template then template:Clone() else nil
end

-- Colours Farmland art dry or wet: the soil's textures are tinted down into furrows, the ridges
-- painted the dirt's own colour.
function GroundArt.paint(model: Model, wet: boolean)
	local by = if wet then WET_SHADE else 1
	local dirt = shade(GroundLook.DIRT_COLOR, by)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = if part.Name == "Ridge" then dirt else shade(dirt, FURROW_SHADE)
			for _, texture in part:GetChildren() do
				if texture:IsA("Texture") then
					texture.Color3 = shade(Color3.new(1, 1, 1), by * FURROW_SHADE)
				end
			end
		end
	end
end

return GroundArt
