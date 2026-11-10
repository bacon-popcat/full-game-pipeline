--!strict
-- Products: what the processing machines and the Assembler (id Workbench) make, from what, and
-- what each is worth. Items turns these into items and Factory/Blocks into recipes, so a product's numbers
-- live only here. Crop values come from World.CROPS. A batch takes inputs of one mutation only
-- and its product keeps that mutation (Machine; Items makes the variants of every valued
-- product). Parts have no value: they are spent crafting machines (Shared/Crafting).
--
-- Art: products borrow an existing Assets.Items model (`art`), tinted `color` when given, until
-- the art phase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local World = require(ReplicatedStorage.Shared.World)

export type Product = {
	id: string,
	name: string,
	description: string,
	value: number?,
	machine: string,
	inputs: { [string]: number },
	-- Seconds per batch.
	time: number,
	art: string,
	color: Color3?,
	-- The research project the machine's owner must have finished to make it (Shared/Research);
	-- nil when having the machine is enough.
	research: string?,
}

local JUICE_FRUITS = { "Strawberry", "Blueberry", "Grape", "Apple", "Tomato" }
-- A juice is worth this many of its fruit, made from JUICE_FRUIT_COUNT of them.
local JUICE_MULTIPLIER = 4.5
local JUICE_FRUIT_COUNT = 3
local PIES: { [string]: number } = { Strawberry = 250, Blueberry = 400, Apple = 600 }
local CRATE_SIZE = 10
-- A crate is worth this many of its crop.
local CRATE_MULTIPLIER = 12
local FLOUR_COLOR = Color3.fromRGB(240, 228, 204)
local STEEL_COLOR = Color3.fromRGB(178, 186, 196)
local CIRCUIT_COLOR = Color3.fromRGB(128, 186, 140)

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

-- The mid-game products (docs/retention.md § Mid-game machines): the Roaster, Preserving Kettle
-- and Chiller's, and what the Recipe Books add to the Baking Oven. A chained product's value is
-- not written down. It is the plain worth of the crops that go into it, every input traced back
-- through the products it is made of, times CHAIN[depth], rounded to two significant figures,
-- where `depth` is how many machines the longest way to it passes through. So a retuned crop
-- carries its products with it, and a longer line always pays more.
local CHAIN = { 1.5, 3, 4.5 }
local JAM_FRUITS = { "Strawberry", "Blueberry", "Apple", "Grape" }
-- A jam takes its fruit's juice and this many more of the fruit.
local JAM_FRUIT_COUNT = 2
local JAM_TIME = 8
local TART_TIME = 8
local CREAM = Color3.fromRGB(244, 226, 190)

local byId: { [string]: Product } = {}
for _, product in PRODUCTS do
	byId[product.id] = product
end

-- What the crops behind `inputs` sell for plain.
local function rawWorth(inputs: { [string]: number }): number
	local worth = 0
	for itemId, count in inputs do
		local product = byId[itemId]
		local crop = World.CROPS[itemId]
		assert(product or crop, `Products: "{itemId}" is neither a crop nor a product defined earlier`)
		worth += count * (if product then rawWorth(product.inputs) else crop.value)
	end
	return worth
end

local function twoFigures(value: number): number
	local step = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.round(value / step) * step
end

local function chained(
	id: string,
	name: string,
	description: string,
	machine: string,
	inputs: { [string]: number },
	depth: number,
	time: number,
	art: string,
	color: Color3?,
	research: string?
)
	local product: Product = {
		id = id,
		name = name,
		description = description,
		value = twoFigures(rawWorth(inputs) * CHAIN[depth]),
		machine = machine,
		inputs = inputs,
		time = time,
		art = art,
		color = color,
		research = research,
	}
	byId[id] = product
	table.insert(PRODUCTS, product)
end

chained(
	"Crisps",
	"Crisps",
	"Thin-sliced potato, roasted crisp.",
	"Roaster",
	{ Potato = 2 },
	1,
	6,
	"BerryDough",
	Color3.fromRGB(232, 196, 110)
)
chained(
	"Popcorn",
	"Popcorn",
	"Corn, popped.",
	"Roaster",
	{ Corn = 2 },
	1,
	6,
	"BerryDough",
	Color3.fromRGB(250, 240, 208)
)
chained(
	"RoastPumpkin",
	"Roast Pumpkin",
	"A pumpkin roasted soft. Bake it into a pie.",
	"Roaster",
	{ Pumpkin = 1 },
	1,
	6,
	"Pumpkin",
	Color3.fromRGB(196, 118, 62)
)
chained(
	"TomatoSauce",
	"Tomato Sauce",
	"Tomatoes simmered down. Bake it onto a pizza.",
	"Kettle",
	{ Tomato = 4 },
	1,
	8,
	"MapleSyrup",
	Color3.fromRGB(200, 70, 56)
)
for _, cropId in JAM_FRUITS do
	local crop = World.CROPS[cropId]
	chained(
		cropId .. "Jam",
		crop.name .. " Jam",
		`{crop.name} juice and fruit, simmered to set.`,
		"Kettle",
		{ [cropId .. "Juice"] = 1, [produceOf(cropId)] = JAM_FRUIT_COUNT },
		2,
		JAM_TIME,
		"MapleSyrup",
		crop.color:Lerp(Color3.new(0, 0, 0), 0.3)
	)
end
chained(
	"Pizza",
	"Pizza",
	"Flour and tomato sauce, baked.",
	"Oven",
	{ Flour = 1, TomatoSauce = 1 },
	2,
	8,
	"BerryBread",
	Color3.fromRGB(226, 150, 96),
	"RecipeBook1"
)
chained(
	"PumpkinPie",
	"Pumpkin Pie",
	"Flour and roast pumpkin, baked golden.",
	"Oven",
	{ Flour = 1, RoastPumpkin = 1 },
	2,
	8,
	"BerryBread",
	Color3.fromRGB(214, 140, 70),
	"RecipeBook1"
)
for _, cropId in JAM_FRUITS do
	local crop = World.CROPS[cropId]
	chained(
		cropId .. "JamTart",
		crop.name .. " Jam Tart",
		`A pastry case of {string.lower(crop.name)} jam.`,
		"Oven",
		{ Flour = 1, [cropId .. "Jam"] = 1 },
		3,
		TART_TIME,
		"BerryBread",
		crop.color:Lerp(CREAM, 0.5),
		"RecipeBook2"
	)
end
chained(
	"WatermelonSorbet",
	"Watermelon Sorbet",
	"Watermelon and strawberry juice, frozen smooth.",
	"Chiller",
	{ Watermelon = 1, StrawberryJuice = 1 },
	2,
	10,
	"MapleSyrup",
	Color3.fromRGB(240, 130, 140)
)
chained(
	"StarfruitSorbet",
	"Starfruit Sorbet",
	"Starfruit and blueberry juice, frozen smooth.",
	"Chiller",
	{ Starfruit = 2, BlueberryJuice = 1 },
	2,
	10,
	"MapleSyrup",
	Color3.fromRGB(250, 234, 150)
)

-- Assembler parts, from the quarry's ore smelted into bars.
local function part(
	id: string,
	name: string,
	description: string,
	inputs: { [string]: number },
	time: number,
	art: string,
	color: Color3?
): Product
	return {
		id = id,
		name = name,
		description = description,
		machine = "Workbench",
		inputs = inputs,
		time = time,
		art = art,
		color = color,
	}
end

table.insert(
	PRODUCTS,
	part("Gear", "Gear", "A cut iron gear, for building machines.", { IronBar = 2 }, 4, "SteelPlate", STEEL_COLOR)
)
table.insert(PRODUCTS, part("CopperWire", "Copper Wire", "Drawn copper, coiled.", { CopperBar = 1 }, 3, "CopperBar"))
table.insert(
	PRODUCTS,
	part(
		"Circuit",
		"Circuit",
		"Wire and a gear on a board.",
		{ CopperWire = 2, Gear = 1 },
		6,
		"CopperPlate",
		CIRCUIT_COLOR
	)
)
table.insert(
	PRODUCTS,
	part("SteelFrame", "Steel Frame", "A braced frame of iron and stone.", { IronBar = 4, Stone = 1 }, 6, "SteelPlate")
)

return PRODUCTS
