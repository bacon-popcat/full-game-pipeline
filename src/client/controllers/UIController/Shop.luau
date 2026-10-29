-- Shop: the authored catalogue window behind the Seed Shop, Gear Shop and Machine Shop
-- stalls. Whichever stall's prompt opened it decides the catalogue: seeds with this player's
-- stock and restock countdown, or Shared/Economy/Shops' offers with their level locks. No
-- prices come from the UI; the server checks every purchase and answers with Notify.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local World = require(ReplicatedStorage.Shared.World)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)
local UI = require(Libraries.UI)
-- `stock` is nil for a shop that never runs out; `level` locks the offer below it.
export type Offer = {
	itemId: string,
	price: number,
	label: string,
	color: Color3,
	order: number,
	stock: number?,
	level: number?,
}
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

local function carries(itemId: string): boolean
	for index = 1, Inventory.SLOT_COUNT do
		local stack = InventoryClient.getSlot(index)
		if stack and stack.itemId == itemId then
			return true
		end
	end
	return false
end

local function render()
	local economy = EconomyClient.get()
	for _, row in rows do
		local offer = row.offer
		local locked = offer.level ~= nil and economy.level < offer.level
		local soldOut = offer.stock == 0
		local owned = Inventory.getItem(offer.itemId).kind == "Tool" and carries(offer.itemId)
		local enabled = not pending and not locked and not soldOut and not owned and economy.coins >= offer.price
		row.stock.Text = if offer.stock
			then (if offer.stock > 0 then `x{offer.stock}` else "Sold out")
			elseif locked then `Lv {offer.level}`
			else ""
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
			elseif locked then "Locked"
			elseif owned then "Owned"
			elseif soldOut then "Sold out"
			elseif economy.coins < offer.price then "Need coins"
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
		return if a.order ~= b.order
			then a.order < b.order
			elseif a.price ~= b.price then a.price < b.price
			else a.itemId < b.itemId
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
		rarity.Text = offer.label
		rarity.TextColor3 = offer.color
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
	local trove = Trove.new()
	local restockAt = 0
	local seedOffers: { Offer } = {}
	local seedById: { [string]: Offer } = {}
	for _, crop in World.CROPS do
		local rarity = Content.RARITIES[crop.rarity]
		local offer: Offer = {
			itemId = crop.seed,
			price = crop.price,
			label = crop.rarity,
			color = rarity.color,
			order = rarity.order,
			stock = 0,
		}
		table.insert(seedOffers, offer)
		seedById[crop.seed] = offer
	end
	local categories: { [string]: number } = { Tool = 1, Block = 2, Conveyor = 1, Router = 2, Machine = 3 }
	local function catalogue(stall: string)
		local shop = Shops.SHOPS[stall]
		local offers: { Offer } = if shop then {} else seedOffers
		for _, each in if shop then shop.offers else {} do
			table.insert(offers, {
				itemId = each.itemId,
				price = each.price,
				label = each.category,
				color = Shops.CATEGORY_COLORS[each.category],
				order = categories[each.category] * 100 + each.level,
				level = each.level,
			})
		end
		restock.Visible = shop == nil
		Shop.configure(if shop then shop.title else "Seed Shop", offers, function(id: string, count: number)
			Remotes.ShopBuy:FireServer(stall, id, count)
		end)
	end
	local stalls = { "SeedShop" }
	for stall in Shops.SHOPS do
		table.insert(stalls, stall)
	end
	local window = HubWindow.bind(hud, "Shop", stalls, render, catalogue)
	if not window then
		return
	end
	catalogue("SeedShop")
	trove:Connect(Remotes.ShopSync.OnClientEvent, function(snapshot: { restockAt: number, stock: { [string]: number } })
		restockAt = snapshot.restockAt
		for id, offer in seedById do
			offer.stock = snapshot.stock[id] or 0
		end
		pending = false
		render()
	end)
	-- Every purchase is answered with a toast, which also ends the Gear and Machine Shops' wait.
	trove:Connect(Remotes.Notify.OnClientEvent, function()
		if pending then
			pending = false
			render()
		end
	end)
	trove:Connect(EconomyClient.changed, render)
	trove:Connect(InventoryClient.changed, render)
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
