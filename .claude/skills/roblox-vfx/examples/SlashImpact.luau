-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/SlashImpact
-- Melee hit, one of many: a spiky flash bigger than the burst for two frames, impact stars
-- that burst open as a colour/black/white stack over a black backing, a claw stroke with
-- its dim twin, streaks that shoot out and stop (with black twins), a flat shock ring,
-- embers and a light that fades while its range grows. One hue; ~10 studs across at Scale
-- 1 (R = 4), the burst gone by ~0.4 s.
-- Layers: flash + flare line, stars (colour, black, white), backing, claw + dim claw,
-- streaks + black streaks, ring, embers, light.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	ImpactStar = Textures.ImpactStar, -- drawn: assets/textures/impact.py (Grid4x4)
	ClawSlash = Textures.ClawSlash, -- drawn: assets/textures/impact.py (Grid4x4)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 140, 35), -- the hue
	HotColor = Color3.fromRGB(255, 232, 170), -- white-hot start of the flash, stars and streaks
	DeepColor = Color3.fromRGB(205, 45, 15), -- the deep end of each gradient
	Scale = 1,
	Radius = 4, -- studs: the burst's radius (R); the flash reaches ~2.5 R
	StarCount = 3,
	StreakCount = 12,
	EmberCount = 8,
	LightBrightness = 10,
	LightRange = 14,
}

Effect.Linger = 0.85 -- embers live up to 0.8 s after the 0.05 s step

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local R = p.Radius * s

	local anchor = ctx.Anchor()
	local att = Layers.Attachment(anchor)
	-- the ring lies across the hit direction, facing the attacker (LookVector)
	local ringAtt = Layers.Attachment(anchor, CFrame.Angles(math.rad(90), 0, 0))

	-- flash: a filled spiky shape that is the biggest thing on screen, then gone
	local flash = Layers.Emitter(att, {
		Texture = ASSETS.Flash,
		Lifetime = 0.08,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.6 * R }, { 0.3, 2.5 * R }, { 1, 2.7 * R } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	-- a thin squashed flare line across it
	local flare = Layers.Emitter(att, {
		Texture = ASSETS.Glint,
		Lifetime = 0.06,
		Rotation = { -12, 12 },
		LightEmission = 1,
		Brightness = 6,
		ZOffset = 3.1,
		Color = p.HotColor,
		Size = { { 0, 2.2 * R }, { 1, 3 * R } },
		Squash = -3,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})

	-- impact stars: colour, its black twin a step in front, a small white core in front of both
	local stars = Layers.Emitter(att, {
		Texture = ASSETS.ImpactStar,
		Lifetime = { 0.1, 0.15 },
		Rotation = { 0, 360 },
		LightEmission = -1,
		Brightness = 5,
		ZOffset = 1,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 1.2 * R }, { 0.25, 2.2 * R, 0.4 * R }, { 1, 2.4 * R, 0.4 * R } },
	})
	local blackStars = Layers.Black(stars, 0.25)
	local whiteStar = Layers.White(stars, {
		Lifetime = { 0.06, 0.1 },
		Brightness = 3,
		Size = { { 0, 0.5 * R }, { 1, 0.9 * R } },
	})
	local backing = Layers.Emitter(att, {
		Texture = ASSETS.SoftGlow,
		Lifetime = 0.3,
		LightEmission = 0,
		ZOffset = -1,
		Color = Layers.BLACK,
		Size = { { 0, 2 * R }, { 1, 3 * R } },
		Transparency = { { 0, 0.35 }, { 1, 1 } },
	})

	-- claw stroke: one angle per hit, shared with its dim twin so the two line up
	local angle = math.random(0, 359)
	local claw = Layers.Emitter(att, {
		Texture = ASSETS.ClawSlash,
		Lifetime = 0.22,
		Rotation = angle,
		LightEmission = 0,
		Brightness = 4,
		ZOffset = 1.5,
		Color = { { 0, p.HotColor }, { 0.4, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 2 * R }, { 1, 2.3 * R } },
	})
	local dimClaw = Layers.Dim(claw, 0.5)

	-- streaks shoot out and stop; their black twins fly slower, so they break the burst up
	local streaks = Layers.Emitter(att, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		Lifetime = { 0.2, 0.35 },
		Speed = { 15 * R, 40 * R },
		SpreadAngle = 180,
		Drag = 10,
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.3 * R, 0.12 * R }, { 1, 0 } },
		Squash = { { 0, 3 }, { 1, 1 } },
	})
	local blackStreaks = Layers.Black(streaks, 0.1, { Speed = { 10 * R, 25 * R } })

	local ring = Layers.Emitter(ringAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.3,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 3,
		ZOffset = 0.5,
		Color = p.HotColor,
		Size = { { 0, 0.3 * R }, { 0.4, 2.2 * R }, { 1, 2.6 * R } },
		Transparency = { { 0, 0 }, { 1, 1.3 } },
	})

	local embers = Layers.Emitter(att, {
		Texture = ASSETS.Speck,
		Lifetime = { 0.4, 0.8 },
		Speed = { 3 * R, 15 * R },
		SpreadAngle = 180,
		Drag = 10,
		Acceleration = Vector3.new(0, -15 * s, 0),
		LightEmission = 1,
		Brightness = 2,
		ZOffset = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.08 * R, 0.03 * R }, { 1, 0 } },
	})

	local light = Layers.Light(att, { Color = p.Color })

	Layers.Timeline(ctx, {
		{ 0, function()
			ctx.Emit(flash, 1)
			ctx.Emit(flare, 1)
			Layers.Pop(ctx, light, p.LightBrightness, 4 * s, p.LightRange * s, 0.45)
		end },
		{ 0.03, function()
			ctx.Emit(stars, p.StarCount)
			ctx.Emit(blackStars, p.StarCount)
			ctx.Emit(whiteStar, 1)
			ctx.Emit(backing, 1)
			ctx.Emit(claw, 1)
			ctx.Emit(dimClaw, 1)
		end },
		{ 0.05, function()
			ctx.Emit(streaks, p.StreakCount)
			ctx.Emit(blackStreaks, math.ceil(p.StreakCount / 3))
			ctx.Emit(ring, 1)
			ctx.Emit(embers, p.EmberCount)
		end },
	})
end

return Effect
