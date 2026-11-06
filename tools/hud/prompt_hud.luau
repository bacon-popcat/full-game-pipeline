--[[
Authors ReplicatedStorage.Assets.UI.Prompt.Card, the BillboardGui PromptController clones for
every ProximityPrompt it shows (the place file only; conventions.md § UI).

Run it like progress_hud.luau: serve the repo (python -m http.server 34998 --bind 127.0.0.1),
fetch this file into a temporary ModuleScript in the Edit datamodel, require it and call the
function it returns. It is safe to rerun: the Prompt folder is removed and rebuilt.

The look follows the hover panel (HUD.BlockInfo): a half-black panel with a faint border, its
white corner brackets (cloned from it) and Sarpanch. On the left a key cap names the key (or
shows the gamepad button's image) and fills while a prompt is held; on the right the action,
the object and an optional status line.

  Card (BillboardGui, Active, AlwaysOnTop)
    Panel (Frame)   UIStroke, Brackets, UIScale
      Key (Frame)   UIStroke, Fill (Frame), Label (TextLabel), Glyph (ImageLabel)
      Text (Frame)  UIListLayout, Action, Object, Status (TextLabels)
    Hit (TextButton) -- a tap or click on the card holds the prompt
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local STROKE = Color3.fromRGB(205, 205, 220)
local MUTED = Color3.fromRGB(190, 190, 205)
local SUCCESS = Color3.fromRGB(150, 230, 140)
local WARNING = Color3.fromRGB(255, 196, 92)

local WIDTH = 280
local HEIGHT = 58
local KEY = 38

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local info = hud:FindFirstChild("BlockInfo")
	local title = info and info:FindFirstChild("Content") and info.Content:FindFirstChild("Title")
	local family = if title then title.FontFace.Family else "rbxasset://fonts/families/Sarpanch.json"
	local ui = ReplicatedStorage.Assets.UI

	local old = ui:FindFirstChild("Prompt")
	if old then
		old:Destroy()
	end

	local function new(className: string, props: { [string]: any }, parent: Instance?): any
		local node = Instance.new(className)
		for key, value in props do
			node[key] = value
		end
		node.Parent = parent
		return node
	end

	local function label(name: string, weight: Enum.FontWeight, size: number, color: Color3, parent: Instance)
		local node = new("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			FontFace = Font.new(family, weight),
			TextSize = size,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, size + 2),
		}, parent)
		new("UIStroke", { Color = BLACK, Transparency = 0.4, Thickness = 1.5 }, node)
		return node
	end

	local folder = new("Folder", { Name = "Prompt" })
	local card = new("BillboardGui", {
		Name = "Card",
		Active = true,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ClipsDescendants = false,
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		MaxDistance = 200,
	}, folder)
	card:SetAttribute("SuccessColor", SUCCESS)
	card:SetAttribute("WarningColor", WARNING)

	local panel = new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, card)
	new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = STROKE,
		Transparency = 0.65,
		Thickness = 1,
	}, panel)
	new("UIScale", { Scale = 1 }, panel)
	local brackets = info and info:FindFirstChild("Brackets")
	if brackets then
		brackets:Clone().Parent = panel
	end

	local key = new("Frame", {
		Name = "Key",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(KEY, KEY),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, panel)
	new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = WHITE,
		Transparency = 0.15,
		Thickness = 1.5,
	}, key)
	new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
	}, key)
	local keyLabel = label("Label", Enum.FontWeight.Bold, 20, WHITE, key)
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center
	keyLabel.TextTruncate = Enum.TextTruncate.None
	keyLabel.TextScaled = false
	keyLabel.Text = "F"
	new("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(KEY - 10, KEY - 10),
		BackgroundTransparency = 1,
		Visible = false,
	}, key)

	local text = new("Frame", {
		Name = "Text",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, KEY + 18, 0.5, 0),
		Size = UDim2.new(1, -(KEY + 26), 1, -8),
		BackgroundTransparency = 1,
	}, panel)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 0),
	}, text)
	label("Action", Enum.FontWeight.Bold, 17, WHITE, text).LayoutOrder = 1
	label("Object", Enum.FontWeight.SemiBold, 13, MUTED, text).LayoutOrder = 2
	label("Status", Enum.FontWeight.Bold, 12, SUCCESS, text).LayoutOrder = 3

	new("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, card)

	folder.Parent = ui
	return "Assets.UI.Prompt.Card built"
end
