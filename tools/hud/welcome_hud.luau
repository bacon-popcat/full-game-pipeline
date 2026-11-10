--[[
Authors the welcome-back card, StarterGui.HUD.Welcome (the place file only; conventions.md § UI):
a small gold window whose Body holds one line each for the time away, ripe crops, waiting
research, offline coins and the daily gift, and a Collect button (WelcomeScreen.luau lists the
nodes it binds).

Run it after progress_hud.luau and quests_hud.luau, through the Studio MCP in the Edit datamodel:
fetch this file into a temporary ModuleScript (or paste it), require it and call the function it
returns. The card is a clone of the Quests window's shell, its lines the Quest row's Reward label
and its button the row's Claim, so the look stays the windows' own. Safe to rerun: the card is
removed and rebuilt.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local STROKE = Color3.fromRGB(205, 205, 220)
local MUTED = Color3.fromRGB(190, 190, 205)
local GOLD = Color3.fromRGB(255, 214, 102)
-- The lines, top to bottom, with a sample of what each says and its colour.
local LINES = {
	{ "Away", "You were away for 5h 12m.", MUTED },
	{ "Crops", "24 crops are ready to harvest.", WHITE },
	{ "Research", "Rich Soil II is ready to complete in Research.", WHITE },
	{ "Coins", "Your Shipping Bins earned 12,000 coins while you were away.", GOLD },
	{ "Gift", "Day 3 gift  ·  4,000 coins", GOLD },
}

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local questRow = ReplicatedStorage.Assets.UI.Progress.Quest
	local old = hud:FindFirstChild("Welcome")
	if old then
		old:Destroy()
	end

	local card = hud.Quests:Clone()
	card.Name = "Welcome"
	card.Visible = false
	card.Header.Title.Text = "Welcome back"
	card.Header.Subtitle.Text = "While you were away"
	-- Tall enough for all five lines and the button, with little left over.
	card.UISizeConstraint.MaxSize = Vector2.new(480, 310)
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

	local body = card.Body
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	for index, entry in LINES do
		local line = questRow.Reward:Clone()
		line.Name = entry[1]
		line.Text = entry[2]
		line.TextColor3 = entry[3]
		line.TextSize = 16
		line.TextWrapped = true
		line.TextTruncate = Enum.TextTruncate.None
		line.Position = UDim2.new()
		line.Size = UDim2.new(1, 0, 0, 22)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.LayoutOrder = index
		line.Parent = body
	end

	local collect = questRow.Claim:Clone()
	collect.Name = "Collect"
	collect.AnchorPoint = Vector2.zero
	collect.Position = UDim2.new()
	collect.Size = UDim2.new(1, 0, 0, 42)
	collect.LayoutOrder = #LINES + 1
	collect.Label.Text = "Collect"
	local stroke = collect:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = GOLD
	end
	collect.Parent = body
	card.Parent = hud
	return "Welcome card"
end
