-- CropMutationController: ripe Mutation attributes own tint and soft sparkle. Baselines
-- come from replicated crop art, including fallback tint. A crop with stacked mutations takes
-- its most valuable one's tint and sparkles in all their colours. Only nearby mutations emit;
-- Rainbow cycles at 6 Hz and becomes a static tint with reduced motion.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local World = require(ReplicatedStorage.Shared.World)
local Trove = require(ReplicatedStorage.Packages.Trove)
type Effect = { rainbow: boolean, emitter: ParticleEmitter, parts: { [BasePart]: Color3 } }
local CropMutationController = {}
function CropMutationController.init()
	local folder = workspace:WaitForChild("World")
	local trove = Trove.new()
	local effects: { [Model]: Effect } = {}
	local bindings: { [Model]: typeof(Trove.new()) } = {}
	local function clear(model: Model)
		local effect = effects[model]
		if not effect then
			return
		end
		effect.emitter:Destroy()
		for part, color in effect.parts do
			if part.Parent then
				part.Color = color
			end
		end
		effects[model] = nil
	end
	local function refresh(model: Model)
		clear(model)
		local key, nodeType = model:GetAttribute("Mutation"), model:GetAttribute("NodeType")
		local names = if typeof(key) == "string" then Mutations.parse(key) else nil
		local def = if typeof(nodeType) == "string" then World.NODES[nodeType] else nil
		local root = model.PrimaryPart
		if not names or not def or not World.isRipe(def) or not root then
			return
		end
		local tint = Mutations.color(names)
		local sparkle = {}
		for index, name in names do
			table.insert(sparkle, ColorSequenceKeypoint.new((index - 1) / math.max(1, #names - 1), Mutations.ALL[name].color))
		end
		if #sparkle == 1 then
			table.insert(sparkle, ColorSequenceKeypoint.new(1, tint))
		end
		local parts: { [BasePart]: Color3 } = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Hitbox" then
				parts[part] = part.Color
				part.Color = tint
			end
		end
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "MutationSparkles"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(sparkle)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.16),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new(0.5)
		emitter.Lifetime = NumberRange.new(1, 1.5)
		emitter.Speed = NumberRange.new(0.3, 0.7)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 3
		emitter.LightEmission = 0.35
		emitter.Enabled = false
		emitter.Parent = root
		effects[model] = { rainbow = names[#names] == "Rainbow", emitter = emitter, parts = parts }
	end
	local function bind(child: Instance)
		if not child:IsA("Model") or bindings[child] then
			return
		end
		local def = World.NODES[child.Name]
		if not def or not def.crop then
			return
		end
		local scope = Trove.new()
		bindings[child] = scope
		local queued = false
		local function refreshParts(part: Instance)
			if not part:IsA("BasePart") or queued then
				return
			end
			queued = true
			task.defer(function()
				queued = false
				if bindings[child] and child.Parent == folder then
					refresh(child)
				end
			end)
		end
		scope:Connect(child.DescendantAdded, refreshParts)
		scope:Connect(child.DescendantRemoving, refreshParts)
		scope:Connect(child:GetAttributeChangedSignal("Mutation"), function()
			refresh(child)
		end)
		scope:Connect(child:GetAttributeChangedSignal("NodeType"), function()
			refresh(child)
		end)
		scope:Connect(child:GetPropertyChangedSignal("PrimaryPart"), function()
			refresh(child)
		end)
		refresh(child)
	end
	trove:Connect(folder.ChildAdded, bind)
	trove:Connect(folder.ChildRemoved, function(child: Instance)
		if child:IsA("Model") then
			clear(child)
			local scope = bindings[child]
			if scope then
				scope:Destroy()
			end
			bindings[child] = nil
		end
	end)
	for _, child in folder:GetChildren() do
		bind(child)
	end
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed < 1 / 6 then
			return
		end
		elapsed = 0
		local camera = workspace.CurrentCamera
		local emitting = 0
		for model, effect in effects do
			local near = camera ~= nil and (model:GetPivot().Position - camera.CFrame.Position).Magnitude < 100
			effect.emitter.Enabled = near and emitting < 48
			if effect.emitter.Enabled then
				emitting += 1
			end
			if effect.rainbow and near then
				local color = if GuiService.ReducedMotionEnabled
					then Mutations.ALL.Rainbow.color
					else Color3.fromHSV((os.clock() / 8) % 1, 0.4, 1)
				for part in effect.parts do
					part.Color = color
				end
				effect.emitter.Color = ColorSequence.new(color)
			end
		end
	end)
	trove:Connect(script.Destroying, function()
		for model, scope in bindings do
			clear(model)
			scope:Destroy()
		end
		trove:Destroy()
	end)
end
return CropMutationController
