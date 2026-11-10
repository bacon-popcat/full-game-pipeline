--[[
Authors the Quests window's two tabs in StarterGui.HUD and the order row in
ReplicatedStorage.Assets.UI.Progress (the place file only; conventions.md § UI):

  * HUD.Quests.Body: Tabs (Daily, Orders), Hint, and the Daily and Orders lists
    (QuestsScreen.luau lists every node it binds).
  * Assets.UI.Progress.Order: the Quest row with an item Icon, Deliver and Skip buttons and a
    Wait line for a slot whose next order is on its way.

Run it after progress_hud.luau, which rebuilds the Quests window with its old single list and
remakes the Progress folder, through the Studio MCP in the Edit datamodel: fetch this file into a
temporary ModuleScript (or paste it), require it and call the function it returns. Everything is
cloned from what progress_hud made (the Quest row, its Claim button, the window's list and hint),
so the look stays the window's own. Safe to rerun: what it makes is removed and rebuilt.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local MUTED = Color3.fromRGB(190, 190, 205)
local DIM = Color3.fromRGB(150, 150, 168)
-- Top of the hint and of the lists, under the tabs.
local HINT_Y, LIST_Y = 42, 70
-- Room the order row's icon takes on the left.
local ICON_SHIFT = 64

local function remove(parent: Instance, name: string)
	local old = parent:FindFirstChild(name)
	while old do
		old:Destroy()
		old = parent:FindFirstChild(name)
	end
end

local function shift(node: GuiObject, by: number)
	node.Position += UDim2.fromOffset(by, 0)
	node.Size -= UDim2.fromOffset(by, 0)
end

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local progress = ReplicatedStorage.Assets.UI.Progress
	local window = hud.Quests
	local body = window.Body
	local questRow = progress.Quest
	local log = {}

	window.UISizeConstraint.MaxSize = Vector2.new(660, 480)
	window.Header.Subtitle.Text = "Daily quests and orders for your garden"

	-- Clone what the rebuilt body is made from before clearing it.
	local listSource = (body:FindFirstChild("List") or body:FindFirstChild("Daily")):Clone()
	for _, child in listSource:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local hint = body.Hint:Clone()
	for _, name in { "List", "Daily", "Orders", "Tabs", "Hint" } do
		remove(body, name)
	end

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 34)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 8)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = tabs
	for index, entry in { { "Daily", "Daily quests" }, { "Orders", "Orders" } } do
		local tab = questRow.Claim:Clone()
		tab.Name = entry[1]
		tab.AnchorPoint = Vector2.zero
		tab.Position = UDim2.new()
		tab.Size = UDim2.fromOffset(150, 34)
		tab.LayoutOrder = index
		tab.Label.Text = entry[2]
		tab.Parent = tabs
	end
	tabs.Parent = body

	hint.Position = UDim2.fromOffset(0, HINT_Y)
	hint.Size = UDim2.new(1, 0, 0, 22)
	hint.Text = "New quests every day. Finish all three for a bonus seed."
	hint.Parent = body

	for _, name in { "Daily", "Orders" } do
		local list = listSource:Clone()
		list.Name = name
		list.Position = UDim2.fromOffset(0, LIST_Y)
		list.Size = UDim2.new(1, 0, 1, -LIST_Y)
		list.Visible = name == "Daily"
		list.Parent = body
	end
	listSource:Destroy()
	table.insert(log, "Quests window: Tabs, Hint, Daily and Orders lists")

	remove(progress, "Order")
	local order = questRow:Clone()
	order.Name = "Order"
	shift(order.Text, ICON_SHIFT)
	shift(order.Reward, ICON_SHIFT)
	shift(order.Track, ICON_SHIFT)
	order.Text.Text = "Carrot x9"

	local icon = Instance.new("ViewportFrame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(12, 13)
	icon.Size = UDim2.fromOffset(56, 56)
	icon.Ambient = Color3.fromRGB(170, 170, 180)
	icon.LightColor = Color3.new(1, 1, 1)
	icon.LightDirection = Vector3.new(-1, -1.5, -1)
	icon.Parent = order

	local deliver = order.Claim
	deliver.Name = "Deliver"
	deliver.AnchorPoint = Vector2.new(1, 0)
	deliver.Position = UDim2.new(1, -14, 0, 10)
	deliver.Size = UDim2.fromOffset(136, 36)
	deliver.Label.Text = "Deliver"

	local skip = deliver:Clone()
	skip.Name = "Skip"
	skip.Position = UDim2.new(1, -14, 0, 52)
	skip.Size = UDim2.fromOffset(136, 22)
	skip.Label.Text = "Skip"
	skip.Label.TextSize = 13
	skip.Label.TextColor3 = MUTED
	local skipStroke = skip:FindFirstChildOfClass("UIStroke")
	if skipStroke then
		skipStroke.Color = DIM
	end
	skip.Parent = order

	local wait = order.Reward:Clone()
	wait.Name = "Wait"
	wait.Position = UDim2.fromOffset(16, 0)
	wait.Size = UDim2.new(1, -32, 1, 0)
	wait.Text = "The next order arrives in 4:12"
	wait.TextColor3 = MUTED
	wait.TextSize = 16
	wait.TextXAlignment = Enum.TextXAlignment.Center
	wait.Visible = false
	wait.Parent = order
	order.Parent = progress
	table.insert(log, "Assets.UI.Progress.Order")

	return table.concat(log, "\n")
end
