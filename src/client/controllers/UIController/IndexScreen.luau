-- IndexScreen: the Index window, opened from the Menu popup (Screens.open "Index"). Every plain item in the
-- catalogue has a cell (mutated variants show on their plain item's page); the ones the
-- player has had (Remotes.IndexSync, from GardenService) draw their art, the rest are dark
-- silhouettes named "???".
--
-- Three areas, left to right: the item list (Body.Main.GridPanel.Grid, cells cloned from
-- Assets.UI.Inventory.Slot), the showcase (Body.Showcase: the picked item large on a
-- Turntable, its name and kind) and the facts (Body.Sidebar.Information, ItemDetails' rows).
-- Pressing or focusing a cell picks it; the first cell is picked until then. All of it is
-- authored in StarterGui.HUD.Index (place file only). Screens owns window exclusivity.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Controls = require(Libraries.Controls)
local Hud = require(Libraries.Hud)
local ItemDetails = require(Libraries.ItemDetails)
local ItemIcon = require(Libraries.ItemIcon)
local PopupMotion = require(Libraries.PopupMotion)
local Screens = require(Libraries.Screens)
local Turntable = require(Libraries.Turntable)
local UI = require(Libraries.UI)

local BACK_ACTION = "IndexBack"
local UNKNOWN = "???"
local MIN_CELL = 50
local MIN_COLUMNS = 4
local MAX_COLUMNS = 9

type Cell = { item: Inventory.Item, button: TextButton, icon: ViewportFrame, bars: { Frame } }

local IndexScreen = {}

function IndexScreen.init(hud: ScreenGui)
	local window = Hud.find(hud, "Index", "Frame")
	local scale = Hud.find(hud, "Index.UIScale", "UIScale")
	local opener = Hud.find(hud, "SideButtons.Index", "TextButton")
	local closeButton = Hud.find(hud, "Index.Header.Close", "TextButton")
	local subtitle = Hud.find(hud, "Index.Header.Subtitle", "TextLabel")
	local view = Hud.find(hud, "Index.Body.Showcase.View", "ViewportFrame")
	local itemName = Hud.find(hud, "Index.Body.Showcase.ItemName", "TextLabel")
	local itemKind = Hud.find(hud, "Index.Body.Showcase.Kind", "TextLabel")
	local rows = Hud.find(hud, "Index.Body.Sidebar.Information.Rows", "Frame")
	local description = Hud.find(hud, "Index.Body.Sidebar.Information.Rows.Description", "TextLabel")
	local grid = Hud.find(hud, "Index.Body.Main.GridPanel.Grid", "ScrollingFrame")
	local gridLayout = Hud.find(hud, "Index.Body.Main.GridPanel.Grid.UIGridLayout", "UIGridLayout")
	local gridPadding = Hud.find(hud, "Index.Body.Main.GridPanel.Grid.UIPadding", "UIPadding")
	local slotTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Inventory.Slot", "TextButton")
	local rowTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Inventory.InfoRow", "Frame")
	local selectionImage = Hud.find(ReplicatedStorage, "Assets.UI.Inventory.SelectionImage", "GuiObject")
	if
		not window
		or not scale
		or not closeButton
		or not subtitle
		or not view
		or not itemName
		or not itemKind
		or not rows
		or not description
		or not grid
		or not gridLayout
		or not gridPadding
		or not slotTemplate
		or not rowTemplate
		or not selectionImage
	then
		return
	end
	assert(window:IsA("GuiObject") and scale:IsA("UIScale"))
	assert(closeButton:IsA("GuiButton") and subtitle:IsA("TextLabel") and view:IsA("ViewportFrame"))
	assert(itemName:IsA("TextLabel") and itemKind:IsA("TextLabel") and rows:IsA("Frame"))
	assert(description:IsA("TextLabel") and grid:IsA("ScrollingFrame") and gridLayout:IsA("UIGridLayout"))
	assert(gridPadding:IsA("UIPadding") and slotTemplate:IsA("TextButton") and rowTemplate:IsA("Frame"))
	assert(selectionImage:IsA("GuiObject"))

	local trove = Trove.new()
	local animateWindow, cleanup = PopupMotion.bind(window, true)
	trove:Add(cleanup)
	local turntable = Turntable.bind(view)
	trove:Add(turntable.destroy)
	local opened = false
	local prior: GuiObject? = nil
	local had: { [string]: boolean } = {}
	local cells: { Cell } = {}
	local picked: Cell? = nil
	-- Resting and picked looks, captured from the Slot template (the hotbar's selected look).
	local iconColor = (slotTemplate:FindFirstChild("Icon") :: ViewportFrame).ImageColor3
	local slotColor, slotTransparency = slotTemplate.BackgroundColor3, slotTemplate.BackgroundTransparency
	local pickedColor = slotTemplate:GetAttribute("SelectedBackgroundColor") or slotColor
	local pickedTransparency = slotTemplate:GetAttribute("SelectedBackgroundTransparency") or slotTransparency
	local pickedBracket = slotTemplate:GetAttribute("SelectedBracketColor") or Color3.new(1, 1, 1)
	local bracketColor = Color3.new(1, 1, 1)

	local function bracketBars(root: Instance): { Frame }
		local bars = {}
		for _, bar in root:GetDescendants() do
			if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
				table.insert(bars, bar)
			end
		end
		return bars
	end
	local templateBars = bracketBars(slotTemplate)
	if templateBars[1] then
		bracketColor = templateBars[1].BackgroundColor3
	end

	-- Whether the player has had the plain item or any of its mutated variants.
	local function found(item: Inventory.Item): boolean
		if had[item.id] then
			return true
		end
		if Inventory.hasMutations(item.id) then
			for _, key in Mutations.KEYS do
				if had[item.id .. "+" .. key] then
					return true
				end
			end
		end
		return false
	end

	local function paintPicked()
		local cell = picked
		if not cell then
			turntable.show(nil)
			itemName.Text = ""
			itemKind.Text = ""
			ItemDetails.paint(rows, rowTemplate, {})
			description.Text = ""
			return
		end
		local item = cell.item
		turntable.show(item.id)
		itemKind.Text = item.kind
		if not found(item) then
			view.ImageColor3 = Color3.new()
			itemName.Text = UNKNOWN
			ItemDetails.paint(rows, rowTemplate, {})
			description.Text = "Get one to learn about it."
			return
		end
		view.ImageColor3 = iconColor
		itemName.Text = item.name
		local details = ItemDetails.rows(item)
		local variants = {}
		if Inventory.hasMutations(item.id) then
			for _, key in Mutations.KEYS do
				if had[item.id .. "+" .. key] then
					table.insert(variants, table.concat(string.split(key, "+"), " "))
				end
			end
			table.insert(details, { key = "Mutations found", value = `{#variants} / {#Mutations.KEYS}` })
		end
		ItemDetails.paint(rows, rowTemplate, details)
		local text = item.description or ""
		if #variants > 0 then
			-- Sarpanch draws a colon as one dot, so the list follows a dash.
			text ..= `\nFound - {table.concat(variants, ", ")}`
		end
		description.Text = text
	end

	local function render()
		local count = 0
		for _, cell in cells do
			local known = found(cell.item)
			local isPicked = cell == picked
			count += if known then 1 else 0
			ItemIcon.show(cell.icon, cell.item.id)
			cell.icon.ImageColor3 = if known then iconColor else Color3.new()
			cell.button.BackgroundColor3 = if isPicked then pickedColor else slotColor
			cell.button.BackgroundTransparency = if isPicked then pickedTransparency else slotTransparency
			for _, bar in cell.bars do
				bar.BackgroundColor3 = if isPicked then pickedBracket else bracketColor
			end
		end
		subtitle.Text = `Found {count} of {#cells}`
		paintPicked()
	end

	local function pick(cell: Cell)
		if picked ~= cell then
			picked = cell
			render()
		end
	end

	local function layoutGrid()
		local padding = gridPadding.PaddingLeft.Offset + gridPadding.PaddingRight.Offset
		local gap = gridLayout.CellPadding.X.Offset
		local usable = grid.AbsoluteSize.X / scale.Scale - padding - grid.ScrollBarThickness
		if usable <= 0 then
			return
		end
		local columns = math.clamp(math.floor((usable + gap) / (MIN_CELL + gap)), MIN_COLUMNS, MAX_COLUMNS)
		local size = math.floor((usable - gap * (columns - 1)) / columns)
		gridLayout.CellSize = UDim2.fromOffset(size, size)
	end

	for order, item in Inventory.ITEMS do
		if item.base then
			continue
		end
		local button = slotTemplate:Clone()
		button.Name = item.id
		button.LayoutOrder = order
		button.SelectionImageObject = selectionImage
		for _, name in { "Key", "Count" } do
			local label = button:FindFirstChild(name)
			if label and label:IsA("GuiObject") then
				label.Visible = false
			end
		end
		local cell: Cell = {
			item = item,
			button = button,
			icon = button:FindFirstChild("Icon") :: ViewportFrame,
			bars = bracketBars(button),
		}
		table.insert(cells, cell)
		trove:Add(button)
		trove:Add(UI.bindButton(button, {
			hoverScale = 1.06,
			onActivate = function()
				pick(cell)
			end,
		}))
		trove:Connect(button.SelectionGained, function()
			pick(cell)
		end)
		button.Parent = grid
	end
	picked = cells[1]

	local function close()
		if not opened then
			return
		end
		opened = false
		animateWindow(false)
		-- Nothing turns while the window is shut; opening shows the picked item afresh.
		turntable.show(nil)
		ContextActionService:UnbindAction(BACK_ACTION)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(window) then
			GuiService.SelectedObject = if prior and prior.Parent and prior.Visible then prior else nil
		end
		prior = nil
	end

	local function open()
		Screens.claim("Index")
		local current = GuiService.SelectedObject
		prior = if current and not current:IsDescendantOf(window) then current else nil
		opened = true
		render()
		animateWindow(true)
		ContextActionService:BindActionAtPriority(BACK_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(Controls.BACK))
		task.spawn(function()
			RunService.RenderStepped:Wait() -- a selection must be rendered before it can be selected
			if opened and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad and cells[1] then
				GuiService.SelectedObject = cells[1].button
			end
		end)
	end

	Screens.register("Index", close, open)
	closeButton.SelectionImageObject = selectionImage
	-- The Menu popup opens the Index by name; an old side button, if the place file still has one, works too.
	if opener and opener:IsA("GuiButton") then
		opener.SelectionImageObject = selectionImage
		trove:Add(UI.bindButton(opener, {
			hoverScale = 1.08,
			onActivate = function()
				if opened then
					close()
				else
					open()
				end
			end,
		}))
	end
	trove:Add(UI.bindButton(closeButton, { hoverScale = 1.15, onActivate = close }))
	trove:Connect(Remotes.IndexSync.OnClientEvent, function(itemIds: { string })
		table.clear(had)
		for _, itemId in itemIds do
			had[itemId] = true
		end
		if opened then
			render()
		end
	end)
	trove:Connect(grid:GetPropertyChangedSignal("AbsoluteSize"), layoutGrid)
	trove:Connect(hud.Destroying, function()
		close()
		trove:Destroy()
	end)
	window.Visible = false
	layoutGrid()
	render()
end

return IndexScreen
