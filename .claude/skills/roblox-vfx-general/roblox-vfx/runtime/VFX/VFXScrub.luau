-- ModuleScript: <VFX folder>/VFXScrub (e.g. ReplicatedStorage.VFX.VFXScrub)
-- Edit-time tool (like MeshFactory): plays an effect in Studio's Edit mode and
-- freezes it at an exact effect time, so it can be screenshotted and compared
-- frame by frame against a reference. Effects must never require this module.
--
--   local Scrub = require(game.ReplicatedStorage.VFX.VFXScrub)
--   Scrub.Play("SlashImpact", dummy.HumanoidRootPart.CFrame, nil, 0.1)
--   -- take the screenshot now (e.g. Studio MCP screen_capture), then:
--   Scrub.Clear()
--
-- Each Play requires a fresh copy of the whole Effects folder, so source edits
-- show up without restarting Studio, including effects that require other
-- effects. The effect's math.random is seeded; emitter and
-- MeshParticles randomness is not, so particle scatter varies between runs.
-- The ctx built here mirrors VFXPlayer's; keep the two in sync.

local TweenService = game:GetService("TweenService")

local VFXScrub = {}

local effectsFolder = script.Parent:WaitForChild("Effects")
local FOLDER_NAME = "VFXScrub"

function VFXScrub.Clear()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

-- Require a fresh copy so edits since the last require are picked up. The whole
-- Effects folder is copied: require caches by module, so an effect that requires
-- a sibling would otherwise get the stale cached sibling.
local function loadFresh(name)
	assert(effectsFolder:FindFirstChild(name), "VFXScrub: no effect named " .. tostring(name))
	local copyFolder = effectsFolder:Clone()
	copyFolder.Name = "__ScrubEffects"
	copyFolder.Parent = effectsFolder.Parent -- keeps script.Parent.Parent requires working
	local ok, def = pcall(require, copyFolder:FindFirstChild(name))
	copyFolder:Destroy()
	assert(ok, def)
	return def
end

-- Plays `name` and freezes it at effect time `stopAt` (seconds).
--   overrides  optional Params overrides
--   timeScale  playback speed while advancing (default 0.1; lower = more precise)
--   seed       math.random seed (default 7)
-- Returns the frozen effect time and the number of instances created.
function VFXScrub.Play(name, cframe, overrides, stopAt, timeScale, seed)
	VFXScrub.Clear()
	timeScale = timeScale or 0.1
	math.randomseed(seed or 7)

	local def = loadFresh(name)
	local params = table.clone(def.Defaults or {})
	for key, value in overrides or {} do
		params[key] = value
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace

	local frozen = false
	local tweens = {}
	local ctx = {
		CFrame = cframe,
		Params = params,
		Folder = folder,
		TimeScale = timeScale,
	}

	function ctx.Wait(seconds)
		local remaining = seconds
		while remaining > 0 do
			if not folder.Parent then
				coroutine.yield() -- cleared: park this thread forever so it can be collected
			end
			local dt = task.wait()
			if not frozen then
				remaining -= dt * timeScale
			end
		end
		return seconds - remaining -- effect time that actually passed, like VFXPlayer
	end

	function ctx.Tween(instance, seconds, props, style, direction)
		local info = TweenInfo.new(
			seconds / timeScale,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out
		)
		local tween = TweenService:Create(instance, info, props)
		tween:Play()
		table.insert(tweens, tween)
		return tween
	end

	function ctx.Emit(emitter, count)
		emitter.TimeScale = timeScale
		emitter:Emit(count)
	end

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

	-- Camera shake is skipped: a scrub freezes on a fixed capture camera.
	function ctx.Shake() end


	task.spawn(function()
		local ok, err = pcall(def.Play, ctx)
		if not ok then
			warn(("VFXScrub: effect '%s' errored: %s"):format(name, tostring(err)))
		end
	end)

	local clock = 0
	while clock < stopAt do
		clock += task.wait() * timeScale
	end

	-- Freeze: particles, tweens, and MeshParticles (which reads ctx.TimeScale)
	frozen = true
	ctx.TimeScale = 0
	for _, tween in tweens do
		if tween.PlaybackState == Enum.PlaybackState.Playing then
			tween:Pause()
		end
	end
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.TimeScale = 0
		end
	end

	return clock, #folder:GetDescendants()
end

return VFXScrub
