--!strict
-- Unlocks: what reaching a level opens, read from the content owners: a crafting tier upgrade
-- (Shared/Crafting), Gear Shop offers (Economy/Shops) and research projects (Shared/Research).
-- The level-up notice (FxService) and the Objective panel's "next unlock" share it.
--
-- A research project is named only when the Research window would show it: a category's first
-- project, or one that needs a finished project in its own category. Others are still "?" tiles
-- there, so they are only counted (`hidden`).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Research = require(ReplicatedStorage.Shared.Research)

export type Opened = {
	-- The crafting tier whose upgrade this level allows.
	tier: string?,
	-- Item names newly sold in the shops.
	offers: { string },
	-- Research project names, in catalogue order.
	research: { string },
	-- Research projects it opens that are still undiscovered.
	hidden: number,
}

local Unlocks = {}

-- The highest level that opens anything.
local last = 1
for _, each in Crafting.TIERS do
	last = math.max(last, each.level)
end
for _, shop in Shops.SHOPS do
	for _, offer in shop.offers do
		last = math.max(last, offer.level)
	end
end
for _, project in Research.PROJECTS do
	last = math.max(last, project.level)
end

local function discovered(project: Research.Project, done: { [string]: boolean }): boolean
	local root = true
	for _, id in project.needs do
		local need = Research.get(id)
		if need and need.category == project.category then
			root = false
			if done[id] then
				return true
			end
		end
	end
	return root
end

-- What level `level` opens for a player who has finished the research in `done`; nil when nothing.
function Unlocks.at(level: number, done: { [string]: boolean }): Opened?
	local opened: Opened = { tier = nil, offers = {}, research = {}, hidden = 0 }
	for tier, each in Crafting.TIERS do
		if tier > 1 and each.level == level then
			opened.tier = each.name
		end
	end
	for _, shop in Shops.SHOPS do
		for _, offer in shop.offers do
			if offer.level == level and level > 1 then
				table.insert(opened.offers, Inventory.getItem(offer.itemId).name)
			end
		end
	end
	table.sort(opened.offers)
	for _, project in Research.PROJECTS do
		if project.level == level and not done[project.id] then
			if discovered(project, done) then
				table.insert(opened.research, project.name)
			else
				opened.hidden += 1
			end
		end
	end
	if opened.tier or #opened.offers > 0 or #opened.research > 0 or opened.hidden > 0 then
		return opened
	end
	return nil
end

-- The first level past `level` that opens something, and what; nil when nothing is left.
function Unlocks.next(level: number, done: { [string]: boolean }): (number?, Opened?)
	for each = level + 1, last do
		local opened = Unlocks.at(each, done)
		if opened then
			return each, opened
		end
	end
	return nil, nil
end

-- "Machine Works crafting, Green Thumb I and new research": everything a level opens, as a list.
function Unlocks.describe(opened: Opened): string
	local names: { string } = {}
	if opened.tier then
		table.insert(names, `{opened.tier} crafting`)
	end
	table.move(opened.offers, 1, #opened.offers, #names + 1, names)
	table.move(opened.research, 1, #opened.research, #names + 1, names)
	if opened.hidden > 0 then
		table.insert(names, "new research")
	end
	if #names <= 1 then
		return names[1] or ""
	end
	return `{table.concat(names, ", ", 1, #names - 1)} and {names[#names]}`
end

return Unlocks
