-- ModuleScript: ReplicatedStorage/Shared/VFX/VFXShake
-- Camera shake for effects, used through ctx.Shake (VFXPlayer). Client only.
--
-- Rotation only, summed over every active shake. The offset is taken back off just before
-- the camera scripts run and put on again just after them, so the player's camera never
-- builds on last frame's shake and drifts (references/camera-world.md). Every shake ends on
-- its own after its duration; Stop() ends them all (VFXPlayer.Clear calls it).
--
--   VFXShake.Start({ Magnitude = 3, Duration = 1.2, Roughness = 8, FadeIn = 0.03,
--       Position = hitPos, Range = 250, TimeScale = ctx.TimeScale })

local RunService = game:GetService("RunService")

local VFXShake = {}

local UNDO_STEP = "VFXShakeUndo"
local APPLY_STEP = "VFXShakeApply"

local shakes = {}
local lastOffset = CFrame.identity
local bound = false

local function unbind()
	if bound then
		RunService:UnbindFromRenderStep(UNDO_STEP)
		RunService:UnbindFromRenderStep(APPLY_STEP)
		bound = false
	end
end

local function undo()
	local camera = workspace.CurrentCamera
	if camera and lastOffset ~= CFrame.identity then
		camera.CFrame *= lastOffset:Inverse()
	end
	lastOffset = CFrame.identity
end

local function apply()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	local pitch, yaw, roll = 0, 0, 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local t = (now - s.Start) * s.TimeScale -- effect time, so slow-mo slows the shake
		if t >= s.Duration then
			table.remove(shakes, i)
		else
			-- quick rise, then a squared fade to zero
			local rise = s.FadeIn > 0 and math.min(t / s.FadeIn, 1) or 1
			local fall = 1 - math.max(t - s.FadeIn, 0) / math.max(s.Duration - s.FadeIn, 1e-3)
			local k = s.Magnitude * s.Falloff * rise * fall * fall
			local n = t * s.Roughness
			pitch += math.noise(s.Seed, n, 0.5) * k
			yaw += math.noise(s.Seed + 17.3, n, 0.5) * k
			roll += math.noise(s.Seed + 41.9, n, 0.5) * k * 0.5
		end
	end
	if camera and #shakes > 0 then
		lastOffset = CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
		camera.CFrame *= lastOffset
	elseif #shakes == 0 then
		unbind()
	end
end

-- options: Magnitude (degrees), Duration (effect seconds), Roughness (noise speed, 3-50),
-- FadeIn (effect seconds), Position + Range (no shake beyond Range studs from the camera,
-- weaker toward it), TimeScale (the play's slow-mo).
function VFXShake.Start(options)
	if not RunService:IsClient() then
		return
	end
	local camera = workspace.CurrentCamera
	local falloff = 1
	if options.Position and camera then
		local range = options.Range or 250
		local distance = (camera.CFrame.Position - options.Position).Magnitude
		if distance >= range then
			return
		end
		falloff = 1 - 0.7 * distance / range
	end
	table.insert(shakes, {
		Start = os.clock(),
		Magnitude = options.Magnitude or 1,
		Duration = math.max(options.Duration or 0.5, 1e-3),
		Roughness = options.Roughness or 10,
		FadeIn = options.FadeIn or 0.02,
		TimeScale = math.max(options.TimeScale or 1, 1e-3),
		Falloff = falloff,
		Seed = math.random() * 1000,
	})
	if not bound then
		bound = true
		RunService:BindToRenderStep(UNDO_STEP, Enum.RenderPriority.Camera.Value - 1, undo)
		RunService:BindToRenderStep(APPLY_STEP, Enum.RenderPriority.Camera.Value + 1, apply)
	end
end

function VFXShake.Stop()
	table.clear(shakes)
	undo()
	unbind()
end

return VFXShake
