-- BuildService: puts block items into the world and takes them back out. A client only
-- proposes -- a cell and rotation to place at, or a placed model to pick up. The item
-- always comes from the player's own held slot (never from the request), and reach and
-- overlap are re-checked against the server's world with the shared Build rules.
--
-- Whole footprints must belong to the player's plot. Seeds go directly to WorldService;
-- blocks carry ItemId, Owner, Origin, Rotation and Against attributes. Profile restoration
-- uses the same placement and synchronous factory registration path without consuming items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Factory = require(ReplicatedStorage.Shared.Factory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Plot = require(ReplicatedStorage.Shared.Plot)
local World = require(ReplicatedStorage.Shared.World)
local WorldService = require(script.Parent.WorldService)
local Soil = require(ReplicatedStorage.Shared.World.Soil)
local GardenEvents = require(game:GetService("ServerScriptService").Libraries.GardenEvents)
local FactoryService = require(script.Parent.FactoryService)
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

-- Trusted server entry point shared by interactive placement and profile restoration.
-- The caller validates reach/overlap for an intent; restore validates saved content first.
function BuildService.place(
	player: Player,
	itemId: string,
	origin: Vector3,
	rotation: number,
	against: Vector3?
): Model?
	local template = Build.getTemplate(itemId)
	local footprint = Build.footprint(itemId, rotation)
	local pivot = Build.pivotFor(itemId, origin, rotation)
	if not template or not footprint or not pivot or not Build.owns(player, origin, footprint) then
		return nil
	end
	if World.PLANTS[itemId] then
		WorldService.plant(origin, itemId)
		return nil
	end
	local model = template:Clone()
	-- Named for the item, not the template it may borrow (Items `art`).
	model.Name = itemId
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
	model:SetAttribute("Against", against)
	model.Parent = placed
	if Factory.get(itemId) and not FactoryService.register(model) then
		model:Destroy()
		return nil
	end
	return model
end

local function onPlace(player: Player, origin: unknown, rotation: unknown, against: unknown)
	if typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return
	end
	-- Only a unit axis counts; anything else just means it went against nothing in particular.
	local side = if typeof(against) == "Vector3"
			and Build.isCell(against)
			and against.Magnitude == 1
		then against
		else nil
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
	if
		not Build.canEdit(player, origin, footprint)
		or not Build.inReach(root.Position, origin, footprint)
		or not Build.isFree(origin, footprint, overlapParams, itemId, rotation)
	then
		return
	end
	if Build.clipsCharacter(itemId, pivot) or not Soil.canPlant(itemId, origin) then
		return
	end
	if Factory.get(itemId) and (not Factory.originFrame(template) or not Factory.extents(itemId)) then
		return
	end
	if not InventoryService.consumeHeld(player, itemId) then
		return
	end

	if World.PLANTS[itemId] then
		if WorldService.plant(origin, itemId) then
			GardenEvents.Planted:Fire(player, origin, itemId)
		else
			InventoryService.give(player, itemId, 1)
		end
		return
	end
	local model = BuildService.place(player, itemId, origin, rotation, side)
	if model then
		GardenEvents.Placed:Fire(player, itemId, model)
	else
		InventoryService.give(player, itemId, 1)
	end
end

local function onPickUp(player: Player, model: unknown)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or model.Parent ~= placed or not ready(player) then
		return
	end
	local held = InventoryService.getHeldItemId(player)
	if not held or model:GetAttribute("Owner") ~= player.UserId then
		return
	end
	local itemId = model:GetAttribute("ItemId")
	local origin = model:GetAttribute("Origin")
	local rotation = model:GetAttribute("Rotation")
	if typeof(itemId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return
	end
	if not Inventory.getItem(held).picksUp and Inventory.getItem(itemId).breaksWith ~= held then
		return
	end
	local footprint = Build.footprint(itemId, rotation)
	local root = rootOf(player)
	if
		not footprint
		or not root
		or not Build.canEdit(player, origin, footprint)
		or not Build.inReach(root.Position, origin, footprint)
	then
		return
	end
	if not InventoryService.canGive(player, itemId, 1) then
		return
	end
	local contents = FactoryService.drain(model)
	FactoryService.unregister(model)
	model:Destroy()
	InventoryService.give(player, itemId, 1)
	for contentId, count in contents do
		InventoryService.give(player, contentId, count)
	end
end

function BuildService.snapshot(player: Player, index: number): { Plot.SavedBlock }
	local saved: { Plot.SavedBlock } = {}
	for _, model in placed:GetChildren() do
		if not model:IsA("Model") or model:GetAttribute("Owner") ~= player.UserId then
			continue
		end
		local origin = model:GetAttribute("Origin")
		local itemId = model:GetAttribute("ItemId")
		local rotation = model:GetAttribute("Rotation")
		local against = model:GetAttribute("Against")
		local footprint = if typeof(itemId) == "string" and typeof(rotation) == "number"
			then Build.footprint(itemId, rotation)
			else nil
		if
			typeof(origin) == "Vector3"
			and typeof(itemId) == "string"
			and typeof(rotation) == "number"
			and footprint
		then
			-- Saved as if in an unturned garden (Plot), so it loads the same way into either row.
			table.insert(saved, {
				itemId = itemId,
				cell = Plot.pack(Plot.blockToRelative(index, origin, footprint)),
				rotation = Plot.turn(index, rotation),
				against = if typeof(against) == "Vector3" then Plot.pack(Plot.axis(index, against)) else nil,
				contents = FactoryService.snapshot(model),
			})
		end
	end
	return saved
end

function BuildService.restore(player: Player, index: number, saved: Plot.SavedBlock): boolean
	local relative = Plot.unpack(saved.cell)
	if not relative or not Build.isRotation(saved.rotation) then
		return false
	end
	local rotation = Plot.turn(index, saved.rotation)
	local footprint = Build.footprint(saved.itemId, rotation)
	if not footprint then
		return false
	end
	local origin = Plot.blockToWorld(index, relative, footprint)
	if
		not Build.owns(player, origin, footprint)
		or not Build.isFree(origin, footprint, overlapParams, saved.itemId, rotation)
	then
		return false
	end
	local against = if saved.against then Plot.unpack(saved.against) else nil
	if against and against.Magnitude ~= 1 then
		return false
	end
	against = if against then Plot.axis(index, against) else nil
	local model = BuildService.place(player, saved.itemId, origin, rotation, against)
	if not model then
		return false
	end
	return not saved.contents or FactoryService.restore(model, saved.contents)
end

function BuildService.clear(player: Player)
	for _, model in placed:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Owner") == player.UserId then
			FactoryService.unregister(model)
			model:Destroy()
		end
	end
end

function BuildService.init()
	Remotes.PlaceBlock.OnServerEvent:Connect(onPlace)
	Remotes.PickUpBlock.OnServerEvent:Connect(onPickUp)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return BuildService
