--!strict
-- Ground: what a garden's earth is made of, level by level, before anyone digs it. Every cell of
-- a garden's owned land from y = -1 down to Plot.FLOOR is ground: grass on top (the starter
-- farm's Farmland in its place), DIRT_LEVELS of dirt under it, then stone. GroundService builds
-- it, digs it and tills it, and saves only where it differs from this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Plot = require(ReplicatedStorage.Shared.Plot)

-- The ground's top level: the grass the garden stands on, its top flush with y = 0.
local SURFACE = -1
-- Levels of dirt between the grass and the stone.
local DIRT_LEVELS = 2

local Ground = {}

Ground.SURFACE = SURFACE
-- Seconds Farmland stays wet once nothing keeps it wet (a sprinkler over it, or rain).
Ground.WET_FOR = 120

-- Whether a plot-relative cell is on the starter farm.
function Ground.onFarm(relative: Vector3): boolean
	return relative.Y == Plot.FARM_LOW.Y
		and relative.X >= Plot.FARM_LOW.X
		and relative.X <= Plot.FARM_HIGH.X
		and relative.Z >= Plot.FARM_LOW.Z
		and relative.Z <= Plot.FARM_HIGH.Z
end

-- The node a plot-relative cell holds before it is dug or tilled, or nil above the ground and
-- below the floor.
function Ground.natural(relative: Vector3): string?
	local y = relative.Y
	if y > SURFACE or y < Plot.FLOOR then
		return nil
	elseif Ground.onFarm(relative) then
		return "Farmland"
	elseif y == SURFACE then
		return "GrassGround"
	elseif y >= SURFACE - DIRT_LEVELS then
		return "DirtGround"
	end
	return "StoneGround"
end

return Ground
