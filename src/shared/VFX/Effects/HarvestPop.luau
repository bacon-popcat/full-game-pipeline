-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/HarvestPop
-- A crop pulled from the soil, kept clean: a quick small glint where it stood, one thin crisp
-- ring of its colour running out across the soil, a few solid bits of its colour and a few soil
-- clods kicked up and falling back, and three sparkles rising. Every layer is a hard-edged shape
-- (no soft glows or dust), each with its own job. A mutated pick adds a wider ring in its
-- mutation's colour, more sparkles in that colour and a light. About 5 studs across, gone
-- within a second, calm.
-- Layers: glint, ring, crop bits, clods, sparkles, (mutated) wide ring, accent sparkles, light.
--
-- ctx.CFrame = the soil under the crop (its foot). FxController leaves the produce popping into
-- the picker and the leaves fluttering to its own parts; this is the burst round them.
-- Reduced = true (the player's reduced motion) keeps only what fades in place: the glint, the
-- rings at their full size, and the light; nothing flies or rises.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids. Comment = where it came from and what it is.
local ASSETS = {
	ThinRing = "rbxassetid://118128517935651", -- cs_halo_thin (custom): crisp thin ring at 0.86 of the half-width
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153 (small 4-point sparkle)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31 (small solid speck)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py (fallback: Star153)
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(240, 150, 70), -- the crop's colour (FxController passes it)
	HotColor = Color3.fromRGB(255, 250, 236), -- near-white highlights
	SoilColor = Color3.fromRGB(118, 82, 52), -- the soil kicked up, a step darker than the dirt
	AccentColor = Color3.fromRGB(255, 214, 110), -- a mutation's colour (mutated picks only)
	Mutated = false,
	Scale = 1,
	PlantHeight = 1.1, -- studs from the soil to the crop's middle, where the glint sits
	RingSize = 4.5, -- studs: the ring's final diameter
	BitCount = 6, -- solid bits of the crop springing out
	ClodCount = 4,
	SparkleCount = 3,
	LightBrightness = 1.4, -- mutated only
	LightRange = 9,
	Reduced = false,
}

Effect.Linger = 0.9 -- the sparkles live up to 0.8 s

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local foot = ctx.CFrame.Position
	-- lifted off the soil so flat layers are not clipped by it
	local groundAtt = Layers.Attachment(ctx.Anchor(CFrame.new(foot + Vector3.new(0, 0.1, 0))))
	local plantAtt = Layers.Attachment(ctx.Anchor(CFrame.new(foot + Vector3.new(0, p.PlantHeight, 0))))
	local still = p.Reduced
	-- the ring texture's line sits at 0.86 of its half-width: size for the wanted radius
	local ringHalf = p.RingSize * 0.5 * s / 0.86

	-- one small sharp flash where the crop stood, gone in a blink
	local glint = Layers.Emitter(plantAtt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.14,
		Rotation = 0,
		LightEmission = 1,
		Brightness = 2.5,
		ZOffset = 1,
		Color = p.HotColor,
		Size = { { 0, 0.6 * s }, { 0.25, 1.6 * s }, { 1, 0 } },
	})
	-- one thin ring running out across the soil: fast then easing, white to the crop's colour
	local function ringSpec(half, life, color)
		return {
			Flat = true,
			Texture = ASSETS.ThinRing,
			Lifetime = life,
			LightEmission = 0.2,
			Brightness = 1.6,
			Color = { { 0, p.HotColor }, { 0.25, color }, { 1, color } },
			Size = if still
				then half
				else { { 0, 0.3 * half }, { 0.3, 0.85 * half }, { 1, half } },
			Transparency = { { 0, 0 }, { 0.5, 0.25 }, { 1, 1 } },
		}
	end
	local ring = Layers.Emitter(groundAtt, ringSpec(ringHalf, 0.45, p.Color))
	-- solid bits of the crop arcing out and dropping back, lit like the crop itself
	local bits = Layers.Emitter(plantAtt, {
		Texture = ASSETS.Speck,
		Lifetime = { 0.45, 0.6 },
		Speed = { 5 * s, 7 * s },
		EmissionDirection = "Top",
		SpreadAngle = 50,
		Acceleration = Vector3.new(0, -30 * s, 0),
		Rotation = { 0, 360 },
		RotSpeed = { -200, 200 },
		LightEmission = 0,
		LightInfluence = 0.25,
		Brightness = 1.3,
		Color = p.Color,
		Size = { { 0, 0.26 * s }, { 0.75, 0.22 * s }, { 1, 0 } },
	})
	-- a few soil clods thrown low that fall back: the darks that let the colour read
	local clods = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Speck,
		Lifetime = { 0.35, 0.5 },
		Speed = { 3.5 * s, 5.5 * s },
		EmissionDirection = "Top",
		SpreadAngle = 60,
		Acceleration = Vector3.new(0, -30 * s, 0),
		Rotation = { 0, 360 },
		RotSpeed = { -180, 180 },
		LightEmission = 0,
		LightInfluence = 0.6,
		Color = p.SoilColor,
		Size = { { 0, 0.2 * s }, { 0.8, 0.16 * s }, { 1, 0 } },
	})
	-- three sparkles drifting up and winking out, the same shape as the glint
	local function sparkleSpec(color)
		return {
			Texture = ASSETS.Sparkle,
			Lifetime = { 0.6, 0.8 },
			Speed = { 2 * s, 3 * s },
			EmissionDirection = "Top",
			SpreadAngle = 30,
			Drag = 2.5,
			Rotation = 0,
			LightEmission = 1,
			Brightness = 2,
			ZOffset = 0.5,
			Color = { { 0, p.HotColor }, { 0.5, color }, { 1, color } },
			Size = { { 0, 0 }, { 0.15, 0.4 * s }, { 0.6, 0.3 * s }, { 1, 0 } },
		}
	end
	local sparkles = Layers.Emitter(plantAtt, sparkleSpec(p.Color))

	local wideRing, accentSparkles, light
	if p.Mutated then
		wideRing = Layers.Emitter(groundAtt, ringSpec(ringHalf * 1.6, 0.65, p.AccentColor))
		accentSparkles = Layers.Emitter(plantAtt, sparkleSpec(p.AccentColor))
		light = Layers.Light(plantAtt, { Color = p.AccentColor })
	end

	Layers.Timeline(ctx, {
		{
			0,
			function()
				ctx.Emit(glint, 1)
				if light then
					Layers.Pop(ctx, light, p.LightBrightness, 3 * s, p.LightRange * s, 0.6)
				end
			end,
		},
		{
			0.03,
			function()
				ctx.Emit(ring, 1)
				if not still then
					ctx.Emit(clods, p.ClodCount)
					ctx.Emit(bits, p.BitCount)
				end
			end,
		},
		{
			0.08,
			function()
				if wideRing then
					ctx.Emit(wideRing, 1)
				end
			end,
		},
		{
			0.1,
			function()
				if not still then
					ctx.Emit(sparkles, p.SparkleCount)
					if accentSparkles then
						ctx.Emit(accentSparkles, p.SparkleCount + 1)
					end
				end
			end,
		},
	})
end

return Effect
