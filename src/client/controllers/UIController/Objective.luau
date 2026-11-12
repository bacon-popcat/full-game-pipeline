-- Objective: binds the authored next-step panel to server progress. A completion briefly
-- shows its check and fades the old text; reduced motion changes state immediately.
-- Replicated progress recovers a late binding. New updates cancel any older transition.
-- A goal's progress ("12 / 50 sold") takes the step count's place and updates in place. Once every
-- goal is done the panel stays, as "Next unlock": the next level that opens something
-- (Shared/Unlocks) and the XP left to it, hidden only when nothing is left to open.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TextColors = require(ReplicatedStorage.Shared.TextColors)
local Unlocks = require(ReplicatedStorage.Shared.Unlocks)
local EconomyClient = require(Players.LocalPlayer.PlayerScripts.Libraries.EconomyClient)
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)
local ResearchClient = require(Players.LocalPlayer.PlayerScripts.Libraries.ResearchClient)
local Sound = require(Players.LocalPlayer.PlayerScripts.Libraries.Sound)

local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NEXT_UNLOCK = "Next unlock"
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
	local stepTitle = title.Text
	-- Item names, numbers and amounts in the step read in their own colours (Shared/TextColors).
	text.RichText = true
	progress.RichText = true
	local textTransparency = text.TextTransparency
	local progressTransparency = progress.TextTransparency
	local checkTransparency = if check:IsA("ImageLabel") then check.ImageTransparency else check.BackgroundTransparency
	local tweens: { Tween } = {}
	local revision = 0
	-- The latest objective, and whether its completion transition is still playing.
	local latest: Onboarding.Snapshot? = nil
	local fading = false
	panel.Visible = false
	check.Visible = false

	local function cancel(): ()
		revision += 1
		fading = false
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
	end

	-- With every goal done: the next level that opens something, or nothing to show.
	local function showUnlock(): ()
		local wallet = EconomyClient.get()
		local level, opened = Unlocks.next(wallet.level, ResearchClient.done())
		if not level or not opened then
			panel.Visible = false
			return
		end
		title.Text = NEXT_UNLOCK
		text.Text = TextColors.highlight(`Level {level}: {Unlocks.describe(opened)}`)
		progress.Text = TextColors.highlight(`{Hud.number(Economy.toReach(wallet.xp, level))} XP to go`)
		panel.Visible = true
	end

	local function show(state: Onboarding.Snapshot): ()
		fading = false
		text.TextTransparency = textTransparency
		progress.TextTransparency = progressTransparency
		check.Visible = false
		if state.done then
			showUnlock()
			return
		end
		title.Text = stepTitle
		text.Text = TextColors.highlight(state.text)
		-- The authored label has room for one short phrase, so progress replaces the step count.
		progress.Text = TextColors.highlight(if state.detail and state.detail ~= ""
			then state.detail
			else `Step {state.step} of {state.total}`)
		panel.Visible = true
	end

	local function render(state: Onboarding.Snapshot): ()
		local before = latest
		if before and state.step < before.step then
			return
		end
		if before and state.step == before.step then
			-- The same goal again: only the server's progress line is news. A snapshot made
			-- from the step attribute carries none and must not wipe it.
			if state.detail ~= nil then
				latest = state
				if not fading then
					show(state)
				end
			end
			return
		end
		latest = state
		cancel()
		if before then
			Sound.play("Step")
		end
		if not before or GuiService.ReducedMotionEnabled or not panel.Visible then
			show(state)
			return
		end
		fading = true
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
			if revision == version and latest then
				show(latest)
			end
		end)
	end

	local function refresh(): ()
		local step = Players.LocalPlayer:GetAttribute("OnboardingStep")
		if typeof(step) == "number" then
			render(Onboarding.snapshot(Onboarding.sanitize(step)))
		elseif latest then
			-- The garden was released (the save menu): the next one starts from its own step.
			cancel()
			latest = nil
			panel.Visible = false
		end
	end
	-- The next unlock moves with XP, levels and finished research.
	local function refreshUnlock(): ()
		if latest and latest.done and not fading then
			showUnlock()
		end
	end
	local remoteConnection = Remotes.Objective.OnClientEvent:Connect(render)
	local attributeConnection = Players.LocalPlayer:GetAttributeChangedSignal("OnboardingStep"):Connect(refresh)
	local economyConnection = EconomyClient.changed:Connect(refreshUnlock)
	local researchConnection = ResearchClient.changed:Connect(refreshUnlock)
	local motionConnection = GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		if GuiService.ReducedMotionEnabled and latest then
			cancel()
			show(latest)
		end
	end)
	hud.Destroying:Once(function()
		cancel()
		remoteConnection:Disconnect()
		attributeConnection:Disconnect()
		economyConnection:Disconnect()
		researchConnection:Disconnect()
		motionConnection:Disconnect()
	end)
	refresh()
end

return Objective
