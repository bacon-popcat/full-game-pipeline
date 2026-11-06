-- DayClock: a small bracketed card (UIController/Panel) in the top right corner showing the world's time of day (Shared/DayCycle),
-- a sun or moon dial and a bar of how far through the day or night it is. Uses HUD.DayClock when
-- the place file authors one (Icon, Time, Phase, Bar.Fill); otherwise builds its own.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Panel = require(script.Parent.Panel)

local DayClock = {}

local FONT = Panel.FONT
local DAY = Color3.fromRGB(250, 211, 112)
local NIGHT = Color3.fromRGB(160, 178, 232)

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Size = size
	text.Position = position
	text.FontFace = FONT
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Right
	text.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize
	limit.Parent = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = text
	return text
end

local function build(hud: ScreenGui): Frame
	local frame = Instance.new("Frame")
	frame.Name = "DayClock"
	-- In the very top right corner; the music button (MusicPlayer) sits under it.
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -12, 0, 12)
	frame.Size = UDim2.fromOffset(150, 56)
	frame.ZIndex = 5
	Panel.apply(frame, 9, 2)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, -3)
	icon.Size = UDim2.fromOffset(28, 28)
	icon.BackgroundColor3 = DAY
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = icon
	icon.Parent = frame
	label(frame, "Time", UDim2.new(1, -50, 0, 26), UDim2.fromOffset(40, 4), 24)
	label(frame, "Phase", UDim2.new(1, -50, 0, 14), UDim2.fromOffset(40, 29), 13)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 10, 1, -8)
	bar.Size = UDim2.new(1, -20, 0, 3)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BackgroundTransparency = 0.8
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = DAY
	fill.BorderSizePixel = 0
	fill.Parent = bar
	frame.Parent = hud
	return frame
end

local function phaseName(hour: number): string
	if hour >= DayCycle.DAWN and hour < DayCycle.DAWN + 1.5 then
		return "Dawn"
	elseif hour >= DayCycle.DAWN and hour < 12 then
		return "Morning"
	elseif hour >= 12 and hour < DayCycle.DUSK - 1.5 then
		return "Afternoon"
	elseif hour >= DayCycle.DUSK - 1.5 and hour < DayCycle.DUSK then
		return "Dusk"
	end
	return "Night"
end

function DayClock.init(hud: ScreenGui)
	local frame = hud:FindFirstChild("DayClock") or build(hud)
	local icon = frame:FindFirstChild("Icon") :: GuiObject?
	local time = frame:FindFirstChild("Time") :: TextLabel?
	local phase = frame:FindFirstChild("Phase") :: TextLabel?
	local bar = frame:FindFirstChild("Bar")
	local fill = bar and bar:FindFirstChild("Fill") :: GuiObject?
	local elapsed = 1
	local connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local now = workspace:GetServerTimeNow()
		local hour = DayCycle.clock(now)
		local cycle = (now % DayCycle.LENGTH) / DayCycle.LENGTH
		local isDay = cycle < DayCycle.DAYLIGHT
		local progress = if isDay
			then cycle / DayCycle.DAYLIGHT
			else (cycle - DayCycle.DAYLIGHT) / (1 - DayCycle.DAYLIGHT)
		local h = math.floor(hour)
		local m = math.floor((hour - h) * 60)
		local suffix = if h < 12 then "AM" else "PM"
		local h12 = if h % 12 == 0 then 12 else h % 12
		local colour = if isDay then DAY else NIGHT
		if time then
			time.Text = string.format("%d:%02d %s", h12, m, suffix)
		end
		if phase then
			phase.Text = phaseName(hour)
			phase.TextColor3 = colour
		end
		if icon then
			icon.BackgroundColor3 = colour
		end
		if fill then
			fill.Size = UDim2.fromScale(progress, 1)
			fill.BackgroundColor3 = colour
		end
	end)
	hud.Destroying:Once(function()
		connection:Disconnect()
	end)
end

return DayClock
