-- BuildService: puts block items into the world and takes them back out. A client only
-- proposes -- a cell and rotation to place at, or a placed model to pick up. The item
-- always comes from the player's own held slot (never from the request), and reach and
-- overlap are re-checked against the server's world with the shared Build rules.
--
-- Placed blocks live in Workspace.Placed with ItemId, Owner (UserId), Origin and
-- Rotation attributes. Only the owner can pick a block up, and only into free space in
-- their inventory. Not persisted: placed blocks outlive their owner's session but not
-- the server's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local InventoryService = require(script.Parent.InventoryService)

-- Seconds between one player's build actions; caps how fast a client can spam remotes.
local COOLDOWN = 0.08

local BuildService = {}

local function placedFolder(): Folder
	local existing = workspace:FindFirstChild("Placed")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Placed"
	folder.Parent = workspace
	return folder
end

local placed = placedFolder()
local overlapParams = Build.newOverlapParams()
local lastAction: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function ready(player: Player): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < COOLDOWN then
		return false
	end
	lastAction[player] = now
	return true
end

local function onPlace(player: Player, origin: unknown, rotation: unknown)
	if typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return
	end
	if not Build.isCell(origin) or not Build.isRotation(rotation) or not ready(player) then
		return
	end
	local itemId = InventoryService.getHeldItemId(player)
	if not itemId or not Inventory.isPlaceable(Inventory.getItem(itemId)) then
		return
	end
	local template = Build.getTemplate(itemId)
	local footprint = Build.footprint(itemId, rotation)
	local pivot = Build.pivotFor(itemId, origin, rotation)
	local root = rootOf(player)
	if not template or not footprint or not pivot or not root then
		return
	end
	if not Build.inReach(root.Position, origin, footprint) or not Build.isFree(origin, footprint, overlapParams) then
		return
	end
	if not InventoryService.consumeHeld(player, itemId) then
		return
	end

	local model = template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model:PivotTo(pivot)
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("Origin", origin)
	model:SetAttribute("Rotation", rotation)
	model.Parent = placed
end

local function onPickUp(player: Player, model: unknown)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model.Parent ~= placed or not ready(player) then
		return
	end
	local held = InventoryService.getHeldItemId(player)
	if not held or not Inventory.getItem(held).picksUp or model:GetAttribute("Owner") ~= player.UserId then
		return
	end
	local itemId = model:GetAttribute("ItemId")
	local origin = model:GetAttribute("Origin")
	local rotation = model:GetAttribute("Rotation")
	if typeof(itemId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return
	end
	local footprint = Build.footprint(itemId, rotation)
	local root = rootOf(player)
	if not footprint or not root or not Build.inReach(root.Position, origin, footprint) then
		return
	end
	if not InventoryService.canGive(player, itemId, 1) then
		return
	end
	model:Destroy()
	InventoryService.give(player, itemId, 1)
end

function BuildService.init()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlace)
	Remotes.PickUpBlock.OnServerEvent:Connect(onPickUp)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return BuildService
