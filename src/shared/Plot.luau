--!strict
-- Plot: the map's six gardens, their sections, and lossless plot-relative coordinates.
-- Origins are minimum cells; all plots face -Z so a saved layout has the same orientation
-- and farmland underneath it in either row. Height does not change which plot a cell is in.
--
-- A garden is a grid of SECTIONS_X by SECTIONS_Z square sections of SECTION cells each.
-- Section column x, row z (row 0 is the front, the -Z edge) covers relative cells from
-- x * SECTION and z * SECTION. The START block at the front centre is everyone's from the
-- start; any other section is bought (PlotService) once it shares an edge with owned land,
-- for the price of its ring: its distance in sections from the start block. A cell counts as
-- on a plot only while that plot has an owner and owns the cell's section; elsewhere it is
-- treated exactly like a cell off every plot. The server writes Owner and Sections ("x,z;x,z",
-- bought sections only) on Workspace.Plots[index]; both sides read them on every call but
-- parse Sections only when it changes, because Plot.at runs very often.

local SECTION = 10
local SECTIONS_X, SECTIONS_Z = 7, 6
-- The start block's first and last section columns and rows.
local START = { x0 = 2, x1 = 4, z0 = 0, z1 = 2 }
-- Coins for a section by ring: ring 1 touches the start block.
local PRICES = { 2500, 20000, 100000 }

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
	-- Its picks' ticked mutations, as "Carrot:Golden" or "Flour:Plain".
	filterMutations: { string }?,
	powered: boolean,
}
export type SavedBlock = { itemId: string, cell: Cell, rotation: number, against: Cell?, contents: Contents? }

local WIDTH, DEPTH = SECTIONS_X * SECTION, SECTIONS_Z * SECTION
-- The front-left corners of the six gardens, in cells: three across, 10 cells apart, one row
-- on either side of the hub with the quarry between them.
local ORIGINS: { Vector3 } = {}
for _, z in { -76, 16 } do
	for _, x in { -115, -35, 45 } do
		table.insert(ORIGINS, Vector3.new(x, 0, z))
	end
end

local Plot = {}
Plot.SECTION = SECTION
Plot.SECTIONS_X = SECTIONS_X
Plot.SECTIONS_Z = SECTIONS_Z
Plot.START = START
Plot.PRICES = PRICES
Plot.WIDTH = WIDTH
Plot.DEPTH = DEPTH
-- Where the start block's first cell sits in a garden. Saves from before sections were laid
-- out from there (DataService moves them over once).
Plot.START_OFFSET = Vector3.new(START.x0 * SECTION, 0, START.z0 * SECTION)
Plot.COUNT = #ORIGINS
Plot.HEIGHT = 80
-- Studs from the character to a section's centre within which it can be bought.
Plot.BUY_REACH = 30

function Plot.origin(index: number): Vector3
	assert(ORIGINS[index], "Plot.origin: invalid plot index")
	return ORIGINS[index]
end

-- One number per section, for sets.
function Plot.key(x: number, z: number): number
	return z * SECTIONS_X + x
end

function Plot.inGrid(x: number, z: number): boolean
	return x % 1 == 0 and z % 1 == 0 and x >= 0 and x < SECTIONS_X and z >= 0 and z < SECTIONS_Z
end

function Plot.isStart(x: number, z: number): boolean
	return x >= START.x0 and x <= START.x1 and z >= START.z0 and z <= START.z1
end

-- Sections from the start block, counting a diagonal step as one (0 inside it).
function Plot.ring(x: number, z: number): number
	local dx = math.max(START.x0 - x, x - START.x1, 0)
	local dz = math.max(START.z0 - z, z - START.z1, 0)
	return math.max(dx, dz)
end

function Plot.price(x: number, z: number): number
	return PRICES[math.clamp(Plot.ring(x, z), 1, #PRICES)]
end

-- The section a plot-relative cell is in.
function Plot.sectionOf(relative: Vector3): (number, number)
	return relative.X // SECTION, relative.Z // SECTION
end

-- The bought sections in a Sections attribute ("x,z;x,z") or a save ({ "x,z" }), as a set of
-- keys. Anything that is not a whole, in-grid, non-start section is dropped.
function Plot.decode(value: unknown): { [number]: boolean }
	local set = {}
	local entries: { unknown } = {}
	if typeof(value) == "string" then
		for entry in string.gmatch(value, "[^;]+") do
			table.insert(entries, entry)
		end
	elseif typeof(value) == "table" then
		entries = value :: { unknown }
	end
	for _, entry in entries do
		if typeof(entry) == "string" then
			local x, z = string.match(entry, "^(%d+),(%d+)$")
			local sx, sz = tonumber(x), tonumber(z)
			if sx and sz and Plot.inGrid(sx, sz) and not Plot.isStart(sx, sz) then
				set[Plot.key(sx, sz)] = true
			end
		end
	end
	return set
end

-- A set of bought sections as "x,z" strings in a stable order, for saves and the attribute.
function Plot.encode(set: { [number]: boolean }): { string }
	local list = {}
	for z = 0, SECTIONS_Z - 1 do
		for x = 0, SECTIONS_X - 1 do
			if set[Plot.key(x, z)] and not Plot.isStart(x, z) then
				table.insert(list, `{x},{z}`)
			end
		end
	end
	return list
end

function Plot.model(index: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local model = if plots then plots:FindFirstChild(tostring(index)) else nil
	return if model and model:IsA("Model") then model else nil
end

type State = { model: Model, owner: number, raw: unknown, bought: { [number]: boolean } }
local states: { [number]: State } = {}

-- The plot's owner and bought sections, read fresh from its attributes every call (a change
-- must count in the same frame: DataService restores a garden straight after assigning it,
-- before any changed signal would run), with the Sections string parsed only when it changes.
local function stateOf(index: number): State?
	local state: State
	local cached = states[index]
	if cached and cached.model.Parent then
		state = cached
	else
		local model = Plot.model(index)
		if not model then
			return nil
		end
		state = { model = model, owner = 0, raw = nil, bought = {} }
		states[index] = state
	end
	local owner = state.model:GetAttribute("Owner")
	state.owner = if typeof(owner) == "number" then owner else 0
	local raw = state.model:GetAttribute("Sections")
	if raw ~= state.raw then
		state.raw = raw
		state.bought = Plot.decode(raw)
	end
	return state
end

-- Whether a plot owns section (x, z): the start block, or one it bought.
function Plot.owns(index: number, x: number, z: number): boolean
	if not Plot.inGrid(x, z) then
		return false
	end
	if Plot.isStart(x, z) then
		return true
	end
	local state = stateOf(index)
	return state ~= nil and state.bought[Plot.key(x, z)] == true
end

-- Whether section (x, z) can be bought now: in the grid, not owned yet, and sharing an edge
-- with owned land.
function Plot.canBuy(index: number, x: number, z: number): boolean
	if not Plot.inGrid(x, z) or Plot.owns(index, x, z) then
		return false
	end
	return Plot.owns(index, x - 1, z)
		or Plot.owns(index, x + 1, z)
		or Plot.owns(index, x, z - 1)
		or Plot.owns(index, x, z + 1)
end

-- A section's centre at ground level, in studs (`grid` studs per cell).
function Plot.sectionCentre(index: number, x: number, z: number, grid: number): Vector3
	local corner = Plot.origin(index) + Vector3.new(x * SECTION, 0, z * SECTION)
	return (corner + Vector3.new(SECTION / 2, 0, SECTION / 2)) * grid
end

function Plot.at(cell: Vector3): number?
	for index, origin in ORIGINS do
		local relative = cell - origin
		if relative.X >= 0 and relative.X < WIDTH and relative.Z >= 0 and relative.Z < DEPTH then
			local state = stateOf(index)
			if not state or state.owner == 0 then
				return nil
			end
			local x, z = Plot.sectionOf(relative)
			return if Plot.owns(index, x, z) then index else nil
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

-- Every cell of a footprint must be on the plot: bought sections can leave notches, so its
-- corners alone are not enough.
function Plot.contains(index: number, cell: Vector3, footprint: Vector3): boolean
	for x = 0, footprint.X - 1 do
		for z = 0, footprint.Z - 1 do
			if Plot.at(cell + Vector3.new(x, 0, z)) ~= index then
				return false
			end
		end
	end
	return true
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
