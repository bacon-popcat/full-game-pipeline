--!strict
-- Backdrop: focuses the screen while a modal window (Backpack, MachinePanel, Shop, Sell,
-- Settings) is open: the authored HUD.Backdrop frame darkens the world and a private blur
-- softens it. It sits at ZIndex 0, under every other HUD node, so the hotbar and wallet stay
-- clear. Windows report through PopupMotion; the backdrop shows while any one is open.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR = 14
local DIM = 0.55

local blur = Instance.new("BlurEffect")
blur.Name = "PopupBlur"
blur.Size = 0
blur.Enabled = false
blur.Parent = Lighting

local open: { [Instance]: boolean } = {}
local tweens: { Tween } = {}
local Backdrop = {}

local function frame(): Frame?
	local hud = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local found = if hud then hud:FindFirstChild("HUD") else nil
	local backdrop = if found then found:FindFirstChild("Backdrop") else nil
	return if backdrop and backdrop:IsA("Frame") then backdrop else nil
end

local function apply()
	local shown = next(open) ~= nil
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
	local dim = frame()
	local blurSize = if shown then BLUR else 0
	local transparency = if shown then DIM else 1
	if shown then
		blur.Enabled = true
		if dim then
			dim.Visible = true
		end
	end
	if GuiService.ReducedMotionEnabled then
		blur.Size = blurSize
		blur.Enabled = shown
		if dim then
			dim.BackgroundTransparency = transparency
			dim.Visible = shown
		end
		return
	end
	local blurTween = TweenService:Create(blur, FADE, { Size = blurSize })
	table.insert(tweens, blurTween)
	if dim then
		table.insert(tweens, TweenService:Create(dim, FADE, { BackgroundTransparency = transparency }))
	end
	blurTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and next(open) == nil then
			blur.Enabled = false
			if dim then
				dim.Visible = false
			end
		end
	end)
	for _, tween in tweens do
		tween:Play()
	end
end

-- Marks one window open or closed.
function Backdrop.set(window: Instance, shown: boolean)
	if (open[window] == true) == shown then
		return
	end
	open[window] = if shown then true else nil
	apply()
end

return Backdrop
