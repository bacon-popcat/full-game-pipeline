-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/DashBurst
-- A dash: a dust kick and flat wind ring shed backwards at the start, a one-frame smear,
-- a body that streaks Distance studs along LookVector in DashTime carrying a hot core
-- trail and a wide soft wisp trail, speed lines shed behind it, and a skid puff where it
-- stops. Shows "anything that moves carries its speed" and a moved part with trail pairs.
-- Layers: start dust + skid dust (warm/cool pair), wind ring, smear, core trail, wisp
-- trail, speed lines + black twins, end flare.
--
-- ctx.CFrame = where the dash starts, LookVector = dash direction. The effect only draws
-- the dash; move the character yourself over the same DashTime.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))
local Textures = require(VFX:WaitForChild("Textures"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	Needle = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle)
	WispTrail = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks
	WindRing = "rbxassetid://12318427672", -- StaticVFXTextures/Smokey Shockwave (grey wind ring)
	Dust = Textures.DustPuff, -- drawn: assets/textures/fire.py (Grid4x4)
	Glint = Textures.Glint, -- drawn: assets/textures/impact.py
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(255, 230, 120), -- the hue of the energy layers
	HotColor = Color3.fromRGB(255, 252, 235),
	DeepColor = Color3.fromRGB(230, 120, 30),
	DustColor = Color3.fromRGB(165, 150, 130), -- warm grey dust
	CoolDustColor = Color3.fromRGB(130, 132, 140), -- its cool grey pair
	Scale = 1,
	Distance = 18, -- studs
	DashTime = 0.12, -- seconds; keep in step with the character's real move
	BodyHeight = 2.5, -- studs above the ground the trails run at
	DustCount = 4, -- per dust layer, at each end
	LineCount = 10,
}

Effect.Linger = 1.05 -- skid dust (0.8 s slowed to 0.8x = 1 s) after the stop

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local timeScale = ctx.TimeScale

	local look = ctx.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local startGround = Layers.Ground(ctx)
	local endGround = Layers.Ground(ctx, ctx.CFrame.Position + look * p.Distance * s)
	-- frames face along the dash, so Back = behind the runner
	local startFrame = CFrame.lookAt(startGround, startGround + look)
	local endFrame = CFrame.lookAt(endGround, endGround + look)

	-- dust starts a little above the floor, or half of every puff is hidden under it
	local startAtt = Layers.Attachment(ctx.Anchor(startFrame + Vector3.new(0, 0.8 * s, 0)))
	local endAtt = Layers.Attachment(ctx.Anchor(endFrame + Vector3.new(0, 0.8 * s, 0)))
	-- the ring lies upright across the dash and is shed backwards
	local ringAtt = Layers.Attachment(startAtt.Parent, CFrame.new(0, (p.BodyHeight - 0.8) * s, 0))

	local function dust(att, color, direction)
		return Layers.Emitter(att, {
			Texture = ASSETS.Dust,
			EmissionDirection = direction,
			SpreadAngle = { 40, 15 },
			Speed = { 8 * s, 16 * s },
			Drag = 6,
			Lifetime = { 0.5, 0.8 },
			Rotation = { 0, 360 },
			RotSpeed = { -60, 60 },
			LightEmission = 0,
			Brightness = 1.5,
			Color = color,
			Size = { { 0, 2.5 * s }, { 1, 5 * s } },
			Transparency = { { 0, 0.5 }, { 0.2, 0.3 }, { 1, 1 } },
		})
	end
	local startDust = dust(startAtt, p.DustColor, "Back")
	local startDustCool = dust(startAtt, p.CoolDustColor, "Back")
	local skidDust = dust(endAtt, p.DustColor, "Front")
	local skidDustCool = dust(endAtt, p.CoolDustColor, "Front")

	local windRing = Layers.Emitter(ringAtt, {
		Flat = true,
		Texture = ASSETS.WindRing,
		EmissionDirection = "Back", -- the ring faces along the dash and flies backwards
		Speed = 10 * s,
		Lifetime = 0.45,
		Rotation = { 0, 360 },
		RotSpeed = 20,
		LightEmission = 1,
		Brightness = 1,
		Color = p.HotColor,
		Size = { { 0, 2 * s }, { 0.6, 9 * s }, { 1, 10 * s } },
		Transparency = { { 0, 0.5 }, { 1, 1.1 } },
	})
	local smear = Layers.Emitter(ringAtt, {
		Texture = ASSETS.Needle,
		Orientation = "VelocityParallel",
		EmissionDirection = "Front",
		SpreadAngle = 0,
		Speed = p.Distance * s / p.DashTime,
		Lifetime = 0.04,
		LightEmission = 1,
		Brightness = 6,
		Color = p.HotColor,
		Size = 4 * s,
		Squash = -0.5,
	})

	-- the moving body: a part with trail pairs and a speed-line emitter
	local body = ctx.Anchor(startFrame + Vector3.new(0, p.BodyHeight * s, 0))
	local coreA = Layers.Attachment(body, CFrame.new(0, 0.3 * s, 0))
	local coreB = Layers.Attachment(body, CFrame.new(0, -0.3 * s, 0))
	local wispA = Layers.Attachment(body, CFrame.new(0, 1 * s, 0))
	local wispB = Layers.Attachment(body, CFrame.new(0, -1 * s, 0))
	local core = Instance.new("Trail")
	Layers.Apply(core, {
		Attachment0 = coreA,
		Attachment1 = coreB,
		Texture = ASSETS.Needle,
		Lifetime = 0.1 / timeScale, -- thin hot core, short
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = 0.5,
		Brightness = 12,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		WidthScale = { { 0, 1 }, { 1, 0 } },
	})
	core.Parent = body
	local wisp = Instance.new("Trail")
	Layers.Apply(wisp, {
		Attachment0 = wispA,
		Attachment1 = wispB,
		Texture = ASSETS.WispTrail,
		Lifetime = 0.18 / timeScale, -- wide soft wisp; shorter than the dash, so it visibly thins out behind
		MinLength = 0.05,
		FaceCamera = true,
		LightEmission = 1, -- a dim, opaque wisp read as a solid tan plank in Studio
		Brightness = 3,
		Color = { { 0, p.HotColor }, { 0.3, p.Color }, { 1, p.DeepColor } },
		Transparency = { { 0, 0.4 }, { 0.5, 0.75 }, { 1, 1 } },
		WidthScale = { { 0, 1 }, { 0.5, 0.45 }, { 1, 0 } },
	})
	wisp.Parent = body
	local bodyAtt = Layers.Attachment(body)
	local lines = Layers.Emitter(bodyAtt, {
		Texture = ASSETS.Needle,
		Orientation = "VelocityParallel",
		EmissionDirection = "Back",
		SpreadAngle = 8,
		Speed = { 20 * s, 40 * s },
		Drag = 8,
		Lifetime = { 0.15, 0.3 },
		LightEmission = 1,
		Brightness = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 1.2 * s, 0.4 * s }, { 1, 0 } },
		Squash = { { 0, 2 }, { 1, 0.5 } },
	})
	local blackLines = Layers.Black(lines, 0.1)
	local endFlare = Layers.Emitter(bodyAtt, {
		Texture = ASSETS.Glint,
		Lifetime = 0.1,
		Rotation = { -15, 15 },
		LightEmission = 1,
		Brightness = 5,
		ZOffset = 1,
		Color = p.HotColor,
		Size = { { 0, 3 * s }, { 1, 5 * s } },
		Squash = -2,
		Transparency = { { 0, 0 }, { 1, 1 } },
	})

	Layers.Emit(ctx, startDust, p.DustCount, 0.8)
	Layers.Emit(ctx, startDustCool, p.DustCount, 0.8)
	ctx.Emit(windRing, 1)
	ctx.Emit(smear, 1)

	-- move the body (Quart Out: most of the distance early, a short glide into the stop),
	-- shedding lines spread across the frames
	local target = endFrame + Vector3.new(0, p.BodyHeight * s, 0)
	ctx.Tween(body, p.DashTime, { CFrame = target }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local age, shed = 0, 0
	while age < p.DashTime do
		age += ctx.Wait(1 / 60)
		if not ctx.Folder.Parent then
			return
		end
		local due = math.floor(p.LineCount * math.min(age / p.DashTime, 1))
		if due > shed then
			ctx.Emit(lines, due - shed)
			ctx.Emit(blackLines, math.ceil((due - shed) / 3))
			shed = due
		end
	end

	core.Enabled = false
	wisp.Enabled = false
	ctx.Emit(endFlare, 1)
	Layers.Emit(ctx, skidDust, p.DustCount, 0.8)
	Layers.Emit(ctx, skidDustCool, p.DustCount, 0.8)
end

return Effect
