-- WeatherController: one camera-local rain emitter and calm lighting requests from the
-- replicated event. Rain stops under cover; reduced motion suppresses lightning flashes.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Lighting = require(Players.LocalPlayer.PlayerScripts.Libraries.Lighting)
local WeatherController = {}
function WeatherController.init()
	local state = ReplicatedStorage:WaitForChild("Weather")
	local trove = Trove.new()
	local cloud = Instance.new("Part")
	cloud.Name = "LocalRain"
	cloud.Size = Vector3.new(60, 1, 60)
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Parent = workspace
	trove:Add(cloud)
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rain.Color = ColorSequence.new(Color3.fromRGB(193, 213, 229))
	-- Stretched along their fall so drops read as soft streaks, not specks.
	rain.Size = NumberSequence.new(0.16)
	rain.Squash = NumberSequence.new(2)
	rain.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rain.Transparency = NumberSequence.new(0.35)
	rain.Lifetime = NumberRange.new(0.6, 0.9)
	rain.Speed = NumberRange.new(40, 48)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(3, 3)
	rain.LightInfluence = 0.5
	rain.Rate = 0
	rain.Parent = cloud
	local event = ""
	local rateTween: Tween? = nil
	local targetRate = 0
	local function setRate(rate: number)
		if targetRate == rate then
			return
		end
		targetRate = rate
		if rateTween then
			rateTween:Cancel()
		end
		local nextTween = TweenService:Create(rain, TweenInfo.new(2, Enum.EasingStyle.Quad), { Rate = rate })
		rateTween = nextTween
		nextTween:Play()
	end
	local function refresh()
		local value, deadline = state:GetAttribute("Event"), state:GetAttribute("EndsAt")
		local wanted = if typeof(value) == "string"
				and typeof(deadline) == "number"
				and deadline > workspace:GetServerTimeNow()
			then value
			else ""
		if wanted == event then
			return
		end
		event = wanted
		Lighting.clear("lightning", 0.5)
		if event == "Rain" or event == "Thunderstorm" then
			Lighting.set(
				"weather",
				if event == "Rain" then Color3.fromRGB(196, 209, 230) else Color3.fromRGB(172, 186, 214),
				if event == "Rain" then -0.1 else -0.18,
				0.05,
				3
			)
		elseif event == "Golden Hour" then
			Lighting.set("weather", Color3.fromRGB(255, 231, 187), 0.03, 0.02, 3)
		else
			Lighting.clear("weather", 3)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local random = Random.new()
	local nextFlash = os.clock() + random:NextNumber(12, 24)
	local elapsed = 1
	trove:Connect(RunService.RenderStepped, function(dt: number)
		local camera = workspace.CurrentCamera
		if camera then
			cloud.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 16, 0))
		end
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		refresh()
		local wet = event == "Rain" or event == "Thunderstorm"
		local character = Players.LocalPlayer.Character
		params.FilterDescendantsInstances = if character then { cloud, character } else { cloud }
		local covered = camera and workspace:Raycast(camera.CFrame.Position, Vector3.new(0, 80, 0), params) ~= nil
		setRate(if camera and wet and not covered then (if GuiService.ReducedMotionEnabled then 120 else 380) else 0)
		if os.clock() >= nextFlash then
			nextFlash = os.clock() + random:NextNumber(12, 24)
			if event == "Thunderstorm" and not GuiService.ReducedMotionEnabled then
				Lighting.set("lightning", Color3.new(1, 1, 1), 0.1, 0, 0.15)
				task.delay(0.25, function()
					Lighting.clear("lightning", 0.7)
				end)
			end
		end
	end)
	trove:Connect(state.AttributeChanged, refresh)
	trove:Connect(script.Destroying, function()
		if rateTween then
			rateTween:Cancel()
		end
		Lighting.clear("weather", 0)
		Lighting.clear("lightning", 0)
		trove:Destroy()
	end)
	refresh()
end
return WeatherController
