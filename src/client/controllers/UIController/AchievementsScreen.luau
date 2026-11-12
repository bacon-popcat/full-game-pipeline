-- AchievementsScreen: the Achievements window (HUD.Achievements), opened from the Menu. One
-- Assets.UI.Progress.Achievement row per Shared/Progress achievement, in its order: name, goal,
-- progress towards it from this garden's stats and the reward. Unlocked rows turn gold and read
-- "Unlocked". ProgressService decides every unlock and pays the reward; this only shows them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progress = require(ReplicatedStorage.Shared.Progress)
local TextColors = require(ReplicatedStorage.Shared.TextColors)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local ProgressClient = require(Libraries.ProgressClient)

local GOLD = Color3.fromRGB(255, 214, 102)
local LOCKED = Color3.fromRGB(120, 120, 136)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(190, 190, 205)

type Row = {
	achievement: Progress.Achievement,
	frame: Frame,
	name: TextLabel,
	count: TextLabel,
	fill: Frame,
	medal: Frame,
	bars: { Frame },
}

local AchievementsScreen = {}

-- "1h 05m" from an hour, else "12m": playtime goals are whole hours or minutes.
local function amount(stat: Progress.Stat?, value: number): string
	if stat and stat.format == "time" then
		local minutes = math.floor(value / 60)
		return if minutes >= 60 then string.format("%dh %02dm", minutes // 60, minutes % 60) else `{minutes}m`
	end
	return Hud.number(value)
end

local function rewardText(reward: Progress.Reward): string
	return TextColors.reward(reward.coins, reward.xp, Hud.number)
end

local function paintMedal(medal: Frame, color: Color3)
	for _, part in medal:GetDescendants() do
		if part:IsA("Frame") and part.BackgroundTransparency < 1 then
			part.BackgroundColor3 = color
		elseif part:IsA("UIStroke") then
			part.Color = color
		end
	end
end

function AchievementsScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Achievements.Body.List", "ScrollingFrame")
	local summary = Hud.find(hud, "Achievements.Body.Summary", "TextLabel")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Achievement", "Frame")
	if not list or not summary or not summary:IsA("TextLabel") or not template or not template:IsA("Frame") then
		return
	end
	local trove = Trove.new()
	local rows: { Row } = {}
	for order, achievement in Progress.ACHIEVEMENTS do
		local frame = template:Clone()
		local name = Hud.find(frame, "Name", "TextLabel")
		local description = Hud.find(frame, "Description", "TextLabel")
		local count = Hud.find(frame, "Count", "TextLabel")
		local fill = Hud.find(frame, "Track.Fill", "Frame")
		local reward = Hud.find(frame, "Reward", "TextLabel")
		local medal = Hud.find(frame, "Icon", "Frame")
		if not (name and description and count and fill and reward and medal) then
			frame:Destroy()
			return
		end
		assert(
			name:IsA("TextLabel") and description:IsA("TextLabel") and count:IsA("TextLabel"),
			"Achievement row labels"
		)
		assert(reward:IsA("TextLabel") and fill:IsA("Frame") and medal:IsA("Frame"), "Achievement row parts")
		frame.Name = achievement.id
		frame.LayoutOrder = order
		name.Text = achievement.name
		description.RichText = true
		reward.RichText = true
		description.Text = TextColors.highlight(achievement.description)
		reward.Text = rewardText(achievement.reward)
		local bars = {}
		local brackets = frame:FindFirstChild("Brackets")
		if brackets then
			for _, bar in brackets:GetDescendants() do
				if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
					table.insert(bars, bar)
				end
			end
		end
		frame.Parent = list
		trove:Add(frame)
		table.insert(rows, {
			achievement = achievement,
			frame = frame,
			name = name,
			count = count,
			fill = fill,
			medal = medal,
			bars = bars,
		})
	end

	local function render()
		local snapshot = ProgressClient.get()
		local unlocked = 0
		for _, row in rows do
			local achievement = row.achievement
			local done = snapshot.achievements[achievement.id] == true
			local value = math.min(ProgressClient.stat(achievement.stat), achievement.goal)
			local stat = Progress.getStat(achievement.stat)
			if done then
				unlocked += 1
			end
			row.count.Text = if done then "Unlocked" else `{amount(stat, value)} / {amount(stat, achievement.goal)}`
			row.count.TextColor3 = if done then GOLD else MUTED
			row.name.TextColor3 = if done then GOLD else WHITE
			row.fill.Size = UDim2.fromScale(if done then 1 else value / achievement.goal, 1)
			paintMedal(row.medal, if done then GOLD else LOCKED)
			for _, bar in row.bars do
				bar.BackgroundColor3 = if done then GOLD else LOCKED
			end
		end
		summary.Text = `{unlocked} of {#rows} unlocked`
	end

	local window = HubWindow.bind(hud, "Achievements", {}, render)
	if not window then
		trove:Destroy()
		return
	end
	trove:Connect(ProgressClient.changed, function()
		if window.isOpen() then
			render()
		end
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
	render()
end

return AchievementsScreen
