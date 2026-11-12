--!strict
-- Brand: the game's name, tagline and title colours, and the loading screen's tips. It lives in
-- ReplicatedFirst so the loading screen has it before anything else arrives; any other screen
-- that shows the name reads it from here (ReplicatedFirst.Brand) rather than spelling it out.
local Brand = {}

Brand.NAME = "Seedworks"
Brand.TAGLINE = "GROW  ·  BUILD  ·  AUTOMATE"

-- The title in two halves, each with its top and bottom gradient colours: the green of a
-- sprout, then the gold of a coin and a machine's brass.
Brand.TITLE = {
	{ text = "SEED", top = Color3.fromRGB(196, 248, 160), bottom = Color3.fromRGB(86, 196, 112) },
	{ text = "WORKS", top = Color3.fromRGB(255, 232, 150), bottom = Color3.fromRGB(240, 156, 64) },
}

-- One is shown at a time while the game loads; Shared/TextColors paints them once it is there.
Brand.TIPS = {
	"Shipping Bins keep earning coins while you're away.",
	"The Seed Shop restocks every 5m, and rare seeds come with a notice.",
	"Mutated crops sell for many times more than plain ones.",
	"Conveyors carry harvests from a Harvester straight to a Shipping Bin.",
	"Research makes crops grow faster and machines work harder.",
	"Press C anywhere to open Crafting.",
	"Daily quests and orders pay extra coins and XP.",
	"Leave a like at a garden you enjoy, at its sign.",
	"Upgrade machines to Mk II and beyond with materials from the quarry.",
}

return Brand
