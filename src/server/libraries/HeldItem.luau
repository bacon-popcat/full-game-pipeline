--!strict
-- HeldItem: builds the Tool a character holds for an item. Tool items clone their
-- authored Tool from Assets.Tools; blocks and machines get a generated Tool carrying a
-- shrunken copy of the block, so whatever the hotbar has selected is visibly in hand.
--
-- Every Tool made here carries an ItemId attribute (the client reads it to decide what
-- the hand does), cannot be dropped, and has CanQuery off on every part, so a player's
-- own hand never blocks a placement next to them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)

-- Studs along the longest side of a block held in hand.
local HELD_BLOCK_SIZE = 1.3
-- Holds a block out in front of the hand rather than inside it.
local HELD_BLOCK_GRIP = CFrame.new(0, 0, -0.5)

local HeldItem = {}

local function blockTool(item: Inventory.Item, copy: Model): Tool
	local tool = Instance.new("Tool")
	tool.Name = item.name
	tool.RequiresHandle = true
	tool.Grip = HELD_BLOCK_GRIP

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.2
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	local _, size = copy:GetBoundingBox()
	copy:ScaleTo(copy:GetScale() * HELD_BLOCK_SIZE / math.max(size.X, size.Y, size.Z))
	local box = copy:GetBoundingBox()
	copy:PivotTo(handle.CFrame * box:ToObjectSpace(copy:GetPivot()))
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end
	copy.Parent = tool
	return tool
end

function HeldItem.create(itemId: string): Tool?
	local item = Inventory.getItem(itemId)
	local tool: Tool
	if item.kind == "Tool" then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local tools = if assets then assets:FindFirstChild("Tools") else nil
		local template = if tools then tools:FindFirstChild(itemId) else nil
		if not template or not template:IsA("Tool") then
			warn(`HeldItem: no Tool named "{itemId}" in ReplicatedStorage.Assets.Tools`)
			return nil
		end
		tool = template:Clone()
	else
		local art = Build.copyArt(itemId)
		if not art then
			return nil
		end
		tool = blockTool(item, art)
	end

	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	tool.CanBeDropped = false
	tool:SetAttribute("ItemId", itemId)
	return tool
end

return HeldItem
