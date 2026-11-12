--[[
Authors the welcome-back card, StarterGui.HUD.Welcome (the place file only; conventions.md § UI):
a gold window with a turning sunburst behind its title, a line for the time away, one row each
for ripe crops, waiting research and offline coins (an icon, a coloured stripe and a rich-text
line), a gift panel with the day's reward and a seven-day track, and a gold Collect button with a
shine that sweeps across it (WelcomeScreen.luau lists the nodes it binds and plays the motion).

Run it after progress_hud.luau, quests_hud.luau and notice_hud.luau, through the Studio MCP in the
Edit datamodel: fetch this file into a temporary ModuleScript (or paste it), require it and call
the function it returns. The card is a clone of the Quests window's shell, its icons the notice
kinds' icons (Assets.UI.Toast.Icons) and its button the Quest row's Claim, so the look stays the
windows' own. Safe to rerun: the card is removed and rebuilt.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(20, 16, 8)
local STROKE = Color3.fromRGB(205, 205, 220)
local MUTED = Color3.fromRGB(176, 178, 196)
local GOLD = Color3.fromRGB(255, 214, 102)
local ROW_FILL = Color3.fromRGB(16, 16, 28)
-- The rows, top to bottom: name, the notice icon it wears, its colour and a sample line.
local ROWS = {
	{ "Crops", "Success", Color3.fromRGB(157, 220, 154), "24 crops are ready to harvest." },
	{ "Research", "Quest", Color3.fromRGB(193, 173, 244), "Rich Soil II is ready to complete in Research." },
	{ "Coins", "Reward", GOLD, "Your Shipping Bins earned 12,000 coins while you were away." },
}
local DAYS = 7
local RAYS = 8

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local questRow = ReplicatedStorage.Assets.UI.Progress.Quest
	local icons = ReplicatedStorage.Assets.UI.Toast.Icons
	local old = hud:FindFirstChild("Welcome")
	if old then
		old:Destroy()
	end
	local family = hud.Quests.Header.Title.FontFace.Family
	local bold = Font.new(family, Enum.FontWeight.Bold)

	local function new(className: string, props: { [string]: any }, parent: Instance?): any
		local node = Instance.new(className)
		for key, value in props do
			node[key] = value
		end
		node.Parent = parent
		return node
	end

	local function label(name: string, text: string, size: number, color: Color3, props: { [string]: any }, parent: Instance): TextLabel
		local node = new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			FontFace = bold,
			Text = text,
			TextSize = size,
			TextColor3 = color,
			RichText = true,
			TextWrapped = true,
		}, parent)
		for key, value in props do
			node[key] = value
		end
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.35 }, node)
		return node
	end

	-- A band of light for WelcomeScreen to sweep across `parent` by its gradient's Offset.
	local function shine(parent: GuiObject, z: number)
		local node = new("Frame", {
			Name = "Shine",
			BorderSizePixel = 0,
			BackgroundColor3 = WHITE,
			Size = UDim2.fromScale(1, 1),
			ZIndex = z,
		}, parent)
		new("UIGradient", {
			Rotation = 20,
			Offset = Vector2.new(-1, 0),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.5, 0.6),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, node)
	end

	local card = hud.Quests:Clone()
	card.Name = "Welcome"
	card.Visible = false
	card.Header.Title.Text = "Welcome back"
	card.Header.Subtitle.Text = "Here's what your garden did"
	-- WelcomeScreen sets the height to fit the rows it shows; this is the tallest.
	card.UISizeConstraint.MaxSize = Vector2.new(520, 440)
	-- Gold, where the Quests window is sky blue.
	for _, bar in card.Brackets:GetDescendants() do
		if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
			bar.BackgroundColor3 = GOLD
		end
	end
	card.Accent.BackgroundColor3 = GOLD
	card.Header.Divider.BackgroundColor3 = GOLD
	for _, stroke in card.Header.Close:GetChildren() do
		if stroke:IsA("Frame") then
			stroke.BackgroundColor3 = GOLD
		end
	end
	card.UIStroke.Color = STROKE:Lerp(GOLD, 0.6)

	-- A sunburst behind the title: bars through one centre, each faded at its middle and ends.
	local rays = new("Frame", {
		Name = "Rays",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 0,
	}, card.Header)
	for index = 1, RAYS do
		local bar = new("Frame", {
			Name = `Ray{index}`,
			BorderSizePixel = 0,
			BackgroundColor3 = GOLD,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(if index % 2 == 0 then 3 else 5, 84),
			Rotation = (index - 1) * (180 / RAYS),
			ZIndex = 0,
		}, rays)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.72),
				NumberSequenceKeypoint.new(0.44, 0.92),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(0.56, 0.92),
				NumberSequenceKeypoint.new(0.8, 0.72),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, bar)
	end

	local body = card.Body
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, body)

	label("Away", "You were away for 5h 12m.", 18, MUTED, {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
	}, body)

	local rows = new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rows)
	for index, entry in ROWS do
		local name, iconName, color, sample = entry[1], entry[2], entry[3], entry[4]
		local row = new("Frame", {
			Name = name,
			BorderSizePixel = 0,
			BackgroundColor3 = ROW_FILL,
			BackgroundTransparency = 0.1,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = index,
		}, rows)
		new("UIGradient", {
			Color = ColorSequence.new(color:Lerp(ROW_FILL, 0.8), ROW_FILL),
		}, row)
		new("UIStroke", { Color = color, Thickness = 1, Transparency = 0.6 }, row)
		new("UIScale", { Name = "Pop" }, row)
		new("Frame", {
			Name = "Stripe",
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Size = UDim2.new(0, 3, 1, 0),
		}, row)
		local holder = new("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(22, 22),
		}, row)
		local icon = icons:FindFirstChild(iconName)
		if icon then
			local copy = icon:Clone()
			copy.Size = UDim2.fromScale(1, 1)
			copy.Position = UDim2.new()
			copy.AnchorPoint = Vector2.zero
			copy.Visible = true
			for _, part in copy:GetDescendants() do
				if part:IsA("GuiObject") then
					part.BackgroundColor3 = if part.Name == "Cut" then ROW_FILL:Lerp(color, 0.2) else color
				elseif part:IsA("UIStroke") then
					part.Color = color
				end
			end
			copy.Parent = holder
		end
		label("Text", sample, 15, WHITE, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 46, 0.5, 0),
			Size = UDim2.new(1, -56, 1, -4),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
	end

	-- The gift: what today's is, and where it sits in the week's cycle.
	local gift = new("Frame", {
		Name = "Gift",
		BorderSizePixel = 0,
		BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 0, 108),
		ClipsDescendants = true,
		LayoutOrder = 3,
	}, body)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(58, 44, 16), Color3.fromRGB(20, 15, 8)),
	}, gift)
	new("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.25 }, gift)
	new("UIScale", { Name = "Pop" }, gift)
	shine(gift, 2)
	label("Label", "DAY 3 GIFT", 13, GOLD, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, gift)
	label("Reward", "4,000 coins", 26, WHITE, {
		Position = UDim2.fromOffset(16, 28),
		Size = UDim2.new(1, -32, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, gift)
	local trackFrame = new("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.new(1, -32, 0, 28),
		ZIndex = 3,
	}, gift)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, trackFrame)
	for day = 1, DAYS do
		local pip = new("Frame", {
			Name = `Day{day}`,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(24, 22, 30),
			Size = UDim2.new(1 / DAYS, -6, 1, 0),
			LayoutOrder = day,
			ZIndex = 3,
		}, trackFrame)
		new("UIStroke", { Color = GOLD, Thickness = 1, Transparency = 0.5 }, pip)
		new("UIScale", {}, pip)
		label("Number", tostring(day), 14, MUTED, {
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, pip)
	end

	local collect = questRow.Claim:Clone()
	collect.Name = "Collect"
	collect.AnchorPoint = Vector2.zero
	collect.Position = UDim2.new()
	collect.Size = UDim2.new(1, 0, 0, 46)
	collect.LayoutOrder = 4
	collect.BackgroundColor3 = WHITE
	collect.BackgroundTransparency = 0
	collect.ClipsDescendants = true
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 232, 150), Color3.fromRGB(236, 172, 70)),
	}, collect)
	local stroke = collect:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Color3.fromRGB(255, 244, 200)
		stroke.Transparency = 0.2
	end
	shine(collect, 2)
	collect.Label.Text = "Collect"
	collect.Label.TextColor3 = INK
	collect.Label.TextSize = 20
	collect.Label.ZIndex = 3
	local labelStroke = collect.Label:FindFirstChildOfClass("UIStroke")
	if labelStroke then
		labelStroke.Enabled = false
	end
	collect.Parent = body
	card.Parent = hud
	return "Welcome card"
end
