--!strict
-- Sounds: the game's sound palette, one entry per role. Generated with ElevenLabs sound effects in
-- one family of material words (warm wood, soil, soft chimes; never voice or melody), imported into
-- the place as audio assets. A role with no id yet plays nothing, so the game is whole when muted.
-- Volumes sit well under music level: these confirm a moment, they never announce one.

export type Role = { id: string, volume: number, spatial: boolean }

local ROLES: { [string]: Role } = {
	-- a seed pressed into soil
	Plant = { id = "", volume = 0.35, spatial = true },
	-- a crop picked or reaped
	Harvest = { id = "", volume = 0.45, spatial = true },
	-- coins earned at the Sell Stand or by a Shipping Bin
	Coin = { id = "", volume = 0.4, spatial = false },
	-- a purchase at a stall
	Buy = { id = "", volume = 0.4, spatial = false },
	-- a watering can splash
	Water = { id = "", volume = 0.4, spatial = true },
	-- an onboarding step done
	Step = { id = "", volume = 0.45, spatial = false },
	-- a new level
	LevelUp = { id = "", volume = 0.5, spatial = false },
}

return ROLES
