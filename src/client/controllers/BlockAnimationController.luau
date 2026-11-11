-- BlockAnimationController: the placed machines' own moving parts, animated on this client while
-- they work (Status == "Working", which FactoryService replicates; a Sprinkler, which has no
-- status, always runs). Nothing moves a whole block: the drill bit spins, the Fruit Press's juice
-- fills and drains under a pumping, slowly turning handle, the Grain Mill's sails and millstone turn, the
-- Harvester's reel and the Seed Planter's wheels roll, the Crate Packer's press stamps, the
-- Assembler's gear turns, the Sprinkler's head sweeps, and the Smelter's and Oven's fires flicker
-- with smoke from their stacks.
--
-- A moving part is found by its art key, the suffix of Mesh_<Asset>_<Key> (garden_machines.py
-- builds each as a part of its own, centred on its axle), so a Mk II machine that borrows its tier
-- 1 art animates the same. ANIMATIONS is the whole list; a key the art lacks just stays still.
--
-- Only local copies move: the real part is hidden with LocalTransparencyModifier and keeps its
-- CFrame, size and collision, and the copy has no collision or queries. Stopping, culling or a
-- block leaving restores the part and drops the copy. One RenderStepped loop drives every block,
-- skipping those beyond the quality preset's distance (docs/animations.md).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Lighting = require(Players.LocalPlayer.PlayerScripts.Libraries.Lighting)

-- How far away blocks still animate, how often the copies move, and whether stacks smoke.
local QUALITY = {
	Low = { distance = 60, interval = 1 / 30, smoke = false },
	Medium = { distance = 90, interval = 1 / 45, smoke = true },
	High = { distance = 120, interval = 0, smoke = true },
}
-- Seconds a machine takes to spin up to full speed or wind down to rest.
local EASE = 0.35
local SMOKE_RATE = 2.5

type Motion = "Spin" | "Slide" | "Fill" | "Flicker" | "Smoke"
type Animation = {
	motion: Motion,
	-- Spin: the axle in the part's own frame and radians a second. Slide: the direction moved
	-- and how far. Fill: the share of its height the level drops to.
	axis: Vector3?,
	speed: number?,
	distance: number?,
	low: number?,
	-- Seconds per stroke, for the cyclic motions.
	period: number?,
	-- Slide only: also turns about the part's Y axle at `pivot` (part frame) by `turn` radians a
	-- second, for a part whose axle is off its bounding-box centre.
	turn: number?,
	pivot: Vector3?,
	-- Runs whether or not the machine is working.
	always: boolean?,
}

-- By art key. Axes are in the part's frame, which is the block's authored frame: +Y up, +Z the
-- way items travel, +X across.
local ANIMATIONS: { [string]: Animation } = {
	Bit = { motion = "Spin", axis = Vector3.yAxis, speed = 9 },
	Sails = { motion = "Spin", axis = Vector3.xAxis, speed = 1.4 },
	Millstone = { motion = "Spin", axis = Vector3.yAxis, speed = 1.8 },
	Reel = { motion = "Spin", axis = Vector3.xAxis, speed = -4 },
	Wheels = { motion = "Spin", axis = Vector3.xAxis, speed = 1.2 },
	Gear = { motion = "Spin", axis = Vector3.zAxis, speed = 2.5 },
	-- The Roaster's barrel rolls on its rollers; the Preserving Kettle's paddle stirs; the
	-- Chiller's condenser fan runs (garden_kitchen.py).
	Drum = { motion = "Spin", axis = Vector3.zAxis, speed = 1.5 },
	Stirrer = { motion = "Spin", axis = Vector3.yAxis, speed = 1.8 },
	Fan = { motion = "Spin", axis = Vector3.yAxis, speed = 8 },
	Head = { motion = "Spin", axis = Vector3.yAxis, speed = 2.6, always = true },
	Press = { motion = "Slide", axis = -Vector3.yAxis, distance = 0.32, period = 1.3 },
	-- The Fruit Press's handle: its stem sits 0.665 studs behind the part's centre (the yellow knob
	-- reaches further out, garden_machines.py `juicer`), so it only turns slowly round the stem: no
	-- vertical stroke (distance 0), the handle never bobs.
	Piston = {
		motion = "Slide",
		axis = -Vector3.yAxis,
		distance = 0,
		period = 0.7,
		turn = 1.1,
		pivot = Vector3.new(0, 0, -0.665),
	},
	Juice = { motion = "Fill", low = 0.35, period = 5 },
	Glow = { motion = "Flicker" },
	Stack = { motion = "Smoke" },
}

type Moving = {
	part: BasePart,
	animation: Animation,
	copy: BasePart?,
	transparency: number,
	emitter: ParticleEmitter?,
}
type Block = {
	model: Model,
	trove: typeof(Trove.new()),
	moving: { Moving },
	-- 0 at rest, 1 at full speed, eased between.
	strength: number,
	-- Seconds of animation run so far, scaled by strength, so a wind-down slows rather than stops.
	clock: number,
	phase: number,
}

local BlockAnimationController = {}
local blocks: { [Model]: Block } = {}
local container = Instance.new("Folder")
container.Name = "BlockAnimationVisuals"

local function keyOf(name: string): string?
	return string.match(name, "^Mesh_[^_]+_(.+)$")
end

local function hide(moving: Moving)
	if moving.copy then
		moving.copy:Destroy()
		moving.copy = nil
		moving.part.LocalTransparencyModifier = moving.transparency
	end
	if moving.emitter then
		moving.emitter.Enabled = false
	end
end

local function copyOf(moving: Moving): BasePart
	if moving.copy then
		return moving.copy
	end
	local copy = moving.part:Clone()
	for _, child in copy:GetChildren() do
		if not (child:IsA("SurfaceAppearance") or child:IsA("DataModelMesh") or child:IsA("Decal")) then
			child:Destroy()
		end
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanTouch = false
	copy.CanQuery = false
	copy.Parent = container
	moving.transparency = moving.part.LocalTransparencyModifier
	moving.part.LocalTransparencyModifier = 1
	moving.copy = copy
	return copy
end

-- Soft grey puffs from the top of a stack, made once and switched on while working.
local function smokeOf(moving: Moving): ParticleEmitter
	if moving.emitter then
		return moving.emitter
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "StackSmoke"
	attachment.Position = Vector3.new(0, moving.part.Size.Y / 2, 0)
	attachment.Parent = moving.part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(236, 232, 226))
	emitter.LightEmission = 0
	emitter.Rate = SMOKE_RATE
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Speed = NumberRange.new(1, 1.6)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Acceleration = Vector3.new(0.4, 0.5, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1.4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
	emitter.Parent = attachment
	moving.emitter = emitter
	return emitter
end

local function rest(block: Block)
	for _, moving in block.moving do
		hide(moving)
	end
end

local function unbind(model: Instance)
	local block = if model:IsA("Model") then blocks[model] else nil
	if block then
		blocks[model] = nil
		block.trove:Destroy()
	end
end

local function bind(model: Instance)
	if not model:IsA("Model") or blocks[model] then
		return
	end
	local position = model:GetPivot().Position
	local block: Block = {
		model = model,
		trove = Trove.new(),
		moving = {},
		strength = 0,
		clock = 0,
		-- Neighbouring machines don't move in step.
		phase = (position.X * 0.73 + position.Z * 0.37) % 7,
	}
	local function track(part: Instance)
		local key = if part:IsA("BasePart") then keyOf(part.Name) else nil
		local animation = if key then ANIMATIONS[key] else nil
		if animation then
			table.insert(block.moving, { part = part :: BasePart, animation = animation, transparency = 0 })
		end
	end
	for _, part in model:GetDescendants() do
		track(part)
	end
	blocks[model] = block
	-- Parts that stream in after their model still animate.
	block.trove:Connect(model.DescendantAdded, track)
	block.trove:Connect(model.DescendantRemoving, function(part: Instance)
		for index, moving in block.moving do
			if moving.part == part then
				hide(moving)
				if moving.emitter then
					moving.emitter.Parent:Destroy()
				end
				table.remove(block.moving, index)
				return
			end
		end
	end)
	block.trove:Add(function()
		for _, moving in block.moving do
			hide(moving)
			if moving.emitter and moving.emitter.Parent then
				moving.emitter.Parent:Destroy()
			end
		end
	end)
end

-- 0 to 1 and back once a period: a quick stroke down and an eased lift.
local function stroke(t: number): number
	local alpha = t % 1
	return if alpha < 0.3
		then math.sin(alpha / 0.3 * math.pi / 2)
		else (1 + math.cos((alpha - 0.3) / 0.7 * math.pi)) / 2
end

local function pose(moving: Moving, block: Block, parts: { BasePart }, frames: { CFrame }, smoke: boolean)
	local animation = moving.animation
	local part = moving.part
	local strength = if animation.always then 1 else block.strength
	-- An always-running part keeps the real clock, since its block may never work.
	local t = (if animation.always then os.clock() else block.clock) + block.phase
	if animation.motion == "Smoke" then
		local emitter = smokeOf(moving)
		emitter.Enabled = smoke and strength > 0.5
		return
	end
	local copy = copyOf(moving)
	local at = part.CFrame
	if animation.motion == "Spin" then
		at *= CFrame.fromAxisAngle(animation.axis :: Vector3, (t * (animation.speed :: number)) % (math.pi * 2))
	elseif animation.motion == "Slide" then
		local offset = stroke(t / (animation.period :: number)) * (animation.distance :: number) * strength
		at *= CFrame.new((animation.axis :: Vector3) * offset)
		if animation.turn and animation.pivot then
			local pivot = animation.pivot
			at *= CFrame.new(pivot) * CFrame.Angles(0, (t * animation.turn) % (math.pi * 2), 0) * CFrame.new(-pivot)
		end
	elseif animation.motion == "Fill" then
		-- Fills over most of the period, then drains quickly as the batch is bottled.
		local alpha = (t / (animation.period :: number)) % 1
		local fill = if alpha < 0.8 then alpha / 0.8 else 1 - (alpha - 0.8) / 0.2
		local low = animation.low :: number
		local level = 1 - (1 - low) * (1 - fill) * strength
		copy.Size = Vector3.new(part.Size.X, part.Size.Y * level, part.Size.Z)
		-- Keep the juice's bottom where it is, turning slowly as it churns.
		at *= CFrame.new(0, -part.Size.Y * (1 - level) / 2, 0) * CFrame.Angles(0, t * 0.6, 0)
	elseif animation.motion == "Flicker" then
		local flicker = (math.sin(t * 7.3) + math.sin(t * 3.1 + 1)) / 2
		copy.Transparency = part.Transparency + (0.12 + flicker * 0.12) * strength
	end
	table.insert(parts, copy)
	table.insert(frames, at)
end

local function step(dt: number, draw: boolean, quality: typeof(QUALITY.High))
	local camera = workspace.CurrentCamera
	local parts, frames = {}, {}
	for _, block in blocks do
		if #block.moving == 0 then
			continue
		end
		local near = camera ~= nil
			and (block.model:GetPivot().Position - camera.CFrame.Position).Magnitude <= quality.distance
		if not near or GuiService.ReducedMotionEnabled then
			rest(block)
			continue
		end
		local working = block.model:GetAttribute("Status") == "Working"
		block.strength = math.clamp(block.strength + (if working then dt else -dt) / EASE, 0, 1)
		block.clock += dt * block.strength
		if not draw then
			continue
		end
		for _, moving in block.moving do
			if moving.animation.always or block.strength > 0 then
				pose(moving, block, parts, frames, quality.smoke)
			else
				hide(moving)
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function BlockAnimationController.init()
	local placed = workspace:WaitForChild("Placed")
	local trove = Trove.new()
	container.Parent = workspace
	trove:Add(container)
	trove:Connect(placed.ChildAdded, bind)
	trove:Connect(placed.ChildRemoved, unbind)
	for _, model in placed:GetChildren() do
		bind(model)
	end
	local elapsed = 0
	trove:Connect(RunService.RenderStepped, function(dt: number)
		local quality = QUALITY[Lighting.quality()] or QUALITY.High
		elapsed += dt
		local draw = elapsed >= quality.interval
		if draw then
			elapsed = 0
		end
		step(dt, draw, quality)
	end)
	trove:Connect(script.Destroying, function()
		for model in blocks do
			unbind(model)
		end
		trove:Destroy()
	end)
end

return BlockAnimationController
