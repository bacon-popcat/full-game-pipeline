--!strict
-- Soil: whether an item may be planted in a cell. A sapling grows anywhere; a seed needs soil
-- under it: a placed Grass or Dirt block (World.SOIL_BLOCKS) or a world node marked `soil`
-- (Farmland). The client's ghost and the server's placing and planting all ask this, and it
-- reads the world itself, like Build's overlap test, so there is no soil map to fall out of
-- sync with blocks being placed and broken.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local World = require(ReplicatedStorage.Shared.World)

local Soil = {}

local params = Build.newOverlapParams()

-- The model directly in `folder` that `part` belongs to.
local function modelIn(part: Instance, folder: Instance?): Model?
	if not folder then
		return nil
	end
	local current: Instance? = part
	while current and current.Parent ~= folder do
		current = current.Parent
	end
	return if current and current:IsA("Model") then current else nil
end

-- Whether the cell under `cell` holds a whole block of soil.
function Soil.isUnder(cell: Vector3): boolean
	local below = cell - Vector3.yAxis
	local centre, size = Build.box(below, Vector3.one)
	local placed = workspace:FindFirstChild("Placed")
	local world = workspace:FindFirstChild("World")
	for _, part in workspace:GetPartBoundsInBox(centre, size, params) do
		local block = modelIn(part, placed)
		local itemId = if block then block:GetAttribute("ItemId") else nil
		if block and typeof(itemId) == "string" and World.SOIL_BLOCKS[itemId] then
			-- a cube fills exactly its origin cell
			return block:GetAttribute("Origin") == below
		end
		local node = modelIn(part, world)
		local nodeType = if node then node:GetAttribute("NodeType") else nil
		local def = if typeof(nodeType) == "string" then World.NODES[nodeType] else nil
		if node and def and def.soil then
			return node:GetAttribute("Cell") == below
		end
	end
	return false
end

-- Whether `itemId` may be planted in `cell`, as far as the ground goes: true for anything that
-- isn't a plant, and for a plant that needs no soil.
function Soil.canPlant(itemId: string, cell: Vector3): boolean
	local plant = World.PLANTS[itemId]
	return not plant or not plant.soil or Soil.isUnder(cell)
end

return Soil
