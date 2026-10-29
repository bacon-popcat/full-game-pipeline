-- InventoryScreen: the hotbar (always on screen), the backpack window, and the side
-- button that opens it. Renders InventoryClient into slot cells cloned from
-- Assets.UI.Inventory.Slot and turns input into intents: choosing which hotbar slot to
-- hold, and moving stacks between any two slots.
--
-- Moving is one gesture on every device: press a slot to lift its stack, press another
-- to put it down (merging or swapping). A mouse or finger can also drag: releasing over
-- a different slot puts the stack down; releasing where it started keeps it lifted for
-- a second press. While the backpack is closed, pressing a hotbar slot holds it instead,
-- so the hotbar never moves stacks by accident.
--
-- The window, hotbar strip and drag ghost are authored in StarterGui.HUD (place file
-- only). Resting looks are captured from those instances; selected and lifted looks are
-- attributes on the Slot template.
--
-- Invariants:
--   * `view` plus InventoryClient is the only input to `render`.
--   * One cell per slot, created once at init and only repainted after.
--   * Layout reads sizes divided by the window's UIScale, so the open animation never
--     reflows the grid mid-tween.

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Controls = require(Libraries.Controls)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local UI = require(Libraries.UI)
local Screens = require(Libraries.Screens)

type Cell = {
	button: TextButton,
	icon: ViewportFrame,
	count: TextLabel,
	bars: { Frame },
}

type View = {
	open: boolean,
	-- Slot whose stack is lifted and waiting to be put down.
	held: number?,
	-- Whether the lift came from a pointer press that is still down.
	dragging: boolean,
	-- Slot the sidebar describes: last hovered or focused.
	inspected: number?,
}

local TOGGLE_ACTION = "ToggleBackpack"
local BACK_ACTION = "BackpackBack"
local HOTBAR_ACTION = "HotbarSelect"
local OPEN_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.94
local NAME_HOLD_SECONDS = 1.5
local NAME_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
-- Hotbar slots shrink toward this on narrow screens before the strip would overflow.
local MIN_HOTBAR_SLOT = 42
-- Pixels of screen kept clear either side of the hotbar.
local HOTBAR_EDGE = 12
-- Below this width or height the backpack drops its sidebar and is all grid.
local COMPACT_WIDTH = 560
local COMPACT_HEIGHT = 360
local MIN_CELL = 50
local MIN_COLUMNS = 5
local MAX_COLUMNS = 9

local InventoryScreen = {}

local view: View = { open = false, held = nil, dragging = false, inspected = nil }
local trove = Trove.new()
local cells: { [number]: Cell } = {}
-- Latest pointer position in GUI space (the space AbsolutePosition uses).
local pointer = Vector2.zero
local lastSelectedItem: string? = nil
local nameThread: thread? = nil
local nameTweens: { Tween } = {}
local openTween: Tween? = nil
local priorSelection: GuiObject? = nil

-- Every authored node this screen touches, found once by `bind`. Nil if the HUD is
-- missing a piece, which turns the public API into no-ops.
local ui = nil
-- Resting looks captured from the authored instances by `captureLook`.
local look = nil

local function findNode(root: Instance, path: string): Instance?
	local node: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		node = if node then node:FindFirstChild(name) else nil
	end
	if not node then
		warn(`InventoryScreen: {root:GetFullName()}.{path} is missing`)
	end
	return node
end

local function bind(hud: ScreenGui): boolean
	local templates = findNode(ReplicatedStorage, "Assets.UI.Inventory")
	if not templates then
		return false
	end
	local nodes = { hud = hud }
	local hudPaths = {
		opener = "SideButtons.Backpack",
		hotbar = "Hotbar",
		hotbarLayout = "Hotbar.UIListLayout",
		itemName = "ItemName",
		ghost = "DragGhost",
		ghostIcon = "DragGhost.Icon",
		ghostCount = "DragGhost.Count",
		window = "Backpack",
		windowScale = "Backpack.UIScale",
		close = "Backpack.Header.Close",
		sidebar = "Backpack.Body.Sidebar",
		main = "Backpack.Body.Main",
		previewIcon = "Backpack.Body.Sidebar.Preview.Icon",
		previewName = "Backpack.Body.Sidebar.Preview.ItemName",
		previewKind = "Backpack.Body.Sidebar.Preview.Kind",
		amount = "Backpack.Body.Sidebar.Information.Rows.Amount.Value",
		footprint = "Backpack.Body.Sidebar.Information.Rows.Footprint.Value",
		description = "Backpack.Body.Sidebar.Information.Rows.Description",
		hint = "Backpack.Body.Sidebar.Controls.Hint",
		grid = "Backpack.Body.Main.GridPanel.Grid",
		gridLayout = "Backpack.Body.Main.GridPanel.Grid.UIGridLayout",
		gridPadding = "Backpack.Body.Main.GridPanel.Grid.UIPadding",
	}
	for key, path in hudPaths do
		local node = findNode(hud, path)
		if not node then
			return false
		end
		nodes[key] = node
	end
	for key, name in { slotTemplate = "Slot", selectionImage = "SelectionImage" } do
		local node = findNode(templates, name)
		if not node then
			return false
		end
		nodes[key] = node
	end
	-- createCell dot-indexes these on every clone, so prove the template has them once.
	for _, path in { "Icon", "Count", "Key", "Brackets", "UIScale" } do
		if not findNode(nodes.slotTemplate, path) then
			return false
		end
	end
	ui = nodes
	return true
end

local function bracketBars(root: Instance): { Frame }
	local bars = {}
	for _, bar in root:GetDescendants() do
		if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
			table.insert(bars, bar)
		end
	end
	return bars
end

local function captureLook()
	local slot = ui.slotTemplate
	local bars = bracketBars(slot.Brackets)
	local hotbarHeight = slot.Size.Y.Offset - ui.hotbar.Position.Y.Offset
	local nameStroke = ui.itemName:FindFirstChildOfClass("UIStroke")
	look = {
		slotSize = slot.Size.X.Offset,
		slotColor = slot.BackgroundColor3,
		slotTransparency = slot.BackgroundTransparency,
		slotSelectedColor = slot:GetAttribute("SelectedBackgroundColor") or slot.BackgroundColor3,
		slotSelectedTransparency = slot:GetAttribute("SelectedBackgroundTransparency") or slot.BackgroundTransparency,
		bracket = if bars[1] then bars[1].BackgroundColor3 else Color3.new(1, 1, 1),
		bracketSelected = slot:GetAttribute("SelectedBracketColor") or Color3.new(1, 1, 1),
		iconTransparency = slot.Icon.ImageTransparency,
		iconLifted = slot:GetAttribute("HeldIconTransparency") or slot.Icon.ImageTransparency,
		hotbarMargin = -ui.hotbar.Position.Y.Offset,
		hotbarGap = ui.hotbarLayout.Padding.Offset,
		-- Gaps between the hotbar's top edge and what sits above it, as authored.
		nameGap = -ui.itemName.Position.Y.Offset - hotbarHeight,
		windowGap = -ui.window.Position.Y.Offset - hotbarHeight,
		windowTopGap = ui.window.Position.Y.Offset - ui.window.Size.Y.Offset,
		windowWidth = ui.window.Size.X,
		nameStroke = nameStroke,
		nameStrokeTransparency = if nameStroke then nameStroke.Transparency else 0,
		windowScale = ui.windowScale.Scale,
		mainPosition = ui.main.Position,
		mainSize = ui.main.Size,
		previewNone = ui.previewName.Text,
	}
end

local function hideName()
	for _, tween in nameTweens do
		tween:Cancel()
	end
	table.clear(nameTweens)
	if nameThread then
		task.cancel(nameThread)
		nameThread = nil
	end
	ui.itemName.TextTransparency = 1
	if look.nameStroke then
		look.nameStroke.Transparency = 1
	end
end

-- Shows the held item's name above the hotbar, then fades it.
local function flashName(text: string)
	hideName()
	ui.itemName.Text = text
	ui.itemName.TextTransparency = 0
	if look.nameStroke then
		look.nameStroke.Transparency = look.nameStrokeTransparency
	end
	nameThread = task.delay(NAME_HOLD_SECONDS, function()
		nameThread = nil
		if GuiService.ReducedMotionEnabled then
			hideName()
			return
		end
		table.insert(nameTweens, TweenService:Create(ui.itemName, NAME_FADE, { TextTransparency = 1 }))
		if look.nameStroke then
			table.insert(nameTweens, TweenService:Create(look.nameStroke, NAME_FADE, { Transparency = 1 }))
		end
		for _, tween in nameTweens do
			tween:Play()
		end
	end)
end

local function paintCell(cell: Cell, stack: Inventory.Stack?, selected: boolean, lifted: boolean)
	local button = cell.button
	button.BackgroundColor3 = if selected then look.slotSelectedColor else look.slotColor
	button.BackgroundTransparency = if selected then look.slotSelectedTransparency else look.slotTransparency
	for _, bar in cell.bars do
		bar.BackgroundColor3 = if selected then look.bracketSelected else look.bracket
	end
	cell.icon.ImageTransparency = if lifted then look.iconLifted else look.iconTransparency
	ItemIcon.show(cell.icon, if stack then stack.itemId else nil)
	cell.count.Visible = stack ~= nil and stack.count > 1
	cell.count.Text = if stack then tostring(stack.count) else ""
end

local function paintInspector(index: number?)
	local stack = if index then InventoryClient.getSlot(index) else nil
	if not stack then
		ItemIcon.show(ui.previewIcon, nil)
		ui.previewName.Text = look.previewNone
		ui.previewKind.Text = ""
		ui.amount.Text = "-"
		ui.footprint.Text = "-"
		ui.description.Text = ""
		return
	end
	local item = Inventory.getItem(stack.itemId)
	ItemIcon.show(ui.previewIcon, item.id)
	ui.previewName.Text = item.name
	ui.previewKind.Text = item.kind
	ui.amount.Text = `{stack.count} / {item.stack}`
	local footprint = if Inventory.isPlaceable(item) then Build.footprint(item.id, 0) else nil
	ui.footprint.Text = if footprint then `{footprint.X} x {footprint.Z} x {footprint.Y}` else "-"
	ui.description.Text = item.description or ""
end

local function usesPointer(): boolean
	return UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad
end

local function render()
	if view.held and not InventoryClient.getSlot(view.held) then
		-- A snapshot emptied the lifted slot (e.g. the server rejected a move).
		view.held = nil
		view.dragging = false
	end
	local selected = InventoryClient.getSelected()
	for index, cell in cells do
		paintCell(cell, InventoryClient.getSlot(index), index == selected, index == view.held)
	end

	local lifted = if view.held then InventoryClient.getSlot(view.held) else nil
	ui.ghost.Visible = lifted ~= nil and usesPointer()
	ItemIcon.show(ui.ghostIcon, if lifted then lifted.itemId else nil)
	ui.ghostCount.Text = if lifted and lifted.count > 1 then tostring(lifted.count) else ""

	local inHand = if selected > 0 then InventoryClient.getSlot(selected) else nil
	paintInspector(view.held or view.inspected or (if inHand then selected else nil))

	local inHandItem = if inHand then inHand.itemId else nil
	if inHandItem ~= lastSelectedItem then
		lastSelectedItem = inHandItem
		if inHandItem then
			flashName(Inventory.getItem(inHandItem).name)
		else
			hideName()
		end
	end
end

local function selectHotbar(index: number)
	InventoryClient.select(if InventoryClient.getSelected() == index then 0 else index)
end

local function stepHotbar(step: number)
	local current = InventoryClient.getSelected()
	local nextIndex = if current == 0
		then (if step > 0 then 1 else Inventory.HOTBAR_SIZE)
		else (current - 1 + step) % Inventory.HOTBAR_SIZE + 1
	InventoryClient.select(nextIndex)
end

local function pressSlot(index: number)
	local held = view.held
	if held then
		view.held = nil
		if held ~= index then
			InventoryClient.move(held, index)
		end
	elseif InventoryClient.getSlot(index) then
		view.held = index
	end
	view.inspected = index
	render()
end

local function cancelLift()
	view.held = nil
	view.dragging = false
	render()
end

local function slotAt(point: Vector2): number?
	for index, cell in cells do
		local button = cell.button
		if button.Visible and (index <= Inventory.HOTBAR_SIZE or view.open) then
			local min = button.AbsolutePosition
			local max = min + button.AbsoluteSize
			if point.X >= min.X and point.X <= max.X and point.Y >= min.Y and point.Y <= max.Y then
				return index
			end
		end
	end
	return nil
end

local function isPointerPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function createCell(index: number, parent: GuiObject)
	local button = ui.slotTemplate:Clone()
	local isHotbar = index <= Inventory.HOTBAR_SIZE
	button.Name = if isHotbar then `Hotbar{index}` else `Backpack{index - Inventory.HOTBAR_SIZE}`
	button.LayoutOrder = index
	button.SelectionImageObject = ui.selectionImage
	button.Key.Visible = isHotbar
	button.Key.Text = tostring(index)
	cells[index] = { button = button, icon = button.Icon, count = button.Count, bars = bracketBars(button.Brackets) }

	trove:Add(button)
	trove:Add(UI.bindButton(button, {
		hoverScale = 1.06,
		onActivate = function(input)
			if not view.open then
				if isHotbar then
					selectHotbar(index)
				end
			elseif not isPointerPress(input) then
				-- Pointer presses were handled on InputBegan, so drags work.
				pressSlot(index)
			end
		end,
	}))
	trove:Connect(button.InputBegan, function(input: InputObject)
		if view.open and isPointerPress(input) and input.UserInputState == Enum.UserInputState.Begin then
			pressSlot(index)
			view.dragging = view.held ~= nil
		end
	end)
	local function inspect()
		if view.open and view.inspected ~= index then
			view.inspected = index
			render()
		end
	end
	trove:Connect(button.MouseEnter, inspect)
	trove:Connect(button.SelectionGained, inspect)
	button.Parent = parent
end

local function layoutHotbar()
	local width = ui.hud.AbsoluteSize.X
	local gap = look.hotbarGap
	local fit = math.floor((width - HOTBAR_EDGE * 2 - gap * (Inventory.HOTBAR_SIZE - 1)) / Inventory.HOTBAR_SIZE)
	local size = math.clamp(fit, MIN_HOTBAR_SLOT, look.slotSize)
	for index = 1, Inventory.HOTBAR_SIZE do
		cells[index].button.Size = UDim2.fromOffset(size, size)
	end
	-- The name and the backpack keep their authored gaps above the hotbar's top edge.
	local top = look.hotbarMargin + size
	ui.itemName.Position = UDim2.new(0.5, 0, 1, -(top + look.nameGap))
	ui.window.Position = UDim2.new(0.5, 0, 1, -(top + look.windowGap))
	ui.window.Size = UDim2.new(look.windowWidth, UDim.new(1, -(top + look.windowGap + look.windowTopGap)))
end

local function applyComposition()
	local size = ui.window.AbsoluteSize / ui.windowScale.Scale
	if size.X <= 0 then
		return
	end
	local compact = size.X < COMPACT_WIDTH or size.Y < COMPACT_HEIGHT
	ui.sidebar.Visible = not compact
	ui.main.Position = if compact then UDim2.new() else look.mainPosition
	ui.main.Size = if compact then UDim2.fromScale(1, 1) else look.mainSize
end

local function layoutGrid()
	local padding = ui.gridPadding.PaddingLeft.Offset + ui.gridPadding.PaddingRight.Offset
	local gap = ui.gridLayout.CellPadding.X.Offset
	local usable = ui.grid.AbsoluteSize.X / ui.windowScale.Scale - padding - ui.grid.ScrollBarThickness
	if usable <= 0 then
		return
	end
	local columns = math.clamp(math.floor((usable + gap) / (MIN_CELL + gap)), MIN_COLUMNS, MAX_COLUMNS)
	local cell = math.floor((usable - gap * (columns - 1)) / columns)
	ui.gridLayout.CellSize = UDim2.fromOffset(cell, cell)
end

local function focusBackpack()
	task.spawn(function()
		RunService.RenderStepped:Wait() -- a selection must be rendered before it can be selected
		if view.open and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			local current = GuiService.SelectedObject
			if not current or not current:IsDescendantOf(ui.hud) then
				GuiService.SelectedObject = cells[Inventory.HOTBAR_SIZE + 1].button
			end
		end
	end)
end

local function onBackAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if view.held then
		cancelLift()
	else
		InventoryScreen.close()
	end
	return Enum.ContextActionResult.Sink
end

local function onToggleAction(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if view.open then
		InventoryScreen.close()
	else
		InventoryScreen.open()
	end
	return Enum.ContextActionResult.Sink
end

local function onHotbarAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local index = table.find(Controls.HOTBAR_SLOTS, input.KeyCode)
	if index then
		selectHotbar(index)
	elseif table.find(Controls.HOTBAR_PREVIOUS, input.KeyCode) then
		stepHotbar(-1)
	elseif table.find(Controls.HOTBAR_NEXT, input.KeyCode) then
		stepHotbar(1)
	else
		return Enum.ContextActionResult.Pass
	end
	return Enum.ContextActionResult.Sink
end

local function paintInputHints()
	ui.hint.Text = Controls.hint(UserInputService.PreferredInput)
	local keyHint = ui.opener:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.Text = Controls.TOGGLE_BACKPACK[1].Name
		keyHint.Visible = UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
	end
end

function InventoryScreen.open()
	if not ui or view.open then
		return
	end
	Screens.claim("Backpack")
	view.open = true
	local current = GuiService.SelectedObject
	priorSelection = if current and not current:IsDescendantOf(ui.window) then current else nil

	render()
	ui.window.Visible = true
	if openTween then
		openTween:Cancel()
		openTween = nil
	end
	if GuiService.ReducedMotionEnabled then
		ui.windowScale.Scale = look.windowScale
	else
		ui.windowScale.Scale = look.windowScale * OPEN_FROM_SCALE
		local tween = TweenService:Create(ui.windowScale, OPEN_TWEEN, { Scale = look.windowScale })
		tween:Play()
		openTween = tween
	end
	ContextActionService:BindActionAtPriority(
		BACK_ACTION,
		onBackAction,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(Controls.BACK)
	)
	focusBackpack()
end

function InventoryScreen.close()
	if not ui or not view.open then
		return
	end
	view.open = false
	view.held = nil
	view.dragging = false
	if openTween then
		openTween:Cancel()
		openTween = nil
	end
	ContextActionService:UnbindAction(BACK_ACTION)

	local current = GuiService.SelectedObject
	if current and current:IsDescendantOf(ui.window) then
		local prior = priorSelection
		GuiService.SelectedObject = if prior and prior.Parent and prior.Visible then prior else nil
	end
	priorSelection = nil
	ui.windowScale.Scale = look.windowScale
	ui.window.Visible = false
	render()
end

function InventoryScreen.init(hud: ScreenGui)
	Screens.register("Backpack", InventoryScreen.close)
	if not bind(hud) then
		return
	end
	captureLook()
	-- This screen replaces Roblox's backpack and its 1-9 keys.
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	-- Item icons are mostly MeshParts; fetch them now so the first backpack open isn't
	-- a grid of blanks while they download.
	local blocks = findNode(ReplicatedStorage, "Assets.Blocks")
	if blocks then
		task.spawn(ContentProvider.PreloadAsync, ContentProvider, { blocks })
	end

	for index = 1, Inventory.SLOT_COUNT do
		createCell(index, if index <= Inventory.HOTBAR_SIZE then ui.hotbar else ui.grid)
	end
	for _, node in { ui.opener, ui.close } do
		node.SelectionImageObject = ui.selectionImage
	end
	trove:Add(UI.bindButton(ui.opener, {
		hoverScale = 1.08,
		onActivate = function()
			if view.open then
				InventoryScreen.close()
			else
				InventoryScreen.open()
			end
		end,
	}))
	trove:Add(UI.bindButton(ui.close, { hoverScale = 1.15, onActivate = InventoryScreen.close }))

	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if isPointerPress(input) then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and view.held then
			cancelLift()
		end
	end)
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if not view.dragging or not isPointerPress(input) then
			return
		end
		view.dragging = false
		local target = slotAt(Vector2.new(input.Position.X, input.Position.Y))
		if target and target ~= view.held then
			pressSlot(target)
		end
	end)
	trove:Connect(RunService.RenderStepped, function()
		if ui.ghost.Visible then
			local origin = ui.hud.AbsolutePosition
			ui.ghost.Position = UDim2.fromOffset(pointer.X - origin.X, pointer.Y - origin.Y)
		end
	end)

	trove:Connect(InventoryClient.changed, render)
	trove:Connect(hud:GetPropertyChangedSignal("AbsoluteSize"), layoutHotbar)
	trove:Connect(ui.window:GetPropertyChangedSignal("AbsoluteSize"), applyComposition)
	trove:Connect(ui.grid:GetPropertyChangedSignal("AbsoluteSize"), layoutGrid)
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), function()
		paintInputHints()
		render()
	end)

	ContextActionService:BindAction(TOGGLE_ACTION, onToggleAction, false, table.unpack(Controls.TOGGLE_BACKPACK))
	local hotbarKeys = table.clone(Controls.HOTBAR_SLOTS)
	table.move(Controls.HOTBAR_PREVIOUS, 1, #Controls.HOTBAR_PREVIOUS, #hotbarKeys + 1, hotbarKeys)
	table.move(Controls.HOTBAR_NEXT, 1, #Controls.HOTBAR_NEXT, #hotbarKeys + 1, hotbarKeys)
	ContextActionService:BindAction(HOTBAR_ACTION, onHotbarAction, false, table.unpack(hotbarKeys))
	trove:Add(function()
		ContextActionService:UnbindAction(TOGGLE_ACTION)
		ContextActionService:UnbindAction(HOTBAR_ACTION)
		ContextActionService:UnbindAction(BACK_ACTION)
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
		table.clear(cells)
	end)

	paintInputHints()
	layoutHotbar()
	applyComposition()
	layoutGrid()
	render()
end

return InventoryScreen
