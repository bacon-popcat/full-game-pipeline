--!strict
-- Sounds: the game's sound palette, one entry per role, uploaded from assets/sounds as audio assets
-- through Open Cloud (assets/sounds/README.md has each role's file, recipe and earlier ids). The
-- game cues are bright and bouncy in a Roblox-simulator way (blips, bubble pops, quick arpeggios,
-- sparkles), synthesized by tools/sounds/synth.py; Water is an ElevenLabs take and Chop and
-- TreeFall are synthesized in a material family (wood, leaves). A role with no id plays nothing, so
-- the game is whole when muted.
-- Volumes sit well under music level and are balanced by measured loudness: these confirm a
-- moment, they never announce one.

export type Role = { id: string, volume: number, spatial: boolean }

local ROLES: { [string]: Role } = {
	-- a seed popped into soil: a bubbly bloop
	Plant = { id = "rbxassetid://108581884979353", volume = 0.25, spatial = true },
	-- a crop picked or reaped: a leafy tug, a stem snap and a bright pop
	Harvest = { id = "rbxassetid://120566065392427", volume = 0.25, spatial = true },
	-- layered over Harvest when the crop came out mutated: a twinkling run up
	HarvestRare = { id = "rbxassetid://116274355495687", volume = 0.3, spatial = true },
	-- an axe biting into a forest tree, and the tree coming down
	Chop = { id = "rbxassetid://110876799577978", volume = 0.45, spatial = true },
	TreeFall = { id = "rbxassetid://97110688548965", volume = 0.4, spatial = true },
	-- something crafted in the Crafting window
	Craft = { id = "rbxassetid://104827661586586", volume = 0.3, spatial = false },
	-- a research project finished
	ResearchDone = { id = "rbxassetid://110212030422183", volume = 0.5, spatial = false },
	-- coins earned at the Sell Stand (a Shipping Bin's sales are silent)
	Coin = { id = "rbxassetid://80805932029640", volume = 0.32, spatial = false },
	-- a purchase at a stall
	Buy = { id = "rbxassetid://118394111171147", volume = 0.32, spatial = false },
	-- a watering can splash
	Water = { id = "rbxassetid://95345293500300", volume = 0.4, spatial = true },
	-- an onboarding step done
	Step = { id = "rbxassetid://110150377452756", volume = 0.4, spatial = false },
	-- a new level: an arpeggio up to a ringing chord
	LevelUp = { id = "rbxassetid://78053196984145", volume = 0.5, spatial = false },
	-- notices, by kind (Shared/Notices): a refusal's low "nuh-uh", a reward's three-note bling,
	-- and the banner's five-note run over a swell
	NoticeError = { id = "rbxassetid://94091563133765", volume = 0.16, spatial = false },
	NoticeReward = { id = "rbxassetid://115224806235121", volume = 0.4, spatial = false },
	NoticeBanner = { id = "rbxassetid://103094767156685", volume = 0.45, spatial = false },
	-- the interface (client/libraries/UISound decides when): the pointer reaching a button, a
	-- press, a window opening and closing, and a press on a button that is not available. The
	-- quietest roles here, since they play the most
	UIHover = { id = "rbxassetid://131744800074021", volume = 0.07, spatial = false },
	UIClick = { id = "rbxassetid://124062174863160", volume = 0.22, spatial = false },
	UIOpen = { id = "rbxassetid://91011286793855", volume = 0.24, spatial = false },
	UIClose = { id = "rbxassetid://72266303509782", volume = 0.16, spatial = false },
	UIDeny = { id = "rbxassetid://135241996192619", volume = 0.16, spatial = false },
}

return ROLES
