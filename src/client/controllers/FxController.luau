-- FxController: shows and sounds the moments FxService sends (Remotes.Fx). Each is short and soft:
-- a puff of soil when planting; a harvest that pops (a ring across the soil, a few leaves and
-- twinkles springing out, and the produce bouncing up and floating into whoever picked it, a
-- mutated one shimmering in its colours); coins sparkling round you when you sell (a Shipping
-- Bin's sales only sparkle, with no sound, so a busy factory stays quiet); a chopped tree tipping
-- over and settling away; wood shavings when you craft; a warm ring when you level up; and when
-- you complete research, the ResearchComplete effect (Shared/VFX) round you: a gold ring, motes
-- spiralling up and a column of light. Reduced motion keeps the sounds and colours but drops the
-- movement. Nothing here changes the game.
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Build = require(ReplicatedStorage.Shared.Build)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VFXPlayer = require(ReplicatedStorage.Shared.VFX.VFXPlayer)
local World = require(ReplicatedStorage.Shared.World)
local Sound = require(Players.LocalPlayer.PlayerScripts.Libraries.Sound)

local FxController = {}

local SOIL = Color3.fromRGB(176, 128, 82)
local COIN = Color3.fromRGB(246, 214, 120)
local GLOW = Color3.fromRGB(255, 236, 190)
local LEAF = Color3.fromRGB(132, 190, 104)
local WOOD = Color3.fromRGB(196, 150, 104)
local TWINKLE = "rbxasset://textures/particles/sparkles_main.dds"
-- Studs past which nobody needs to see someone else's farm moment.
local SHOW_WITHIN = 140
-- Seconds the produce takes to bounce up, hang, and float into the picker.
local POP, HANG, FLY = 0.32, 0.12, 0.38
-- How far a harvest's produce may fly to reach its picker; further, it just fades where it is.
local FLY_WITHIN = Build.REACH + 4
-- Seconds a chopped tree takes to tip over, and to settle away once down.
local FALL, SETTLE = 1.1, 0.7

local function near(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= SHOW_WITHIN
end

-- Runs `step(alpha)` every frame for `seconds` (alpha 0 to 1), then `done`.
local function animate(seconds: number, step: (number) -> (), done: (() -> ())?)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / seconds)
		step(alpha)
		if alpha >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
end

-- A one-off burst of `count` soft particles at `position`.
local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number, texture: string?)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new(size, size * 0.3)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.45, 0.8)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -speed * 1.6, 0)
	emitter.LightInfluence = 0.5
	if texture then
		emitter.Texture = texture
		emitter.LightEmission = 0.8
		emitter.Rotation = NumberRange.new(0, 360)
	end
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(if GuiService.ReducedMotionEnabled then math.ceil(count / 2) else count)
	Debris:AddItem(holder, 1.5)
end

local function scenery(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- A soft flat ring spreading out across the ground from `at`.
local function groundRing(at: Vector3, color: Color3, reach: number, seconds: number)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.06, 1, 1)
	part.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.45
	part.CastShadow = false
	scenery(part)
	part.Parent = workspace.Terrain
	if GuiService.ReducedMotionEnabled then
		TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	else
		TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.06, reach, reach),
			Transparency = 1,
		}):Play()
	end
	Debris:AddItem(part, seconds + 0.1)
end

-- A few small leaves springing out of a picked plant and fluttering down.
local function leaves(at: Vector3, count: number)
	if GuiService.ReducedMotionEnabled then
		return
	end
	for _ = 1, count do
		local leaf = Instance.new("Part")
		leaf.Size = Vector3.new(0.32, 0.04, 0.2)
		leaf.Color = LEAF:Lerp(Color3.fromRGB(170, 210, 120), math.random())
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.CastShadow = false
		scenery(leaf)
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (0.9 + math.random() * 0.9)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		leaf.CFrame = CFrame.new(at) * spin
		leaf.Parent = workspace.Terrain
		local seconds = 0.55 + math.random() * 0.25
		animate(seconds, function(alpha)
			-- up and out, then drifting down as it slows
			local height = 1.6 * alpha - 1.9 * alpha * alpha
			leaf.CFrame = CFrame.new(at + out * math.sin(alpha * math.pi / 2) + Vector3.yAxis * height)
				* spin
				* CFrame.Angles(alpha * 4, alpha * 3, 0)
			leaf.Transparency = math.max(0, alpha - 0.6) / 0.4
		end, function()
			leaf:Destroy()
		end)
	end
end

local function produceModel(itemId: string): (Model?, { BasePart })
	if not Inventory.find(itemId) then
		return nil, {}
	end
	local model = ItemArt.copy(itemId)
	if not model then
		return nil, {}
	end
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			scenery(part)
			table.insert(parts, part)
		end
	end
	return model, parts
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- The produce bouncing up out of the plant, turning, then floating into the player who picked
-- it, shrinking as it lands (or, for someone else's or a machine's harvest, fading in the air).
local function pop(position: Vector3, itemId: string, picker: BasePart?)
	if GuiService.ReducedMotionEnabled then
		return
	end
	local model, parts = produceModel(itemId)
	if not model then
		return
	end
	local top = position + Vector3.yAxis * 2.3
	model:ScaleTo(0.35)
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace.Terrain
	local function fade(alpha: number)
		for _, part in parts do
			part.LocalTransparencyModifier = alpha
		end
	end
	animate(POP, function(alpha)
		-- easeOutBack: a little overshoot so it lands at the top with a bounce
		local back = 1 + 2.2 * (alpha - 1) ^ 3 + 1.2 * (alpha - 1) ^ 2
		model:ScaleTo(math.max(0.05, 0.35 + 0.65 * back))
		model:PivotTo(CFrame.new(position:Lerp(top, back)) * CFrame.Angles(0, alpha * 2.5, 0))
	end, function()
		task.delay(HANG, function()
			local from = model:GetPivot().Position
			if picker and picker.Parent and (picker.Position - from).Magnitude <= FLY_WITHIN then
				animate(FLY, function(alpha)
					local ease = alpha * alpha
					local target = picker.Position + Vector3.yAxis * 0.6
					local arc = Vector3.yAxis * math.sin(alpha * math.pi) * 1.4
					model:ScaleTo(math.max(0.05, 1 - 0.7 * ease))
					model:PivotTo(CFrame.new(from:Lerp(target, ease) + arc) * CFrame.Angles(0, 2.5 + alpha * 4, 0))
					fade(math.max(0, ease - 0.7) / 0.3)
				end, function()
					burst(picker.Position + Vector3.yAxis * 0.6, GLOW, 5, 3, 0.25, TWINKLE)
					model:Destroy()
				end)
			else
				animate(FLY, function(alpha)
					model:ScaleTo(math.max(0.05, 1 - 0.5 * alpha))
					model:PivotTo(CFrame.new(from + Vector3.yAxis * alpha * 0.8) * CFrame.Angles(0, 2.5 + alpha * 2, 0))
					fade(alpha)
				end, function()
					model:Destroy()
				end)
			end
		end)
	end)
end

local function harvest(fx: { [string]: any }, position: Vector3)
	local itemId = if typeof(fx.itemId) == "string" then fx.itemId else ""
	local crop = World.CROPS[itemId]
	local mutation = if typeof(fx.mutation) == "string" then Mutations.parse(fx.mutation) else nil
	local color = if mutation then Mutations.color(mutation) elseif crop then crop.color else GLOW
	local foot = position - Vector3.yAxis * 1.15
	local mine = fx.by == Players.LocalPlayer.UserId
	groundRing(foot, color:Lerp(Color3.new(1, 1, 1), 0.35), if mutation then 7 else 4.5, 0.55)
	burst(position, color, if mutation then 18 else 10, 6, 0.28)
	burst(position + Vector3.yAxis * 0.6, color:Lerp(GLOW, 0.5), if mutation then 14 else 5, 4, 0.45, TWINKLE)
	leaves(position, 4)
	if mutation then
		-- each of a stacked crop's mutations shimmers in its own colour
		for _, name in mutation do
			burst(position + Vector3.yAxis, Mutations.color({ name }), 6, 5, 0.5, TWINKLE)
		end
		groundRing(foot + Vector3.yAxis * 0.02, color, 10, 0.9)
	end
	pop(
		position,
		if mutation then `{itemId}+{fx.mutation}` else itemId,
		if mine then rootOf(Players.LocalPlayer) else nil
	)
	-- A mutated pick layers its shimmer over the plain pluck.
	Sound.play("Harvest", position)
	if mutation then
		Sound.play("HarvestRare", position)
	end
end

-- A chopped tree's look tipping over away from its chopper, then settling into the ground.
local function fell(fx: { [string]: any }, position: Vector3)
	local pivot: CFrame = if typeof(fx.pivot) == "CFrame" then fx.pivot else CFrame.new(position)
	local base = pivot.Position
	burst(base + Vector3.yAxis * 1.2, WOOD, 12, 7, 0.3)
	Sound.play("Chop", base)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local holder = if assets then assets:FindFirstChild("World") else nil
	local art = if holder and typeof(fx.look) == "string" then holder:FindFirstChild(fx.look) else nil
	if GuiService.ReducedMotionEnabled or not art or not art:IsA("Model") then
		burst(base + Vector3.yAxis * 6, LEAF, 16, 5, 0.45)
		Sound.play("TreeFall", base)
		return
	end
	local tree = art:Clone()
	local parts = {}
	for _, part in tree:GetDescendants() do
		if part:IsA("BasePart") then
			scenery(part)
			if part.Name == "Hitbox" then
				part.Transparency = 1
			end
			table.insert(parts, part)
		end
	end
	tree:PivotTo(pivot)
	tree.Parent = workspace.Terrain
	local _, size = tree:GetBoundingBox()
	local from = if typeof(fx.from) == "Vector3" then fx.from else base - pivot.LookVector
	local away = Vector3.new(base.X - from.X, 0, base.Z - from.Z)
	away = if away.Magnitude > 0.1 then away.Unit else pivot.LookVector
	-- Tip about the foot, on the axis across the fall.
	local up = Vector3.new(0, 1, 0)
	local axis = up:Cross(away).Unit
	local start = tree:GetPivot()
	local function tipped(angle: number): CFrame
		return CFrame.new(base) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-base) * start
	end
	animate(FALL, function(alpha)
		-- slow to start, quick at the end, like a tree going over
		tree:PivotTo(tipped(math.rad(84) * alpha ^ 2.2))
	end, function()
		local landed = base + away * size.Y * 0.6 + Vector3.yAxis * 0.8
		burst(landed, LEAF, 22, 6, 0.5)
		burst(landed, SOIL, 10, 4, 0.35)
		Sound.play("TreeFall", landed)
		local down = tree:GetPivot()
		animate(SETTLE, function(alpha)
			tree:PivotTo(down - Vector3.yAxis * alpha * 1.2)
			for _, part in parts do
				part.LocalTransparencyModifier = alpha
			end
		end, function()
			tree:Destroy()
		end)
	end)
end

-- A soft ring of light spreading out round the player's feet.
local function ring(color: Color3)
	local root = rootOf(Players.LocalPlayer)
	if not root then
		return
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.1, 2, 2)
	part.CFrame = CFrame.new(root.Position - Vector3.yAxis * 2.8) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.3
	scenery(part)
	part.Parent = workspace.Terrain
	if not GuiService.ReducedMotionEnabled then
		TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.1, 14, 14),
			Transparency = 1,
		}):Play()
	end
	Debris:AddItem(part, 1)
	burst(root.Position, color, 18, 9, 0.35)
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	return if character then character:GetPivot().Position else nil
end

local function show(fx: { [string]: any })
	local kind, position = fx.kind, fx.position
	if kind == "Plant" and typeof(position) == "Vector3" and near(position) then
		burst(position, SOIL, 8, 4, 0.25)
		Sound.play("Plant", position)
	elseif kind == "Harvest" and typeof(position) == "Vector3" and near(position) then
		harvest(fx, position)
	elseif kind == "Water" and typeof(position) == "Vector3" and near(position) then
		Sound.play("Water", position)
	elseif kind == "Chop" and typeof(position) == "Vector3" and near(position) then
		fell(fx, position)
	elseif kind == "Sell" then
		if typeof(position) == "Vector3" then
			-- a Shipping Bin selling: a small, silent sparkle at the bin
			if near(position) then
				burst(position + Vector3.yAxis * 2, COIN, 5, 5, 0.22)
			end
		else
			local at = characterPosition()
			if at then
				burst(at, COIN, 16, 8, 0.3)
			end
			Sound.play("Coin")
		end
	elseif kind == "Buy" then
		Sound.play("Buy")
	elseif kind == "Craft" then
		local at = characterPosition()
		if at then
			burst(at + Vector3.yAxis, WOOD, 10, 5, 0.25)
		end
		Sound.play("Craft")
	elseif kind == "Research" then
		local root = rootOf(Players.LocalPlayer)
		if root then
			VFXPlayer.Play("ResearchComplete", root.CFrame, {
				Character = Players.LocalPlayer.Character,
				Reduced = GuiService.ReducedMotionEnabled,
			})
		end
		Sound.play("ResearchDone")
	elseif kind == "LevelUp" then
		ring(GLOW)
		Sound.play("LevelUp")
	end
end

function FxController.init()
	Remotes.Fx.OnClientEvent:Connect(function(fx: unknown)
		if typeof(fx) == "table" then
			show(fx :: { [string]: any })
		end
	end)
end

return FxController
