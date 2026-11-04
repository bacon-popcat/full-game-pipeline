-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/ChargeAura
-- A held charge-up: an orb built on the orb skeleton (black linework, hard ring, black
-- pupil, core rays, outer ring, halo, black backdrop) that cross-fades so it holds but
-- shimmers, motes sucked in from a sphere around it, a breathing ground sigil and a light
-- that swells, held for Duration, then released as a pop. A looping (Rate > 0) effect: shows
-- how sustained layers start, hold and stop.
-- Layers: orb (7 cross-fading stacks), inward motes, rising sparks, sigil (two sizes),
-- release flash + ring, light.
--
-- ctx.CFrame = the orb's centre (e.g. the caster's hand or chest).

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Swirl = { Id = "rbxassetid://17612139917", Grid = 4 }, -- FlipbookTextures/Whole swirl (wisps circling a point)
	HardRing = "rbxassetid://15268062056", -- StaticVFXTextures/thick ring 3 (crisp inner edge)
	SoftGlow = "rbxassetid://87365446017300", -- lava_glow (custom): soft glow that reaches 0 at the edge
	DarkDisc = "rbxassetid://107972524433656", -- StaticVFXTextures/Blurry Black Hole (soft dark disc)
	Rays = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	Sigil = "rbxassetid://17388445727", -- StaticVFXTextures/Crescent32 (layered crescent strokes)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(170, 90, 255), -- violet
	AccentColor = Color3.fromRGB(255, 90, 210), -- magenta, on the outer ring only
	HotColor = Color3.fromRGB(240, 225, 255), -- pale lilac: rays, hard ring, release
	DeepColor = Color3.fromRGB(70, 25, 140), -- dark violet: gradient ends, sigil
	InkColor = Color3.fromRGB(12, 5, 25), -- near-black: linework, pupil, backdrop
	Scale = 1,
	Radius = 1.5, -- studs: R of the orb
	Duration = 2, -- seconds held before the release
	MoteRate = 30,
	SparkRate = 6,
	Release = true, -- end with a pop (false = just fade out)
	LightBrightness = 2, -- at 4 the light washed the whole floor purple
	LightRange = 10,
}

Effect.Linger = 2.05 -- the last sigil copies (Lifetime 2) emitted just before the stop

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local R = p.Radius * s

	local anchor = ctx.Anchor()
	local att = Layers.Attachment(anchor)

	-- Every orb layer: stationary, locked to the part, Rate x Lifetime ~3 copies that fade in
	-- and out (0:1, 0.5:0, 1:1) at random angles, so the form holds but shimmers.
	local CROSSFADE = { { 0, 1 }, { 0.5, 0 }, { 1, 1 } }
	local function orbLayer(spec)
		spec.LockedToPart = true
		spec.Speed = 0.001
		spec.Rotation = { 0, 360 }
		spec.Rate = spec.Rate or 4
		spec.Lifetime = spec.Lifetime or 0.75
		spec.Enabled = false
		spec.Transparency = spec.Transparency or CROSSFADE
		return Layers.Emitter(att, spec)
	end

	local orb = {
		orbLayer({ -- black linework
			Texture = ASSETS.Swirl,
			FlipbookMode = "Loop",
			FlipbookStartRandom = true,
			LightEmission = 0,
			Brightness = 1,
			ZOffset = 0.4,
			Color = p.InkColor,
			Size = 1 * R,
		}),
		orbLayer({ -- hard ring
			Texture = ASSETS.HardRing,
			LightEmission = 0,
			Brightness = 20,
			ZOffset = 0.3,
			Color = p.HotColor,
			Size = 0.9 * R,
		}),
		orbLayer({ -- black pupil, pulsing
			Texture = ASSETS.SoftGlow,
			Lifetime = 0.5,
			LightEmission = 0,
			Brightness = 1,
			ZOffset = 0.1,
			Color = p.InkColor,
			Size = { { 0, 0.15 * R }, { 0.5, 0.4 * R }, { 1, 0.2 * R } },
		}),
		orbLayer({ -- core rays
			Texture = ASSETS.Rays,
			LightEmission = 1,
			Brightness = 6,
			ZOffset = 0,
			RotSpeed = { -20, 20 },
			Color = { { 0, p.HotColor }, { 1, p.Color } },
			Size = 0.45 * R,
		}),
		orbLayer({ -- outer ring, growing; the accent hue lives here only
			Texture = ASSETS.HardRing,
			LightEmission = 1,
			Brightness = 2,
			ZOffset = -1,
			Color = { { 0, p.Color }, { 1, p.AccentColor } },
			Size = { { 0, 0.9 * R }, { 1, 1.5 * R } },
		}),
		orbLayer({ -- halo
			Texture = ASSETS.SoftGlow,
			Rate = 3,
			Lifetime = 0.9,
			LightEmission = 1,
			Brightness = 0.3,
			ZOffset = -1.05,
			Color = p.Color,
			Size = 1.6 * R,
		}),
		orbLayer({ -- black backdrop
			Texture = ASSETS.DarkDisc,
			Rate = 3,
			Lifetime = 0.9,
			LightEmission = 0,
			Brightness = 1,
			ZOffset = -1.1,
			Color = p.InkColor,
			Size = 2 * R,
			Transparency = { { 0, 1 }, { 0.5, 0.3 }, { 1, 1 } },
		}),
	}

	-- motes pulled in from a sphere; Lifetime ~ radius / speed so they vanish at the core
	local moteAnchor = ctx.Anchor()
	moteAnchor.Shape = Enum.PartType.Ball
	moteAnchor.Size = Vector3.one * 8 * R
	local motes = Layers.Emitter(moteAnchor, {
		Texture = ASSETS.Speck,
		Shape = "Sphere",
		ShapeInOut = "Inward",
		ShapeStyle = "Surface",
		Rate = p.MoteRate,
		Enabled = false,
		Speed = 12 * R,
		Lifetime = 0.3,
		Orientation = "VelocityParallel",
		LightEmission = 1,
		Brightness = 2,
		Color = { { 0, p.Color }, { 1, p.HotColor } },
		Size = { { 0, 0.08 * R }, { 1, 0.15 * R } },
		Squash = 2,
		Transparency = { { 0, 1 }, { 0.3, 0 }, { 1, 0 } },
	})
	local sparks = Layers.Emitter(att, {
		Texture = ASSETS.Sparkle,
		Rate = p.SparkRate,
		Enabled = false,
		Speed = { 1 * R, 3 * R },
		SpreadAngle = 180,
		Acceleration = Vector3.new(0, 4 * R, 0),
		Lifetime = { 0.5, 0.9 },
		LightEmission = 1,
		Brightness = 3,
		Color = p.HotColor,
		Size = { { 0, 0.3 * R }, { 1, 0 } },
	})

	-- ground sigil: two sizes that shrink a little as they live, so the circle breathes
	local groundPos = Layers.Ground(ctx)
	local sigilAtt = Layers.Attachment(ctx.Anchor(CFrame.new(groundPos + Vector3.new(0, 0.05, 0))))
	local function sigil(size, spin)
		return Layers.Emitter(sigilAtt, {
			Flat = true,
			Texture = ASSETS.Sigil,
			Rate = 1,
			Enabled = false,
			Lifetime = 2,
			RotSpeed = spin,
			LightEmission = 0.5,
			Brightness = 2,
			Color = { { 0, p.Color }, { 1, p.DeepColor } },
			Size = { { 0, size }, { 1, size * 0.85 } },
			Transparency = { { 0, 1 }, { 0.25, 0.4 }, { 0.75, 0.4 }, { 1, 1 } },
		})
	end
	local sigils = { sigil(5 * R, 5), sigil(3.5 * R, -8) }

	local releaseFlash = Layers.Emitter(att, {
		Texture = ASSETS.Rays,
		Lifetime = 0.08,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 1 * R }, { 0.3, 4 * R }, { 1, 4.3 * R } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local releaseRing = Layers.Emitter(att, {
		Texture = ASSETS.ShockRing,
		Lifetime = 0.3,
		LightEmission = 0.3,
		Brightness = 3,
		ZOffset = 1,
		Color = p.HotColor,
		Size = { { 0, 0.5 * R }, { 0.4, 4 * R }, { 1, 4.8 * R } },
		Transparency = { { 0, 0 }, { 1, 1.3 } },
	})

	local light = Layers.Light(att, { Color = p.Color, Range = 4 * s })

	-- start every looping layer at the play's speed
	local looping = table.clone(orb)
	table.insert(looping, motes)
	table.insert(looping, sparks)
	for _, emitter in sigils do
		table.insert(looping, emitter)
	end
	for _, emitter in looping do
		emitter.TimeScale = ctx.TimeScale
		emitter.Enabled = true
	end
	-- prime the stack and the sigils so they're there from the first frame, not after one
	-- Rate interval (a Rate 1 sigil would otherwise first appear a second in)
	for _, emitter in orb do
		ctx.Emit(emitter, 1)
	end
	for _, emitter in sigils do
		ctx.Emit(emitter, 1)
	end
	ctx.Tween(light, 0.4, { Brightness = p.LightBrightness, Range = p.LightRange * s })

	-- hold; a looping effect still blocks for its duration so Linger starts at the end
	local held = 0
	while held < p.Duration do
		held += ctx.Wait(math.min(0.25, p.Duration - held))
		if not ctx.Folder.Parent then
			return
		end
	end

	-- stop emitting; the live copies finish their cross-fade during Linger
	for _, emitter in looping do
		emitter.Enabled = false
	end
	if p.Release then
		for _, emitter in orb do
			emitter:Clear()
		end
		ctx.Emit(releaseFlash, 1)
		ctx.Emit(releaseRing, 1)
		Layers.Pop(ctx, light, p.LightBrightness * 2, p.LightRange * s, p.LightRange * 1.6 * s, 0.5)
	else
		ctx.Tween(light, 0.6, { Brightness = 0 })
	end
end

return Effect
