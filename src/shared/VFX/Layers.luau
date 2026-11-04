-- ModuleScript: ReplicatedStorage/Shared/VFX/Layers
-- Helpers for building effect layers the way the skill's design guidance describes:
-- many single-sprite emitters, each with its black, dim or white twin, timed in place.
-- Effects may require this module (it only builds instances under what you pass in).
--
--   local Layers = require(script.Parent.Parent:WaitForChild("Layers"))
--   local star = Layers.Emitter(att, {
--   	Texture = ASSETS.ImpactStar,          -- a string id, or a Textures entry { Id, Grid }
--   	Lifetime = { 0.1, 0.15 },              -- number or { min, max }
--   	Size = { { 0, 6, 1 }, { 0.25, 11, 2 }, { 1, 12 } }, -- number or { time, value, envelope }
--   	Color = p.Color,                       -- Color3 or { { time, Color3 }, ... }
--   	LightEmission = -1, Brightness = 5, ZOffset = 1,
--   })
--   local black = Layers.Black(star)          -- same emitter, black, a step in front
--   Layers.Timeline(ctx, { { 0, function() ... end }, { 0.03, function() ctx.Emit(star, 3) ... end } })
--
-- Spec tables take the property names of the instance. Values are converted to the type
-- the property holds: a number or { { time, value, envelope? } } -> NumberSequence; a
-- Color3 or { { time, Color3 } } -> ColorSequence; a number or { min, max } ->
-- NumberRange; a number or { x, y } -> Vector2; an enum item's name ("VelocityParallel")
-- -> the EnumItem. Extra keys:
--   Flat = true       lie in the attachment's XZ plane (VelocityPerpendicular, Top,
--                     no spread, Speed 0.01 unless given)
--   Texture = entry   a Textures entry sets the flipbook layout from its Grid (OneShot
--                     unless FlipbookMode says otherwise)
-- Emitters default to Rate 0, Speed 0 and LightInfluence 0 (self-lit).

local Layers = {}

local ENUMS = {
	Orientation = Enum.ParticleOrientation,
	EmissionDirection = Enum.NormalId,
	Shape = Enum.ParticleEmitterShape,
	ShapeStyle = Enum.ParticleEmitterShapeStyle,
	ShapeInOut = Enum.ParticleEmitterShapeInOut,
	FlipbookLayout = Enum.ParticleFlipbookLayout,
	FlipbookMode = Enum.ParticleFlipbookMode,
	TextureMode = Enum.TextureMode,
	Material = Enum.Material,
	Face = Enum.NormalId,
}
local GRIDS = {
	[2] = Enum.ParticleFlipbookLayout.Grid2x2,
	[4] = Enum.ParticleFlipbookLayout.Grid4x4,
	[8] = Enum.ParticleFlipbookLayout.Grid8x8,
}

Layers.BLACK = Color3.new(0, 0, 0)
Layers.WHITE = Color3.new(1, 1, 1)

-- number, NumberSequence or { { time, value, envelope? }, ... } -> NumberSequence
function Layers.Seq(value)
	if typeof(value) == "NumberSequence" then
		return value
	elseif type(value) == "number" then
		return NumberSequence.new(value)
	end
	local keypoints = table.create(#value)
	for i, key in value do
		keypoints[i] = NumberSequenceKeypoint.new(key[1], key[2], key[3] or 0)
	end
	return NumberSequence.new(keypoints)
end

-- Color3, ColorSequence or { { time, Color3 }, ... } -> ColorSequence
function Layers.Colors(value)
	if typeof(value) == "ColorSequence" then
		return value
	elseif typeof(value) == "Color3" then
		return ColorSequence.new(value)
	end
	local keypoints = table.create(#value)
	for i, key in value do
		keypoints[i] = ColorSequenceKeypoint.new(key[1], key[2])
	end
	return ColorSequence.new(keypoints)
end

-- number, NumberRange or { min, max } -> NumberRange
function Layers.Range(value)
	if typeof(value) == "NumberRange" then
		return value
	elseif type(value) == "number" then
		return NumberRange.new(value)
	end
	return NumberRange.new(value[1], value[2])
end

-- Converts `value` to the type the property already holds (so Size is a NumberSequence on
-- an emitter and a Vector3 on a part).
local function convert(instance, key, value)
	local current = typeof(instance[key])
	if current == "NumberSequence" then
		return Layers.Seq(value)
	elseif current == "ColorSequence" then
		return Layers.Colors(value)
	elseif current == "NumberRange" then
		return Layers.Range(value)
	elseif current == "Vector2" and typeof(value) ~= "Vector2" then
		return if type(value) == "number" then Vector2.new(value, value) else Vector2.new(value[1], value[2])
	elseif type(value) == "string" and current == "EnumItem" then
		local enum = if key == "Shape" and instance:IsA("BasePart") then Enum.PartType else ENUMS[key]
		return enum[value]
	end
	return value
end

-- Sets every property in `spec` on `instance` (with the conversions above).
function Layers.Apply(instance, spec)
	local isEmitter = instance:IsA("ParticleEmitter")
	if spec.Flat then
		instance.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		instance.EmissionDirection = Enum.NormalId.Top
		instance.SpreadAngle = Vector2.zero
		if spec.Speed == nil then
			instance.Speed = NumberRange.new(0.01)
		end
	end
	for key, value in spec do
		if key == "Flat" then
			continue
		elseif key == "Texture" and type(value) == "table" then
			instance.Texture = value.Id
			if isEmitter and spec.FlipbookLayout == nil then
				instance.FlipbookLayout = GRIDS[value.Grid] or Enum.ParticleFlipbookLayout.None
				if value.Grid and spec.FlipbookMode == nil then
					instance.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
				end
			end
		else
			instance[key] = convert(instance, key, value)
		end
	end
	return instance
end

-- A burst ParticleEmitter under `parent` (an Attachment, or a part for shaped emission).
function Layers.Emitter(parent, spec)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Speed = NumberRange.new(0)
	e.LightInfluence = 0
	Layers.Apply(e, spec)
	e.Parent = parent
	return e
end

-- A copy of `emitter` with some properties changed (same texture, curves and lifetime
-- unless `changes` says otherwise), parented beside it.
function Layers.Twin(emitter, changes)
	local copy = emitter:Clone()
	Layers.Apply(copy, changes or {})
	copy.Parent = emitter.Parent
	return copy
end

-- The black twin: solid ink at the same size, life and count, a step in front (or `zStep`).
-- Twins of a lopsided shape line up only when Rotation is one value and RotSpeed is shared.
function Layers.Black(emitter, zStep, changes)
	local spec = {
		Color = Layers.BLACK,
		Brightness = 1,
		LightEmission = 0,
		ZOffset = emitter.ZOffset + (zStep or 0.25),
	}
	for key, value in changes or {} do
		spec[key] = value
	end
	return Layers.Twin(emitter, spec)
end

-- A dim twin of the same hue behind the bright copy, living a little longer, so the shape
-- gets a darker halo step without a black layer.
function Layers.Dim(emitter, brightness, changes)
	local life = emitter.Lifetime
	local spec = {
		Brightness = brightness or 0.4,
		LightEmission = 0,
		ZOffset = emitter.ZOffset - 0.1,
		Lifetime = NumberRange.new(life.Min * 1.15, life.Max * 1.15),
	}
	for key, value in changes or {} do
		spec[key] = value
	end
	return Layers.Twin(emitter, spec)
end

-- A small white-hot copy in front: the thin hottest shape of the three-value stack.
function Layers.White(emitter, changes)
	local spec = {
		Color = Layers.WHITE,
		LightEmission = 0,
		ZOffset = emitter.ZOffset + 1,
	}
	for key, value in changes or {} do
		spec[key] = value
	end
	return Layers.Twin(emitter, spec)
end

-- Bursts `count` and, for lingering layers, slows them (`slow` 0.6-0.95) while the core
-- stays at the play's speed.
function Layers.Emit(ctx, emitter, count, slow)
	ctx.Emit(emitter, count)
	if slow then
		emitter.TimeScale = ctx.TimeScale * slow
	end
end

function Layers.Attachment(parent, cframe)
	local a = Instance.new("Attachment")
	a.CFrame = cframe or CFrame.identity
	a.Parent = parent
	return a
end

-- An anchored, non-colliding, shadowless part in ctx.Folder.
function Layers.Part(ctx, spec)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	Layers.Apply(part, spec or {})
	part.Parent = ctx.Folder
	return part
end

-- Makes a cloned mesh/part safe to show: anchored, no collision, query, touch or shadow.
function Layers.Quiet(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- A PointLight (no shadows) under `parent`.
function Layers.Light(parent, spec)
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Brightness = 0
	Layers.Apply(light, spec)
	light.Parent = parent
	return light
end

-- Flashes a light and fades it while its Range grows: Brightness b -> 0 and Range
-- r0 -> r1 over `time` effect seconds (Range is capped at Roblox's 60).
function Layers.Pop(ctx, light, brightness, range0, range1, time)
	range0, range1 = math.min(range0, 60), math.min(range1, 60)
	light.Brightness = brightness
	light.Range = range0
	ctx.Tween(light, time, { Brightness = 0, Range = range1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Runs { { time, fn }, ... } in effect time (sorted by time), each fn called with the
-- effect time that has passed. Blocks until the last one has run.
function Layers.Timeline(ctx, events)
	table.sort(events, function(a, b)
		return a[1] < b[1]
	end)
	local clock = 0
	for _, event in events do
		if event[1] > clock then
			clock += ctx.Wait(event[1] - clock)
		end
		if not ctx.Folder.Parent then
			return clock
		end
		event[2](clock)
	end
	return clock
end

-- Value of a keyframe track { { time, value }, ... } at t (numbers or Color3),
-- smoothstepped between keys and held at both ends.
function Layers.Track(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local alpha = (t - a[1]) / math.max(b[1] - a[1], 1e-6)
			alpha = alpha * alpha * (3 - 2 * alpha)
			if typeof(a[2]) == "Color3" then
				return a[2]:Lerp(b[2], alpha)
			end
			return a[2] + (b[2] - a[2]) * alpha
		end
	end
	return keys[#keys][2]
end

-- Ground point below `origin` (default ctx.CFrame), skipping characters and the effect.
-- Returns the position and the RaycastResult (nil when nothing was hit).
function Layers.Ground(ctx, origin)
	origin = origin or ctx.CFrame.Position
	local params = RaycastParams.new()
	params.RespectCanCollide = true
	local exclude = { ctx.Folder }
	params.FilterDescendantsInstances = exclude
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -30, 0), params)
		if not hit then
			break
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			table.insert(exclude, model)
			params.FilterDescendantsInstances = exclude
		else
			return hit.Position, hit
		end
	end
	return origin - Vector3.new(0, 2.6, 0), nil
end

-- Layout frame on the ground facing away from the viewer, like a camera:
-- +X = the viewer's right, +Y up, +Z toward the viewer.
function Layers.Frame(ctx, ground)
	local look = ctx.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(ground, ground - look.Unit)
end

return Layers
