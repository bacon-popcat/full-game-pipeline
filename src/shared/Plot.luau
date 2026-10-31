--!strict
-- Plot: expansion prices, the map's six owned bounds and lossless plot-relative coordinates.
-- Origins are minimum cells; all plots face -Z so a saved layout has the same orientation
-- and farmland underneath it in either row. Height does not change which plot a cell is in.
-- Growth is only +X/+Z: saved cells never shift within the garden. Owner and Expansion
-- attributes are server-written; missing replication fails closed, including for machines.

local SIZE = 30
local EXPANSIONS = {
	{ size = 36, price = 2500 },
	{ size = 42, price = 25000 },
	{ size = 48, price = 125000 },
}
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
local ORIGINS: { Vector3 } = {}
for _, z in { -74, 24 } do
	for _, x in { -78, -24, 30 } do
		table.insert(ORIGINS, Vector3.new(x, 0, z))
	end
end

local Plot = {}
Plot.SIZE = SIZE
Plot.EXPANSIONS = EXPANSIONS
Plot.MAX_SIZE = EXPANSIONS[#EXPANSIONS].size
Plot.REACH = 12
Plot.COUNT = #ORIGINS
Plot.HEIGHT = 80

function Plot.origin(index: number): Vector3
	assert(ORIGINS[index], "Plot.origin: invalid plot index")
	return ORIGINS[index]
end

function Plot.sanitize(value: unknown): number
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, #EXPANSIONS)
end

function Plot.size(tier: number): number
	local expansion = EXPANSIONS[Plot.sanitize(tier)]
	return if expansion then expansion.size else SIZE
end

function Plot.model(index: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local model = if plots then plots:FindFirstChild(tostring(index)) else nil
	return if model and model:IsA("Model") then model else nil
end

function Plot.tier(index: number): number
	local model = Plot.model(index)
	return Plot.sanitize(if model then model:GetAttribute("Expansion") else nil)
end

function Plot.inReach(player: Player, index: number): boolean
	local model = Plot.model(index)
	local anchor = if model then model:FindFirstChild("ExpansionSign") else nil
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return model ~= nil
		and model:GetAttribute("Owner") == player.UserId
		and anchor ~= nil
		and anchor:IsA("BasePart")
		and root ~= nil
		and root:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.Health > 0
		and (root.Position - anchor.Position).Magnitude <= Plot.REACH
end

function Plot.at(cell: Vector3): number?
	for index, origin in ORIGINS do
		local model = Plot.model(index)
		local owner = if model then model:GetAttribute("Owner") else nil
		local size = Plot.size(if model then Plot.sanitize(model:GetAttribute("Expansion")) else 0)
		if
			typeof(owner) == "number"
			and owner ~= 0
			and cell.X >= origin.X
			and cell.X < origin.X + size
			and cell.Z >= origin.Z
			and cell.Z < origin.Z + size
		then
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
