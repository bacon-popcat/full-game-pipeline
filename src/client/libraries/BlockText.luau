--!strict
-- BlockText: what a placed factory block's published attributes say, in words. The hover
-- panel (UIController/BlockInfo) and the machine panel (UIController/MachinePanel) both
-- show a block through here, so the two always word it the same way. It reads the
-- attributes FactoryService publishes on the block model: Status, Fuel, Contents, Output,
-- Progress, Sold, Earned, Slots, Powered, Filter, FilterRight and FilterMutations. What a
-- machine reaches comes from its def.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)

export type Row = { key: string, value: string }

-- Machine statuses that mean it is doing its job, for the "working" colour.
local WORKING = { Working = true, Selling = true, Feeding = true, Storing = true, Watering = true }

local BlockText = {}

function BlockText.itemName(itemId: string): string
	local ok, item = pcall(Inventory.getItem, itemId)
	return if ok then item.name else itemId
end

-- "IronOre:2,Coal:1" -> "2 Iron Ore · 1 Coal"; nil when empty.
local function describe(encoded: unknown, names: (string) -> string): string?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local parts = {}
	for id, count in string.gmatch(encoded, "([^:,]+):(%d+)") do
		table.insert(parts, `{count} {names(id)}`)
	end
	return table.concat(parts, " · ")
end

-- What the block is doing in a few words, and whether that counts as working. Nil for a
-- block with nothing to report (a filter conveyor).
function BlockText.status(model: Model, def: Factory.Def): (string?, boolean)
	if def.route == "Split" then
		local powered = model:GetAttribute("Powered") == true
		return if powered then "Powered: to the side" else "Unpowered: straight on", powered
	end
	local status = model:GetAttribute("Status")
	if typeof(status) ~= "string" then
		return nil, false
	end
	return status, WORKING[status] == true
end

export type Side = "Left" | "Right"

local SIDES: { Side } = { "Left", "Right" }
BlockText.SIDES = SIDES
-- What a filter's mutation checklist offers, in order: plain items, then each mutation.
local FILTER_MUTATIONS: { string } = table.clone(Mutations.ORDER)
table.insert(FILTER_MUTATIONS, 1, "Plain")
BlockText.FILTER_MUTATIONS = FILTER_MUTATIONS
-- The attribute FactoryService publishes each side's items in.
local SIDE_ATTRIBUTES: { [Side]: string } = { Left = "Filter", Right = "FilterRight" }

-- The row key naming what a filter conveyor sends to `side`, so a screen can find that row.
function BlockText.sideLabel(side: Side): string
	return `Sends {string.lower(side)}`
end

-- The mutations ticked on each of a filter conveyor's picks ("Plain" or a mutation name), by
-- the picked item; a pick with none ticked takes any.
function BlockText.filterMutations(model: Model): { [string]: { [string]: boolean } }
	local ticks: { [string]: { [string]: boolean } } = {}
	local encoded = model:GetAttribute("FilterMutations")
	if typeof(encoded) == "string" then
		for id, name in string.gmatch(encoded, "([^,:]+):(%a+)") do
			ticks[id] = ticks[id] or {}
			ticks[id][name] = true
		end
	end
	return ticks
end

-- The items a filter conveyor sends to a side, and which side; the rest go straight on.
function BlockText.filter(model: Model): { [string]: Side }
	local filtered: { [string]: Side } = {}
	for _, side in SIDES do
		local encoded = model:GetAttribute(SIDE_ATTRIBUTES[side])
		if typeof(encoded) == "string" then
			for id in string.gmatch(encoded, "[^,]+") do
				filtered[id] = side
			end
		end
	end
	return filtered
end

-- Whether the machine has finished items waiting, or loaded items not used yet.
function BlockText.hasOutput(model: Model): boolean
	return describe(model:GetAttribute("Output"), BlockText.itemName) ~= nil
end

function BlockText.hasContents(model: Model): boolean
	return describe(model:GetAttribute("Contents"), BlockText.itemName) ~= nil
end

-- "IronOre:2,Coal:1" -> { IronOre = 2, Coal = 1 }: what a machine holds, for a chest's grid.
function BlockText.contents(model: Model): { [string]: number }
	local counts = {}
	local encoded = model:GetAttribute("Contents")
	if typeof(encoded) == "string" then
		for id, count in string.gmatch(encoded, "([^:,]+):(%d+)") do
			counts[id] = tonumber(count) or 0
		end
	end
	return counts
end

-- Key/value rows describing the block. `withProgress` adds a Progress row, for panels
-- without a progress bar of their own.
function BlockText.rows(model: Model, def: Factory.Def, withProgress: boolean): { Row }
	local rows: { Row } = {}
	local function add(key: string, value: string?)
		if value and value ~= "" then
			table.insert(rows, { key = key, value = value })
		end
	end
	if def.kind == "Machine" then
		if def.fuel then
			local fuel = model:GetAttribute("Fuel")
			add("Fuel", if typeof(fuel) == "number" and fuel > 0 then `{fuel}s` else "Empty")
		end
		add("Holding", describe(model:GetAttribute("Contents"), BlockText.itemName))
		add("Output", describe(model:GetAttribute("Output"), BlockText.itemName))
		local progress = model:GetAttribute("Progress")
		if withProgress and typeof(progress) == "number" and progress > 0 then
			add("Progress", `{math.round(progress * 100)}%`)
		end
		local sold = model:GetAttribute("Sold")
		local earned = model:GetAttribute("Earned")
		if def.sells and typeof(sold) == "number" then
			add("Sold", if typeof(earned) == "number" then `{sold} for {earned} coins` else tostring(sold))
		end
		if def.sprinkles then
			local rule = def.sprinkles
			add("Reach", `{rule.radius} cells around`)
			add("Crops", `grow {math.round((rule.speed - 1) * 100)}% faster, +{math.round(rule.wet * 100)}% Wet`)
		end
		if def.produce and def.produce.radius then
			add("Reach", `{def.produce.radius} cells around`)
		end
		if def.plantSize then
			add("Plants", `{def.plantSize.width} wide, {def.plantSize.depth} deep in front`)
		end
		local slots = model:GetAttribute("Slots")
		if def.stores and typeof(slots) == "number" then
			add("Slots", `{slots} / {def.stores}`)
		end
	elseif def.route == "Filter" then
		local names: { [Side]: { string } } = { Left = {}, Right = {} }
		local ticks = BlockText.filterMutations(model)
		for id, side in BlockText.filter(model) do
			-- A pick narrowed to some mutations names them: "Carrot (Golden, Rainbow)".
			local ticked = {}
			for _, name in FILTER_MUTATIONS do
				if ticks[id] and ticks[id][name] then
					table.insert(ticked, name)
				end
			end
			local name = BlockText.itemName(id)
			table.insert(names[side], if #ticked > 0 then `{name} ({table.concat(ticked, ", ")})` else name)
		end
		for _, side in SIDES do
			local list = names[side]
			table.sort(list)
			add(BlockText.sideLabel(side), if #list > 0 then table.concat(list, ", ") else "Nothing yet")
		end
		add("Straight on", "Everything else")
	end
	return rows
end

return BlockText
