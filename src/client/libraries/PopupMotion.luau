-- PopupMotion: shared window transitions from authored scale/body baselines. Logical
-- closure disables input immediately; cancelled exits cannot hide a reopened window.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local PopupMotion = {}
local ENTER = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EXIT = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CONTENT = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

function PopupMotion.bind(frame: GuiObject): ((boolean) -> (), () -> ())
	local scale = frame:FindFirstChildOfClass("UIScale")
	assert(scale, "PopupMotion requires an authored UIScale")
	local baseline = scale.Scale
	local body = frame:FindFirstChild("Body")
	local bodyPosition = if body and body:IsA("GuiObject") then body.Position else nil
	local interactable = frame.Interactable
	local opened = false
	local tweens: { Tween } = {}
	local completion: RBXScriptConnection? = nil
	local function cancel()
		if completion then
			completion:Disconnect()
			completion = nil
		end
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
	end
	local function restore()
		scale.Scale = baseline
		if body and body:IsA("GuiObject") and bodyPosition then
			body.Position = bodyPosition
		end
	end
	local function settle()
		cancel()
		restore()
		frame.Visible = opened
		frame.Interactable = opened and interactable
	end
	frame.Visible = false
	local preference = GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		if GuiService.ReducedMotionEnabled then
			settle()
		end
	end)
	return function(show: boolean)
		if show == opened then
			return
		end
		opened = show
		cancel()
		frame.Interactable = show and interactable
		if GuiService.ReducedMotionEnabled then
			settle()
			return
		end
		if show and not frame.Visible then
			scale.Scale = baseline * 0.92
			if body and body:IsA("GuiObject") and bodyPosition then
				body.Position = bodyPosition + UDim2.fromOffset(0, 12)
			end
		end
		frame.Visible = true
		local tween =
			TweenService:Create(scale, if show then ENTER else EXIT, { Scale = baseline * (if show then 1 else 0.92) })
		table.insert(tweens, tween)
		if body and body:IsA("GuiObject") and bodyPosition then
			table.insert(
				tweens,
				TweenService:Create(body, if show then CONTENT else EXIT, {
					Position = if show then bodyPosition else bodyPosition + UDim2.fromOffset(0, 8),
				})
			)
		end
		completion = tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not opened then
				settle()
			end
		end)
		for _, active in tweens do
			active:Play()
		end
	end, function()
		preference:Disconnect()
		cancel()
		restore()
		frame.Visible = false
		frame.Interactable = interactable
	end
end

return PopupMotion
