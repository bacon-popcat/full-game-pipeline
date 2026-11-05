-- StatsScreen: the Stats window (HUD.Stats), opened from the Menu. A "Now" heading (level, coins
-- in hand, research finished) from the live wallet and research, then "All time" with every
-- Shared/Progress stat in its order, from this garden's ProgressSync. Rows are clones of
-- Assets.UI.Progress.Heading and Stat. Time played keeps counting while the window is open.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Progress = require(ReplicatedStorage.Shared.Progress)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local ProgressClient = require(Libraries.ProgressClient)

type Line = { name: string, value: () -> string }

local StatsScreen = {}

local function duration(seconds: number): string
	local total = math.floor(seconds)
	local hours, minutes = total // 3600, (total // 60) % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm %02ds", minutes, total % 60)
end

local function format(stat: Progress.Stat, value: number): string
	if stat.format == "time" then
		return duration(value)
	elseif stat.format == "coins" then
		return Hud.number(value) .. " coins"
	end
	return Hud.number(value)
end

function StatsScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Stats.Body.List", "ScrollingFrame")
	local rowTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Stat", "Frame")
	local headingTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Heading", "Frame")
	if not list or not rowTemplate or not headingTemplate then
		return
	end
	local trove = Trove.new()
	local order = 0
	local values: { { label: TextLabel, value: () -> string } } = {}

	local function heading(text: string)
		local frame = headingTemplate:Clone()
		order += 1
		frame.LayoutOrder = order
		local name = frame:FindFirstChild("Name")
		if name and name:IsA("TextLabel") then
			name.Text = text
		end
		frame.Parent = list
		trove:Add(frame)
	end
	local function line(each: Line)
		local frame = rowTemplate:Clone()
		order += 1
		frame.LayoutOrder = order
		local name = frame:FindFirstChild("Name")
		local value = frame:FindFirstChild("Value")
		if not (name and name:IsA("TextLabel") and value and value:IsA("TextLabel")) then
			frame:Destroy()
			return
		end
		name.Text = each.name
		frame.Parent = list
		trove:Add(frame)
		table.insert(values, { label = value, value = each.value })
	end

	heading("Now")
	line({
		name = "Level",
		value = function()
			return tostring(EconomyClient.get().level)
		end,
	})
	line({
		name = "Coins",
		value = function()
			return Hud.number(EconomyClient.get().coins)
		end,
	})
	heading("All time")
	for _, stat in Progress.STATS do
		line({
			name = stat.name,
			value = function()
				return format(stat, ProgressClient.stat(stat.id))
			end,
		})
	end

	local function render()
		for _, each in values do
			each.label.Text = each.value()
		end
	end
	local window = HubWindow.bind(hud, "Stats", {}, render)
	if not window then
		trove:Destroy()
		return
	end
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed >= 1 and window.isOpen() then
			elapsed = 0
			render()
		end
	end)
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

return StatsScreen
