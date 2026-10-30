--!strict
-- Plot: the map's six horizontal cell bounds and lossless plot-relative coordinates.
-- Origins are minimum cells; all plots face -Z so a saved layout has the same orientation
-- and farmland underneath it in either row. Height does not change which plot a cell is in.

local SIZE = 24
export type Cell = { number }
export type SavedCrop = {
	cropId: string,
	cell: Cell,
	plantedAt: number,
	harvestCount: number,
	mutation: string?,
	mutationRolled: boolean?,
	growthBonus: number?,
}
export type Counts = { [string]: number }
export type Contents = {
	inputs: Counts,
	outputs: Counts,
	lanes: { Counts },
	fuel: number,
	sold: number,
	-- A filter conveyor's items sent left, and (since filters could send right) right.
	filter: { string },
	filterRight: { string }?,
	-- Its ticked mutations, as "Left:Golden" or "Right:Plain".
	filterMutations: { string }?,
	powered: boolean,
}
export type SavedBlock = { itemId: string, cell: Cell, rotation: number, against: Cell?, contents: Contents? }
local ORIGINS: { Vector3 } = {}
for _, z in { -40, 17 } do
	for _, x in { -30, 0, 30 } do
		table.insert(ORIGINS, Vector3.new(x - SIZE / 2, 0, z))
	end
end

local Plot = {}
Plot.SIZE = SIZE
Plot.COUNT = #ORIGINS
Plot.HEIGHT = 80

function Plot.origin(index: number): Vector3
	assert(ORIGINS[index], "Plot.origin: invalid plot index")
	return ORIGINS[index]
end

function Plot.at(cell: Vector3): number?
	for index, origin in ORIGINS do
		if cell.X >= origin.X and cell.X < origin.X + SIZE and cell.Z >= origin.Z and cell.Z < origin.Z + SIZE then
			return index
		end
	end
	return nil
end

function Plot.toRelative(index: number, cell: Vector3): Vector3
	return cell - Plot.origin(index)
end

function Plot.toWorld(index: number, cell: Vector3): Vector3
	return Plot.origin(index) + cell
end

function Plot.contains(index: number, cell: Vector3, footprint: Vector3): boolean
	return Plot.at(cell) == index and Plot.at(cell + footprint - Vector3.one) == index
end

function Plot.same(a: Vector3, b: Vector3): boolean
	local index = Plot.at(a)
	return index ~= nil and Plot.at(b) == index
end

-- DataStores cannot store Vector3 values.
function Plot.pack(cell: Vector3): Cell
	return { cell.X, cell.Y, cell.Z }
end

function Plot.unpack(cell: Cell): Vector3?
	if typeof(cell) ~= "table" or #cell ~= 3 then
		return nil
	end
	for _, value in cell do
		if typeof(value) ~= "number" or value % 1 ~= 0 or math.abs(value) > 10000 then
			return nil
		end
	end
	return Vector3.new(cell[1], cell[2], cell[3])
end

return Plot
