--!strict
-- ItemDetails: the facts an item's info panel lists (the backpack's sidebar and the Index's),
-- as key/value rows in display order, and the painter that shows them. Rows are clones of
-- Assets.UI.Inventory.InfoRow (Key and Value labels) kept in the panel's Rows frame ahead of
-- its authored Description, which keeps its own LayoutOrder.
--
-- Every number comes from shared content (Items, World.CROPS, Shops); nothing here decides one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)
local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local World = require(ReplicatedStorage.Shared.World)
local Hud = require(script.Parent.Hud)

export type Row = { key: string, value: string, color: Color3? }

local ROW_PREFIX = "Detail"

-- The crop an item is the seed or (any mutation of the) produce of.
local cropOf: { [string]: World.Crop } = {}
for _, crop in World.CROPS do
	cropOf[crop.seed] = crop
	cropOf[crop.produce] = crop
end

local ItemDetails = {}

local function coins(value: number): string
	return Hud.number(value) .. " coins"
end

-- "1:30" under an hour, "1h 05m" from one.
local function duration(seconds: number): string
	if seconds < 3600 then
		return Hud.time(seconds)
	end
	local minutes = math.floor(seconds / 60)
	return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

-- The rows for `item`, with `count` of it in a slot when it is in one.
function ItemDetails.rows(item: Inventory.Item, count: number?): { Row }
	local rows: { Row } = {}
	local function add(key: string, value: string, color: Color3?)
		table.insert(rows, { key = key, value = value, color = color })
	end
	if count then
		add("Amount", `{count} / {item.stack}`)
	else
		add("Stacks to", tostring(item.stack))
	end
	if item.value then
		add("Sell value", coins(item.value))
		if count and count > 1 then
			add("Stack value", coins(item.value * count))
		end
	end
	if item.mutations then
		-- The name already lists the mutations; this says what they are worth together.
		add("Mutation bonus", `x{Mutations.multiplier(item.mutations)}`, Mutations.color(item.mutations))
	end
	local crop = cropOf[item.base or item.id]
	if crop then
		local rarity = Content.RARITIES[crop.rarity]
		add("Rarity", crop.rarity, if rarity then rarity.color else nil)
		-- A slot of produce keeps to what it is worth; its seeds and the Index say how it grows.
		local isSeed = item.id == crop.seed
		if isSeed or not count then
			add("Grow time", duration(crop.grow))
			if crop.regrow then
				add("Regrows in", duration(crop.regrow))
			end
			add("Harvest", `{crop.yield} {crop.name}`)
		end
		if isSeed then
			add("Seed price", coins(crop.price))
		end
	end
	for shopId in Shops.SHOPS do
		local offer = Shops.find(shopId, item.id)
		if offer then
			add("Shop price", if offer.level > 1 then `{coins(offer.price)} (Lv {offer.level})` else coins(offer.price))
		end
	end
	if Inventory.isPlaceable(item) and not crop then
		local footprint = Build.footprint(item.id, 0)
		if footprint then
			add("Footprint", `{footprint.X} x {footprint.Z} x {footprint.Y}`)
		end
	end
	return rows
end

-- Shows `rows` in `frame` (a panel's Rows), cloning `template` as needed; spare rows hide.
function ItemDetails.paint(frame: Instance, template: Frame, rows: { Row })
	for index, row in rows do
		local node = frame:FindFirstChild(ROW_PREFIX .. index)
		if not node then
			node = template:Clone()
			node.Name = ROW_PREFIX .. index
			node.Parent = frame
		end
		assert(node and node:IsA("Frame"))
		node.LayoutOrder = index
		node.Visible = true
		local key, value = node:FindFirstChild("Key"), node:FindFirstChild("Value")
		if key and key:IsA("TextLabel") and value and value:IsA("TextLabel") then
			key.Text = row.key
			value.Text = row.value
			value.TextColor3 = row.color or (template:FindFirstChild("Value") :: TextLabel).TextColor3
		end
	end
	local index = #rows + 1
	while true do
		local spare = frame:FindFirstChild(ROW_PREFIX .. index)
		if not spare or not spare:IsA("GuiObject") then
			break
		end
		spare.Visible = false
		index += 1
	end
end

return ItemDetails
