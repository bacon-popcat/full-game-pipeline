-- ResearchScreen: the Research window, a full-screen dark view of one upgrade tree drawn like a
-- seed's constellation. It lives in its own ScreenGui (StarterGui.ResearchView, authored) and,
-- while open, hides the HUD, player list and chat (HudVisibility), leaving the close button and
-- the running project's strip along the bottom. SideButtons.Research opens it from anywhere; the
-- screen animates itself through HubWindow's `animate`: opening ripples out from the middle (the
-- hub, then the rings, lines and tiles in order of distance), closing draws it back in, the
-- furthest first.
--
-- The tree is five-fold: a glowing hub sits in the middle of Research.Canvas, two orbits turning
-- round it, and each category (CATEGORIES) is a fan in its own fifth of the circle, Farming at the
-- top. A project's ring is how many projects lead to it in its category (faint guide rings mark
-- them); it hangs off its latest need, children continuing its line (Yield1 -> Yield2) run
-- straight on with its other branches either side, each branch in lanes of its own so no lines
-- cross, spread evenly across the fan. Each fan's first project sits on its middle line, joined
-- to the hub by a stem carrying the category's tag.
-- Tiles are round, cloned from Assets.UI.Research.Node; each need in the same category is joined
-- to it by a curved line of Assets.UI.Research.Link pieces, lit green once the need is done, with
-- motes of sap drifting outward along the lit ones.
--
-- What shows: each fan's first project, anything done or running, and whatever a finished
-- project leads to. One step further, what an unlocked one of those leads to shows as an
-- undiscovered "?" tile (nothing shows past a tile still locked by level). A
-- tile's ring says its state: green done, yellow can start (with a breathing halo), red locked,
-- blue running (with a bar), gold and pulsing ready to complete. Open and locked tiles show a
-- short coin-cost badge, red when the wallet falls short.
--
-- Pressing a tile selects it: the canvas glides it just left of the middle and Research.Info
-- stands beside it with its name, description, level and cost, a card per required item (its
-- picture with "x20 Wheat" under it, outlined and named in green once you carry enough), the
-- time behind an hourglass, and an Action button (Research, Complete...). An undiscovered tile
-- says what to research to find it. Pressing empty space puts the info away and centres the
-- tile; pressing the hub glides home. Hovering another tile shows the same in Research.Tooltip,
-- without the button. The canvas pans by dragging or the gamepad's right stick, and zooms with
-- the wheel, a two-finger pinch, or ButtonL2/ButtonR2. Pinching never also drags it.
--
-- Body.Active shows the running project's countdown and Cancel; once its timer runs out its
-- Complete button glows. Completing a project bursts its tile, then a glow runs down each line
-- out of it, drawing the line as it goes, and each undiscovered project it reaches turns over
-- into itself with a flash, a ring and sparks, its own next step appearing as "?" behind it;
-- FxController plays the world effect round the player. Whether a project can start is
-- Research.blocker's to say, with the wallet and inventory here; the server checks it all again
-- and answers with Notify and a fresh ResearchSync, which ends the wait.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local HudVisibility = require(Libraries.HudVisibility)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local ResearchClient = require(Libraries.ResearchClient)
local UI = require(Libraries.UI)

-- The item each line of projects shows, by the id's leading word (Belts1 -> Belts); crafting
-- projects show the recipe they unlock instead.
local ICONS: { [string]: string } = {
	Belts = "ConveyorBelt",
	Machines = "Mill",
	Reapers = "Harvester",
	Sprinklers = "Sprinkler",
	Yield = "Carrot",
	Growth = "WateringCan",
	Luck = "Carrot+Golden",
	Haggle = "ShippingBin",
	Learn = "Circuit",
	Seeds = "CarrotSeeds",
	Study = "Workbench",
	Axe = "Axe",
	Pick = "Pickaxe",
	Master = "Starfruit+Golden",
	-- The Recipe Books unlock bakes, not crafting recipes, so they have no recipe to show.
	RecipeBook = "PumpkinPie",
	Water = "WateringCan",
	Saver = "SeedPlanter",
	Lucky = "IronOre",
	Night = "Chest",
	Contract = "StrawberryJam",
	Notebook = "Gear",
	FarmMastery = "Pumpkin+Golden",
	AutoMastery = "ConveyorBelt",
	EconMastery = "ShippingBin",
	ToolMastery = "Pickaxe",
	CraftMastery = "Workbench",
}
-- The fans round the hub, clockwise from the top, each in its own colour: its tag, its tiles'
-- fill, a finished tile's ring, its lit lines, the unlock glow and the sap.
local CATEGORIES: { { name: string, color: Color3 } } = {
	{ name = "Farming", color = Color3.fromRGB(110, 220, 120) },
	{ name = "Automation", color = Color3.fromRGB(80, 190, 255) },
	{ name = "Economy", color = Color3.fromRGB(255, 196, 70) },
	{ name = "Tools", color = Color3.fromRGB(255, 120, 96) },
	{ name = "Crafting", color = Color3.fromRGB(196, 130, 255) },
}
local TINTS: { [string]: Color3 } = {}
for _, category in CATEGORIES do
	TINTS[category.name] = category.color
end
-- Pixels from the hub's middle to the first ring and between rings, and degrees between the
-- lines of a fan.
local FIRST_RING, RING_GAP, FAN_STEP = 260, 180, 18
-- The most degrees a fan's outermost lines may span; a fan with many lines draws them closer.
local FAN_SPREAD = 54
-- How dark a tile's fill is against its category's colour: still to research, and finished.
local FILL_DARK, FILL_DONE = 0.8, 0.55
-- The hub's diameter, and its two orbits' diameters, dots and turning speeds (degrees a second).
local HUB_SIZE = 100
local ORBIT_SIZE, ORBIT_DOTS, ORBIT_SPEED = 150, 24, 7
local OUTER_SIZE, OUTER_MOTES, OUTER_SPEED = 196, 3, -11
-- Pieces a curved line is drawn with.
local CURVE_PIECES = 8
local COLORS = {
	Done = Color3.fromRGB(120, 220, 110),
	Ready = Color3.fromRGB(255, 214, 110),
	Running = Color3.fromRGB(120, 180, 240),
	Open = Color3.fromRGB(240, 210, 90),
	Locked = Color3.fromRGB(196, 78, 78),
	Queued = Color3.fromRGB(176, 156, 245),
}
local HOT = Color3.fromRGB(255, 246, 222)
-- An undiscovered tile's ring, and how much fainter the line to it is than a known one.
local MYSTERY = Color3.fromRGB(78, 80, 96)
local MYSTERY_LINE = 0.55
-- Before the research time in the info.
local HOURGLASS = utf8.char(0x231B)
-- How far a locked tile's item and name fade.
local LOCKED_FADE = 0.55
-- The canvas: how quickly it glides to where it is going (per second), how far the wheel zooms,
-- and pixels left of the screen's middle the selected tile sits, leaving room for its info.
local GLIDE = 8
local NEAREST, FARTHEST = 0.4, 1.4
local SIT_LEFT = 210
-- Opening: the zoom the view opens at, and the share of it the canvas glides in from.
local OVERVIEW, OPEN_ZOOM = 0.72, 0.8
-- The ripple: seconds each piece takes to appear or go, and the spread of start times from the
-- middle to the furthest shown piece (out on opening, in on closing). Closing fades the backdrop
-- last, after this long.
local APPEAR, APPEAR_SPREAD = 0.34, 0.55
local VANISH, VANISH_SPREAD, BACKDROP_AFTER = 0.22, 0.32, 0.3
-- A tile's size as a share of its own as it starts to appear.
local APPEAR_SCALE = 0.3
-- Sap: a mote sets off down a lit line this often (seconds), at this speed (pixels a second),
-- with at most this many on the way.
local SAP_EVERY, SAP_SPEED, SAP_MOST = 0.3, 150, 12
-- Pixels a press may move and still count as a press rather than a drag.
local DRAG_START = 6
-- Screen pixels per second the right stick pans at full tilt, independent of zoom.
local PAN_SPEED = 500
-- Stick movement within this radius is ignored to avoid drift.
local STICK_DEAD_ZONE = 0.2
-- Each shoulder press multiplies or divides the canvas zoom by this much.
local GAMEPAD_ZOOM = 1.1
-- A pair of touches owns the gesture until fewer remain, keeping pinch separate from drag.
local PINCH_TOUCHES = 2
-- Coin-cost badge suffixes begin at these amounts.
local THOUSAND, MILLION = 1000, 1000000
-- Pixels between a tile and the info beside it, kept clear of the screen's edges, the close
-- button along the top and the running project's strip along the bottom.
local INFO_GAP, EDGE, TOP, BOTTOM = 14, 12, 56, 76
-- The completion burst: sparks, and how far they fly.
local SPARKS, SPARK_REACH = 16, 110
local SPARK_COLORS = { COLORS.Ready, COLORS.Done, HOT }
-- The unlock: seconds after the burst before the glow sets off, its speed along a line (pixels a
-- second, each line taking between the two times), and the sparks a revealed tile throws.
local GLOW_DELAY, GLOW_SPEED, GLOW_SHORTEST, GLOW_LONGEST = 0.35, 420, 0.3, 0.75
local REVEAL_SPARKS, REVEAL_REACH = 10, 80
local REVEAL_COLORS = { COLORS.Open, HOT, COLORS.Done }

type State = "Done" | "Ready" | "Running" | "Queued" | "Open" | "Locked"
-- Shown in full, undiscovered ("?"), or not drawn.
type Kind = "Shown" | "Mystery" | "Hidden"
type Node = {
	project: Research.Project,
	frame: GuiButton,
	-- the diamond (Node.Shape, turned 45 degrees) and its ring; the button itself is clear
	shape: GuiObject,
	tint: Color3,
	stroke: UIStroke?,
	scale: UIScale?,
	icon: ViewportFrame,
	name: TextLabel,
	cost: TextLabel?,
	progress: GuiObject?,
	fill: GuiObject?,
	mystery: GuiObject?,
	halo: Frame,
	haloStroke: UIStroke,
	centre: Vector2,
	state: State,
	kind: Kind,
}
type Piece = { holder: Frame, fill: Frame, from: Vector2, to: Vector2, length: number }
-- `need` is nil for a stem from the hub; it is lit, in its category's colour, once `lit` is done.
type Link = { need: string?, child: string, lit: string, pieces: { Piece }, length: number, color: Color3 }
type Panel = {
	frame: GuiObject,
	name: TextLabel,
	description: TextLabel,
	level: TextLabel,
	cost: TextLabel,
	needs: TextLabel,
	-- optional: the "Requirements" header, the row of item cards and the hourglass time
	requirements: GuiObject?,
	items: GuiObject?,
	time: TextLabel?,
	-- the cards on show, and for which project
	cards: { [string]: Card },
	cardsFor: string?,
}
type Card = { frame: GuiObject, icon: ViewportFrame?, stroke: UIStroke?, label: TextLabel? }
-- One transparency the ripple eases, and when (a share of the spread) its piece moves.
type FadeEntry = { instance: Instance, property: string, base: number, at: number }

local ResearchScreen = {}

local function shortCost(coins: number): string
	if coins < THOUSAND then
		return tostring(coins)
	end
	local divisor = if coins < MILLION then THOUSAND else MILLION
	local suffix = if coins < MILLION then "K" else "M"
	local amount = string.format("%.1f", coins / divisor):gsub("%.0$", "")
	return amount .. suffix
end

local function iconOf(project: Research.Project): string?
	local unlocks = Crafting.unlockedBy(project.id)
	if #unlocks > 0 then
		return unlocks[1].output
	end
	return ICONS[string.match(project.id, "^%a+") or ""]
end

-- "45 min", "1 h 30 min", "0:45".
local function duration(seconds: number): string
	if seconds < 60 then
		return Hud.time(seconds)
	end
	local minutes = math.ceil(seconds / 60)
	return if minutes >= 60
		then `{minutes // 60} h{if minutes % 60 > 0 then ` {minutes % 60} min` else ""}`
		else `{minutes} min`
end

-- "2:00", "1:30:00".
local function clock(seconds: number): string
	local left = math.max(0, math.ceil(seconds))
	if left >= 3600 then
		return string.format("%d:%02d:%02d", left // 3600, left % 3600 // 60, left % 60)
	end
	return string.format("%d:%02d", left // 60, left % 60)
end

local function countOf(itemId: string): number
	local count = 0
	for index = 1, Inventory.SLOT_COUNT do
		local stack = InventoryClient.getSlot(index)
		if stack and stack.itemId == itemId then
			count += stack.count
		end
	end
	return count
end

-- "20 Wood Planks, 2 Circuit", and whether this player carries them all.
local function itemsOf(project: Research.Project): (string, boolean)
	local names, enough = {}, true
	for itemId, count in project.items do
		table.insert(names, `{count} {Inventory.getItem(itemId).name}`)
		enough = enough and countOf(itemId) >= count
	end
	table.sort(names)
	return table.concat(names, ", "), enough
end

-- Whether the running project's timer has run out.
local function activeReady(): boolean
	local active = ResearchClient.get().active
	return active ~= nil and Research.isReady(active.endsAt, workspace:GetServerTimeNow())
end

local function stateOf(project: Research.Project): State
	local done = ResearchClient.done()
	local snapshot = ResearchClient.get()
	local active = snapshot.active
	if not project.ranked and done[project.id] then
		return "Done"
	elseif active and active.id == project.id then
		return if activeReady() then "Ready" else "Running"
	elseif table.find(snapshot.ready, project.id) then
		return "Ready"
	elseif (ResearchClient.lined()[project.id] or 0) > 0 then
		return "Queued"
	end
	local blocked = Research.blocker(project, done, EconomyClient.get().level, ResearchClient.lined())
	return if blocked then "Locked" else "Open"
end

-- What lining `project` up now costs, and the rank it buys (1 for unranked projects).
local function priceOf(project: Research.Project): (Research.Price, number)
	local rank = Research.nextRank(project, ResearchClient.get().ranks, ResearchClient.lined())
	return Research.price(project, rank), rank
end

-- Whether the line has no room for another project.
local function lineFull(): boolean
	local snapshot = ResearchClient.get()
	return not Research.fits(snapshot.active ~= nil, #snapshot.queue + #snapshot.ready, snapshot.room)
end

-- A project's place in the queue (1 is next), or nil.
local function queuePlace(id: string): number?
	for index, entry in ResearchClient.get().queue do
		if entry.id == id then
			return index
		end
	end
	return nil
end

-- The needs of `project` inside its own category (the ones its lines come from).
local function treeNeeds(project: Research.Project): { string }
	local needs = {}
	for _, id in project.needs do
		local need = Research.get(id)
		if need and need.category == project.category then
			table.insert(needs, id)
		end
	end
	return needs
end

-- Whether a project is in reach, given the finished ids: a fan's first project, a finished or
-- running one, or one a finished project in its category leads to.
local function inReach(project: Research.Project, done: { [string]: boolean }): boolean
	if done[project.id] or ResearchClient.lined()[project.id] or ResearchClient.rank(project.id) > 0 then
		return true
	end
	local needs = treeNeeds(project)
	if #needs == 0 then
		return true
	end
	for _, id in needs do
		if done[id] then
			return true
		end
	end
	return false
end

-- Where each project of `category` sits in its tree, as a ring and a line of the fan.
local function layout(category: string): { [string]: Vector2 }
	local order: { [string]: number } = {}
	local members: { Research.Project } = {}
	for index, project in Research.PROJECTS do
		if project.category == category then
			order[project.id] = index
			table.insert(members, project)
		end
	end
	local depth: { [string]: number } = {}
	local function depthOf(project: Research.Project): number
		local known = depth[project.id]
		if known then
			return known
		end
		local value = 0
		for _, id in project.needs do
			local need = Research.get(id)
			if need and order[id] then
				value = math.max(value, depthOf(need) + 1)
			end
		end
		depth[project.id] = value
		return value
	end
	local children: { [string]: { Research.Project } } = {}
	local roots: { Research.Project } = {}
	for _, project in members do
		local parent: string? = nil
		for _, id in project.needs do
			local need = Research.get(id)
			if need and order[id] and (not parent or depthOf(need) > depth[parent]) then
				parent = id
			end
		end
		depthOf(project)
		if parent then
			children[parent] = children[parent] or {}
			table.insert(children[parent], project)
		else
			table.insert(roots, project)
		end
	end
	local function line(id: string): string
		return string.match(id, "^%a+") or id
	end
	for id, list in children do
		table.sort(list, function(a, b)
			local aLine, bLine = line(a.id) == line(id), line(b.id) == line(id)
			if aLine ~= bLine then
				return aLine
			end
			return order[a.id] < order[b.id]
		end)
	end
	-- Lines are numbered across the fan, each branch's lines all together, so no two lines cross.
	-- The line a project continues (its first child) sits in the middle of its branches: half of
	-- the others before it, half after.
	local rows: { [string]: number } = {}
	local nextRow = 0
	local function place(project: Research.Project)
		local list = children[project.id]
		if not list then
			rows[project.id] = nextRow
			nextRow += 1
			return
		end
		local before = (#list - 1) // 2
		for index = 2, before + 1 do
			place(list[index])
		end
		place(list[1])
		for index = before + 2, #list do
			place(list[index])
		end
		rows[project.id] = rows[list[1].id]
	end
	for _, root in roots do
		place(root)
	end
	local cells: { [string]: Vector2 } = {}
	for _, project in members do
		cells[project.id] = Vector2.new(depth[project.id], rows[project.id])
	end
	return cells
end

local function polar(angle: number, radius: number): Vector2
	return Vector2.new(math.cos(angle), math.sin(angle)) * radius
end

local function panelOf(frame: Instance?): Panel?
	if not frame or not frame:IsA("GuiObject") then
		return nil
	end
	local name = Hud.find(frame, "Name", "TextLabel")
	local description = Hud.find(frame, "Description", "TextLabel")
	local level = Hud.find(frame, "Level", "TextLabel")
	local cost = Hud.find(frame, "Cost", "TextLabel")
	local needs = Hud.find(frame, "Needs", "TextLabel")
	if
		not name
		or not name:IsA("TextLabel")
		or not description
		or not description:IsA("TextLabel")
		or not level
		or not level:IsA("TextLabel")
		or not cost
		or not cost:IsA("TextLabel")
		or not needs
		or not needs:IsA("TextLabel")
	then
		return nil
	end
	local requirements = frame:FindFirstChild("Requirements")
	local items = frame:FindFirstChild("Items")
	local time = frame:FindFirstChild("Time")
	return {
		frame = frame,
		name = name,
		description = description,
		level = level,
		cost = cost,
		needs = needs,
		requirements = if requirements and requirements:IsA("GuiObject") then requirements else nil,
		items = if items and items:IsA("GuiObject") then items else nil,
		time = if time and time:IsA("TextLabel") then time else nil,
		cards = {},
	}
end

-- Runs `step(alpha)` every frame for `seconds` (alpha 0 to 1), then `done`. Returns a stop.
local function animate(seconds: number, step: (number) -> (), done: (() -> ())?): () -> ()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / seconds)
		step(alpha)
		if alpha >= 1 then
			connection:Disconnect()
			if done then
				done()
			end
		end
	end)
	return function()
		connection:Disconnect()
	end
end

-- Whether a screen point lies on a shown GuiObject.
local function over(object: GuiObject, point: Vector2): boolean
	if not object.Visible then
		return false
	end
	local low, size = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= low.X and point.Y >= low.Y and point.X <= low.X + size.X and point.Y <= low.Y + size.Y
end

-- A round frame (a disc, or a ring when `stroke` is given) centred at `at` under `parent`.
local function circle(
	parent: Instance,
	at: UDim2,
	size: UDim2,
	color: Color3,
	transparency: number,
	zIndex: number,
	stroke: number?
): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at
	frame.Size = size
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = if stroke then 1 else transparency
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	if stroke then
		local line = Instance.new("UIStroke")
		line.Color = color
		line.Thickness = stroke
		line.Transparency = transparency
		line.Parent = frame
	end
	frame.Parent = parent
	return frame
end

local function backOut(alpha: number): number
	local s = 1.6
	local t = alpha - 1
	return 1 + (s + 1) * t * t * t + s * t * t
end

function ResearchScreen.init(hud: ScreenGui)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local view = playerGui:WaitForChild("ResearchView", 10)
	if not view or not view:IsA("ScreenGui") then
		warn("ResearchScreen: PlayerGui.ResearchView must be an authored ScreenGui")
		return
	end
	local root = Hud.find(view, "Research", "Frame")
	local canvas = Hud.find(view, "Research.Canvas", "Frame")
	local zoom = Hud.find(view, "Research.Canvas.UIScale", "UIScale")
	local linkLayer = Hud.find(view, "Research.Canvas.Links", "Frame")
	local nodeLayer = Hud.find(view, "Research.Canvas.Nodes", "Frame")
	local info = panelOf(Hud.find(view, "Research.Info", "Frame"))
	local tooltip = panelOf(Hud.find(view, "Research.Tooltip", "Frame"))
	local action = Hud.find(view, "Research.Info.Action", "TextButton")
	local actionLabel = Hud.find(view, "Research.Info.Action.Label", "TextLabel")
	local activeStrip = Hud.find(view, "Research.Body.Active", "Frame")
	local activeText = Hud.find(view, "Research.Body.Active.Text", "TextLabel")
	local activeTime = Hud.find(view, "Research.Body.Active.Time", "TextLabel")
	local fill = Hud.find(view, "Research.Body.Active.Bar.Fill", "Frame")
	local cancel = Hud.find(view, "Research.Body.Active.Cancel", "TextButton")
	local completeButton = Hud.find(view, "Research.Body.Active.Complete", "TextButton")
	local nodeTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Research.Node", "GuiButton")
	local linkTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Research.Link", "Frame")
	-- Optional: without it the required items are listed as words in Needs.
	local requirementAsset: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in { "UI", "Research", "Requirement" } do
		requirementAsset = if requirementAsset then requirementAsset:FindFirstChild(name) else nil
	end
	local requirementTemplate: GuiObject? = if requirementAsset and requirementAsset:IsA("GuiObject")
		then requirementAsset
		else nil
	-- A card's outline and words while you are short, from the template.
	local cardStrokeColor, cardTextColor = Color3.fromRGB(205, 205, 220), Color3.fromRGB(230, 230, 235)
	if requirementTemplate then
		local box = requirementTemplate:FindFirstChild("Box")
		local outline = (box or requirementTemplate):FindFirstChildOfClass("UIStroke")
		local label = requirementTemplate:FindFirstChild("Label")
		cardStrokeColor = if outline then outline.Color else cardStrokeColor
		cardTextColor = if label and label:IsA("TextLabel") then label.TextColor3 else cardTextColor
	end
	if
		not root
		or not root:IsA("Frame")
		or not canvas
		or not canvas:IsA("Frame")
		or not zoom
		or not zoom:IsA("UIScale")
		or not linkLayer
		or not linkLayer:IsA("Frame")
		or not nodeLayer
		or not nodeLayer:IsA("Frame")
		or not info
		or not tooltip
		or not action
		or not action:IsA("TextButton")
		or not actionLabel
		or not actionLabel:IsA("TextLabel")
		or not activeStrip
		or not activeStrip:IsA("Frame")
		or not activeText
		or not activeText:IsA("TextLabel")
		or not activeTime
		or not activeTime:IsA("TextLabel")
		or not fill
		or not fill:IsA("Frame")
		or not cancel
		or not cancel:IsA("TextButton")
		or not completeButton
		or not completeButton:IsA("TextButton")
		or not nodeTemplate
		or not nodeTemplate:IsA("GuiButton")
		or not linkTemplate
		or not linkTemplate:IsA("Frame")
	then
		return
	end
	local trove = Trove.new()
	local treeTrove = Trove.new()
	local nodes: { [string]: Node } = {}
	local links: { Link } = {}
	local hub: GuiButton? = nil
	local hubStroke: UIStroke? = nil
	local orbits: { { frame: GuiObject, speed: number } } = {}
	-- What sits on the canvas besides tiles and lines (guide rings, the hub, its orbits, tags),
	-- with how far from the middle each is, for the ripple.
	local distanceOf: { [Instance]: number } = {}
	local selected: string? = nil
	local hovered: string? = nil
	local pending = false
	-- What the Action button sends for the selected project ("Start", "Cancel", "Complete").
	local actionKind: string? = nil
	local shown = false
	-- Projects whose tile waits for the unlock glow to reach it, and lines it is running down.
	local revealing: { [string]: boolean } = {}
	local glowing: { [Link]: boolean } = {}
	-- Baselines, captured from what is authored.
	local nodeSize = nodeTemplate.Size
	local tileRadius = nodeSize.X.Offset / 2
	-- A diamond's fill before it is tinted, from the template (dark when it has none).
	local templateShape = nodeTemplate:FindFirstChild("Shape")
	local nodeColor = if templateShape and templateShape:IsA("GuiObject")
		then templateShape.BackgroundColor3
		else Color3.fromRGB(26, 28, 36)
	local templateCost = nodeTemplate:FindFirstChild("Cost")
	local nodeCostColor = if templateCost and templateCost:IsA("TextLabel") then templateCost.TextColor3 else nil
	local templateStroke = nodeTemplate:FindFirstChildOfClass("UIStroke")
	local strokeThickness = if templateStroke then templateStroke.Thickness else 3
	local linkTransparency = linkTemplate.BackgroundTransparency
	local linkThickness = math.max(1, linkTemplate.Size.Y.Offset)
	local actionLook = { transparency = action.BackgroundTransparency, text = actionLabel.TextTransparency }
	local costColor = info.cost.TextColor3
	local levelColor = info.level.TextColor3
	local completeStroke = completeButton:FindFirstChildOfClass("UIStroke")
	local completeThickness = if completeStroke then completeStroke.Thickness else 1
	-- Clicks on the info panel stay on it rather than reaching the background below.
	info.frame.Active = true
	-- The finished ids at the last sync, so a newly completed one can burst.
	local lastDone: { [string]: boolean }? = nil
	local lastRanks: { [string]: number }? = nil
	-- The canvas point the screen centres on, where it is going and where it is, and its zoom.
	local focus, shownFocus = Vector2.zero, Vector2.zero
	local scale = zoom.Scale
	local shownScale = scale
	local press: Vector2? = nil
	local dragging = false
	local touches: { InputObject } = {}
	local pinchDistance: number? = nil
	local saps: { Frame } = {}
	local sapClock = 0

	-- The ripple. Every transparency under the view is taken from where it stands and eased to
	-- clear and back, each piece of the tree at its own moment by its distance from the middle:
	-- out from the hub on opening, in from the edge on closing, the backdrop and strip first in and
	-- last out. Tiles also grow in with a bounce and shrink away. The tiles' item pictures are
	-- ViewportFrames, faded the same way.
	local fadeEntries: { FadeEntry } = {}
	local fadeScales: { { scale: UIScale, at: number } } = {}
	local stopFade: (() -> ())? = nil
	local fadeOpening = true
	local fadeClock = 1
	local FADED = {
		GuiObject = { "BackgroundTransparency" },
		TextLabel = { "TextTransparency", "TextStrokeTransparency" },
		TextButton = { "TextTransparency", "TextStrokeTransparency" },
		TextBox = { "TextTransparency", "TextStrokeTransparency" },
		ImageLabel = { "ImageTransparency" },
		ImageButton = { "ImageTransparency" },
		ViewportFrame = { "ImageTransparency" },
		UIStroke = { "Transparency" },
	}
	-- Where on the canvas `instance` belongs (its tile, line piece or decoration), or nil for the
	-- backdrop and panels.
	local function placeOf(instance: Instance): number?
		local current: Instance? = instance
		while current and current ~= root do
			local known = distanceOf[current]
			if known then
				return known
			end
			current = current.Parent
		end
		return nil
	end
	local function capture()
		table.clear(fadeEntries)
		table.clear(fadeScales)
		local farthest = 1
		for instance, distance in distanceOf do
			if instance:IsA("GuiObject") and instance.Visible then
				farthest = math.max(farthest, distance)
			end
		end
		local function add(instance: Instance)
			local distance = placeOf(instance)
			local at = if distance then math.clamp(distance / farthest, 0, 1) else -1
			for className, properties in FADED do
				if instance:IsA(className) then
					for _, property in properties do
						table.insert(
							fadeEntries,
							{ instance = instance, property = property, base = (instance :: any)[property], at = at }
						)
					end
				end
			end
		end
		add(root)
		for _, descendant in root:GetDescendants() do
			add(descendant)
		end
		for _, node in nodes do
			if node.scale and node.frame.Visible then
				table.insert(
					fadeScales,
					{ scale = node.scale, at = math.clamp(node.centre.Magnitude / farthest, 0, 1) }
				)
			end
		end
	end
	-- How far gone (0 shown, 1 clear) a piece at `at` is, `elapsed` seconds into the ripple.
	local function goneAt(at: number, elapsed: number): number
		if fadeOpening then
			local start = if at < 0 then 0 else 0.05 + at * APPEAR_SPREAD
			local alpha = math.clamp((elapsed - start) / APPEAR, 0, 1)
			return 1 - (1 - (1 - alpha) ^ 2)
		end
		local start = if at < 0 then BACKDROP_AFTER else (1 - at) * VANISH_SPREAD
		local alpha = math.clamp((elapsed - start) / VANISH, 0, 1)
		return alpha * alpha
	end
	local function applyFade(elapsed: number)
		for _, entry in fadeEntries do
			local target: any = entry.instance
			if target.Parent then
				target[entry.property] = entry.base + (1 - entry.base) * goneAt(entry.at, elapsed)
			end
		end
		for _, entry in fadeScales do
			local gone = goneAt(entry.at, elapsed)
			entry.scale.Scale = if fadeOpening
				then APPEAR_SCALE + (1 - APPEAR_SCALE) * backOut(1 - gone)
				else 1 - (1 - APPEAR_SCALE) * gone
		end
	end
	local function restoreFade()
		for _, entry in fadeEntries do
			if entry.instance.Parent then
				(entry.instance :: any)[entry.property] = entry.base
			end
		end
		for _, entry in fadeScales do
			entry.scale.Scale = 1
		end
		table.clear(fadeEntries)
		table.clear(fadeScales)
	end

	-- The required items as cards: each item's picture in a box with "x20 Wheat" under it, the
	-- outline and words turning green once you carry enough. Rebuilt only when the project
	-- changes. Returns whether the panel has cards (else the items go in Needs as words).
	local function showCards(panel: Panel, project: Research.Project, wanted: boolean): boolean
		local row = panel.items
		local template = requirementTemplate
		if not row or not template then
			return false
		end
		local any = next(project.items) ~= nil
		row.Visible = wanted and any
		if panel.requirements then
			panel.requirements.Visible = wanted and any
		end
		if not (wanted and any) then
			return true
		end
		if panel.cardsFor ~= project.id then
			for _, card in panel.cards do
				if card.icon then
					ItemIcon.clear(card.icon)
				end
				card.frame:Destroy()
			end
			table.clear(panel.cards)
			panel.cardsFor = project.id
			local ids = {}
			for itemId in project.items do
				table.insert(ids, itemId)
			end
			table.sort(ids)
			for order, itemId in ids do
				local frame = template:Clone()
				frame.Name = itemId
				frame.LayoutOrder = order
				local icon = frame:FindFirstChild("Icon", true)
				local box = frame:FindFirstChild("Box")
				local label = frame:FindFirstChild("Label")
				local card: Card = {
					frame = frame,
					icon = if icon and icon:IsA("ViewportFrame") then icon else nil,
					stroke = (box or frame):FindFirstChildOfClass("UIStroke"),
					label = if label and label:IsA("TextLabel") then label else nil,
				}
				if card.icon then
					ItemIcon.show(card.icon, itemId)
				end
				if card.label then
					card.label.Text = `x{project.items[itemId]} {Inventory.getItem(itemId).name}`
				end
				frame.Parent = row
				panel.cards[itemId] = card
			end
		end
		for itemId, card in panel.cards do
			local enough = countOf(itemId) >= (project.items[itemId] or 0)
			if card.stroke then
				card.stroke.Color = if enough then COLORS.Done else cardStrokeColor
			end
			if card.label then
				card.label.TextColor3 = if enough then COLORS.Done else cardTextColor
			end
		end
		return true
	end

	-- An undiscovered project's info: what to research to find it, and nothing else.
	local function fillMystery(panel: Panel, project: Research.Project)
		local names = {}
		for _, id in treeNeeds(project) do
			local need = Research.get(id)
			if need then
				table.insert(names, need.name)
			end
		end
		showCards(panel, project, false)
		panel.name.Text = "???"
		panel.name.TextColor3 = MYSTERY:Lerp(Color3.new(1, 1, 1), 0.5)
		panel.description.Text = `Research {table.concat(names, " and ")} to discover it.`
		panel.level.Text = "Undiscovered"
		panel.level.TextColor3 = levelColor
		panel.cost.Visible = false
		if panel.time then
			panel.time.Visible = false
		end
		panel.needs.Visible = false
	end

	local function fillPanel(panel: Panel, project: Research.Project)
		local node = nodes[project.id]
		if node and node.kind == "Mystery" then
			fillMystery(panel, project)
			return
		end
		local economy = EconomyClient.get()
		local snapshot = ResearchClient.get()
		local done = ResearchClient.done()
		local blocked = Research.blocker(project, done, economy.level, ResearchClient.lined(), lineFull())
		local items, hasItems = itemsOf(project)
		local state = stateOf(project)
		local price, rank = priceOf(project)
		-- A ranked project can be lined up again while a rank of it runs (its button then says
		-- Queue); a queued or finished one's button is Remove or Complete, so no price shows.
		local buying = state == "Open"
			or state == "Locked"
			or (project.ranked == true and state == "Running" and blocked == nil)
		local cards = showCards(panel, project, buying)
		local ranks = ResearchClient.rank(project.id)
		panel.name.Text = if project.ranked and ranks > 0 then `{project.name} {ranks}` else project.name
		panel.name.TextColor3 = COLORS[state]
		panel.description.Text = if project.ranked
			then `{project.description}\nRanks so far: {ranks}. Next: rank {rank}.`
			else project.description
		panel.level.Text = `Lv. {project.level}  -  {if state == "Done"
			then "Researched"
			elseif state == "Ready" then "Ready to complete"
			elseif state == "Running" then "Researching"
			elseif state == "Queued" then `Queued ({if queuePlace(project.id) == 1
				then "next"
				else `#{queuePlace(project.id) or 1}`})`
			elseif state == "Locked" then "Locked"
			else "Can research"}`
		panel.level.TextColor3 = if economy.level < project.level then COLORS.Locked else levelColor
		panel.cost.Visible = buying
		panel.cost.Text = `{Hud.number(price.coins)} coins`
		panel.cost.TextColor3 = if economy.coins >= price.coins then costColor else COLORS.Locked
		local lines = {}
		local seconds = Research.duration(price.seconds, snapshot.bonuses.researchSpeed or 0)
		local place = queuePlace(project.id)
		if state == "Running" then
			local active = snapshot.active
			seconds = if active then math.max(0, active.endsAt - workspace:GetServerTimeNow()) else 0
		elseif state == "Queued" and place then
			seconds = snapshot.queue[place].seconds
		end
		if panel.time then
			panel.time.Visible = state ~= "Done" and state ~= "Ready"
			panel.time.Text = `{HOURGLASS} {clock(seconds)}{if state == "Running" then " left" else ""}`
		end
		if state == "Ready" then
			table.insert(lines, "Finished! Complete it to get its bonus.")
		elseif state == "Running" then
			if not panel.time then
				table.insert(lines, `{Hud.time(seconds)} left`)
			end
		elseif state == "Queued" then
			table.insert(lines, "Paid for. It starts when the projects ahead of it finish.")
		elseif state ~= "Done" then
			if not panel.time then
				table.insert(lines, `Takes {duration(seconds)}`)
			end
			if items ~= "" and not cards then
				table.insert(lines, `Needs {items}{if hasItems then "" else " (you don't have them)"}`)
			end
			if blocked then
				table.insert(lines, blocked)
			elseif snapshot.active then
				table.insert(lines, "Joins the queue and starts when the projects ahead of it finish.")
			end
		end
		panel.needs.Text = table.concat(lines, "\n")
		panel.needs.Visible = #lines > 0
	end

	local function renderAction()
		local project = if selected then Research.get(selected) else nil
		if not project then
			return
		end
		local economy = EconomyClient.get()
		local snapshot = ResearchClient.get()
		local done = ResearchClient.done()
		local full = lineFull()
		-- What stops it apart from a full line, which has its own label.
		local blocked = Research.blocker(project, done, economy.level, ResearchClient.lined())
		local _, hasItems = itemsOf(project)
		local enoughCoins = economy.coins >= priceOf(project).coins
		local state = stateOf(project)
		local node = nodes[project.id]
		local mystery = node ~= nil and node.kind == "Mystery"
		local label: string
		actionKind = nil
		if pending then
			label = "..."
		elseif mystery then
			label = "Undiscovered"
		elseif state == "Done" then
			label = "Done"
		elseif state == "Ready" then
			label, actionKind = "Complete", "Complete"
		elseif state == "Queued" then
			label, actionKind = "Remove", "Cancel"
		elseif state == "Running" and not project.ranked then
			label, actionKind = "Cancel", "Cancel"
		elseif blocked then
			label = if state == "Running" then "Running" else "Locked"
		elseif full then
			label = "Queue full"
		elseif not enoughCoins then
			label = "Need coins"
		elseif not hasItems then
			label = "Need items"
		else
			label, actionKind = if snapshot.active then "Queue" else "Research", "Start"
		end
		local enabled = actionKind ~= nil
		action.Active = enabled
		action.Selectable = enabled
		action.BackgroundTransparency = if enabled
			then actionLook.transparency
			else actionLook.transparency + (1 - actionLook.transparency) * 0.5
		actionLabel.TextTransparency = if enabled
			then actionLook.text
			else actionLook.text + (1 - actionLook.text) * 0.5
		actionLabel.Text = label
	end

	-- Every tile's kind: in reach, undiscovered, or neither. Each tile in reach that isn't locked
	-- shows one undiscovered "?" past it, the nearest (lowest level) of what it leads to, as a hint
	-- that there is more; nothing shows past a tile still locked by level, so the tree grows as the
	-- player does. A tile the unlock glow has yet to reach stays hidden until it arrives.
	local function kinds(done: { [string]: boolean }): { [string]: Kind }
		local result: { [string]: Kind } = {}
		for id, node in nodes do
			result[id] = if not revealing[id] and inReach(node.project, done) then "Shown" else "Hidden"
		end
		local nearest: { [string]: Research.Project } = {}
		for id, node in nodes do
			if result[id] == "Hidden" then
				local project = node.project
				for _, need in treeNeeds(project) do
					local best = nearest[need]
					if
						result[need] == "Shown"
						and stateOf(nodes[need].project) ~= "Locked"
						and (
							not best
							or project.level < best.level
							or (project.level == best.level and project.id < best.id)
						)
					then
						nearest[need] = project
					end
				end
			end
		end
		for _, project in nearest do
			result[project.id] = "Mystery"
		end
		return result
	end

	-- A tile coming into view on its own (an undiscovered one past a new unlock): it grows in.
	local function appear(node: Node)
		local tileScale = node.scale
		if not tileScale or GuiService.ReducedMotionEnabled or stopFade then
			return
		end
		tileScale.Scale = 0
		task.delay(0.15, function()
			if node.frame.Parent then
				TweenService:Create(tileScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end)
	end

	local function paintTiles()
		local done = ResearchClient.done()
		local coins = EconomyClient.get().coins
		local kind = kinds(done)
		for id, node in nodes do
			local state = stateOf(node.project)
			local was = node.kind
			node.state = state
			node.kind = kind[id]
			local mystery = node.kind == "Mystery"
			node.frame.Visible = node.kind ~= "Hidden"
			if was == "Hidden" and node.kind == "Mystery" and shown then
				appear(node)
			end
			if node.stroke then
				node.stroke.Color = if mystery then MYSTERY elseif state == "Done" then node.tint else COLORS[state]
				node.stroke.Thickness = if mystery then 2 else strokeThickness
			end
			local ranks = ResearchClient.rank(id)
			local filled = state == "Done" or ranks > 0
			node.shape.BackgroundColor3 = if mystery
				then nodeColor:Lerp(Color3.new(0, 0, 0), 0.4)
				else node.tint:Lerp(Color3.new(0, 0, 0), if filled then FILL_DONE else FILL_DARK)
			node.icon.Visible = not mystery
			node.icon.ImageTransparency = if state == "Locked" then LOCKED_FADE else 0
			node.name.Visible = not mystery
			node.name.Text = if node.project.ranked and ranks > 0
				then `{node.project.name} {ranks}`
				else node.project.name
			node.name.TextTransparency = if state == "Locked" then LOCKED_FADE else 0
			if node.mystery then
				node.mystery.Visible = mystery
			end
			if node.cost then
				-- the coin cost while it can be bought; its place while queued
				local place = if state == "Queued" then queuePlace(id) else nil
				local price = priceOf(node.project).coins
				node.cost.Visible = not mystery and (state == "Open" or state == "Locked" or place ~= nil)
				node.cost.Text = if place then (if place == 1 then "Next" else `#{place}`) else shortCost(price)
				if nodeCostColor then
					node.cost.TextColor3 = if place
						then COLORS.Queued
						elseif coins < price then COLORS.Locked
						else nodeCostColor
				end
			end
			if node.progress then
				node.progress.Visible = not mystery and (state == "Running" or state == "Ready")
				if node.fill and state == "Ready" then
					node.fill.Size = UDim2.fromScale(1, 1)
				end
			end
			node.halo.Visible = not mystery and (state == "Open" or state == "Ready")
			node.haloStroke.Color = if state == "Ready" then COLORS.Ready else COLORS.Open
		end
		for _, link in links do
			if glowing[link] then
				continue
			end
			local childKind = kind[link.child]
			local needKind = if link.need then kind[link.need] else "Shown"
			local shows = childKind ~= "Hidden" and needKind ~= "Hidden"
			local lit = done[link.lit] == true
			local faint = if childKind == "Mystery"
				then linkTransparency + (1 - linkTransparency) * MYSTERY_LINE
				else linkTransparency
			for _, piece in link.pieces do
				piece.holder.Visible = shows
				piece.holder.BackgroundTransparency = faint
				piece.fill.Size = UDim2.fromScale(if lit then 1 else 0, 1)
			end
		end
		if selected and not (nodes[selected] and nodes[selected].frame.Visible) then
			selected = nil
		end
		if hovered and not (nodes[hovered] and nodes[hovered].frame.Visible) then
			hovered = nil
		end
	end

	local function render()
		paintTiles()
		local selectedProject = if selected then Research.get(selected) else nil
		if selectedProject then
			fillPanel(info, selectedProject)
		end
		local hoveredProject = if hovered and hovered ~= selected then Research.get(hovered) else nil
		if hoveredProject then
			fillPanel(tooltip, hoveredProject)
		end
		renderAction()
		local snapshot = ResearchClient.get()
		local active = snapshot.active
		local ready = activeReady() or #snapshot.ready > 0
		cancel.Visible = active ~= nil and not activeReady() and #snapshot.ready == 0
		cancel.Active = cancel.Visible and not pending
		completeButton.Visible = ready
		completeButton.Active = ready and not pending
		if stopFade then
			-- mid-ripple, what was just painted stays where the ripple has it (its end paints again)
			applyFade(fadeClock)
		end
	end

	-- The canvas point that puts `centre` at the screen's middle, or left of it with room for the
	-- info beside it.
	local function focusOn(centre: Vector2, beside: boolean)
		focus = centre + Vector2.new(if beside then SIT_LEFT else 0, 0) / scale
		if GuiService.ReducedMotionEnabled then
			shownFocus = focus
		end
	end

	local function selectProject(id: string, snap: boolean?)
		local node = nodes[id]
		if not node or not node.frame.Visible then
			return
		end
		selected = id
		focusOn(node.centre, true)
		if snap then
			shownFocus = focus
		end
		render()
	end

	local function deselect()
		if not selected then
			return
		end
		local node = nodes[selected]
		selected = nil
		if node then
			focusOn(node.centre, false)
		end
		render()
	end

	-- A straight piece of line on the canvas from `a` to `b`: a dim line turned to run along it,
	-- holding the lit fill that grows from `a`.
	local function segment(a: Vector2, b: Vector2, distance: number): Piece
		local holder = linkTemplate:Clone()
		local delta = b - a
		local length = delta.Magnitude
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		holder.Size = UDim2.fromOffset(length + linkThickness, linkThickness)
		holder.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		local lit = Instance.new("Frame")
		lit.Name = "Lit"
		lit.BorderSizePixel = 0
		lit.BackgroundColor3 = COLORS.Done
		lit.Size = UDim2.fromScale(0, 1)
		lit.ZIndex = holder.ZIndex
		lit.Parent = holder
		holder.Parent = linkLayer
		distanceOf[holder] = distance
		treeTrove:Add(holder)
		return { holder = holder, fill = lit, from = a, to = b, length = length }
	end

	local function addLink(
		need: string?,
		child: string,
		lit: string,
		points: { Vector2 },
		distance: number,
		color: Color3
	)
		local pieces = {}
		local length = 0
		for index = 1, #points - 1 do
			local piece = segment(points[index], points[index + 1], distance)
			piece.fill.BackgroundColor3 = color
			table.insert(pieces, piece)
			length += piece.length
		end
		table.insert(links, { need = need, child = child, lit = lit, pieces = pieces, length = length, color = color })
	end

	-- The curve from one tile to the next: it leaves the parent heading for the child's line and
	-- flows into the child along it, trimmed to the tiles' rims. A child on the same line gets a
	-- straight piece.
	local function curve(from: Vector2, to: Vector2, fromRadius: number): { Vector2 }
		local toAngle = math.atan2(to.Y, to.X)
		local fromAngle = math.atan2(from.Y, from.X)
		if math.abs(fromAngle - toAngle) < 1e-3 or from.Magnitude < 1 then
			local way = (to - from).Unit
			return { from + way * fromRadius, to - way * tileRadius }
		end
		local control = polar(toAngle, (from.Magnitude + to.Magnitude) / 2)
		local samples = {}
		local steps = CURVE_PIECES * 4
		for index = 0, steps do
			local t = index / steps
			local point = from:Lerp(control, t):Lerp(control:Lerp(to, t), t)
			if (point - from).Magnitude >= fromRadius and (point - to).Magnitude >= tileRadius then
				table.insert(samples, point)
			end
		end
		local points = {}
		for index = 1, #samples, 4 do
			table.insert(points, samples[index])
		end
		if samples[#samples] ~= points[#points] then
			table.insert(points, samples[#samples])
		end
		return points
	end

	-- The middle of the canvas: faint guide rings, the hub with the side button's flask, and two
	-- orbits turning round it. Pressing the hub glides home.
	local function buildHub(rings: number)
		for index = 0, rings do
			local radius = FIRST_RING + index * RING_GAP
			local guide = circle(
				linkLayer,
				UDim2.fromOffset(0, 0),
				UDim2.fromOffset(radius * 2, radius * 2),
				Color3.fromRGB(150, 156, 190),
				0.9 + index * 0.012,
				0,
				1
			)
			guide.Name = "Ring" .. index
			distanceOf[guide] = radius
			treeTrove:Add(guide)
		end
		local glow = circle(
			nodeLayer,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(HUB_SIZE * 1.5, HUB_SIZE * 1.5),
			COLORS.Ready,
			0.9,
			nodeTemplate.ZIndex
		)
		glow.Name = "HubGlow"
		distanceOf[glow] = 0
		treeTrove:Add(glow)
		local orbit = Instance.new("Frame")
		orbit.Name = "Orbit"
		orbit.AnchorPoint = Vector2.new(0.5, 0.5)
		orbit.Size = UDim2.fromOffset(ORBIT_SIZE, ORBIT_SIZE)
		orbit.BackgroundTransparency = 1
		for index = 1, ORBIT_DOTS do
			local angle = index / ORBIT_DOTS * math.pi * 2
			local spot = polar(angle, ORBIT_SIZE / 2)
			circle(
				orbit,
				UDim2.new(0.5, spot.X, 0.5, spot.Y),
				UDim2.fromOffset(if index % 6 == 0 then 6 else 3, if index % 6 == 0 then 6 else 3),
				COLORS.Ready,
				if index % 6 == 0 then 0.1 else 0.55,
				nodeTemplate.ZIndex
			)
		end
		orbit.Parent = nodeLayer
		distanceOf[orbit] = 0
		treeTrove:Add(orbit)
		local outer = circle(
			nodeLayer,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(OUTER_SIZE, OUTER_SIZE),
			COLORS.Ready,
			0.82,
			nodeTemplate.ZIndex,
			1
		)
		outer.Name = "OuterOrbit"
		for index = 1, OUTER_MOTES do
			local spot = polar(index / OUTER_MOTES * math.pi * 2, OUTER_SIZE / 2)
			circle(outer, UDim2.new(0.5, spot.X, 0.5, spot.Y), UDim2.fromOffset(8, 8), HOT, 0, nodeTemplate.ZIndex)
		end
		distanceOf[outer] = 0
		treeTrove:Add(outer)
		orbits = { { frame = orbit, speed = ORBIT_SPEED }, { frame = outer, speed = OUTER_SPEED } }

		local tile = Instance.new("TextButton")
		tile.Name = "Hub"
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Size = UDim2.fromOffset(HUB_SIZE, HUB_SIZE)
		tile.BackgroundColor3 = nodeColor
		tile.BorderSizePixel = 0
		tile.ZIndex = nodeTemplate.ZIndex + 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = tile
		local shade = Instance.new("UIGradient")
		shade.Rotation = 90
		shade.Color = ColorSequence.new(Color3.fromRGB(255, 240, 210), Color3.fromRGB(140, 120, 90))
		shade.Parent = tile
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.Ready
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = tile
		hubStroke = stroke
		local flask = hud:FindFirstChild("SideButtons")
		flask = if flask then flask:FindFirstChild("Research") else nil
		flask = if flask then flask:FindFirstChild("Icon") else nil
		if flask and flask:IsA("GuiObject") then
			local icon = flask:Clone()
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(0.6, 0.6)
			icon.Parent = tile
		end
		tile.Parent = nodeLayer
		distanceOf[tile] = 0
		treeTrove:Add(tile)
		treeTrove:Add(UI.bindButton(tile, {
			onActivate = function()
				selected = nil
				focusOn(Vector2.zero, false)
				render()
			end,
		}))
		hub = tile
	end

	-- A category's tag, a small pill on the stem between the hub and the fan's first project.
	local function tag(category: { name: string, color: Color3 }, angle: number)
		local radius = (HUB_SIZE / 2 + FIRST_RING - tileRadius) / 2 + 6
		local spot = polar(angle, radius)
		local pill = Instance.new("TextLabel")
		pill.Name = category.name .. "Tag"
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Position = UDim2.fromOffset(spot.X, spot.Y)
		pill.Size = UDim2.fromOffset(0, 20)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
		pill.BorderSizePixel = 0
		pill.Text = string.upper(category.name)
		pill.TextColor3 = category.color
		pill.TextSize = 12
		pill.FontFace = Font.new(info.name.FontFace.Family, Enum.FontWeight.Bold)
		pill.ZIndex = nodeTemplate.ZIndex
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 9)
		padding.PaddingRight = UDim.new(0, 9)
		padding.Parent = pill
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = pill
		local stroke = Instance.new("UIStroke")
		stroke.Color = category.color
		stroke.Thickness = 1
		stroke.Transparency = 0.4
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = pill
		pill.Parent = nodeLayer
		distanceOf[pill] = radius
		treeTrove:Add(pill)
	end

	local function build()
		treeTrove:Clean()
		table.clear(nodes)
		table.clear(links)
		table.clear(revealing)
		table.clear(glowing)
		table.clear(distanceOf)
		hovered = nil
		canvas.Size = UDim2.fromOffset(0, 0)
		-- Each project's place: its fan's middle, the angle of its line and its ring.
		local spots: { [string]: Vector2 } = {}
		local rings = 0
		for index, category in CATEGORIES do
			local middle = math.rad(-90 + (index - 1) * 360 / #CATEGORIES)
			local cells = layout(category.name)
			-- the lines spread evenly either side of the fan's middle, closer when there are many,
			-- so the fan stays inside its fifth
			local low, high = math.huge, -math.huge
			for _, cell in cells do
				low, high = math.min(low, cell.Y), math.max(high, cell.Y)
			end
			local centre = (low + high) / 2
			local step = if high > low then math.min(FAN_STEP, FAN_SPREAD / (high - low)) else FAN_STEP
			for id, cell in cells do
				local angle = if cell.X == 0 then middle else middle + math.rad((cell.Y - centre) * step)
				spots[id] = polar(angle, FIRST_RING + cell.X * RING_GAP)
				rings = math.max(rings, cell.X)
			end
			tag(category, middle)
		end
		buildHub(rings + 1)
		for _, project in Research.PROJECTS do
			local to = spots[project.id]
			if not to then
				continue
			end
			local distance = to.Magnitude
			local tint = TINTS[project.category] or COLORS.Done
			local needs = treeNeeds(project)
			if #needs == 0 then
				addLink(nil, project.id, project.id, curve(Vector2.zero, to, HUB_SIZE / 2), distance, tint)
			end
			for _, id in needs do
				local from = spots[id]
				if from then
					addLink(id, project.id, id, curve(from, to, tileRadius), distance, tint)
				end
			end
			local frame = nodeTemplate:Clone()
			local icon = Hud.find(frame, "Icon", "ViewportFrame")
			local name = Hud.find(frame, "Name", "TextLabel")
			if not icon or not icon:IsA("ViewportFrame") or not name or not name:IsA("TextLabel") then
				frame:Destroy()
				continue
			end
			local cost = frame:FindFirstChild("Cost")
			local progress = frame:FindFirstChild("Progress")
			local progressFill = if progress then progress:FindFirstChild("Fill") else nil
			local mystery = frame:FindFirstChild("Mystery")
			name.Text = project.name
			ItemIcon.show(icon, iconOf(project))
			frame.Name = project.id
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromOffset(to.X, to.Y)
			frame.ZIndex = nodeTemplate.ZIndex + 1
			-- the diamond: Node.Shape when authored, else one drawn here
			local shape = frame:FindFirstChild("Shape")
			if not shape or not shape:IsA("GuiObject") then
				local drawn = Instance.new("Frame")
				drawn.Name = "Shape"
				drawn.AnchorPoint = Vector2.new(0.5, 0.5)
				drawn.Position = UDim2.fromScale(0.5, 0.5)
				drawn.Size = UDim2.fromScale(0.74, 0.74)
				drawn.Rotation = 45
				drawn.BorderSizePixel = 0
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0, 12)
				round.Parent = drawn
				local ring = Instance.new("UIStroke")
				ring.Thickness = strokeThickness
				ring.Parent = drawn
				drawn.Parent = frame
				shape = drawn
			end
			local diamond = shape :: GuiObject
			local border = diamond:FindFirstChildOfClass("UIStroke")
			if border then
				-- a mitred join squares off a rounded corner
				border.LineJoinMode = Enum.LineJoinMode.Round
			end
			-- the breathing halo round a tile that can be researched (or completed): a larger
			-- diamond outline
			local halo = Instance.new("Frame")
			halo.Name = "Halo"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position = UDim2.fromScale(0.5, 0.5)
			halo.Size = UDim2.new(diamond.Size.X.Scale, 14, diamond.Size.Y.Scale, 14)
			halo.Rotation = 45
			halo.BackgroundTransparency = 1
			halo.ZIndex = diamond.ZIndex
			local haloCorner = Instance.new("UICorner")
			haloCorner.CornerRadius = UDim.new(0, 16)
			haloCorner.Parent = halo
			local haloStroke = Instance.new("UIStroke")
			haloStroke.Thickness = 2
			haloStroke.Color = COLORS.Open
			haloStroke.LineJoinMode = Enum.LineJoinMode.Round
			haloStroke.Parent = halo
			halo.Parent = frame
			frame.Parent = nodeLayer
			distanceOf[frame] = distance
			local id = project.id
			nodes[id] = {
				project = project,
				frame = frame,
				shape = diamond,
				tint = tint,
				stroke = border,
				scale = frame:FindFirstChildOfClass("UIScale"),
				icon = icon,
				name = name,
				cost = if cost and cost:IsA("TextLabel") then cost else nil,
				progress = if progress and progress:IsA("GuiObject") then progress else nil,
				fill = if progressFill and progressFill:IsA("GuiObject") then progressFill else nil,
				mystery = if mystery and mystery:IsA("GuiObject") then mystery else nil,
				halo = halo,
				haloStroke = haloStroke,
				centre = to,
				state = "Locked",
				kind = "Hidden",
			}
			treeTrove:Add(frame)
			treeTrove:Add(function()
				ItemIcon.clear(icon)
			end)
			treeTrove:Add(UI.bindButton(frame, {
				onActivate = function()
					selectProject(id)
				end,
			}))
			local function hover(on: boolean)
				if on then
					hovered = id
				elseif hovered == id then
					hovered = nil
				end
				render()
			end
			treeTrove:Connect(frame.MouseEnter, function()
				hover(true)
			end)
			treeTrove:Connect(frame.MouseLeave, function()
				hover(false)
			end)
			treeTrove:Connect(frame.SelectionGained, function()
				hover(true)
			end)
			treeTrove:Connect(frame.SelectionLost, function()
				hover(false)
			end)
		end
	end

	local function grow(by: number): UDim2
		return UDim2.fromOffset(nodeSize.X.Offset * by, nodeSize.Y.Offset * by)
	end

	-- A flash spreading from a tile and a ring running out past it.
	local function flashAndRing(frame: GuiObject, flashColor: Color3, ringColor: Color3, reach: number)
		local reduced = GuiService.ReducedMotionEnabled
		local at = frame.Position
		local flash = circle(nodeLayer, at, nodeSize, flashColor, 0.15, frame.ZIndex + 5)
		treeTrove:Add(flash)
		TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = if reduced then nodeSize else grow(reach * 0.72),
			BackgroundTransparency = 1,
		}):Play()
		local ring = circle(nodeLayer, at, nodeSize, ringColor, 0, frame.ZIndex + 5, 4)
		treeTrove:Add(ring)
		local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = if reduced then nodeSize else grow(reach),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1, Thickness = 1 }):Play()
		task.delay(0.85, function()
			flash:Destroy()
			ring:Destroy()
		end)
	end

	-- Diamond sparks flying out of a tile and shrinking away.
	local function sparks(frame: GuiObject, count: number, reach: number, colors: { Color3 })
		if GuiService.ReducedMotionEnabled then
			return
		end
		local at = frame.Position
		for index = 1, count do
			local spark = Instance.new("Frame")
			local side = math.random(6, 11)
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.Position = at
			spark.Size = UDim2.fromOffset(side, side)
			spark.Rotation = 45
			spark.BorderSizePixel = 0
			spark.BackgroundColor3 = colors[index % #colors + 1]
			spark.ZIndex = frame.ZIndex + 6
			spark.Parent = nodeLayer
			treeTrove:Add(spark)
			local angle = (index / count + math.random() * 0.06) * math.pi * 2
			local distance = reach * (0.55 + math.random() * 0.45)
			local seconds = 0.6 + math.random() * 0.3
			TweenService:Create(spark, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = at + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance - 16),
				Size = UDim2.fromOffset(1, 1),
				Rotation = 45 + math.random(-90, 90),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(seconds, function()
				spark:Destroy()
			end)
		end
	end

	-- The completion burst on a tile: it pops, a gold flash and a green ring spread from it and
	-- sparks fly out.
	local function burst(id: string)
		local node = nodes[id]
		if not node then
			return
		end
		local frame = node.frame
		flashAndRing(frame, COLORS.Ready, COLORS.Done, 3.6)
		sparks(frame, SPARKS, SPARK_REACH, SPARK_COLORS)
		if not GuiService.ReducedMotionEnabled then
			TweenService:Create(frame, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = grow(1.22),
			}):Play()
			task.delay(0.16, function()
				if frame.Parent then
					TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = nodeSize }):Play()
				end
			end)
		end
	end

	-- A tile the glow has just reached turns over into itself: it squashes flat, swaps its "?"
	-- for its picture and springs back, a pale flash and a gold ring spread from it and sparks
	-- scatter.
	local function reveal(id: string)
		local node = nodes[id]
		if not node then
			return
		end
		node.frame.Visible = true
		flashAndRing(node.frame, HOT, COLORS.Open, 2.6)
		sparks(node.frame, REVEAL_SPARKS, REVEAL_REACH, REVEAL_COLORS)
		local tileScale = node.scale
		if tileScale and not GuiService.ReducedMotionEnabled then
			tileScale.Scale = 0.2
			TweenService:Create(tileScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end

	-- The glow running down a line: a bright head travels its pieces in turn, drawing the lit line
	-- behind it, then `arrive` runs.
	local function travel(link: Link, arrive: () -> ())
		glowing[link] = true
		for _, piece in link.pieces do
			piece.holder.Visible = true
			piece.holder.BackgroundTransparency = 1
			piece.fill.Size = UDim2.fromScale(0, 1)
		end
		local zIndex = nodeTemplate.ZIndex + 4
		local start = link.pieces[1].from
		local at0 = UDim2.fromOffset(start.X, start.Y)
		local halo = circle(nodeLayer, at0, UDim2.fromOffset(34, 34), link.color, 0.5, zIndex)
		local head = circle(nodeLayer, at0, UDim2.fromOffset(14, 14), HOT, 0, zIndex + 1)
		treeTrove:Add(halo)
		treeTrove:Add(head)
		local headStroke = Instance.new("UIStroke")
		headStroke.Color = link.color
		headStroke.Thickness = 3
		headStroke.Transparency = 0.2
		headStroke.Parent = head
		local seconds = math.clamp(link.length / GLOW_SPEED, GLOW_SHORTEST, GLOW_LONGEST)
		local function finish()
			halo:Destroy()
			head:Destroy()
			glowing[link] = nil
			for _, piece in link.pieces do
				piece.holder.BackgroundTransparency = linkTransparency
				piece.fill.Size = UDim2.fromScale(1, 1)
			end
			arrive()
		end
		if GuiService.ReducedMotionEnabled then
			finish()
			return
		end
		animate(seconds, function(alpha)
			-- quick off the mark, easing as it arrives
			local travelled = (1 - (1 - alpha) ^ 2) * link.length
			local at = link.pieces[1].from
			for _, piece in link.pieces do
				local share = math.clamp(travelled / math.max(piece.length, 1), 0, 1)
				piece.fill.Size = UDim2.fromScale(share, 1)
				piece.fill.BackgroundColor3 = HOT:Lerp(link.color, alpha)
				if travelled > 0 then
					at = piece.from:Lerp(piece.to, share)
				end
				travelled -= piece.length
			end
			local pulse = 1 + 0.25 * math.sin(alpha * math.pi * 6)
			head.Position = UDim2.fromOffset(at.X, at.Y)
			halo.Position = head.Position
			halo.Size = UDim2.fromOffset(34 * pulse, 34 * pulse)
		end, function()
			for _, piece in link.pieces do
				piece.fill.BackgroundColor3 = link.color
			end
			finish()
		end)
	end

	-- Sap: a small mote drifting outward down a lit line, fading in and out.
	local function sap()
		local candidates = {}
		for _, link in links do
			local first = link.pieces[1]
			if
				first
				and not glowing[link]
				and first.holder.Visible
				and first.fill.Size.X.Scale >= 1
				and ResearchClient.done()[link.lit]
			then
				table.insert(candidates, link)
			end
		end
		if #candidates == 0 then
			return
		end
		local link = candidates[math.random(#candidates)]
		local start = link.pieces[1].from
		local mote = circle(
			linkLayer,
			UDim2.fromOffset(start.X, start.Y),
			UDim2.fromOffset(6, 6),
			link.color:Lerp(HOT, 0.55),
			1,
			3
		)
		treeTrove:Add(mote)
		table.insert(saps, mote)
		animate(link.length / SAP_SPEED, function(alpha)
			local travelled = alpha * link.length
			local at = start
			for _, piece in link.pieces do
				local share = math.clamp(travelled / math.max(piece.length, 1), 0, 1)
				if travelled > 0 then
					at = piece.from:Lerp(piece.to, share)
				end
				travelled -= piece.length
			end
			mote.Position = UDim2.fromOffset(at.X, at.Y)
			mote.BackgroundTransparency = 0.15 + 0.85 * math.abs(alpha * 2 - 1) ^ 3
		end, function()
			local index = table.find(saps, mote)
			if index then
				table.remove(saps, index)
			end
			mote:Destroy()
		end)
	end

	-- A project just completed: its tile bursts, then a glow runs down every line out of it and
	-- each undiscovered project it reaches turns over into itself. The view glides to take in the
	-- project and what it leads to.
	local function celebrate(id: string, before: { [string]: boolean })
		local node = nodes[id]
		if not node then
			return
		end
		local outgoing: { Link } = {}
		local around = node.centre
		for _, link in links do
			if link.need == id and nodes[link.child] then
				table.insert(outgoing, link)
				around += nodes[link.child].centre
				if not inReach(nodes[link.child].project, before) then
					revealing[link.child] = true
				end
			end
		end
		selected = nil
		focusOn(around / (#outgoing + 1), false)
		render()
		burst(id)
		task.delay(if GuiService.ReducedMotionEnabled then 0 else GLOW_DELAY, function()
			if not node.frame.Parent then
				return
			end
			for _, link in outgoing do
				travel(link, function()
					local child = link.child
					if revealing[child] then
						revealing[child] = nil
						render()
						reveal(child)
					else
						render()
					end
				end)
			end
		end)
	end

	local function enter()
		shown = true
		HudVisibility.hide("Research", true, true)
		hovered = nil
		selected = nil
		focus, shownFocus = Vector2.zero, Vector2.zero
		scale = OVERVIEW
		shownScale = if GuiService.ReducedMotionEnabled then scale else scale * OPEN_ZOOM
		render()
	end

	local function leave()
		shown = false
		hovered = nil
		press = nil
		dragging = false
		pinchDistance = nil
		table.clear(touches)
		HudVisibility.hide("Research", false)
	end

	local function animateView(show: boolean)
		if show == shown then
			return
		end
		if stopFade then
			stopFade()
			stopFade = nil
			restoreFade()
		end
		if show then
			enter()
		else
			leave()
		end
		root.Interactable = show
		if GuiService.ReducedMotionEnabled then
			root.Visible = show
			return
		end
		root.Visible = true
		fadeOpening = show
		capture()
		fadeClock = 0
		applyFade(0)
		local total = if show then 0.05 + APPEAR_SPREAD + APPEAR else BACKDROP_AFTER + VANISH
		stopFade = animate(total, function(alpha)
			fadeClock = alpha * total
			applyFade(fadeClock)
		end, function()
			stopFade = nil
			restoreFade()
			root.Visible = show
			if shown then
				render()
			end
		end)
	end

	-- Puts a panel beside a tile, level with it: to its right, or its left when there is no room,
	-- kept on screen and clear of the strip along the bottom.
	local function place(panel: Panel, id: string?)
		local node = if id then nodes[id] else nil
		if not node or not node.frame.Visible then
			panel.frame.Visible = false
			return
		end
		panel.frame.Visible = true
		panel.frame.AnchorPoint = Vector2.zero
		local frame = node.frame
		local low = frame.AbsolutePosition - root.AbsolutePosition
		local tile = frame.AbsoluteSize
		local size = panel.frame.AbsoluteSize
		local screen = root.AbsoluteSize
		local x = low.X + tile.X + INFO_GAP
		if x + size.X > screen.X - EDGE then
			x = low.X - INFO_GAP - size.X
		end
		x = math.clamp(x, EDGE, math.max(EDGE, screen.X - size.X - EDGE))
		local y = math.clamp(low.Y + tile.Y / 2 - size.Y / 2, TOP, math.max(TOP, screen.Y - size.Y - BOTTOM))
		panel.frame.Position = UDim2.fromOffset(x, y)
	end

	-- Every frame while open: the canvas glides, the orbits turn, the hub and halos breathe, sap
	-- drifts, the panels follow their tiles, and the running project's countdown and bars tick.
	local wasReady = false
	local function step(dt: number)
		for _, gamepad in UserInputService:GetConnectedGamepads() do
			for _, input in UserInputService:GetGamepadState(gamepad) do
				if input.KeyCode == Enum.KeyCode.Thumbstick2 then
					local stick = Vector2.new(input.Position.X, -input.Position.Y)
					if stick.Magnitude > STICK_DEAD_ZONE then
						local move = stick * PAN_SPEED * dt / scale
						focus += move
						shownFocus += move
					end
				end
			end
		end
		local blend = 1 - math.exp(-dt * GLIDE)
		shownFocus = shownFocus:Lerp(focus, blend)
		shownScale += (scale - shownScale) * blend
		zoom.Scale = shownScale
		local middle = root.AbsoluteSize / 2
		local offset = middle - shownFocus * shownScale
		canvas.Position = UDim2.fromOffset(offset.X, offset.Y)
		place(info, selected)
		if hovered and hovered ~= selected then
			place(tooltip, hovered)
		else
			tooltip.frame.Visible = false
		end
		local now = os.clock()
		local calm = not GuiService.ReducedMotionEnabled
		if calm then
			for _, orbit in orbits do
				orbit.frame.Rotation = (orbit.frame.Rotation + orbit.speed * dt) % 360
			end
		end
		-- the breathing (left alone mid-ripple, which owns transparencies then)
		if not stopFade and calm then
			local breath = 0.5 + 0.5 * math.sin(now * 2.2)
			if hubStroke then
				hubStroke.Transparency = 0.35 * breath
			end
			for _, node in nodes do
				if node.halo.Visible then
					local fast = node.state == "Ready"
					local wave = 0.5 + 0.5 * math.sin(now * (if fast then 5 else 2.4) + node.centre.X * 0.01)
					node.haloStroke.Transparency = 0.25 + 0.6 * wave
					local size = node.shape.Size.X.Scale
					local out = 10 + 8 * (1 - wave)
					node.halo.Size = UDim2.new(size, out, size, out)
				end
			end
			sapClock += dt
			if sapClock >= SAP_EVERY then
				sapClock = 0
				if #saps < SAP_MOST then
					sap()
				end
			end
		end
		local snapshot = ResearchClient.get()
		local active = snapshot.active
		local project = if active then Research.get(active.id) else nil
		local ready = activeReady()
		if ready ~= wasReady then
			wasReady = ready
			render()
		end
		local waiting = #snapshot.ready + (if ready then 1 else 0)
		local pulse = 0.5 + 0.5 * math.sin(now * 4)
		if completeStroke then
			completeStroke.Thickness = completeThickness + if waiting > 0 then pulse * 2 else 0
		end
		-- finished tiles pulse gold until completed
		for _, node in nodes do
			if node.state == "Ready" and node.stroke and node.kind == "Shown" then
				node.stroke.Color = COLORS.Ready:Lerp(Color3.new(1, 1, 1), pulse * 0.45)
				node.stroke.Thickness = strokeThickness + pulse * 2
			end
		end
		-- After the running project: what waits for Complete and what is queued next.
		local extras = {}
		if #snapshot.ready > 0 then
			table.insert(extras, `{#snapshot.ready} ready`)
		end
		local nextUp = snapshot.queue[1]
		local nextProject = if nextUp then Research.get(nextUp.id) else nil
		if nextProject then
			table.insert(
				extras,
				`Next: {nextProject.name}{if #snapshot.queue > 1 then ` +{#snapshot.queue - 1}` else ""}`
			)
		end
		local tail = if #extras > 0 then "  ·  " .. table.concat(extras, "  ·  ") else ""
		if not active or not project then
			activeText.Text = if waiting > 0
				then `{waiting} project{if waiting > 1 then "s" else ""} ready to complete!`
				elseif ResearchClient.isSynced() then "Pick an upgrade to research. It keeps going while you're away."
				else "Loading your research..."
			activeTime.Text = ""
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		local left = math.max(0, active.endsAt - workspace:GetServerTimeNow())
		local progress = math.clamp(1 - left / active.seconds, 0, 1)
		-- Complete stands where the countdown is while an earlier project waits, so the time
		-- moves into the line.
		local covered = not ready and #snapshot.ready > 0
		activeText.Text = (
			if ready
				then `{project.name} is ready!`
				elseif covered then `Researching {project.name} ({Hud.time(left)})`
				else `Researching {project.name}`
		) .. tail
		activeTime.Text = if ready or covered then "" else Hud.time(left)
		fill.Size = UDim2.fromScale(progress, 1)
		local node = nodes[active.id]
		if node and node.fill then
			node.fill.Size = UDim2.fromScale(progress, 1)
		end
		if selected == active.id and not ready then
			fillPanel(info, project)
		end
	end

	local window = HubWindow.bind(view, "Research", {}, render, nil, false, animateView)
	if not window then
		return
	end
	local tabs = view:FindFirstChild("Tabs", true)
	if tabs and tabs:IsA("GuiObject") then
		-- one tree now: an older place's category tabs stay hidden
		tabs.Visible = false
	end
	local function send(kind: string, id: string?)
		pending = true
		render()
		Remotes.Research:FireServer(kind, id)
	end
	trove:Add(UI.bindButton(action, {
		onActivate = function()
			if action.Active and not pending and selected and actionKind then
				send(actionKind, selected)
			end
		end,
	}))
	trove:Add(UI.bindButton(cancel, {
		onActivate = function()
			if cancel.Active and not pending then
				send("Cancel")
			end
		end,
	}))
	trove:Add(UI.bindButton(completeButton, {
		onActivate = function()
			if completeButton.Active and not pending then
				send("Complete")
			end
		end,
	}))
	local opener = Hud.find(hud, "SideButtons.Research", "TextButton")
	if opener then
		trove:Add(UI.bindButton(opener, {
			hoverScale = 1.08,
			onActivate = function()
				if window.isOpen() then
					window.close()
				else
					window.open()
				end
			end,
		}))
	end
	-- Whether a press at `point` landed on empty space: not a tile, the hub, the info or the strip.
	local function onEmpty(point: Vector2): boolean
		if over(info.frame, point) or over(activeStrip, point) or (hub and over(hub, point)) then
			return false
		end
		for _, node in nodes do
			if over(node.frame, point) then
				return false
			end
		end
		return true
	end
	-- Both input paths may see a touch first; registering it once prevents a second finger
	-- from starting another drag before the global listener sees it.
	local function touchDistance(): number?
		return if #touches >= PINCH_TOUCHES
			then (touches[1].Position - touches[PINCH_TOUCHES].Position).Magnitude
			else nil
	end
	local function addTouch(input: InputObject)
		if not table.find(touches, input) then
			table.insert(touches, input)
			pinchDistance = touchDistance()
		end
		if #touches >= PINCH_TOUCHES then
			press = nil
			dragging = false
		end
	end
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if not shown then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			addTouch(input)
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			scale = math.clamp(scale / GAMEPAD_ZOOM, NEAREST, FARTHEST)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			scale = math.clamp(scale * GAMEPAD_ZOOM, NEAREST, FARTHEST)
		end
	end)
	-- Dragging the background pans the tree; a touch pair owns zoom until it ends.
	local pressedEmpty = false
	trove:Connect(root.InputBegan, function(input: InputObject)
		if not shown then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch then
			addTouch(input)
		end
		if #touches >= PINCH_TOUCHES then
			return
		end
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			press = Vector2.new(input.Position.X, input.Position.Y)
			pressedEmpty = onEmpty(press)
			dragging = false
		end
	end)
	trove:Connect(root.InputChanged, function(input: InputObject)
		if shown and input.UserInputType == Enum.UserInputType.MouseWheel then
			scale = math.clamp(scale * (1 + input.Position.Z * 0.1), NEAREST, FARTHEST)
		end
	end)
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		if not shown then
			return
		end
		local kind = input.UserInputType
		if #touches >= PINCH_TOUCHES then
			if kind == Enum.UserInputType.Touch then
				local distance = touchDistance()
				if distance and distance > 0 and pinchDistance and pinchDistance > 0 then
					scale = math.clamp(scale * distance / pinchDistance, NEAREST, FARTHEST)
				end
				pinchDistance = distance
			end
			return
		end
		if not press or (kind ~= Enum.UserInputType.MouseMovement and kind ~= Enum.UserInputType.Touch) then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if not dragging and (at - press).Magnitude < DRAG_START then
			return
		end
		dragging = true
		focus -= (at - press) / scale
		shownFocus = focus
		press = at
	end)
	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch then
			local index = table.find(touches, input)
			if index then
				table.remove(touches, index)
			end
			pinchDistance = touchDistance()
		end
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			-- a press on empty space that never became a drag puts the info away
			if shown and press and pressedEmpty and not dragging and #touches < PINCH_TOUCHES then
				deselect()
			end
			press = nil
			pressedEmpty = false
		end
	end)
	build()
	render()
	-- Every request is answered with a sync, which also ends the wait. A project that has just
	-- been completed bursts and unlocks what it leads to.
	trove:Connect(ResearchClient.changed, function()
		pending = false
		local done = ResearchClient.done()
		local ranks = ResearchClient.get().ranks
		local completed: string? = nil
		local before = lastDone
		if before then
			for id in done do
				if not before[id] then
					completed = id
				end
			end
			for id, rank in ranks do
				if lastRanks and rank > (lastRanks[id] or 0) then
					completed = id
				end
			end
		end
		lastDone = table.clone(done)
		lastRanks = table.clone(ranks)
		if shown and completed and before then
			celebrate(completed, before)
		else
			render()
		end
	end)
	trove:Connect(EconomyClient.changed, render)
	trove:Connect(InventoryClient.changed, render)
	trove:Connect(RunService.RenderStepped, function(dt: number)
		if shown then
			step(dt)
		end
	end)
	trove:Connect(view.Destroying, function()
		if shown then
			leave()
		end
		if stopFade then
			stopFade()
		end
		treeTrove:Destroy()
		trove:Destroy()
	end)
end

return ResearchScreen
