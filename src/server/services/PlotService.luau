-- PlotService: builds the six plots with runtime parts and WorldService soil nodes. The
-- first free plot is assigned by DataService after a profile opens; release follows saving
-- and clearing the old world. All plots face -Z, keeping saved coordinates and farms aligned.
-- Decorative fences never obstruct placement queries. The hub spawn is shared.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local WorldService = require(script.Parent.WorldService)

local PlotService = {}
local assigned: { [Player]: number } = {}
local models: { Model } = {}
local signs: { TextLabel } = {}
local plots = Instance.new("Folder")
plots.Name = "Plots"
plots.Parent = workspace
local built = false

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	solid: boolean
): Part
	local block = Instance.new("Part")
	block.Name = name
	block.Size = size
	block.Position = position
	block.Color = color
	block.Material = Enum.Material.SmoothPlastic
	block.Anchored = true
	block.CanCollide = solid
	block.CanQuery = solid
	block.CanTouch = false
	block.Parent = parent
	return block
end

local function build()
	if built then
		return
	end
	built = true
	for index = 1, Plot.COUNT do
		local model = Instance.new("Model")
		model.Name = tostring(index)
		model:SetAttribute("Owner", 0)
		model.Parent = plots
		models[index] = model
		local origin = Plot.origin(index) * Build.GRID
		local width = Plot.SIZE * Build.GRID
		part(
			model,
			"Grass",
			Vector3.new(width, 0.4, width),
			-- 0.05 proud of the baseplate so its grid texture can't flicker through.
			origin + Vector3.new(width / 2, -0.15, width / 2),
			Color3.fromRGB(153, 191, 126),
			true
		)
		local fenceColor = Color3.fromRGB(225, 211, 178)
		for _, x in { 0, width } do
			part(model, "Fence", Vector3.new(0.5, 2, width), origin + Vector3.new(x, 1, width / 2), fenceColor, false)
		end
		part(model, "Fence", Vector3.new(width, 2, 0.5), origin + Vector3.new(width / 2, 1, width), fenceColor, false)
		for _, x in { width / 4 - 2, width * 3 / 4 + 2 } do
			part(model, "Fence", Vector3.new(width / 2 - 4, 2, 0.5), origin + Vector3.new(x, 1, 0), fenceColor, false)
		end
		local sign =
			part(model, "Sign", Vector3.new(9, 3, 0.4), origin + Vector3.new(width / 2, 4, -1), fenceColor, false)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(210, 50)
		gui.Adornee = sign
		gui.MaxDistance = 180
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(65, 78, 52)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.Text = "Available garden"
		label.Parent = gui
		signs[index] = label
		for x = 6, 17 do
			for z = 2, 9 do
				WorldService.farmland(Plot.toWorld(index, Vector3.new(x, 0, z)))
			end
		end
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.Position = Vector3.new(0, 0.2, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.Parent = plots
end

function PlotService.assign(player: Player): number?
	build()
	if assigned[player] then
		return assigned[player]
	end
	for index, model in models do
		if model:GetAttribute("Owner") == 0 then
			assigned[player] = index
			model:SetAttribute("Owner", player.UserId)
			signs[index].Text = player.DisplayName .. "'s garden"
			return index
		end
	end
	return nil
end

function PlotService.get(player: Player): number?
	return assigned[player]
end

function PlotService.release(player: Player)
	local index = assigned[player]
	if not index then
		return
	end
	models[index]:SetAttribute("Owner", 0)
	signs[index].Text = "Available garden"
	assigned[player] = nil
end

function PlotService.init()
	build()
	-- Remove only the live showcases; authored templates and the place file stay untouched.
	for _, name in { "IslandsMachines", "IslandsWorld", "IslandsItems", "GardenWorld", "GardenItems" } do
		local showcase = workspace:FindFirstChild(name)
		if showcase then
			showcase:Destroy()
		end
	end
end

return PlotService
