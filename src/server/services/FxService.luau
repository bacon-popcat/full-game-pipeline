-- FxService: turns garden events (server/libraries/GardenEvents) into moments clients show and
-- sound (Remotes.Fx -> FxController). Planting, harvesting and watering are seen by everyone near;
-- sales, purchases and level-ups are the player's own. A level-up also says what it unlocked.
-- Cosmetic only: nothing here changes the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Build = require(ReplicatedStorage.Shared.Build)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local World = require(ReplicatedStorage.Shared.World)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)

local FxService = {}

-- The top centre of a crop's cell, where its effects start.
local function cellTop(cell: Vector3): Vector3
	return Build.box(cell, Vector3.one).Position - Vector3.yAxis * (Build.GRID / 2 - 0.4)
end

-- "Level 6! Now in the Machine Shop: Harvester." or just "Level 6!".
local function levelMessage(level: number): string
	local names = {}
	for _, shop in Shops.SHOPS do
		for _, offer in shop.offers do
			if offer.level == level then
				table.insert(names, Inventory.getItem(offer.itemId).name)
			end
		end
	end
	table.sort(names)
	return if #names > 0 then `Level {level}! New in the shops: {table.concat(names, ", ")}.` else `Level {level}!`
end

function FxService.init()
	GardenEvents.Planted:Connect(function(_: Player, cell: Vector3, seedId: string)
		Remotes.Fx:FireAllClients({ kind = "Plant", position = cellTop(cell), itemId = seedId })
	end)
	GardenEvents.Harvested:Connect(function(_: Player, cropId: string, mutation: string?, cell: Vector3)
		local crop = World.CROPS[cropId]
		Remotes.Fx:FireAllClients({
			kind = "Harvest",
			position = cellTop(cell) + Vector3.yAxis * 0.8,
			itemId = if crop then crop.produce else cropId,
			mutation = mutation,
		})
	end)
	GardenEvents.Watered:Connect(function(_: Player, cell: Vector3)
		Remotes.Fx:FireAllClients({ kind = "Water", position = cellTop(cell) })
	end)
	GardenEvents.Sold:Connect(function(player: Player, coins: number, at: Vector3?)
		Remotes.Fx:FireClient(player, { kind = "Sell", amount = coins, position = at })
	end)
	GardenEvents.Bought:Connect(function(player: Player, itemId: string)
		Remotes.Fx:FireClient(player, { kind = "Buy", itemId = itemId })
	end)
	GardenEvents.LevelUp:Connect(function(player: Player, level: number)
		Remotes.Fx:FireClient(player, { kind = "LevelUp", amount = level })
		Remotes.Notify:FireClient(player, levelMessage(level))
	end)
end

return FxService
