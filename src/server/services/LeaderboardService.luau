-- LeaderboardService: three boards in the hub, each the top TOP gardens by one number: coins
-- earned, crops harvested (Progress stats) and garden likes (SocialService). A garden's numbers
-- are written to an OrderedDataStore per board whenever DataService saves it, keeping the
-- higher of the stored and the new value (a player's save files share one row), and the boards
-- are read again every REFRESH seconds. Names are display names looked up from user ids.
--
-- The board is the Leaderboards prop (Assets.Props, garden_kitchen.py) stood at BOARD_AT, with a
-- SurfaceGui of three columns on its Board part's front, each column under the prop's medallion
-- for it; a place without the prop gets a slab on two posts built from plain parts. Every data
-- store call is pcalled and off the caller's thread; with no API access the columns say so.
-- Studio writes to its own stores (STUDIO_SUFFIX), so playtests never touch the live boards.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Props = require(ServerScriptService.Libraries.Props)
local ProgressService = require(script.Parent.ProgressService)
local SocialService = require(script.Parent.SocialService)

local TOP = 10
local REFRESH = 300
local STORE_VERSION = "v1"
local STUDIO_SUFFIX = if RunService:IsStudio() then "_studio" else ""
-- West of the Orders Board in the hub, facing the spawn (studs).
local BOARD_AT = CFrame.new(-72, 0, 0) * CFrame.Angles(0, math.rad(-90), 0)
local SLAB = Vector3.new(30, 12, 0.6)
local WOOD = Color3.fromRGB(176, 128, 86)
local FACE = Color3.fromRGB(34, 36, 48)
local GOLD = Color3.fromRGB(255, 214, 102)
local PALE = Color3.fromRGB(235, 235, 245)
local MUTED = Color3.fromRGB(170, 170, 188)

type Board = { id: string, title: string, value: (player: Player) -> number }
local BOARDS: { Board } = {
	{
		id = "Coins",
		title = "Coins earned",
		value = function(player)
			local progress = ProgressService.snapshot(player)
			return if progress then progress.stats.coinsEarned else 0
		end,
	},
	{
		id = "Harvests",
		title = "Crops harvested",
		value = function(player)
			local progress = ProgressService.snapshot(player)
			return if progress then progress.stats.cropsHarvested else 0
		end,
	},
	{ id = "Likes", title = "Garden likes", value = SocialService.likes },
}

local stores: { [string]: OrderedDataStore } = {}
local columns: { [string]: TextLabel } = {}
local names: { [number]: string } = {}
local started = false
local LeaderboardService = {}

local function storeFor(board: Board): OrderedDataStore?
	if stores[board.id] then
		return stores[board.id]
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(`Board_{board.id}_{STORE_VERSION}{STUDIO_SUFFIX}`)
	end)
	if ok then
		stores[board.id] = store
		return store
	end
	return nil
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	local ok, name = pcall(function()
		return if online then online.DisplayName else Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = if ok and typeof(name) == "string" then name else "A gardener"
	return names[userId]
end

-- "1,234,567", for a board's numbers.
local function grouped(value: number): string
	local text = string.reverse(tostring(math.floor(value)))
	return (string.reverse((string.gsub(text, "(%d%d%d)", "%1,"))):gsub("^,", ""))
end

local function label(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	color: Color3,
	bold: boolean
): TextLabel
	local created = Instance.new("TextLabel")
	created.BackgroundTransparency = 1
	created.Size = size
	created.Position = position
	created.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	created.Text = text
	created.TextColor3 = color
	created.TextScaled = true
	created.TextXAlignment = Enum.TextXAlignment.Left
	created.TextYAlignment = Enum.TextYAlignment.Top
	created.Parent = parent
	return created
end

-- The stand-in for a place without the prop; returns the slab the columns go on.
local function plainBoard(): BasePart
	local model = Instance.new("Model")
	model.Name = "Leaderboards"
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local created = Instance.new("Part")
		created.Name = name
		created.Size = size
		created.CFrame = BOARD_AT * CFrame.new(offset)
		created.Color = color
		created.Material = Enum.Material.SmoothPlastic
		created.Anchored = true
		created.Parent = model
		return created
	end
	for _, x in { -SLAB.X / 2 + 1, SLAB.X / 2 - 1 } do
		part("Post", Vector3.new(0.8, 4, 0.8), Vector3.new(x, 2, 0), WOOD)
	end
	part("Frame", SLAB + Vector3.new(0.8, 0.8, -0.2), Vector3.new(0, 4 + SLAB.Y / 2, 0), WOOD)
	local slab = part("Slab", SLAB, Vector3.new(0, 4 + SLAB.Y / 2, -0.15), FACE)
	model.Parent = workspace
	return slab
end

local function build(): ()
	local prop = Props.place("Leaderboards", BOARD_AT, workspace)
	local slab = (if prop then Props.part(prop, "Board") else nil) or plainBoard()
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.MaxDistance = 220
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.03, 0)
	padding.PaddingRight = UDim.new(0.03, 0)
	padding.PaddingTop = UDim.new(0.05, 0)
	padding.PaddingBottom = UDim.new(0.05, 0)
	padding.Parent = gui
	for index, board in BOARDS do
		local x = (index - 1) / #BOARDS
		local width = 1 / #BOARDS - 0.02
		label(gui, board.title, UDim2.fromScale(width, 0.1), UDim2.fromScale(x, 0), GOLD, true)
		local column = label(gui, "Loading...", UDim2.fromScale(width, 0.86), UDim2.fromScale(x, 0.14), PALE, false)
		column.TextScaled = false
		column.TextSize = 30
		column.TextWrapped = true
		column.RichText = true
		columns[board.id] = column
	end
	gui.Parent = slab
end

local function refresh(board: Board): ()
	local column = columns[board.id]
	local store = storeFor(board)
	local ok, page = pcall(function()
		assert(store, "no store")
		return store:GetSortedAsync(false, TOP):GetCurrentPage()
	end)
	if not ok then
		column.Text = `<font color="#{MUTED:ToHex()}">The boards open when the game is live.</font>`
		return
	end
	local lines = {}
	for rank, entry in page do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(lines, `{rank}. {nameOf(userId)}  <font color="#{GOLD:ToHex()}">{grouped(entry.value)}</font>`)
		end
	end
	column.Text = if #lines > 0
		then table.concat(lines, "\n")
		else `<font color="#{MUTED:ToHex()}">No gardens yet.</font>`
end

-- Writes a loaded garden's numbers to the boards; call it when the garden is saved. The values
-- are read now and the store calls run on their own thread.
function LeaderboardService.record(player: Player): ()
	LeaderboardService.init()
	local key = tostring(player.UserId)
	for _, board in BOARDS do
		local value = math.floor(board.value(player))
		if value > 0 then
			task.spawn(function()
				local store = storeFor(board)
				if store then
					pcall(function()
						store:UpdateAsync(key, function(old: number?): number?
							-- nil leaves the row as it is: a save file behind the player's best.
							return if old and old >= value then nil else value
						end)
					end)
				end
			end)
		end
	end
end

function LeaderboardService.init(): ()
	if started then
		return
	end
	started = true
	build()
	task.spawn(function()
		while true do
			for _, board in BOARDS do
				refresh(board)
			end
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService
