--[[
Authors the notice pieces Toasts.luau binds to (its header lists them): the stack's slot and card,
the top banner's holder and card, and one icon per notice kind, in StarterGui.HUD and
ReplicatedStorage.Assets.UI.Toast (the place file only; conventions.md § UI).

Run it through the Studio MCP in the Edit datamodel, like the other builders here: serve the repo
(python -m http.server 34998 --bind 127.0.0.1), fetch this file into a temporary ModuleScript,
require it and call the function it returns. It is safe to rerun: every node it makes is removed and
rebuilt. It does not depend on the other builders' order.

Cards are authored in pixels at the reference screen (Hud.REFERENCE_WIDTH x REFERENCE_HEIGHT);
Toasts.luau scales them to the screen. The icons are drawn from frames in white, in a square of
Scale sizes, and take their kind's colour at run time, except parts named "Cut", which keep the
card's own colour to carve a detail out of a filled shape. A kind in Shared/Notices with no icon
here shows none.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(10, 10, 18)
local MUTED = Color3.fromRGB(190, 190, 205)
-- Over every window (they sit at ZIndex 30), so a notice answering a press in one is seen.
local Z = 50

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local folder = ReplicatedStorage.Assets.UI.Toast
	local family = hud.Crafting.Header.Title.FontFace.Family
	local log = {}

	local function new(className: string, props: { [string]: any }, parent: Instance?): any
		local node = Instance.new(className)
		for key, value in props do
			node[key] = value
		end
		node.Parent = parent
		return node
	end

	local function remove(parent: Instance, name: string)
		local old = parent:FindFirstChild(name)
		while old do
			old:Destroy()
			old = parent:FindFirstChild(name)
		end
	end

	local function text(name: string, size: number, order: number, color: Color3, parent: Instance, wrap: number?): TextLabel
		local label = new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			FontFace = Font.new(family, Enum.FontWeight.Bold),
			Text = name,
			TextColor3 = color,
			TextSize = size,
			TextWrapped = wrap ~= nil,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			ZIndex = Z,
		}, parent)
		new("UIStroke", { Color = BLACK, Transparency = 0.4, Thickness = 1.5 }, label)
		if wrap then
			new("UISizeConstraint", { MaxSize = Vector2.new(wrap, math.huge) }, label)
		end
		return label
	end

	local function row(parent: Instance, direction: Enum.FillDirection, padding: number)
		new("UIListLayout", {
			FillDirection = direction,
			HorizontalAlignment = if direction == Enum.FillDirection.Vertical
				then Enum.HorizontalAlignment.Left
				else Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, padding),
		}, parent)
	end

	local function pad(parent: Instance, x: number, y: number)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, x),
			PaddingRight = UDim.new(0, x),
			PaddingTop = UDim.new(0, y),
			PaddingBottom = UDim.new(0, y),
		}, parent)
	end

	-- The card both notices share: a dark rounded button with a Border stroke in the kind's colour.
	local function card(parent: Instance, transparency: number): TextButton
		local button = new("TextButton", {
			Name = "Card",
			Text = "",
			AutoButtonColor = false,
			Selectable = false,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = Z,
		}, parent)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
		new("UIStroke", {
			Name = "Border",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = WHITE,
			Transparency = 0.35,
			Thickness = 1.5,
		}, button)
		new("UIScale", {}, button)
		return button
	end

	local function pictures(parent: Instance, icon: number, item: number)
		new("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(icon, icon),
			LayoutOrder = 1,
			ZIndex = Z,
		}, parent)
		new("ViewportFrame", {
			Name = "Item",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(item, item),
			LayoutOrder = 1,
			Visible = false,
			ZIndex = Z,
		}, parent)
	end

	---------------------------------------------------------------- the stack
	do
		local holder = hud.Toasts
		local layout = holder:FindFirstChildOfClass("UIListLayout")
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		-- Each slot carries its own gap, so it closes with the slot.
		layout.Padding = UDim.new(0, 0)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.ZIndex = Z

		remove(folder, "Toast")
		local slot = new("Frame", {
			Name = "Toast",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32),
			ZIndex = Z,
		}, folder)
		new("UIScale", {}, slot)
		local button = card(slot, 0.12)
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.fromScale(0.5, 1)
		pad(button, 10, 4)
		row(button, Enum.FillDirection.Horizontal, 7)
		pictures(button, 18, 24)
		text("Text", 17, 2, WHITE, button, 340).Text = "Done! +120 coins"
		text("Count", 14, 3, MUTED, button).Text = "x2"
		text("Go", 15, 4, MUTED, button).Text = ">"
		table.insert(log, "toast: slot, card, icon, item, text, count, go")
	end

	---------------------------------------------------------------- the banner
	do
		remove(hud, "Banner")
		local holder = new("Frame", {
			Name = "Banner",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			-- Under the weather pill, which ends at 0.15 of the screen's height.
			Position = UDim2.fromScale(0.5, 0.165),
			Size = UDim2.new(),
			ZIndex = Z,
		}, hud)
		new("UIScale", {}, holder)

		remove(folder, "Banner")
		local button = card(folder, 0.06)
		button.Name = "Banner"
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.fromScale(0.5, 0)

		-- Corner brackets like the windows', sat just outside the card.
		local length, thickness = 12, 2
		local brackets = new("Frame", {
			Name = "Brackets",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = Z,
		}, button)
		for _, corner in { { "TopLeft", 0, 0 }, { "TopRight", 1, 0 }, { "BottomLeft", 0, 1 }, { "BottomRight", 1, 1 } } do
			local x, y = corner[2], corner[3]
			local outward = thickness + 2
			local arm = new("Frame", {
				Name = corner[1],
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(x, y),
				Position = UDim2.new(x, if x == 0 then -outward else outward, y, if y == 0 then -outward else outward),
				Size = UDim2.fromOffset(length, length),
				ZIndex = Z,
			}, brackets)
			for name, size in { Horizontal = UDim2.new(1, 0, 0, thickness), Vertical = UDim2.new(0, thickness, 1, 0) } do
				new("Frame", {
					Name = name,
					BorderSizePixel = 0,
					BackgroundColor3 = WHITE,
					AnchorPoint = Vector2.new(x, y),
					Position = UDim2.fromScale(x, y),
					Size = size,
					ZIndex = Z,
				}, arm)
			end
		end

		local content = new("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			ZIndex = Z,
		}, button)
		pad(content, 20, 10)
		row(content, Enum.FillDirection.Horizontal, 14)
		pictures(content, 34, 42)
		local column = new("Frame", {
			Name = "Column",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = 2,
			ZIndex = Z,
		}, content)
		row(column, Enum.FillDirection.Vertical, 0)
		text("Title", 13, 1, MUTED, column).Text = "LEVEL UP"
		text("Text", 20, 2, WHITE, column, 400).Text = "Level 6! New research too."
		text("Go", 20, 3, MUTED, content).Text = ">"
		table.insert(log, "banner: HUD.Banner holder, Banner card with brackets, title, text")
	end

	---------------------------------------------------------------- kind icons
	do
		remove(folder, "Icons")
		local icons = new("Folder", { Name = "Icons" }, folder)

		local function icon(kind: string): Frame
			return new("Frame", { Name = kind, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = Z }, icons)
		end
		-- A filled bar centred at (x, y), `w` by `h` of the square, turned `turn` degrees.
		local function bar(parent: Instance, x: number, y: number, w: number, h: number, turn: number?, round: number?): Frame
			local frame = new("Frame", {
				Name = "Bar",
				BorderSizePixel = 0,
				BackgroundColor3 = WHITE,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromScale(w, h),
				Rotation = turn or 0,
				ZIndex = Z,
			}, parent)
			new("UICorner", { CornerRadius = UDim.new(round or 0.5, 0) }, frame)
			return frame
		end
		-- An outlined shape: hollow, with a stroke that takes the kind's colour.
		local function outline(parent: Instance, x: number, y: number, w: number, h: number, round: number): Frame
			local frame = bar(parent, x, y, w, h, 0, round)
			frame.Name = "Outline"
			frame.BackgroundTransparency = 1
			new("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
			return frame
		end
		local function cut(frame: Frame): Frame
			frame.Name = "Cut"
			frame.BackgroundColor3 = PANEL
			return frame
		end

		local info = icon("Info")
		outline(info, 0.5, 0.5, 0.86, 0.86, 0.5)
		bar(info, 0.5, 0.29, 0.15, 0.15)
		bar(info, 0.5, 0.6, 0.14, 0.36, 0, 0.3)

		local success = icon("Success")
		bar(success, 0.3, 0.6, 0.4, 0.17, 45)
		bar(success, 0.6, 0.48, 0.7, 0.17, -50)

		local failure = icon("Error")
		bar(failure, 0.5, 0.5, 0.95, 0.18, 45)
		bar(failure, 0.5, 0.5, 0.95, 0.18, -45)

		-- A coin: a disc with a ring cut into it.
		local reward = icon("Reward")
		bar(reward, 0.5, 0.5, 0.94, 0.94)
		cut(bar(reward, 0.5, 0.5, 0.62, 0.62))
		bar(reward, 0.5, 0.5, 0.44, 0.44)

		-- A medal: two ribbon tails over a disc with a stud.
		local achievement = icon("Achievement")
		bar(achievement, 0.34, 0.24, 0.2, 0.5, -24, 0.2)
		bar(achievement, 0.66, 0.24, 0.2, 0.5, 24, 0.2)
		bar(achievement, 0.5, 0.64, 0.66, 0.66)
		cut(bar(achievement, 0.5, 0.64, 0.26, 0.26))

		-- A list: a page with three lines.
		local quest = icon("Quest")
		outline(quest, 0.5, 0.5, 0.72, 0.9, 0.12)
		for _, y in { 0.3, 0.5, 0.7 } do
			bar(quest, 0.5, y, 0.4, 0.09)
		end

		-- A four-point sparkle.
		local function sparkle(kind: string)
			local frame = icon(kind)
			bar(frame, 0.5, 0.5, 0.16, 1, 0, 0.5)
			bar(frame, 0.5, 0.5, 1, 0.16, 0, 0.5)
			bar(frame, 0.5, 0.5, 0.42, 0.42, 45, 0.15)
		end
		sparkle("Rare")
		-- Shown only if a stock notice names no seed to picture.
		sparkle("Stock")

		-- An arrow pointing up.
		local level = icon("Level")
		bar(level, 0.34, 0.38, 0.5, 0.17, -45)
		bar(level, 0.66, 0.38, 0.5, 0.17, 45)
		bar(level, 0.5, 0.58, 0.17, 0.66, 0, 0.3)

		table.insert(log, "icons: " .. #icons:GetChildren())
	end

	return table.concat(log, "\n")
end
