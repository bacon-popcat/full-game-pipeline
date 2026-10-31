-- PlotService: builds the six gardens with runtime parts and WorldService soil nodes, and sells
-- their sections (Shared/Plot). The first free garden is assigned by DataService after a profile
-- opens, with its bought sections; release follows saving and clearing the old world. All
-- plots face -Z, keeping saved coordinates and farms aligned. Decorative fences never obstruct
-- placement queries. The hub spawn is shared, and the place's Baseplate is widened so every
-- garden stands on ground.
--
-- A garden's scenery (its Boundary model) is rebuilt whenever its owner or sections change,
-- never its soil, crops or machines: one ground tile per section (grass where owned, a darker
-- tone where locked), each locked section's price lying on its ground (dimmed until it touches
-- owned land), a BuySection prompt on each section that can be bought, and a fence round the
-- owned land, whatever its shape: one PlotFence prop per cell edge between owned and unowned
-- land, a PlotFencePost at every corner of it, and a two-cell gate in the middle of the start
-- block's front. The PlotSign stands outside the gate with the owner's name on its board. A
-- place without those props gets plain parts. Prompts start disabled; PlotController enables
-- the ones on the local player's own garden, so nobody else sees them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local Props = require(ServerScriptService.Libraries.Props)
local EconomyService = require(script.Parent.EconomyService)
local WorldService = require(script.Parent.WorldService)

local GRID = Build.GRID
-- Relative cells along the start block's front edge left open as the gate.
local GATE_X = { [Plot.START_OFFSET.X + 14] = true, [Plot.START_OFFSET.X + 15] = true }
local COOLDOWN = 0.5
local GRASS = Color3.fromRGB(153, 191, 126)
local LOCKED = Color3.fromRGB(119, 132, 105)
local FENCE = Color3.fromRGB(225, 211, 178)
local PRICE_TEXT = Color3.fromRGB(246, 238, 214)
-- Studs of ground round the gardens on every side.
local GROUND_MARGIN = 36

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

-- Widens the place's Baseplate (top kept where it is) to reach past every garden, or lays a
-- ground part where there is none.
local function ground()
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for index = 1, Plot.COUNT do
		local origin = Plot.origin(index) * GRID
		low = low:Min(origin)
		high = high:Max(origin + Vector3.new(Plot.WIDTH, 0, Plot.DEPTH) * GRID)
	end
	local half = Vector3.new(
		math.max(math.abs(low.X), math.abs(high.X)) + GROUND_MARGIN,
		0,
		math.max(math.abs(low.Z), math.abs(high.Z)) + GROUND_MARGIN
	)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		local top = baseplate.Position.Y + baseplate.Size.Y / 2
		baseplate.Size = Vector3.new(half.X * 2, baseplate.Size.Y, half.Z * 2)
		baseplate.Position = Vector3.new(0, top - baseplate.Size.Y / 2, 0)
	else
		part(workspace, "Ground", Vector3.new(half.X * 2, 20, half.Z * 2), Vector3.new(0, -10, 0), GRASS, true)
	end
end

-- One fence piece along a cell edge from `a` to `b` (studs, one cell apart): a PlotFence prop
-- or a plain rail.
local function rail(parent: Instance, a: Vector3, b: Vector3)
	local middle = (a + b) / 2
	local alongZ = math.abs(b.Z - a.Z) > math.abs(b.X - a.X)
	local turn = if alongZ then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity
	if not Props.place("PlotFence", CFrame.new(middle) * turn, parent) then
		local size = if alongZ then Vector3.new(0.5, 2, GRID) else Vector3.new(GRID, 2, 0.5)
		part(parent, "Fence", size, middle + Vector3.new(0, 1, 0), FENCE, false)
	end
end

local function post(parent: Instance, at: Vector3)
	if not Props.place("PlotFencePost", CFrame.new(at), parent) then
		part(parent, "FencePost", Vector3.new(0.7, 2.4, 0.7), at + Vector3.new(0, 1.2, 0), FENCE, false)
	end
end

-- The fence round owned land: every cell edge with owned land on one side only.
local function fence(parent: Instance, index: number)
	local origin = Plot.origin(index) * GRID
	local posts: { [string]: Vector3 } = {}
	local function owned(cx: number, cz: number): boolean
		local x, z = cx // Plot.SECTION, cz // Plot.SECTION
		return cx >= 0 and cz >= 0 and Plot.owns(index, x, z)
	end
	local function edge(ax: number, az: number, bx: number, bz: number)
		local a = origin + Vector3.new(ax, 0, az) * GRID
		local b = origin + Vector3.new(bx, 0, bz) * GRID
		rail(parent, a, b)
		posts[`{ax},{az}`] = a
		posts[`{bx},{bz}`] = b
	end
	for cx = 0, Plot.WIDTH - 1 do
		for cz = 0, Plot.DEPTH - 1 do
			if owned(cx, cz) then
				if not owned(cx, cz - 1) and not (cz == 0 and GATE_X[cx]) then
					edge(cx, cz, cx + 1, cz)
				end
				if not owned(cx, cz + 1) then
					edge(cx, cz + 1, cx + 1, cz + 1)
				end
				if not owned(cx - 1, cz) then
					edge(cx, cz, cx, cz + 1)
				end
				if not owned(cx + 1, cz) then
					edge(cx + 1, cz, cx + 1, cz + 1)
				end
			end
		end
	end
	for _, at in posts do
		post(parent, at)
	end
end

-- 2500 -> "2,500".
local function commas(amount: number): string
	local text = tostring(amount)
	while true do
		local spaced, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = spaced
		if count == 0 then
			return text
		end
	end
end

-- A locked section's price, lying face up on its ground tile.
local function price(tile: BasePart, coins: number, buyable: boolean)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Price"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0.6
	gui.MaxDistance = 400
	local fade = if buyable then 0.05 else 0.6
	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.AnchorPoint = Vector2.new(0.5, 1)
	amount.Position = UDim2.fromScale(0.5, 0.58)
	amount.Size = UDim2.fromScale(0.9, 0.28)
	amount.BackgroundTransparency = 1
	amount.Font = Enum.Font.GothamBold
	amount.TextScaled = true
	amount.TextColor3 = PRICE_TEXT
	amount.TextTransparency = fade
	amount.Text = commas(coins)
	amount.Parent = gui
	local unit = Instance.new("TextLabel")
	unit.Name = "Unit"
	unit.AnchorPoint = Vector2.new(0.5, 0)
	unit.Position = UDim2.fromScale(0.5, 0.6)
	unit.Size = UDim2.fromScale(0.5, 0.11)
	unit.BackgroundTransparency = 1
	unit.Font = Enum.Font.GothamMedium
	unit.TextScaled = true
	unit.TextColor3 = PRICE_TEXT
	unit.TextTransparency = fade
	unit.Text = "coins"
	unit.Parent = gui
	gui.Parent = tile
end

-- The prompt that buys a section, hidden until PlotController shows it to the owner.
local function buyPrompt(parent: Instance, index: number, x: number, z: number, coins: number)
	local anchor = part(
		parent,
		"BuyAnchor",
		Vector3.one,
		Plot.sectionCentre(index, x, z, GRID) + Vector3.new(0, 3, 0),
		LOCKED,
		false
	)
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuySection"
	prompt.ActionText = "Buy section"
	prompt.ObjectText = `{commas(coins)} coins`
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("SectionX", x)
	prompt:SetAttribute("SectionZ", z)
	prompt.Parent = anchor
end

-- Rebuilds a garden's scenery from its current owner and sections.
local function landscape(index: number)
	local model = models[index]
	local old = model:FindFirstChild("Boundary")
	if old then
		old:Destroy()
	end
	local boundary = Instance.new("Model")
	boundary.Name = "Boundary"
	local owned = model:GetAttribute("Owner") ~= 0
	local size = Vector3.new(Plot.SECTION * GRID, 0.4, Plot.SECTION * GRID)
	-- Locked tiles turn (they are square) so their price reads upright from the hub side.
	local facing = CFrame.Angles(0, if Plot.origin(index).Z < 0 then -math.pi / 2 else math.pi / 2, 0)
	for x = 0, Plot.SECTIONS_X - 1 do
		for z = 0, Plot.SECTIONS_Z - 1 do
			local mine = Plot.owns(index, x, z)
			-- 0.05 proud of the baseplate so its texture cannot flicker through.
			local centre = Plot.sectionCentre(index, x, z, GRID) - Vector3.new(0, 0.15, 0)
			local tile = part(
				boundary,
				if mine then "Grass" else "LockedLand",
				size,
				centre,
				if mine then GRASS else LOCKED,
				true
			)
			if not mine then
				tile.CFrame = CFrame.new(centre) * facing
				local coins = Plot.price(x, z)
				local buyable = owned and Plot.canBuy(index, x, z)
				price(tile, coins, buyable)
				if buyable then
					buyPrompt(boundary, index, x, z, coins)
				end
			end
		end
	end
	fence(boundary, index)
	boundary.Parent = model
end

-- The sign's name label: on the PlotSign's board, or a floating one over a plain part.
local function sign(model: Model, at: Vector3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(65, 78, 52)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.Text = "Available garden"
	local prop = Props.place("PlotSign", CFrame.new(at), model)
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
	local plain = part(model, "Sign", Vector3.new(9, 3, 0.4), at + Vector3.new(0, 4, 0), FENCE, false)
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
	ground()
	for index = 1, Plot.COUNT do
		local model = Instance.new("Model")
		model.Name = tostring(index)
		model:SetAttribute("Owner", 0)
		model:SetAttribute("Sections", "")
		model.Parent = plots
		models[index] = model
		landscape(index)
		-- Beside the gate, just outside the front fence.
		local gate = Plot.START_OFFSET.X + 15
		signs[index] = sign(model, (Plot.origin(index) + Vector3.new(gate + 3, 0, 0)) * GRID + Vector3.new(0, 0, -1.5))
		local farm = Plot.START_OFFSET
		for x = 6, 17 do
			for z = 2, 9 do
				WorldService.farmland(Plot.toWorld(index, farm + Vector3.new(x, 0, z)))
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

-- Assigns the first free garden with the sections the player bought ("x,z" strings).
function PlotService.assign(player: Player, sections: { string }?): number?
	build()
	if assigned[player] then
		return assigned[player]
	end
	for index, model in models do
		if model:GetAttribute("Owner") == 0 then
			assigned[player] = index
			model:SetAttribute("Sections", table.concat(Plot.encode(Plot.decode(sections)), ";"))
			model:SetAttribute("Owner", player.UserId)
			landscape(index)
			signs[index].Text = player.DisplayName .. "'s garden"
			return index
		end
	end
	return nil
end

function PlotService.get(player: Player): number?
	return assigned[player]
end

-- The sections a garden has bought, for its owner's save.
function PlotService.sections(index: number): { string }
	return Plot.encode(Plot.decode(models[index]:GetAttribute("Sections")))
end

function PlotService.release(player: Player)
	lastAction[player] = nil
	local index = assigned[player]
	if not index then
		return
	end
	models[index]:SetAttribute("Owner", 0)
	models[index]:SetAttribute("Sections", "")
	landscape(index)
	signs[index].Text = "Available garden"
	assigned[player] = nil
end

local function purchase(player: Player, x: unknown, z: unknown)
	local now = os.clock()
	if now - (lastAction[player] or -math.huge) < COOLDOWN then
		return
	end
	lastAction[player] = now
	local index = assigned[player]
	if
		player:GetAttribute("DataReady") ~= true
		or not index
		or typeof(x) ~= "number"
		or typeof(z) ~= "number"
		or not Plot.canBuy(index, x, z)
	then
		return
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if
		not root
		or not root:IsA("BasePart")
		or (root.Position - Plot.sectionCentre(index, x, z, GRID)).Magnitude > Plot.BUY_REACH
	then
		return
	end
	local coins = Plot.price(x, z)
	if not EconomyService.trySpend(player, coins) then
		Remotes.Notify:FireClient(player, "You need more coins for this section.")
		return
	end
	-- Publish the section before scenery work, so a snapshot always sees what was paid for.
	local model = models[index]
	local bought = Plot.decode(model:GetAttribute("Sections"))
	bought[Plot.key(x, z)] = true
	model:SetAttribute("Sections", table.concat(Plot.encode(bought), ";"))
	landscape(index)
	Remotes.Notify:FireClient(player, "New garden section unlocked!")
	GardenEvents.SectionBought:Fire(player, x, z)
end

function PlotService.init()
	build()
	Remotes.PlotBuySection.OnServerEvent:Connect(purchase)
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
