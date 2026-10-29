-- WeatherService: owns the server weather clock. Bonus time is an integrated clock, so
-- crops bank exactly the rain they experienced and keep that credit across saves.
-- ReplicatedStorage.Weather publishes Event and EndsAt (GetServerTimeNow seconds).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeatherService = {}
local random = Random.new()
local state = Instance.new("Folder")
state.Name = "Weather"
state:SetAttribute("Event", "")
state:SetAttribute("EndsAt", 0)
state.Parent = ReplicatedStorage
local event = ""
local bonus = 0
local updatedAt = workspace:GetServerTimeNow()
local endsAt = 0
local DURATIONS = { Rain = 120, Thunderstorm = 90, ["Golden Hour"] = 60 }

function WeatherService.speed(): number
	return if (event == "Rain" or event == "Thunderstorm") and workspace:GetServerTimeNow() < endsAt then 1.5 else 1
end

function WeatherService.bonusNow(): number
	local now = workspace:GetServerTimeNow()
	if event == "Rain" or event == "Thunderstorm" then
		bonus += math.max(0, math.min(now, endsAt) - updatedAt) * 0.5
	end
	updatedAt = now
	return bonus
end

function WeatherService.current(): string
	return if workspace:GetServerTimeNow() < endsAt then event else ""
end

function WeatherService.init()
	local nextAt = workspace:GetServerTimeNow() + random:NextInteger(480, 720)
	while true do
		task.wait(math.max(0, nextAt - workspace:GetServerTimeNow()))
		WeatherService.bonusNow()
		nextAt = workspace:GetServerTimeNow() + random:NextInteger(480, 720)
		event = ({ "Rain", "Thunderstorm", "Golden Hour" })[random:NextInteger(1, 3)]
		endsAt = workspace:GetServerTimeNow() + DURATIONS[event]
		state:SetAttribute("EndsAt", endsAt)
		state:SetAttribute("Event", event)
		task.wait(DURATIONS[event])
		WeatherService.bonusNow()
		event = ""
		state:SetAttribute("Event", "")
		state:SetAttribute("EndsAt", 0)
	end
end
return WeatherService
