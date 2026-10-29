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
local Mutations = { ALL = ALL }

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
