-- HubService: builds soft placeholder stalls and their prompts. Hub owns positions and
-- transaction reach; the authored HUD remains entirely in the place file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage.Shared.Hub)
local HubService = {}

local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.Position = position
	created.Color = color
	created.Material = Enum.Material.SmoothPlastic
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.Parent = parent
	return created
end

function HubService.init()
	if workspace:FindFirstChild("Hub") then
		return
	end
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	for name, position in Hub.STALLS do
		local stall = Instance.new("Model")
		stall.Name = name
		local wood = Color3.fromRGB(219, 192, 156)
		local counter = part(stall, "Counter", Vector3.new(9, 3, 3), position + Vector3.new(0, 1.5, 0), wood)
		for _, x in { -4, 4 } do
			part(stall, "Post", Vector3.new(0.5, 7, 0.5), position + Vector3.new(x, 3.5, 1), wood)
		end
		part(
			stall,
			"Canopy",
			Vector3.new(10, 0.5, 5),
			position + Vector3.new(0, 7, 0),
			if name == "SeedShop" then Color3.fromRGB(179, 207, 158) else Color3.fromRGB(242, 211, 164)
		)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = if name == "SeedShop" then "Shop" else "Sell"
		prompt.ObjectText = if name == "SeedShop" then "Seed Shop" else "Sell Stand"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = counter
		stall.Parent = hub
	end
	hub.Parent = workspace
end
return HubService
