-- PlotService: builds the six plots with runtime parts and WorldService soil nodes. The
-- first free plot is assigned by DataService after a profile opens; release follows saving
-- and clearing the old world. All plots face -Z, keeping saved coordinates and farms aligned.
-- Decorative fences never obstruct placement queries. The hub spawn is shared.
--
-- The fence is one PlotFence prop per edge cell, with a PlotFencePost at each corner and either
-- side of a two-cell gate in the middle of the front; the PlotSign stands outside the fence beside
-- the gate with the owner's name on its board. A place without those props gets plain parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Props = require(ServerScriptService.Libraries.Props)
local WorldService = require(script.Parent.WorldService)

-- The front edge's cells left open as the gate.
local GATE = { [11] = true, [12] = true }

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

local function fence(model: Model, origin: Vector3, width: number): boolean
	if not Props.template("PlotFence") or not Props.template("PlotFencePost") then
		return false
	end
	local grid = Build.GRID
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	for i = 0, Plot.SIZE - 1 do
		local along = (i + 0.5) * grid
		Props.place("PlotFence", CFrame.new(origin + Vector3.new(0, 0, along)) * turn, model)
		Props.place("PlotFence", CFrame.new(origin + Vector3.new(width, 0, along)) * turn, model)
		Props.place("PlotFence", CFrame.new(origin + Vector3.new(along, 0, width)), model)
		if not GATE[i] then
			Props.place("PlotFence", CFrame.new(origin + Vector3.new(along, 0, 0)), model)
		end
	end
	for _, corner in { Vector3.zero, Vector3.new(width, 0, 0), Vector3.new(0, 0, width), Vector3.new(width, 0, width) } do
		Props.place("PlotFencePost", CFrame.new(origin + corner), model)
	end
	for i in GATE do
		for _, side in { i * grid, (i + 1) * grid } do
			Props.place("PlotFencePost", CFrame.new(origin + Vector3.new(side, 0, 0)), model)
		end
	end
	return true
end

-- The sign's name label: on the PlotSign's board, or a floating one over a plain part.
local function sign(model: Model, origin: Vector3, width: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(65, 78, 52)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.Text = "Available garden"
	local prop = Props.place("PlotSign", CFrame.new(origin + Vector3.new(width / 2 + 9, 0, -1.5)), model)
	local board = if prop then Props.part(prop, "Board") else nil
	if board then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.4
		gui.MaxDistance = 180
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.08, 0)
		padding.PaddingRight = UDim.new(0.08, 0)
		padding.PaddingTop = UDim.new(0.18, 0)
		padding.PaddingBottom = UDim.new(0.18, 0)
		padding.Parent = gui
		label.Parent = gui
		gui.Parent = board
		return label
	end
	local fenceColor = Color3.fromRGB(225, 211, 178)
	local plain = part(model, "Sign", Vector3.new(9, 3, 0.4), origin + Vector3.new(width / 2, 4, -1), fenceColor, false)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(210, 50)
	gui.Adornee = plain
	gui.MaxDistance = 180
	gui.Parent = plain
	label.Parent = gui
	return label
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
		if not fence(model, origin, width) then
			local fenceColor = Color3.fromRGB(225, 211, 178)
			for _, x in { 0, width } do
				part(
					model,
					"Fence",
					Vector3.new(0.5, 2, width),
					origin + Vector3.new(x, 1, width / 2),
					fenceColor,
					false
				)
			end
			part(
				model,
				"Fence",
				Vector3.new(width, 2, 0.5),
				origin + Vector3.new(width / 2, 1, width),
				fenceColor,
				false
			)
			for _, x in { width / 4 - 2, width * 3 / 4 + 2 } do
				part(
					model,
					"Fence",
					Vector3.new(width / 2 - 4, 2, 0.5),
					origin + Vector3.new(x, 1, 0),
					fenceColor,
					false
				)
			end
		end
		signs[index] = sign(model, origin, width)
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
	for _, name in
		{
			"IslandsMachines",
			"IslandsWorld",
			"IslandsItems",
			"GardenWorld",
			"GardenItems",
			"GardenMachines",
			"GardenProcessors",
			"GardenConveyors",
			"GardenRouters",
			"GardenProps",
		}
	do
		local showcase = workspace:FindFirstChild(name)
		if showcase then
			showcase:Destroy()
		end
	end
end

return PlotService
