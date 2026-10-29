--!strict
-- Layout: shared quarry nodes in the hub, in Build cells. Plot farms belong to PlotService.
export type Spot = { node: string, cell: Vector3 }
local NODES: { Spot } = {}
for index, node in { "StoneRock", "CoalRock", "IronRock", "CopperRock" } do
	for row = 0, 2 do
		table.insert(NODES, { node = node, cell = Vector3.new(24 + index * 4, 0, -8 + row * 5) })
	end
end
return { nodes = NODES }
