--[[
Authors the HUD pieces for notices, the hotbar's backpack button, the side Menu and its windows
(Achievements, Quests, Stats) and the Islands-style Crafting window, in StarterGui.HUD and
ReplicatedStorage.Assets.UI (the place file only; conventions.md § UI).

Run it through the Studio MCP in the Edit datamodel: serve the repo (python -m http.server 34998
--bind 127.0.0.1), fetch this file into a temporary ModuleScript, require it and call the function
it returns. It is safe to rerun: every node it makes is removed and rebuilt, and the moves (the
backpack button into the Hotbar, Settings out of SideButtons) check where things already are.

Looks follow the existing windows: the Crafting window's shell (near-black gradient, accent
brackets, Sarpanch) is cloned for each new window, so one retune of the shell's look in Studio is
the template for the rest.
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
local SKY = Color3.fromRGB(142, 197, 255)
local LAVENDER = Color3.fromRGB(184, 168, 242)
local CRAFT_GREEN = Color3.fromRGB(74, 168, 92)

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local assets = ReplicatedStorage.Assets.UI
	local shell = hud.Crafting
	local family = shell.Header.Title.FontFace.Family
	local log = {}

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
			if key ~= "Children" then
				node[key] = value
			end
		end
		for _, child in props.Children or {} do
			child.Parent = node
		end
		node.Parent = parent
		return node
	end

	local function textStroke(parent: Instance, transparency: number?)
		new("UIStroke", { Color = BLACK, Transparency = transparency or 0.4, Thickness = 1.5 }, parent)
	end

	local function border(parent: Instance, color: Color3?, transparency: number?, name: string?)
		return new("UIStroke", {
			Name = name or "UIStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = color or STROKE,
			Transparency = transparency or 0.65,
			Thickness = 1,
		}, parent)
	end

	local function label(props: { [string]: any }, parent: Instance): TextLabel
		local node = new(props.ClassName or "TextLabel", {
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
			RichText = props.RichText or false,
			AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None,
			ZIndex = props.ZIndex or 1,
		}, parent)
		textStroke(node)
		return node
	end

	-- L-shaped corner brackets round `parent`: `length` px arms, `thickness` px bars, sat
	-- `thickness` px outside its edges, like the windows' own.
	local function brackets(parent: Instance, color: Color3, length: number, thickness: number, zIndex: number?)
		local frame = new("Frame", {
			Name = "Brackets",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = zIndex or 2,
		}, parent)
		for _, corner in
			{
				{ "TopLeft", 0, 0 },
				{ "TopRight", 1, 0 },
				{ "BottomLeft", 0, 1 },
				{ "BottomRight", 1, 1 },
			}
		do
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
				ZIndex = zIndex or 2,
			}, frame)
			new("Frame", {
				Name = "Horizontal",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.new(1, 0, 0, thickness),
				ZIndex = zIndex or 2,
			}, holder)
			new("Frame", {
				Name = "Vertical",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.new(0, thickness, 1, 0),
				ZIndex = zIndex or 2,
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
			LayoutOrder = props.LayoutOrder or 0,
			ZIndex = props.ZIndex or 1,
		}, parent)
		border(node, props.Stroke or STROKE, props.StrokeTransparency or 0.45)
		new("UIScale", {}, node)
		if props.Text then
			label({
				Name = "Label",
				Text = props.Text,
				TextSize = props.TextSize or 16,
				X = Enum.TextXAlignment.Center,
				ZIndex = props.ZIndex,
			}, node)
		end
		return node
	end

	-- A track with a fill, for progress bars.
	local function bar(parent: Instance, props: { [string]: any })
		local track = new("Frame", {
			Name = props.Name or "Track",
			BackgroundColor3 = Color3.fromRGB(40, 40, 54),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Position = props.Position,
			Size = props.Size,
			AnchorPoint = props.AnchorPoint or Vector2.zero,
		}, parent)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		local fill = new("Frame", {
			Name = "Fill",
			BackgroundColor3 = props.Color or GOLD,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0.4, 1),
		}, track)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		return track
	end

	-- A window: the Crafting window's shell (header, brackets, gradient, accent), re-titled and
	-- re-coloured, with an empty Body. Built from the original shell's children before the
	-- Crafting body is rebuilt, so every window starts from the same look.
	local function window(name: string, title: string, subtitle: string, accent: Color3, maxSize: Vector2)
		remove(hud, name)
		local frame = shell:Clone()
		frame.Name = name
		for _, child in frame:GetChildren() do
			if child.Name == "Body" or child.Name == "Tooltip" then
				child:Destroy()
			end
		end
		frame.Visible = false
		frame.Header.Title.Text = title
		frame.Header.Subtitle.Text = subtitle
		frame.UISizeConstraint.MaxSize = maxSize
		paintBars(frame.Brackets, accent)
		frame.Accent.BackgroundColor3 = accent
		frame.Header.Divider.BackgroundColor3 = accent
		for _, stroke in frame.Header.Close:GetChildren() do
			if stroke:IsA("Frame") then
				stroke.BackgroundColor3 = accent
			end
		end
		frame.UIStroke.Color = STROKE:Lerp(accent, 0.6)
		local body = new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 1, -64),
		}, frame)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 18),
			PaddingRight = UDim.new(0, 18),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 16),
		}, body)
		frame.Parent = hud
		return frame, body
	end

	local function list(parent: Instance, props: { [string]: any }): ScrollingFrame
		local scroll = new("ScrollingFrame", {
			Name = props.Name or "List",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = props.Position or UDim2.new(),
			Size = props.Size or UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = STROKE,
			ScrollBarImageTransparency = 0.4,
		}, parent)
		new(
			"UIPadding",
			{ PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) },
			scroll
		)
		new(
			"UIListLayout",
			{ Padding = UDim.new(0, props.Padding or 6), SortOrder = Enum.SortOrder.LayoutOrder },
			scroll
		)
		return scroll
	end

	local function circle(parent: Instance, props: { [string]: any })
		local node = new("Frame", {
			Name = props.Name,
			BackgroundColor3 = props.Color or WHITE,
			BackgroundTransparency = props.Transparency or 0,
			BorderSizePixel = 0,
			AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
			Position = props.Position,
			Size = props.Size,
			ZIndex = props.ZIndex or 1,
		}, parent)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, node)
		return node
	end

	local function rect(parent: Instance, name: string, color: Color3, position: UDim2, size: UDim2, zIndex: number?)
		return new("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			ZIndex = zIndex or 1,
		}, parent)
	end

	-- Small frame-drawn icons, in a square Icon frame, all in one colour so the code can recolour them.
	local function iconFrame(parent: Instance, position: UDim2, size: UDim2, anchor: Vector2?)
		return new("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = anchor or Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
		}, parent)
	end
	local function medalIcon(icon: Instance, color: Color3)
		rect(icon, "RibbonLeft", color, UDim2.fromScale(0.36, 0.2), UDim2.fromScale(0.16, 0.42))
		rect(icon, "RibbonRight", color, UDim2.fromScale(0.64, 0.2), UDim2.fromScale(0.16, 0.42))
		local disc = circle(icon, {
			Name = "Disc",
			Color = color,
			Transparency = 1,
			Position = UDim2.fromScale(0.5, 0.62),
			Size = UDim2.fromScale(0.62, 0.62),
		})
		new("UIStroke", { Name = "Ring", Color = color, Thickness = 2 }, disc)
		circle(
			icon,
			{ Name = "Core", Color = color, Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.26, 0.26) }
		)
	end
	local function questIcon(icon: Instance, color: Color3)
		local sheet = rect(icon, "Sheet", color, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.66, 0.86))
		sheet.BackgroundTransparency = 1
		new("UIStroke", { Color = color, Thickness = 2 }, sheet)
		for index, y in { 0.3, 0.5, 0.7 } do
			rect(icon, `Line{index}`, color, UDim2.fromScale(0.54, y), UDim2.fromScale(0.34, 0.07))
			rect(icon, `Tick{index}`, color, UDim2.fromScale(0.3, y), UDim2.fromScale(0.08, 0.08))
		end
	end
	local function statsIcon(icon: Instance, color: Color3)
		for index, spec in { { 0.24, 0.4 }, { 0.5, 0.75 }, { 0.76, 0.56 } } do
			local column =
				rect(icon, `Bar{index}`, color, UDim2.fromScale(spec[1], 0.9), UDim2.fromScale(0.18, spec[2]))
			column.AnchorPoint = Vector2.new(0.5, 1)
		end
		rect(icon, "Base", color, UDim2.fromScale(0.5, 0.93), UDim2.fromScale(0.9, 0.06))
	end
	local function menuIcon(icon: Instance, color: Color3)
		for index, y in { 0.24, 0.5, 0.76 } do
			rect(icon, `Line{index}`, color, UDim2.fromScale(0.5, y), UDim2.fromScale(0.84, 0.13))
		end
	end
	local function checkMark(parent: Instance, color: Color3, zIndex: number)
		local short = rect(parent, "Short", color, UDim2.fromScale(0.36, 0.56), UDim2.fromScale(0.14, 0.34), zIndex)
		short.Rotation = -45
		local long = rect(parent, "Long", color, UDim2.fromScale(0.58, 0.47), UDim2.fromScale(0.14, 0.6), zIndex)
		long.Rotation = 40
	end
	local function padlock(parent: Instance, color: Color3, zIndex: number)
		local body = rect(parent, "Body", color, UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.6, 0.44), zIndex)
		new("UICorner", { CornerRadius = UDim.new(0.2, 0) }, body)
		local shackle = circle(parent, {
			Name = "Shackle",
			Color = color,
			Transparency = 1,
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.fromScale(0.42, 0.46),
			ZIndex = zIndex,
		})
		new("UIStroke", { Color = color, Thickness = 2 }, shackle)
	end
	-- A count badge on a corner: a gold pill with dark digits, hidden until there is something to claim.
	local function badge(parent: Instance, position: UDim2, size: number)
		local pill = circle(
			parent,
			{ Name = "Badge", Color = GOLD, Position = position, Size = UDim2.fromOffset(size, size), ZIndex = 6 }
		)
		pill.Visible = false
		new("UIStroke", { Color = BLACK, Transparency = 0.3, Thickness = 1.5 }, pill)
		local text = label({
			Name = "Count",
			Text = "1",
			Color = Color3.fromRGB(30, 26, 20),
			TextSize = math.floor(size * 0.72),
			X = Enum.TextXAlignment.Center,
			ZIndex = 7,
		}, pill)
		text:FindFirstChildOfClass("UIStroke"):Destroy()
		return pill
	end

	---------------------------------------------------------------- notices
	do
		local toast = assets.Toast.Toast
		remove(toast, "Border")
		border(toast, WHITE, 0.35, "Border").Thickness = 1.5
		toast.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
		toast.BackgroundTransparency = 0.12
		toast.ZIndex = 50
		local corner = toast:FindFirstChildOfClass("UICorner") or new("UICorner", {}, toast)
		corner.CornerRadius = UDim.new(0, 4)
		local layout = hud.Toasts:FindFirstChildOfClass("UIListLayout")
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		hud.Toasts.AnchorPoint = Vector2.new(0.5, 1)
		-- Over every window (they sit at ZIndex 30), so a notice answering a press in one (a craft, a claim) is seen.
		hud.Toasts.ZIndex = 50
		table.insert(log, "toasts: bottom-stacked, Border stroke")
	end

	---------------------------------------------------------------- backpack button
	do
		local opener = hud.SideButtons:FindFirstChild("Backpack") or hud.Hotbar:FindFirstChild("Backpack")
		opener.Parent = hud.Hotbar
		opener.LayoutOrder = 10
		opener.Size = UDim2.fromOffset(58, 58)
		paintBars(opener, WHITE)
		for _, cell in opener.Icon:GetChildren() do
			if cell:IsA("Frame") then
				cell.BackgroundColor3 = WHITE
			end
		end
		opener.UIStroke.Color = STROKE
		opener.UIStroke.Transparency = 0.45
		local tooltip = opener.Tooltip
		tooltip.AnchorPoint = Vector2.new(0.5, 1)
		tooltip.Position = UDim2.new(0.5, 0, 0, -10)
		tooltip.Size = UDim2.fromScale(2, 0.6)
		table.insert(log, "backpack button: in Hotbar, white")
	end

	---------------------------------------------------------------- side Menu button
	local sideButtons = hud.SideButtons
	do
		local settingsButton = sideButtons:FindFirstChild("Settings")
		remove(sideButtons, "Menu")
		local source = settingsButton or sideButtons.Research
		local menu = source:Clone()
		menu.Name = "Menu"
		menu.LayoutOrder = 100
		menu.Icon:ClearAllChildren()
		menuIcon(menu.Icon, WHITE)
		paintBars(menu, WHITE)
		menu.UIStroke.Color = STROKE
		menu.Tooltip.Label.Text = "Menu"
		menu.Tooltip.Label.TextColor3 = WHITE
		local tooltipStroke = menu.Tooltip.Label:FindFirstChildOfClass("UIStroke")
		if tooltipStroke then
			tooltipStroke.Color = BLACK
		end
		badge(menu, UDim2.fromScale(0.92, 0.08), 18)
		menu.Parent = sideButtons
		if settingsButton then
			settingsButton:Destroy()
		end
		-- Five buttons now (Shop, Sell, Index, Research, Menu): keep their authored pixel size and gap.
		local count = 0
		for _, child in sideButtons:GetChildren() do
			if child:IsA("GuiButton") then
				count += 1
			end
		end
		local reference = 720
		local height = sideButtons.Size.Y.Scale * reference
		local layout = sideButtons:FindFirstChildOfClass("UIListLayout")
		local buttonPx = sideButtons.Research.Size.Y.Scale * height
		local gapPx = layout.Padding.Scale * height
		local newHeight = buttonPx * count + gapPx * (count - 1)
		for _, child in sideButtons:GetChildren() do
			if child:IsA("GuiButton") then
				child.Size = UDim2.fromScale(1, buttonPx / newHeight)
			end
		end
		layout.Padding = UDim.new(gapPx / newHeight, 0)
		local width = sideButtons.Size.X.Scale * 1280
		sideButtons.Size = UDim2.fromScale(sideButtons.Size.X.Scale, newHeight / reference)
		sideButtons:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio = width / newHeight
		table.insert(log, `side buttons: {count}, Menu replaces Settings`)
	end

	---------------------------------------------------------------- Menu popup
	do
		local menu, body = window("Menu", "Menu", "Where to?", WHITE, Vector2.new(340, 292))
		body.UIPadding.PaddingTop = UDim.new(0, 14)
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
		for index, entry in
			{
				{ "Achievements", GOLD, medalIcon },
				{ "Quests", SKY, questIcon },
				{ "Stats", LAVENDER, statsIcon },
				{ "Settings", MUTED, nil },
			}
		do
			local name, color, draw = entry[1], entry[2], entry[3]
			local row = button({
				Name = name,
				Size = UDim2.new(1, 0, 0, 44),
				LayoutOrder = index,
				Stroke = color,
				StrokeTransparency = 0.55,
			}, body)
			brackets(row, color, 10, 2)
			local icon = iconFrame(row, UDim2.new(0, 26, 0.5, 0), UDim2.fromOffset(24, 24))
			if draw then
				draw(icon, color)
			else
				-- A gear: a ring with eight teeth, like the old Settings side button's.
				local ring = circle(icon, {
					Name = "Ring",
					Color = color,
					Transparency = 1,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.56, 0.56),
				})
				new("UIStroke", { Color = color, Thickness = 3 }, ring)
				for tooth = 0, 7 do
					local angle = math.rad(tooth * 45)
					local t = rect(
						icon,
						`Tooth{tooth}`,
						color,
						UDim2.fromScale(0.5 + math.sin(angle) * 0.4, 0.5 - math.cos(angle) * 0.4),
						UDim2.fromScale(0.16, 0.18)
					)
					t.Rotation = tooth * 45
				end
			end
			label({
				Name = "Label",
				Text = name,
				TextSize = 19,
				Position = UDim2.fromOffset(52, 0),
				Size = UDim2.new(1, -60, 1, 0),
			}, row)
			if name == "Quests" then
				badge(row, UDim2.new(1, -18, 0.5, 0), 22)
			end
		end
		menu.Header.Subtitle.TextColor3 = DIM
		table.insert(log, "Menu popup")
	end

	---------------------------------------------------------------- Progress templates
	remove(assets, "Progress")
	local templates = new("Folder", { Name = "Progress" }, assets)

	---------------------------------------------------------------- Achievements
	do
		local _, body = window(
			"Achievements",
			"Achievements",
			"Milestones for your garden, each with a reward",
			GOLD,
			Vector2.new(760, 540)
		)
		label(
			{ Name = "Summary", Text = "0 of 0 unlocked", TextSize = 15, Color = MUTED, Size = UDim2.new(1, 0, 0, 22) },
			body
		)
		list(body, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), Padding = 10 })
		local row = new("Frame", {
			Name = "Achievement",
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.5,
			Size = UDim2.new(1, -8, 0, 66),
		}, templates)
		border(row, STROKE, 0.65)
		brackets(row, DIM, 10, 2)
		local medal = iconFrame(row, UDim2.new(0, 34, 0.5, 0), UDim2.fromOffset(36, 36))
		medalIcon(medal, GOLD)
		label({
			Name = "Name",
			Text = "Green Thumb",
			TextSize = 19,
			Position = UDim2.fromOffset(66, 9),
			Size = UDim2.new(1, -290, 0, 24),
		}, row)
		label({
			Name = "Description",
			Text = "Harvest 100 crops.",
			Weight = Enum.FontWeight.Medium,
			TextSize = 14,
			Color = MUTED,
			Position = UDim2.fromOffset(66, 35),
			Size = UDim2.new(1, -290, 0, 20),
		}, row)
		label({
			Name = "Count",
			Text = "45 / 100",
			TextSize = 14,
			Color = MUTED,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 8),
			Size = UDim2.fromOffset(200, 18),
		}, row)
		bar(row, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 30),
			Size = UDim2.fromOffset(200, 8),
			Color = GOLD,
		})
		label({
			Name = "Reward",
			Text = "+250 coins",
			TextSize = 14,
			Color = GOLD,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 42),
			Size = UDim2.fromOffset(200, 18),
		}, row)
		table.insert(log, "Achievements window")
	end

	---------------------------------------------------------------- Quests
	do
		local _, body = window("Quests", "Quests", "Little jobs around the garden", SKY, Vector2.new(660, 420))
		label({
			Name = "Hint",
			Text = "Finish a quest, then claim its reward. A new one takes its place.",
			Weight = Enum.FontWeight.Medium,
			TextSize = 14,
			Color = MUTED,
			Size = UDim2.new(1, 0, 0, 22),
		}, body)
		list(body, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), Padding = 12 })
		local row = new(
			"Frame",
			{ Name = "Quest", BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, Size = UDim2.new(1, -8, 0, 82) },
			templates
		)
		border(row, STROKE, 0.65)
		brackets(row, DIM, 10, 2)
		label({
			Name = "Text",
			Text = "Harvest 25 crops",
			TextSize = 19,
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -180, 0, 24),
		}, row)
		label({
			Name = "Reward",
			Text = "+150 coins  ·  20 XP",
			TextSize = 14,
			Color = GOLD,
			Position = UDim2.fromOffset(16, 33),
			Size = UDim2.new(1, -180, 0, 18),
		}, row)
		bar(row, { Position = UDim2.fromOffset(16, 60), Size = UDim2.new(1, -250, 0, 8), Color = SKY })
		label({
			Name = "Count",
			Text = "12 / 25",
			TextSize = 14,
			Color = MUTED,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -168, 0, 54),
			Size = UDim2.fromOffset(70, 20),
		}, row)
		button({
			Name = "Claim",
			Text = "Claim",
			TextSize = 17,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(136, 40),
			Stroke = SKY,
		}, row)
		table.insert(log, "Quests window")
	end

	---------------------------------------------------------------- Stats
	do
		local _, body = window("Stats", "Stats", "Everything this garden has done", LAVENDER, Vector2.new(560, 540))
		list(body, { Padding = 4 })
		local row = new(
			"Frame",
			{ Name = "Stat", BackgroundColor3 = BLACK, BackgroundTransparency = 0.5, Size = UDim2.new(1, -8, 0, 34) },
			templates
		)
		border(row, STROKE, 0.72)
		label({
			Name = "Name",
			Text = "Crops harvested",
			Weight = Enum.FontWeight.Medium,
			TextSize = 16,
			Color = MUTED,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.6, -14, 1, 0),
		}, row)
		label({
			Name = "Value",
			Text = "1,234",
			TextSize = 17,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.4, -14, 1, 0),
		}, row)
		local heading =
			new("Frame", { Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 30) }, templates)
		label({
			Name = "Name",
			Text = "Garden",
			TextSize = 15,
			Color = LAVENDER,
			Position = UDim2.fromOffset(4, 6),
			Size = UDim2.new(1, -8, 1, -6),
		}, heading)
		table.insert(log, "Stats window")
	end

	---------------------------------------------------------------- Crafting
	do
		local crafting = shell
		crafting.UISizeConstraint.MaxSize = Vector2.new(980, 600)
		crafting.Header.Subtitle.Text = "Pick something to make, then how many"
		remove(crafting, "Body")
		remove(crafting, "Tooltip")
		local body = new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 64),
			Size = UDim2.new(1, 0, 1, -64),
		}, crafting)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 16),
		}, body)

		local categories =
			new("Frame", { Name = "Categories", BackgroundTransparency = 1, Size = UDim2.new(0, 150, 1, 0) }, body)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, categories)

		local main = new("Frame", {
			Name = "Main",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(162, 0),
			Size = UDim2.new(1, -162 - 274, 1, 0),
		}, body)
		local search = hud.Backpack.Body.Main.Search:Clone()
		search.Position = UDim2.new()
		search.Size = UDim2.new(1, 0, 0, 34)
		search.AnchorPoint = Vector2.zero
		search.Box.PlaceholderText = "Search..."
		search.Box.Text = ""
		search.Parent = main
		local grid = new("ScrollingFrame", {
			Name = "Grid",
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 42),
			Size = UDim2.new(1, 0, 1, -42),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = STROKE,
			ScrollBarImageTransparency = 0.4,
		}, main)
		border(grid, STROKE, 0.75)
		new("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}, grid)
		new("UIGridLayout", {
			CellSize = UDim2.fromOffset(100, 118),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		label({
			Name = "Empty",
			Text = "Nothing here yet.",
			Weight = Enum.FontWeight.Medium,
			TextSize = 15,
			Color = DIM,
			X = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 60),
			Size = UDim2.new(1, 0, 0, 24),
		}, main).Visible =
			false

		local details = new("Frame", {
			Name = "Details",
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.45,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 262, 1, 0),
		}, body)
		border(details, STROKE, 0.7)
		brackets(details, SAGE, 12, 2)
		label({
			Name = "ItemName",
			Text = "Wood Planks",
			TextSize = 22,
			X = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 26),
		}, details)
		label({
			Name = "Kind",
			Text = "Block",
			Weight = Enum.FontWeight.Medium,
			TextSize = 13,
			Color = DIM,
			X = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 36),
			Size = UDim2.new(1, -20, 0, 16),
		}, details)
		new("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 54),
			Size = UDim2.new(1, -20, 0, 140),
			Ambient = Color3.fromRGB(170, 170, 180),
			LightColor = WHITE,
			LightDirection = Vector3.new(-1, -1.5, -1),
		}, details)
		label({
			Name = "NeedsTitle",
			Text = "Needs",
			TextSize = 14,
			Color = SAGE,
			Position = UDim2.fromOffset(12, 198),
			Size = UDim2.new(1, -24, 0, 18),
		}, details)
		local ingredients = new("Frame", {
			Name = "Ingredients",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 218),
			Size = UDim2.new(1, -20, 1, -218 - 128),
		}, details)
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, ingredients)
		label({
			Name = "Status",
			Text = "",
			Weight = Enum.FontWeight.SemiBold,
			TextSize = 13,
			Color = Color3.fromRGB(240, 150, 140),
			X = Enum.TextXAlignment.Center,
			Wrapped = true,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -96),
			Size = UDim2.new(1, -20, 0, 30),
		}, details)
		local stepper = new("Frame", {
			Name = "Amount",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -56),
			Size = UDim2.new(1, -20, 0, 34),
		}, details)
		button({ Name = "Minus", Text = "-", TextSize = 22, Size = UDim2.fromOffset(34, 34) }, stepper)
		local value = new("TextBox", {
			Name = "Value",
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.3,
			Position = UDim2.fromOffset(40, 0),
			Size = UDim2.new(1, -40 - 40 - 56, 1, 0),
			FontFace = font(Enum.FontWeight.Bold),
			Text = "1",
			TextColor3 = WHITE,
			TextSize = 18,
			ClearTextOnFocus = true,
		}, stepper)
		border(value, STROKE, 0.6)
		button({
			Name = "Plus",
			Text = "+",
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -56, 0, 0),
			Size = UDim2.fromOffset(34, 34),
		}, stepper)
		button({
			Name = "Max",
			Text = "Max",
			TextSize = 15,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(50, 34),
		}, stepper)
		local craft = button({
			Name = "Craft",
			Text = "CRAFT",
			TextSize = 20,
			Background = CRAFT_GREEN,
			Transparency = 0.05,
			Stroke = WHITE,
			StrokeTransparency = 0.6,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 10, 1, -10),
			Size = UDim2.new(1, -20, 0, 40),
		}, details)
		craft:SetAttribute("DisabledBackgroundColor", Color3.fromRGB(70, 74, 80))

		-- The hover card that follows the pointer over the grid.
		local tooltip = new("Frame", {
			Name = "Tooltip",
			BackgroundColor3 = Color3.fromRGB(10, 10, 16),
			BackgroundTransparency = 0.06,
			Size = UDim2.fromOffset(250, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			ZIndex = 20,
		}, crafting)
		border(tooltip, STROKE, 0.5)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		}, tooltip)
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tooltip)
		local tipName = label(
			{ Name = "ItemName", Text = "Merger", TextSize = 18, Size = UDim2.new(1, 0, 0, 22), ZIndex = 21 },
			tooltip
		)
		tipName.LayoutOrder = 1
		local tipText = label({
			Name = "Description",
			Text = "Accepts two input items and combines them.",
			Weight = Enum.FontWeight.Medium,
			TextSize = 14,
			Color = MUTED,
			Wrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 21,
		}, tooltip)
		tipText.LayoutOrder = 2
		local lines = new("Frame", {
			Name = "Lines",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			ZIndex = 21,
		}, tooltip)
		new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, lines)
		new("UIPadding", { PaddingTop = UDim.new(0, 4) }, lines)

		-- Templates.
		local folder = assets.Crafting
		folder:ClearAllChildren()
		local category =
			button({ Name = "Category", Text = "All", TextSize = 17, Size = UDim2.new(1, 0, 0, 36) }, folder)
		category:SetAttribute("SelectedBackgroundColor", Color3.fromRGB(58, 74, 60))
		category:SetAttribute("SelectedStrokeColor", SAGE)

		local card = button({ Name = "Card", Size = UDim2.fromOffset(100, 118), Transparency = 0.25 }, folder)
		card:SetAttribute("SelectedStrokeColor", SAGE)
		brackets(card, STROKE, 10, 2, 3)
		new("ViewportFrame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 8),
			Size = UDim2.fromOffset(78, 78),
			ZIndex = 2,
		}, card)
		label({
			Name = "ItemName",
			Text = "Wood Planks",
			Weight = Enum.FontWeight.SemiBold,
			TextSize = 13,
			X = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 1, -26),
			Size = UDim2.new(1, -8, 0, 20),
			ZIndex = 3,
		}, card)
		label({
			Name = "Count",
			Text = "x4",
			TextSize = 13,
			Color = MUTED,
			Position = UDim2.fromOffset(7, 5),
			Size = UDim2.fromOffset(40, 16),
			ZIndex = 3,
		}, card)
		local ready = circle(card, {
			Name = "Ready",
			Color = GOLD,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 5),
			Size = UDim2.fromOffset(24, 24),
			ZIndex = 4,
		})
		new("UIStroke", { Color = BLACK, Transparency = 0.35, Thickness = 1.5 }, ready)
		checkMark(ready, Color3.fromRGB(40, 34, 24), 5)
		local lock = new("Frame", {
			Name = "Lock",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(20, 22),
			ZIndex = 4,
		}, card)
		padlock(lock, DIM, 4)

		local ingredient = new("Frame", {
			Name = "Ingredient",
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.35,
			Size = UDim2.new(1, 0, 0, 32),
		}, folder)
		border(ingredient, STROKE, 0.8)
		new("ViewportFrame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(3, 2),
			Size = UDim2.fromOffset(28, 28),
		}, ingredient)
		label({
			Name = "ItemName",
			Text = "Iron Bar",
			Weight = Enum.FontWeight.SemiBold,
			TextSize = 14,
			Position = UDim2.fromOffset(36, 0),
			Size = UDim2.new(1, -120, 1, 0),
		}, ingredient)
		label({
			Name = "Amount",
			Text = "12 / 5",
			TextSize = 14,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(80, 32),
		}, ingredient)

		local line = new(
			"Frame",
			{ Name = "TooltipLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), ZIndex = 21 },
			folder
		)
		label({
			Name = "ItemName",
			Text = "Steel Rod",
			TextSize = 14,
			Color = SAGE,
			Size = UDim2.new(1, -70, 1, 0),
			ZIndex = 21,
		}, line)
		label({
			Name = "Amount",
			Text = "1,125 / 4",
			TextSize = 14,
			Color = SAGE,
			X = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 90, 1, 0),
			ZIndex = 21,
		}, line)
		table.insert(log, "Crafting window rebuilt")
	end

	return table.concat(log, "\n")
end
