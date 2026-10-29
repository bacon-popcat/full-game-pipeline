-- BuildController: what the hand does in the world. InventoryService puts a Tool in the
-- character's hand with an ItemId attribute; every frame this module works out what a
-- press would do where the player aims, and outlines it:
--   * a placeable shows a grid-snapped ghost -- green when the shared Build rules say the
--     server will accept it, red when not -- and asks to place it;
--   * any item aimed at a filter conveyor toggles it in the filter. Machines are only
--     worked through their panel (UIController/MachinePanel), so a press never feeds or
--     empties one;
--   * the Hammer picks up the player's own placed block; a Pickaxe breaks their own
--     cubes it fits and mines the world nodes it fits;
--   * a resource aimed at a conveyor is dropped onto it (DropService puts it on the belt);
--   * an empty hand takes from a conveyor (its belt items) or switches a router, or harvests a crop (a ripe one for its produce, a growing one for its seed);
--   * a seed's ghost is only green over soil (Shared/World/Soil).
-- The drop key drops one of whatever is held: onto the conveyor aimed at, or in front.
-- The server re-checks everything; nothing here is trusted.
--
-- Aim comes from the Aim library, which this module also feeds touches. Everything bound
-- for a held item lives in `heldTrove` and is cleaned the moment the hand changes, so a
-- swap can never leave a ghost or a rotate binding behind.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Build = require(ReplicatedStorage.Shared.Build)
local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Soil = require(ReplicatedStorage.Shared.World.Soil)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Aim = require(Players.LocalPlayer.PlayerScripts.Libraries.Aim)
local Controls = require(Players.LocalPlayer.PlayerScripts.Libraries.Controls)

-- `against`: the axis the aimed surface faces, so the server knows which block it went
-- against.
type Placement = { origin: Vector3, valid: boolean, against: Vector3 }
type Action = { kind: "Place" | "PickUp" | "Use" | "Take" | "Drop", model: Model? }

local ROTATE_ACTION = "RotateBlock"
local DROP_ACTION = "DropItem"
-- Studs the aim ray reaches from the camera.
local AIM_DISTANCE = 150
-- How far a ghost's parts fade from their own transparency toward invisible.
local GHOST_FADE = 0.45
local VALID_COLOR = Color3.fromRGB(90, 230, 120)
local INVALID_COLOR = Color3.fromRGB(255, 80, 90)
local PICK_UP_COLOR = Color3.fromRGB(255, 255, 255)
local USE_COLOR = Color3.fromRGB(255, 200, 60)
-- Studs the outline stands proud of the box it marks.
local OUTLINE_MARGIN = 0.15

local BuildController = {}

local player = Players.LocalPlayer
local characterTrove = Trove.new()
local heldTrove = Trove.new()
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local overlapParams = Build.newOverlapParams()

local heldTool: Tool? = nil
local heldItem: Inventory.Item? = nil
local ghost: Model? = nil
local rotation = 0
local placement: Placement? = nil
local action: Action? = nil

-- One outline, shared by the ghost and every target: an invisible box wrapped in a
-- SelectionBox. Not a Highlight -- those skip translucent parts, so they can't draw on a
-- ghost, and one with no Adornee lights up its whole parent instead.
local outline = Instance.new("Part")
outline.Name = "BuildOutline"
outline.Anchored = true
outline.CanCollide = false
outline.CanQuery = false
outline.CanTouch = false
outline.CastShadow = false
outline.Transparency = 1
local outlineBox = Instance.new("SelectionBox")
outlineBox.Adornee = outline
outlineBox.LineThickness = 0.06
outlineBox.SurfaceTransparency = 0.85
outlineBox.Parent = outline

local function showOutline(cframe: CFrame, size: Vector3, color: Color3)
	-- Sized just outside the box: Build.box shrinks inward for overlap tests, which would
	-- bury the lines inside an opaque block.
	outline.CFrame = cframe
	outline.Size = size + Vector3.one * OUTLINE_MARGIN
	outlineBox.Color3 = color
	outlineBox.SurfaceColor3 = color
	outline.Parent = workspace.CurrentCamera
end

local function hideOutline()
	outline.Parent = nil
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function inReach(model: Model): boolean
	local from = rootPosition()
	local hitbox = model.PrimaryPart
	if not from or not hitbox then
		return false
	end
	local offset = hitbox.CFrame:PointToObjectSpace(from)
	local half = hitbox.Size / 2
	local nearest = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return (offset - nearest).Magnitude <= Build.REACH
end

local function placedItemId(model: Model): string?
	local itemId = model:GetAttribute("ItemId")
	return if typeof(itemId) == "string" then itemId else nil
end

local function nodeDef(model: Model): World.Node?
	local nodeType = model:GetAttribute("NodeType")
	return if typeof(nodeType) == "string" then World.NODES[nodeType] else nil
end

-- Conveyors and routers: a click with a resource drops it on. A machine's input end takes
-- drops too, but only from the drop key.
local function hasLanes(itemId: string?): boolean
	local def = if itemId then Factory.get(itemId) else nil
	return def ~= nil and def.lanes ~= nil
end

-- Machines answer only their panel, never a press of the hand.
local function isMachine(itemId: string?): boolean
	local def = if itemId then Factory.get(itemId) else nil
	return def ~= nil and def.kind == "Machine"
end

local function isOwn(model: Model): boolean
	local origin = model:GetAttribute("Origin")
	return model:GetAttribute("Owner") == player.UserId
		and typeof(origin) == "Vector3"
		and Build.canEdit(player, origin, Vector3.one)
end

local function choosePlacement(item: Inventory.Item, model: Model, result: RaycastResult?): Action?
	local footprint = Build.footprint(item.id, rotation)
	local from = rootPosition()
	local cell = if result and footprint then Build.cellAt(result.Position, result.Normal) else nil
	local origin = if result and footprint and cell then Build.originFor(cell, result.Normal, footprint) else nil
	local pivot = if origin then Build.pivotFor(item.id, origin, rotation) else nil
	if not result or not footprint or not from or not origin or not pivot then
		return nil
	end
	local valid = Build.inReach(from, origin, footprint)
		and Build.canEdit(player, origin, footprint)
		and Build.isFree(origin, footprint, overlapParams)
		and not Build.clipsCharacter(item.id, pivot)
		and Soil.canPlant(item.id, origin)
	local normal = result.Normal
	local axis = math.max(math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z))
	local against = if math.abs(normal.Y) == axis
		then Vector3.new(0, math.sign(normal.Y), 0)
		elseif math.abs(normal.X) == axis then Vector3.new(math.sign(normal.X), 0, 0)
		else Vector3.new(0, 0, math.sign(normal.Z))
	placement = { origin = origin, valid = valid, against = against }
	model:PivotTo(pivot)
	model.Parent = workspace.CurrentCamera
	local centre = Build.box(origin, footprint)
	showOutline(centre, footprint * Build.GRID, if valid then VALID_COLOR else INVALID_COLOR)
	return { kind = "Place", model = nil }
end

-- What a press would do right now, given the hand and the aim.
local function decide(): Action?
	local result = Aim.cast(raycastParams, AIM_DISTANCE)
	local placed = if result then Aim.modelUnder(result.Instance, "Placed") else nil
	local node = if result then Aim.modelUnder(result.Instance, "World") else nil
	local placedId = if placed then placedItemId(placed) else nil
	local item = heldItem
	if placed and (not inReach(placed) or not isOwn(placed)) then
		placed, placedId = nil, nil
	end
	if node and not inReach(node) then
		node = nil
	end
	if node then
		local def = nodeDef(node)
		local cell = node:GetAttribute("Cell")
		if def and def.crop and (typeof(cell) ~= "Vector3" or not Build.canEdit(player, cell, Vector3.one)) then
			node = nil
		end
	end

	if not item then
		if placed and placedId and Factory.get(placedId) and not isMachine(placedId) then
			return { kind = "Take", model = placed }
		end
		local def = if node then nodeDef(node) else nil
		if node and def and def.harvest then
			return { kind = "Take", model = node }
		end
		return nil
	end
	if placed and placedId and not isMachine(placedId) and Factory.takesByHand(placedId, item.id) then
		return { kind = "Use", model = placed }
	end
	if item.kind == "Resource" and placed and hasLanes(placedId) then
		return { kind = "Drop", model = placed }
	end
	if item.picksUp then
		return if placed and isOwn(placed) then { kind = "PickUp", model = placed } else nil
	end
	if item.kind == "Tool" then
		if placed and placedId and isOwn(placed) and Inventory.getItem(placedId).breaksWith == item.id then
			return { kind = "PickUp", model = placed }
		end
		local def = if node then nodeDef(node) else nil
		if node and def and def.tool == item.id then
			return { kind = "Use", model = node }
		end
		return nil
	end
	local model = ghost
	if model and Inventory.isPlaceable(item) then
		return choosePlacement(item, model, result)
	end
	return nil
end

local function update()
	local chosen = decide()
	action = chosen
	if not chosen or chosen.kind ~= "Place" then
		placement = nil
		if ghost then
			ghost.Parent = nil
		end
	end
	local target = if chosen then chosen.model else nil
	local hitbox = if target then target.PrimaryPart else nil
	if chosen and chosen.kind ~= "Place" and hitbox then
		local useColor = chosen.kind == "Use" or chosen.kind == "Drop"
		showOutline(hitbox.CFrame, hitbox.Size, if useColor then USE_COLOR else PICK_UP_COLOR)
	elseif not chosen then
		hideOutline()
	end
end

local function swing(tool: Tool)
	-- The default Animate script plays its tool slash when it finds this value.
	local animation = Instance.new("StringValue")
	animation.Name = "toolanim"
	animation.Value = "Slash"
	animation.Parent = tool
end

-- Does what the aim and hand call for, re-aimed at where the press happened rather than
-- where the last frame was.
local function perform()
	update()
	local chosen = action
	if not chosen then
		return
	end
	local target = chosen.model
	if chosen.kind == "Place" then
		local placing = placement
		if placing and placing.valid then
			Remotes.PlaceBlock:FireServer(placing.origin, rotation, placing.against)
		end
	elseif chosen.kind == "PickUp" and target then
		Remotes.PickUpBlock:FireServer(target)
	elseif chosen.kind == "Drop" then
		Remotes.DropItem:FireServer(target)
	elseif target then
		Remotes.Interact:FireServer(target, chosen.kind)
	end
end

local function onActivated()
	local tool = heldTool
	local item = heldItem
	if tool and item and item.kind == "Tool" then
		swing(tool)
	end
	perform()
end

-- Drops one of the held item: onto the conveyor aimed at, or in front of the player.
local function onDrop(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local result = Aim.cast(raycastParams, AIM_DISTANCE)
		local placed = if result then Aim.modelUnder(result.Instance, "Placed") else nil
		local placedId = if placed then placedItemId(placed) else nil
		local onto = if placed
				and placedId
				and isOwn(placed)
				and inReach(placed)
				and Factory.hasBelt(placedId)
			then placed
			else nil
		Remotes.DropItem:FireServer(onto)
	end
	return Enum.ContextActionResult.Sink
end

local function onRotate(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		rotation = (rotation + 1) % 4
		update()
	end
	return Enum.ContextActionResult.Sink
end

local function makeGhost(itemId: string): Model?
	local template = Build.getTemplate(itemId)
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Transparency += (1 - part.Transparency) * GHOST_FADE
		end
	end
	return model
end

local function clearHeld()
	heldTrove:Clean()
	heldTool = nil
	heldItem = nil
	ghost = nil
	placement = nil
	action = nil
	hideOutline()
end

-- Re-reads the hand and rebinds everything for whatever it now holds.
local function refreshHeld(character: Model)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool == heldTool then
		return
	end
	clearHeld()

	local itemId = if tool then tool:GetAttribute("ItemId") else nil
	if not tool or typeof(itemId) ~= "string" then
		return
	end
	local item = Inventory.getItem(itemId)
	heldTool = tool
	heldItem = item
	heldTrove:Connect(tool.Activated, onActivated)
	ContextActionService:BindAction(DROP_ACTION, onDrop, true, table.unpack(Controls.DROP))
	ContextActionService:SetTitle(DROP_ACTION, "Drop")
	heldTrove:Add(function()
		ContextActionService:UnbindAction(DROP_ACTION)
	end)

	if Inventory.isPlaceable(item) then
		local model = makeGhost(itemId)
		if model then
			ghost = model
			heldTrove:Add(model)
		end
		ContextActionService:BindAction(ROTATE_ACTION, onRotate, true, table.unpack(Controls.ROTATE))
		ContextActionService:SetTitle(ROTATE_ACTION, "Rotate")
		heldTrove:Add(function()
			ContextActionService:UnbindAction(ROTATE_ACTION)
		end)
	end
end

local function bindCharacter(character: Model)
	characterTrove:Clean()
	clearHeld()
	raycastParams.FilterDescendantsInstances = { character }
	characterTrove:Connect(character.ChildAdded, function()
		refreshHeld(character)
	end)
	characterTrove:Connect(character.ChildRemoved, function()
		refreshHeld(character)
	end)
	refreshHeld(character)
end

-- A press with nothing in hand: tools report presses through Activated, so an empty hand
-- needs its own.
local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		Aim.setTouch(Vector2.new(input.Position.X, input.Position.Y))
		return
	end
	if heldTool then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		perform()
	end
end

local function onTouchTap(position: Vector2, processed: boolean)
	if not processed and not heldTool then
		Aim.setTouch(position)
		perform()
	end
end

function BuildController.init()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.TouchTapInWorld:Connect(onTouchTap)
	RunService.RenderStepped:Connect(update)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

return BuildController
