-- ResearchScreen: the Research window, a full-screen black view of the upgrade trees. It lives in
-- its own ScreenGui (StarterGui.ResearchView, authored) and, while open, hides the HUD, player
-- list and chat (HudVisibility), leaving the close button, the category tabs along the top and
-- the running project's strip along the bottom. SideButtons.Research opens it from anywhere.
--
-- Each tab draws its tree on Research.Canvas: one tile per project (Assets.UI.Research.Node),
-- in columns by how many projects lead to it, hanging off its latest need. Children continuing
-- its line (Yield1 -> Yield2) run along its row; each other child starts a row below. Each need
-- in the same tree is joined to it by an elbowed line (Assets.UI.Research.Link), lit green once
-- the need is done. A tile's border says its state: green done, yellow can start, red locked,
-- blue running (with a bar), gold and pulsing ready to complete. Open and locked tiles show
-- a short coin-cost badge, red when the wallet falls short, otherwise in its authored colour.
--
-- Pressing a tile selects it: the canvas glides to centre it and Research.Info stands above it
-- with its name, description, level, cost, time and items, and an Action button (Research,
-- Complete...). Hovering another tile shows the same in Research.Tooltip above that one,
-- without the button. The canvas pans by dragging or the gamepad's right stick, and zooms
-- with the wheel, a two-finger pinch, or ButtonL2/ButtonR2. Pinching never also drags it.
--
-- Body.Active shows the running project's countdown and Cancel; once its timer runs out its
-- Complete button glows. Completing a project bursts its tile (a flash, a ring and sparks, and
-- its lines lighting up); FxController plays the world effect round the player. Whether a
-- project can start is Research.blocker's to say, with the wallet and inventory here; the server
-- checks it all again and answers with Notify and a fresh ResearchSync, which ends the wait.
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

local CATEGORIES = { "Farming", "Automation", "Economy", "Tools", "Crafting" }
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
-- Pixels between tile centres across and down, and round the tree.
local COLUMN, ROW, MARGIN = 140, 136, 80
local COLORS = {
	Done = Color3.fromRGB(120, 220, 110),
	Ready = Color3.fromRGB(255, 214, 110),
	Running = Color3.fromRGB(120, 180, 240),
	Open = Color3.fromRGB(240, 210, 90),
	Locked = Color3.fromRGB(196, 78, 78),
}
-- How far a locked tile's item and name fade.
local LOCKED_FADE = 0.55
-- The canvas: how quickly it glides to where it is going (per second), how far the wheel zooms,
-- and pixels below the screen's middle the selected tile sits, leaving room for its info.
local GLIDE = 8
local NEAREST, FARTHEST = 0.6, 1.4
local SIT_BELOW = 90
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
-- Pixels between a tile's top and the info above it, kept clear of the screen's edges, and of
-- the tabs along the top.
local INFO_GAP, EDGE, TOP = 10, 12, 70
-- The completion burst: sparks, and how far they fly.
local SPARKS, SPARK_REACH = 16, 110
local SPARK_COLORS = { COLORS.Ready, COLORS.Done, Color3.fromRGB(255, 246, 222) }

type State = "Done" | "Ready" | "Running" | "Open" | "Locked"
type Node = {
	project: Research.Project,
	frame: GuiButton,
	stroke: UIStroke?,
	icon: ViewportFrame,
	name: TextLabel,
	cost: TextLabel?,
	progress: GuiObject?,
	fill: GuiObject?,
	centre: Vector2,
	state: State,
}
type Link = { need: string, pieces: { Frame } }
type Panel = {
	frame: GuiObject,
	name: TextLabel,
	description: TextLabel,
	level: TextLabel,
	cost: TextLabel,
	needs: TextLabel,
}

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

-- Where each project of `category` sits in its tree, as a column and a row, and the tree's
-- size in columns and rows.
local function layout(category: string): ({ [string]: Vector2 }, Vector2)
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
	local columns = 0
	for _, project in members do
		cells[project.id] = Vector2.new(depth[project.id], rows[project.id])
		columns = math.max(columns, depth[project.id] + 1)
	end
	return cells, Vector2.new(columns, nextRow)
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
	return { frame = frame, name = name, description = description, level = level, cost = cost, needs = needs }
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
	local activeText = Hud.find(view, "Research.Body.Active.Text", "TextLabel")
	local activeTime = Hud.find(view, "Research.Body.Active.Time", "TextLabel")
	local fill = Hud.find(view, "Research.Body.Active.Bar.Fill", "Frame")
	local cancel = Hud.find(view, "Research.Body.Active.Cancel", "TextButton")
	local completeButton = Hud.find(view, "Research.Body.Active.Complete", "TextButton")
	local nodeTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Research.Node", "GuiButton")
	local linkTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Research.Link", "Frame")
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
	local current = CATEGORIES[1]
	local selected: string? = nil
	local hovered: string? = nil
	local pending = false
	local shown = false
	local tabs: { [string]: TextButton } = {}
	local tabLooks: { [TextButton]: { transparency: number, color: Color3 } } = {}
	-- Baselines, captured from what is authored.
	local nodeSize = nodeTemplate.Size
	local templateCost = nodeTemplate:FindFirstChild("Cost")
	local nodeCostColor = if templateCost and templateCost:IsA("TextLabel") then templateCost.TextColor3 else nil
	local templateStroke = nodeTemplate:FindFirstChildOfClass("UIStroke")
	local strokeThickness = if templateStroke then templateStroke.Thickness else 3
	local linkColor = linkTemplate.BackgroundColor3
	local linkThickness = math.max(1, linkTemplate.Size.Y.Offset)
	local actionLook = { transparency = action.BackgroundTransparency, text = actionLabel.TextTransparency }
	local costColor = info.cost.TextColor3
	local levelColor = info.level.TextColor3
	local completeStroke = completeButton:FindFirstChildOfClass("UIStroke")
	local completeThickness = if completeStroke then completeStroke.Thickness else 1
	-- The finished ids at the last sync, so a newly completed one can burst.
	local lastDone: { [string]: boolean }? = nil
	-- The canvas point the screen centres on, where it is going and where it is, and its zoom.
	local focus, shownFocus = Vector2.zero, Vector2.zero
	local scale = zoom.Scale
	local press: Vector2? = nil
	local dragging = false
	local touches: { InputObject } = {}
	local pinchDistance: number? = nil

	local function fillPanel(panel: Panel, project: Research.Project)
		local economy = EconomyClient.get()
		local snapshot = ResearchClient.get()
		local done = ResearchClient.done()
		local activeId = if snapshot.active then snapshot.active.id else nil
		local blocked = Research.blocker(project, done, economy.level, activeId)
		local items, hasItems = itemsOf(project)
		local state = stateOf(project)
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
		if state == "Ready" then
			table.insert(lines, "Finished! Complete it to get its bonus.")
		elseif state == "Running" then
			local active = snapshot.active
			local left = if active then math.max(0, active.endsAt - workspace:GetServerTimeNow()) else 0
			table.insert(lines, `{Hud.time(left)} left`)
		elseif state ~= "Done" then
			table.insert(lines, `Takes {duration(Research.duration(project, snapshot.bonuses.researchSpeed or 0))}`)
			if items ~= "" then
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

	local function paintTiles()
		local done = ResearchClient.done()
		local coins = EconomyClient.get().coins
		for _, node in nodes do
			local state = stateOf(node.project)
			node.state = state
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
			for _, piece in link.pieces do
				piece.BackgroundColor3 = if done[link.need] then COLORS.Done else linkColor
			end
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
	end

	local function selectProject(id: string, snap: boolean?)
		local node = nodes[id]
		if not node then
			return
		end
		selected = id
		focus = node.centre
		if snap or GuiService.ReducedMotionEnabled then
			shownFocus = focus
		end
		render()
	end

	-- A straight piece of line on the canvas from `a` to `b` (one shared, so it runs across or down).
	local function segment(a: Vector2, b: Vector2): Frame
		local frame = linkTemplate:Clone()
		local low = a:Min(b)
		local size = b - a
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(low.X - linkThickness / 2, low.Y - linkThickness / 2)
		frame.Size = UDim2.fromOffset(math.abs(size.X) + linkThickness, math.abs(size.Y) + linkThickness)
		frame.Parent = linkLayer
		treeTrove:Add(frame)
		return frame
	end

	local function build()
		treeTrove:Clean()
		table.clear(nodes)
		table.clear(links)
		hovered = nil
		local cells, extent = layout(current)
		local width = nodeSize.X.Offset
		local function centre(id: string): Vector2
			local cell = cells[id]
			return Vector2.new(MARGIN + cell.X * COLUMN, MARGIN + cell.Y * ROW)
		end
		canvas.Size = UDim2.fromOffset(MARGIN * 2 + (extent.X - 1) * COLUMN, MARGIN * 2 + (extent.Y - 1) * ROW)
		for _, project in Research.PROJECTS do
			if not cells[project.id] then
				continue
			end
			-- Elbowed lines from each need in this tree: across to the gap before this tile,
			-- down to its row, and across into it.
			local to = centre(project.id)
			for _, id in project.needs do
				if cells[id] then
					local from = centre(id)
					local startX, endX = from.X + width / 2, to.X - width / 2
					local pieces = {}
					if from.Y == to.Y then
						table.insert(pieces, segment(Vector2.new(startX, from.Y), Vector2.new(endX, to.Y)))
					else
						local turn = endX - (COLUMN - width) / 2
						table.insert(pieces, segment(Vector2.new(startX, from.Y), Vector2.new(turn, from.Y)))
						table.insert(pieces, segment(Vector2.new(turn, from.Y), Vector2.new(turn, to.Y)))
						table.insert(pieces, segment(Vector2.new(turn, to.Y), Vector2.new(endX, to.Y)))
					end
					table.insert(links, { need = id, pieces = pieces })
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

	-- The tile a tab opens on: the running project, else the first that can start, else the root.
	local function pickIn(category: string): string?
		local active = ResearchClient.get().active
		local activeProject = if active then Research.get(active.id) else nil
		if activeProject and activeProject.category == category then
			return activeProject.id
		end
		local first: string? = nil
		for _, project in Research.PROJECTS do
			if project.category == category then
				first = first or project.id
				if stateOf(project) == "Open" then
					return project.id
				end
			end
		end
		return first
	end

	local function show(category: string, snap: boolean?)
		current = category
		for name, tab in tabs do
			local look = tabLooks[tab]
			local isCurrent = name == category
			tab.BackgroundTransparency = if isCurrent then look.transparency else 0.6
			tab.TextColor3 = if isCurrent then look.color else look.color:Lerp(Color3.new(0.5, 0.5, 0.5), 0.5)
		end
		build()
		local pick = pickIn(category)
		if pick then
			selectProject(pick, snap)
		end
	end

	-- The completion burst on a tile: it pops, a gold flash and a green ring spread from it,
	-- sparks fly out, and the lines out of it light up one after another. Transient frames.
	local function burst(id: string)
		local node = nodes[id]
		if not node then
			return
		end
		local frame = node.frame
		local at = frame.Position
		local reduced = GuiService.ReducedMotionEnabled
		local function grow(by: number): UDim2
			return UDim2.fromOffset(nodeSize.X.Offset * by, nodeSize.Y.Offset * by)
		end
		local function disc(color: Color3, transparency: number): Frame
			local circle = Instance.new("Frame")
			circle.AnchorPoint = Vector2.new(0.5, 0.5)
			circle.Position = at
			circle.Size = nodeSize
			circle.BackgroundColor3 = color
			circle.BackgroundTransparency = transparency
			circle.BorderSizePixel = 0
			circle.ZIndex = frame.ZIndex + 5
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = circle
			circle.Parent = nodeLayer
			treeTrove:Add(circle)
			return circle
		end
		local flash = disc(COLORS.Ready, 0.15)
		TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = if reduced then nodeSize else grow(2.6),
			BackgroundTransparency = 1,
		}):Play()
		local ring = disc(COLORS.Done, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.Done
		stroke.Thickness = 4
		stroke.Parent = ring
		TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = if reduced then nodeSize else grow(3.6),
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.8), { Transparency = 1, Thickness = 1 }):Play()
		task.delay(0.85, function()
			flash:Destroy()
			ring:Destroy()
		end)
		if not reduced then
			TweenService:Create(frame, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = grow(1.22),
			}):Play()
			task.delay(0.16, function()
				if frame.Parent then
					TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = nodeSize }):Play()
				end
			end)
			for index = 1, SPARKS do
				local spark = Instance.new("Frame")
				local side = math.random(6, 11)
				spark.AnchorPoint = Vector2.new(0.5, 0.5)
				spark.Position = at
				spark.Size = UDim2.fromOffset(side, side)
				spark.Rotation = 45
				spark.BorderSizePixel = 0
				spark.BackgroundColor3 = SPARK_COLORS[index % #SPARK_COLORS + 1]
				spark.ZIndex = frame.ZIndex + 6
				spark.Parent = nodeLayer
				treeTrove:Add(spark)
				local angle = (index / SPARKS + math.random() * 0.06) * math.pi * 2
				local reach = SPARK_REACH * (0.55 + math.random() * 0.45)
				local seconds = 0.6 + math.random() * 0.3
				TweenService:Create(spark, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Position = at + UDim2.fromOffset(math.cos(angle) * reach, math.sin(angle) * reach - 16),
					Size = UDim2.fromOffset(1, 1),
					Rotation = 45 + math.random(-90, 90),
					BackgroundTransparency = 1,
				}):Play()
				task.delay(seconds, function()
					spark:Destroy()
				end)
			end
		end
		local delay = 0.2
		for _, link in links do
			if link.need == id then
				for _, piece in link.pieces do
					piece.BackgroundColor3 = linkColor
					task.delay(delay, function()
						if piece.Parent then
							TweenService:Create(piece, TweenInfo.new(0.25), { BackgroundColor3 = COLORS.Done }):Play()
						end
					end)
					delay += 0.08
				end
			end
		end
	end

	local function enter()
		shown = true
		HudVisibility.hide("Research", true, true)
		hovered = nil
		show(current, true)
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

	-- Puts a panel just above a tile, kept on screen.
	local function place(panel: Panel, id: string?)
		local node = if id then nodes[id] else nil
		if not node then
			panel.frame.Visible = false
			return
		end
		panel.frame.Visible = true
		local frame = node.frame
		local origin = root.AbsolutePosition
		local top = frame.AbsolutePosition + Vector2.new(frame.AbsoluteSize.X / 2, 0) - origin
		local size = panel.frame.AbsoluteSize
		local screen = root.AbsoluteSize
		local x = math.clamp(top.X, size.X / 2 + EDGE, math.max(size.X / 2 + EDGE, screen.X - size.X / 2 - EDGE))
		local y = math.clamp(top.Y - INFO_GAP, size.Y + TOP, math.max(size.Y + TOP, screen.Y - EDGE))
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
		shownFocus = shownFocus:Lerp(focus, 1 - math.exp(-dt * GLIDE))
		zoom.Scale = scale
		local middle = root.AbsoluteSize / 2 + Vector2.new(0, SIT_BELOW)
		local offset = middle - shownFocus * scale
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

	local window = HubWindow.bind(view, "Research", {}, render, nil, false)
	if not window then
		return
	end
	for _, category in CATEGORIES do
		local tab = Hud.find(view, "Research.Body.Tabs." .. category, "TextButton")
		if tab and tab:IsA("TextButton") then
			tabs[category] = tab
			tabLooks[tab] = { transparency = tab.BackgroundTransparency, color = tab.TextColor3 }
			trove:Add(UI.bindButton(tab, {
				onActivate = function()
					show(category)
				end,
			}))
		end
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
			press = nil
		end
	end)
	show(current, true)
	-- Every request is answered with a sync, which also ends the wait. A project that has just
	-- been completed is glided to and bursts.
	trove:Connect(ResearchClient.changed, function()
		pending = false
		local done = ResearchClient.done()
		local completed: string? = nil
		if lastDone then
			for id in done do
				if not lastDone[id] then
					completed = id
				end
			end
		end
		lastDone = table.clone(done)
		local project = if completed then Research.get(completed) else nil
		if shown and project and completed then
			if project.category ~= current then
				show(project.category)
			end
			selectProject(completed)
			burst(completed)
		else
			render()
		end
	end)
	trove:Connect(EconomyClient.changed, render)
	trove:Connect(InventoryClient.changed, render)
	trove:Connect(RunService.RenderStepped, function(dt: number)
		local open = window.isOpen()
		if open ~= shown then
			if open then
				enter()
			else
				leave()
			end
		end
		if shown then
			step(dt)
		end
	end)
	trove:Connect(view.Destroying, function()
		if shown then
			leave()
		end
		treeTrove:Destroy()
		trove:Destroy()
	end)
end

return ResearchScreen
