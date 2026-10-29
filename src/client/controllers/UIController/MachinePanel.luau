-- MachinePanel: the popup for the machine or router (Factory.hasControls) the player aims
-- at, opened with the interact key (Controls.INTERACT; an on-screen Open button on touch).
-- It shows what the block is doing -- worded by BlockText, from the attributes
-- FactoryService publishes -- and turns its buttons and item cells into Interact requests:
-- load an item from anywhere in the inventory, collect the output, take back what is
-- loaded and unused, switch a split conveyor, pick a filter's items. A chest (`stores`)
-- shows what it holds in the grid instead, one cell a slot, and a press takes that item out. The server checks
-- every request; the panel never changes anything itself.
--
-- The window is authored in StarterGui.HUD.MachinePanel (place file only) from the same
-- pieces as the backpack, and takes the backpack's place on screen, so only one of them
-- is ever open. Item cells clone Assets.UI.Inventory.Slot and rows clone
-- Assets.UI.BlockInfo.Row, so they look like the backpack's slots and the hover panel's
-- rows.
--
-- It closes on the interact key, the close button or gamepad B, and on its own when the
-- block is picked up or the player walks out of reach.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Build = require(ReplicatedStorage.Shared.Build)
local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Aim = require(Libraries.Aim)
local BlockText = require(Libraries.BlockText)
local Controls = require(Libraries.Controls)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local UI = require(Libraries.UI)
local InventoryScreen = require(script.Parent.InventoryScreen)

type Cell = {
	button: TextButton,
	icon: ViewportFrame,
	count: TextLabel,
	bars: { Frame },
	itemId: string?,
	amount: number,
}

-- One item the grid offers: an item in the inventory, and how many of it there are.
type Offer = { itemId: string, count: number }

local INTERACT_ACTION = "MachinePanelInteract"
local TOUCH_ACTION = "MachinePanelOpen"
local BACK_ACTION = "MachinePanelBack"
-- Studs the interact key looks; the block must also be within Build.REACH.
local AIM_DISTANCE = 150
-- Seconds between checks of what is aimed at (for the touch button) and of reach.
local CHECK_EVERY = 0.2
local OPEN_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.94
-- Below this width the two halves stack instead of sitting side by side.
local COMPACT_WIDTH = 560
local BUTTONS = { "Collect", "TakeBack", "Switch", "ClearFilter" }

local MachinePanel = {}

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
local trove = Trove.new()
-- Connections that last while one block's panel is open.
local openTrove = trove:Extend()
local cells: { Cell } = {}
local rows: { Frame } = {}
local model: Model? = nil
local blockItemId: string? = nil
local openTween: Tween? = nil
-- The grid cell under the pointer or focus, whose item the hint names.
local hovered: Cell? = nil
local touchShown = false
local priorSelection: GuiObject? = nil
-- Whether each block id takes anything by hand at all, so a pure producer shows no grid.
local takesAnything: { [string]: boolean } = {}

-- Every authored node this screen touches, found once by `bind`.
local ui = nil
-- Resting looks captured from the authored instances by `bind`.
local look = nil

local function bracketBars(root: Instance): { Frame }
	local bars = {}
	for _, bar in root:GetDescendants() do
		if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
			table.insert(bars, bar)
		end
	end
	return bars
end

local function findNode(root: Instance, path: string): Instance?
	local node: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		node = if node then node:FindFirstChild(name) else nil
	end
	if not node then
		warn(`MachinePanel: {root:GetFullName()}.{path} is missing`)
	end
	return node
end

local function bind(hud: ScreenGui): boolean
	local nodes = { hud = hud }
	local paths = {
		window = "MachinePanel",
		windowScale = "MachinePanel.UIScale",
		title = "MachinePanel.Header.Title",
		close = "MachinePanel.Header.Close",
		info = "MachinePanel.Body.Info",
		status = "MachinePanel.Body.Info.Content.Status",
		progress = "MachinePanel.Body.Info.Content.Progress",
		fill = "MachinePanel.Body.Info.Content.Progress.Fill",
		rows = "MachinePanel.Body.Info.Content.Rows",
		actions = "MachinePanel.Body.Info.Actions",
		load = "MachinePanel.Body.Load",
		heading = "MachinePanel.Body.Load.Heading",
		hint = "MachinePanel.Body.Load.Hint",
		grid = "MachinePanel.Body.Load.Grid",
		empty = "MachinePanel.Body.Load.Empty",
		backpack = "Backpack",
		blockInfo = "BlockInfo",
	}
	for key, path in paths do
		local node = findNode(hud, path)
		if not node then
			return false
		end
		nodes[key] = node
	end
	for _, name in BUTTONS do
		local node = findNode(nodes.actions, name)
		if not node then
			return false
		end
		nodes[name] = node
	end
	for key, path in
		{
			slotTemplate = "Assets.UI.Inventory.Slot",
			selectionImage = "Assets.UI.Inventory.SelectionImage",
			rowTemplate = "Assets.UI.BlockInfo.Row",
		}
	do
		local node = findNode(ReplicatedStorage, path)
		if not node then
			return false
		end
		nodes[key] = node
	end
	ui = nodes

	local slot = nodes.slotTemplate
	local firstButton = nodes[BUTTONS[1]]
	local slotBars = bracketBars(slot)
	look = {
		bracket = if slotBars[1] then slotBars[1].BackgroundColor3 else Color3.new(1, 1, 1),
		windowScale = nodes.windowScale.Scale,
		working = nodes.blockInfo:GetAttribute("SuccessColor") or nodes.status.TextColor3,
		idle = nodes.blockInfo:GetAttribute("WarningColor") or nodes.status.TextColor3,
		infoSize = nodes.info.Size,
		loadPosition = nodes.load.Position,
		loadSize = nodes.load.Size,
		heading = nodes.heading.Text,
		hint = nodes.hint.Text,
		empty = nodes.empty.Text,
		takeBack = nodes.TakeBack.Text,
		slotColor = slot.BackgroundColor3,
		slotTransparency = slot.BackgroundTransparency,
		slotSelectedColor = slot:GetAttribute("SelectedBackgroundColor") or slot.BackgroundColor3,
		slotSelectedTransparency = slot:GetAttribute("SelectedBackgroundTransparency") or slot.BackgroundTransparency,
		bracketSelected = slot:GetAttribute("SelectedBracketColor") or Color3.new(1, 1, 1),
		buttonTransparency = firstButton.BackgroundTransparency,
		buttonDisabled = firstButton:GetAttribute("DisabledTransparency") or 0.65,
	}
	return true
end

local function rootPosition(): Vector3?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- The same reach the server checks requests against.
local function inReach(target: Model): boolean
	local from = rootPosition()
	local itemId = target:GetAttribute("ItemId")
	local origin = target:GetAttribute("Origin")
	local rotation = target:GetAttribute("Rotation")
	if not from or typeof(itemId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return false
	end
	local footprint = Build.footprint(itemId, rotation)
	return footprint ~= nil and Build.canEdit(player, origin, footprint) and Build.inReach(from, origin, footprint)
end

-- The placed block with controls under the aim and within reach, and its item id.
local function aimed(): (Model?, string?)
	local character = player.Character
	raycastParams.FilterDescendantsInstances = if character then { character } else {}
	-- The art, as the hover panel aims, so the key opens what the hover panel names.
	local result = Aim.castArt(raycastParams, AIM_DISTANCE)
	local target = if result then Aim.modelUnder(result.Instance, "Placed") else nil
	local itemId = if target then target:GetAttribute("ItemId") else nil
	if target and typeof(itemId) == "string" and Factory.hasControls(itemId) and inReach(target) then
		return target, itemId
	end
	return nil, nil
end

local function send(action: string, itemId: string?)
	if model then
		Remotes.Interact:FireServer(model, action, itemId)
	end
end

local function takesAnythingByHand(itemId: string): boolean
	local cached = takesAnything[itemId]
	if cached == nil then
		cached = false
		for _, item in Inventory.ITEMS do
			if Factory.takesByHand(itemId, item.id) then
				cached = true
				break
			end
		end
		takesAnything[itemId] = cached
	end
	return cached
end

-- What the inventory holds, one entry per item in slot order, filtered by `keep`.
local function offers(keep: (string) -> boolean): { Offer }
	local list: { Offer } = {}
	local byItem: { [string]: Offer } = {}
	for index = 1, Inventory.SLOT_COUNT do
		local stack = InventoryClient.getSlot(index)
		if stack and keep(stack.itemId) then
			local offer = byItem[stack.itemId]
			if offer then
				offer.count += stack.count
			else
				offer = { itemId = stack.itemId, count = stack.count }
				byItem[stack.itemId] = offer
				table.insert(list, offer)
			end
		end
	end
	return list
end

local function setButton(button: TextButton, shown: boolean, enabled: boolean)
	button.Visible = shown
	button.Active = enabled
	button.BackgroundTransparency = if enabled then look.buttonTransparency else look.buttonDisabled
	button.TextTransparency = if enabled then 0 else 0.5
end

local function setRows(wanted: { BlockText.Row })
	for index, row in wanted do
		local frame = rows[index]
		if not frame then
			local clone = ui.rowTemplate:Clone()
			clone.LayoutOrder = index
			clone.Parent = ui.rows
			frame = clone
			rows[index] = clone
		end
		local key = frame:FindFirstChild("Key")
		local value = frame:FindFirstChild("Value")
		if key and key:IsA("TextLabel") and value and value:IsA("TextLabel") then
			key.Text = row.key
			value.Text = row.value
		end
		frame.Visible = true
	end
	for index = #wanted + 1, #rows do
		rows[index].Visible = false
	end
end

local function paintCell(cell: Cell, offer: Offer?, selected: boolean)
	cell.itemId = if offer then offer.itemId else nil
	cell.amount = if offer then offer.count else 0
	cell.button.Visible = offer ~= nil
	if not offer then
		return
	end
	cell.button.BackgroundColor3 = if selected then look.slotSelectedColor else look.slotColor
	cell.button.BackgroundTransparency = if selected then look.slotSelectedTransparency else look.slotTransparency
	for _, bar in cell.bars do
		bar.BackgroundColor3 = if selected then look.bracketSelected else look.bracket
	end
	ItemIcon.show(cell.icon, offer.itemId)
	cell.count.Visible = offer.count > 1
	cell.count.Text = tostring(offer.count)
end

local function isFilter(): boolean
	local def = if blockItemId then Factory.get(blockItemId) else nil
	return def ~= nil and def.route == "Filter"
end

local function isChest(): boolean
	local def = if blockItemId then Factory.get(blockItemId) else nil
	return def ~= nil and def.stores ~= nil
end

-- The grid's hint names the item under the pointer or focus, and says what a press does.
local function showHint(cell: Cell?)
	hovered = cell
	if not ui or not model then
		return
	end
	local itemId = if cell then cell.itemId else nil
	if not itemId then
		ui.hint.Text = if isFilter()
			then "Click items to send them left (up to 4)."
			elseif isChest() then "Click an item to take it out."
			else look.hint
	elseif isFilter() then
		ui.hint.Text = `{BlockText.itemName(itemId)}: click to send it left, or not.`
	elseif isChest() then
		ui.hint.Text = `{BlockText.itemName(itemId)} ({cell and cell.amount or 0}): click to take it all out.`
	else
		ui.hint.Text = `{BlockText.itemName(itemId)} ({cell and cell.amount or 0}): click to put in as many as fit.`
	end
end

local function createCell(): Cell
	local button = ui.slotTemplate:Clone()
	local key = button:FindFirstChild("Key")
	if key and key:IsA("GuiObject") then
		key.Visible = false
	end
	button.SelectionImageObject = ui.selectionImage
	local cell: Cell = {
		button = button,
		icon = button.Icon,
		count = button.Count,
		bars = bracketBars(button.Brackets),
		itemId = nil,
		amount = 0,
	}
	trove:Add(button)
	trove:Add(UI.bindButton(button, {
		hoverScale = 1.06,
		onActivate = function()
			local itemId = cell.itemId
			if itemId then
				send(if isFilter() then "Filter" elseif isChest() then "TakeOut" else "Load", itemId)
			end
		end,
	}))
	trove:Connect(button.MouseEnter, function()
		showHint(cell)
	end)
	trove:Connect(button.SelectionGained, function()
		showHint(cell)
	end)
	trove:Connect(button.MouseLeave, function()
		showHint(nil)
	end)
	button.LayoutOrder = #cells + 1
	button.Parent = ui.grid
	table.insert(cells, cell)
	return cell
end

-- A chest's contents as its slots fill: each item split into stacks, in name order.
local function chestSlots(target: Model): { Offer }
	local list: { Offer } = {}
	local counts = BlockText.contents(target)
	local ids = {}
	for id in counts do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return BlockText.itemName(a) < BlockText.itemName(b)
	end)
	for _, id in ids do
		local ok, item = pcall(Inventory.getItem, id)
		local stack = if ok then item.stack else counts[id]
		local left = counts[id]
		while left > 0 do
			table.insert(list, { itemId = id, count = math.min(left, stack) })
			left -= stack
		end
	end
	return list
end

local function renderGrid(def: Factory.Def, itemId: string)
	if def.stores and model then
		local list = chestSlots(model)
		for index, offer in list do
			paintCell(cells[index] or createCell(), offer, false)
		end
		for index = #list + 1, #cells do
			paintCell(cells[index], nil, false)
		end
		ui.empty.Visible = #list == 0
		return
	end
	local filtered = if def.route == "Filter" and model then BlockText.filter(model) else {}
	local list = offers(function(candidate)
		return def.route == "Filter" or Factory.takesByHand(itemId, candidate)
	end)
	for index, offer in list do
		paintCell(cells[index] or createCell(), offer, filtered[offer.itemId] == true)
	end
	for index = #list + 1, #cells do
		paintCell(cells[index], nil, false)
	end
	ui.empty.Visible = #list == 0
end

-- Side by side when there is room; stacked on narrow screens. Without a grid, the status
-- half takes the whole window.
local function layout()
	local width = ui.window.AbsoluteSize.X / ui.windowScale.Scale
	local compact = width > 0 and width < COMPACT_WIDTH
	if not ui.load.Visible then
		ui.info.Size = UDim2.fromScale(1, 1)
	elseif compact then
		ui.info.Size = UDim2.new(1, 0, 0.5, -6)
		ui.load.Position = UDim2.new(0, 0, 0.5, 6)
		ui.load.Size = UDim2.new(1, 0, 0.5, -6)
	else
		ui.info.Size = look.infoSize
		ui.load.Position = look.loadPosition
		ui.load.Size = look.loadSize
	end
end

local function render()
	local target, itemId = model, blockItemId
	if not ui or not target or not itemId then
		return
	end
	local def = Factory.get(itemId)
	if not def then
		return
	end
	local isMachine = def.kind == "Machine"
	ui.title.Text = BlockText.itemName(itemId)

	local status, working = BlockText.status(target, def)
	ui.status.Visible = status ~= nil
	ui.status.Text = status or ""
	ui.status.TextColor3 = if working then look.working else look.idle
	local progress = target:GetAttribute("Progress")
	ui.progress.Visible = isMachine and (def.recipes ~= nil or def.produce ~= nil)
	ui.fill.Size = UDim2.fromScale(if typeof(progress) == "number" then math.clamp(progress, 0, 1) else 0, 1)
	setRows(BlockText.rows(target, def, false))

	local powered = target:GetAttribute("Powered") == true
	setButton(ui.Collect, isMachine, BlockText.hasOutput(target))
	setButton(ui.TakeBack, isMachine, BlockText.hasContents(target))
	ui.TakeBack.Text = if def.stores then "Take all" else look.takeBack
	setButton(ui.Switch, def.route == "Split", true)
	ui.Switch.Text = if powered then "Send straight on" else "Send to the side"
	setButton(ui.ClearFilter, def.route == "Filter", next(BlockText.filter(target)) ~= nil)
	ui.actions.Visible = isMachine or def.route ~= nil

	local showsGrid = def.route == "Filter" or def.stores ~= nil or (isMachine and takesAnythingByHand(itemId))
	ui.load.Visible = showsGrid
	ui.heading.Text = if def.route == "Filter" then "[ Filter ]" elseif def.stores then "[ Chest ]" else look.heading
	ui.empty.Text = if def.route == "Filter"
		then "Your backpack is empty."
		elseif def.stores then "Nothing collected yet."
		else look.empty
	if showsGrid then
		renderGrid(def, itemId)
	end
	-- The hovered cell may now hold a different count, or nothing.
	local current = hovered
	showHint(if current and current.itemId then current else nil)
	layout()
end

-- First thing a gamepad lands on: an enabled button, else the first item.
local function focusPanel()
	task.spawn(function()
		RunService.RenderStepped:Wait() -- a selection must be rendered before it can be selected
		if not ui or not model or UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad then
			return
		end
		for _, name in BUTTONS do
			local button = ui[name]
			if button.Visible and button.Active then
				GuiService.SelectedObject = button
				return
			end
		end
		local first = cells[1]
		if first and first.button.Visible then
			GuiService.SelectedObject = first.button
		end
	end)
end

-- Sits where the backpack sits; InventoryScreen keeps that clear of the hotbar.
local function matchBackpack()
	ui.window.Position = ui.backpack.Position
	ui.window.Size = ui.backpack.Size
end

local function onBack(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	MachinePanel.close()
	return Enum.ContextActionResult.Sink
end

function MachinePanel.isOpen(): boolean
	return model ~= nil
end

function MachinePanel.open(target: Model, itemId: string)
	if not ui then
		return
	end
	if model then
		MachinePanel.close()
	end
	InventoryScreen.close()
	model = target
	blockItemId = itemId
	local current = GuiService.SelectedObject
	priorSelection = if current and not current:IsDescendantOf(ui.window) then current else nil

	openTrove:Connect(target.AttributeChanged, render)
	openTrove:Connect(target.AncestryChanged, function()
		if not target:IsDescendantOf(workspace) then
			MachinePanel.close()
		end
	end)
	openTrove:Connect(InventoryClient.changed, render)
	openTrove:Connect(ui.backpack:GetPropertyChangedSignal("Visible"), function()
		if ui.backpack.Visible then
			MachinePanel.close()
		end
	end)
	ContextActionService:BindActionAtPriority(
		BACK_ACTION,
		onBack,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(Controls.BACK)
	)
	openTrove:Add(function()
		ContextActionService:UnbindAction(BACK_ACTION)
	end)

	matchBackpack()
	ui.window.Visible = true
	render()
	showHint(nil)
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
	focusPanel()
end

function MachinePanel.close()
	if not ui or not model then
		return
	end
	model = nil
	blockItemId = nil
	hovered = nil
	openTrove:Clean()
	if openTween then
		openTween:Cancel()
		openTween = nil
	end
	local current = GuiService.SelectedObject
	if current and current:IsDescendantOf(ui.window) then
		local prior = priorSelection
		GuiService.SelectedObject = if prior and prior.Parent and prior.Visible then prior else nil
	end
	priorSelection = nil
	ui.windowScale.Scale = look.windowScale
	ui.window.Visible = false
end

local function toggle()
	if model then
		MachinePanel.close()
		return
	end
	local target, itemId = aimed()
	if target and itemId then
		MachinePanel.open(target, itemId)
	end
end

local function onInteract(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not model and not aimed() then
		return Enum.ContextActionResult.Pass
	end
	toggle()
	return Enum.ContextActionResult.Sink
end

-- Touch has no interact key: an Open button shows while a block with controls is aimed at.
local function showTouchButton(shown: boolean)
	if shown == touchShown then
		return
	end
	touchShown = shown
	if shown then
		ContextActionService:BindAction(TOUCH_ACTION, onInteract, true)
		ContextActionService:SetTitle(TOUCH_ACTION, "Open")
	else
		ContextActionService:UnbindAction(TOUCH_ACTION)
	end
end

function MachinePanel.init(hud: ScreenGui)
	if not bind(hud) then
		return
	end
	trove:Add(UI.bindButton(ui.close, { hoverScale = 1.15, onActivate = MachinePanel.close }))
	ui.close.SelectionImageObject = ui.selectionImage
	for _, name in BUTTONS do
		local button = ui[name]
		button.SelectionImageObject = ui.selectionImage
		trove:Add(UI.bindButton(button, {
			hoverScale = 1.04,
			onActivate = function()
				if button.Active then
					send(name)
				end
			end,
		}))
	end
	trove:Connect(ui.window:GetPropertyChangedSignal("AbsoluteSize"), function()
		if model then
			layout()
		end
	end)
	trove:Connect(ui.backpack:GetPropertyChangedSignal("Position"), matchBackpack)
	trove:Connect(ui.backpack:GetPropertyChangedSignal("Size"), matchBackpack)

	ContextActionService:BindAction(INTERACT_ACTION, onInteract, false, table.unpack(Controls.INTERACT))
	trove:Add(function()
		ContextActionService:UnbindAction(INTERACT_ACTION)
		ContextActionService:UnbindAction(TOUCH_ACTION)
		ContextActionService:UnbindAction(BACK_ACTION)
	end)

	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt)
		elapsed += dt
		if elapsed < CHECK_EVERY then
			return
		end
		elapsed = 0
		local target = model
		if target and not inReach(target) then
			MachinePanel.close()
		end
		local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		showTouchButton(touch and model == nil and aimed() ~= nil)
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
		table.clear(cells)
		table.clear(rows)
	end)
end

return MachinePanel
