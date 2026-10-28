--!strict
-- UI: the shared button layer. Every clickable thing gets its hover, press and gamepad
-- focus feedback here, so the whole interface responds the same way.
--
-- A clickable thing is a bare GuiButton or a Frame wrapping a `Trigger` button;
-- `resolveButton` handles both. Feedback animates a UIScale on `target` (found, or added
-- once); the resting scale is captured from that UIScale, so a scale authored in Studio
-- is kept. Activation is `Activated` only -- it already unifies mouse, touch and gamepad.
--
-- Hover is ignored while the preferred input is touch: a tap fires MouseEnter with no
-- reliable MouseLeave, which would leave the button stuck enlarged.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Trove = require(ReplicatedStorage.Packages.Trove)

export type ButtonOptions = {
	-- What scales; defaults to the node passed to bindButton.
	target: GuiObject?,
	hoverScale: number?,
	pressScale: number?,
	-- Receives Activated's InputObject, for callers that treat devices differently.
	onActivate: ((input: InputObject) -> ())?,
}

local TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEFAULT_HOVER_SCALE = 1.05
local DEFAULT_PRESS_SCALE = 0.95

local UI = {}

function UI.resolveButton(node: GuiObject): GuiButton?
	if node:IsA("GuiButton") then
		return node
	end
	local trigger = node:FindFirstChild("Trigger")
	if trigger and trigger:IsA("GuiButton") then
		return trigger
	end
	return nil
end

-- Returns a cleanup that disconnects everything this call made; hand it to a Trove.
function UI.bindButton(node: GuiObject, options: ButtonOptions): () -> ()
	local button = UI.resolveButton(node)
	if not button then
		warn(`UI.bindButton: {node:GetFullName()} is not a GuiButton and has no Trigger`)
		return function() end
	end

	local target = options.target or node
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Parent = target
		scale = created
	end
	assert(scale, "UIScale was just ensured")

	local rest = scale.Scale
	local hoverScale = options.hoverScale or DEFAULT_HOVER_SCALE
	local pressScale = options.pressScale or DEFAULT_PRESS_SCALE
	local hovered = false
	local focused = false
	local pressed = false
	local tween: Tween? = nil

	local function apply()
		local factor = if pressed then pressScale elseif hovered or focused then hoverScale else 1
		if tween then
			tween:Cancel()
			tween = nil
		end
		if GuiService.ReducedMotionEnabled then
			scale.Scale = rest * factor
			return
		end
		local nextTween = TweenService:Create(scale, TWEEN_INFO, { Scale = rest * factor })
		nextTween:Play()
		tween = nextTween
	end

	local trove = Trove.new()
	trove:Connect(button.MouseEnter, function()
		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			return
		end
		hovered = true
		apply()
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		pressed = false
		apply()
	end)
	trove:Connect(button.SelectionGained, function()
		focused = true
		apply()
	end)
	trove:Connect(button.SelectionLost, function()
		focused = false
		apply()
	end)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		apply()
	end)
	trove:Connect(button.MouseButton1Up, function()
		pressed = false
		apply()
	end)
	trove:Connect(button.Activated, function(input: InputObject)
		pressed = false
		apply()
		if options.onActivate then
			options.onActivate(input)
		end
	end)
	trove:Add(function()
		if tween then
			tween:Cancel()
		end
	end)

	return function()
		trove:Destroy()
	end
end

return UI
