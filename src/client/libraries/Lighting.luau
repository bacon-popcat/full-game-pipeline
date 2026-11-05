--!strict
-- Lighting: owns the game's look on this client. It sets every Lighting property the look
-- depends on and keeps one of each post effect (Sky, Atmosphere, ColorCorrection, Bloom,
-- SunRays, DepthOfField), adopting the place file's own instance of that class when there is
-- one, so a Studio-authored copy is retuned rather than stacked. The place uses unified
-- lighting (no Technology property); its LightingStyle (Realistic) and
-- PrioritizeLightingQuality stay authored with the Sky's textures, since only plugins may set
-- them.
--
-- setClock blends the look to a time of day (LightingController drives it from
-- Shared/DayCycle). A quality preset (Low, Medium, High) decides how much of the look is paid for; setQuality
-- applies one live. Features never write Lighting directly: they make named requests (set,
-- clear) that compose on top of the preset's colour correction, so weather and lightning
-- release only their own contribution. PopupBlur (Backdrop) is the one other effect here.
local LightingService = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

export type Quality = "Low" | "Medium" | "High"
type Preset = {
	shadows: boolean,
	shadowSoftness: number,
	diffuse: number,
	specular: number,
	glare: number,
	haze: number,
	bloom: boolean,
	sunRays: boolean,
	depthOfField: boolean,
}

-- The time of day is a chain of keyframes, blended smoothly by setClock: a warm sun by day
-- with long shadows by late afternoon, golden sunrise and sunset, and a moonlit night. Night
-- is lit, not dark: a bright blue OutdoorAmbient, a moon-tinted ColorShift and raised exposure
-- keep crops, machines and paths easy to read, so play never waits for morning.
type Key = {
	hour: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	shift: Color3,
	exposure: number,
	tint: Color3,
	haze: Color3,
	decay: Color3,
}
local function key(
	hour: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	shift: Color3,
	exposure: number,
	tint: Color3,
	haze: Color3,
	decay: Color3
): Key
	return {
		hour = hour,
		brightness = brightness,
		ambient = ambient,
		outdoor = outdoor,
		shift = shift,
		exposure = exposure,
		tint = tint,
		haze = haze,
		decay = decay,
	}
end
local rgb = Color3.fromRGB
local NIGHT = key(
	0,
	1.8,
	rgb(62, 70, 100),
	rgb(100, 114, 156),
	rgb(168, 184, 228),
	0.5,
	rgb(226, 232, 255),
	rgb(70, 84, 124),
	rgb(44, 52, 86)
)
-- In hour order, from midnight round to midnight again.
local KEYS: { Key } = {
	NIGHT,
	key(5.2, 1.8, rgb(64, 68, 96), rgb(104, 110, 148), rgb(176, 172, 222), 0.45, rgb(222, 220, 250), rgb(104, 106, 142), rgb(72, 66, 98)),
	key(6.5, 2.6, rgb(60, 56, 64), rgb(104, 96, 108), rgb(255, 172, 124), 0.15, rgb(255, 232, 216), rgb(236, 198, 178), rgb(150, 110, 100)),
	key(9, 3.2, rgb(46, 50, 60), rgb(78, 88, 108), rgb(255, 228, 198), -0.1, rgb(255, 246, 236), rgb(196, 210, 228), rgb(120, 116, 110)),
	key(13, 2.8, rgb(46, 50, 60), rgb(76, 86, 106), rgb(255, 236, 214), -0.35, rgb(255, 246, 236), rgb(176, 196, 222), rgb(110, 110, 108)),
	key(16.3, 3.4, rgb(42, 46, 56), rgb(70, 80, 100), rgb(255, 200, 140), -0.15, rgb(255, 238, 216), rgb(196, 208, 226), rgb(128, 112, 96)),
	key(17.6, 2.8, rgb(56, 52, 62), rgb(96, 88, 106), rgb(255, 160, 108), 0, rgb(255, 226, 206), rgb(226, 178, 158), rgb(140, 100, 92)),
	key(18.6, 1.9, rgb(66, 70, 100), rgb(110, 120, 164), rgb(178, 180, 230), 0.65, rgb(228, 228, 255), rgb(96, 100, 140), rgb(56, 58, 92)),
	key(24, NIGHT.brightness, NIGHT.ambient, NIGHT.outdoor, NIGHT.shift, NIGHT.exposure, NIGHT.tint, NIGHT.haze, NIGHT.decay),
}
local GRADE = {
	brightness = 0,
	contrast = 0.25,
	saturation = 0.2,
}
local PRESETS: { [Quality]: Preset } = {
	-- Colour grade and plain haze only: no shadow maps, no bloom pass, no reflections.
	Low = {
		shadows = false,
		shadowSoftness = 0.5,
		diffuse = 0.6,
		specular = 0,
		glare = 0,
		haze = 1,
		bloom = false,
		sunRays = false,
		depthOfField = false,
	},
	Medium = {
		shadows = true,
		shadowSoftness = 0.25,
		diffuse = 1,
		specular = 0.7,
		glare = 0.8,
		haze = 1.2,
		bloom = true,
		sunRays = false,
		depthOfField = false,
	},
	High = {
		shadows = true,
		shadowSoftness = 0.12,
		diffuse = 1,
		specular = 1,
		glare = 1.2,
		haze = 1.4,
		bloom = true,
		sunRays = true,
		depthOfField = true,
	},
}

local function owned<T>(className: string, name: string): T
	local found = LightingService:FindFirstChild(name)
	if not (found and found.ClassName == className) then
		found = LightingService:FindFirstChildOfClass(className :: any)
	end
	local instance = found or Instance.new(className :: any)
	instance.Name = name
	instance.Parent = LightingService
	return instance :: any
end

-- The place may carry more than one of an effect from older edits; any extra would stack.
local function dropExtras(className: string, keep: Instance)
	for _, child in LightingService:GetChildren() do
		if child.ClassName == className and child ~= keep then
			child:Destroy()
		end
	end
end

local sky = owned("Sky", "Sky") :: Sky
local atmosphere = owned("Atmosphere", "Atmosphere") :: Atmosphere
local grade = owned("ColorCorrectionEffect", "GardenGrade") :: ColorCorrectionEffect
local bloom = owned("BloomEffect", "Bloom") :: BloomEffect
local sunRays = owned("SunRaysEffect", "SunRays") :: SunRaysEffect
local depthOfField = owned("DepthOfFieldEffect", "DepthOfField") :: DepthOfFieldEffect
for _, instance in { sky, atmosphere, grade, bloom, sunRays, depthOfField } :: { Instance } do
	dropExtras(instance.ClassName, instance)
end

LightingService.GeographicLatitude = 35
LightingService.ColorShift_Bottom = Color3.new(0, 0, 0)
-- The time-of-day tint, apart from GardenGrade so weather tweens there never fight setClock.
local dayTint = LightingService:FindFirstChild("DayTint") :: ColorCorrectionEffect?
if not dayTint then
	local created = Instance.new("ColorCorrectionEffect")
	created.Name = "DayTint"
	created.Parent = LightingService
	dayTint = created
end
assert(dayTint, "DayTint was just ensured")
sky.SunAngularSize = 14
sky.MoonAngularSize = 11
sky.StarCount = 3000
sky.CelestialBodiesShown = true
atmosphere.Density = 0.3
atmosphere.Offset = 0.1
bloom.Intensity = 0.8
bloom.Size = 30
bloom.Threshold = 0.95
sunRays.Intensity = 0.12
sunRays.Spread = 0.8
-- Far blur only, starting well past the plot, so the garden stays sharp and the hills soften.
depthOfField.NearIntensity = 0
depthOfField.FarIntensity = 0.12
depthOfField.FocusDistance = 60
depthOfField.InFocusRadius = 90

type Request = { tint: Color3, brightness: number, contrast: number }
local requests: { [string]: Request } = {}
local tween: Tween? = nil
local current: Quality = "High"
local Lighting = {}

local function applyGrade(seconds: number)
	local tint = Vector3.one
	local brightness, contrast = GRADE.brightness, GRADE.contrast
	for _, request in requests do
		tint *= Vector3.new(request.tint.R, request.tint.G, request.tint.B)
		brightness += request.brightness
		contrast += request.contrast
	end
	if tween then
		tween:Cancel()
	end
	local nextTween =
		TweenService:Create(grade, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			TintColor = Color3.new(tint.X, tint.Y, tint.Z),
			Brightness = brightness,
			Contrast = contrast,
		})
	tween = nextTween
	nextTween:Play()
end

-- Applies a quality preset now; an unknown name falls back to High.
function Lighting.setQuality(quality: string)
	local preset = PRESETS[quality :: Quality]
	if not preset then
		quality, preset = "High", PRESETS.High
	end
	current = quality :: Quality
	LightingService.GlobalShadows = preset.shadows
	LightingService.ShadowSoftness = preset.shadowSoftness
	LightingService.EnvironmentDiffuseScale = preset.diffuse
	LightingService.EnvironmentSpecularScale = preset.specular
	atmosphere.Glare = preset.glare
	atmosphere.Haze = preset.haze
	bloom.Enabled = preset.bloom
	sunRays.Enabled = preset.sunRays
	depthOfField.Enabled = preset.depthOfField
end

function Lighting.quality(): Quality
	return current
end

-- Sets the time of day (a ClockTime, 0-24) and blends the look to it.
function Lighting.setClock(hour: number)
	hour %= 24
	local index = 1
	while KEYS[index + 1].hour <= hour do
		index += 1
	end
	local from, to = KEYS[index], KEYS[index + 1]
	local t = (hour - from.hour) / (to.hour - from.hour)
	t = t * t * (3 - 2 * t)
	LightingService.ClockTime = hour
	LightingService.Brightness = from.brightness + (to.brightness - from.brightness) * t
	LightingService.Ambient = from.ambient:Lerp(to.ambient, t)
	LightingService.OutdoorAmbient = from.outdoor:Lerp(to.outdoor, t)
	LightingService.ColorShift_Top = from.shift:Lerp(to.shift, t)
	LightingService.ExposureCompensation = from.exposure + (to.exposure - from.exposure) * t
	dayTint.TintColor = from.tint:Lerp(to.tint, t)
	atmosphere.Color = from.haze:Lerp(to.haze, t)
	atmosphere.Decay = from.decay:Lerp(to.decay, t)
end

function Lighting.set(source: string, tint: Color3, brightness: number, contrast: number, seconds: number)
	requests[source] = { tint = tint, brightness = brightness, contrast = contrast }
	applyGrade(seconds)
end

function Lighting.clear(source: string, seconds: number)
	requests[source] = nil
	applyGrade(seconds)
end

grade.Saturation = GRADE.saturation
applyGrade(0)
Lighting.setClock(16.3)
Lighting.setQuality(current)
return Lighting
