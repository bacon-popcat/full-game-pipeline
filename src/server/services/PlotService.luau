-- PlotService: builds the six plots with runtime parts and WorldService soil nodes. The
-- first free plot is assigned by DataService after a profile opens; release follows saving
-- and clearing the old world. All plots face -Z, keeping saved coordinates and farms aligned.
-- Decorative fences never obstruct placement queries. The hub spawn is shared.
-- The saved expansion is applied before restoration. Purchases validate the next tier and
-- spend without yielding; only scenery is rebuilt, never soil, crops or placed machines.
--
-- The fence is one PlotFence prop per edge cell, with a PlotFencePost at each corner and either
-- side of a fixed two-cell gate at the original front; the PlotSign stands outside the fence beside
-- the gate with the owner's name on its board. A place without those props gets plain parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local Props = require(ServerScriptService.Libraries.Props)
local EconomyService = require(script.Parent.EconomyService)
local WorldService = require(script.Parent.WorldService)

-- The front edge's cells left open as the gate.
local GATE = { [Plot.SIZE / 2 - 1] = true, [Plot.SIZE / 2] = true }
local COOLDOWN = 0.5

local PlotService = {}
local assigned: { [Player]: number } = {}
local models: { Model } = {}
local signs: { TextLabel } = {}
local lastAction: { [Player]: number } = {}
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

local function fence(model: Model, origin: Vector3, size: number): boolean
	if not Props.template("PlotFence") or not Props.template("PlotFencePost") then
		return false
	end
	local grid = Build.GRID
	local width = size * grid
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	for i = 0, size - 1 do
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
	local plain =
		part(model, "Sign", Vector3.new(9, 3, 0.4), origin + Vector3.new(width / 2 + 9, 4, -1.5), fenceColor, false)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(210, 50)
	gui.Adornee = plain
	gui.MaxDistance = 180
	gui.Parent = plain
	label.Parent = gui
	return label
end

local function landscape(index: number, tier: number)
	local model = models[index]
	local old = model:FindFirstChild("Boundary")
	if old then
		old:Destroy()
	end
	local boundary = Instance.new("Model")
	boundary.Name = "Boundary"
	local origin = Plot.origin(index) * Build.GRID
	local size = Plot.size(tier)
	local width = size * Build.GRID
	local maximum = Plot.MAX_SIZE * Build.GRID
	part(
		boundary,
		"Grass",
		Vector3.new(width, 0.4, width),
		-- 0.05 proud of the baseplate so its texture cannot flicker through.
		origin + Vector3.new(width / 2, -0.15, width / 2),
		Color3.fromRGB(153, 191, 126),
		true
	)
	-- Separate strips keep both ground tones flush, with no overlapping surfaces.
	if width < maximum then
		local locked = Color3.fromRGB(119, 132, 105)
		part(
			boundary,
			"LockedLand",
			Vector3.new(maximum - width, 0.4, maximum),
			origin + Vector3.new((width + maximum) / 2, -0.15, maximum / 2),
			locked,
			true
		)
		part(
			boundary,
			"LockedLand",
			Vector3.new(width, 0.4, maximum - width),
			origin + Vector3.new(width / 2, -0.15, (width + maximum) / 2),
			locked,
			true
		)
	end
	if not fence(boundary, origin, size) then
		local color = Color3.fromRGB(225, 211, 178)
		for _, x in { 0, width } do
			part(boundary, "Fence", Vector3.new(0.5, 2, width), origin + Vector3.new(x, 1, width / 2), color, false)
		end
		part(boundary, "Fence", Vector3.new(width, 2, 0.5), origin + Vector3.new(width / 2, 1, width), color, false)
		local gateStart = (Plot.SIZE / 2 - 1) * Build.GRID
		local gateEnd = (Plot.SIZE / 2 + 1) * Build.GRID
		part(boundary, "Fence", Vector3.new(gateStart, 2, 0.5), origin + Vector3.new(gateStart / 2, 1, 0), color, false)
		part(
			boundary,
			"Fence",
			Vector3.new(width - gateEnd, 2, 0.5),
			origin + Vector3.new((width + gateEnd) / 2, 1, 0),
			color,
			false
		)
	end
	boundary.Parent = model
	model:SetAttribute("Expansion", tier)
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
		landscape(index, 0)
		signs[index] = sign(model, origin, width)
		local anchor =
			part(model, "ExpansionSign", Vector3.one, origin + Vector3.new(width / 2 + 9, 3, -1.5), Color3.new(), false)
		anchor.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ExpandPlot"
		prompt.ActionText = "Expand garden"
		prompt.ObjectText = "Garden space"
		prompt.MaxActivationDistance = Plot.REACH
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchor
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

function PlotService.assign(player: Player, tier: number?): number?
	build()
	if assigned[player] then
		return assigned[player]
	end
	for index, model in models do
		if model:GetAttribute("Owner") == 0 then
			assigned[player] = index
			landscape(index, Plot.sanitize(tier))
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
	lastAction[player] = nil
	local index = assigned[player]
	if not index then
		return
	end
	models[index]:SetAttribute("Owner", 0)
	landscape(index, 0)
	signs[index].Text = "Available garden"
	assigned[player] = nil
end

local function purchase(player: Player, nextTier: unknown)
	local now = os.clock()
	if now - (lastAction[player] or -math.huge) < COOLDOWN then
		return
	end
	lastAction[player] = now
	local index = assigned[player]
	if player:GetAttribute("DataReady") ~= true or not index or not Plot.inReach(player, index) then
		Remotes.Notify:FireClient(player, "Visit your garden sign to buy more space.")
		return
	end
	local tier = Plot.tier(index)
	local offer = Plot.EXPANSIONS[tier + 1]
	if typeof(nextTier) ~= "number" or nextTier ~= tier + 1 or not offer then
		Remotes.Notify:FireClient(player, "That expansion is no longer available. Check your garden sign.")
		return
	end
	if not EconomyService.trySpend(player, offer.price) then
		Remotes.Notify:FireClient(player, "You need more coins for this expansion.")
		return
	end
	-- Publish the entitlement before scenery work; a snapshot always sees the paid tier.
	models[index]:SetAttribute("Expansion", tier + 1)
	landscape(index, tier + 1)
	Remotes.Notify:FireClient(player, `Garden expanded to {offer.size} x {offer.size} cells!`)
	GardenEvents.Expanded:Fire(player, tier + 1)
end

function PlotService.init()
	build()
	Remotes.PlotExpand.OnServerEvent:Connect(purchase)
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
