-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/HarvestPop
-- A crop pulled from the soil: a quick soft glint where it stood, a ring of its colour running
-- across the soil with a faint glow under it, a puff of soil and a few clods kicked up, bright
-- bits of the crop's colour springing out and falling, and sparkles drifting up. A mutated pick
-- adds a wider second ring in its mutation's colour, a short column of motes, more sparkles and
-- a light. One small moment of many: about 5 studs across, gone within a second, calm.
-- Layers: glint, ring, ground glow, soil puff, clods, crop bits, sparkles, (mutated) wide ring,
-- mote column, light.
--
-- ctx.CFrame = the soil under the crop (its foot). FxController leaves the produce popping into
-- the picker and the leaves fluttering to its own parts; this is the burst round them.
-- Reduced = true (the player's reduced motion) keeps only what fades in place: the glint, the
-- ring and glow at their full size, and the light; nothing flies or rises.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	SoftGlow = "rbxassetid://87365446017300", -- lava_glow (custom): soft glow that reaches 0 at the edge
	GroundDisc = "rbxassetid://13580366694", -- StaticVFXTextures/glowing ring (disc with a bright rim)
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153 (small 4-point sparkle)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31 (small solid speck)
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	DustPuff = Textures.DustPuff, -- drawn (fallback: FlipbookTextures/Realistic Smoke Burst, 4x4)
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(240, 150, 70), -- the crop's colour (FxController passes it)
	HotColor = Color3.fromRGB(255, 248, 228), -- near-white highlights
	SoilColor = Color3.fromRGB(150, 108, 72), -- desaturated matter: the soil kicked up
	AccentColor = Color3.fromRGB(255, 214, 110), -- a mutation's colour (mutated picks only)
	Mutated = false,
	Scale = 1,
	PlantHeight = 1.15, -- studs from the soil to the crop's middle, where the glint sits
	RingSize = 5, -- studs: the ring's final diameter
	BitCount = 8, -- bright bits of the crop springing out
	ClodCount = 6,
	SparkleCount = 5,
	MoteCount = 10, -- mutated only: the column of motes
	LightBrightness = 1.6, -- mutated only
	LightRange = 10,
	Reduced = false,
}

Effect.Linger = 1.1 -- the column's motes live up to 1 s

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale * (if p.Mutated then 1.25 else 1)
	local foot = ctx.CFrame.Position
	-- lifted off the soil so flat layers are not clipped by it
	local groundAtt = Layers.Attachment(ctx.Anchor(CFrame.new(foot + Vector3.new(0, 0.12, 0))))
	local plantAtt = Layers.Attachment(ctx.Anchor(CFrame.new(foot + Vector3.new(0, p.PlantHeight, 0))))
	local still = p.Reduced
	-- the ring texture's line sits at ~0.75 of its half-width: size for the wanted radius
	local ringHalf = p.RingSize * 0.5 * s / 0.75

	local glint = Layers.Emitter(plantAtt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.12,
		Rotation = { -15, 15 },
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 1.5,
		Color = p.HotColor,
		Size = { { 0, 0.8 * s }, { 0.3, 2.2 * s }, { 1, 2.4 * s } },
		Transparency = { { 0, 0.15 }, { 1, 1 } },
	})
	local glintHue = Layers.Twin(glint, {
		Texture = ASSETS.SoftGlow,
		Lifetime = 0.2,
		LightEmission = 0.3,
		Brightness = 1.5,
		ZOffset = 1,
		Color = p.Color,
		Size = { { 0, 1 * s }, { 1, 2.6 * s } },
		Transparency = { { 0, 0.35 }, { 1, 1 } },
	})
	local ring = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.5,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 2,
		Color = { { 0, p.HotColor }, { 0.35, p.Color }, { 1, p.Color } },
		Size = if still
			then { { 0, ringHalf }, { 1, ringHalf } }
			else { { 0, 0.4 * s }, { 0.45, ringHalf * 0.9 }, { 1, ringHalf } },
		Transparency = { { 0, 0.05 }, { 0.6, 0.5 }, { 1, 1 } },
	})
	local glow = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.GroundDisc,
		Lifetime = 0.6,
		LightEmission = 0.4,
		Brightness = 1,
		Color = p.Color,
		Size = { { 0, ringHalf * 0.35 }, { 0.3, ringHalf * 0.5 }, { 1, ringHalf * 0.45 } },
		Transparency = { { 0, 1 }, { 0.2, 0.6 }, { 1, 1 } },
	})
	-- soil: a low puff that swells and settles, and clods thrown up that fall back
	local puff = Layers.Emitter(groundAtt, {
		Texture = ASSETS.DustPuff,
		Lifetime = { 0.45, 0.6 },
		Speed = { 0.8 * s, 1.6 * s },
		EmissionDirection = "Top",
		SpreadAngle = 70,
		Drag = 3,
		Rotation = { 0, 360 },
		RotSpeed = { -40, 40 },
		LightEmission = 0,
		LightInfluence = 0.6,
		Brightness = 1,
		Color = p.SoilColor,
		Size = { { 0, 0.5 * s }, { 0.4, 1.1 * s }, { 1, 1.3 * s } },
		Transparency = { { 0, 0.45 }, { 0.5, 0.6 }, { 1, 1 } },
	})
	local clods = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Speck,
		Lifetime = { 0.45, 0.65 },
		Speed = { 5 * s, 8 * s },
		EmissionDirection = "Top",
		SpreadAngle = 45,
		Acceleration = Vector3.new(0, -32 * s, 0),
		Rotation = { 0, 360 },
		RotSpeed = { -180, 180 },
		LightEmission = 0,
		LightInfluence = 0.5,
		Color = { { 0, p.SoilColor }, { 1, p.SoilColor:Lerp(Color3.new(0, 0, 0), 0.35) } },
		Size = { { 0, 0.16 * s }, { 0.8, 0.13 * s }, { 1, 0 } },
	})
	-- the crop's colour: solid bits springing out and dropping, with a thin hot core twin
	local bits = Layers.Emitter(plantAtt, {
		Texture = ASSETS.SoftGlow,
		Lifetime = { 0.5, 0.7 },
		Speed = { 5 * s, 8 * s },
		EmissionDirection = "Top",
		SpreadAngle = 55,
		Acceleration = Vector3.new(0, -26 * s, 0),
		Drag = 0.8,
		LightEmission = 0.25,
		Brightness = 1.6,
		Color = p.Color,
		Size = { { 0, 0.35 * s }, { 0.7, 0.25 * s }, { 1, 0 } },
	})
	local bitCores = Layers.Twin(bits, {
		LightEmission = 1,
		Brightness = 1.5,
		ZOffset = 0.2,
		Color = p.HotColor,
		Size = { { 0, 0.12 * s }, { 0.6, 0.08 * s }, { 1, 0 } },
	})
	local sparkles = Layers.Emitter(plantAtt, {
		Texture = ASSETS.Sparkle,
		Lifetime = { 0.55, 0.85 },
		Speed = { 2.5 * s, 4 * s },
		EmissionDirection = "Top",
		SpreadAngle = 35,
		Drag = 2,
		Rotation = { 0, 90 },
		LightEmission = 1,
		Brightness = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0 }, { 0.2, 0.45 * s }, { 1, 0 } },
	})

	local wideRing, motes, light
	if p.Mutated then
		local wideHalf = ringHalf * 1.7
		wideRing = Layers.Emitter(groundAtt, {
			Flat = true,
			Texture = ASSETS.ShockRing,
			Lifetime = 0.8,
			Rotation = { 0, 360 },
			LightEmission = 0.3,
			Brightness = 2.2,
			Color = { { 0, p.HotColor }, { 0.3, p.AccentColor }, { 1, p.AccentColor } },
			Size = if still
				then { { 0, wideHalf }, { 1, wideHalf } }
				else { { 0, 0.6 * s }, { 0.5, wideHalf * 0.9 }, { 1, wideHalf } },
			Transparency = { { 0, 0.1 }, { 0.6, 0.55 }, { 1, 1 } },
		})
		motes = Layers.Emitter(groundAtt, {
			Texture = ASSETS.SoftGlow,
			Shape = "Disc",
			ShapeStyle = "Volume",
			Lifetime = { 0.7, 1 },
			Speed = { 3 * s, 5 * s },
			EmissionDirection = "Top",
			SpreadAngle = 8,
			Drag = 0.8,
			LightEmission = 0.6,
			Brightness = 1.3,
			Color = { { 0, p.AccentColor }, { 1, p.Color } },
			Size = { { 0, 0 }, { 0.15, 0.5 * s }, { 1, 0.1 * s } },
			Transparency = { { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } },
		})
		-- Shape "Disc" emits over the anchor's footprint
		groundAtt.Parent.Size = Vector3.new(p.RingSize * 0.4 * s, 0.1, p.RingSize * 0.4 * s)
		light = Layers.Light(plantAtt, { Color = p.AccentColor })
	end

	Layers.Timeline(ctx, {
		{
			0,
			function()
				ctx.Emit(glint, 1)
				ctx.Emit(glintHue, 1)
				if light then
					Layers.Pop(ctx, light, p.LightBrightness, 3 * s, p.LightRange * s, 0.7)
				end
			end,
		},
		{
			0.03,
			function()
				ctx.Emit(ring, 1)
				ctx.Emit(glow, 1)
				if not still then
					ctx.Emit(puff, 3)
					ctx.Emit(clods, p.ClodCount)
				end
			end,
		},
		{
			0.06,
			function()
				if not still then
					ctx.Emit(bits, p.BitCount)
					ctx.Emit(bitCores, math.ceil(p.BitCount / 2))
				end
				if wideRing then
					ctx.Emit(wideRing, 1)
				end
			end,
		},
		{
			0.12,
			function()
				if not still then
					ctx.Emit(sparkles, if p.Mutated then p.SparkleCount * 2 else p.SparkleCount)
					if motes then
						ctx.Emit(motes, p.MoteCount)
					end
				end
			end,
		},
	})
end

return Effect
