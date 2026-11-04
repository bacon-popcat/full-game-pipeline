-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/EnergyBolt
-- A thrown energy bolt: a launch smear at the hand, a head that flies a curved Bezier path
-- to the target with a sharp and a soft textured ribbon and shed specks, then a small hit
-- built on the impact skeleton (flash, stars with black twins, streaks, ring, light).
-- Layers: launch smear + muzzle ring, head glow + core, sharp trail, soft trail, specks,
-- hit flash, hit stars (colour/black/white), hit streaks + black streaks, hit ring, light.
--
-- ctx.CFrame = the launch point, LookVector toward the target. Runtime-only override:
--   Target (Vector3)  where the bolt lands; nil = Distance studs along LookVector.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Flash = "rbxassetid://136210055019402", -- Custom: Starburst (filled spiky shape, white)
	SoftGlow = "rbxassetid://87365446017300", -- lava_glow (custom): soft glow that reaches 0 at the edge
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle)
	SoftTrail = "rbxassetid://85104342894286", -- cs_soft_trail (custom): soft fibrous strip, Wrap-safe
	ImpactStar = Textures.ImpactStar, -- drawn: assets/textures/impact.py (Grid4x4)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
	ShockRing = Textures.ShockRing, -- drawn: assets/textures/impact.py
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(90, 200, 255), -- the hue
	HotColor = Color3.fromRGB(225, 250, 255), -- white-hot head, smear and flash
	DeepColor = Color3.fromRGB(30, 70, 200), -- deep end of every gradient
	Scale = 1,
	Distance = 60, -- studs flown when no Target override is given
	Speed = 90, -- studs a second along the path
	Arc = 8, -- studs the path bows up (and a little sideways) at its middle
	HeadSize = 1.6,
	SpeckRate = 45,
	HitRadius = 3.5, -- studs: R of the hit
	StreakCount = 10,
	LightBrightness = 8,
	LightRange = 14,
}

Effect.Linger = 0.5 -- light (0.4 s), specks (0.4 s) and hit streaks (0.3 s) after the hit

-- Quadratic Bezier point and its tangent at t.
local function bezier(a, b, c, t)
	local u = 1 - t
	local point = a * (u * u) + b * (2 * u * t) + c * (t * t)
	local tangent = (b - a) * (2 * u) + (c - b) * (2 * t)
	return point, tangent
end

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local timeScale = ctx.TimeScale

	local start = ctx.CFrame.Position
	local target = p.Target or (start + ctx.CFrame.LookVector * p.Distance * s)
	local span = target - start
	local side = span:Cross(Vector3.yAxis)
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	-- one random sideways lean per throw, so a volley of these never overlaps
	local control = start + span * 0.5 + Vector3.yAxis * p.Arc * s + side * p.Arc * s * (math.random() - 0.5)
	local flightTime = math.max(span.Magnitude / (p.Speed * s), 0.1)

	-- launch: a one-frame squashed smear along the throw and a ring shed backwards
	local launchAtt = Layers.Attachment(ctx.Anchor())
	local smear = Layers.Emitter(launchAtt, {
		Texture = ASSETS.Needle,
		Orientation = "VelocityParallel",
		EmissionDirection = "Front",
		SpreadAngle = 0,
		Speed = 300 * s,
		Lifetime = 0.04,
		LightEmission = 1,
		Brightness = 6,
		Color = p.HotColor,
		Size = 3 * s,
		Squash = -0.5,
	})
	local muzzleRing = Layers.Emitter(launchAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		EmissionDirection = "Front", -- ring faces along the throw
		Speed = -6 * s,
		Lifetime = 0.3,
		LightEmission = 0.3,
		Brightness = 3,
		Color = p.Color,
		Size = { { 0, 1 * s }, { 1, 6 * s } },
		Transparency = { { 0, 0.2 }, { 1, 1 } },
	})

	-- the head travels on its own part; trails hang between attachments either side of it
	local headPart = ctx.Anchor(CFrame.new(start))
	local head = Layers.Attachment(headPart)
	local sharpA = Layers.Attachment(headPart, CFrame.new(0, 0.4 * s, 0))
	local sharpB = Layers.Attachment(headPart, CFrame.new(0, -0.4 * s, 0))
	local softA = Layers.Attachment(headPart, CFrame.new(0, 1.2 * s, 0))
	local softB = Layers.Attachment(headPart, CFrame.new(0, -1.2 * s, 0))

	local glow = Layers.Emitter(head, {
		Texture = ASSETS.SoftGlow,
		LockedToPart = true,
		Lifetime = flightTime + 0.05,
		LightEmission = 1,
		Brightness = 3,
		ZOffset = 0.5,
		Color = p.Color,
		Size = 2.2 * p.HeadSize * s,
		Transparency = 0.3,
	})
	local core = Layers.Emitter(head, {
		Texture = ASSETS.Glint,
		LockedToPart = true,
		Lifetime = flightTime + 0.05,
		RotSpeed = 400,
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 1,
		Color = p.HotColor,
		Size = p.HeadSize * s,
	})
	local specks = Layers.Emitter(head, {
		Texture = ASSETS.Speck,
		Rate = p.SpeckRate,
		Enabled = false,
		Lifetime = { 0.2, 0.4 },
		Speed = { 1 * s, 4 * s },
		SpreadAngle = 180,
		Drag = 4,
		LightEmission = 1,
		Brightness = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.18 * s }, { 1, 0 } },
	})

	-- Trail.Lifetime is real time: divide by the play's TimeScale so slow-mo keeps its length
	local sharp = Instance.new("Trail")
	Layers.Apply(sharp, {
		Attachment0 = sharpA,
		Attachment1 = sharpB,
		Texture = ASSETS.Needle,
		Lifetime = 0.18 / timeScale,
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = 0.5,
		Brightness = 8,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Transparency = { { 0, 1 }, { 0.12, 0 }, { 1, 1 } }, -- a gap behind the head
		WidthScale = { { 0, 1 }, { 1, 0 } },
	})
	sharp.Parent = headPart
	local soft = Instance.new("Trail")
	Layers.Apply(soft, {
		Attachment0 = softA,
		Attachment1 = softB,
		Texture = ASSETS.SoftTrail,
		TextureMode = "Wrap",
		Lifetime = 0.2 / timeScale, -- ~18 studs at Speed 90: a few heads long, not back to the thrower
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = 0.2,
		Brightness = 2,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Transparency = { { 0, 0.35 }, { 1, 1 } },
		WidthScale = { { 0, 0.6 }, { 0.35, 1 }, { 1, 0 } }, -- bulges in the middle
	})
	soft.Parent = headPart

	-- hit layers wait at the target
	local R = p.HitRadius * s
	local hitAnchor = ctx.Anchor(CFrame.lookAt(target, start))
	local hitAtt = Layers.Attachment(hitAnchor)
	local ringAtt = Layers.Attachment(hitAnchor, CFrame.Angles(math.rad(90), 0, 0))
	local flash = Layers.Emitter(hitAtt, {
		Texture = ASSETS.Flash,
		Lifetime = 0.07,
		Rotation = { 0, 360 },
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.5 * R }, { 0.3, 1.8 * R }, { 1, 2 * R } },
		Transparency = { { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } },
	})
	local stars = Layers.Emitter(hitAtt, {
		Texture = ASSETS.ImpactStar,
		Lifetime = { 0.1, 0.14 },
		Rotation = { 0, 360 },
		LightEmission = -1,
		Brightness = 5,
		ZOffset = 1,
		Color = { { 0, p.Color }, { 1, p.DeepColor } },
		Size = { { 0, 1.2 * R }, { 0.25, 2.1 * R, 0.4 * R }, { 1, 2.3 * R } },
	})
	local blackStars = Layers.Black(stars)
	local whiteStar = Layers.White(stars, { Lifetime = 0.08, Brightness = 3, Size = { { 0, 0.5 * R }, { 1, 0.9 * R } } })
	local streaks = Layers.Emitter(hitAtt, {
		Texture = ASSETS.SoftGlow,
		Orientation = "VelocityParallel",
		Lifetime = { 0.2, 0.3 },
		Speed = { 15 * R, 35 * R },
		SpreadAngle = 180,
		Drag = 10,
		LightEmission = 0,
		Brightness = 8,
		ZOffset = 2,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.3 * R, 0.1 * R }, { 1, 0 } },
		Squash = { { 0, 3 }, { 1, 1 } },
	})
	local blackStreaks = Layers.Black(streaks, 0.1, { Speed = { 10 * R, 22 * R } })
	local ring = Layers.Emitter(ringAtt, {
		Flat = true,
		Texture = ASSETS.ShockRing,
		Lifetime = 0.28,
		Rotation = { 0, 360 },
		LightEmission = 0.3,
		Brightness = 3,
		Color = p.HotColor,
		Size = { { 0, 0.3 * R }, { 0.4, 2 * R }, { 1, 2.4 * R } },
		Transparency = { { 0, 0 }, { 1, 1.3 } },
	})
	local light = Layers.Light(hitAtt, { Color = p.Color })

	local function place(t)
		local point, tangent = bezier(start, control, target, t)
		if tangent.Magnitude < 1e-3 then
			tangent = span
		end
		headPart.CFrame = CFrame.lookAt(point, point + tangent)
	end

	ctx.Emit(smear, 1)
	ctx.Emit(muzzleRing, 1)
	place(0)
	ctx.Emit(glow, 1)
	ctx.Emit(core, 1)
	specks.TimeScale = timeScale
	specks.Enabled = true

	-- fly one step per rendered frame; add what ctx.Wait returns, never a fixed 1/60.
	-- (Not inside a Timeline event: a Timeline's clock only advances between events.)
	local age = 0
	while age < flightTime do
		age += ctx.Wait(1 / 60)
		if not ctx.Folder.Parent then
			return
		end
		place(math.min(age / flightTime, 1))
	end

	-- the hit, timed from the moment the bolt arrives
	Layers.Timeline(ctx, {
		{ 0, function()
			-- the head vanishes in the hit frame; the ribbons stop growing and fade out
			glow:Clear()
			core:Clear()
			specks.Enabled = false
			sharp.Enabled = false
			soft.Enabled = false
			ctx.Emit(flash, 1)
			Layers.Pop(ctx, light, p.LightBrightness, 4 * s, p.LightRange * s, 0.4)
		end },
		{ 0.03, function()
			ctx.Emit(stars, 3)
			ctx.Emit(blackStars, 3)
			ctx.Emit(whiteStar, 1)
		end },
		{ 0.05, function()
			ctx.Emit(streaks, p.StreakCount)
			ctx.Emit(blackStreaks, math.ceil(p.StreakCount / 3))
			ctx.Emit(ring, 1)
		end },
	})
end

return Effect
