--!strict
-- Lighting: named requests compose into a private colour correction effect. Features
-- release only their own contribution; authored Lighting and other effects remain owners
-- of their baselines. Weather and lightning never race to restore a global property.
local LightingService = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
type Request = { tint: Color3, brightness: number, contrast: number }
local requests: { [string]: Request } = {}
local effect = Instance.new("ColorCorrectionEffect")
effect.Name = "GardenAtmosphere"
effect.Parent = LightingService
local tween: Tween? = nil
local Lighting = {}
local function apply(seconds: number)
	local tint = Vector3.one
	local brightness, contrast = 0, 0
	for _, request in requests do
		tint *= Vector3.new(request.tint.R, request.tint.G, request.tint.B)
		brightness += request.brightness
		contrast += request.contrast
	end
	if tween then
		tween:Cancel()
	end
	local nextTween =
		TweenService:Create(effect, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			TintColor = Color3.new(tint.X, tint.Y, tint.Z),
			Brightness = brightness,
			Contrast = contrast,
		})
	tween = nextTween
	nextTween:Play()
end
function Lighting.set(source: string, tint: Color3, brightness: number, contrast: number, seconds: number)
	requests[source] = { tint = tint, brightness = brightness, contrast = contrast }
	apply(seconds)
end
function Lighting.clear(source: string, seconds: number)
	requests[source] = nil
	apply(seconds)
end
return Lighting
