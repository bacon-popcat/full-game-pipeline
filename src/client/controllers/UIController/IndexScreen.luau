-- IndexScreen: the Index window and the side button that opens it. Every plain item in the
-- catalogue has a cell (mutated variants show on their plain item's page); the ones the
-- player has had (Remotes.IndexSync, from GardenService) draw their art and describe
-- themselves in the sidebar with ItemDetails, the rest are dark silhouettes named "???".
--
-- The window is authored in StarterGui.HUD.Index (place file only) as a sibling of the
-- Backpack with the same Header, Body.Sidebar and Body.Main.GridPanel.Grid; its cells are
-- clones of Assets.UI.Inventory.Slot. Hovering or focusing a cell describes it, pressing one
-- keeps it described. Screens owns window exclusivity.

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
local UI = require(Libraries.UI)

local BACK_ACTION = "IndexBack"
local UNKNOWN = "???"
local MIN_CELL = 50
local MIN_COLUMNS = 5
local MAX_COLUMNS = 9

type Cell = { item: Inventory.Item, button: TextButton, icon: ViewportFrame }

local IndexScreen = {}

function IndexScreen.init(hud: ScreenGui)
	local window = Hud.find(hud, "Index", "Frame")
	local scale = Hud.find(hud, "Index.UIScale", "UIScale")
	local opener = Hud.find(hud, "SideButtons.Index", "TextButton")
	local closeButton = Hud.find(hud, "Index.Header.Close", "TextButton")
	local subtitle = Hud.find(hud, "Index.Header.Subtitle", "TextLabel")
	local previewIcon = Hud.find(hud, "Index.Body.Sidebar.Preview.Icon", "ViewportFrame")
	local previewName = Hud.find(hud, "Index.Body.Sidebar.Preview.ItemName", "TextLabel")
	local previewKind = Hud.find(hud, "Index.Body.Sidebar.Preview.Kind", "TextLabel")
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
		or not opener
		or not closeButton
		or not subtitle
		or not previewIcon
		or not previewName
		or not previewKind
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
	assert(window:IsA("GuiObject") and scale:IsA("UIScale") and opener:IsA("GuiButton"))
	assert(closeButton:IsA("GuiButton") and subtitle:IsA("TextLabel") and previewIcon:IsA("ViewportFrame"))
	assert(previewName:IsA("TextLabel") and previewKind:IsA("TextLabel") and rows:IsA("Frame"))
	assert(description:IsA("TextLabel") and grid:IsA("ScrollingFrame") and gridLayout:IsA("UIGridLayout"))
	assert(gridPadding:IsA("UIPadding") and slotTemplate:IsA("TextButton") and rowTemplate:IsA("Frame"))
	assert(selectionImage:IsA("GuiObject"))

	local trove = Trove.new()
	local animateWindow, cleanup = PopupMotion.bind(window, true)
	trove:Add(cleanup)
	local opened = false
	local prior: GuiObject? = nil
	local had: { [string]: boolean } = {}
	local cells: { Cell } = {}
	-- The cell pressed last, and the one under the pointer or focus, which wins while it lasts.
	local picked: Cell? = nil
	local hovered: Cell? = nil
	local iconColor = (slotTemplate:FindFirstChild("Icon") :: ViewportFrame).ImageColor3
	local noneText = previewName.Text

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

	local function paintSidebar()
		local cell = hovered or picked
		if not cell then
			ItemIcon.show(previewIcon, nil)
			previewName.Text = noneText
			previewKind.Text = ""
			ItemDetails.paint(rows, rowTemplate, {})
			description.Text = ""
			return
		end
		local item = cell.item
		previewKind.Text = item.kind
		if not found(item) then
			ItemIcon.show(previewIcon, item.id)
			previewIcon.ImageColor3 = Color3.new()
			previewName.Text = UNKNOWN
			ItemDetails.paint(rows, rowTemplate, {})
			description.Text = "Get one to learn about it."
			return
		end
		ItemIcon.show(previewIcon, item.id)
		previewIcon.ImageColor3 = iconColor
		previewName.Text = item.name
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
			text ..= `\nFound: {table.concat(variants, ", ")}`
		end
		description.Text = text
	end

	local function render()
		local count = 0
		for _, cell in cells do
			local known = found(cell.item)
			count += if known then 1 else 0
			ItemIcon.show(cell.icon, cell.item.id)
			cell.icon.ImageColor3 = if known then iconColor else Color3.new()
		end
		subtitle.Text = `Found {count} of {#cells}`
		paintSidebar()
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
		local cell: Cell = { item = item, button = button, icon = button:FindFirstChild("Icon") :: ViewportFrame }
		table.insert(cells, cell)
		trove:Add(button)
		trove:Add(UI.bindButton(button, {
			hoverScale = 1.06,
			onActivate = function()
				picked = cell
				paintSidebar()
			end,
		}))
		local function enter()
			hovered = cell
			paintSidebar()
		end
		local function leave()
			if hovered == cell then
				hovered = nil
				paintSidebar()
			end
		end
		trove:Connect(button.MouseEnter, enter)
		trove:Connect(button.SelectionGained, enter)
		trove:Connect(button.MouseLeave, leave)
		trove:Connect(button.SelectionLost, leave)
		button.Parent = grid
	end

	local function close()
		if not opened then
			return
		end
		opened = false
		hovered = nil
		animateWindow(false)
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

	Screens.register("Index", close)
	opener.SelectionImageObject = selectionImage
	closeButton.SelectionImageObject = selectionImage
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
