-- Shop: a generic authored catalogue window. configure supplies title, priced offers and
-- purchase callback; the seed adapter below supplies Phase 2 stock. No prices come from UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local ItemIcon = require(Libraries.ItemIcon)
local UI = require(Libraries.UI)
export type Offer = { itemId: string, price: number, rarity: string, stock: number }
type Row = {
	offer: Offer,
	frame: Frame,
	stock: TextLabel,
	buy: TextButton,
	label: TextLabel,
	transparency: number,
	textTransparency: number,
}
local Shop = {}
local rows: { Row } = {}
local rowTrove = Trove.new()
local list: ScrollingFrame? = nil
local titleLabel: TextLabel? = nil
local rowTemplate: Frame? = nil
local buyOffer: (string, number) -> () = function(_: string, _: number) end
local pending = false

local function render()
	local coins = EconomyClient.get().coins
	for _, row in rows do
		local offer = row.offer
		local enabled = not pending and offer.stock > 0 and coins >= offer.price
		row.stock.Text = if offer.stock > 0 then `x{offer.stock}` else "Sold out"
		row.buy.Active = enabled
		row.buy.Selectable = enabled
		row.buy.BackgroundTransparency = if enabled
			then row.transparency
			else row.transparency + (1 - row.transparency) * 0.5
		row.label.TextTransparency = if enabled
			then row.textTransparency
			else row.textTransparency + (1 - row.textTransparency) * 0.5
		row.label.Text = if pending
			then "..."
			elseif offer.stock == 0 then "Sold out"
			elseif coins < offer.price then "Need coins"
			else "Buy"
	end
end

function Shop.configure(title: string, offers: { Offer }, purchase: (string, number) -> ())
	if not list or not titleLabel or not rowTemplate then
		return
	end
	rowTrove:Clean()

	table.clear(rows)
	titleLabel.Text = title
	buyOffer = purchase
	pending = false
	local sorted = table.clone(offers)
	table.sort(sorted, function(a: Offer, b: Offer)
		local ar, br = Content.RARITIES[a.rarity].order, Content.RARITIES[b.rarity].order
		return if ar ~= br then ar < br elseif a.price ~= b.price then a.price < b.price else a.itemId < b.itemId
	end)
	for index, offer in sorted do
		local frame = rowTemplate:Clone()
		local icon = Hud.find(frame, "Icon", "ViewportFrame")
		local name = Hud.find(frame, "Name", "TextLabel")
		local rarity = Hud.find(frame, "Rarity", "TextLabel")
		local price = Hud.find(frame, "Price", "TextLabel")
		local stock = Hud.find(frame, "Stock", "TextLabel")
		local buy = Hud.find(frame, "Buy", "TextButton")
		local label = Hud.find(frame, "Buy.Label", "TextLabel")
		if
			not icon
			or not icon:IsA("ViewportFrame")
			or not name
			or not name:IsA("TextLabel")
			or not rarity
			or not rarity:IsA("TextLabel")
			or not price
			or not price:IsA("TextLabel")
			or not stock
			or not stock:IsA("TextLabel")
			or not buy
			or not buy:IsA("TextButton")
			or not label
			or not label:IsA("TextLabel")
		then
			frame:Destroy()
			continue
		end
		name.Text = Inventory.getItem(offer.itemId).name
		rarity.Text = offer.rarity
		rarity.TextColor3 = Content.RARITIES[offer.rarity].color
		price.Text = Hud.number(offer.price)
		ItemIcon.show(icon, offer.itemId)
		frame.LayoutOrder = index
		frame.Visible = true
		frame.Parent = list
		table.insert(rows, {
			offer = offer,
			frame = frame,
			stock = stock,
			buy = buy,
			label = label,
			transparency = buy.BackgroundTransparency,
			textTransparency = label.TextTransparency,
		})
		rowTrove:Add(frame)
		rowTrove:Add(function()
			ItemIcon.clear(icon)
		end)
		rowTrove:Add(UI.bindButton(buy, {
			onActivate = function()
				if not buy.Active or pending then
					return
				end
				pending = true
				render()
				buyOffer(offer.itemId, 1)
			end,
		}))
	end
	render()
end

function Shop.init(hud: ScreenGui)
	local foundList = Hud.find(hud, "Shop.Body.List", "ScrollingFrame")
	local title = Hud.find(hud, "Shop.Header.Title", "TextLabel")
	local restock = Hud.find(hud, "Shop.Body.Restock", "TextLabel")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Shop.Row", "Frame")
	if
		not foundList
		or not foundList:IsA("ScrollingFrame")
		or not title
		or not title:IsA("TextLabel")
		or not restock
		or not restock:IsA("TextLabel")
		or not template
		or not template:IsA("Frame")
	then
		return
	end
	list, titleLabel, rowTemplate = foundList, title, template
	foundList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local window = HubWindow.bind(hud, "Shop", "SeedShop", render)
	if not window then
		return
	end
	local trove = Trove.new()
	local restockAt = 0
	local offers: { Offer } = {}
	local byId: { [string]: Offer } = {}
	for _, crop in World.CROPS do
		local offer = { itemId = crop.seed, price = crop.price, rarity = crop.rarity, stock = 0 }
		table.insert(offers, offer)
		byId[crop.seed] = offer
	end
	Shop.configure("Seed Shop", offers, function(id: string, count: number)
		Remotes.ShopBuy:FireServer(id, count)
	end)
	trove:Connect(Remotes.ShopSync.OnClientEvent, function(snapshot: { restockAt: number, stock: { [string]: number } })
		restockAt = snapshot.restockAt
		for id, offer in byId do
			offer.stock = snapshot.stock[id] or 0
		end
		pending = false
		render()
	end)
	trove:Connect(EconomyClient.changed, render)
	local elapsed = 1
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		restock.Text = if restockAt > 0
			then "Restocks in " .. Hud.time(restockAt - workspace:GetServerTimeNow())
			else "Loading stock..."
	end)
	trove:Connect(hud.Destroying, function()
		rowTrove:Destroy()
		trove:Destroy()
		table.clear(rows)
	end)
end
return Shop
