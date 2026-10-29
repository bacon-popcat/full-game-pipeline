--!strict
-- Shops: what the Gear Shop and Machine Shop sell, at what price and from what level. Seed
-- prices belong to World.CROPS and seed stock to GardenService. These two shops never run
-- out; a tool can't be bought while you carry one. Each shop is a hub stall (Hub.STALLS)
-- of the same name, and its title is what the shop window shows.

export type Offer = { itemId: string, price: number, level: number, category: string }
export type Shop = { title: string, offers: { Offer } }

local CATEGORY_COLORS: { [string]: Color3 } = {
	Tool = Color3.fromRGB(150, 205, 190),
	Block = Color3.fromRGB(205, 186, 152),
	Conveyor = Color3.fromRGB(170, 190, 215),
	Router = Color3.fromRGB(190, 175, 220),
	Machine = Color3.fromRGB(225, 196, 130),
}

local function offer(itemId: string, price: number, level: number, category: string): Offer
	return { itemId = itemId, price = price, level = level, category = category }
end

local SHOPS: { [string]: Shop } = {
	GearShop = {
		title = "Gear Shop",
		offers = {
			offer("WateringCan", 150, 1, "Tool"),
			offer("Pickaxe", 50, 1, "Tool"),
			offer("Hammer", 50, 1, "Tool"),
			offer("Grass", 5, 1, "Block"),
			offer("Dirt", 5, 1, "Block"),
			offer("Stone", 10, 1, "Block"),
			offer("WoodPlanks", 10, 1, "Block"),
			offer("Bricks", 15, 1, "Block"),
			offer("Glass", 20, 1, "Block"),
		},
	},
	MachineShop = {
		title = "Machine Shop",
		offers = {
			offer("ConveyorBelt", 25, 1, "Conveyor"),
			offer("ConveyorBeltLeft", 25, 1, "Conveyor"),
			offer("ConveyorBeltRight", 25, 1, "Conveyor"),
			offer("ConveyorRamp", 25, 1, "Conveyor"),
			offer("ConveyorRampDown", 25, 1, "Conveyor"),
			offer("ConveyorBeltTier2", 75, 4, "Conveyor"),
			offer("ConveyorBeltLeftTier2", 75, 4, "Conveyor"),
			offer("ConveyorBeltRightTier2", 75, 4, "Conveyor"),
			offer("ConveyorRampTier2", 75, 4, "Conveyor"),
			offer("ConveyorRampDownTier2", 75, 4, "Conveyor"),
			offer("SplitConveyor", 150, 3, "Router"),
			offer("Merger", 150, 3, "Router"),
			offer("FilterConveyor", 150, 3, "Router"),
			offer("Randomizer", 150, 3, "Router"),
			offer("ConveyorSensor", 150, 3, "Router"),
			offer("StorageChest", 200, 2, "Machine"),
			offer("ShippingBin", 300, 2, "Machine"),
			offer("SeedPlanter", 800, 4, "Machine"),
			offer("Sprinkler", 1000, 5, "Machine"),
			offer("Harvester", 2000, 6, "Machine"),
			offer("Mill", 2500, 7, "Machine"),
			offer("Juicer", 4000, 8, "Machine"),
			offer("CratePacker", 6000, 9, "Machine"),
			offer("Oven", 8000, 10, "Machine"),
		},
	},
}

local Shops = {}
Shops.SHOPS = SHOPS
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

return Shops
