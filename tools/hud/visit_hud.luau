--[[
Authors the Visit card, StarterGui.HUD.Visit (the place file only; conventions.md § UI): the
small window a garden sign's prompt opens, with the garden's likes, a Like button, what the
player holds, two gift buttons and a note (VisitScreen.luau lists the nodes it binds).

Run it after welcome_hud.luau, through the Studio MCP in the Edit datamodel: fetch this file into a
temporary ModuleScript (or paste it), require it and call the function it returns. The card is a
clone of the Welcome card, its lines that card's lines and its buttons that card's Collect, in the
Quests window's sky blue, so the look stays the windows' own. Safe to rerun: the card is removed
and rebuilt.
]]
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local STROKE = Color3.fromRGB(205, 205, 220)
local MUTED = Color3.fromRGB(190, 190, 205)
local ROSE = Color3.fromRGB(240, 150, 170)

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local welcome = hud.Welcome
	local old = hud:FindFirstChild("Visit")
	if old then
		old:Destroy()
	end

	local card = welcome:Clone()
	card.Name = "Visit"
	card.Visible = false
	card.Header.Title.Text = "A garden"
	card.Header.Subtitle.Text = "Leave a like or a gift"
	card.UISizeConstraint.MaxSize = Vector2.new(440, 340)
	for _, bar in card.Brackets:GetDescendants() do
		if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
			bar.BackgroundColor3 = ROSE
		end
	end
	card.Accent.BackgroundColor3 = ROSE
	card.Header.Divider.BackgroundColor3 = ROSE
	for _, stroke in card.Header.Close:GetChildren() do
		if stroke:IsA("Frame") then
			stroke.BackgroundColor3 = ROSE
		end
	end
	card.UIStroke.Color = STROKE:Lerp(ROSE, 0.6)

	local body = card.Body
	local line = body.Away:Clone()
	local button = body.Collect:Clone()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local function text(name: string, sample: string, color: Color3, order: number)
		local label = line:Clone()
		label.Name = name
		label.Text = sample
		label.TextColor3 = color
		label.LayoutOrder = order
		label.Visible = true
		label.Parent = body
	end
	local function press(name: string, sample: string, order: number, height: number)
		local created = button:Clone()
		created.Name = name
		created.Size = UDim2.new(1, 0, 0, height)
		created.LayoutOrder = order
		created.Label.Text = sample
		local stroke = created:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = ROSE
		end
		created.Parent = body
	end

	text("Likes", "12 likes", WHITE, 1)
	press("Like", "Like", 2, 38)
	text("Held", "Holding Carrot x24", WHITE, 3)
	press("GiftOne", "Give 1", 4, 34)
	press("GiftAll", "Give 24", 5, 34)
	text("Note", "You can still give 4,000 coins' worth today.", MUTED, 6)
	line:Destroy()
	button:Destroy()
	card.Parent = hud
	return "Visit card"
end
