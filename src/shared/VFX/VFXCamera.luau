-- ModuleScript: ReplicatedStorage/Shared/VFX/VFXCamera
-- Locks the camera onto an effect from a fixed angle, so effects can be judged
-- (and screenshotted) from the same side / top / 3/4 views as a reference.
-- Angles are relative to the effect's CFrame: "Front" looks back along its
-- LookVector, "Side" is from its RightVector, "Top" looks straight down.
-- Works in Play mode (client) and in Edit mode, e.g. next to VFXScrub:
--
--   local Cam = require(game.ReplicatedStorage.Shared.VFX.VFXCamera)
--   Cam.Lock(dummy.HumanoidRootPart.CFrame, "Side")      -- or { Yaw = 30, Pitch = 10 }
--   Cam.Lock(cf, "Top", { Distance = 30, FieldOfView = 50 })
--   Cam.Unlock()
--
-- Locking keeps the effect still between plays: same distance, FOV and focus
-- every time, so frame-by-frame comparisons line up.

local VFXCamera = {}

-- Yaw: degrees around the effect's up axis, 0 = in front (along LookVector),
-- 90 = its right side. Pitch: degrees above the horizon.
VFXCamera.Angles = {
	Front = { Yaw = 0, Pitch = 0 },
	Side = { Yaw = 90, Pitch = 0 },
	Back = { Yaw = 180, Pitch = 0 },
	Top = { Yaw = 0, Pitch = 90 },
	ThreeQuarter = { Yaw = 45, Pitch = 30 },
}
-- Order the harness cycles through (nil = free camera)
VFXCamera.Order = { "ThreeQuarter", "Side", "Front", "Top", "Back" }

local DEFAULTS = {
	Distance = 20,
	FieldOfView = 70,
	Height = 2, -- focus point above the effect origin (studs)
}

local saved = nil -- camera state from before the first Lock, restored by Unlock

local function resolve(angle)
	if typeof(angle) == "table" then
		return angle
	end
	local preset = VFXCamera.Angles[angle]
	assert(preset, "VFXCamera: no angle named " .. tostring(angle))
	return preset
end

-- Camera CFrame for viewing `cframe` from `angle` (preset name or {Yaw, Pitch}).
function VFXCamera.CFrameFor(cframe, angle, options)
	local a = resolve(angle)
	local distance = (options and options.Distance) or DEFAULTS.Distance
	local height = (options and options.Height) or DEFAULTS.Height
	local yaw = math.rad(a.Yaw or 0)
	local pitch = math.rad(math.clamp(a.Pitch or 0, -90, 90))

	-- Direction from the focus to the camera, in the effect's space (-Z = LookVector)
	local localDir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
	local dir = cframe:VectorToWorldSpace(localDir)
	local focus = cframe.Position + cframe.UpVector * height
	local position = focus + dir * distance

	-- Looking (nearly) straight down/up: world up is degenerate, so put the
	-- effect's LookVector at the top of the screen instead
	local up = if math.abs(dir:Dot(cframe.UpVector)) > 0.99 then cframe.LookVector else cframe.UpVector
	return CFrame.lookAt(position, focus, up)
end

function VFXCamera.Lock(cframe, angle, options)
	local camera = workspace.CurrentCamera
	if not saved then
		saved = { CameraType = camera.CameraType, FieldOfView = camera.FieldOfView }
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = (options and options.FieldOfView) or DEFAULTS.FieldOfView
	camera.CFrame = VFXCamera.CFrameFor(cframe, angle, options)
end

function VFXCamera.Unlock()
	if not saved then
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = saved.CameraType
	camera.FieldOfView = saved.FieldOfView
	saved = nil
end

function VFXCamera.IsLocked()
	return saved ~= nil
end

return VFXCamera
