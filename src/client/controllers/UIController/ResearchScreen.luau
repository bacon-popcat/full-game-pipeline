-- ResearchScreen: the authored Research window (HUD.Research), opened by SideButtons.Research from
-- anywhere. Its tabs (Body.Tabs.<Category>) list Shared/Research's projects in that category,
-- lowest level first and finished ones last, each row cloned from Assets.UI.Research.Row;
-- Body.Active shows the running project's countdown, progress and Cancel. Whether a project can
-- start is Research.blocker's to say, with the wallet and inventory here; the server checks it
-- all again and answers with Notify and a fresh ResearchSync, which ends the wait.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local ResearchClient = require(Libraries.ResearchClient)
local UI = require(Libraries.UI)

local CATEGORIES = { "Farming", "Automation", "Economy", "Tools", "Crafting" }
-- The item each line of projects shows as its icon, by the id's leading word (Belts1 -> Belts);
-- crafting projects show the recipe they unlock instead.
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
-- How much a finished row fades, so the ones left to do stand out.
local DONE_FADE = 0.5

type Row = {
	project: Research.Project,
	frame: Frame,
	needs: TextLabel,
	start: TextButton,
	label: TextLabel,
	transparency: number,
	textTransparency: number,
}

local ResearchScreen = {}

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

function ResearchScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Research.Body.List", "ScrollingFrame")
	local activeText = Hud.find(hud, "Research.Body.Active.Text", "TextLabel")
	local activeTime = Hud.find(hud, "Research.Body.Active.Time", "TextLabel")
	local fill = Hud.find(hud, "Research.Body.Active.Bar.Fill", "Frame")
	local cancel = Hud.find(hud, "Research.Body.Active.Cancel", "TextButton")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Research.Row", "Frame")
	if
		not list
		or not list:IsA("ScrollingFrame")
		or not activeText
		or not activeText:IsA("TextLabel")
		or not activeTime
		or not activeTime:IsA("TextLabel")
		or not fill
		or not fill:IsA("Frame")
		or not cancel
		or not cancel:IsA("TextButton")
		or not template
		or not template:IsA("Frame")
	then
		return
	end
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local trove = Trove.new()
	local rowTrove = Trove.new()
	local rows: { Row } = {}
	local current = CATEGORIES[1]
	local pending = false
	local tabs: { [string]: TextButton } = {}
	local tabLooks: { [TextButton]: { transparency: number, color: Color3 } } = {}

	local function render()
		local economy = EconomyClient.get()
		local snapshot = ResearchClient.get()
		local done = ResearchClient.done()
		local activeId = if snapshot.active then snapshot.active.id else nil
		local speed = snapshot.bonuses.researchSpeed or 0
		for _, row in rows do
			local project = row.project
			local blocked = Research.blocker(project, done, economy.level, activeId)
			local items, hasItems = itemsOf(project)
			local enoughCoins = economy.coins >= project.coins
			local enabled = not pending and blocked == nil and enoughCoins and hasItems
			local time = duration(Research.duration(project, speed))
			row.needs.Text = if done[project.id]
				then "Researched"
				elseif activeId == project.id then "Researching now"
				elseif blocked and blocked ~= "Another project is running" then blocked
				elseif items ~= "" then `{time}  +  {items}`
				else time
			row.start.Active = enabled
			row.start.Selectable = enabled
			row.start.BackgroundTransparency = if enabled
				then row.transparency
				else row.transparency + (1 - row.transparency) * 0.5
			row.label.TextTransparency = if enabled
				then row.textTransparency
				else row.textTransparency + (1 - row.textTransparency) * 0.5
			row.label.Text = if pending
				then "..."
				elseif done[project.id] then "Done"
				elseif activeId == project.id then "Running"
				elseif blocked == "Another project is running" then "Busy"
				elseif blocked then "Locked"
				elseif not enoughCoins then "Need coins"
				elseif not hasItems then "Need items"
				else "Research"
		end
		cancel.Visible = activeId ~= nil
		cancel.Active = activeId ~= nil and not pending
	end

	-- The running project's countdown and bar, every quarter second while it runs.
	local function tick()
		local active = ResearchClient.get().active
		local project = if active then Research.get(active.id) else nil
		if not active or not project then
			activeText.Text = if ResearchClient.isSynced()
				then "Pick a project to research. It keeps going while you're away."
				else "Loading your research..."
			activeTime.Text = ""
			fill.Size = UDim2.fromScale(0, 1)
			return
		end
		local left = math.max(0, active.endsAt - workspace:GetServerTimeNow())
		activeText.Text = `Researching {project.name}`
		activeTime.Text = if left > 0 then Hud.time(left) else "Finishing..."
		fill.Size = UDim2.fromScale(math.clamp(1 - left / active.seconds, 0, 1), 1)
	end

	local function build()
		rowTrove:Clean()
		table.clear(rows)
		local done = ResearchClient.done()
		local shown = {}
		for index, project in Research.PROJECTS do
			if project.category == current then
				table.insert(shown, { project = project, index = index })
			end
		end
		table.sort(shown, function(a, b)
			local aDone, bDone = done[a.project.id] == true, done[b.project.id] == true
			if aDone ~= bDone then
				return bDone
			end
			return if a.project.level ~= b.project.level then a.project.level < b.project.level else a.index < b.index
		end)
		for order, entry in shown do
			local project = entry.project
			local frame = template:Clone()
			local icon = Hud.find(frame, "Icon", "ViewportFrame")
			local name = Hud.find(frame, "Name", "TextLabel")
			local description = Hud.find(frame, "Description", "TextLabel")
			local cost = Hud.find(frame, "Cost", "TextLabel")
			local needs = Hud.find(frame, "Needs", "TextLabel")
			local start = Hud.find(frame, "Start", "TextButton")
			local label = Hud.find(frame, "Start.Label", "TextLabel")
			if
				not icon
				or not icon:IsA("ViewportFrame")
				or not name
				or not name:IsA("TextLabel")
				or not description
				or not description:IsA("TextLabel")
				or not cost
				or not cost:IsA("TextLabel")
				or not needs
				or not needs:IsA("TextLabel")
				or not start
				or not start:IsA("TextButton")
				or not label
				or not label:IsA("TextLabel")
			then
				frame:Destroy()
				continue
			end
			name.Text = project.name
			description.Text = project.description
			cost.Text = Hud.number(project.coins)
			ItemIcon.show(icon, iconOf(project))
			if done[project.id] then
				frame.BackgroundTransparency += (1 - frame.BackgroundTransparency) * DONE_FADE
				icon.ImageTransparency = DONE_FADE
			end
			frame.Name = project.id
			frame.LayoutOrder = order
			frame.Parent = list
			table.insert(rows, {
				project = project,
				frame = frame,
				needs = needs,
				start = start,
				label = label,
				transparency = start.BackgroundTransparency,
				textTransparency = label.TextTransparency,
			})
			rowTrove:Add(frame)
			rowTrove:Add(function()
				ItemIcon.clear(icon)
			end)
			rowTrove:Add(UI.bindButton(start, {
				onActivate = function()
					if start.Active and not pending then
						pending = true
						render()
						Remotes.Research:FireServer("Start", project.id)
					end
				end,
			}))
		end
		render()
	end

	local function show(category: string)
		current = category
		for name, tab in tabs do
			local look = tabLooks[tab]
			local selected = name == category
			tab.BackgroundTransparency = if selected then look.transparency else 0.6
			tab.TextColor3 = if selected then look.color else look.color:Lerp(Color3.new(0.5, 0.5, 0.5), 0.5)
		end
		list.CanvasPosition = Vector2.zero
		build()
	end

	local window = HubWindow.bind(hud, "Research", {}, render)
	if not window then
		return
	end
	for _, category in CATEGORIES do
		local tab = Hud.find(hud, "Research.Body.Tabs." .. category, "TextButton")
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
	trove:Add(UI.bindButton(cancel, {
		onActivate = function()
			if cancel.Active and not pending then
				pending = true
				render()
				Remotes.Research:FireServer("Cancel")
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
	show(current)
	-- Every request is answered with a sync, which also ends the wait; a finish re-sorts the list.
	trove:Connect(ResearchClient.changed, function()
		pending = false
		build()
		tick()
	end)
	trove:Connect(EconomyClient.changed, render)
	trove:Connect(InventoryClient.changed, render)
	local elapsed = 1
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed >= 0.25 and window.isOpen() then
			elapsed = 0
			tick()
		end
	end)
	trove:Connect(hud.Destroying, function()
		rowTrove:Destroy()
		trove:Destroy()
		table.clear(rows)
	end)
end

return ResearchScreen
