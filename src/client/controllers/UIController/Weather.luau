-- Weather: the authored event banner reads the replicated server-time deadline.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)
local Weather = {}
function Weather.init(hud: ScreenGui)
	local frame = Hud.find(hud, "Weather", "Frame")
	local title = Hud.find(hud, "Weather.Title", "TextLabel")
	local time = Hud.find(hud, "Weather.Time", "TextLabel")
	if
		not frame
		or not frame:IsA("Frame")
		or not title
		or not title:IsA("TextLabel")
		or not time
		or not time:IsA("TextLabel")
	then
		return
	end
	local state = ReplicatedStorage:WaitForChild("Weather")
	local elapsed = 1
	local connection = RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		local event = state:GetAttribute("Event")
		local endsAt = state:GetAttribute("EndsAt")
		local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		frame.Visible = typeof(event) == "string" and event ~= "" and left > 0
		if frame.Visible and typeof(event) == "string" then
			title.Text = event
			time.Text = Hud.time(left)
		end
	end)
	hud.Destroying:Once(function()
		connection:Disconnect()
	end)
end
return Weather
