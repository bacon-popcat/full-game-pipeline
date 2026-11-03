-- NowPlaying: the authored card at the top right (HUD.NowPlaying) that names each background
-- track as it starts. MusicController publishes the playing track's name as the `Track`
-- attribute of SoundService.Music; the card slides in from the right, its bars bob for a few
-- seconds, then it slides back out. It sits in the top bar's row, above Roblox's player list.
-- Reduced motion shows and hides it in place, with still bars.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)

-- Seconds the card stays up once in.
local SHOW_FOR = 6
local SLIDE = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local NowPlaying = {}

function NowPlaying.init(hud: ScreenGui)
	local card = Hud.find(hud, "NowPlaying", "Frame")
	local title = Hud.find(hud, "NowPlaying.Title", "TextLabel")
	local bars = Hud.find(hud, "NowPlaying.Bars", "Frame")
	if not card or not card:IsA("Frame") or not title or not title:IsA("TextLabel") or not bars then
		return
	end
	local trove = Trove.new()
	-- The authored spot it rests at; it slides in from past the right edge.
	local rest = card.Position
	local hidden = UDim2.new(1 + card.Size.X.Scale, card.Position.X.Offset, rest.Y.Scale, rest.Y.Offset)
	local barSizes: { [GuiObject]: UDim2 } = {}
	for _, bar in bars:GetChildren() do
		if bar:IsA("GuiObject") then
			barSizes[bar] = bar.Size
		end
	end
	card.Visible = false
	card.Position = hidden
	local shownAt = 0
	local showing = 0

	local function hide(token: number)
		if token ~= showing then
			return
		end
		if GuiService.ReducedMotionEnabled then
			card.Visible = false
			return
		end
		local out = TweenService:Create(card, SLIDE_OUT, { Position = hidden })
		out.Completed:Connect(function()
			if token == showing then
				card.Visible = false
			end
		end)
		out:Play()
	end

	local function show(name: string)
		showing += 1
		local token = showing
		title.Text = name
		shownAt = os.clock()
		card.Visible = true
		if GuiService.ReducedMotionEnabled then
			card.Position = rest
		else
			card.Position = hidden
			TweenService:Create(card, SLIDE, { Position = rest }):Play()
		end
		task.delay(SHOW_FOR, hide, token)
	end

	-- The bars bob like a little equaliser while the card is up.
	trove:Connect(RunService.RenderStepped, function()
		if not card.Visible then
			return
		end
		local t = os.clock() - shownAt
		local index = 0
		for bar, size in barSizes do
			index += 1
			local bob = if GuiService.ReducedMotionEnabled
				then 1
				else 0.55 + 0.45 * math.abs(math.sin(t * (3.1 + index * 1.3) + index))
			bar.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale * bob, size.Y.Offset)
		end
	end)

	task.spawn(function()
		local music = SoundService:WaitForChild("Music", 30)
		if not music then
			return
		end
		local function changed()
			local track = music:GetAttribute("Track")
			if typeof(track) == "string" and track ~= "" then
				show(track)
			end
		end
		trove:Connect(music:GetAttributeChangedSignal("Track"), changed)
		changed()
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return NowPlaying
