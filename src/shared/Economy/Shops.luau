--!strict
-- Shops: what the Gear Shop sells for coins, at what price and from what level, and the Robux
-- Shop's packs. Machines, conveyors and routers are never sold: they are crafted (Shared/Crafting).
-- Seed prices belong to World.CROPS and seed stock to GardenService. The Gear Shop never runs out;
-- a tool can't be bought while you carry one. Each shop is a hub stall (Hub.STALLS) of the same
-- name, and its title is what the shop window shows.
--
-- Robux packs are developer products: MonetizationService grants a pack when Roblox reports its
-- receipt. A pack whose `productId` is 0 has no product yet and only says so when bought; set each
-- id to the developer product made for it on the Creator Dashboard.

export type Offer = {
	itemId: string,
	price: number,
	level: number,
	category: string,
}
export type Shop = { title: string, offers: { Offer } }
export type RobuxPack = {
	id: string,
	name: string,
	-- What the pack shows for its price, in Robux; Roblox charges whatever the product is set to.
	robux: number,
	productId: number,
	coins: number,
}

local CATEGORY_COLORS: { [string]: Color3 } = {
	Tool = Color3.fromRGB(150, 205, 190),
	Block = Color3.fromRGB(205, 186, 152),
	Robux = Color3.fromRGB(120, 200, 120),
}

local function offer(itemId: string, price: number, level: number, category: string): Offer
	return { itemId = itemId, price = price, level = level, category = category }
end

local SHOPS: { [string]: Shop } = {
	GearShop = {
		title = "Gear Shop",
		offers = {
			offer("WateringCan", 150, 1, "Tool"),
			offer("Hoe", 25, 1, "Tool"),
			offer("Pickaxe", 50, 1, "Tool"),
			offer("Axe", 60, 1, "Tool"),
			offer("Hammer", 50, 1, "Tool"),
			offer("Grass", 5, 1, "Block"),
			offer("Dirt", 5, 1, "Block"),
			offer("Stone", 10, 1, "Block"),
			offer("WoodPlanks", 10, 1, "Block"),
			offer("Bricks", 15, 1, "Block"),
			offer("Glass", 20, 1, "Block"),
		},
	},
}

-- The Robux Shop's stall and window tab.
local ROBUX_SHOP = "RobuxShop"
local ROBUX_PACKS: { RobuxPack } = {
	{ id = "CoinsSmall", name = "Pouch of Coins", robux = 49, productId = 0, coins = 2500 },
	{ id = "CoinsMedium", name = "Sack of Coins", robux = 99, productId = 0, coins = 6000 },
	{ id = "CoinsLarge", name = "Chest of Coins", robux = 249, productId = 0, coins = 17500 },
	{ id = "CoinsHuge", name = "Vault of Coins", robux = 499, productId = 0, coins = 40000 },
}

local Shops = {}
Shops.SHOPS = SHOPS
Shops.ROBUX_SHOP = ROBUX_SHOP
Shops.ROBUX_PACKS = ROBUX_PACKS
Shops.CATEGORY_COLORS = CATEGORY_COLORS

function Shops.find(shopId: string, itemId: string): Offer?
	local shop = SHOPS[shopId]
	if not shop then
		return nil
	end
	for _, each in shop.offers do
		if each.itemId == itemId then
			return each
		end
	end
	return nil
end

function Shops.pack(id: string): RobuxPack?
	for _, each in ROBUX_PACKS do
		if each.id == id then
			return each
		end
	end
	return nil
end

function Shops.packForProduct(productId: number): RobuxPack?
	for _, each in ROBUX_PACKS do
		if each.productId ~= 0 and each.productId == productId then
			return each
		end
	end
	return nil
end

return Shops
