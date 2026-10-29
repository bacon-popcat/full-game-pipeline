-- SprinklerController: a slow, soft spray over every placed sprinkler, drawn only here. What a
-- sprinkler does to crops is FactoryService's; this only shows its reach. Reduced motion keeps
-- the spray but thins it.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Factory = require(ReplicatedStorage.Shared.Factory)
local Build = require(ReplicatedStorage.Shared.Build)

local SprinklerController = {}
local sprays: { [Model]: Attachment } = {}

local function spray(model: Instance)
	if not model:IsA("Model") or sprays[model] then
		return
	end
	local itemId = model:GetAttribute("ItemId")
	local def = if typeof(itemId) == "string" then Factory.get(itemId) else nil
	local rule = if def then def.sprinkles else nil
	local hitbox = model.PrimaryPart
	if not rule or not hitbox then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Spray"
	attachment.Position = Vector3.new(0, hitbox.Size.Y / 2 - 0.4, 0)
	local drops = Instance.new("ParticleEmitter")
	drops.Color = ColorSequence.new(Color3.fromRGB(184, 222, 242))
	drops.Size = NumberSequence.new(0.14, 0.04)
	drops.Transparency = NumberSequence.new(0.35, 1)
	drops.Lifetime = NumberRange.new(1.1, 1.4)
	-- Thrown up and out so the drops land around the edge of its reach.
	local reach = rule.radius * Build.GRID
	drops.Speed = NumberRange.new(reach * 0.55, reach * 0.7)
	drops.SpreadAngle = Vector2.new(70, 70)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Acceleration = Vector3.new(0, -14, 0)
	drops.Rate = if GuiService.ReducedMotionEnabled then 6 else 18
	drops.LightInfluence = 0.6
	drops.Parent = attachment
	attachment.Parent = hitbox
	sprays[model] = attachment
end

function SprinklerController.init()
	local placed = workspace:WaitForChild("Placed")
	placed.ChildAdded:Connect(spray)
	placed.ChildRemoved:Connect(function(model)
		if model:IsA("Model") then
			sprays[model] = nil
		end
	end)
	for _, model in placed:GetChildren() do
		spray(model)
	end
end

return SprinklerController
