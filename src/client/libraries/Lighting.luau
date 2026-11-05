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

-- The time of day is a chain of keyframes, blended smoothly by setClock: by day a soft,
-- filmic warmth, with gentle contrast, muted earthy colour and a creamy golden mist that
-- swallows the distance, shadows lengthening into the afternoon; golden sunrise and sunset;
-- and a moonlit night under a large moon and stars, drained to an indigo-blue monochrome
-- (DayTint saturation) with a blue mist on the horizon. Night is lit, not dark:
-- a blue OutdoorAmbient, a moon-tinted ColorShift and raised exposure keep crops, machines
-- and paths easy to read, so play never waits for morning.
type Key = {
	hour: number,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	shift: Color3,
	exposure: number,
	tint: Color3,
	saturation: number,
	contrast: number,
	haze: Color3,
	decay: Color3,
}
local rgb = Color3.fromRGB
local DAY = { saturation = 0, contrast = 0 }
local function key(hour: number, look: { [string]: any }, grade: { saturation: number, contrast: number }): Key
	return {
		hour = hour,
		brightness = look.brightness,
		ambient = look.ambient,
		outdoor = look.outdoor,
		shift = look.shift,
		exposure = look.exposure,
		tint = look.tint,
		saturation = grade.saturation,
		contrast = grade.contrast,
		haze = look.haze,
		decay = look.decay,
	}
end
local NIGHT = {
	brightness = 2,
	ambient = rgb(64, 76, 128),
	outdoor = rgb(104, 124, 186),
	shift = rgb(160, 186, 255),
	exposure = 0.8,
	tint = rgb(176, 196, 255),
	haze = rgb(84, 108, 190),
	decay = rgb(44, 56, 120),
}
-- A touch of negative contrast lifts the darks (soil, leaves) so nothing is lost in shadow.
local NIGHT_GRADE = { saturation = -0.35, contrast = -0.04 }
-- In hour order, from midnight round to midnight again.
local KEYS: { Key } = {
	key(0, NIGHT, NIGHT_GRADE),
	key(5.2, {
		brightness = 2,
		ambient = rgb(68, 74, 120),
		outdoor = rgb(108, 118, 176),
		shift = rgb(184, 180, 240),
		exposure = 0.7,
		tint = rgb(200, 206, 252),
		haze = rgb(110, 116, 176),
		decay = rgb(76, 72, 120),
	}, { saturation = -0.25, contrast = -0.02 }),
	key(6.5, {
		brightness = 2.6,
		ambient = rgb(60, 56, 64),
		outdoor = rgb(104, 96, 108),
		shift = rgb(255, 172, 124),
		exposure = 0.15,
		tint = rgb(255, 232, 216),
		haze = rgb(236, 198, 178),
		decay = rgb(150, 110, 100),
	}, DAY),
	key(9, {
		brightness = 2.7,
		ambient = rgb(60, 56, 50),
		outdoor = rgb(100, 98, 92),
		shift = rgb(255, 222, 180),
		exposure = 0,
		tint = rgb(255, 238, 210),
		haze = rgb(232, 224, 204),
		decay = rgb(170, 156, 124),
	}, DAY),
	key(13, {
		brightness = 2.8,
		ambient = rgb(60, 56, 48),
		outdoor = rgb(104, 100, 90),
		shift = rgb(255, 226, 186),
		exposure = -0.05,
		tint = rgb(255, 238, 206),
		haze = rgb(234, 226, 204),
		decay = rgb(176, 160, 124),
	}, DAY),
	key(16.3, {
		brightness = 2.8,
		ambient = rgb(60, 56, 48),
		outdoor = rgb(104, 100, 90),
		shift = rgb(255, 216, 168),
		exposure = 0,
		tint = rgb(255, 236, 202),
		haze = rgb(234, 224, 198),
		decay = rgb(176, 158, 120),
	}, DAY),
	key(17.6, {
		brightness = 2.8,
		ambient = rgb(56, 52, 62),
		outdoor = rgb(96, 88, 106),
		shift = rgb(255, 160, 108),
		exposure = 0,
		tint = rgb(255, 226, 206),
		haze = rgb(226, 178, 158),
		decay = rgb(140, 100, 92),
	}, DAY),
	key(18.6, {
		brightness = 2,
		ambient = rgb(66, 76, 124),
		outdoor = rgb(106, 122, 180),
		shift = rgb(176, 184, 245),
		exposure = 0.75,
		tint = rgb(190, 202, 255),
		haze = rgb(92, 110, 184),
		decay = rgb(50, 58, 118),
	}, { saturation = -0.25, contrast = -0.02 }),
	key(24, NIGHT, NIGHT_GRADE),
}
local GRADE = {
	brightness = 0,
	contrast = 0.06,
	saturation = 0,
}
local PRESETS: { [Quality]: Preset } = {
	-- Colour grade and plain haze only: no shadow maps, no bloom pass, no reflections.
	Low = {
		shadows = false,
		shadowSoftness = 0.5,
		diffuse = 0.6,
		specular = 0,
		glare = 0,
		haze = 1.2,
		bloom = false,
		sunRays = false,
		depthOfField = false,
	},
	Medium = {
		shadows = true,
		shadowSoftness = 0.25,
		diffuse = 1,
		specular = 0.7,
		glare = 0.25,
		haze = 1.4,
		bloom = true,
		sunRays = false,
		depthOfField = false,
	},
	High = {
		shadows = true,
		shadowSoftness = 0.12,
		diffuse = 1,
		specular = 1,
		glare = 0.3,
		haze = 1.6,
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
sky.MoonAngularSize = 24
sky.StarCount = 3000
sky.CelestialBodiesShown = true
atmosphere.Density = 0.36
atmosphere.Offset = 0.25
-- Only light well past white blooms, so lit white surfaces (hands, road arrows) don't halo.
bloom.Intensity = 0.3
bloom.Size = 20
bloom.Threshold = 1.8
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
	dayTint.Saturation = from.saturation + (to.saturation - from.saturation) * t
	dayTint.Contrast = from.contrast + (to.contrast - from.contrast) * t
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
