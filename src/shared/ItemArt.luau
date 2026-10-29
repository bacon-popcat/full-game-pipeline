--!strict
-- ItemArt: where every item's art lives, and display copies of it for item icons, the
-- hand and items riding conveyors. Blocks and machines draw their template from
-- Assets.Blocks (without its hitbox), tools their Tool from Assets.Tools, and resources a
-- Model from Assets.Items. Build delegates template lookup here. Missing crop/seed art
-- borrows the crop table's base art and tint; mutations tint their base produce. Expected
-- fallbacks are silent; other missing resources draw a grey cube and warn once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.World)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Inventory = require(ReplicatedStorage.Shared.Inventory)

local PLACEHOLDER_COLOR = Color3.fromRGB(160, 160, 160)

local ItemArt = {}

local warned: { [string]: boolean } = {}

local function asset(folder: string, name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local holder = if assets then assets:FindFirstChild(folder) else nil
	return if holder then holder:FindFirstChild(name) else nil
end

local function placeholder(): Model
	local model = Instance.new("Model")
	local part = Instance.new("Part")
	part.Size = Vector3.one
	part.Color = PLACEHOLDER_COLOR
	part.Anchored = true
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- Geometry callers use the same seed fallback as icons, without making Build and ItemArt cyclic.
function ItemArt.blockTemplate(itemId: string): Model?
	local found = asset("Blocks", itemId)
	if found and found:IsA("Model") then
		return found
	end
	for _, crop in World.CROPS do
		if crop.seed == itemId then
			local fallback = asset("Blocks", crop.art .. "Seeds")
			if fallback and fallback:IsA("Model") then
				return fallback
			end
		end
	end
	return nil
end

function ItemArt.tint(model: Model, color: Color3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Hitbox" then
			part.Color = color
		end
	end
end

function ItemArt.copyBlock(itemId: string): Model?
	local template = ItemArt.blockTemplate(itemId)
	if not template then
		return nil
	end
	local copy = template:Clone()
	for _, crop in World.CROPS do
		if crop.seed == itemId and template.Name ~= itemId then
			ItemArt.tint(copy, crop.color)
		end
	end
	return copy
end

function ItemArt.blockArt(itemId: string): Model?
	local copy = ItemArt.copyBlock(itemId)
	if copy then
		local hitbox = copy:FindFirstChild("Hitbox")
		if hitbox then
			local pivot = copy:GetPivot()
			copy.PrimaryPart = nil
			copy.WorldPivot = pivot
			hitbox:Destroy()
		end
	end
	return copy
end

-- A copy of the item's art as a Model, or nil when a block or tool has no template.
function ItemArt.copy(itemId: string): Model?
	local item = Inventory.getItem(itemId)
	if Inventory.isPlaceable(item) then
		return ItemArt.blockArt(itemId)
	end
	if item.kind == "Tool" then
		local template = asset("Tools", itemId)
		if not template or not template:IsA("Tool") then
			return nil
		end
		local model = Instance.new("Model")
		for _, child in template:Clone():GetChildren() do
			child.Parent = model
		end
		return model
	end
	local base = item.base or itemId
	local crop = World.CROPS[base]
	local template = asset("Items", base)
	local fallback = false
	if not template and crop then
		template = asset("Items", crop.art)
		fallback = true
	end
	if template and template:IsA("Model") then
		local copy = template:Clone()
		if item.mutation then
			ItemArt.tint(copy, Mutations.ALL[item.mutation].color)
		elseif fallback and crop then
			ItemArt.tint(copy, crop.color)
		end
		return copy
	end
	if not warned[itemId] then
		warned[itemId] = true
		warn(`ItemArt: no model for "{itemId}" in ReplicatedStorage.Assets.Items; drawing a placeholder`)
	end
	return placeholder()
end

return ItemArt
