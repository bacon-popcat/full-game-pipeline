--!strict
-- ItemArt: where every item's art lives, and display copies of it for item icons, the
-- hand and items riding conveyors. Blocks and machines draw their template from
-- Assets.Blocks (without its hitbox, via Build), tools their Tool from Assets.Tools, and
-- resources a Model from Assets.Items. A resource with no model yet draws a plain grey
-- cube and warns once, so a gap in the art never stops the factory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
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

-- A copy of the item's art as a Model, or nil when a block or tool has no template.
function ItemArt.copy(itemId: string): Model?
	local item = Inventory.getItem(itemId)
	if Inventory.isPlaceable(item) then
		return Build.copyArt(itemId)
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
	local template = asset("Items", itemId)
	if template and template:IsA("Model") then
		return template:Clone()
	end
	if not warned[itemId] then
		warned[itemId] = true
		warn(`ItemArt: no model for "{itemId}" in ReplicatedStorage.Assets.Items; drawing a placeholder`)
	end
	return placeholder()
end

return ItemArt
