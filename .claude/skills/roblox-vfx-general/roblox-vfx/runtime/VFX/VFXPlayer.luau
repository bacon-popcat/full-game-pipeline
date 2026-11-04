-- ModuleScript: <VFX folder>/VFXPlayer (e.g. ReplicatedStorage.VFX.VFXPlayer)
-- Plays effects by name on the client. Each effect module in the sibling Effects folder
-- gets a "ctx" with helpers, so timing respects TimeScale (slow-mo for testing) and
-- cleanup is automatic.
--
--   local VFXPlayer = require(game.ReplicatedStorage.VFX.VFXPlayer)
--   VFXPlayer.Play("SlashImpact", hitCFrame, { Color = Color3.fromRGB(120, 200, 255) })

local TweenService = game:GetService("TweenService")

local VFXShake = require(script.Parent:WaitForChild("VFXShake"))

local VFXPlayer = {}
VFXPlayer.TimeScale = 1 -- read once per play; lower it to watch effects in slow motion

local effectsFolder = script.Parent:WaitForChild("Effects")

local container = Instance.new("Folder")
container.Name = "ActiveVFX"
container.Parent = workspace

local cache = {}

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

function VFXPlayer.Play(name, cframe, overrides)
	local def = getEffect(name)
	local timeScale = VFXPlayer.TimeScale

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
		local info = TweenInfo.new(
			seconds / timeScale,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out
		)
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

	task.spawn(function()
		local ok, err = pcall(def.Play, ctx)
		if not ok then
			warn(("VFXPlayer: effect '%s' errored: %s"):format(name, tostring(err)))
		end
		-- Let particles finish before cleaning up
		ctx.Wait(def.Linger or 1)
		folder:Destroy()
	end)
end

function VFXPlayer.Clear()
	VFXShake.Stop()
	container:ClearAllChildren()
end

return VFXPlayer
