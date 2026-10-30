-- FxController: shows and sounds the moments FxService sends (Remotes.Fx). Each is short and soft:
-- a puff of soil when planting, a pop of the crop's colour and its produce bobbing up when
-- harvesting, coins sparkling round you when you sell, a warm ring when you level up. Reduced
-- motion keeps the sounds and colours but drops the movement. Nothing here changes the game.
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Sound = require(Players.LocalPlayer.PlayerScripts.Libraries.Sound)

local FxController = {}

local SOIL = Color3.fromRGB(176, 128, 82)
local COIN = Color3.fromRGB(246, 214, 120)
local GLOW = Color3.fromRGB(255, 236, 190)
-- Studs past which nobody needs to see someone else's farm moment.
local SHOW_WITHIN = 140
local BOB_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Seconds between a Shipping Bin's coin sounds, so a busy bin chimes instead of chattering.
local BIN_SOUND_EVERY = 1.5

local lastBinSound = 0

local function near(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= SHOW_WITHIN
end

-- A one-off burst of `count` soft particles at `position`.
local function burst(position: Vector3, color: Color3, count: number, speed: number, size: number)
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
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(if GuiService.ReducedMotionEnabled then math.ceil(count / 2) else count)
	Debris:AddItem(holder, 1.5)
end

-- The produce, small, bobbing up out of the crop and fading.
local function bob(position: Vector3, itemId: string)
	if GuiService.ReducedMotionEnabled or not Inventory.find(itemId) then
		return
	end
	local model = ItemArt.copy(itemId)
	if not model then
		return
	end
	model:ScaleTo(0.9)
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			table.insert(parts, part)
		end
	end
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace.Terrain
	local lift = Instance.new("CFrameValue")
	lift.Value = model:GetPivot()
	lift.Changed:Connect(function(value)
		model:PivotTo(value)
	end)
	TweenService
		:Create(lift, BOB_TWEEN, { Value = CFrame.new(position + Vector3.yAxis * 2.2) * CFrame.Angles(0, 2, 0) })
		:Play()
	for _, part in parts do
		TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		}):Play()
	end
	Debris:AddItem(model, 0.8)
	Debris:AddItem(lift, 0.8)
end

-- A soft ring of light spreading out round the player's feet.
local function ring(color: Color3)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.1, 2, 2)
	part.CFrame = CFrame.new(root.Position - Vector3.yAxis * 2.8) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.3
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
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
		local itemId = if typeof(fx.itemId) == "string" then fx.itemId else ""
		local crop = World.CROPS[itemId]
		local mutation = if typeof(fx.mutation) == "string" then Mutations.ALL[fx.mutation] else nil
		local color = if mutation then mutation.color elseif crop then crop.color else GLOW
		burst(position, color, if mutation then 22 else 12, 6, 0.3)
		bob(position, if mutation then `{itemId}+{fx.mutation}` else itemId)
		Sound.play("Harvest", position)
	elseif kind == "Water" and typeof(position) == "Vector3" and near(position) then
		Sound.play("Water", position)
	elseif kind == "Sell" then
		if typeof(position) == "Vector3" then
			-- a Shipping Bin selling: a small sparkle at the bin, a chime now and then
			if near(position) then
				burst(position + Vector3.yAxis * 2, COIN, 5, 5, 0.22)
			end
			if os.clock() - lastBinSound >= BIN_SOUND_EVERY then
				lastBinSound = os.clock()
				Sound.play("Coin", position)
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
