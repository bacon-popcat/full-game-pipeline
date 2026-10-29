--!strict
-- Blocks: what every factory block does, as data. FactoryService runs it; clients read it
-- to draw items and to know what a machine would take by hand. Recipes, fuels and timings
-- are authored here. Only the smelter needs fuel.
--
-- Geometry is in a block's authored frame (Factory.originFrame): its conveyor
-- runs down x = 0, +Z is the way items travel on a plain conveyor, and +X is the left of
-- that travel. `ext` is the block's hitbox in that frame (Factory.extents), so a lane or
-- port reaches exactly to a hitbox face, where the next block's port sits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Products = require(ReplicatedStorage.Shared.Factory.Products)
local World = require(ReplicatedStorage.Shared.World)

-- Belt surface height above a block's floor (the art's BELT_TOP).
local BELT = 1.59
local TIER1 = 4
local TIER2 = 8

export type Extents = { min: Vector3, max: Vector3 }

export type LaneDef = {
	points: { Vector3 },
	-- Studs per second.
	speed: number,
	-- The start takes items from a neighbour's exit; otherwise it starts at a router's hub.
	entry: boolean,
	-- The end hands items to a neighbour's entry; otherwise it ends at a router's hub.
	exit: boolean,
	-- The end feeds the block's machine: a machine's input belt, from its input face to
	-- where the belt meets the machine's port (Factory.lanes adds it).
	feeds: boolean?,
	-- The start takes the block's machine's finished items: a machine's output belt, from
	-- its port to its output face (Factory.lanes adds it).
	emits: boolean?,
}

export type Recipe = {
	inputs: { [string]: number },
	outputs: { [string]: number },
	-- Seconds per batch.
	time: number,
}

export type Source = {
	item: string,
	every: number,
	count: number?,
	-- The node is a ripe crop the machine reaps (it starts again from a sprout) for its item.
	reaps: boolean?,
}

export type Produce = {
	sources: { [string]: Source },
	-- In cells, from the block's centre.
	radius: number?,
}

export type Face = "-Z" | "+Z"

export type Def = {
	kind: "Conveyor" | "Router" | "Machine",
	-- Conveyor and Router.
	lanes: ((ext: Extents) -> { LaneDef })?,
	-- Router: which out-lane an item leaving the hub takes.
	route: ("Split" | "Merge" | "Random" | "Filter")?,
	-- Conveyor: flashes and powers neighbouring split conveyors as items pass.
	sensor: boolean?,
	-- Machine: the faces its conveyor meets, on the x = 0 axis. A face with no conveyor art
	-- still works, so a conveyor can be placed against it.
	input: Face?,
	output: Face?,
	recipes: { Recipe }?,
	-- Fuel item -> seconds of running it gives. Burns only while working.
	fuel: { [string]: number }?,
	produce: Produce?,
	-- Takes any item with a value and sells one a second for the block's owner.
	sells: boolean?,
	-- Chest: keeps whatever arrives in this many slots, each up to the item's stack size,
	-- until a player takes it out through the panel.
	stores: number?,
	-- Planter: the seeds it plants, tried in order, seconds per planting, and the centres of
	-- the cells it plants into, nearest first. A crop goes in at the planter's own level, or
	-- one cell up where a raised bed stands beside it (FactoryService).
	plants: { string }?,
	plantEvery: number?,
	plantArea: ((ext: Extents) -> { Vector3 })?,
	-- Planter: its patch in cells, for the panel's words.
	plantSize: { width: number, depth: number }?,
	-- Sprinkler: crops within `radius` cells on its plot grow `speed` times as fast and gain
	-- `wet` to their Wet chance. The best sprinkler over a crop counts; several don't stack.
	sprinkles: { radius: number, speed: number, wet: number }?,
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function conveyor(speed: number, sensor: boolean?): Def
	return {
		kind = "Conveyor",
		sensor = sensor,
		lanes = function(ext)
			return {
				{ points = { v(0, BELT, ext.min.Z), v(0, BELT, ext.max.Z) }, speed = speed, entry = true, exit = true },
			}
		end,
	}
end

-- side 1 turns left (+X), -1 right.
local function turn(speed: number, side: number): Def
	return {
		kind = "Conveyor",
		lanes = function(ext)
			local edge = if side > 0 then ext.max.X else ext.min.X
			return {
				{
					points = { v(0, BELT, ext.min.Z), v(0, BELT, 0), v(edge, BELT, 0) },
					speed = speed,
					entry = true,
					exit = true,
				},
			}
		end,
	}
end

-- rise 1 climbs one block toward +Z, -1 descends.
local function ramp(speed: number, rise: number): Def
	return {
		kind = "Conveyor",
		lanes = function(ext)
			local low, high = v(0, BELT, 0), v(0, BELT + 3, 0)
			local from, to = if rise > 0 then low else high, if rise > 0 then high else low
			return {
				{
					points = { from + v(0, 0, ext.min.Z), to + v(0, 0, ext.max.Z) },
					speed = speed,
					entry = true,
					exit = true,
				},
			}
		end,
	}
end

local function arm(from: Vector3, to: Vector3, entry: boolean): LaneDef
	return { points = { from, to }, speed = TIER1, entry = entry, exit = not entry }
end

-- Junction hubs: lane 1 is the back arm in; the rest depend on the route.
local function router(route: "Split" | "Merge" | "Random" | "Filter"): Def
	return {
		kind = "Router",
		route = route,
		lanes = function(ext)
			local hub = v(0, BELT, 0)
			local back, front = v(0, BELT, ext.min.Z), v(0, BELT, ext.max.Z)
			local right, left = v(ext.min.X, BELT, 0), v(ext.max.X, BELT, 0)
			if route == "Merge" then
				return { arm(back, hub, true), arm(front, hub, true), arm(hub, right, false) }
			elseif route == "Filter" then
				return { arm(back, hub, true), arm(hub, front, false), arm(hub, left, false), arm(hub, right, false) }
			end
			return { arm(back, hub, true), arm(hub, front, false), arm(hub, right, false) }
		end,
	}
end

local function recipe(inputs: { [string]: number }, outputs: { [string]: number }, time: number): Recipe
	return { inputs = inputs, outputs = outputs, time = time }
end

local function processor(recipes: { Recipe }, fuel: { [string]: number }?): Def
	return { kind = "Machine", input = "-Z", output = "+Z", recipes = recipes, fuel = fuel }
end

-- Every ripe crop, reaped for its produce.
local SEEDS: { string } = {}
for _, crop in World.CROPS do
	table.insert(SEEDS, crop.seed)
end
table.sort(SEEDS)

local function pickerSources(every: number): { [string]: Source }
	local sources: { [string]: Source } = {}
	for cropId, crop in World.CROPS do
		sources[World.cropStage(cropId, #World.STAGES)] =
			{ item = crop.produce, every = every, count = crop.yield, reaps = true }
	end
	return sources
end

-- `width` across and `depth` deep, centred on the forks and starting just past them, filled
-- row by row away from the planter, middle cell first.
local function plantPatch(width: number, depth: number): (ext: Extents) -> { Vector3 }
	return function(ext)
		local cells = {}
		for row = 0, depth - 1 do
			for column = 0, width - 1 do
				-- 0, -1, +1, -2, +2 ... cells from the middle.
				local side = math.ceil(column / 2) * (if column % 2 == 1 then -1 else 1)
				table.insert(cells, v(-3 + side * 3, 1.5, ext.min.Z - 1.5 - row * 3))
			end
		end
		return cells
	end
end

local function planter(width: number, depth: number, every: number): Def
	return {
		kind = "Machine",
		input = "+Z",
		plants = SEEDS,
		plantEvery = every,
		plantArea = plantPatch(width, depth),
		plantSize = { width = width, depth = depth },
	}
end

local function harvester(radius: number, every: number): Def
	return { kind = "Machine", output = "+Z", produce = { sources = pickerSources(every), radius = radius } }
end

local function sprinkler(radius: number, speed: number, wet: number): Def
	return { kind = "Machine", sprinkles = { radius = radius, speed = speed, wet = wet } }
end

-- The processing recipes Products lists for one machine.
-- The recipes Products lists for one machine, each taking `pace` times as long.
local function productRecipes(machine: string, pace: number?): { Recipe }
	local recipes = {}
	for _, product in Products do
		if product.machine == machine then
			table.insert(recipes, recipe(product.inputs, { [product.id] = 1 }, product.time * (pace or 1)))
		end
	end
	return recipes
end

local BLOCKS: { [string]: Def } = {
	ConveyorBelt = conveyor(TIER1),
	ConveyorBeltTier2 = conveyor(TIER2),
	ConveyorBeltLeft = turn(TIER1, 1),
	ConveyorBeltRight = turn(TIER1, -1),
	ConveyorBeltLeftTier2 = turn(TIER2, 1),
	ConveyorBeltRightTier2 = turn(TIER2, -1),
	ConveyorRamp = ramp(TIER1, 1),
	ConveyorRampDown = ramp(TIER1, -1),
	ConveyorRampTier2 = ramp(TIER2, 1),
	ConveyorRampDownTier2 = ramp(TIER2, -1),
	ConveyorSensor = conveyor(TIER1, true),

	SplitConveyor = router("Split"),
	Merger = router("Merge"),
	Randomizer = router("Random"),
	FilterConveyor = router("Filter"),

	Smelter = processor({
		recipe({ IronOre = 1 }, { IronBar = 1 }, 10),
		recipe({ CopperOre = 1 }, { CopperBar = 1 }, 10),
	}, { Coal = 30 }),
	Workbench = processor(productRecipes("Workbench")),
	Mill = processor(productRecipes("Mill")),
	MillTier2 = processor(productRecipes("Mill", 0.5)),
	Juicer = processor(productRecipes("Juicer")),
	Oven = processor(productRecipes("Oven")),
	CratePacker = processor(productRecipes("CratePacker")),
	Harvester = harvester(4, 3),
	HarvesterTier2 = harvester(6, 1.5),
	ShippingBin = { kind = "Machine", input = "-Z", sells = true },
	StorageChest = { kind = "Machine", input = "-Z", stores = 12 },
	SeedPlanter = planter(3, 5, 2),
	SeedPlanterTier2 = planter(5, 7, 1),
	Sprinkler = sprinkler(3, 1.25, 0.1),
	SprinklerTier2 = sprinkler(5, 1.5, 0.2),
}

return BLOCKS
