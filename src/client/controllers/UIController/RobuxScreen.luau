-- RobuxScreen: the authored Robux Shop window (HUD.Robux), opened by the Robux Shop stall's prompt
-- or the Robux side button (SideButtons.Robux) from anywhere. Body.List holds one
-- Assets.UI.Robux.Pack card per Shared/Economy/Shops.ROBUX_PACKS entry: a coin, the pack's name,
-- its coins and a Buy button priced in Robux. Buy only sends the intent (ShopBuy with the stall and
-- the pack id); the server shows Roblox's purchase prompt, and MonetizationService grants the
-- coins from the receipt (economy.md). The wait ends when that prompt closes or a notice arrives.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local UI = require(Libraries.UI)

local RobuxScreen = {}

function RobuxScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Robux.Body.List", "ScrollingFrame")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Robux.Pack", "Frame")
	if not list or not template then
		return
	end
	local trove = Trove.new()
	local pending = false
	local buttons: { { button: TextButton, label: TextLabel, price: string } } = {}

	local function render()
		for _, each in buttons do
			each.button.Active = not pending
			each.button.Selectable = not pending
			each.button.BackgroundTransparency = if pending then 0.5 else 0.1
			each.label.Text = if pending then "..." else each.price
		end
	end

	for order, pack in Shops.ROBUX_PACKS do
		local card = template:Clone()
		local name = Hud.find(card, "Name", "TextLabel")
		local coins = Hud.find(card, "Coins", "TextLabel")
		local buy = Hud.find(card, "Buy", "TextButton")
		local label = Hud.find(card, "Buy.Label", "TextLabel")
		if not (name and coins and buy and label) then
			card:Destroy()
			return
		end
		assert(name:IsA("TextLabel") and coins:IsA("TextLabel") and buy:IsA("TextButton") and label:IsA("TextLabel"))
		name.Text = pack.name
		coins.Text = `+{Hud.number(pack.coins)}`
		local price = `R$ {Hud.number(pack.robux)}`
		label.Text = price
		card.LayoutOrder = order
		card.Parent = list
		trove:Add(card)
		table.insert(buttons, { button = buy, label = label, price = price })
		trove:Add(UI.bindButton(buy, {
			onActivate = function()
				if pending then
					return
				end
				pending = true
				render()
				Remotes.ShopBuy:FireServer(Shops.ROBUX_SHOP, pack.id, 1)
			end,
		}))
	end

	local window = HubWindow.bind(hud, "Robux", { Shops.ROBUX_SHOP }, render)
	if not window then
		return
	end
	local opener = Hud.find(hud, "SideButtons.Robux", "TextButton")
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
	local function settle()
		if pending then
			pending = false
			render()
		end
	end
	trove:Connect(MarketplaceService.PromptProductPurchaseFinished, settle)
	trove:Connect(Remotes.Notify.OnClientEvent, settle)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
		table.clear(buttons)
	end)
	render()
end

return RobuxScreen
