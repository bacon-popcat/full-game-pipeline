-- PromptController: every ProximityPrompt in the world, drawn in the game's own look. Each
-- prompt -- the server's (hub stalls, section signs) and the client's own (BlockPrompts) --
-- is switched to the Custom style and bound to Controls.INTERACT, and while Roblox shows one
-- a clone of Assets.UI.Prompt.Card (tools/hud/prompt_hud.luau) floats on it: a key cap
-- naming the key, or the gamepad button's image, that fills while the prompt is held, then
-- the action, the object and an optional status line. A tap or click on the card holds the
-- prompt too, which is how touch works it. Only the look and the keys change here; what a
-- trigger does, and the server's checks, stay with whoever made the prompt.
--
-- A prompt may carry `CardOffset` (studs up from where it hangs to float the card),
-- `Status` / `Working` (a status line, green when working, amber when not) and `Highlight`
-- (outline the model it hangs in while its card shows, so it's clear which block the key works).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Controls = require(script.Parent.Parent.Libraries.Controls)

-- Seconds the card takes to pop in, and how small it starts.
local POP_TIME = 0.14
local POP_FROM = 0.85
-- A short squeeze when a prompt triggers.
local PRESS_SCALE = 0.92
-- The highlight on the prompted model: a soft white wash and a clear outline, faded in.
local HIGHLIGHT_COLOR = Color3.new(1, 1, 1)
local HIGHLIGHT_FILL = 0.85
local HIGHLIGHT_OUTLINE = 0.1

local PromptController = {}

local player = Players.LocalPlayer
-- The card showing on each prompt, and its cleanup.
local cards: { [ProximityPrompt]: () -> () } = {}

local function bind(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Style = Enum.ProximityPromptStyle.Custom
		instance.KeyboardKeyCode = Controls.INTERACT[1]
		instance.GamepadKeyCode = Controls.INTERACT[2]
	end
end

local function find(root: Instance, path: string, className: string): any
	local node: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA(className) then node else nil
end

local function show(template: BillboardGui, prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local card = template:Clone()
	local panel = find(card, "Panel", "Frame")
	local scale = find(card, "Panel.UIScale", "UIScale")
	local fill = find(card, "Panel.Key.Fill", "Frame")
	local keyLabel = find(card, "Panel.Key.Label", "TextLabel")
	local glyph = find(card, "Panel.Key.Glyph", "ImageLabel")
	local action = find(card, "Panel.Text.Action", "TextLabel")
	local object = find(card, "Panel.Text.Object", "TextLabel")
	local status = find(card, "Panel.Text.Status", "TextLabel")
	local hit = find(card, "Hit", "GuiButton")
	if not (panel and scale and fill and keyLabel and glyph and action and object and status and hit) then
		warn("PromptController: Assets.UI.Prompt.Card is missing a piece; rerun tools/hud/prompt_hud.luau")
		card:Destroy()
		return
	end
	local working = card:GetAttribute("SuccessColor")
	local idle = card:GetAttribute("WarningColor")
	local connections: { RBXScriptConnection } = {}
	local fillTween: Tween? = nil

	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		glyph.Image = image
		glyph.Visible = image ~= ""
		keyLabel.Text = if image ~= "" then "" else prompt.GamepadKeyCode.Name
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		keyLabel.Text = "TAP"
		keyLabel.TextSize = 13
	else
		keyLabel.Text = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		if keyLabel.Text == "" then
			keyLabel.Text = prompt.KeyboardKeyCode.Name
		end
	end

	local function refresh()
		action.Text = prompt.ActionText
		object.Text = prompt.ObjectText
		object.Visible = prompt.ObjectText ~= ""
		local line = prompt:GetAttribute("Status")
		status.Visible = typeof(line) == "string" and line ~= ""
		status.Text = if typeof(line) == "string" then line else ""
		local isWorking = prompt:GetAttribute("Working") == true
		local color = if isWorking then working else idle
		if typeof(color) == "Color3" then
			status.TextColor3 = color
		end
		local offset = prompt:GetAttribute("CardOffset")
		card.StudsOffsetWorldSpace = Vector3.new(0, if typeof(offset) == "number" then offset else 0, 0)
	end
	refresh()
	table.insert(connections, prompt.Changed:Connect(refresh))
	table.insert(connections, prompt.AttributeChanged:Connect(refresh))

	local function setFill(target: number, seconds: number)
		if fillTween then
			fillTween:Cancel()
		end
		fillTween = TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
			Size = UDim2.fromScale(1, target),
		})
		assert(fillTween):Play()
	end
	table.insert(
		connections,
		prompt.PromptButtonHoldBegan:Connect(function()
			setFill(1, prompt.HoldDuration)
		end)
	)
	table.insert(
		connections,
		prompt.PromptButtonHoldEnded:Connect(function()
			setFill(0, 0.1)
		end)
	)
	table.insert(
		connections,
		prompt.Triggered:Connect(function()
			scale.Scale = PRESS_SCALE
			TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
	)

	-- A tap or click on the card holds the prompt until it lifts (or leaves the card).
	local holding = false
	local function release()
		if holding then
			holding = false
			prompt:InputHoldEnd()
		end
	end
	table.insert(
		connections,
		hit.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
				holding = true
				prompt:InputHoldBegin()
			end
		end)
	)
	table.insert(
		connections,
		hit.InputEnded:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
				release()
			end
		end)
	)
	table.insert(connections, hit.MouseLeave:Connect(release))

	local highlight: Highlight? = nil
	local model = prompt:FindFirstAncestorOfClass("Model")
	if prompt:GetAttribute("Highlight") == true and model then
		local made = Instance.new("Highlight")
		made.Name = "PromptHighlight"
		made.Adornee = model
		made.DepthMode = Enum.HighlightDepthMode.Occluded
		made.FillColor = HIGHLIGHT_COLOR
		made.OutlineColor = HIGHLIGHT_COLOR
		made.FillTransparency = 1
		made.OutlineTransparency = 1
		made.Parent = model
		TweenService:Create(made, TweenInfo.new(POP_TIME), {
			FillTransparency = HIGHLIGHT_FILL,
			OutlineTransparency = HIGHLIGHT_OUTLINE,
		}):Play()
		highlight = made
	end

	card.Adornee = prompt.Parent
	card.Parent = player:FindFirstChildOfClass("PlayerGui")
	scale.Scale = POP_FROM
	TweenService:Create(scale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	cards[prompt] = function()
		release()
		for _, connection in connections do
			connection:Disconnect()
		end
		card:Destroy()
		if highlight then
			highlight:Destroy()
		end
	end
end

local function hide(prompt: ProximityPrompt)
	local cleanup = cards[prompt]
	if cleanup then
		cards[prompt] = nil
		cleanup()
	end
end

function PromptController.init()
	workspace.DescendantAdded:Connect(bind)
	for _, instance in workspace:GetDescendants() do
		bind(instance)
	end
	local ui = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
	local template = find(ui, "Prompt.Card", "BillboardGui")
	if not template then
		warn("PromptController: Assets.UI.Prompt.Card is missing; rerun tools/hud/prompt_hud.luau")
		return
	end
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		hide(prompt)
		show(template, prompt, inputType)
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
end

return PromptController
