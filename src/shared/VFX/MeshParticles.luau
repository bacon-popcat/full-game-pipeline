-- ModuleScript: ReplicatedStorage/Shared/VFX/MeshParticles
-- Roblox ParticleEmitters only draw flat textures, so mesh "particles"
-- are real MeshParts simulated here on the client.
--
-- MeshParticles.Burst(ctx, template, count, config)
--   template: a MeshPart/Part to clone (store templates in ReplicatedStorage/Assets/Meshes)
--   config fields (all optional):
--     Origin        Vector3          default ctx.CFrame.Position
--     Direction     Vector3          center of the emission cone, default up
--     Spread        number (deg)     cone half-angle, 0-180, default 45
--     Speed         NumberRange|num  studs/sec, default 20
--     Lifetime      NumberRange|num  seconds, default 1
--     Drag          number           exponential slowdown per second, default 0
--     Acceleration  Vector3          e.g. gravity, default (0,-60,0)
--     SpinSpeed     NumberRange|num  degrees/sec, default 360
--     Scale         number           multiplies the template's size, default 1
--     Size          NumberSequence|num  size multiplier over lifetime, default 1
--     Transparency  NumberSequence|num  over lifetime, default 0
--     SpawnRadius   number           random offset from Origin, default 0
-- Non-blocking. Make sure the effect's Linger covers the longest Lifetime.

local RunService = game:GetService("RunService")

local MeshParticles = {}
local rng = Random.new()

local function sample(value)
	if typeof(value) == "NumberRange" then
		return rng:NextNumber(value.Min, value.Max)
	end
	return value
end

local function evaluate(seq, t)
	if typeof(seq) ~= "NumberSequence" then
		return seq
	end
	local keypoints = seq.Keypoints
	for i = 1, #keypoints - 1 do
		local a, b = keypoints[i], keypoints[i + 1]
		if t <= b.Time then
			local alpha = (t - a.Time) / math.max(b.Time - a.Time, 1e-6)
			return a.Value + (b.Value - a.Value) * alpha
		end
	end
	return keypoints[#keypoints].Value
end

local function coneDirection(direction, spreadDegrees)
	local base = CFrame.lookAt(Vector3.zero, direction.Unit)
	local tilted = base
		* CFrame.Angles(0, 0, rng:NextNumber(0, 2 * math.pi))
		* CFrame.Angles(rng:NextNumber(0, math.rad(spreadDegrees)), 0, 0)
	return tilted.LookVector
end

function MeshParticles.Burst(ctx, template, count, config)
	config = config or {}
	local origin = config.Origin or ctx.CFrame.Position
	local direction = config.Direction or Vector3.yAxis
	local spread = config.Spread or 45
	local drag = config.Drag or 0
	local acceleration = config.Acceleration or Vector3.new(0, -60, 0)
	local sizeSeq = config.Size or 1
	local transparencySeq = config.Transparency or 0
	local baseSize = template.Size * (config.Scale or 1)

	local particles = {}
	for _ = 1, count do
		local part = template:Clone()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local dir = coneDirection(direction, spread)
		local p = {
			Part = part,
			Position = origin + dir * rng:NextNumber(0, config.SpawnRadius or 0),
			Velocity = dir * sample(config.Speed or 20),
			Rotation = CFrame.fromOrientation(
				rng:NextNumber(0, 2 * math.pi),
				rng:NextNumber(0, 2 * math.pi),
				rng:NextNumber(0, 2 * math.pi)
			),
			SpinAxis = rng:NextUnitVector(),
			Spin = math.rad(sample(config.SpinSpeed or 360)),
			Life = sample(config.Lifetime or 1),
			Age = 0,
		}
		part.Size = baseSize * evaluate(sizeSeq, 0)
		part.Transparency = evaluate(transparencySeq, 0)
		part.CFrame = CFrame.new(p.Position) * p.Rotation
		part.Parent = ctx.Folder
		table.insert(particles, p)
	end

	local connection
	connection = RunService.RenderStepped:Connect(function(rawDt)
		-- The effect was cleaned up early: stop simulating
		if not ctx.Folder.Parent then
			connection:Disconnect()
			return
		end

		local dt = rawDt * ctx.TimeScale
		local parts, cframes = {}, {}
		local alive = 0

		for _, p in particles do
			if p.Part.Parent then
				p.Age += dt
				local t = p.Age / p.Life
				if t >= 1 then
					p.Part:Destroy()
				else
					alive += 1
					p.Velocity = (p.Velocity + acceleration * dt) * math.exp(-drag * dt)
					p.Position += p.Velocity * dt
					p.Rotation = CFrame.fromAxisAngle(p.SpinAxis, p.Spin * dt) * p.Rotation

					p.Part.Size = baseSize * evaluate(sizeSeq, t)
					p.Part.Transparency = evaluate(transparencySeq, t)
					table.insert(parts, p.Part)
					table.insert(cframes, CFrame.new(p.Position) * p.Rotation)
				end
			end
		end

		if #parts > 0 then
			-- One call to move every particle; much cheaper than setting CFrame per part
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if alive == 0 then
			connection:Disconnect()
		end
	end)
end

return MeshParticles
