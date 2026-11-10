--!strict
-- Sounds: the game's sound palette, one entry per role. Generated with ElevenLabs sound effects in
-- one family of material words (warm wood, soil, soft chimes; never voice or melody), or for the
-- phase 7 roles synthesized in that family by tools/sounds/synth.py, and uploaded from
-- assets/sounds as audio assets through Open Cloud. A role with no id plays nothing, so the game is
-- whole when muted.
-- Volumes sit well under music level: these confirm a moment, they never announce one.

export type Role = { id: string, volume: number, spatial: boolean }

local ROLES: { [string]: Role } = {
	-- a seed pressed into soil
	Plant = { id = "rbxassetid://90385484162031", volume = 0.35, spatial = true },
	-- a crop picked or reaped: leaves, a stem snapping, soil crumbling (the phase 7 pop was
	-- rbxassetid://85383832508508, the ElevenLabs pluck before it rbxassetid://140384005911871)
	Harvest = { id = "rbxassetid://121632984070614", volume = 0.5, spatial = true },
	-- layered over Harvest when the crop came out mutated
	HarvestRare = { id = "rbxassetid://126550585056131", volume = 0.3, spatial = true },
	-- an axe biting into a forest tree, and the tree coming down
	Chop = { id = "rbxassetid://136761976782388", volume = 0.45, spatial = true },
	TreeFall = { id = "rbxassetid://118623246906163", volume = 0.4, spatial = true },
	-- something crafted in the Crafting window
	Craft = { id = "rbxassetid://104446383390823", volume = 0.4, spatial = false },
	-- a research project finished
	ResearchDone = { id = "rbxassetid://82850696869958", volume = 0.45, spatial = false },
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
