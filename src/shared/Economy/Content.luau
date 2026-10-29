--!strict
-- Content: rarity presentation, harvest XP and seed stock bands. Crop prices and
-- sell values belong to World.CROPS; an item's value already includes its mutation.
export type Rarity = { order: number, color: Color3, xp: number, min: number, max: number, chance: number }
local RARITIES: { [string]: Rarity } = {
	Common = { order = 1, color = Color3.fromRGB(166, 187, 157), xp = 1, min = 5, max = 15, chance = 1 },
	Uncommon = { order = 2, color = Color3.fromRGB(112, 185, 140), xp = 2, min = 3, max = 8, chance = 1 },
	Rare = { order = 3, color = Color3.fromRGB(115, 162, 219), xp = 4, min = 1, max = 4, chance = 0.6 },
	Epic = { order = 4, color = Color3.fromRGB(180, 137, 211), xp = 8, min = 1, max = 2, chance = 0.25 },
	Legendary = { order = 5, color = Color3.fromRGB(221, 178, 92), xp = 15, min = 1, max = 1, chance = 0.08 },
	Mythic = { order = 6, color = Color3.fromRGB(223, 133, 167), xp = 30, min = 1, max = 1, chance = 0.02 },
}
return { RESTOCK_SECONDS = 300, RARITIES = RARITIES }
