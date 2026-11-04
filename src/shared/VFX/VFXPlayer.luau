-- ModuleScript: ReplicatedStorage/Shared/VFX/VFXPlayer
-- Plays effects by name. Each effect gets a "ctx" with helpers so that
-- timing respects TimeScale (slow-mo in the harness) and cleanup is automatic.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ForgeBridge = require(script.Parent:WaitForChild("ForgeBridge"))
local VFXCamera = require(script.Parent:WaitForChild("VFXCamera"))
local VFXShake = require(script.Parent:WaitForChild("VFXShake"))

local VFXPlayer = {}
VFXPlayer.TimeScale = 1
-- Camera lock (client only): when set, every Play points the camera at the
-- effect from this angle (a VFXCamera preset name or {Yaw, Pitch}). Set it with
-- VFXPlayer.SetCamera; nil = free camera.
VFXPlayer.CameraAngle = nil
VFXPlayer.CameraOptions = nil

local effectsFolder = script.Parent:WaitForChild("Effects")

local container = Instance.new("Folder")
container.Name = "ActiveVFX"
container.Parent = workspace

local cache = {}
local activeForge = {} -- [Forge env] = true, for every Forge layer still playing

local function getEffect(name)
	if cache[name] then
		return cache[name]
	end
	local moduleScript = effectsFolder:FindFirstChild(name)
	assert(moduleScript, "VFXPlayer: no effect named " .. tostring(name))
	cache[name] = require(moduleScript)
	return cache[name]
end

local function resolveParams(def, overrides)
	local params = table.clone(def.Defaults or {})
	if overrides then
		for key, value in overrides do
			params[key] = value
		end
	end
	return params
end

-- Lock the camera to `angle` for every following Play (nil unlocks). If `cframe`
-- is given, the camera moves there now instead of waiting for the next Play.
function VFXPlayer.SetCamera(angle, options, cframe)
	VFXPlayer.CameraAngle = angle
	VFXPlayer.CameraOptions = options
	if angle == nil then
		VFXCamera.Unlock()
	elseif cframe and RunService:IsClient() then
		VFXCamera.Lock(cframe, angle, options)
	end
end

function VFXPlayer.Play(name, cframe, overrides)
	local def = getEffect(name)
	local timeScale = VFXPlayer.TimeScale

	if VFXPlayer.CameraAngle and RunService:IsClient() then
		VFXCamera.Lock(cframe, VFXPlayer.CameraAngle, VFXPlayer.CameraOptions)
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = container

	local ctx = {
		CFrame = cframe,
		Params = resolveParams(def, overrides),
		Folder = folder,
		TimeScale = timeScale,
	}

	-- Wait in "effect time" (stretches in slow-mo). Returns the effect time that
	-- actually passed, which is usually a bit more than asked (frame granularity).
	function ctx.Wait(seconds)
		return task.wait(seconds / timeScale) * timeScale
	end

	-- Tween in "effect time"
	function ctx.Tween(instance, seconds, props, style, direction)
		local info =
			TweenInfo.new(seconds / timeScale, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
		local tween = TweenService:Create(instance, info, props)
		tween:Play()
		return tween
	end

	-- Burst particles, respecting slow-mo
	function ctx.Emit(emitter, count)
		emitter.TimeScale = timeScale
		emitter:Emit(count)
	end

	-- Invisible anchored part to hang attachments/emitters/lights on
	function ctx.Anchor(at)
		local part = Instance.new("Part")
		part.Name = "Anchor"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.one * 0.1
		part.CFrame = at or cframe
		part.Parent = folder
		return part
	end

	-- Shake the local camera (rotation only, effect time, distance-gated; see VFXShake).
	-- magnitude in degrees, duration in effect seconds. options: Roughness, FadeIn,
	-- Position (default this effect's position), Range (default 250 studs).
	-- Effects replicated from other players should pass a Shake = false override.
	function ctx.Shake(magnitude, duration, options)
		options = options or {}
		VFXShake.Start({
			Magnitude = magnitude,
			Duration = duration,
			Roughness = options.Roughness,
			FadeIn = options.FadeIn,
			Position = options.Position or cframe.Position,
			Range = options.Range,
			TimeScale = timeScale,
		})
	end

	-- Play a VFX Forge template (Shared.VFX.ForgeAssets) as a layer, retimed to
	-- this play's TimeScale. Non-blocking; see ForgeBridge for the options.
	-- Returns Forge's env: env.Finished:await() waits until the layer is done.
	local envs = {}
	function ctx.Forge(template, at, options)
		local _, env = ForgeBridge.Emit(template, at or cframe, folder, timeScale, options)
		envs[env] = true
		activeForge[env] = true
		env.Finished:finally(function()
			envs[env] = nil
			activeForge[env] = nil
		end)
		return env
	end

	task.spawn(function()
		local ok, err = pcall(def.Play, ctx)
		if not ok then
			warn(("VFXPlayer: effect '%s' errored: %s"):format(name, tostring(err)))
		end
		-- Let particles finish before cleaning up
		ctx.Wait(def.Linger or 1)
		-- Forge keeps some layer parts outside the folder (beam clones, cached
		-- parts in Terrain); stop any layer that outlived Linger so they go too.
		for env in envs do
			env.Clear()
		end
		folder:Destroy()
	end)
end

function VFXPlayer.Clear()
	VFXShake.Stop()
	for env in activeForge do
		env.Clear()
	end
	container:ClearAllChildren()
end

return VFXPlayer
