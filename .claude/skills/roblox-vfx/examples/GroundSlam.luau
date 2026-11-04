-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/GroundSlam
-- A slam into the ground: a spiky flash, impact stars (colour/black/white) over a black
-- backing, a neon shock ring that flattens, widens and spins, a flat ground ring, a dust
-- body that keeps swelling and rising for a second after the flash (warm and cool mottled
-- dust, a squashed ground skirt, black grit), rocks thrown up, energy streaks, wind arcs,
-- and a crater of rocks in the ground's own material that grow, hold and sink.
-- Layers: flash + flare, stars, backing, shock mesh, ground ring, dust warm/cool + skirt +
-- column, grit, rocks (MeshParticles), streaks, wind, crater, light.
--
-- Mesh templates from ReplicatedStorage/Assets/Meshes if they exist (ShockRing: a flat
-- ring, Y up; Rock: ~1 stud chunk), else plain parts, so it works right away.

local VFX = script.Parent.Parent
local MeshParticles = require(VFX:WaitForChild("MeshParticles"))
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	SoftGlow = "rbxassetid://284205403", -- StaticVFXTextures/Blurred Spec 11
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	WindArc = "rbxassetid://17388365742", -- StaticVFXTextures/Crescent18 (thin clean crescent)
	ImpactStar = Textures.ImpactStar, -- drawn: assets/textures/impact.py (Grid4x4)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
	Dust = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
	Splinters = Textures.Splinters, -- drawn: assets/textures/impact.py (Grid4x4)
}

local meshRoot = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local meshFolder = meshRoot and meshRoot:FindFirstChild("Meshes")

local fallbacks = {}
local function getTemplate(name)
	local template = meshFolder and meshFolder:FindFirstChild(name)
	if template then
		return template, false
	end
	if not fallbacks[name] then
		local part = Instance.new("Part")
		if name == "ShockRing" then
			part.Shape = Enum.PartType.Cylinder -- disc; axis is X
			part.Size = Vector3.new(0.2, 2, 2)
		else
			part.Size = Vector3.new(0.8, 0.6, 0.7)
		end
		fallbacks[name] = part
	end
	return fallbacks[name], true
end

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(150, 210, 255), -- energy: flash, stars, ring, streaks
	DeepColor = Color3.fromRGB(45, 95, 210), -- deep end of the energy gradients
	DustColor = Color3.fromRGB(150, 140, 128), -- warm grey dust
	CoolDustColor = Color3.fromRGB(120, 124, 132), -- its cool grey pair
	RockColor = Color3.fromRGB(110, 100, 95), -- thrown rocks (crater rocks copy the ground)
	Scale = 1,
	Radius = 6, -- studs: the impact's radius (R)
	RingSize = 18, -- studs: the shock ring's final radius
	RingTime = 0.35,
	RockCount = 14,
	RockSpeed = 38,
	DustCount = 7, -- per dust layer (warm, cool)
	StreakCount = 14,
	CraterCount = 8, -- rocks left round the impact (0 = none)
	CraterHold = 1.4, -- seconds the crater holds before it sinks
	LightBrightness = 9,
	LightRange = 26,
}

Effect.Linger = 1.4 -- dust (slowed to 0.75x: up to ~1.75 s) and the crater's 1 s sink

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local R = p.Radius * s

	local ground, hit = Layers.Ground(ctx)
	local frame = Layers.Frame(ctx, ground)
	local anchor = ctx.Anchor(frame)
	local groundAtt = Layers.Attachment(anchor, CFrame.new(0, 0.15 * s, 0))
	local att = Layers.Attachment(anchor, CFrame.new(0, 1.2 * s, 0))

	-- flash and the three-value impact stack ----------------------------------------
	local flash = Layers.Emitter(att, {
		Texture = ASSETS.Flash,
		Lifetime = 0.09,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 9,
		ZOffset = 4,
		Color = { { 0, Layers.WHITE }, { 1, p.Color } },
		Size = { { 0, 0.6 * R }, { 0.3, 2.5 * R }, { 1, 2.7 * R } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local flare = Layers.Emitter(att, {
		Texture = ASSETS.Glint,
		Lifetime = 0.07,
		LightEmission = 1,
		Brightness = 7,
		ZOffset = 4.1,
		Color = Layers.WHITE,
		Size = { { 0, 2.5 * R }, { 1, 3.2 * R } },
		Squash = -4,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})
	local stars = Layers.Emitter(att, {
		Texture = ASSETS.ImpactStar,
		Lifetime = { 0.1, 0.15 },
		Rotation = { 0, 360 },
		LightEmission = -1,
		Brightness = 5,
		ZOffset = 2,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 1.2 * R }, { 0.25, 2 * R, 0.35 * R }, { 1, 2.2 * R, 0.35 * R } },
	})
	local blackStars = Layers.Black(stars, 0.25)
	local whiteStar = Layers.White(stars, { Lifetime = { 0.06, 0.1 }, Brightness = 3, Size = { { 0, 0.5 * R }, { 1, 0.8 * R } } })
	local backing = Layers.Emitter(att, {
		Texture = ASSETS.SoftGlow,
		Lifetime = 0.35,
		LightEmission = 0,
		ZOffset = -1,
		Color = Layers.BLACK,
		Size = { { 0, 2 * R }, { 1, 3.2 * R } },
		Transparency = { { 0, 0.35 }, { 1, 1 } },
	})

	-- a flat ring on the ground (particle), under the mesh ring --------------------------
	local groundRing = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.4,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 3,
		ZOffset = 0.5,
		Color = { { 0, Layers.WHITE }, { 1, p.Color } },
		Size = { { 0, 0.4 * R }, { 0.4, 2.4 * R }, { 1, 2.8 * R } },
		Transparency = { { 0, 0 }, { 1, 1.3 } },
	})

	-- dust body: warm and cool mottled dust that bursts out low, then swells and hangs ----
	local function dustLayer(color, zOffset)
		return Layers.Emitter(groundAtt, {
			Texture = ASSETS.Dust,
			EmissionDirection = "Top",
			SpreadAngle = 75,
			Lifetime = { 0.9, 1.3 },
			Speed = { 6 * R, 10 * R },
			Drag = 4,
			Acceleration = Vector3.new(0, 2 * s, 0),
			Rotation = { 0, 360 },
			RotSpeed = { -20, 20 },
			LightEmission = 0,
			Brightness = 1.6,
			ZOffset = zOffset,
			Color = color,
			Size = { { 0, 0.7 * R, 0.2 * R }, { 0.4, 1.6 * R, 0.4 * R }, { 1, 2 * R, 0.4 * R } },
			-- daylight: fairly solid at its peak so it keeps its own grey against the sky
			Transparency = { { 0, 0.5 }, { 0.15, 0.28 }, { 1, 1.1 } },
		})
	end
	local warmDust = dustLayer(p.DustColor, 0)
	local coolDust = dustLayer(p.CoolDustColor, -0.05)
	local skirt = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.Dust,
		Lifetime = 1.2,
		Rotation = { 0, 360 },
		RotSpeed = { -15, 15 },
		LightEmission = 0,
		Brightness = 1.4,
		Color = p.DustColor,
		Size = { { 0, 1.2 * R }, { 0.5, 2.8 * R }, { 1, 3.2 * R } },
		Squash = -0.5,
		Transparency = { { 0, 0.55 }, { 0.2, 0.4 }, { 1, 1 } },
	})
	-- something thrown up: a short column of dust so the hit doesn't stay a flat splash
	local column = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Dust,
		Orientation = "FacingCameraWorldUp",
		EmissionDirection = "Top",
		SpreadAngle = 12,
		Lifetime = { 0.8, 1.1 },
		Speed = { 9 * R, 13 * R },
		Drag = 5,
		Rotation = { -20, 20 },
		LightEmission = 0,
		Brightness = 1.5,
		ZOffset = 0.2,
		Color = p.CoolDustColor,
		Size = { { 0, 0.8 * R }, { 1, 1.7 * R, 0.3 * R } },
		Squash = 0.6,
		Transparency = { { 0, 0.5 }, { 0.2, 0.35 }, { 1, 1.1 } },
	})
	local grit = Layers.Emitter(groundAtt, {
		Texture = ASSETS.Splinters,
		EmissionDirection = "Top",
		SpreadAngle = 60,
		Lifetime = { 0.5, 0.8 },
		Speed = { 5 * R, 10 * R },
		Acceleration = Vector3.new(0, -70 * s, 0),
		Rotation = { 0, 360 },
		RotSpeed = { -200, 200 },
		LightEmission = 0,
		ZOffset = 1,
		Color = Color3.fromRGB(30, 28, 26),
		Size = { { 0, 0.25 * R, 0.1 * R }, { 1, 0.2 * R } },
	})

	-- energy streaks shooting up and out ------------------------------------------------
	local streaks = Layers.Emitter(att, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		EmissionDirection = "Top",
		SpreadAngle = 70,
		Lifetime = { 0.15, 0.3 },
		Speed = { 15 * R, 35 * R },
		Drag = 10,
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 3,
		Color = { { 0, Layers.WHITE }, { 1, p.Color } },
		Size = { { 0, 0.22 * R, 0.08 * R }, { 1, 0 } },
		Squash = { { 0, 3 }, { 1, 1 } },
	})
	local blackStreaks = Layers.Black(streaks, 0.1, { Speed = { 8 * R, 20 * R } })

	-- wind arcs: nearly transparent grey crescents flat round the base, over the dust -----
	local wind = Layers.Emitter(groundAtt, {
		Flat = true,
		Texture = ASSETS.WindArc,
		Lifetime = { 0.45, 0.6 },
		Speed = 2 * s, -- rise a little as they spin out
		Rotation = { 0, 360 },
		RotSpeed = { -20, 20 },
		LightEmission = 1,
		Brightness = 1,
		ZOffset = 0.5,
		Color = Color3.fromRGB(225, 230, 238),
		Size = { { 0, 1.5 * R }, { 0.6, 4.5 * R }, { 1, 5 * R } },
		Transparency = { { 0, 0.55 }, { 0.6, 0.8 }, { 1, 1.1 } },
	})

	local light = Layers.Light(att, { Color = p.Color })

	-- shock ring mesh: flattens while it widens and spins -------------------------------
	local function shockRing()
		local template, isFallback = getTemplate("ShockRing")
		local ring = Layers.Quiet(template:Clone())
		ring.Material = Enum.Material.Neon
		ring.Color = p.Color
		ring.Transparency = 0
		local tilt = if isFallback then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity
		local base = CFrame.new(ground + Vector3.new(0, 0.2 * s, 0)) * tilt
		ring.CFrame = base
		local start = template.Size * s
		local grow = 2 * p.RingSize * s / math.max(start.Z, 0.01) -- to RingSize radius
		-- the fallback disc's axis is X (height), so X is the one that flattens
		local final = if isFallback
			then Vector3.new(start.X * 0.25, start.Y * grow, start.Z * grow)
			else Vector3.new(start.X * grow, start.Y * 0.2, start.Z * grow)
		ring.Size = start
		ring.Parent = ctx.Folder
		ctx.Tween(ring, p.RingTime, { Size = final, Transparency = 1 }, Enum.EasingStyle.Cubic)
		local spin = if isFallback then CFrame.Angles(math.rad(150), 0, 0) else CFrame.Angles(0, math.rad(150), 0)
		ctx.Tween(ring, p.RingTime, { CFrame = base * spin }, Enum.EasingStyle.Cubic)
	end

	-- crater: rocks in the hit surface's material and colour, tilted outward ------------
	local craterRocks = {}
	local function crater()
		local template, isFallback = getTemplate("Rock")
		-- RaycastResult.Material works for terrain too; only parts have a Color
		local material = if hit then hit.Material else Enum.Material.Slate
		local color = if hit and hit.Instance:IsA("BasePart") then hit.Instance.Color else p.RockColor
		for i = 1, p.CraterCount do
			local a = (i / p.CraterCount) * math.pi * 2 + (math.random() - 0.5) * 0.6
			local r = R * (0.7 + math.random() * 0.6)
			local tiltOut = math.rad(15 + math.random() * 35)
			local cf = frame
				* CFrame.Angles(0, -a, 0)
				* CFrame.new(r, 0, 0)
				* CFrame.Angles(0, 0, tiltOut) -- tip outward, away from the centre
			local rock = Layers.Quiet(template:Clone())
			rock.Material = material
			rock.Color = color
			local size = template.Size * s * (1.6 + math.random() * 1.4)
			if isFallback then
				size = Vector3.new(size.X, size.Y * 1.4, size.Z)
			end
			rock.Size = size * 0.2
			rock.CFrame = cf * CFrame.new(0, -size.Y * 0.4, 0)
			rock.Parent = ctx.Folder
			ctx.Tween(rock, 0.4, { Size = size, CFrame = cf * CFrame.new(0, size.Y * 0.15, 0) }, Enum.EasingStyle.Back)
			table.insert(craterRocks, { Part = rock, CFrame = cf, Size = size })
		end
	end

	Layers.Timeline(ctx, {
		{ 0, function()
			ctx.Emit(flash, 1)
			ctx.Emit(flare, 1)
			Layers.Pop(ctx, light, p.LightBrightness, 6 * s, p.LightRange * s, 0.6)
			crater()
		end },
		{ 0.03, function()
			ctx.Emit(stars, 3)
			ctx.Emit(blackStars, 3)
			ctx.Emit(whiteStar, 1)
			ctx.Emit(backing, 1)
			ctx.Emit(groundRing, 1)
			shockRing()
		end },
		{ 0.05, function()
			Layers.Emit(ctx, warmDust, p.DustCount, 0.75)
			Layers.Emit(ctx, coolDust, p.DustCount, 0.75)
			Layers.Emit(ctx, skirt, 2, 0.8)
			ctx.Emit(streaks, p.StreakCount)
			ctx.Emit(blackStreaks, math.ceil(p.StreakCount / 3))
			ctx.Emit(grit, 6)
			local rockTemplate, rockIsFallback = getTemplate("Rock")
			if rockIsFallback then
				rockTemplate.Color = p.RockColor
				rockTemplate.Material = Enum.Material.Slate
			end
			MeshParticles.Burst(ctx, rockTemplate, p.RockCount, {
				Origin = ground + Vector3.new(0, 0.5 * s, 0),
				Direction = Vector3.yAxis,
				Spread = 50,
				Speed = NumberRange.new(p.RockSpeed * s * 0.6, p.RockSpeed * s),
				Lifetime = NumberRange.new(0.7, 1.1),
				Acceleration = Vector3.new(0, -110 * s, 0),
				SpinSpeed = NumberRange.new(180, 540),
				Scale = s,
				SpawnRadius = 0.25 * R,
				Size = Layers.Seq({ { 0, 1 }, { 0.75, 1 }, { 1, 0 } }),
			})
		end },
		{ 0.08, function()
			Layers.Emit(ctx, column, 3, 0.8)
			Layers.Emit(ctx, wind, 4, 0.85)
		end },
		{ 0.4 + p.CraterHold, function()
			for _, rock in craterRocks do
				ctx.Tween(rock.Part, 1, {
					Size = rock.Size * 0.4,
					CFrame = rock.CFrame * CFrame.new(0, -rock.Size.Y * 0.6, 0),
					Transparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end },
	})
end

return Effect
