--!strict
-- Sounds: the game's sound palette, one entry per role. Generated with ElevenLabs sound effects in
-- one family of material words (warm wood, soil, soft chimes; never voice or melody), uploaded from
-- assets/sounds as audio assets through Open Cloud. A role with no id plays nothing, so the game is
-- whole when muted.
-- Volumes sit well under music level: these confirm a moment, they never announce one.

export type Role = { id: string, volume: number, spatial: boolean }

local ROLES: { [string]: Role } = {
	-- a seed pressed into soil
	Plant = { id = "rbxassetid://90385484162031", volume = 0.35, spatial = true },
	-- a crop picked or reaped
	Harvest = { id = "rbxassetid://140384005911871", volume = 0.45, spatial = true },
	-- coins earned at the Sell Stand or by a Shipping Bin
	Coin = { id = "rbxassetid://126449219917694", volume = 0.4, spatial = false },
	-- a purchase at a stall
	Buy = { id = "rbxassetid://133840506516150", volume = 0.4, spatial = false },
	-- a watering can splash
	Water = { id = "rbxassetid://95345293500300", volume = 0.4, spatial = true },
	-- an onboarding step done
	Step = { id = "rbxassetid://110055073598907", volume = 0.45, spatial = false },
	-- a new level
	LevelUp = { id = "rbxassetid://138182978724965", volume = 0.5, spatial = false },
}

return ROLES
