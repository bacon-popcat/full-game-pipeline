--!strict
-- Mutations: variants a ripe crop can carry, their value multipliers and visual colours.
-- They stack: each mutation rolls on its own when a crop ripens, so one harvest can be Wet
-- and Golden at once. A set of mutations is written as a key, its names in ORDER joined by
-- "+" ("Wet+Golden"); an item id is its base id, "+", then the key (`Carrot+Wet+Golden`).
--
-- A set's multiplier adds up each mutation's bonus over plain: 1 + the sum of (multiplier - 1),
-- so Wet (x2) and Golden (x20) together are x21, never x40.

export type Mutation = { multiplier: number, color: Color3 }
export type Chances = { wet: number, shocked: number, golden: number, rainbow: number?, multiplier: number? }
local ALL: { [string]: Mutation } = {
	Wet = { multiplier = 2, color = Color3.fromRGB(135, 194, 234) },
	Shocked = { multiplier = 10, color = Color3.fromRGB(193, 173, 244) },
	Golden = { multiplier = 20, color = Color3.fromRGB(250, 211, 112) },
	Rainbow = { multiplier = 50, color = Color3.fromRGB(235, 153, 206) },
}
local RAINBOW_CHANCE = 0.001
-- Every mutation, from the least to the most valuable: the order a key names them in, and
-- the order anything that lists them uses (the filter conveyor's checklist).
local ORDER: { string } = {}
for name in ALL do
	table.insert(ORDER, name)
end
table.sort(ORDER, function(a, b)
	return ALL[a].multiplier < ALL[b].multiplier
end)
local Mutations = { ALL = ALL, ORDER = ORDER }

-- The canonical key for a set of mutation names, or nil for none. Unknown names are dropped.
function Mutations.key(names: { string }): string?
	local present: { [string]: boolean } = {}
	for _, name in names do
		present[name] = true
	end
	local ordered = {}
	for _, name in ORDER do
		if present[name] and ALL[name] then
			table.insert(ordered, name)
		end
	end
	return if #ordered > 0 then table.concat(ordered, "+") else nil
end

-- The names in a key, in ORDER; nil unless it is a canonical key of known, distinct names
-- (so it also validates keys from saves).
function Mutations.parse(key: string): { string }?
	local names = string.split(key, "+")
	return if Mutations.key(names) == key then names else nil
end

function Mutations.multiplier(names: { string }): number
	local total = 1
	for _, name in names do
		total += ALL[name].multiplier - 1
	end
	return total
end

-- The colour a set shows as: its most valuable mutation's.
function Mutations.color(names: { string }): Color3
	return ALL[names[#names]].color
end

-- Every set of one or more mutations as a key, from the least to the most valuable (ties by
-- key): Machine tries batches in this order, after plain.
local KEYS: { string } = {}
for mask = 1, 2 ^ #ORDER - 1 do
	local names = {}
	for bit, name in ORDER do
		if bit32.btest(mask, 2 ^ (bit - 1)) then
			table.insert(names, name)
		end
	end
	table.insert(KEYS, table.concat(names, "+"))
end
table.sort(KEYS, function(a, b)
	local ma, mb = Mutations.multiplier(string.split(a, "+")), Mutations.multiplier(string.split(b, "+"))
	return if ma ~= mb then ma < mb else a < b
end)
Mutations.KEYS = KEYS

-- One ripening's mutations as a key, nil for plain: each mutation rolls on its own chance.
function Mutations.roll(random: Random, chances: Chances): string?
	local rolls = { Wet = chances.wet, Shocked = chances.shocked, Golden = chances.golden, Rainbow = RAINBOW_CHANCE + (chances.rainbow or 0) }
	local names = {}
	for _, name in ORDER do
		if random:NextNumber() < math.clamp(rolls[name] * (chances.multiplier or 1), 0, 1) then
			table.insert(names, name)
		end
	end
	return Mutations.key(names)
end

return Mutations
