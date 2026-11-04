-- ModuleScript: ReplicatedStorage/Shared/VFX/Effects/CrescentSlash
-- A sword swing drawn without a mesh: a pivot part swept through Arc degrees (Quart Out)
-- carrying two ribbons between attachments at the blade's inner and outer radius (a thin
-- hot core and a wide dark-edged wisp), sparks shed from the blade tip one burst per frame
-- so the eye follows the swing, and black ink flecks. Roll tilts the whole swing for a
-- diagonal cut. The ribbons draw the crescent themselves: a flat crescent flipbook laid
-- over them read as stepped panels in Studio, so there is none.
-- Layers: core ribbon, wisp ribbon, ink ribbon, tip sparks + black twins, ink flecks.
--
-- ctx.CFrame = the swing's centre (the caster's chest), LookVector = forward. With Roll the
-- low end of the swing dips OuterRadius * sin(Roll) studs: keep that above the floor.

local VFX = script.Parent.Parent
local Layers = require(VFX:WaitForChild("Layers"))

-- Library ids from ReplicatedStorage.Assets.VFX. Comment = <Folder>/<CardName>.
local ASSETS = {
	CoreTrail = "rbxassetid://10614304526", -- StaticVFXTextures/Sideways Spec 41 (thin needle)
	WispTrail = "rbxassetid://13280046773", -- MigratedBeams/BeamSoftBlurredStreaks
	Speck = "rbxassetid://16879822194", -- StaticVFXTextures/Spec31
	Flecks = "rbxassetid://6893847210", -- StaticVFXTextures/Sideways Spec 50 (tapered spike)
}

local Effect = {}

Effect.Defaults = {
	Color = Color3.fromRGB(120, 180, 255), -- the hue
	HotColor = Color3.fromRGB(235, 245, 255), -- white-hot core
	DeepColor = Color3.fromRGB(35, 60, 160), -- deep end of the wisp
	InkColor = Color3.fromRGB(10, 12, 25), -- near-black ink
	Scale = 1,
	InnerRadius = 2.5, -- studs from the centre to the blade's base
	OuterRadius = 7, -- studs to the tip
	Arc = 160, -- degrees swept
	SwingTime = 0.14, -- seconds for the sweep
	Roll = -15, -- degrees: tilts the swing plane (0 = flat, 90 = vertical)
	SparkCount = 3, -- per frame from the tip
	Ink = true, -- black ribbon and flecks
}

Effect.Linger = 0.45 -- wisp ribbon (0.3 s) and sparks (up to 0.4 s) after the sweep

function Effect.Play(ctx)
	local p = ctx.Params
	local s = p.Scale
	local timeScale = ctx.TimeScale
	local inner, outer = p.InnerRadius * s, p.OuterRadius * s
	local arc = math.rad(p.Arc)

	-- swing plane: the centre's XZ plane rolled about the forward axis; the sweep starts on
	-- the right and ends on the left, centred on forward
	local plane = ctx.CFrame * CFrame.Angles(0, 0, math.rad(p.Roll))
	local function bladeAt(t)
		return plane * CFrame.Angles(0, arc * (0.5 - t), 0)
	end

	local pivot = ctx.Anchor(bladeAt(0))
	-- the blade lies along the pivot's -Z (forward); attachments at base, mid and tip
	local function at(radius, lift)
		return Layers.Attachment(pivot, CFrame.new(0, lift or 0, -radius))
	end
	local coreA, coreB = at(outer - 0.6 * s), at(outer)
	local wispA, wispB = at(inner), at(outer + 0.4 * s)
	local inkA, inkB = at(outer + 0.15 * s), at(outer + 0.55 * s)
	local tip = at(outer)

	local function ribbon(a0, a1, spec)
		local trail = Instance.new("Trail")
		spec.Attachment0 = a0
		spec.Attachment1 = a1
		spec.MinLength = 0.05
		spec.FaceCamera = false -- lies in the swing plane, so it reads as a crescent
		Layers.Apply(trail, spec)
		trail.Parent = pivot
		return trail
	end
	local trails = {
		ribbon(coreA, coreB, {
			Texture = ASSETS.CoreTrail,
			Lifetime = 0.1 / timeScale,
			LightEmission = 0.5,
			Brightness = 15,
			Color = p.HotColor,
			WidthScale = { { 0, 1 }, { 1, 0 } },
		}),
		ribbon(wispA, wispB, {
			Texture = ASSETS.WispTrail,
			Lifetime = 0.3 / timeScale,
			LightEmission = 0.6,
			Brightness = 2,
			Color = { { 0, p.Color }, { 1, p.DeepColor } },
			Transparency = { { 0, 0.2 }, { 1, 1 } },
			WidthScale = { { 0, 1 }, { 1, 0.2 } },
		}),
	}
	if p.Ink then
		table.insert(trails, ribbon(inkA, inkB, {
			Texture = ASSETS.CoreTrail,
			Lifetime = 0.16 / timeScale,
			LightEmission = 0,
			Brightness = 1,
			Color = p.InkColor,
			Transparency = { { 0, 0.1 }, { 1, 1 } },
			WidthScale = { { 0, 1 }, { 1, 0 } },
		}))
	end

	local sparks = Layers.Emitter(tip, {
		Texture = ASSETS.Speck,
		Orientation = "VelocityParallel",
		Speed = { 15 * s, 35 * s },
		SpreadAngle = 50,
		EmissionDirection = "Front", -- out past the tip
		Drag = 8,
		Lifetime = { 0.2, 0.4 },
		LightEmission = 1,
		Brightness = 3,
		Color = { { 0, p.HotColor }, { 1, p.Color } },
		Size = { { 0, 0.3 * s }, { 1, 0 } },
		Squash = { { 0, 2.5 }, { 1, 1 } },
	})
	local blackSparks = Layers.Black(sparks, 0.1)

	local flecks = Layers.Emitter(tip, {
		Texture = ASSETS.Flecks,
		Orientation = "VelocityParallel",
		Speed = { 8 * s, 18 * s },
		SpreadAngle = 70,
		EmissionDirection = "Front",
		Drag = 6,
		Lifetime = { 0.2, 0.35 },
		LightEmission = 0,
		Brightness = 1,
		Color = p.InkColor,
		Size = { { 0, 0.5 * s }, { 1, 0 } },
	})

	-- sweep one step per rendered frame (Quart Out), shedding from the tip as it goes.
	-- Moving the pivot twice in one frame wouldn't move the spawn point, so emit once per Wait.
	local age = 0
	while age < p.SwingTime do
		age += ctx.Wait(1 / 60)
		if not ctx.Folder.Parent then
			return
		end
		local t = math.min(age / p.SwingTime, 1)
		pivot.CFrame = bladeAt(1 - (1 - t) ^ 4)
		ctx.Emit(sparks, p.SparkCount)
		if p.Ink then
			ctx.Emit(blackSparks, 1)
			if math.random() < 0.5 then
				ctx.Emit(flecks, 1)
			end
		end
	end

	for _, trail in trails do
		trail.Enabled = false
	end
end

return Effect
