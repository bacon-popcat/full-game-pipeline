-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/ResearchComplete
-- A research upgrade completed, round the player who completed it: a soft warm flash at the
-- chest, a gold ring and a breathing glow spreading across the ground, two strands of warm
-- motes spiralling up round the body (one gold, one leaf green), a slow column of light motes
-- drifting up after them, small sparkles rising, a warm Highlight that fades, and a light that
-- pops and fades. Calm and warm, never a blast: it reads as "something grew", in the garden's
-- gold and green.
-- Layers: chest flash, ground ring, ground glow, spiral motes (x Strands), rising column,
-- rising sparkles, character Highlight, light.
--
-- ctx.CFrame = the character's root. Runtime-only override:
--   Character (Model)  gets the Highlight; nil = no Highlight.
-- Reduced = true (the player's reduced motion) keeps only what fades in place: the flash, the
-- ring and glow at their full size, the Highlight and the light; nothing grows, flies or rises.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	SoftGlow = "rbxassetid://87365446017300", -- lava_glow (custom): soft glow that reaches 0 at the edge
	GroundDisc = "rbxassetid://13580366694", -- StaticVFXTextures/glowing ring (disc with a bright rim)
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153 (small 4-point sparkle)
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(246, 206, 118), -- the hue: warm gold
	HotColor = Color3.fromRGB(255, 246, 222), -- near-white highlights
	DeepColor = Color3.fromRGB(196, 118, 62), -- deep end of the gradients
	AccentColor = Color3.fromRGB(150, 214, 128), -- leaf green, on one strand only
	Scale = 1,
	RingSize = 11, -- studs: ground ring's final diameter
	Height = 8, -- studs the spiral rises
	Strands = 2, -- spiral strands, evenly spaced round the body
	SpiralTime = 0.9, -- seconds for a strand to climb Height
	ColumnCount = 14, -- light motes drifting up after the spiral
	SparkleCount = 10,
	HighlightTransparency = 0.65, -- Highlight fill at its strongest (1 = off)
	LightBrightness = 2.5,
	LightRange = 14,
	Reduced = false, -- reduced motion: fades in place only
}

Effect.Linger = 1.8 -- the column's motes live up to 1.6 s

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale

	local root = ctx.CFrame.Position
	local groundPos = Layers.Ground(ctx)
	-- lifted off the floor so the flat layers are not clipped by it
	local groundAtt = Layers.Attachment(ctx.Anchor(CFrame.new(groundPos + Vector3.new(0, 0.15, 0))))
	local chestAtt = Layers.Attachment(ctx.Anchor(CFrame.new(root + Vector3.new(0, 0.5 * s, 0))))

	local flash = Layers.Emitter(chestAtt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.14,
		Rotation = { -10, 10 },
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 2,
		Color = p.HotColor,
		Size = { { 0, 2 * s }, { 0.3, 5.5 * s }, { 1, 6 * s } },
		Transparency = { { 0, 0.1 }, { 1, 1 } },
	})
	local ring = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.8,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 2.5,
		Color = { { 0, p.HotColor }, { 0.4, p.Color }, { 1, p.DeepColor } },
		Size = if p.Reduced
			then { { 0, p.RingSize * s }, { 1, p.RingSize * s } }
			else { { 0, 1.5 * s }, { 0.5, p.RingSize * 0.9 * s }, { 1, p.RingSize * s } },
		Transparency = { { 0, 0.05 }, { 1, 1 } },
	})
	local glow = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.GroundDisc,
		Lifetime = 1.3,
		LightEmission = 0.5,
		Brightness = 1,
		Color = p.Color,
		Size = if p.Reduced
			then { { 0, p.RingSize * 0.6 * s }, { 1, p.RingSize * 0.6 * s } }
			else { { 0, p.RingSize * 0.4 * s }, { 0.3, p.RingSize * 0.65 * s }, { 1, p.RingSize * 0.55 * s } },
		Transparency = { { 0, 1 }, { 0.25, 0.55 }, { 1, 1 } },
	})
	local sparkles = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Sparkle,
		Shape = "Disc",
		ShapeStyle = "Volume",
		Lifetime = { 0.6, 1 },
		Speed = { 4 * s, 8 * s },
		EmissionDirection = "Top",
		SpreadAngle = 12,
		Drag = 2,
		LightEmission = 1,
		Brightness = 2.5,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0 }, { 0.2, 1 * s }, { 1, 0 } },
	})
	-- the column: soft motes that start on the hue and drift slowly up past the head
	local column = Layers.Emitter(groundAtt, {
		Texture = ASSETS.SoftGlow,
		Shape = "Disc",
		ShapeStyle = "Volume",
		Lifetime = { 1.1, 1.6 },
		Speed = { 2.5 * s, 4.5 * s },
		EmissionDirection = "Top",
		SpreadAngle = 6,
		Drag = 0.6,
		LightEmission = 0.6,
		Brightness = 1.2,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 0 }, { 0.15, 0.9 * s }, { 1, 0.2 * s } },
		Transparency = { { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } },
	})
	-- Shape "Disc" emits over the parent part's footprint: give the ground anchor that size
	groundAtt.Parent.Size = Vector3.new(p.RingSize * 0.45 * s, 0.1, p.RingSize * 0.45 * s)

	-- one moving attachment per strand: a burst each frame leaves a ribbon of motes behind
	local strands = {}
	for i = 1, p.Strands do
		local att = Layers.Attachment(groundAtt.Parent)
		local hue = if i % 2 == 0 then p.AccentColor else p.Color
		local mote = Layers.Emitter(att, {
			Texture = ASSETS.SoftGlow,
			Lifetime = { 0.45, 0.7 },
			Speed = 0.4 * s,
			SpreadAngle = 180,
			LightEmission = 1,
			Brightness = 1.4,
			Color = { { 0, hue }, { 1, p.DeepColor } }, -- start on the hue, or overlapping motes blow out
			Size = { { 0, 0.75 * s }, { 1, 0 } },
		})
		local speck = Layers.Dim(mote, 1, { Texture = ASSETS.Speck, Size = { { 0, 0.25 * s }, { 1, 0 } } })
		strands[i] = { Att = att, Mote = mote, Speck = speck, Phase = (i - 1) / p.Strands * 2 * math.pi }
	end

	local highlight
	if p.Character then
		highlight = Instance.new("Highlight")
		highlight.Adornee = p.Character
		highlight.FillColor = p.Color
		highlight.OutlineColor = p.HotColor
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = ctx.Folder -- Adornee points at the character; it lives in the folder
	end
	local light = Layers.Light(chestAtt, { Color = p.Color })

	local function spiral()
		local radius = 2.8 * s -- outside an R15 torso
		local age = 0
		while age < p.SpiralTime do
			age += ctx.Wait(1 / 60)
			if not ctx.Folder.Parent then
				return
			end
			local t = math.min(age / p.SpiralTime, 1)
			local eased = 1 - (1 - t) * (1 - t) -- quick start, slows near the top
			for _, strand in strands do
				local angle = strand.Phase + eased * 2.2 * math.pi
				local r = radius * (1 - 0.4 * t) -- tightens as it climbs
				strand.Att.Position = Vector3.new(math.cos(angle) * r, eased * p.Height * s, math.sin(angle) * r)
				ctx.Emit(strand.Mote, 1)
				if math.random() < 0.5 then
					ctx.Emit(strand.Speck, 1)
				end
			end
		end
	end

	Layers.Timeline(ctx, {
		{
			0,
			function()
				ctx.Emit(flash, 1)
				Layers.Pop(ctx, light, p.LightBrightness, 4 * s, p.LightRange * s, 0.9)
				if highlight then
					highlight.FillTransparency = p.HighlightTransparency
					highlight.OutlineTransparency = 0.3
					ctx.Tween(highlight, 0.9, { FillTransparency = 1, OutlineTransparency = 1 })
				end
			end,
		},
		{
			0.04,
			function()
				ctx.Emit(ring, 1)
				ctx.Emit(glow, 1)
			end,
		},
		{
			0.08,
			function()
				if not p.Reduced then
					ctx.Emit(sparkles, p.SparkleCount)
					task.spawn(spiral)
				end
			end,
		},
		{
			0.5,
			function()
				if not p.Reduced then
					ctx.Emit(column, p.ColumnCount)
				end
			end,
		},
	})
end

return Effect
