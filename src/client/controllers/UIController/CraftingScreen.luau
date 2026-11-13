-- CraftingScreen: the authored Crafting window (HUD.Crafting), toggled from anywhere by the side
-- Crafting button (SideButtons.Crafting) or the crafting key (Controls.TOGGLE_CRAFTING). Laid out
-- like a workshop catalogue:
--
--   * Body.Categories: one Assets.UI.Crafting.Category button per category that has recipes
--     (Craftable, All, then by the output's item kind).
--   * Body.Main: a Search box and a Grid of Assets.UI.Crafting.Card, one per Shared/Crafting
--     recipe; a card shows its output, how many one craft makes, `Ready` when the inventory can
--     make it now and `Lock` while research or the crafting tier hasn't unlocked it. Hovering one
--     shows HUD.Crafting.Tooltip (name, description, and each input as have / need).
--   * Header.Title names the crafting tier ("Workshop"). Header.Upgrade opens UpgradePanel, which
--     lays out what the next tier (Crafting.TIERS) needs, the level and each input as have / need,
--     and its Confirm button spends them. Tier upgrades are recipes (Crafting.RECIPES, `upgrade`)
--     but have no card in the grid: the server takes the same Craft request for them.
--   * Body.Details: the picked recipe's output turning in Preview, its Ingredients (one
--     Assets.UI.Crafting.Ingredient each, have / need in green or red), a Status line saying what
--     is missing, the Amount stepper (1 to Crafting.MAX_TIMES crafts) and Craft.
--
-- Crafting.blocker says what's missing from this player's inventory, research, level and crafting
-- tier (the BenchTier attribute CraftingService sets); the server checks it all again and answers
-- with Notify. A craft that goes through pulses the preview and throws sparks from the button; one
-- refused, or a press on a button that can't craft, shakes the button and flashes Status red
-- (Flair).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local TextColors = require(ReplicatedStorage.Shared.TextColors)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Controls = require(Libraries.Controls)
local EconomyClient = require(Libraries.EconomyClient)
local Flair = require(Libraries.Flair)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local ResearchClient = require(Libraries.ResearchClient)
local TabSlide = require(Libraries.TabSlide)
local Turntable = require(Libraries.Turntable)
local UI = require(Libraries.UI)

local TOGGLE_ACTION = "CraftingToggle"
-- Seconds a press waits for the server's answer before the buttons wake again anyway.
local PENDING_FOR = 1.5
-- Pixels between the pointer and the hover card.
local TOOLTIP_OFFSET = Vector2.new(18, 14)
local ENOUGH = Color3.fromRGB(157, 220, 154)
local SHORT = Color3.fromRGB(240, 140, 130)
local DIMMED = Color3.fromRGB(130, 130, 145)

type Category = { name: string, shows: (Crafting.Recipe) -> boolean }
type Card = {
	recipe: Crafting.Recipe,
	button: TextButton,
	ready: GuiObject,
	lock: GuiObject,
	stroke: UIStroke?,
}

local CraftingScreen = {}

local player = Players.LocalPlayer
-- Set once the window is bound: whether it is open.
local isOpen: (() -> boolean)? = nil

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

local function craftingTier(): number
	return Crafting.sanitizeTier(player:GetAttribute("BenchTier"))
end

local function locked(recipe: Crafting.Recipe): boolean
	return Crafting.locked(recipe, ResearchClient.done(), craftingTier())
end

-- Why it can't be crafted `times` times now, or nil.
local function blockerOf(recipe: Crafting.Recipe, times: number): string?
	return Crafting.blocker(recipe, times, ResearchClient.done(), countOf, craftingTier(), EconomyClient.get().level)
end

-- How many times the inventory could craft it now, ignoring room for the output.
local function makeable(recipe: Crafting.Recipe): number
	local most = math.huge
	for itemId, need in recipe.inputs do
		most = math.min(most, countOf(itemId) // need)
	end
	return if most == math.huge then 0 else most
end

-- A recipe's inputs in a stable order: by item name.
local function inputsOf(recipe: Crafting.Recipe): { string }
	local ids = {}
	for itemId in recipe.inputs do
		table.insert(ids, itemId)
	end
	table.sort(ids, function(a, b)
		return Inventory.getItem(a).name < Inventory.getItem(b).name
	end)
	return ids
end

local function kindShows(kind: string): (Crafting.Recipe) -> boolean
	return function(recipe: Crafting.Recipe): boolean
		return recipe.upgrade == nil and Inventory.getItem(recipe.output).kind == kind
	end
end

local CATEGORIES: { Category } = {
	{
		name = "Craftable",
		shows = function(recipe: Crafting.Recipe): boolean
			return recipe.upgrade == nil and blockerOf(recipe, 1) == nil
		end,
	},
	{
		name = "All",
		shows = function(recipe: Crafting.Recipe): boolean
			return recipe.upgrade == nil
		end,
	},
	{ name = "Materials", shows = kindShows("Resource") },
	{ name = "Blocks", shows = kindShows("Block") },
	{ name = "Machines", shows = kindShows("Machine") },
}

function CraftingScreen.init(hud: ScreenGui)
	local templates = Hud.find(ReplicatedStorage, "Assets.UI.Crafting", "Folder")
	local paths = {
		categories = { "Body.Categories", "Frame" },
		search = { "Body.Main.Search.Box", "TextBox" },
		searchClear = { "Body.Main.Search.Clear", "GuiButton" },
		grid = { "Body.Main.Grid", "ScrollingFrame" },
		empty = { "Body.Main.Empty", "TextLabel" },
		itemName = { "Body.Details.ItemName", "TextLabel" },
		kind = { "Body.Details.Kind", "TextLabel" },
		preview = { "Body.Details.Preview", "ViewportFrame" },
		ingredients = { "Body.Details.Ingredients", "ScrollingFrame" },
		status = { "Body.Details.Status", "TextLabel" },
		minus = { "Body.Details.Amount.Minus", "GuiButton" },
		plus = { "Body.Details.Amount.Plus", "GuiButton" },
		max = { "Body.Details.Amount.Max", "GuiButton" },
		amount = { "Body.Details.Amount.Value", "TextBox" },
		craft = { "Body.Details.Craft", "TextButton" },
		craftLabel = { "Body.Details.Craft.Label", "TextLabel" },
		tooltip = { "Tooltip", "Frame" },
		tipName = { "Tooltip.ItemName", "TextLabel" },
		tipText = { "Tooltip.Description", "TextLabel" },
		tipLines = { "Tooltip.Lines", "Frame" },
		windowScale = { "UIScale", "UIScale" },
		upgrade = { "Header.Upgrade", "TextButton" },
		upgradeLabel = { "Header.Upgrade.Label", "TextLabel" },
		panel = { "UpgradePanel", "Frame" },
		panelTitle = { "UpgradePanel.Title", "TextLabel" },
		panelTier = { "UpgradePanel.Tier", "TextLabel" },
		panelText = { "UpgradePanel.Description", "TextLabel" },
		panelNeeds = { "UpgradePanel.Needs", "ScrollingFrame" },
		panelStatus = { "UpgradePanel.Status", "TextLabel" },
		confirm = { "UpgradePanel.Confirm", "TextButton" },
		confirmLabel = { "UpgradePanel.Confirm.Label", "TextLabel" },
	}
	-- Every node is required: a place missing one keeps the rest of the HUD working, without crafting.
	local nodes: { [string]: any } = {}
	for key, spec in paths do
		local node = Hud.find(hud, "Crafting." .. spec[1], spec[2])
		if not node then
			return
		end
		nodes[key] = node
	end
	if not templates then
		return
	end
	local categoryTemplate = Hud.find(templates, "Category", "TextButton")
	local cardTemplate = Hud.find(templates, "Card", "TextButton")
	local ingredientTemplate = Hud.find(templates, "Ingredient", "Frame")
	local lineTemplate = Hud.find(templates, "TooltipLine", "Frame")
	if not categoryTemplate or not cardTemplate or not ingredientTemplate or not lineTemplate then
		return
	end
	assert(categoryTemplate:IsA("TextButton") and cardTemplate:IsA("TextButton"), "Category and Card are TextButtons")
	assert(ingredientTemplate:IsA("Frame") and lineTemplate:IsA("Frame"), "Ingredient and TooltipLine are Frames")

	local trove = Trove.new()
	local turntable = Turntable.bind(nodes.preview)
	trove:Add(turntable.destroy)
	-- The picked category's highlight, sliding between them, in the window's accent colour.
	local accent = Hud.find(hud, "Crafting.Accent", "Frame")
	local pickCategory, cleanupCategory =
		TabSlide.bind(if accent and accent:IsA("Frame") then accent.BackgroundColor3 else Color3.new(1, 1, 1))
	trove:Add(cleanupCategory)
	local cards: { Card } = {}
	local categoryButtons: { [string]: TextButton } = {}
	local categoryLook = {
		color = categoryTemplate.BackgroundColor3,
		transparency = categoryTemplate.BackgroundTransparency,
		selected = categoryTemplate:GetAttribute("SelectedBackgroundColor") or categoryTemplate.BackgroundColor3,
		stroke = (assert(categoryTemplate:FindFirstChildOfClass("UIStroke"), "Category needs a UIStroke")).Color,
		strokeSelected = categoryTemplate:GetAttribute("SelectedStrokeColor") or Color3.new(1, 1, 1),
	}
	local cardStroke = cardTemplate:FindFirstChildOfClass("UIStroke")
	local cardLook = {
		stroke = if cardStroke then cardStroke.Color else Color3.new(1, 1, 1),
		strokeTransparency = if cardStroke then cardStroke.Transparency else 0.5,
		selected = cardTemplate:GetAttribute("SelectedStrokeColor") or Color3.new(1, 1, 1),
	}
	local upgradeLook = {
		color = nodes.upgradeLabel.TextColor3,
		ready = Color3.fromRGB(255, 244, 190),
	}
	local craftLook = {
		color = nodes.craft.BackgroundColor3,
		disabled = nodes.craft:GetAttribute("DisabledBackgroundColor") or Color3.fromRGB(70, 74, 80),
	}
	local category = "All"
	local query = ""
	local picked: Crafting.Recipe? = nil
	local hovered: Crafting.Recipe? = nil
	local times = 1
	local pendingSince: number? = nil
	-- The button whose craft the server has yet to answer: the inventory changing means it was
	-- made; an Error notice means it was refused.
	local crafting: GuiObject? = nil
	local function settleCraft(made: boolean)
		local button = crafting
		crafting = nil
		if not button then
			return
		end
		if made then
			Flair.pulse(nodes.preview)
			Flair.burst(button, TextColors.GOOD, 14)
		else
			Flair.refuse(button, nodes.status)
		end
	end
	local ingredientRows: { Frame } = {}
	local upgradeRows: { Frame } = {}
	local upgradeOpen = false
	local tipRows: { Frame } = {}

	local function matches(recipe: Crafting.Recipe): boolean
		if query == "" then
			return true
		end
		local item = Inventory.getItem(recipe.output)
		return string.find(string.lower(Crafting.nameOf(recipe)), query, 1, true) ~= nil
			or string.find(string.lower(item.kind), query, 1, true) ~= nil
	end

	local function categoryOf(name: string): Category
		for _, each in CATEGORIES do
			if each.name == name then
				return each
			end
		end
		return CATEGORIES[2]
	end

	-- Clones `template` until `rows` has `count`, hides the rest.
	local function rowsFor(rows: { Frame }, template: Frame, parent: Instance, count: number)
		while #rows < count do
			local row = template:Clone()
			row.LayoutOrder = #rows + 1
			row.Parent = parent
			table.insert(rows, row)
			trove:Add(row)
		end
		for index, row in rows do
			row.Visible = index <= count
		end
	end

	local function paintAmounts(rows: { Frame }, recipe: Crafting.Recipe, crafts: number, withIcons: boolean)
		local ids = inputsOf(recipe)
		for index, itemId in ids do
			local row = rows[index]
			local need = recipe.inputs[itemId] * crafts
			local have = countOf(itemId)
			local name = row:FindFirstChild("ItemName") :: TextLabel
			local amount = row:FindFirstChild("Amount") :: TextLabel
			name.Text = Inventory.getItem(itemId).name
			amount.Text = `{Hud.number(have)} / {Hud.number(need)}`
			local color = if have >= need then ENOUGH else SHORT
			amount.TextColor3 = color
			if not withIcons then
				name.TextColor3 = color
			end
			local icon = row:FindFirstChild("Icon")
			if withIcons and icon and icon:IsA("ViewportFrame") then
				ItemIcon.show(icon, itemId)
			end
		end
	end

	local function paintDetails()
		local recipe = picked
		if not recipe then
			nodes.itemName.Text = "Pick a recipe"
			nodes.kind.Text = ""
			turntable.show(nil)
			rowsFor(ingredientRows, ingredientTemplate, nodes.ingredients, 0)
			nodes.status.Text = ""
			nodes.craft.Active = false
			nodes.craft.BackgroundColor3 = craftLook.disabled
			nodes.craftLabel.Text = "CRAFT"
			return
		end
		local item = Inventory.getItem(recipe.output)
		local name = Crafting.nameOf(recipe)
		nodes.itemName.Text = if recipe.count * times > 1 then `{name} x{recipe.count * times}` else name
		nodes.kind.Text = if recipe.upgrade then "Crafting upgrade" else item.kind
		turntable.show(recipe.output)
		local ids = inputsOf(recipe)
		rowsFor(ingredientRows, ingredientTemplate, nodes.ingredients, #ids)
		paintAmounts(ingredientRows, recipe, times, true)
		local blocked = blockerOf(recipe, times)
		local pending = pendingSince ~= nil
		local enabled = blocked == nil and not pending
		nodes.status.Text = if blocked then blocked else ""
		nodes.amount.Text = tostring(times)
		nodes.craft.Active = enabled
		nodes.craft.Selectable = enabled
		nodes.craft.BackgroundColor3 = if enabled then craftLook.color else craftLook.disabled
		nodes.craftLabel.Text = if pending
			then "..."
			elseif locked(recipe) then "LOCKED"
			elseif recipe.upgrade then "UPGRADE"
			else "CRAFT"
	end

	local function paintTooltip()
		local recipe = hovered
		nodes.tooltip.Visible = recipe ~= nil and UserInputService.PreferredInput ~= Enum.PreferredInput.Touch
		if not recipe then
			return
		end
		local item = Inventory.getItem(recipe.output)
		local name = Crafting.nameOf(recipe)
		nodes.tipName.Text = if recipe.count > 1 then `{name} x{recipe.count}` else name
		local target = if recipe.upgrade then Crafting.TIERS[recipe.upgrade] else nil
		local description = if target
			then `{target.description} Needs level {target.level}.`
			else item.description or ""
		local tier = craftingTier()
		local project = if recipe.research and not ResearchClient.done()[recipe.research]
			then Research.get(recipe.research)
			else nil
		local needs = {}
		if tier < recipe.tier then
			table.insert(needs, `Upgrade crafting to {Crafting.TIERS[recipe.tier].name}`)
		end
		if project then
			table.insert(needs, `research {project.name}`)
		end
		nodes.tipText.Text = if #needs > 0
			then `{description}\n{table.concat(needs, " and ")} to unlock.`
			else description
		local ids = inputsOf(recipe)
		rowsFor(tipRows, lineTemplate, nodes.tipLines, #ids)
		paintAmounts(tipRows, recipe, 1, false)
	end

	local function paintCards()
		local shows = categoryOf(category).shows
		local visible = 0
		for _, card in cards do
			local recipe = card.recipe
			local shown = shows(recipe) and matches(recipe)
			card.button.Visible = shown
			if shown then
				visible += 1
			end
			local isLocked = locked(recipe)
			card.lock.Visible = isLocked
			card.ready.Visible = not isLocked and blockerOf(recipe, 1) == nil
			if card.stroke then
				local selected = picked == recipe
				card.stroke.Color = if selected then cardLook.selected else cardLook.stroke
				card.stroke.Transparency = if selected then 0 else cardLook.strokeTransparency
			end
			local icon = card.button:FindFirstChild("Icon")
			if icon and icon:IsA("ViewportFrame") then
				icon.ImageTransparency = if isLocked then 0.55 else 0
			end
		end
		nodes.empty.Visible = visible == 0
		for name, tabButton in categoryButtons do
			local selected = name == category
			tabButton.BackgroundColor3 = if selected then categoryLook.selected else categoryLook.color
			local stroke = tabButton:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected then categoryLook.strokeSelected else categoryLook.stroke
			end
			if selected then
				pickCategory(tabButton)
			end
		end
	end

	-- The recipe that raises crafting one tier, or nil at the top tier.
	local function nextUpgrade(): Crafting.Recipe?
		return Crafting.get(`BenchTier{craftingTier() + 1}`)
	end

	local stopUpgradeBeat: (() -> ())? = nil
	local function paintUpgrade()
		local recipe = nextUpgrade()
		local open = upgradeOpen and recipe ~= nil
		nodes.panel.Visible = open
		local ready = recipe ~= nil and blockerOf(recipe, 1) == nil
		local stroke = nodes.upgrade:FindFirstChildOfClass("UIStroke")
		nodes.upgradeLabel.Text = if recipe then "UPGRADE" else "MAX TIER"
		nodes.upgradeLabel.TextColor3 = if ready then upgradeLook.ready elseif recipe then upgradeLook.color else DIMMED
		nodes.upgrade.Active = recipe ~= nil
		nodes.upgrade.Selectable = recipe ~= nil
		if stroke then
			stroke.Transparency = if ready then 0 elseif recipe then 0.45 else 0.8
		end
		-- an upgrade within reach beats until it is opened or bought
		local beckon = ready and not open
		if beckon and not stopUpgradeBeat then
			stopUpgradeBeat = Flair.attention(nodes.upgradeLabel)
		elseif not beckon and stopUpgradeBeat then
			stopUpgradeBeat()
			stopUpgradeBeat = nil
		end
		if not recipe or not open then
			return
		end
		local target = Crafting.TIERS[recipe.upgrade :: number]
		nodes.panelTitle.Text = target.name
		nodes.panelTier.Text = `Tier {recipe.upgrade} of {#Crafting.TIERS}`
		nodes.panelText.Text = target.description
		local ids = inputsOf(recipe)
		rowsFor(upgradeRows, ingredientTemplate, nodes.panelNeeds, 1 + #ids)
		for index, row in upgradeRows do
			local name = row:FindFirstChild("ItemName") :: TextLabel
			local amount = row:FindFirstChild("Amount") :: TextLabel
			local icon = row:FindFirstChild("Icon")
			local have, need, text
			if index == 1 then
				-- The first row is the level the tier asks for, with no icon.
				have, need, text = EconomyClient.get().level, target.level, "Level"
				name.Position = UDim2.fromOffset(8, 0)
				if icon and icon:IsA("ViewportFrame") then
					icon.Visible = false
				end
			else
				local itemId = ids[index - 1]
				have, need, text = countOf(itemId), recipe.inputs[itemId], Inventory.getItem(itemId).name
				name.Position = UDim2.fromOffset(36, 0)
				if icon and icon:IsA("ViewportFrame") then
					icon.Visible = true
					ItemIcon.show(icon, itemId)
				end
			end
			name.Text = text
			amount.Text = `{Hud.number(have)} / {Hud.number(need)}`
			amount.TextColor3 = if have >= need then ENOUGH else SHORT
		end
		local blocked = blockerOf(recipe, 1)
		local enabled = blocked == nil and pendingSince == nil
		nodes.panelStatus.Text = blocked or "You have everything you need."
		nodes.panelStatus.TextColor3 = if blocked then SHORT else ENOUGH
		nodes.confirm.Active = enabled
		nodes.confirm.Selectable = enabled
		nodes.confirm.BackgroundColor3 = if enabled then craftLook.color else craftLook.disabled
		nodes.confirmLabel.Text = if pendingSince then "..." else "UPGRADE"
	end

	local function render()
		paintCards()
		paintUpgrade()
		paintDetails()
		paintTooltip()
		if nodes.searchClear then
			nodes.searchClear.Visible = query ~= ""
		end
	end

	local function setTimes(value: number)
		times = math.clamp(math.floor(value), 1, Crafting.MAX_TIMES)
		render()
	end

	local function pick(recipe: Crafting.Recipe)
		if picked ~= recipe then
			picked = recipe
			times = 1
		end
		render()
	end

	-- Cards in the order the window lists them: what you can make now, then what's unlocked, then
	-- what research still has to unlock, each in Shared/Crafting's order.
	local function sortCards()
		for index, card in cards do
			local recipe = card.recipe
			local rank = if locked(recipe) then 2000 elseif makeable(recipe) > 0 then 0 else 1000
			card.button.LayoutOrder = rank + index
		end
	end

	for index, recipe in Crafting.RECIPES do
		if recipe.upgrade then
			continue
		end
		local button = cardTemplate:Clone()
		button.Name = recipe.id
		local icon = button:FindFirstChild("Icon")
		local name = button:FindFirstChild("ItemName")
		local count = button:FindFirstChild("Count")
		local ready = button:FindFirstChild("Ready")
		local lock = button:FindFirstChild("Lock")
		if
			not (icon and icon:IsA("ViewportFrame"))
			or not (name and name:IsA("TextLabel"))
			or not (count and count:IsA("TextLabel"))
			or not (ready and ready:IsA("GuiObject"))
			or not (lock and lock:IsA("GuiObject"))
		then
			warn("CraftingScreen: Assets.UI.Crafting.Card needs Icon, ItemName, Count, Ready and Lock")
			button:Destroy()
			return
		end
		ItemIcon.show(icon, recipe.output)
		name.Text = Crafting.nameOf(recipe)
		count.Text = if recipe.count > 1 then `x{recipe.count}` else ""
		button.LayoutOrder = index
		button.Parent = nodes.grid
		local card: Card = {
			recipe = recipe,
			button = button,
			ready = ready,
			lock = lock,
			stroke = button:FindFirstChildOfClass("UIStroke"),
		}
		table.insert(cards, card)
		trove:Add(button)
		trove:Add(function()
			ItemIcon.clear(icon)
		end)
		trove:Add(UI.bindButton(button, {
			hoverScale = 1.04,
			onActivate = function()
				pick(recipe)
			end,
		}))
		trove:Connect(button.MouseEnter, function()
			hovered = recipe
			paintTooltip()
		end)
		trove:Connect(button.MouseLeave, function()
			if hovered == recipe then
				hovered = nil
				paintTooltip()
			end
		end)
		trove:Connect(button.SelectionGained, function()
			pick(recipe)
		end)
	end

	for order, each in CATEGORIES do
		local hasAny = false
		for _, recipe in Crafting.RECIPES do
			if each.name == "Craftable" or each.shows(recipe) then
				hasAny = true
				break
			end
		end
		if hasAny then
			local tabButton = categoryTemplate:Clone()
			tabButton.Name = each.name
			tabButton.LayoutOrder = order
			local text = tabButton:FindFirstChild("Label")
			if text and text:IsA("TextLabel") then
				text.Text = each.name
			end
			tabButton.Parent = nodes.categories
			categoryButtons[each.name] = tabButton
			trove:Add(tabButton)
			trove:Add(UI.bindButton(tabButton, {
				hoverScale = 1.03,
				onActivate = function()
					category = each.name
					nodes.grid.CanvasPosition = Vector2.zero
					render()
				end,
			}))
		end
	end

	trove:Add(UI.bindButton(nodes.minus, {
		onActivate = function()
			setTimes(times - 1)
		end,
	}))
	trove:Add(UI.bindButton(nodes.plus, {
		onActivate = function()
			setTimes(times + 1)
		end,
	}))
	trove:Add(UI.bindButton(nodes.max, {
		onActivate = function()
			setTimes(if picked then math.max(1, makeable(picked)) else 1)
		end,
	}))
	trove:Connect(nodes.amount.FocusLost, function()
		local typed = tonumber(string.match(nodes.amount.Text, "%d+") or "")
		setTimes(typed or times)
	end)
	trove:Add(UI.bindButton(nodes.upgrade, {
		onActivate = function()
			if nextUpgrade() then
				upgradeOpen = not upgradeOpen
				render()
			end
		end,
	}))
	trove:Add(UI.bindButton(nodes.confirm, {
		onActivate = function()
			local recipe = nextUpgrade()
			if recipe and nodes.confirm.Active and not pendingSince then
				pendingSince = os.clock()
				crafting = nodes.confirm
				render()
				Remotes.Craft:FireServer(recipe.id, 1)
			end
		end,
		onRefused = function()
			if nextUpgrade() and not pendingSince then
				Flair.refuse(nodes.confirm)
			end
		end,
	}))
	trove:Add(UI.bindButton(nodes.craft, {
		onActivate = function()
			local recipe = picked
			if recipe and nodes.craft.Active and not pendingSince then
				pendingSince = os.clock()
				crafting = nodes.craft
				render()
				Remotes.Craft:FireServer(recipe.id, times)
			end
		end,
		onRefused = function()
			if picked and not pendingSince then
				Flair.refuse(nodes.craft, nodes.status)
			end
		end,
	}))
	trove:Connect(nodes.search:GetPropertyChangedSignal("Text"), function()
		local typed = string.lower((string.gsub(nodes.search.Text, "^%s+", "")))
		typed = string.gsub(typed, "%s+$", "")
		if typed ~= query then
			query = typed
			nodes.grid.CanvasPosition = Vector2.zero
			render()
		end
	end)
	if nodes.searchClear then
		trove:Add(UI.bindButton(nodes.searchClear, {
			hoverScale = 1.15,
			onActivate = function()
				nodes.search.Text = ""
			end,
		}))
	end

	local window = HubWindow.bind(hud, "Crafting", {}, function()
		sortCards()
		if not picked then
			for _, recipe in Crafting.RECIPES do
				if recipe.upgrade == nil and not locked(recipe) then
					picked = recipe
					break
				end
			end
		end
		render()
	end)
	if not window then
		return
	end
	local frame = window.frame

	-- The hover card follows the pointer, in the window's own (unscaled) space, and flips to the
	-- pointer's left near the window's right edge. Input positions are in GUI space, the space
	-- AbsolutePosition uses.
	local pointer = Vector2.zero
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			pointer = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	trove:Connect(RunService.RenderStepped, function()
		if not nodes.tooltip.Visible then
			return
		end
		local scale = nodes.windowScale.Scale
		local point = (pointer - frame.AbsolutePosition) / scale
		local size = nodes.tooltip.AbsoluteSize / scale
		local width = frame.AbsoluteSize.X / scale
		local x = point.X + TOOLTIP_OFFSET.X
		if x + size.X > width then
			x = point.X - TOOLTIP_OFFSET.X - size.X
		end
		nodes.tooltip.Position = UDim2.fromOffset(x, point.Y + TOOLTIP_OFFSET.Y)
	end)

	local function close()
		window.close()
		hovered = nil
		upgradeOpen = false
		nodes.panel.Visible = false
		nodes.search:ReleaseFocus()
		nodes.search.Text = ""
	end
	local function toggle()
		if window.isOpen() then
			close()
		else
			window.open()
		end
	end
	local opener = Hud.find(hud, "SideButtons.Crafting", "TextButton")
	if opener then
		trove:Add(UI.bindButton(opener, { hoverScale = 1.08, onActivate = toggle }))
	end
	-- The crafting key toggles it, but not while typing (the search box, chat).
	local function onToggle(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		toggle()
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindAction(TOGGLE_ACTION, onToggle, false, table.unpack(Controls.TOGGLE_CRAFTING))
	trove:Add(function()
		ContextActionService:UnbindAction(TOGGLE_ACTION)
	end)
	isOpen = window.isOpen

	local title = Hud.find(hud, "Crafting.Header.Title", "TextLabel")
	local function paintTitle()
		if title and title:IsA("TextLabel") then
			title.Text = Crafting.TIERS[craftingTier()].name
		end
	end
	paintTitle()
	local function refresh()
		paintTitle()
		upgradeOpen = false
		sortCards()
		render()
	end
	trove:Connect(ResearchClient.changed, refresh)
	trove:Connect(player:GetAttributeChangedSignal("BenchTier"), refresh)
	trove:Connect(EconomyClient.changed, function()
		if window.isOpen() then
			render()
		end
	end)
	trove:Connect(InventoryClient.changed, function()
		settleCraft(true)
		pendingSince = nil
		if window.isOpen() then
			render()
		end
	end)
	-- Every craft is answered with a notice, which also ends the wait on a refusal.
	trove:Connect(Remotes.Notify.OnClientEvent, function(_: unknown, kind: unknown)
		if kind == "Error" then
			settleCraft(false)
		end
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
			crafting = nil
			render()
		end
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
		table.clear(cards)
	end)
	sortCards()
	render()
end

function CraftingScreen.isOpen(): boolean
	return if isOpen then isOpen() else false
end

return CraftingScreen
