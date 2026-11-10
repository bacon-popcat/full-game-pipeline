-- QuestsScreen: the Quests window (HUD.Quests), toggled by SideButtons.Quests and opened on its
-- Orders tab by the hub's Orders Board. Its Badge.Count shows what is waiting (daily quests to
-- claim, orders the inventory can fill) even while the window is closed.
--
-- Two tabs (Body.Tabs.Daily / Orders) switch between two lists:
--   Body.Daily: one Assets.UI.Progress.Quest row per daily quest (ProgressClient), in slot order:
--     what to do, its reward, progress and a Claim button that wakes once the quest is done.
--   Body.Orders: one Assets.UI.Progress.Order row per order slot: the item's Icon, "Carrot x9",
--     the reward, how many the inventory holds, Deliver and Skip; a waiting slot shows Wait
--     ("Arrives in 4:12") instead.
-- Body.Hint says when the daily quests change and how far the next bonus seed is.
-- A press waits for the next ProgressSync (ProgressService answers every request), or
-- PENDING_FOR seconds on a dropped answer. tools/hud/quests_hud.luau authors the nodes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local ProgressClient = require(Libraries.ProgressClient)
local UI = require(Libraries.UI)

local PENDING_FOR = 2
local BOARD = "OrdersBoard"
local SKY = Color3.fromRGB(142, 197, 255)
local DONE = Color3.fromRGB(157, 220, 154)
-- The picked tab: a sky-tinted fill and stroke; the other one is dimmed.
local TAB_FILL = Color3.fromRGB(34, 52, 74)
local TAB_DIM = Color3.fromRGB(150, 150, 168)
local TABS = { "Daily", "Orders" }

type Press = { button: TextButton, label: TextLabel, transparency: number }
type QuestRow = {
	frame: Frame,
	text: TextLabel,
	reward: TextLabel,
	count: TextLabel,
	fill: Frame,
	claim: Press,
}
type OrderRow = {
	frame: Frame,
	icon: ViewportFrame,
	text: TextLabel,
	reward: TextLabel,
	count: TextLabel,
	track: Frame,
	fill: Frame,
	deliver: Press,
	skip: Press,
	wait: TextLabel,
}
type Tab = { button: TextButton, label: TextLabel?, stroke: UIStroke, fill: Color3, list: ScrollingFrame }

local QuestsScreen = {}

local function rewardText(reward: Progress.Reward): string
	local parts = {}
	if reward.coins > 0 then
		table.insert(parts, `+{Hud.number(reward.coins)} coins`)
	end
	if reward.xp > 0 then
		table.insert(parts, `{Hud.number(reward.xp)} XP`)
	end
	return table.concat(parts, "  ·  ")
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

local function press(parent: Instance, name: string): Press?
	local button = Hud.find(parent, name, "TextButton")
	local label = Hud.find(parent, name .. ".Label", "TextLabel")
	if not button or not button:IsA("TextButton") or not label or not label:IsA("TextLabel") then
		return nil
	end
	return { button = button, label = label, transparency = button.BackgroundTransparency }
end

local function setEnabled(target: Press, enabled: boolean, text: string)
	target.button.Active = enabled
	target.button.Selectable = enabled
	target.button.BackgroundTransparency = if enabled
		then target.transparency
		else target.transparency + (1 - target.transparency) * 0.5
	target.label.TextTransparency = if enabled then 0 else 0.5
	target.label.Text = text
end

-- How many orders the inventory can fill right now.
local function deliverable(): number
	local count = 0
	for _, order in ProgressClient.get().orders do
		if order.item and order.count and countOf(order.item) >= order.count then
			count += 1
		end
	end
	return count
end

function QuestsScreen.init(hud: ScreenGui)
	local hint = Hud.find(hud, "Quests.Body.Hint", "TextLabel")
	local questTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Quest", "Frame")
	local orderTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Order", "Frame")
	local tabs: { [string]: Tab } = {}
	for _, name in TABS do
		local button = Hud.find(hud, `Quests.Body.Tabs.{name}`, "TextButton")
		local list = Hud.find(hud, `Quests.Body.{name}`, "ScrollingFrame")
		local stroke = if button then button:FindFirstChildOfClass("UIStroke") else nil
		if not button or not button:IsA("TextButton") or not list or not list:IsA("ScrollingFrame") or not stroke then
			return
		end
		local label = button:FindFirstChild("Label")
		tabs[name] = {
			button = button,
			label = if label and label:IsA("TextLabel") then label else nil,
			stroke = stroke,
			fill = button.BackgroundColor3,
			list = list,
		}
	end
	if
		not hint
		or not hint:IsA("TextLabel")
		or not questTemplate
		or not questTemplate:IsA("Frame")
		or not orderTemplate
		or not orderTemplate:IsA("Frame")
	then
		return
	end
	local trove = Trove.new()
	local questRows: { QuestRow } = {}
	local orderRows: { OrderRow } = {}
	local tab = "Daily"
	local pendingSince: number? = nil

	local function send(request: (slot: number) -> (), slot: number)
		if not pendingSince then
			pendingSince = os.clock()
			request(slot)
		end
	end

	local function questRow(slot: number): QuestRow?
		if questRows[slot] then
			return questRows[slot]
		end
		local frame = questTemplate:Clone()
		local text = Hud.find(frame, "Text", "TextLabel")
		local reward = Hud.find(frame, "Reward", "TextLabel")
		local count = Hud.find(frame, "Count", "TextLabel")
		local fill = Hud.find(frame, "Track.Fill", "Frame")
		local claim = press(frame, "Claim")
		if not (text and reward and count and fill and claim) then
			frame:Destroy()
			return nil
		end
		assert(text:IsA("TextLabel") and reward:IsA("TextLabel") and count:IsA("TextLabel"), "Quest row labels")
		assert(fill:IsA("Frame"), "Quest row fill")
		frame.Name = `Quest{slot}`
		frame.LayoutOrder = slot
		frame.Parent = tabs.Daily.list
		trove:Add(frame)
		trove:Add(UI.bindButton(claim.button, {
			onActivate = function()
				if claim.button.Active then
					send(ProgressClient.claimDaily, slot)
				end
			end,
		}))
		local row = { frame = frame, text = text, reward = reward, count = count, fill = fill, claim = claim }
		questRows[slot] = row
		return row
	end

	local function orderRow(slot: number): OrderRow?
		if orderRows[slot] then
			return orderRows[slot]
		end
		local frame = orderTemplate:Clone()
		local icon = Hud.find(frame, "Icon", "ViewportFrame")
		local text = Hud.find(frame, "Text", "TextLabel")
		local reward = Hud.find(frame, "Reward", "TextLabel")
		local count = Hud.find(frame, "Count", "TextLabel")
		local track = Hud.find(frame, "Track", "Frame")
		local fill = Hud.find(frame, "Track.Fill", "Frame")
		local wait = Hud.find(frame, "Wait", "TextLabel")
		local deliver = press(frame, "Deliver")
		local skip = press(frame, "Skip")
		if not (icon and text and reward and count and track and fill and wait and deliver and skip) then
			frame:Destroy()
			return nil
		end
		assert(icon:IsA("ViewportFrame") and track:IsA("Frame") and fill:IsA("Frame"), "Order row parts")
		assert(text:IsA("TextLabel") and reward:IsA("TextLabel"), "Order row labels")
		assert(count:IsA("TextLabel") and wait:IsA("TextLabel"), "Order row labels")
		frame.Name = `Order{slot}`
		frame.LayoutOrder = slot
		frame.Parent = tabs.Orders.list
		trove:Add(frame)
		trove:Add(function()
			ItemIcon.clear(icon)
		end)
		trove:Add(UI.bindButton(deliver.button, {
			onActivate = function()
				if deliver.button.Active then
					send(ProgressClient.deliverOrder, slot)
				end
			end,
		}))
		trove:Add(UI.bindButton(skip.button, {
			onActivate = function()
				if skip.button.Active then
					send(ProgressClient.skipOrder, slot)
				end
			end,
		}))
		local row = {
			frame = frame,
			icon = icon,
			text = text,
			reward = reward,
			count = count,
			track = track,
			fill = fill,
			deliver = deliver,
			skip = skip,
			wait = wait,
		}
		orderRows[slot] = row
		return row
	end

	local function renderDaily(snapshot: ProgressClient.Snapshot)
		local quests = snapshot.daily.quests
		for slot = 1, math.max(#quests, #questRows) do
			local view = quests[slot]
			local row = if view then questRow(slot) else questRows[slot]
			if row then
				row.frame.Visible = view ~= nil
			end
			if row and view then
				local ready = view.done and not view.claimed
				row.text.Text = view.text
				row.reward.Text = rewardText(view.reward)
				row.count.Text = `{Hud.number(view.progress)} / {Hud.number(view.goal)}`
				row.fill.Size = UDim2.fromScale(if view.goal > 0 then math.min(1, view.progress / view.goal) else 1, 1)
				row.fill.BackgroundColor3 = if view.done then DONE else SKY
				setEnabled(
					row.claim,
					ready and pendingSince == nil,
					if view.claimed
						then "Claimed"
						elseif ready and pendingSince then "..."
						elseif ready then "Claim"
						else "In progress"
				)
			end
		end
	end

	local function renderOrders(snapshot: ProgressClient.Snapshot)
		local orders = snapshot.orders
		local now = workspace:GetServerTimeNow()
		for slot = 1, math.max(#orders, #orderRows) do
			local view = orders[slot]
			local row = if view then orderRow(slot) else orderRows[slot]
			if row then
				row.frame.Visible = view ~= nil
			end
			if not row or not view then
				continue
			end
			local item = if view.item then Inventory.find(view.item) else nil
			local asked = view.count
			local active = item ~= nil and asked ~= nil and view.reward ~= nil
			for _, node in { row.icon, row.text, row.reward, row.count, row.track, row.deliver.button, row.skip.button } do
				node.Visible = active
			end
			row.wait.Visible = not active
			if item and asked and view.reward then
				local have = math.min(countOf(item.id), asked)
				local ready = have >= asked
				ItemIcon.show(row.icon, item.id)
				row.text.Text = `{item.name} x{Hud.number(asked)}`
				row.reward.Text = rewardText(view.reward)
				row.count.Text = `{Hud.number(have)} / {Hud.number(asked)}`
				row.fill.Size = UDim2.fromScale(have / asked, 1)
				row.fill.BackgroundColor3 = if ready then DONE else SKY
				setEnabled(
					row.deliver,
					ready and pendingSince == nil,
					if ready and pendingSince then "..." else "Deliver"
				)
				setEnabled(row.skip, pendingSince == nil, "Skip")
			else
				ItemIcon.show(row.icon, nil)
				row.wait.Text = `The next order arrives in {Hud.time((view.waitUntil or 0) - now)}`
			end
		end
	end

	local function renderHint(snapshot: ProgressClient.Snapshot)
		if tab == "Daily" then
			local left = Hud.span(snapshot.daily.resetsAt - workspace:GetServerTimeNow())
			hint.Text = if snapshot.daily.bonus
				then `All done for today. New quests in {left}.`
				else `New quests in {left}. Finish all three for a bonus seed.`
		else
			local toBonus = snapshot.ordersToBonus
			hint.Text = "Orders pay half again over selling, and double XP. "
				.. (if toBonus <= 1 then "Your next one adds a bonus seed." else `Bonus seed in {toBonus} more.`)
		end
	end

	local function render()
		local snapshot = ProgressClient.get()
		for name, each in tabs do
			local selected = name == tab
			each.list.Visible = selected
			each.stroke.Color = if selected then SKY else TAB_DIM
			each.button.BackgroundColor3 = if selected then TAB_FILL else each.fill
			if each.label then
				each.label.TextTransparency = if selected then 0 else 0.45
			end
		end
		renderHint(snapshot)
		if tab == "Daily" then
			renderDaily(snapshot)
		else
			renderOrders(snapshot)
		end
	end

	local window = HubWindow.bind(hud, "Quests", { BOARD }, render, function(opener: string)
		-- The board is about orders; the side button returns to the tab left open.
		if opener == BOARD then
			tab = "Orders"
		end
	end)
	if not window then
		trove:Destroy()
		return
	end
	for name, each in tabs do
		trove:Add(UI.bindButton(each.button, {
			onActivate = function()
				tab = name
				render()
			end,
		}))
	end
	local opener = Hud.find(hud, "SideButtons.Quests", "TextButton")
	local badge = Hud.find(hud, "SideButtons.Quests.Badge", "Frame")
	local badgeCount = Hud.find(hud, "SideButtons.Quests.Badge.Count", "TextLabel")
	local function paintBadge()
		local count = ProgressClient.claimable() + deliverable()
		if badge and badge:IsA("GuiObject") then
			badge.Visible = count > 0
		end
		if badgeCount and badgeCount:IsA("TextLabel") then
			badgeCount.Text = if count > 9 then "9+" else tostring(count)
		end
	end
	if opener then
		trove:Add(UI.bindButton(opener, {
			hoverScale = 1.08,
			onActivate = function()
				if window.isOpen() then
					window.close()
				else
					window.open("Side")
				end
			end,
		}))
	end
	trove:Connect(ProgressClient.changed, function()
		pendingSince = nil
		paintBadge()
		if window.isOpen() then
			render()
		end
	end)
	trove:Connect(InventoryClient.changed, function()
		paintBadge()
		if window.isOpen() and tab == "Orders" then
			render()
		end
	end)
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		if pendingSince and os.clock() - pendingSince > PENDING_FOR then
			pendingSince = nil
			render()
		end
		-- The countdowns in the hint and on waiting orders.
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			if window.isOpen() then
				render()
			end
		end
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
	paintBadge()
	render()
end

return QuestsScreen
