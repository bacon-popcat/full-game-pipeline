-- ResearchScreen: the Research window, a full-screen black view of one upgrade tree. It lives in
-- its own ScreenGui (StarterGui.ResearchView, authored) and, while open, hides the HUD, player
-- list and chat (HudVisibility), leaving the close button and the running project's strip along
-- the bottom. SideButtons.Research opens it from anywhere; it fades in, settling from a touch
-- larger, and fades back out (the screen animates itself through HubWindow's `animate`).
--
-- The tree grows from a hub in the middle of Research.Canvas, where the view always opens. Each
-- category is an arm out of it (ARMS): Farming up, Automation right, Economy down, Crafting left
-- and Tools up and to the left. Along an arm, a project's step out is how many projects lead to
-- it in its category, and it hangs off its latest need: children continuing its line
-- (Yield1 -> Yield2) run straight on, the others branch to alternate sides. Tiles are cloned from
-- Assets.UI.Research.Node; each need in the same category is joined to it by an elbowed line of
-- Assets.UI.Research.Link pieces (straight from the hub), lit green once the need is done.
-- Only what is in reach shows: each arm's first project, what is done or running, and whatever
-- a finished project leads to. A tile's border says its state: green done, yellow can start, red
-- locked, blue running (with a bar), gold and pulsing ready to complete. Open and locked tiles
-- show a short coin-cost badge, red when the wallet falls short.
--
-- Pressing a tile selects it: the canvas glides it just left of the middle and Research.Info
-- stands beside it with its name, description, level and cost, a card per required item (its
-- picture with "x20 Wheat" under it, outlined and named in green once you carry enough), the
-- time behind an hourglass, and an Action button (Research, Complete...). Pressing empty space
-- puts the info away and centres the tile; pressing the hub glides home. Hovering another tile
-- shows the same in Research.Tooltip, without the button. The canvas pans
-- by dragging or the gamepad's right stick, and zooms with the wheel, a two-finger pinch, or
-- ButtonL2/ButtonR2. Pinching never also drags it.
--
-- Body.Active shows the running project's countdown and Cancel; once its timer runs out its
-- Complete button glows. Completing a project bursts its tile, then a glow runs down each line
-- out of it, drawing the line as it goes, and every project it reaches that was hidden pops in
-- with a flash, a ring and sparks; FxController plays the world effect round the player.
-- Whether a project can start is Research.blocker's to say, with the wallet and inventory here;
-- the server checks it all again and answers with Notify and a fresh ResearchSync, which ends
-- the wait.
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
}
-- Each category's arm: where its first project sits (in HUB_REACH units from the hub), the way
-- it grows, and which side its first branch takes (1 = the arm's left as it grows, -1 right).
type Arm = { origin: Vector2, direction: Vector2, side: number }
local ARMS: { [string]: Arm } = {
	Farming = { origin = Vector2.new(0, -1), direction = Vector2.new(0, -1), side = 1 },
	Automation = { origin = Vector2.new(1, 0), direction = Vector2.new(1, 0), side = 1 },
	Economy = { origin = Vector2.new(0, 1), direction = Vector2.new(0, 1), side = 1 },
	Crafting = { origin = Vector2.new(-1, 0), direction = Vector2.new(-1, 0), side = 1 },
	Tools = { origin = Vector2.new(-2.2, -2.2), direction = Vector2.new(0, -1), side = -1 },
}
-- Pixels from the hub to an arm's first project, between steps along an arm, and between its
-- branches.
local HUB_REACH, COLUMN, ROW = 150, 140, 136
-- The hub's diameter in pixels.
local HUB_SIZE = 92
local COLORS = {
	Done = Color3.fromRGB(120, 220, 110),
	Ready = Color3.fromRGB(255, 214, 110),
	Running = Color3.fromRGB(120, 180, 240),
	Open = Color3.fromRGB(240, 210, 90),
	Locked = Color3.fromRGB(196, 78, 78),
}
local HOT = Color3.fromRGB(255, 246, 222)
-- Before the research time in the info.
local HOURGLASS = utf8.char(0x231B)
-- How far a locked tile's item and name fade.
local LOCKED_FADE = 0.55
-- The canvas: how quickly it glides to where it is going (per second), how far the wheel zooms,
-- and pixels left of the screen's middle the selected tile sits, leaving room for its info.
local GLIDE = 8
local NEAREST, FARTHEST = 0.5, 1.4
local SIT_LEFT = 210
-- Opening: the zoom the canvas starts at (as a share of its own) and glides in from.
local OPEN_ZOOM = 0.82
-- The view's fade: seconds in and out, and how much larger it is while faded.
local FADE_IN, FADE_OUT, FADE_SCALE = 0.4, 0.28, 1.04
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

type State = "Done" | "Ready" | "Running" | "Open" | "Locked"
type Node = {
	project: Research.Project,
	frame: GuiButton,
	stroke: UIStroke?,
	scale: UIScale?,
	icon: ViewportFrame,
	name: TextLabel,
	cost: TextLabel?,
	progress: GuiObject?,
	fill: GuiObject?,
	centre: Vector2,
	state: State,
}
type Piece = { holder: Frame, fill: Frame, from: Vector2, to: Vector2, length: number }
-- `need` is nil for a line from the hub; it is lit once `lit` is done.
type Link = { need: string?, child: string, lit: string, pieces: { Piece }, length: number }
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
	local active = ResearchClient.get().active
	if done[project.id] then
		return "Done"
	elseif active and active.id == project.id then
		return if activeReady() then "Ready" else "Running"
	end
	return if Research.blocker(project, done, EconomyClient.get().level, nil) then "Locked" else "Open"
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

-- Whether a project is in reach, given the finished ids: an arm's first project, a finished or
-- running one, or one a finished project in its category leads to.
local function inReach(project: Research.Project, done: { [string]: boolean }): boolean
	local active = ResearchClient.get().active
	if done[project.id] or (active and active.id == project.id) then
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

-- Where each project of `category` sits in its tree, as a step out and a branch.
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
	local rows: { [string]: number } = {}
	local nextRow = 0
	local function place(project: Research.Project)
		local list = children[project.id]
		if not list then
			rows[project.id] = nextRow
			nextRow += 1
			return
		end
		for _, child in list do
			place(child)
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

-- Branch 0 runs down the arm's middle; the rest alternate sides, nearest first.
local function sideOf(row: number): number
	if row == 0 then
		return 0
	end
	return (row + 1) // 2 * (if row % 2 == 1 then 1 else -1)
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

function ResearchScreen.init(hud: ScreenGui)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local view = playerGui:WaitForChild("ResearchView", 10)
	if not view or not view:IsA("ScreenGui") then
		warn("ResearchScreen: PlayerGui.ResearchView must be an authored ScreenGui")
		return
	end
	local root = Hud.find(view, "Research", "Frame")
	local viewScale = Hud.find(view, "Research.UIScale", "UIScale")
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
		or not viewScale
		or not viewScale:IsA("UIScale")
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
	local selected: string? = nil
	local hovered: string? = nil
	local pending = false
	local shown = false
	-- Projects whose tile waits for the unlock glow to reach it, and lines it is running down.
	local revealing: { [string]: boolean } = {}
	local glowing: { [Link]: boolean } = {}
	-- Baselines, captured from what is authored.
	local nodeSize = nodeTemplate.Size
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
	local viewBaseline = viewScale.Scale
	-- Clicks on the info panel stay on it rather than reaching the background below.
	info.frame.Active = true
	-- The finished ids at the last sync, so a newly completed one can burst.
	local lastDone: { [string]: boolean }? = nil
	-- The canvas point the screen centres on, where it is going and where it is, and its zoom.
	local focus, shownFocus = Vector2.zero, Vector2.zero
	local scale = zoom.Scale
	local shownScale = scale
	local press: Vector2? = nil
	local dragging = false
	local touches: { InputObject } = {}
	local pinchDistance: number? = nil

	-- Opening and closing fade the whole view: every transparency under it is taken from where
	-- it stands and eased to clear (and back), while the view settles from a touch larger. The
	-- tiles' item pictures are ViewportFrames, faded the same way.
	local fadeEntries: { { instance: Instance, property: string, base: number } } = {}
	local fadeAmount = 1
	local stopFade: (() -> ())? = nil
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
	local function capture()
		table.clear(fadeEntries)
		local function add(instance: Instance)
			for className, properties in FADED do
				if instance:IsA(className) then
					for _, property in properties do
						table.insert(
							fadeEntries,
							{ instance = instance, property = property, base = (instance :: any)[property] }
						)
					end
				end
			end
		end
		add(root)
		for _, descendant in root:GetDescendants() do
			add(descendant)
		end
	end
	local function applyFade(amount: number)
		for _, entry in fadeEntries do
			if entry.instance.Parent then
				(entry.instance :: any)[entry.property] = entry.base + (1 - entry.base) * amount
			end
		end
		viewScale.Scale = viewBaseline * (1 + (FADE_SCALE - 1) * amount)
	end
	local function restoreFade()
		for _, entry in fadeEntries do
			if entry.instance.Parent then
				(entry.instance :: any)[entry.property] = entry.base
			end
		end
		table.clear(fadeEntries)
		viewScale.Scale = viewBaseline
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

	local function fillPanel(panel: Panel, project: Research.Project)
		local economy = EconomyClient.get()
		local snapshot = ResearchClient.get()
		local done = ResearchClient.done()
		local activeId = if snapshot.active then snapshot.active.id else nil
		local blocked = Research.blocker(project, done, economy.level, activeId)
		local items, hasItems = itemsOf(project)
		local state = stateOf(project)
		local cards = showCards(panel, project, state ~= "Done" and state ~= "Running" and state ~= "Ready")
		panel.name.Text = project.name
		panel.name.TextColor3 = COLORS[state]
		panel.description.Text = project.description
		panel.level.Text = `Lv. {project.level}  -  {if state == "Done"
			then "Researched"
			elseif state == "Ready" then "Ready to complete"
			elseif state == "Running" then "Researching"
			elseif state == "Locked" then "Locked"
			else "Can research"}`
		panel.level.TextColor3 = if economy.level < project.level then COLORS.Locked else levelColor
		panel.cost.Visible = state == "Open" or state == "Locked"
		panel.cost.Text = `{Hud.number(project.coins)} coins`
		panel.cost.TextColor3 = if economy.coins >= project.coins then costColor else COLORS.Locked
		local lines = {}
		local seconds = Research.duration(project, snapshot.bonuses.researchSpeed or 0)
		if state == "Running" then
			local active = snapshot.active
			seconds = if active then math.max(0, active.endsAt - workspace:GetServerTimeNow()) else 0
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
		elseif state ~= "Done" then
			if not panel.time then
				table.insert(lines, `Takes {duration(seconds)}`)
			end
			if items ~= "" and not cards then
				table.insert(lines, `Needs {items}{if hasItems then "" else " (you don't have them)"}`)
			end
			if blocked and blocked ~= "Another project is running" then
				table.insert(lines, blocked)
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
		local activeId = if snapshot.active then snapshot.active.id else nil
		local blocked = Research.blocker(project, done, economy.level, activeId)
		local _, hasItems = itemsOf(project)
		local enoughCoins = economy.coins >= project.coins
		local ready = activeId == project.id and activeReady()
		local enabled = not pending
			and (ready or (blocked == nil and enoughCoins and hasItems and activeId ~= project.id))
		action.Active = enabled
		action.Selectable = enabled
		action.BackgroundTransparency = if enabled
			then actionLook.transparency
			else actionLook.transparency + (1 - actionLook.transparency) * 0.5
		actionLabel.TextTransparency = if enabled
			then actionLook.text
			else actionLook.text + (1 - actionLook.text) * 0.5
		actionLabel.Text = if pending
			then "..."
			elseif done[project.id] then "Done"
			elseif ready then "Complete"
			elseif activeId == project.id then "Running"
			elseif blocked == "Another project is running" then "Busy"
			elseif blocked then "Locked"
			elseif not enoughCoins then "Need coins"
			elseif not hasItems then "Need items"
			else "Research"
	end

	local function visible(id: string, done: { [string]: boolean }): boolean
		local node = nodes[id]
		return node ~= nil and not revealing[id] and inReach(node.project, done)
	end

	local function paintTiles()
		local done = ResearchClient.done()
		local coins = EconomyClient.get().coins
		for id, node in nodes do
			local state = stateOf(node.project)
			node.state = state
			node.frame.Visible = visible(id, done)
			if node.stroke then
				node.stroke.Color = COLORS[state]
				node.stroke.Thickness = strokeThickness
			end
			node.icon.ImageTransparency = if state == "Locked" then LOCKED_FADE else 0
			node.name.TextTransparency = if state == "Locked" then LOCKED_FADE else 0
			if node.cost then
				node.cost.Visible = state == "Open" or state == "Locked"
				node.cost.Text = shortCost(node.project.coins)
				if nodeCostColor then
					node.cost.TextColor3 = if coins < node.project.coins then COLORS.Locked else nodeCostColor
				end
			end
			if node.progress then
				node.progress.Visible = state == "Running" or state == "Ready"
			end
		end
		for _, link in links do
			if glowing[link] then
				continue
			end
			local shows = visible(link.child, done) and (link.need == nil or visible(link.need, done))
			local lit = done[link.lit] == true
			for _, piece in link.pieces do
				piece.holder.Visible = shows
				piece.holder.BackgroundTransparency = linkTransparency
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
		local active = ResearchClient.get().active
		local ready = activeReady()
		cancel.Visible = active ~= nil and not ready
		cancel.Active = active ~= nil and not pending
		completeButton.Visible = ready
		completeButton.Active = ready and not pending
		if stopFade then
			-- mid-fade, what was just painted stays faded (the fade's end paints again)
			applyFade(fadeAmount)
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
	local function segment(a: Vector2, b: Vector2): Piece
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
		treeTrove:Add(holder)
		return { holder = holder, fill = lit, from = a, to = b, length = length }
	end

	local function addLink(need: string?, child: string, lit: string, points: { Vector2 })
		local pieces = {}
		local length = 0
		for index = 1, #points - 1 do
			local piece = segment(points[index], points[index + 1])
			table.insert(pieces, piece)
			length += piece.length
		end
		table.insert(links, { need = need, child = child, lit = lit, pieces = pieces, length = length })
	end

	-- The hub: the flask from the side button on a round tile; pressing it glides home.
	local function buildHub()
		local tile = Instance.new("TextButton")
		tile.Name = "Hub"
		tile.Text = ""
		tile.AutoButtonColor = false
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromOffset(0, 0)
		tile.Size = UDim2.fromOffset(HUB_SIZE, HUB_SIZE)
		tile.BackgroundColor3 = nodeTemplate.BackgroundColor3
		tile.BorderSizePixel = 0
		tile.ZIndex = nodeTemplate.ZIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = tile
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.Ready
		stroke.Thickness = strokeThickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = tile
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

	local function build()
		treeTrove:Clean()
		table.clear(nodes)
		table.clear(links)
		table.clear(revealing)
		table.clear(glowing)
		hovered = nil
		canvas.Size = UDim2.fromOffset(0, 0)
		buildHub()
		local half = nodeSize.X.Offset / 2
		-- Each project's place: its arm, step out and branch, and where that is on the canvas.
		local spots: { [string]: { arm: Arm, along: number, across: number } } = {}
		local function point(arm: Arm, along: number, across: number): Vector2
			local side = Vector2.new(-arm.direction.Y, arm.direction.X) * arm.side
			return arm.origin * HUB_REACH + arm.direction * along + side * across
		end
		for category, arm in ARMS do
			for id, cell in layout(category) do
				spots[id] = { arm = arm, along = cell.X * COLUMN, across = sideOf(cell.Y) * ROW }
			end
		end
		for _, project in Research.PROJECTS do
			local spot = spots[project.id]
			if not spot then
				continue
			end
			local arm = spot.arm
			local to = point(arm, spot.along, spot.across)
			local needs = treeNeeds(project)
			if #needs == 0 then
				-- straight from the hub's rim to the near edge of the tile
				local way = to.Unit
				local reach = half / math.max(math.abs(way.X), math.abs(way.Y))
				addLink(nil, project.id, project.id, { way * HUB_SIZE / 2, to - way * reach })
			end
			-- Elbowed lines from each need in the tree: on along the need's branch to the gap
			-- before this tile, across to its branch, and on into it.
			for _, id in needs do
				local from = spots[id]
				if from then
					local startAlong, endAlong = from.along + half, spot.along - half
					if from.across == spot.across then
						addLink(id, project.id, id, {
							point(arm, startAlong, from.across),
							point(arm, endAlong, spot.across),
						})
					else
						local turn = endAlong - (COLUMN - half * 2) / 2
						addLink(id, project.id, id, {
							point(arm, startAlong, from.across),
							point(arm, turn, from.across),
							point(arm, turn, spot.across),
							point(arm, endAlong, spot.across),
						})
					end
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
			name.Text = project.name
			ItemIcon.show(icon, iconOf(project))
			frame.Name = project.id
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromOffset(to.X, to.Y)
			frame.Parent = nodeLayer
			local id = project.id
			nodes[id] = {
				project = project,
				frame = frame,
				stroke = frame:FindFirstChildOfClass("UIStroke"),
				scale = frame:FindFirstChildOfClass("UIScale"),
				icon = icon,
				name = name,
				cost = if cost and cost:IsA("TextLabel") then cost else nil,
				progress = if progress and progress:IsA("GuiObject") then progress else nil,
				fill = if progressFill and progressFill:IsA("GuiObject") then progressFill else nil,
				centre = to,
				state = "Locked",
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

	-- A round frame on the canvas at `at`, over the tiles, cleared with the tree.
	local function disc(at: UDim2, size: UDim2, color: Color3, transparency: number, zIndex: number): Frame
		local circle = Instance.new("Frame")
		circle.AnchorPoint = Vector2.new(0.5, 0.5)
		circle.Position = at
		circle.Size = size
		circle.BackgroundColor3 = color
		circle.BackgroundTransparency = transparency
		circle.BorderSizePixel = 0
		circle.ZIndex = zIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		circle.Parent = nodeLayer
		treeTrove:Add(circle)
		return circle
	end

	local function grow(by: number): UDim2
		return UDim2.fromOffset(nodeSize.X.Offset * by, nodeSize.Y.Offset * by)
	end

	-- A flash spreading from a tile and a ring running out past it.
	local function flashAndRing(frame: GuiObject, flashColor: Color3, ringColor: Color3, reach: number)
		local reduced = GuiService.ReducedMotionEnabled
		local at = frame.Position
		local flash = disc(at, nodeSize, flashColor, 0.15, frame.ZIndex + 5)
		TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = if reduced then nodeSize else grow(reach * 0.72),
			BackgroundTransparency = 1,
		}):Play()
		local ring = disc(at, nodeSize, ringColor, 1, frame.ZIndex + 5)
		local stroke = Instance.new("UIStroke")
		stroke.Color = ringColor
		stroke.Thickness = 4
		stroke.Parent = ring
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

	-- A tile the glow has just reached pops in: it grows from small with a bounce, a pale flash
	-- and a gold ring spread from it, and sparks scatter.
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
			TweenService:Create(tileScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
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
		local halo = disc(UDim2.fromOffset(start.X, start.Y), UDim2.fromOffset(34, 34), COLORS.Ready, 0.55, zIndex)
		local head = disc(UDim2.fromOffset(start.X, start.Y), UDim2.fromOffset(14, 14), HOT, 0, zIndex + 1)
		local headStroke = Instance.new("UIStroke")
		headStroke.Color = COLORS.Ready
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
				piece.fill.BackgroundColor3 = COLORS.Ready:Lerp(COLORS.Done, alpha)
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
				piece.fill.BackgroundColor3 = COLORS.Done
			end
			finish()
		end)
	end

	-- A project just completed: its tile bursts, then a glow runs down every line out of it and
	-- each project it reaches that was out of reach before pops in. The view glides to take in
	-- the project and what it leads to.
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
		for _, link in outgoing do
			-- drawn by the glow, not before it
			glowing[link] = true
			for _, piece in link.pieces do
				piece.holder.Visible = false
			end
		end
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
			fadeAmount = if show then 0 else 1
			root.Visible = show
			return
		end
		root.Visible = true
		capture()
		local from = fadeAmount
		local target = if show then 0 else 1
		applyFade(from)
		stopFade = animate(if show then FADE_IN else FADE_OUT, function(alpha)
			local eased = if show then 1 - (1 - alpha) ^ 2 else alpha * alpha
			fadeAmount = from + (target - from) * eased
			applyFade(fadeAmount)
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

	-- Every frame while open: the canvas glides, the panels follow their tiles, a ready tile
	-- breathes, and the running project's countdown and bars tick.
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
		local active = ResearchClient.get().active
		local project = if active then Research.get(active.id) else nil
		local ready = activeReady()
		if ready ~= wasReady then
			wasReady = ready
			render()
		end
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 4)
		if completeStroke then
			completeStroke.Thickness = completeThickness + if ready then pulse * 2 else 0
		end
		if not active or not project then
			activeText.Text = if ResearchClient.isSynced()
				then "Pick an upgrade to research. It keeps going while you're away."
				else "Loading your research..."
			activeTime.Text = ""
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		local left = math.max(0, active.endsAt - workspace:GetServerTimeNow())
		local progress = math.clamp(1 - left / active.seconds, 0, 1)
		activeText.Text = if ready then `{project.name} is ready!` else `Researching {project.name}`
		activeTime.Text = if ready then "" else Hud.time(left)
		fill.Size = UDim2.fromScale(progress, 1)
		local node = nodes[active.id]
		if node then
			if node.fill then
				node.fill.Size = UDim2.fromScale(progress, 1)
			end
			if node.stroke and ready then
				node.stroke.Color = COLORS.Ready:Lerp(Color3.new(1, 1, 1), pulse * 0.45)
				node.stroke.Thickness = strokeThickness + pulse * 2
			end
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
			if action.Active and not pending and selected then
				send(if activeReady() then "Complete" else "Start", selected)
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
		local completed: string? = nil
		local before = lastDone
		if before then
			for id in done do
				if not before[id] then
					completed = id
				end
			end
		end
		lastDone = table.clone(done)
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
