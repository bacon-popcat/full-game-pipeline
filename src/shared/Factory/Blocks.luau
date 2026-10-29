--!strict
-- Blocks: what every factory block does, as data. FactoryService runs it; clients read it
-- to draw items and to know what a machine would take by hand. Recipes, fuels and timings
-- follow the Islands wiki, simplified where this kit has no part for it (no pipes: oil and
-- petroleum ride conveyors as items; wood tubes carry sap and syrup).
--
-- Geometry is in a block's authored frame (Factory.originFrame): its conveyor or tube
-- runs down x = 0, +Z is the way items travel on a plain conveyor, and +X is the left of
-- that travel. `ext` is the block's hitbox in that frame (Factory.extents), so a lane or
-- port reaches exactly to a hitbox face, where the next block's port sits.

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
	-- A fluid drawn from the wood tube network instead of (or as well as) items.
	fluidIn: string?,
	-- A fluid pushed into the wood tube network.
	fluidOut: string?,
}

export type Source = { item: string, every: number, count: number? }

export type Produce = {
	-- Below: a node in a cell under the footprint (deposits). Near: a node within
	-- `radius`. Tree: a node in `treeCell`. Animals: a fed animal within `radius`.
	where: "Below" | "Near" | "Tree" | "Animals",
	-- Node or animal type -> what it yields.
	sources: { [string]: Source },
	-- In cells, from the block's centre.
	radius: number?,
	-- Tree only: chop the tree down and output its drops instead of `sources`' item.
	cuts: boolean?,
}

export type Face = "-Z" | "+Z"

export type Def = {
	kind: "Conveyor" | "Router" | "Machine" | "Tube",
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
	-- Anything arriving at the input rides straight through to the output.
	passThrough: boolean?,
	-- Studs of belt at each end face for a machine whose belt runs clear through its art, so
	-- the art gives no port depth to measure (Factory.lanes).
	belt: number?,
	-- Takes any resource and sells one a second.
	sells: boolean?,
	-- Chest: keeps whatever arrives in this many slots, each up to the item's stack size,
	-- until a player takes it out through the panel.
	stores: number?,
	-- Food it keeps to feed animals within `feedRadius` cells.
	feeds: { [string]: boolean }?,
	feedRadius: number?,
	-- Planter: the item it plants into `treeCell`, and seconds per planting.
	plants: string?,
	plantEvery: number?,
	-- Tree and planter machines: centre of the cell they work on.
	treeCell: ((ext: Extents) -> Vector3)?,
	-- Connects to wood tubes touching any face.
	tubes: boolean?,
	-- Tube: the faces it opens onto, as outward normals.
	openings: { Vector3 }?,
	-- Tube: shapes itself to what it joins (FactoryService): straight, corner, up, down or an
	-- elbow, drawn with the WoodTube* art in Assets.Blocks. Its openings are worked out there.
	auto: boolean?,
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

local function tube(openings: { Vector3 }): Def
	return { kind = "Tube", openings = openings }
end

local function recipe(inputs: { [string]: number }, outputs: { [string]: number }, time: number): Recipe
	return { inputs = inputs, outputs = outputs, time = time }
end

local function processor(recipes: { Recipe }, fuel: { [string]: number }?): Def
	return { kind = "Machine", input = "-Z", output = "+Z", recipes = recipes, fuel = fuel }
end

-- Fuel tables: coal and petrified petroleum, by how long a machine runs on one.
local COAL_20 = { Coal = 20, PetrifiedPetroleum = 40 }
local COAL_30 = { Coal = 30, PetrifiedPetroleum = 60 }
local COAL_50 = { Coal = 50, PetrifiedPetroleum = 100 }
local COAL_60 = { Coal = 60, PetrifiedPetroleum = 120 }
local PETROLEUM_60 = { Petroleum = 60 }

local TREES = { "OakTree", "MapleTree", "AppleTree" }

local function treeSources(item: string, every: number): { [string]: Source }
	local sources = {}
	for _, tree in TREES do
		sources[tree] = { item = item, every = every }
	end
	return sources
end

-- The cell just past a lumbermill's tower (+Z), and just past a planter's or shaker's forks
-- (on the -X column, beyond -Z).
local function pastTower(ext: Extents): Vector3
	return v(0, 1.5, ext.max.Z + 1.5)
end

local function pastForks(ext: Extents): Vector3
	return v(-3, 1.5, ext.min.Z - 1.5)
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

	WoodTube = { kind = "Tube", auto = true },
	WoodTubeMerger = tube({ v(-1, 0, 0), v(1, 0, 0), v(0, 0, -1) }),

	Drill = {
		kind = "Machine",
		input = "+Z",
		output = "-Z",
		fuel = COAL_30,
		produce = {
			where = "Below",
			sources = {
				CopperDeposit = { item = "CopperOre", every = 5 },
				GoldDeposit = { item = "GoldOre", every = 120 },
			},
		},
	},
	Pumpjack = {
		kind = "Machine",
		output = "-Z",
		fuel = COAL_60,
		produce = { where = "Below", sources = { OilDeposit = { item = "Oil", every = 5 } } },
	},
	IndustrialLumbermill = {
		kind = "Machine",
		output = "-Z",
		fuel = COAL_50,
		produce = { where = "Tree", sources = treeSources("Log", 10), cuts = true },
		treeCell = pastTower,
	},
	IndustrialSawmill = processor({ recipe({ Log = 1 }, { WoodPlanks = 2 }, 15) }, COAL_50),
	IndustrialStonecutter = processor({ recipe({ Stone = 1 }, { StoneBricks = 1 }, 16) }, COAL_50),
	IndustrialSmelter = processor({
		recipe({ IronOre = 1 }, { IronBar = 1 }, 10),
		recipe({ CopperOre = 1 }, { CopperBar = 1 }, 10),
		recipe({ GoldOre = 1 }, { GoldBar = 1 }, 10),
	}, COAL_30),
	IndustrialPolishingStation = processor({ recipe({ Stone = 1 }, { SmoothStone = 1 }, 10) }, COAL_50),
	IndustrialWashingStation = processor({ recipe({ Truffle = 1 }, { CleanTruffle = 1 }, 1.5) }, COAL_20),
	IndustrialOven = processor({ recipe({ BerryDough = 1 }, { BerryBread = 1 }, 10) }, COAL_30),
	IndustrialMilker = {
		kind = "Machine",
		output = "-Z",
		produce = { where = "Animals", sources = { Cow = { item = "MilkBucket", every = 30 } }, radius = 6 },
	},
	IndustrialBerryBasket = {
		kind = "Machine",
		input = "-Z",
		output = "+Z",
		passThrough = true,
		belt = 3,
		produce = { where = "Near", sources = { BerryBush = { item = "Blueberry", every = 10 } }, radius = 6 },
	},
	IndustrialFlowerPicker = {
		kind = "Machine",
		output = "+Z",
		fuel = PETROLEUM_60,
		produce = { where = "Near", sources = { FlowerPatch = { item = "Tulip", every = 15 } }, radius = 6 },
	},
	IndustrialTruffleBarrel = {
		kind = "Machine",
		input = "-Z",
		output = "+Z",
		passThrough = true,
		belt = 3,
		produce = { where = "Animals", sources = { Pig = { item = "Truffle", every = 30 } }, radius = 6 },
	},
	IndustrialMerchantTeleseller = { kind = "Machine", input = "-Z", sells = true },
	IndustrialChest = { kind = "Machine", input = "-Z", stores = 12 },
	CopperPress = processor({ recipe({ CopperBar = 1 }, { CopperPlate = 1 }, 5) }),
	SteelPress = processor({ recipe({ SteelBar = 1 }, { SteelPlate = 1 }, 5) }),
	SteelMill = processor({ recipe({ IronBar = 1 }, { SteelBar = 1 }, 20) }, COAL_30),
	RedBronzeRefinery = processor({ recipe({ CopperBar = 2, GoldBar = 1 }, { RedBronzeBar = 2 }, 15) }, COAL_30),
	OilRefinery = processor({ recipe({ Oil = 1 }, { Petroleum = 1 }, 10) }),
	PetroleumPetrifier = processor({ recipe({ Petroleum = 1 }, { PetrifiedPetroleum = 1 }, 20) }),
	FuelBarrelFiller = processor({
		recipe({ Oil = 6 }, { OilBarrel = 1 }, 30),
		recipe({ Petroleum = 6 }, { PetroleumBarrel = 1 }, 30),
	}),
	FuelBarrelExtractor = processor({
		recipe({ OilBarrel = 1 }, { Oil = 6 }, 5),
		recipe({ PetroleumBarrel = 1 }, { Petroleum = 6 }, 5),
	}),
	FoodProcessor = processor({ recipe({ Blueberry = 2, MilkBucket = 1 }, { BerryDough = 1 }, 5) }),
	CratePacker = processor({
		recipe({ Apple = 20 }, { FruitCrate = 1 }, 2),
		recipe({ Blueberry = 20 }, { FruitCrate = 1 }, 2),
	}),
	CratePackerTier2 = processor({
		recipe({ Apple = 50 }, { LargeFruitCrate = 1 }, 2),
		recipe({ Blueberry = 50 }, { LargeFruitCrate = 1 }, 2),
	}),
	PalletPacker = processor({ recipe({ WoodPlanks = 10 }, { Pallet = 1 }, 3) }),
	SapBoiler = {
		kind = "Machine",
		tubes = true,
		recipes = { { inputs = {}, outputs = {}, time = 15, fluidIn = "Sap", fluidOut = "Syrup" } },
	},
	SyrupBottler = {
		kind = "Machine",
		output = "+Z",
		tubes = true,
		recipes = { { inputs = {}, outputs = { MapleSyrup = 1 }, time = 5, fluidIn = "Syrup" } },
	},
	SaplingAutomaticPlanter = {
		kind = "Machine",
		input = "+Z",
		fuel = PETROLEUM_60,
		plants = "Sapling",
		plantEvery = 10,
		treeCell = pastForks,
	},
	TreeFruitShaker = {
		kind = "Machine",
		output = "+Z",
		fuel = PETROLEUM_60,
		produce = { where = "Tree", sources = { AppleTree = { item = "Apple", every = 20 } } },
		treeCell = pastForks,
	},
	AutomatedTrough = {
		kind = "Machine",
		input = "-Z",
		feeds = { Apple = true, Blueberry = true },
		feedRadius = 6,
	},
	WoolVacuum = {
		kind = "Machine",
		input = "-Z",
		output = "+Z",
		passThrough = true,
		produce = { where = "Animals", sources = { Sheep = { item = "Wool", every = 60 } }, radius = 6 },
	},
}

return BLOCKS
