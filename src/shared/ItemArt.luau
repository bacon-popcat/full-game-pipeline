--!strict
-- ItemArt: where every item's art lives, and display copies of it for item icons, the
-- hand and items riding conveyors. Blocks and machines draw their template from
-- Assets.Blocks (without its hitbox), tools their Tool from Assets.Tools (a plain built one
-- for the Hoe until it has its own), and resources a
-- Model from Assets.Items. Build delegates template lookup here. Missing crop/seed art
-- borrows the crop table's base art and tint; mutations tint their base produce. Expected
-- fallbacks are silent; other missing resources draw a grey cube and warn once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.World)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Inventory = require(ReplicatedStorage.Shared.Inventory)

local PLACEHOLDER_COLOR = Color3.fromRGB(160, 160, 160)
local WOOD_COLOR = Color3.fromRGB(176, 128, 86)
local BLADE_COLOR = Color3.fromRGB(196, 202, 206)
-- How much bigger than one item a stack draws, at most, and the count it is reached at.
local STACK_GROWTH = 0.6
local STACK_FULL = 100

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

-- How much bigger a stack of `count` draws than one item, loose or on a belt: a pile reads
-- as bigger, rising quickly at first and no more than 1 + STACK_GROWTH.
function ItemArt.stackScale(count: number): number
	return 1 + STACK_GROWTH * math.clamp(math.log(math.max(count, 1)) / math.log(STACK_FULL), 0, 1)
end

-- Geometry callers use the same seed fallback as icons, without making Build and ItemArt cyclic.
-- An item with no template of its own borrows the one its `art` names.
function ItemArt.blockTemplate(itemId: string): Model?
	local found = asset("Blocks", itemId)
	if found and found:IsA("Model") then
		return found
	end
	local item = Inventory.find(itemId)
	local borrowed = if item and item.art then asset("Blocks", item.art) else nil
	if borrowed and borrowed:IsA("Model") then
		return borrowed
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

local function toolPart(parent: Instance, name: string, size: Vector3, at: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.Massless = true
	part.Parent = parent
	return part
end

-- A plain Hoe, until Assets.Tools has one: a wooden shaft (the Handle, pointing ahead of the
-- hand along its Y) with a blade hanging from its tip.
local function buildHoe(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Hoe"
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, -1.2, 0)
	local length = 3.6
	local handle = toolPart(tool, "Handle", Vector3.new(0.22, length, 0.22), CFrame.new(), WOOD_COLOR)
	local blade =
		toolPart(tool, "Blade", Vector3.new(0.9, 0.14, 0.7), CFrame.new(0, length / 2 - 0.07, -0.3), BLADE_COLOR)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = blade
	return tool
end

local builtTools: { [string]: Tool } = {}

-- A tool item's Tool: its own in Assets.Tools, or a plain built one for a tool whose art is
-- still to come.
function ItemArt.toolTemplate(itemId: string): Tool?
	local found = asset("Tools", itemId)
	if found and found:IsA("Tool") then
		return found
	end
	if itemId == "Hoe" then
		local hoe = builtTools.Hoe or buildHoe()
		builtTools.Hoe = hoe
		return hoe
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
		local template = ItemArt.toolTemplate(itemId)
		if not template then
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
	local tint: Color3? = nil
	if not template and crop then
		template = asset("Items", crop.art)
		tint = crop.color
	elseif not template and item.art then
		template = asset("Items", item.art)
		tint = item.color
	end
	if template and template:IsA("Model") then
		local copy = template:Clone()
		if item.mutation then
			ItemArt.tint(copy, Mutations.ALL[item.mutation].color)
		elseif tint then
			ItemArt.tint(copy, tint)
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
