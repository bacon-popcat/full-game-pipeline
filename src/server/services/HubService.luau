-- HubService: stands the hub's stalls and their prompts, on a paved plaza dressed with lamps and
-- flower boxes. Hub owns positions and transaction reach; the authored HUD remains entirely in
-- the place file. Each stall is its Assets.Props model (garden_props.py), turned to face the
-- spawn, with its prompt on the counter; a place without the prop gets a plain placeholder.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Hub = require(ReplicatedStorage.Shared.Hub)
local Props = require(ServerScriptService.Libraries.Props)
local HubService = {}

local PLAZA_SIZE = Vector3.new(72, 0.3, 50)
local PLAZA_COLOR = Color3.fromRGB(233, 223, 203)
local LAMPS = { Vector3.new(-14, 0, -15), Vector3.new(14, 0, -15), Vector3.new(-14, 0, 15), Vector3.new(14, 0, 15) }
local FLOWER_BOXES = { Vector3.new(-7, 0, -8), Vector3.new(7, 0, -8), Vector3.new(-7, 0, 8), Vector3.new(7, 0, 8) }

-- Each stall's canopy colour and prompt words.
local LOOKS: { [string]: { canopy: Color3, action: string, title: string } } = {
	SeedShop = { canopy = Color3.fromRGB(179, 207, 158), action = "Shop", title = "Seed Shop" },
	SellStand = { canopy = Color3.fromRGB(242, 211, 164), action = "Sell", title = "Sell Stand" },
	GearShop = { canopy = Color3.fromRGB(160, 205, 214), action = "Shop", title = "Gear Shop" },
	MachineShop = { canopy = Color3.fromRGB(214, 190, 222), action = "Shop", title = "Machine Shop" },
}

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
	-- 0.05 proud of the baseplate, like the plots, so its grid texture cannot flicker through
	local plaza = part(hub, "Plaza", PLAZA_SIZE, Vector3.new(0, 0.05 - PLAZA_SIZE.Y / 2, 0), PLAZA_COLOR)
	plaza.CanCollide = true
	for _, position in LAMPS do
		Props.place("HubLamp", CFrame.new(position), hub)
	end
	for _, position in FLOWER_BOXES do
		-- turned so its long side runs along the plaza's edge toward the stalls
		Props.place("HubFlowerBox", CFrame.new(position) * CFrame.Angles(0, math.pi / 2, 0), hub)
	end
	for name, position in Hub.STALLS do
		local look = LOOKS[name]
		-- the prop's counter faces -Z; stalls north of the spawn turn round to face it
		local facing = if position.Z < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
		local prop = Props.place(name, CFrame.new(position) * facing, hub)
		local propCounter = if prop then Props.part(prop, "Counter") else nil
		if prop and propCounter then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "Prompt"
			prompt.ActionText = look.action
			prompt.ObjectText = look.title
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = propCounter
			continue
		end
		local stall = Instance.new("Model")
		stall.Name = name
		local wood = Color3.fromRGB(219, 192, 156)
		local counter = part(stall, "Counter", Vector3.new(9, 3, 3), position + Vector3.new(0, 1.5, 0), wood)
		for _, x in { -4, 4 } do
			part(stall, "Post", Vector3.new(0.5, 7, 0.5), position + Vector3.new(x, 3.5, 1), wood)
		end
		part(stall, "Canopy", Vector3.new(10, 0.5, 5), position + Vector3.new(0, 7, 0), look.canopy)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = look.action
		prompt.ObjectText = look.title
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = counter
		stall.Parent = hub
	end
	hub.Parent = workspace
end
return HubService
