-- Sell: previews the held stack and whole inventory from item values. The server chooses
-- the actual items and price at transaction time; the client only sends Held or All.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local UI = require(Libraries.UI)
local Sell = {}
function Sell.init(hud: ScreenGui)
	local held = Hud.find(hud, "Sell.Body.Held", "TextLabel")
	local total = Hud.find(hud, "Sell.Body.Total", "TextLabel")
	local sellHeld = Hud.find(hud, "Sell.Body.SellHeld", "TextButton")
	local sellAll = Hud.find(hud, "Sell.Body.SellAll", "TextButton")
	local heldLabel = Hud.find(hud, "Sell.Body.SellHeld.Label", "TextLabel")
	local allLabel = Hud.find(hud, "Sell.Body.SellAll.Label", "TextLabel")
	local title = Hud.find(hud, "Sell.Header.Title", "TextLabel")
	if
		not held
		or not held:IsA("TextLabel")
		or not total
		or not total:IsA("TextLabel")
		or not sellHeld
		or not sellHeld:IsA("TextButton")
		or not sellAll
		or not sellAll:IsA("TextButton")
		or not heldLabel
		or not heldLabel:IsA("TextLabel")
		or not allLabel
		or not allLabel:IsA("TextLabel")
		or not title
		or not title:IsA("TextLabel")
	then
		return
	end
	title.Text = "Sell Stand"
	local trove = Trove.new()
	local baselines = { [sellHeld] = sellHeld.BackgroundTransparency, [sellAll] = sellAll.BackgroundTransparency }
	local textBaselines = { [heldLabel] = heldLabel.TextTransparency, [allLabel] = allLabel.TextTransparency }
	local pending = false
	local function enable(button: TextButton, label: TextLabel, enabled: boolean)
		button.Active = enabled and not pending
		button.Selectable = button.Active
		button.BackgroundTransparency = if button.Active
			then baselines[button]
			else baselines[button] + (1 - baselines[button]) * 0.5
		label.TextTransparency = if button.Active
			then textBaselines[label]
			else textBaselines[label] + (1 - textBaselines[label]) * 0.5
	end
	local function render()
		local stack = InventoryClient.getSlot(InventoryClient.getSelected())
		local item = if stack then Inventory.getItem(stack.itemId) else nil
		local value = if item then item.value else nil
		held.Text = if stack
				and item
				and value
			then `{item.name} x{stack.count} — {Hud.number(value * stack.count)}`
			else "Hold a crop to sell it"
		local sum = 0
		for index = 1, Inventory.SLOT_COUNT do
			local each = InventoryClient.getSlot(index)
			if each then
				sum += (Inventory.getItem(each.itemId).value or 0) * each.count
			end
		end
		total.Text = "Everything: " .. Hud.number(sum)
		heldLabel.Text = if pending then "..." else "Sell held"
		allLabel.Text = if pending then "..." else "Sell all"
		enable(sellHeld, heldLabel, value ~= nil)
		enable(sellAll, allLabel, sum > 0)
	end
	local window = HubWindow.bind(hud, "Sell", { "SellStand" }, render)
	if not window then
		return
	end
	for button, mode in { [sellHeld] = "Held", [sellAll] = "All" } do
		trove:Add(UI.bindButton(button, {
			onActivate = function()
				if not button.Active then
					return
				end
				pending = true
				render()
				Remotes.Sell:FireServer(mode)
			end,
		}))
	end
	trove:Connect(InventoryClient.changed, render)
	trove:Connect(Remotes.Notify.OnClientEvent, function()
		pending = false
		render()
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
	render()
end
return Sell
