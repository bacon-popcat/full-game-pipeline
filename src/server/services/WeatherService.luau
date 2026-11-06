-- WeatherService: owns the server weather clock; the events themselves live in Shared/World/Weather.
-- Bonus time is an integrated clock, so crops bank exactly the extra growth they experienced and
-- keep that credit across saves.
-- ReplicatedStorage.Weather publishes Event and EndsAt (GetServerTimeNow seconds).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Weather = require(ReplicatedStorage.Shared.World.Weather)
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

local function growth(): number
	local def = Weather.get(event)
	return if def then def.growth else 0
end

function WeatherService.speed(): number
	return if workspace:GetServerTimeNow() < endsAt then 1 + growth() else 1
end

function WeatherService.bonusNow(): number
	local now = workspace:GetServerTimeNow()
	bonus += math.max(0, math.min(now, endsAt) - updatedAt) * growth()
	updatedAt = now
	return bonus
end

function WeatherService.current(): string
	return if workspace:GetServerTimeNow() < endsAt then event else ""
end

-- The current event's definition, or nil when clear.
function WeatherService.currentEvent(): Weather.Event?
	return Weather.get(WeatherService.current())
end

function WeatherService.init()
	local nextAt = workspace:GetServerTimeNow() + random:NextInteger(Weather.GAP_MIN, Weather.GAP_MAX)
	while true do
		task.wait(math.max(0, nextAt - workspace:GetServerTimeNow()))
		WeatherService.bonusNow()
		event = Weather.pick(random)
		local duration = Weather.EVENTS[event].duration
		endsAt = workspace:GetServerTimeNow() + duration
		state:SetAttribute("EndsAt", endsAt)
		state:SetAttribute("Event", event)
		task.wait(duration)
		WeatherService.bonusNow()
		event = ""
		state:SetAttribute("Event", "")
		state:SetAttribute("EndsAt", 0)
		nextAt = workspace:GetServerTimeNow() + random:NextInteger(Weather.GAP_MIN, Weather.GAP_MAX)
	end
end
return WeatherService
