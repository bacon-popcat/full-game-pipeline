-- BuildController: what the held item does in the world. InventoryService puts a Tool in
-- the character's hand with an ItemId attribute, and this module acts on it:
--   * a placeable shows a grid-snapped ghost -- green when the shared Build rules say the
--     server will accept it, red when not -- and asks to place it on activation;
--   * a tool that picks up outlines the player's own placed block under the aim and asks
--     to pick it up on activation;
--   * a Tool item swings on activation.
-- The server re-checks everything; nothing here is trusted.
--
-- Aim follows the mouse, the last touch in the world, or the screen centre on a gamepad.
-- Everything bound for a held item lives in `heldTrove` and is cleaned the moment the
-- hand changes, so a swap can never leave a ghost or a rotate binding behind.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Controls = require(Players.LocalPlayer.PlayerScripts.Libraries.Controls)

type Target = { origin: Vector3, valid: boolean }

local ROTATE_ACTION = "RotateBlock"
-- Studs the aim ray reaches from the camera.
local AIM_DISTANCE = 150
-- How far a ghost's parts fade from their own transparency toward invisible.
local GHOST_FADE = 0.45
local VALID_COLOR = Color3.fromRGB(90, 230, 120)
local INVALID_COLOR = Color3.fromRGB(255, 80, 90)
local PICK_UP_COLOR = Color3.fromRGB(255, 255, 255)
-- Studs the outline stands proud of the cells it marks.
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
local target: Target? = nil
local hovered: Model? = nil
-- Last touch on the world (not on UI), in GUI space; touch aim has no live cursor.
local lastTouch: Vector2? = nil

-- One footprint outline, shared by the ghost and the pick-up target: an invisible box
-- wrapped in a SelectionBox. Not a Highlight -- those skip translucent parts, so they
-- can't draw on a ghost, and one with no Adornee lights up its whole parent instead.
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

local function showOutline(origin: Vector3, footprint: Vector3, color: Color3)
	-- Sized just outside the cells: Build.box shrinks inward for overlap tests, which
	-- would bury the lines inside an opaque block being picked up.
	local centre = Build.box(origin, footprint)
	outline.CFrame = centre
	outline.Size = footprint * Build.GRID + Vector3.one * OUTLINE_MARGIN
	outlineBox.Color3 = color
	outlineBox.SurfaceColor3 = color
	outline.Parent = workspace.CurrentCamera
end

local function hideOutline()
	outline.Parent = nil
end

local function aim(): RaycastResult?
	local camera = workspace.CurrentCamera
	local ray
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Gamepad then
		local centre = camera.ViewportSize / 2
		ray = camera:ViewportPointToRay(centre.X, centre.Y)
	elseif preferred == Enum.PreferredInput.Touch then
		if not lastTouch then
			return nil
		end
		ray = camera:ScreenPointToRay(lastTouch.X, lastTouch.Y)
	else
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	end
	return workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, raycastParams)
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function placedModelOf(part: Instance): Model?
	local placed = workspace:FindFirstChild("Placed")
	local node: Instance? = part
	while node and placed and node.Parent ~= placed do
		node = node.Parent
	end
	return if node and node:IsA("Model") then node else nil
end

local function updatePlacement(item: Inventory.Item, model: Model)
	local result = aim()
	local footprint = Build.footprint(item.id, rotation)
	local from = rootPosition()
	local cell = if result and footprint then Build.cellAt(result.Position, result.Normal) else nil
	local origin = if result and footprint and cell then Build.originFor(cell, result.Normal, footprint) else nil
	local pivot = if origin then Build.pivotFor(item.id, origin, rotation) else nil
	if not footprint or not from or not origin or not pivot then
		target = nil
		model.Parent = nil
		hideOutline()
		return
	end
	local valid = Build.inReach(from, origin, footprint) and Build.isFree(origin, footprint, overlapParams)
	target = { origin = origin, valid = valid }
	model:PivotTo(pivot)
	model.Parent = workspace.CurrentCamera
	showOutline(origin, footprint, if valid then VALID_COLOR else INVALID_COLOR)
end

local function updatePickUp()
	local result = aim()
	local model = if result then placedModelOf(result.Instance) else nil
	local origin = if model then model:GetAttribute("Origin") else nil
	local turns = if model then model:GetAttribute("Rotation") else nil
	local itemId = if model then model:GetAttribute("ItemId") else nil
	local from = rootPosition()
	hovered = nil
	if
		model
		and from
		and model:GetAttribute("Owner") == player.UserId
		and typeof(origin) == "Vector3"
		and typeof(turns) == "number"
		and typeof(itemId) == "string"
	then
		local footprint = Build.footprint(itemId, turns)
		if footprint and Build.inReach(from, origin, footprint) then
			hovered = model
			showOutline(origin, footprint, PICK_UP_COLOR)
		end
	end
	if not hovered then
		hideOutline()
	end
end

local function update()
	local item = heldItem
	if not item then
		return
	end
	if ghost and Inventory.isPlaceable(item) then
		updatePlacement(item, ghost)
	elseif item.picksUp then
		updatePickUp()
	end
end

local function swing(tool: Tool)
	-- The default Animate script plays its tool slash when it finds this value.
	local animation = Instance.new("StringValue")
	animation.Name = "toolanim"
	animation.Value = "Slash"
	animation.Parent = tool
end

local function onActivated()
	local tool = heldTool
	local item = heldItem
	if not tool or not item then
		return
	end
	if item.kind == "Tool" then
		swing(tool)
	end
	update() -- aim at where the press happened, not where the last frame was
	local placing = target
	if Inventory.isPlaceable(item) and placing and placing.valid then
		Remotes.PlaceBlock:FireServer(placing.origin, rotation)
	elseif item.picksUp and hovered then
		Remotes.PickUpBlock:FireServer(hovered)
	end
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
	target = nil
	hovered = nil
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
	if Inventory.isPlaceable(item) or item.picksUp then
		heldTrove:Connect(RunService.RenderStepped, update)
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

function BuildController.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch and not processed then
			lastTouch = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

return BuildController
