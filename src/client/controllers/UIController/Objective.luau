-- Objective: binds the authored next-step panel to server progress. A completion briefly
-- shows its check and fades the old text; reduced motion changes state immediately.
-- Replicated progress recovers a late binding. New updates cancel any older transition.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)
local Sound = require(Players.LocalPlayer.PlayerScripts.Libraries.Sound)

local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local Objective = {}

function Objective.init(hud: ScreenGui): ()
	local panel = Hud.find(hud, "Objective", "Frame")
	local title = Hud.find(hud, "Objective.Title", "TextLabel")
	local text = Hud.find(hud, "Objective.Text", "TextLabel")
	local progress = Hud.find(hud, "Objective.Progress", "TextLabel")
	local check = Hud.find(hud, "Objective.Check", "GuiObject")
	if
		not panel
		or not panel:IsA("Frame")
		or not title
		or not title:IsA("TextLabel")
		or not text
		or not text:IsA("TextLabel")
		or not progress
		or not progress:IsA("TextLabel")
		or not check
		or not check:IsA("GuiObject")
	then
		return
	end
	if not check:IsA("ImageLabel") and not check:IsA("Frame") then
		Hud.find(hud, "Objective.Check", "Frame")
		return
	end
	local textTransparency = text.TextTransparency
	local progressTransparency = progress.TextTransparency
	local checkTransparency = if check:IsA("ImageLabel") then check.ImageTransparency else check.BackgroundTransparency
	local tweens: { Tween } = {}
	local revision = 0
	local current: number? = nil
	panel.Visible = false
	check.Visible = false

	local function cancel(): ()
		revision += 1
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
	end

	local function show(state: Onboarding.Snapshot): ()
		text.Text = state.text
		progress.Text = `Step {state.step} of {state.total}`
		text.TextTransparency = textTransparency
		progress.TextTransparency = progressTransparency
		check.Visible = false
		panel.Visible = not state.done
	end

	local function render(state: Onboarding.Snapshot): ()
		local before = current
		if before and state.step <= before then
			return
		end
		current = state.step
		cancel()
		if before then
			Sound.play("Step")
		end
		if not before or GuiService.ReducedMotionEnabled or not panel.Visible then
			show(state)
			return
		end
		check.Visible = true
		if check:IsA("ImageLabel") then
			check.ImageTransparency = checkTransparency
			table.insert(tweens, TweenService:Create(check, FADE, { ImageTransparency = 1 }))
		else
			check.BackgroundTransparency = checkTransparency
			table.insert(tweens, TweenService:Create(check, FADE, { BackgroundTransparency = 1 }))
		end
		table.insert(tweens, TweenService:Create(text, FADE, { TextTransparency = 1 }))
		table.insert(tweens, TweenService:Create(progress, FADE, { TextTransparency = 1 }))
		for _, tween in tweens do
			tween:Play()
		end
		local version = revision
		task.delay(FADE.Time, function()
			if revision == version then
				show(state)
			end
		end)
	end

	local function refresh(): ()
		local step = Players.LocalPlayer:GetAttribute("OnboardingStep")
		if typeof(step) == "number" then
			render(Onboarding.snapshot(Onboarding.sanitize(step)))
		end
	end
	local remoteConnection = Remotes.Objective.OnClientEvent:Connect(render)
	local attributeConnection = Players.LocalPlayer:GetAttributeChangedSignal("OnboardingStep"):Connect(refresh)
	local motionConnection = GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		if GuiService.ReducedMotionEnabled and current then
			cancel()
			show(Onboarding.snapshot(current))
		end
	end)
	hud.Destroying:Once(function()
		cancel()
		remoteConnection:Disconnect()
		attributeConnection:Disconnect()
		motionConnection:Disconnect()
	end)
	refresh()
end

return Objective
