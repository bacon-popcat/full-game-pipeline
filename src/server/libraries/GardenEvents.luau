--!strict
-- GardenEvents: what a player just did in their garden, announced once by the service that did it, so
-- onboarding (OnboardingService) and feedback (FxService) can listen without the gameplay services
-- knowing about either. Only live actions fire: restoring a saved garden never does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

local GardenEvents = {
	-- (player, cell: Vector3, seedId: string) a seed planted by hand
	Planted = Signal.new(),
	-- (player, itemId: string, model: Model) a block or machine placed by hand
	Placed = Signal.new(),
	-- (player, cropId: string, mutation: string?, cell: Vector3) a ripe crop on the player's plot
	-- harvested, by hand or by a machine
	Harvested = Signal.new(),
	-- (player, coins: number, at: Vector3?) a sale: at the Sell Stand (no position) or by a
	-- Shipping Bin (its position)
	Sold = Signal.new(),
	-- (player, itemId: string, count: number) a purchase at a hub stall
	Bought = Signal.new(),
	-- (player, level: number) the player's level went up
	LevelUp = Signal.new(),
	-- (player, cell: Vector3) a growing crop splashed with the watering can
	Watered = Signal.new(),
}

return GardenEvents
