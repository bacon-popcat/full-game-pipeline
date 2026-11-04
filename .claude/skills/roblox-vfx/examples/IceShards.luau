-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/IceShards
-- Ice erupting from the ground: a ring of crystal shards that stab up out of the floor
-- (Back Out, staggered round the ring), a white-blue flash, a frost ring and cold mist
-- creeping out, glints winking on the crystals, then the shards shatter into flung
-- pieces (MeshParticles) and a puff of frost. Shows mesh templates cloned with a
-- plain-part fallback, MeshParticles, and the frost/ice palette.
-- Layers: flash, frost ring, shards (Count, cloned meshes), mist (warm/cool), glints,
-- shatter pieces (MeshParticles), shatter frost, light.
--
-- Mesh templates from ReplicatedStorage/Assets/Meshes if they exist (Shard: MeshFactory
-- Shard, ~2 studs long along Y), else plain parts, so it works right away.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	Mist = "rbxassetid://111394301752764", -- StaticVFXTextures/smoke 41 (soft puff)
	Sparkle = "rbxassetid://16444981264", -- StaticVFXTextures/Star153 (small 4-point sparkle)
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
}

local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")

-- A template must never yield or error at require time (the harness requires every effect
-- at startup), so look it up with FindFirstChild and build a stand-in once if it's missing.
local fallbacks = {}
local function getTemplate(name)
	local template = meshFolder and meshFolder:FindFirstChild(name)
	if template then
		return template
	end
	if not fallbacks[name] then
		local part = Instance.new("WedgePart") -- a crisp, angular stand-in for a crystal
		part.Size = Vector3.new(0.6, 2, 0.8)
		fallbacks[name] = part
	end
	return fallbacks[name]
end

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(150, 220, 255), -- ice
	HotColor = Color3.fromRGB(240, 252, 255), -- white highlights
	DeepColor = Color3.fromRGB(40, 110, 200), -- deep blue gradient ends
	MistColor = Color3.fromRGB(205, 230, 245), -- pale cold mist
	CoolMistColor = Color3.fromRGB(160, 180, 210), -- its greyer pair
	Scale = 1,
	Count = 9, -- shards round the ring
	RingRadius = 5, -- studs
	ShardHeight = 5, -- studs: the tallest shard
	RiseTime = 0.18, -- seconds for one shard to stab up
	Stagger = 0.025, -- seconds between neighbouring shards
	Hold = 0.9, -- seconds the shards stand
	Shatter = true, -- false = the shards sink back into the ground instead
	PieceCount = 18, -- shatter pieces (MeshParticles; keep under ~40)
	MistCount = 5, -- per mist layer
	LightBrightness = 6,
	LightRange = 18,
}

Effect.Linger = 1.2 -- shatter pieces (up to 0.9 s) and the frost puff (slowed) after the break

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local ringR = p.RingRadius * s

	local ground = Layers.Ground(ctx)
	local frame = Layers.Frame(ctx, ground)
	local att = Layers.Attachment(ctx.Anchor(frame + Vector3.new(0, 1 * s, 0)))
	local floorAtt = Layers.Attachment(ctx.Anchor(frame + Vector3.new(0, 0.1, 0)))

	local flash = Layers.Emitter(att, {
		Texture = ASSETS.Flash,
		Lifetime = 0.08,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 6,
		ZOffset = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 2 * s }, { 0.3, 2.2 * ringR }, { 1, 2.4 * ringR } },
		Transparency = { { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } },
	})
	local frostRing = Layers.Emitter(floorAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.5,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 1 * s }, { 0.5, 2.6 * ringR }, { 1, 3 * ringR } },
		Transparency = { { 0, 0 }, { 1, 1.2 } },
	})
	local function mist(color)
		return Layers.Emitter(floorAtt, {
			Texture = ASSETS.Mist,
			EmissionDirection = "Top",
			SpreadAngle = { 80, 80 },
			Speed = { 4 * s, 9 * s },
			Drag = 3,
			Acceleration = Vector3.new(0, -2 * s, 0), -- cold air sinks and creeps out
			Lifetime = { 0.9, 1.3 },
			Rotation = { 0, 360 },
			RotSpeed = { -30, 30 },
			LightEmission = 0,
			Brightness = 1.2,
			Color = color,
			Size = { { 0, 2 * s }, { 1, 5 * s } },
			Transparency = { { 0, 1 }, { 0.2, 0.55 }, { 1, 1 } },
		})
	end
	local mistWarm = mist(p.MistColor)
	local mistCool = mist(p.CoolMistColor)
	local frostPuff = Layers.Twin(mistWarm, { EmissionDirection = "Top", SpreadAngle = { 180, 180 }, Speed = { 8 * s, 14 * s }, Lifetime = { 0.5, 0.8 } })

	-- shards: cloned meshes standing round the ring, each tilted outward, sized at random
	local template = getTemplate("Shard")
	local shards = {}
	for i = 1, p.Count do
		local angle = (i - 1) / p.Count * 2 * math.pi + math.random() * 0.3
		local height = p.ShardHeight * s * (0.6 + 0.4 * math.random())
		local base = frame * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -ringR)
		-- lean outward 15-35 degrees and twist a little, so the ring isn't a fence
		local stand = base * CFrame.Angles(-math.rad(15 + 20 * math.random()), 0, math.rad(math.random(-10, 10)))
		local size = Vector3.new(template.Size.X / template.Size.Y, 1, template.Size.Z / template.Size.Y) * height
		local shard = Layers.Quiet(template:Clone())
		shard.Material = Enum.Material.Glass
		shard.Color = p.Color
		shard.Transparency = 0.15
		shard.Size = size
		-- start buried: its top just under the floor
		shard.CFrame = stand * CFrame.new(0, -height * 0.55, 0)
		shard.Parent = ctx.Folder
		local glintAtt = Layers.Attachment(shard, CFrame.new(0, height * 0.3, 0))
		local glint = Layers.Emitter(glintAtt, {
			Texture = ASSETS.Sparkle,
			Lifetime = 0.25,
			RotSpeed = 180,
			LightEmission = 1,
			Brightness = 4,
			ZOffset = 1,
			Color = p.HotColor,
			Size = { { 0, 0 }, { 0.3, 1.4 * s }, { 1, 0 } },
		})
		shards[i] = { Part = shard, Stand = stand, Height = height, Glint = glint, Delay = (i - 1) * p.Stagger }
	end

	-- MeshParticles clones its template as-is, so give the pieces the ice look once here
	local pieceTemplate = template:Clone()
	pieceTemplate.Material = Enum.Material.Glass
	pieceTemplate.Color = p.Color

	local light = Layers.Light(att, { Color = p.Color })

	-- rise: each shard on its own step, staggered round the ring
	local events = {
		{ 0, function()
			ctx.Emit(flash, 1)
			ctx.Emit(frostRing, 1)
			Layers.Pop(ctx, light, p.LightBrightness, 6 * s, p.LightRange * s, 0.7)
		end },
		{ 0.04, function()
			Layers.Emit(ctx, mistWarm, p.MistCount, 0.7)
			Layers.Emit(ctx, mistCool, p.MistCount, 0.7)
		end },
	}
	for _, shard in shards do
		table.insert(events, { shard.Delay, function()
			ctx.Tween(shard.Part, p.RiseTime, { CFrame = shard.Stand * CFrame.new(0, shard.Height * 0.45, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end })
		table.insert(events, { shard.Delay + p.RiseTime + math.random() * p.Hold * 0.6, function()
			ctx.Emit(shard.Glint, 1)
		end })
	end
	local breakAt = (p.Count - 1) * p.Stagger + p.RiseTime + p.Hold
	table.insert(events, { breakAt, function()
		if p.Shatter then
			for _, shard in shards do
				local centre = shard.Part.Position
				shard.Part:Destroy()
				-- pieces fly out from each shard, a few per shard
				MeshParticles.Burst(ctx, pieceTemplate, math.max(1, math.floor(p.PieceCount / p.Count)), {
					Origin = centre,
					Direction = (centre - ground).Unit + Vector3.yAxis,
					Spread = 60,
					Speed = NumberRange.new(10 * s, 22 * s),
					Lifetime = NumberRange.new(0.5, 0.9),
					Acceleration = Vector3.new(0, -70 * s, 0),
					SpinSpeed = NumberRange.new(300, 720),
					Scale = shard.Height / template.Size.Y * 0.25,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.15),
						NumberSequenceKeypoint.new(0.7, 0.3),
						NumberSequenceKeypoint.new(1, 1),
					}),
					SpawnRadius = shard.Height * 0.3,
				})
			end
			Layers.Emit(ctx, frostPuff, p.MistCount, 0.8)
			Layers.Pop(ctx, light, p.LightBrightness * 0.6, 4 * s, p.LightRange * 0.7 * s, 0.4)
		else
			for _, shard in shards do
				ctx.Tween(shard.Part, 0.5, { CFrame = shard.Stand * CFrame.new(0, -shard.Height * 0.55, 0), Transparency = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
	end })
	-- in sink mode, hold Play until the shards are under the floor
	table.insert(events, { breakAt + (if p.Shatter then 0 else 0.5), function() end })

	Layers.Timeline(ctx, events)
end

return Effect
