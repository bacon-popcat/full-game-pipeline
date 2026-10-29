--!strict
-- Products: what the processing machines make, from what, and what each is worth. Items turns
-- these into items and Factory/Blocks into recipes, so a product's numbers live only here. Crop
-- values come from World.CROPS; a recipe takes any mutation of a crop input (Machine).
--
-- Art: products borrow an existing Assets.Items model (`art`), tinted `color` when given, until
-- the art phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.World)

export type Product = {
	id: string,
	name: string,
	description: string,
	value: number,
	machine: string,
	inputs: { [string]: number },
	-- Seconds per batch.
	time: number,
	art: string,
	color: Color3?,
}

local JUICE_FRUITS = { "Strawberry", "Blueberry", "Grape", "Apple", "Tomato" }
-- A juice is worth this many of its fruit, made from JUICE_FRUIT_COUNT of them.
local JUICE_MULTIPLIER = 3.5
local JUICE_FRUIT_COUNT = 3
local PIES: { [string]: number } = { Strawberry = 250, Blueberry = 400, Apple = 600 }
local CRATE_SIZE = 10
-- A crate is worth this many of its crop.
local CRATE_MULTIPLIER = 12
local FLOUR_COLOR = Color3.fromRGB(240, 228, 204)

local function produceOf(cropId: string): string
	local crop = World.CROPS[cropId]
	assert(crop, `Products: unknown crop "{cropId}"`)
	return crop.produce
end

local PRODUCTS: { Product } = {
	{
		id = "Flour",
		name = "Flour",
		description = "Milled wheat. Bake it into pies.",
		value = 40,
		machine = "Mill",
		inputs = { Wheat = 2 },
		time = 4,
		art = "BerryDough",
		color = FLOUR_COLOR,
	},
}

for _, cropId in JUICE_FRUITS do
	local crop = World.CROPS[cropId]
	table.insert(PRODUCTS, {
		id = cropId .. "Juice",
		name = crop.name .. " Juice",
		description = `Pressed from {JUICE_FRUIT_COUNT} {string.lower(crop.name)} fruit.`,
		value = math.round(crop.value * JUICE_MULTIPLIER),
		machine = "Juicer",
		inputs = { [produceOf(cropId)] = JUICE_FRUIT_COUNT },
		time = 5,
		art = "MapleSyrup",
		color = crop.color,
	})
end

local pieFruits: { string } = {}
for cropId in PIES do
	table.insert(pieFruits, cropId)
end
table.sort(pieFruits)
for _, cropId in pieFruits do
	local crop = World.CROPS[cropId]
	table.insert(PRODUCTS, {
		id = cropId .. "Pie",
		name = crop.name .. " Pie",
		description = "Flour and fruit, baked golden.",
		value = PIES[cropId],
		machine = "Oven",
		inputs = { Flour = 1, [produceOf(cropId)] = 2 },
		time = 8,
		art = "BerryBread",
		color = crop.color,
	})
end

local cropIds: { string } = {}
for cropId in World.CROPS do
	table.insert(cropIds, cropId)
end
table.sort(cropIds)
for _, cropId in cropIds do
	local crop = World.CROPS[cropId]
	table.insert(PRODUCTS, {
		id = cropId .. "Crate",
		name = crop.name .. " Crate",
		description = `{CRATE_SIZE} {string.lower(crop.name)}, packed for market.`,
		value = crop.value * CRATE_MULTIPLIER,
		machine = "CratePacker",
		inputs = { [crop.produce] = CRATE_SIZE },
		time = 3,
		art = "FruitCrate",
	})
end

return PRODUCTS
