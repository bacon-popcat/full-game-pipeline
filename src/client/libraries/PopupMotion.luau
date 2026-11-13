-- PopupMotion: shared window transitions from authored scale/body baselines. Logical
-- closure disables input immediately; cancelled exits cannot hide a reopened window. A modal
-- window also shows the focus backdrop (Backdrop) while it is open, and plays WindowReveal inside
-- itself as it opens (outline flash, brackets snapping in, accent, divider sweep and glint,
-- springy content cascade), settled at once on every close so a quick reopen starts clean. A
-- modal window also sounds as it opens and closes (UISound).
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Backdrop = require(script.Parent.Backdrop)
local WindowReveal = require(script.Parent.WindowReveal)
local UISound = require(script.Parent.UISound)
local PopupMotion = {}
local ENTER = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- The scale a window pops in from, and the pixels its Body slides up.
local FROM, SLIDE = 0.86, 16
local EXIT = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local CONTENT = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

function PopupMotion.bind(frame: GuiObject, modal: boolean?): ((boolean) -> (), () -> ())
	local scale = frame:FindFirstChildOfClass("UIScale")
	assert(scale, "PopupMotion requires an authored UIScale")
	local baseline = scale.Scale
	local body = frame:FindFirstChild("Body")
	local bodyPosition = if body and body:IsA("GuiObject") then body.Position else nil
	local interactable = frame.Interactable
	local opened = false
	local tweens: { Tween } = {}
	local completion: RBXScriptConnection? = nil
	local reveal: (() -> ())?, settleReveal: (() -> ())? = nil, nil
	if modal then
		reveal, settleReveal = WindowReveal.bind(frame)
	end
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
		if settleReveal then
			settleReveal()
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
		if modal then
			Backdrop.set(frame, show)
			UISound.window(show)
		end
		cancel()
		if settleReveal then
			settleReveal()
		end
		frame.Interactable = show and interactable
		if GuiService.ReducedMotionEnabled then
			settle()
			return
		end
		if show and not frame.Visible then
			scale.Scale = baseline * FROM
			if body and body:IsA("GuiObject") and bodyPosition then
				body.Position = bodyPosition + UDim2.fromOffset(0, SLIDE)
			end
		end
		frame.Visible = true
		local tween =
			TweenService:Create(scale, if show then ENTER else EXIT, { Scale = baseline * (if show then 1 else FROM) })
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
		if show and reveal then
			reveal()
		end
	end, function()
		preference:Disconnect()
		if modal then
			Backdrop.set(frame, false)
		end
		cancel()
		restore()
		frame.Visible = false
		frame.Interactable = interactable
	end
end

return PopupMotion
