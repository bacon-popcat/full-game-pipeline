--[[
Authors three HUD changes in StarterGui.HUD and ReplicatedStorage.Assets.UI (the place file only;
conventions.md § UI):

  * Crafting: Header.Upgrade (a gold button) and UpgradePanel, the card it opens with the next
    bench tier's requirements and an UPGRADE button (CraftingScreen.luau).
  * Shop: a left rail of tab tiles (Seeds, Gear) with the restock timer under it, and a grid of
    tall cards (Assets.UI.Shop.Row) instead of a list of strips. The Robux tab is gone.
  * Robux: its own window (HUD.Robux) and its Assets.UI.Robux.Pack card (RobuxScreen.luau). It
    opens from the Menu popup's Robux row, which sidebar_hud.luau adds.

Run it through the Studio MCP in the Edit datamodel, like progress_hud.luau: serve the repo
(python -m http.server 34998 --bind 127.0.0.1), fetch this file into a temporary ModuleScript,
require it and call the function it returns. Safe to rerun: what it makes is removed and rebuilt,
and the Shop edits check what is already done.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(16, 16, 26)
local MUTED = Color3.fromRGB(190, 190, 205)
local DIM = Color3.fromRGB(150, 150, 168)
local STROKE = Color3.fromRGB(205, 205, 220)
local GOLD = Color3.fromRGB(255, 214, 102)
local SAGE = Color3.fromRGB(157, 220, 154)

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local assets = ReplicatedStorage.Assets.UI
	local crafting = hud.Crafting
	local family = crafting.Header.Title.FontFace.Family

	local function font(weight: Enum.FontWeight): Font
		return Font.new(family, weight)
	end

	local function remove(parent: Instance, name: string)
		local old = parent:FindFirstChild(name)
		while old do
			old:Destroy()
			old = parent:FindFirstChild(name)
		end
	end

	local function new(className: string, props: { [string]: any }, parent: Instance?): any
		local node = Instance.new(className)
		for key, value in props do
			node[key] = value
		end
		node.Parent = parent
		return node
	end

	local function border(parent: Instance, color: Color3?, transparency: number?)
		return new("UIStroke", {
			Name = "Border",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = color or STROKE,
			Transparency = transparency or 0.65,
			Thickness = 1,
		}, parent)
	end

	local function label(props: { [string]: any }, parent: Instance): TextLabel
		local node = new("TextLabel", {
			Name = props.Name,
			BackgroundTransparency = 1,
			Position = props.Position or UDim2.new(),
			Size = props.Size or UDim2.fromScale(1, 1),
			AnchorPoint = props.AnchorPoint or Vector2.zero,
			FontFace = font(props.Weight or Enum.FontWeight.Bold),
			Text = props.Text or "",
			TextColor3 = props.Color or WHITE,
			TextSize = props.TextSize or 16,
			TextXAlignment = props.X or Enum.TextXAlignment.Left,
			TextYAlignment = props.Y or Enum.TextYAlignment.Center,
			TextWrapped = props.Wrapped or false,
			TextTruncate = if props.Wrapped then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
			ZIndex = props.ZIndex or 1,
		}, parent)
		new("UIStroke", { Color = BLACK, Transparency = 0.4, Thickness = 1.5 }, node)
		return node
	end

	local function brackets(parent: Instance, color: Color3, length: number, thickness: number)
		local frame = new("Frame", {
			Name = "Brackets",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		}, parent)
		for _, corner in { { "TopLeft", 0, 0 }, { "TopRight", 1, 0 }, { "BottomLeft", 0, 1 }, { "BottomRight", 1, 1 } } do
			local x, y = corner[2], corner[3]
			local holder = new("Frame", {
				Name = corner[1],
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.new(
					x,
					if x == 0 then -thickness else thickness,
					y,
					if y == 0 then -thickness else thickness
				),
				Size = UDim2.fromOffset(length, length),
				ZIndex = 2,
			}, frame)
			new("Frame", {
				Name = "Horizontal",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.new(1, 0, 0, thickness),
				ZIndex = 2,
			}, holder)
			new("Frame", {
				Name = "Vertical",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.new(0, thickness, 1, 0),
				ZIndex = 2,
			}, holder)
		end
		return frame
	end

	local function paintBars(root: Instance, color: Color3)
		for _, bar in root:GetDescendants() do
			if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
				bar.BackgroundColor3 = color
			end
		end
	end

	local function button(props: { [string]: any }, parent: Instance): TextButton
		local node = new("TextButton", {
			Name = props.Name,
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = props.Background or PANEL,
			BackgroundTransparency = props.Transparency or 0.15,
			Position = props.Position or UDim2.new(),
			Size = props.Size,
			AnchorPoint = props.AnchorPoint or Vector2.zero,
		}, parent)
		border(node, props.Stroke or STROKE, props.StrokeTransparency or 0.45)
		new("UIScale", {}, node)
		label({
			Name = "Label",
			Text = props.Text or "",
			Color = props.Color,
			TextSize = props.TextSize or 16,
			X = Enum.TextXAlignment.Center,
		}, node)
		return node
	end

	--------------------------------------------------------------------------- Robux window
	-- Built first, from the Crafting shell before it grows the upgrade pieces below.
	remove(hud, "Robux")
	local robux = crafting:Clone()
	robux.Name = "Robux"
	for _, name in { "Body", "Tooltip", "UpgradePanel" } do
		remove(robux, name)
	end
	remove(robux.Header, "Upgrade")
	robux.Visible = false
	robux.Header.Title.Text = "Robux Shop"
	robux.Header.Subtitle.Text = "Coin packs, bought with Robux"
	robux.UISizeConstraint.MaxSize = Vector2.new(880, 520)
	paintBars(robux.Brackets, GOLD)
	robux.Accent.BackgroundColor3 = GOLD
	robux.Header.Divider.BackgroundColor3 = GOLD
	for _, stroke in robux.Header.Close:GetChildren() do
		if stroke:IsA("Frame") then
			stroke.BackgroundColor3 = GOLD
		end
	end
	robux.UIStroke.Color = STROKE:Lerp(GOLD, 0.6)
	local robuxBody = new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
	}, robux)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 16),
	}, robuxBody)
	local packs = new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = GOLD,
	}, robuxBody)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(190, 250),
		CellPadding = UDim2.fromOffset(16, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, packs)
	new(
		"UIPadding",
		{ PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) },
		packs
	)
	label({
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Coins arrive the moment Roblox confirms the purchase.",
		Color = DIM,
		TextSize = 13,
		X = Enum.TextXAlignment.Center,
	}, robuxBody)
	robux.Parent = hud

	-- The pack card: a coin over its name, its coins and the buy button.
	remove(assets, "Robux")
	local robuxAssets = new("Folder", { Name = "Robux" }, assets)
	local pack = new("Frame", {
		Name = "Pack",
		Size = UDim2.fromOffset(190, 250),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.45,
	}, robuxAssets)
	border(pack, GOLD, 0.45)
	brackets(pack, GOLD, 12, 2)
	-- A plain gold coin: a rim, a stamped face and a glint.
	local coin = new("Frame", {
		Name = "Coin",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = GOLD,
	}, pack)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, coin)
	new("UIStroke", { Color = Color3.fromRGB(255, 242, 190), Thickness = 3 }, coin)
	local face = new("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		BackgroundColor3 = Color3.fromRGB(232, 178, 62),
	}, coin)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, face)
	local glint = new("Frame", {
		Name = "Glint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = Color3.fromRGB(255, 232, 150),
	}, face)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glint)
	label({
		Name = "Name",
		Position = UDim2.fromOffset(8, 114),
		Size = UDim2.new(1, -16, 0, 22),
		Text = "Pouch of Coins",
		Color = MUTED,
		TextSize = 16,
		X = Enum.TextXAlignment.Center,
	}, pack)
	label({
		Name = "Coins",
		Position = UDim2.fromOffset(8, 136),
		Size = UDim2.new(1, -16, 0, 34),
		Text = "+2,500",
		Color = GOLD,
		TextSize = 28,
		X = Enum.TextXAlignment.Center,
	}, pack)
	label({
		Name = "Caption",
		Position = UDim2.fromOffset(8, 170),
		Size = UDim2.new(1, -16, 0, 16),
		Text = "coins",
		Color = DIM,
		TextSize = 13,
		X = Enum.TextXAlignment.Center,
	}, pack)
	local buy = button({
		Name = "Buy",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 38),
		Text = "R$ 49",
		TextSize = 18,
		Stroke = GOLD,
		StrokeTransparency = 0.25,
		Background = Color3.fromRGB(46, 38, 12),
		Transparency = 0.1,
	}, pack)
	buy.Label.TextColor3 = GOLD

	--------------------------------------------------------------------------- Shop: rail and cards
	local shop = hud.Shop
	local body = shop.Body
	local tabs = body.Tabs
	remove(tabs, "RobuxShop")
	tabs.Position = UDim2.new()
	tabs.Size = UDim2.new(0, 136, 1, -56)
	tabs.UIListLayout.FillDirection = Enum.FillDirection.Vertical
	tabs.UIListLayout.Padding = UDim.new(0, 8)
	tabs.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	for order, name in { "SeedShop", "GearShop" } do
		local tab = tabs[name]
		tab.LayoutOrder = order
		tab.Size = UDim2.new(1, 0, 0, 72)
		tab.TextSize = 20
	end
	local restock = body.Restock
	restock.Position = UDim2.new(0, 0, 1, 0)
	restock.AnchorPoint = Vector2.new(0, 1)
	restock.Size = UDim2.new(0, 136, 0, 44)
	restock.BackgroundColor3 = BLACK
	restock.BackgroundTransparency = 0.5
	restock.TextSize = 14
	restock.TextWrapped = true
	restock.TextXAlignment = Enum.TextXAlignment.Center
	if not restock:FindFirstChild("Border") then
		border(restock, SAGE, 0.5)
	end
	local cards = body.List
	cards.Position = UDim2.fromOffset(152, 0)
	cards.Size = UDim2.new(1, -152, 1, 0)
	if cards:FindFirstChildOfClass("UIListLayout") then
		cards:FindFirstChildOfClass("UIListLayout"):Destroy()
	end
	if not cards:FindFirstChildOfClass("UIGridLayout") then
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(164, 206),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, cards)
	end

	local row = assets.Shop.Row
	row.Size = UDim2.fromOffset(164, 206)
	shop.UISizeConstraint.MaxSize = Vector2.new(900, 560)
	local function place(
		name: string,
		anchor: Vector2,
		position: UDim2,
		size: UDim2,
		alignment: Enum.TextXAlignment,
		textSize: number
	)
		local node = row:FindFirstChild(name) -- not row[name]: "Name" would be the row's own name
		node.AnchorPoint = anchor
		node.Position = position
		node.Size = size
		node.TextXAlignment = alignment
		node.TextSize = textSize
	end
	local center = Enum.TextXAlignment.Center
	place("Rarity", Vector2.zero, UDim2.new(), UDim2.new(1, 0, 0, 24), center, 14)
	row.Rarity.BackgroundTransparency = 0.82
	row.Rarity.BackgroundColor3 = WHITE
	place("Name", Vector2.zero, UDim2.fromOffset(6, 122), UDim2.new(1, -12, 0, 24), center, 18)
	place("Stock", Vector2.zero, UDim2.fromOffset(6, 146), UDim2.new(1, -12, 0, 18), center, 14)
	place("Price", Vector2.zero, UDim2.new(0, 12, 1, -42), UDim2.new(0.5, -12, 0, 32), Enum.TextXAlignment.Left, 20)
	row.Icon.AnchorPoint = Vector2.new(0.5, 0)
	row.Icon.Position = UDim2.new(0.5, 0, 0, 30)
	row.Icon.Size = UDim2.fromOffset(84, 84)
	row.Buy.AnchorPoint = Vector2.new(1, 1)
	row.Buy.Position = UDim2.new(1, -8, 1, -8)
	row.Buy.Size = UDim2.new(0.5, -8, 0, 32)
	row.Buy.Label.TextSize = 16

	--------------------------------------------------------------------------- Crafting: upgrade
	remove(crafting.Header, "Upgrade")
	remove(crafting, "UpgradePanel")
	local upgrade = button({
		Name = "Upgrade",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -52, 0.5, 0),
		Size = UDim2.fromOffset(128, 32),
		Text = "UPGRADE",
		TextSize = 15,
		Stroke = GOLD,
		StrokeTransparency = 0.2,
		Color = GOLD,
	}, crafting.Header)
	upgrade.ZIndex = 3
	upgrade.Label.ZIndex = 3

	local panel = new("Frame", {
		Name = "UpgradePanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 70),
		Size = UDim2.new(0, 340, 1, -82),
		BackgroundColor3 = Color3.fromRGB(10, 10, 18),
		BackgroundTransparency = 0.02,
		ZIndex = 10,
		Visible = false,
	}, crafting)
	border(panel, GOLD, 0.3)
	brackets(panel, GOLD, 12, 2).ZIndex = 11
	new("UIScale", {}, panel)
	local function text(
		name: string,
		y: number,
		height: number,
		content: string,
		color: Color3,
		size: number,
		wrapped: boolean?
	)
		local node = label({
			Name = name,
			Position = UDim2.fromOffset(12, y),
			Size = UDim2.new(1, -24, 0, height),
			Text = content,
			Color = color,
			TextSize = size,
			Wrapped = wrapped,
			Y = if wrapped then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
			ZIndex = 11,
		}, panel)
		return node
	end
	text("Title", 10, 28, "Workshop", WHITE, 24)
	text("Tier", 38, 16, "Bench upgrade", DIM, 13)
	text("Description", 60, 48, "", MUTED, 14, true)
	text("NeedsTitle", 112, 18, "Requirements", SAGE, 14)
	local needs = new("ScrollingFrame", {
		Name = "Needs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 134),
		Size = UDim2.new(1, -24, 1, -134 - 100),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ZIndex = 11,
	}, panel)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, needs)
	local status = text("Status", 0, 30, "", Color3.fromRGB(240, 150, 140), 13, true)
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 12, 1, -58)
	status.TextXAlignment = Enum.TextXAlignment.Center
	local confirm = button({
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 40),
		Text = "UPGRADE",
		TextSize = 18,
		Background = Color3.fromRGB(74, 168, 92),
		Transparency = 0.05,
		Stroke = SAGE,
		StrokeTransparency = 0.3,
	}, panel)
	confirm.ZIndex = 11
	confirm.Label.ZIndex = 11
end
