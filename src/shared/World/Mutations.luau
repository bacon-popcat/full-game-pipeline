--!strict
-- Mutations: exclusive variants, their value multipliers and visual colours. One draw per
-- ripe cycle gives each variant its stated probability; the remaining interval is plain.

export type Mutation = { multiplier: number, color: Color3 }
export type Chances = { wet: number, shocked: number, golden: number }
local ALL: { [string]: Mutation } = {
	Wet = { multiplier = 2, color = Color3.fromRGB(135, 194, 234) },
	Shocked = { multiplier = 10, color = Color3.fromRGB(193, 173, 244) },
	Golden = { multiplier = 20, color = Color3.fromRGB(250, 211, 112) },
	Rainbow = { multiplier = 50, color = Color3.fromRGB(235, 153, 206) },
}
-- Every mutation, from the least to the most valuable, for anything that lists or tries them
-- in order (Machine's batches, the filter conveyor's checklist).
local ORDER: { string } = {}
for name in ALL do
	table.insert(ORDER, name)
end
table.sort(ORDER, function(a, b)
	return ALL[a].multiplier < ALL[b].multiplier
end)
local Mutations = { ALL = ALL, ORDER = ORDER }

function Mutations.roll(random: Random, chances: Chances): string?
	local rolls = { Rainbow = 0.001, Golden = chances.golden, Shocked = chances.shocked, Wet = chances.wet }
	local roll = random:NextNumber()
	for _, name in { "Rainbow", "Golden", "Shocked", "Wet" } do
		if roll < rolls[name] then
			return name
		end
		roll -= rolls[name]
	end
	return nil
end

return Mutations
