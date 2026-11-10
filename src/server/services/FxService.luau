-- FxService: turns garden events (server/libraries/GardenEvents) into moments clients show and
-- sound (Remotes.Fx -> FxController). Planting, harvesting, watering and chopping are seen by
-- everyone near; sales, purchases, crafts, finished research and level-ups are the player's own.
-- A level-up also says what it unlocked.
-- Cosmetic only: nothing here changes the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Build = require(ReplicatedStorage.Shared.Build)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local Unlocks = require(ReplicatedStorage.Shared.Unlocks)
local World = require(ReplicatedStorage.Shared.World)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)

local FxService = {}

-- The top centre of a crop's cell, where its effects start.
local function cellTop(cell: Vector3): Vector3
	return Build.box(cell, Vector3.one).Position - Vector3.yAxis * (Build.GRID / 2 - 0.4)
end

-- What the level opened for this player (Shared/Unlocks): "Level 6! You can now upgrade crafting
-- to Machine Works. New research too.", "Level 13! New research: Haggling II.", "Level 4! New in
-- the shops: ..." or just "Level 21!". A crafting tier keeps its notice short.
local function levelMessage(player: Player, level: number): string
	local done: { [string]: boolean } = {}
	for _, project in Research.PROJECTS do
		done[project.id] = Bonuses.has(player, project.id)
	end
	local opened = Unlocks.at(level, done)
	local parts = { `Level {level}!` }
	if opened then
		local research = #opened.research > 0 or opened.hidden > 0
		if opened.tier then
			table.insert(parts, `You can now upgrade crafting to {opened.tier}.`)
			if research then
				table.insert(parts, "New research too.")
			end
			return table.concat(parts, " ")
		end
		if #opened.offers > 0 then
			table.insert(parts, `New in the shops: {table.concat(opened.offers, ", ")}.`)
		end
		if #opened.research > 0 then
			table.insert(parts, `New research: {table.concat(opened.research, ", ")}.`)
		elseif opened.hidden > 0 then
			table.insert(parts, "New research to discover.")
		end
	end
	return table.concat(parts, " ")
end

function FxService.init()
	GardenEvents.Planted:Connect(function(_: Player, cell: Vector3, seedId: string)
		Remotes.Fx:FireAllClients({ kind = "Plant", position = cellTop(cell), itemId = seedId })
	end)
	GardenEvents.Harvested:Connect(function(player: Player, cropId: string, mutation: string?, cell: Vector3)
		local crop = World.CROPS[cropId]
		Remotes.Fx:FireAllClients({
			kind = "Harvest",
			position = cellTop(cell) + Vector3.yAxis * 0.8,
			itemId = if crop then crop.produce else cropId,
			mutation = mutation,
			by = player.UserId,
		})
	end)
	GardenEvents.Chopped:Connect(function(player: Player, _: string, _: Vector3, look: string, pivot: CFrame)
		local character = player.Character
		Remotes.Fx:FireAllClients({
			kind = "Chop",
			position = pivot.Position,
			pivot = pivot,
			look = look,
			from = if character then character:GetPivot().Position else nil,
		})
	end)
	GardenEvents.Crafted:Connect(function(player: Player, recipeId: string)
		local recipe = Crafting.get(recipeId)
		Remotes.Fx:FireClient(player, { kind = "Craft", itemId = if recipe then recipe.output else nil })
	end)
	GardenEvents.ResearchDone:Connect(function(player: Player)
		Remotes.Fx:FireClient(player, { kind = "Research" })
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
	GardenEvents.SectionBought:Connect(function(player: Player)
		Remotes.Fx:FireClient(player, { kind = "Buy" })
	end)
	GardenEvents.LevelUp:Connect(function(player: Player, level: number)
		Remotes.Fx:FireClient(player, { kind = "LevelUp", amount = level })
		Remotes.Notify:FireClient(player, levelMessage(player, level), "Reward")
	end)
end

return FxService
