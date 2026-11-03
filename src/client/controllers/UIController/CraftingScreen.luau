-- CraftingScreen: the authored Crafting window (HUD.Crafting) of the player's own Crafting
-- Bench, opened with the interact key (Controls.INTERACT; an on-screen Open button on touch)
-- while aiming at one in reach, and closed on walking away. It lists Shared/Crafting's recipes,
-- one Assets.UI.Crafting.Row each, the ones research hasn't unlocked yet last; Body.Tabs.Times1,
-- Times5 and Times10 pick how many times a press crafts. Crafting.blocker says what's missing
-- from this player's inventory and research; the server checks it all again and answers with
-- Notify.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Build = require(ReplicatedStorage.Shared.Build)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Aim = require(Libraries.Aim)
local Controls = require(Libraries.Controls)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local ResearchClient = require(Libraries.ResearchClient)
local UI = require(Libraries.UI)

local INTERACT_ACTION = "CraftingInteract"
local TOUCH_ACTION = "CraftingOpen"
-- Studs the aim reaches to find a bench, as far as the hover panel looks.
local AIM_DISTANCE = 150
local TIMES = { Times1 = 1, Times5 = 5, Times10 = 10 }
-- Seconds a press waits for the server's answer before the buttons wake again anyway.
local PENDING_FOR = 1.5

type Row = {
	recipe: Crafting.Recipe,
	frame: Frame,
	name: TextLabel,
	inputs: TextLabel,
	status: TextLabel,
	have: TextLabel,
	craft: TextButton,
	label: TextLabel,
	transparency: number,
	textTransparency: number,
}

local CraftingScreen = {}

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

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

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Whether a bench is the player's own and close enough to work at, as CraftingService judges it.
local function inReach(bench: Model): boolean
	local from = rootPosition()
	local origin, rotation = bench:GetAttribute("Origin"), bench:GetAttribute("Rotation")
	if not from or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return false
	end
	local footprint = Build.footprint(Crafting.BENCH, rotation)
	return footprint ~= nil
		and bench:GetAttribute("Owner") == player.UserId
		and bench:IsDescendantOf(workspace)
		and Build.inReach(from, origin, footprint)
end

-- The player's own bench under the aim and within reach.
local function aimed(): Model?
	local character = player.Character
	raycastParams.FilterDescendantsInstances = if character then { character } else {}
	local result = Aim.castArt(raycastParams, AIM_DISTANCE)
	local bench = if result then Aim.modelUnder(result.Instance, "Placed") else nil
	return if bench and bench:GetAttribute("ItemId") == Crafting.BENCH and inReach(bench) then bench else nil
end

-- "4 Wood Planks, 1 Iron Bar" for `times` crafts.
local function inputsOf(recipe: Crafting.Recipe, times: number): string
	local names = {}
	for itemId, need in recipe.inputs do
		table.insert(names, `{need * times} {Inventory.getItem(itemId).name}`)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

-- How many times the inventory could craft it now, ignoring room for the output.
local function makeable(recipe: Crafting.Recipe): number
	local most = math.huge
	for itemId, need in recipe.inputs do
		most = math.min(most, countOf(itemId) // need)
	end
	return if most == math.huge then 0 else most
end

function CraftingScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Crafting.Body.List", "ScrollingFrame")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Crafting.Row", "Frame")
	if not list or not list:IsA("ScrollingFrame") or not template or not template:IsA("Frame") then
		return
	end
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local trove = Trove.new()
	local rowTrove = Trove.new()
	local rows: { Row } = {}
	local times = 1
	local pendingSince: number? = nil
	local bench: Model? = nil
	local tabs: { [string]: TextButton } = {}
	local tabLooks: { [TextButton]: { transparency: number, color: Color3 } } = {}

	local function render()
		local done = ResearchClient.done()
		local pending = pendingSince ~= nil
		for _, row in rows do
			local recipe = row.recipe
			local locked = recipe.research ~= nil and not done[recipe.research]
			local blocked = Crafting.blocker(recipe, times, done, countOf)
			local enabled = not pending and blocked == nil
			local item = Inventory.getItem(recipe.output)
			row.name.Text = `{item.name} x{recipe.count * times}`
			row.inputs.Text = inputsOf(recipe, times)
			local project = if locked and recipe.research then Research.get(recipe.research) else nil
			-- Locked: which project to research, named in full since the label is short.
			row.status.Text = if locked then "Research" else ""
			row.have.Text = if project then project.name else `Can make {makeable(recipe)}`
			row.craft.Active = enabled
			row.craft.Selectable = enabled
			row.craft.BackgroundTransparency = if enabled
				then row.transparency
				else row.transparency + (1 - row.transparency) * 0.5
			row.label.TextTransparency = if enabled
				then row.textTransparency
				else row.textTransparency + (1 - row.textTransparency) * 0.5
			row.label.Text = if pending
				then "..."
				elseif locked then "Locked"
				elseif blocked then "Need items"
				else "Craft"
		end
	end

	local function build()
		rowTrove:Clean()
		table.clear(rows)
		local done = ResearchClient.done()
		local order = {}
		for index, recipe in Crafting.RECIPES do
			local locked = recipe.research ~= nil and not done[recipe.research]
			table.insert(order, { recipe = recipe, rank = (if locked then 1000 else 0) + index })
		end
		table.sort(order, function(a, b)
			return a.rank < b.rank
		end)
		for position, entry in order do
			local recipe = entry.recipe
			local frame = template:Clone()
			local icon = Hud.find(frame, "Icon", "ViewportFrame")
			local name = Hud.find(frame, "Name", "TextLabel")
			local inputs = Hud.find(frame, "Inputs", "TextLabel")
			local status = Hud.find(frame, "Status", "TextLabel")
			local have = Hud.find(frame, "Have", "TextLabel")
			local craft = Hud.find(frame, "Craft", "TextButton")
			local label = Hud.find(frame, "Craft.Label", "TextLabel")
			if
				not icon
				or not icon:IsA("ViewportFrame")
				or not name
				or not name:IsA("TextLabel")
				or not inputs
				or not inputs:IsA("TextLabel")
				or not status
				or not status:IsA("TextLabel")
				or not have
				or not have:IsA("TextLabel")
				or not craft
				or not craft:IsA("TextButton")
				or not label
				or not label:IsA("TextLabel")
			then
				frame:Destroy()
				continue
			end
			ItemIcon.show(icon, recipe.output)
			frame.Name = recipe.id
			frame.LayoutOrder = position
			frame.Parent = list
			table.insert(rows, {
				recipe = recipe,
				frame = frame,
				name = name,
				inputs = inputs,
				status = status,
				have = have,
				craft = craft,
				label = label,
				transparency = craft.BackgroundTransparency,
				textTransparency = label.TextTransparency,
			})
			rowTrove:Add(frame)
			rowTrove:Add(function()
				ItemIcon.clear(icon)
			end)
			rowTrove:Add(UI.bindButton(craft, {
				onActivate = function()
					if craft.Active and not pendingSince then
						pendingSince = os.clock()
						render()
						Remotes.Craft:FireServer(recipe.id, times)
					end
				end,
			}))
		end
		render()
	end

	local function pick(name: string)
		times = TIMES[name] or 1
		for each, tab in tabs do
			local look = tabLooks[tab]
			local selected = each == name
			tab.BackgroundTransparency = if selected then look.transparency else 0.6
			tab.TextColor3 = if selected then look.color else look.color:Lerp(Color3.new(0.5, 0.5, 0.5), 0.5)
		end
		render()
	end

	local window = HubWindow.bind(hud, "Crafting", {}, render)
	if not window then
		return
	end
	for name in TIMES do
		local tab = Hud.find(hud, "Crafting.Body.Tabs." .. name, "TextButton")
		if tab and tab:IsA("TextButton") then
			tabs[name] = tab
			tabLooks[tab] = { transparency = tab.BackgroundTransparency, color = tab.TextColor3 }
			trove:Add(UI.bindButton(tab, {
				onActivate = function()
					pick(name)
				end,
			}))
		end
	end

	local function toggle(): boolean
		if window.isOpen() then
			window.close()
			bench = nil
			return true
		end
		local target = aimed()
		if not target then
			return false
		end
		bench = target
		window.open()
		return true
	end
	local function onInteract(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		-- Only this window's own key presses: an open machine panel or a machine under the aim
		-- has its own binding, which passes when it isn't aimed at one.
		if not window.isOpen() and not aimed() then
			return Enum.ContextActionResult.Pass
		end
		return if toggle() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	ContextActionService:BindAction(INTERACT_ACTION, onInteract, false, table.unpack(Controls.INTERACT))
	local touchShown = false
	local function showTouchButton(shown: boolean)
		if shown == touchShown then
			return
		end
		touchShown = shown
		if shown then
			ContextActionService:BindAction(TOUCH_ACTION, onInteract, true)
			ContextActionService:SetTitle(TOUCH_ACTION, "Open")
		else
			ContextActionService:UnbindAction(TOUCH_ACTION)
		end
	end
	trove:Add(function()
		ContextActionService:UnbindAction(INTERACT_ACTION)
		ContextActionService:UnbindAction(TOUCH_ACTION)
	end)

	pick("Times1")
	build()
	trove:Connect(ResearchClient.changed, build)
	trove:Connect(InventoryClient.changed, function()
		pendingSince = nil
		render()
	end)
	-- Every craft is answered with a toast, which also ends the wait on a refusal.
	trove:Connect(Remotes.Notify.OnClientEvent, function()
		if pendingSince then
			pendingSince = nil
			render()
		end
	end)
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		if pendingSince and os.clock() - pendingSince > PENDING_FOR then
			pendingSince = nil
			render()
		end
		if window.isOpen() and (not bench or not inReach(bench)) then
			window.close()
			bench = nil
		end
		local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
		showTouchButton(touch and not window.isOpen() and aimed() ~= nil)
	end)
	trove:Connect(hud.Destroying, function()
		rowTrove:Destroy()
		trove:Destroy()
		table.clear(rows)
	end)
end

return CraftingScreen
