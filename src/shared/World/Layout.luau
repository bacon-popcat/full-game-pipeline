--!strict
-- Layout: where the world spawns its resource nodes and animal pens, in Build cells (the
-- baseplate's top is y = 0). Everything sits west of spawn (negative x), clear of the
-- Workspace.IslandsMachines showcase to the east: an ore field with the deposits, a
-- quarry of rocks, a grove of trees, a meadow of bushes and flowers, and three pens.
--
-- Deposits are spaced so a Drill (5 x 2 blocks) or Pumpjack (3 x 5) fits on each.

export type Spot = { node: string, cell: Vector3 }
export type Pen = { animal: string, centre: Vector3, count: number, radius: number }

local function at(node: string, x: number, z: number): Spot
	return { node = node, cell = Vector3.new(x, 0, z) }
end

local NODES: { Spot } = {
	-- ore field
	at("CopperDeposit", -14, -16),
	at("CopperDeposit", -22, -16),
	at("GoldDeposit", -30, -16),
	at("OilDeposit", -38, -16),

	-- quarry
	at("StoneRock", -14, -6),
	at("StoneRock", -16, -8),
	at("StoneRock", -19, -6),
	at("StoneRock", -21, -9),
	at("StoneRock", -24, -7),
	at("CoalRock", -13, -10),
	at("CoalRock", -17, -11),
	at("CoalRock", -23, -11),
	at("CoalRock", -26, -5),
	at("IronRock", -28, -8),
	at("IronRock", -30, -5),
	at("IronRock", -32, -9),
	at("IronRock", -34, -6),

	-- grove
	at("OakTree", -14, 6),
	at("OakTree", -17, 9),
	at("OakTree", -20, 6),
	at("OakTree", -23, 10),
	at("OakTree", -26, 7),
	at("MapleTree", -30, 6),
	at("MapleTree", -33, 9),
	at("MapleTree", -36, 6),
	at("AppleTree", -29, 12),
	at("AppleTree", -34, 13),
	at("AppleTree", -39, 10),

	-- meadow
	at("BerryBush", -14, 17),
	at("BerryBush", -16, 19),
	at("BerryBush", -18, 16),
	at("BerryBush", -21, 19),
	at("BerryBush", -23, 17),
	at("FlowerPatch", -27, 17),
	at("FlowerPatch", -29, 19),
	at("FlowerPatch", -31, 16),
	at("FlowerPatch", -33, 19),
	at("FlowerPatch", -35, 17),
}

local PENS: { Pen } = {
	{ animal = "Cow", centre = Vector3.new(-48, 0, -10), count = 3, radius = 4 },
	{ animal = "Sheep", centre = Vector3.new(-48, 0, 2), count = 3, radius = 4 },
	{ animal = "Pig", centre = Vector3.new(-48, 0, 14), count = 3, radius = 4 },
}

return { nodes = NODES, pens = PENS }
