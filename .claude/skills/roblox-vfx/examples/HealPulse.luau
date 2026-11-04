-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/HealPulse
-- A heal on a character: a soft flash at the chest, a ground ring that grows and fades, a
-- breathing ground glow, motes that spiral up around the body (attachments moved along a
-- helix, one burst per frame), plus-shaped sparkles rising, and a Highlight that washes
-- the character green and fades. Pulses Pulses times, Interval apart (heal over time).
-- Layers: chest flash, ground ring, ground glow, spiral motes (x Strands), rising sparkles,
-- character Highlight, light.
--
-- ctx.CFrame = the character's root. Runtime-only override:
--   Character (Model)  gets the Highlight; nil = no Highlight.

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
	Color = Color3.fromRGB(90, 255, 140), -- the hue
	HotColor = Color3.fromRGB(230, 255, 225), -- near-white highlights
	DeepColor = Color3.fromRGB(20, 140, 80), -- deep end of the gradients
	Scale = 1,
	Pulses = 1, -- heal ticks
	Interval = 1.6, -- seconds between ticks
	RingSize = 9, -- studs: ground ring's final diameter
	Height = 7, -- studs the spiral rises
	Strands = 3, -- spiral strands, evenly spaced round the body
	SpiralTime = 0.7, -- seconds for a strand to climb Height
	SparkleCount = 8,
	HighlightTransparency = 0.55, -- Highlight fill at its strongest (1 = off)
	LightBrightness = 3,
	LightRange = 12,
}

Effect.Linger = 0.9 -- the last tick's motes (0.6 s) and sparkles (0.8 s)

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale

	local root = ctx.CFrame.Position
	local groundPos = Layers.Ground(ctx)
	local groundAtt = Layers.Attachment(ctx.Anchor(CFrame.new(groundPos + Vector3.new(0, 0.1, 0))))
	local chestAtt = Layers.Attachment(ctx.Anchor(CFrame.new(root + Vector3.new(0, 0.5 * s, 0))))

	local flash = Layers.Emitter(chestAtt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.12,
		Rotation = { -10, 10 },
		LightEmission = 1,
		Brightness = 4,
		ZOffset = 2,
		Color = p.HotColor,
		Size = { { 0, 2 * s }, { 0.3, 6 * s }, { 1, 6.5 * s } },
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local ring = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.6,
		Rotation = { 0, 360 },
		LightEmission = 0.4,
		Brightness = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 1 * s }, { 0.5, p.RingSize * 0.9 * s }, { 1, p.RingSize * s } },
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local glow = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.GroundDisc,
		Lifetime = 1,
		LightEmission = 0.6,
		Brightness = 1,
		Color = p.Color,
		Size = { { 0, p.RingSize * 0.5 * s }, { 0.3, p.RingSize * 0.7 * s }, { 1, p.RingSize * 0.6 * s } },
		Transparency = { { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } },
	})
	local sparkles = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Sparkle,
		Shape = "Disc",
		ShapeStyle = "Volume",
		Lifetime = { 0.5, 0.8 },
		Speed = { 4 * s, 9 * s },
		EmissionDirection = "Top",
		SpreadAngle = 10,
		Drag = 2,
		LightEmission = 1,
		Brightness = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0 }, { 0.2, 1.1 * s }, { 1, 0 } },
	})
	-- Shape "Disc" emits over the parent part's footprint: give the ground anchor that size
	groundAtt.Parent.Size = Vector3.new(p.RingSize * 0.6 * s, 0.1, p.RingSize * 0.6 * s)

	-- one moving attachment per strand: a burst each frame leaves a ribbon of motes behind
	local strands = {}
	for i = 1, p.Strands do
		local att = Layers.Attachment(groundAtt.Parent)
		local mote = Layers.Emitter(att, {
			Texture = ASSETS.SoftGlow,
			Lifetime = { 0.4, 0.6 },
			Speed = 0.5 * s,
			SpreadAngle = 180,
			LightEmission = 1,
			Brightness = 1.5,
			Color = { { 0, p.Color }, { 1, p.DeepColor } }, -- overlapping additive motes blow out to white if they start hot
			Size = { { 0, 0.7 * s }, { 1, 0 } },
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
		local radius = 2.8 * s -- outside the body: at 1.6 the strands were hidden inside an R15 torso
		local age = 0
		while age < p.SpiralTime do
			age += ctx.Wait(1 / 60)
			if not ctx.Folder.Parent then
				return
			end
			local t = math.min(age / p.SpiralTime, 1)
			local eased = 1 - (1 - t) * (1 - t) -- quick start, slows near the top
			for _, strand in strands do
				local angle = strand.Phase + eased * 2.5 * math.pi
				local r = radius * (1 - 0.45 * t) -- tightens as it climbs
				strand.Att.Position = Vector3.new(math.cos(angle) * r, eased * p.Height * s, math.sin(angle) * r)
				ctx.Emit(strand.Mote, 1)
				if math.random() < 0.5 then
					ctx.Emit(strand.Speck, 1)
				end
			end
		end
	end

	for tick = 1, p.Pulses do
		ctx.Emit(flash, 1)
		ctx.Emit(ring, 1)
		ctx.Emit(glow, 1)
		ctx.Emit(sparkles, p.SparkleCount)
		Layers.Pop(ctx, light, p.LightBrightness, 4 * s, p.LightRange * s, 0.6)
		if highlight then
			highlight.FillTransparency = p.HighlightTransparency
			highlight.OutlineTransparency = 0.2
			ctx.Tween(highlight, 0.6, { FillTransparency = 1, OutlineTransparency = 1 })
		end
		spiral()
		if not ctx.Folder.Parent then
			return
		end
		if tick < p.Pulses then
			ctx.Wait(math.max(p.Interval - p.SpiralTime, 0))
		end
	end
end

return Effect
