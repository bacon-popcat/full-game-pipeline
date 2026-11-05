--!strict
-- LightingController: drives the lighting on this client. Each frame it sets the time of day
-- from Shared/DayCycle (server time, so every player sees the same sky), and it applies the
-- player's saved lighting quality. SettingsService mirrors that as the LightingQuality
-- attribute on the local Player; until it arrives the Lighting library's default preset
-- stands. The Settings screen applies a choice at once and asks the server to save it, so the
-- attribute echo that follows is the same preset again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Lighting = require(Players.LocalPlayer.PlayerScripts.Libraries.Lighting)
local LightingController = {}

function LightingController.init()
	local player = Players.LocalPlayer
	local function apply()
		local quality = player:GetAttribute("LightingQuality")
		if typeof(quality) == "string" and quality ~= Lighting.quality() then
			Lighting.setQuality(quality)
		end
	end
	player:GetAttributeChangedSignal("LightingQuality"):Connect(apply)
	apply()
	-- A number FixedClock attribute on Lighting holds the clock there, for checking one time
	-- of day in Studio; nothing in the game sets it.
	local service = game:GetService("Lighting")
	RunService.Heartbeat:Connect(function()
		local fixed = service:GetAttribute("FixedClock")
		Lighting.setClock(if typeof(fixed) == "number" then fixed else DayCycle.clock(workspace:GetServerTimeNow()))
	end)
end

return LightingController
