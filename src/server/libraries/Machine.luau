--!strict
-- Machine: the state of one placed machine and the rules that run it, with no knowledge
-- of where it stands. FactoryService feeds it items and asks the world for it through an
-- Env; this module decides what it takes, when it works and what comes out.
--
-- A machine holds items waiting to be used (`inputs`: ingredients, coal, seeds),
-- a queue of finished items waiting to leave (`outputs`), and at most one job.
-- Fuel burns only while a job runs, and a job only starts when its outputs will fit, so a
-- backed-up machine stops cleanly instead of losing items. Capacities are per item and
-- small, so a conveyor feeding a machine backs up rather than vanishing into it.
--
-- Mutated crops are never mixed with plain ones or with each other: each variant has its own
-- room, a batch takes all its inputs in one mutation (plain first, then rising rarity), and
-- its products come out in that mutation too (Golden Carrots make a Golden Carrot Crate). A
-- recipe with an input that has no variant (bars, parts) only runs plain. Rare variants wait
-- inside until a whole batch of them is in, without holding up the plain ones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Mutations = require(ReplicatedStorage.Shared.World.Mutations)

-- Finished items a machine holds before it stops working.
local OUTPUT_CAP = 8
-- Fuel items a machine holds on top of what is burning.
local FUEL_CAP = 16
local PLANT_CAP = 10
local SELL_CAP = 10
-- Seconds between a seller's sales.
local SELL_EVERY = 1
local NO_RECIPES: { Factory.Recipe } = {}
-- The variants a batch is looked for in, in order: "" is plain, then the mutations from the
-- least to the most valuable.
local VARIANTS: { string } = table.clone(Mutations.ORDER)
table.insert(VARIANTS, 1, "")

export type Job = {
	recipe: Factory.Recipe?,
	source: Factory.Source?,
	time: number,
	elapsed: number,
}

export type State = {
	def: Factory.Def,
	inputs: { [string]: number },
	outputs: { string },
	-- Seconds of running left on the fuel burning now.
	fuel: number,
	job: Job?,
	timer: number,
	sold: number,
	-- Why it is not working, for the player; "Working" when it is.
	status: string,
}

export type Env = {
	-- Producers: what the world offers this machine right now, or nil and why not.
	source: (() -> (Factory.Source?, string?))?,
	-- Pickers: reap a ripe crop near it that `source` comes from; returns whether it did.
	reap: ((source: Factory.Source) -> boolean)?,
	-- Planters: whether an item could be planted in a free cell of its patch, and planting it there.
	canPlant: ((itemId: string) -> boolean)?,
	plant: ((itemId: string) -> boolean)?,
	-- Sellers: pays the owner for one sold item.
	sell: ((itemId: string) -> ())?,
}

local Machine = {}

function Machine.new(def: Factory.Def): State
	return {
		def = def,
		inputs = {},
		outputs = {},
		fuel = 0,
		job = nil,
		timer = 0,
		sold = 0,
		status = "Idle",
	}
end

local function total(counts: { [string]: number }): number
	local sum = 0
	for _, count in counts do
		sum += count
	end
	return sum
end

-- How many of `itemId` the machine could hold in its inputs at most.
local function capacity(def: Factory.Def, itemId: string): number
	if def.fuel and def.fuel[itemId] then
		return FUEL_CAP
	end
	if def.plants and table.find(def.plants, itemId) then
		return PLANT_CAP
	end
	local most = 0
	for _, recipe in def.recipes or NO_RECIPES do
		local need = recipe.inputs[Inventory.getItem(itemId).base or itemId]
		if need then
			most = math.max(most, need * 2, 4)
		end
	end
	return most
end

-- A chest's slots in use: each item fills slots of its stack size.
function Machine.slotsUsed(state: State): number
	local used = 0
	for itemId, count in state.inputs do
		used += math.ceil(count / Inventory.getItem(itemId).stack)
	end
	return used
end

-- How many more of `itemId` the machine would take right now.
function Machine.room(state: State, itemId: string): number
	local def = state.def
	if def.stores then
		-- What fits in the free slots, plus what tops up this item's last part-filled slot.
		local stack = Inventory.getItem(itemId).stack
		local held = state.inputs[itemId] or 0
		local topUp = if held % stack > 0 then stack - held % stack else 0
		return (def.stores - Machine.slotsUsed(state)) * stack + topUp
	end
	if def.sells then
		return if Inventory.getItem(itemId).value then SELL_CAP - total(state.inputs) else 0
	end
	-- Each variant has its own room, so a few rare ones can't crowd out the plain ones.
	return math.max(0, capacity(def, itemId) - (state.inputs[itemId] or 0))
end

-- Puts up to `count` of `itemId` in. Returns how many went in.
function Machine.insert(state: State, itemId: string, count: number): number
	local taken = math.min(count, Machine.room(state, itemId))
	if taken <= 0 then
		return 0
	end
	state.inputs[itemId] = (state.inputs[itemId] or 0) + taken
	return taken
end

-- The next finished item waiting to leave, without removing it.
function Machine.peekOutput(state: State): string?
	return state.outputs[1]
end

function Machine.popOutput(state: State): string?
	return table.remove(state.outputs, 1)
end

local function addCounts(into: { [string]: number }, itemId: string, count: number)
	into[itemId] = (into[itemId] or 0) + count
end

-- Every finished item, removed from the machine.
function Machine.takeOutputs(state: State): { [string]: number }
	local counts = {}
	for _, itemId in state.outputs do
		addCounts(counts, itemId, 1)
	end
	table.clear(state.outputs)
	return counts
end

-- Everything loaded and not used yet (ingredients, unlit coal, seeds, goods
-- waiting to sell), removed from the machine. The job in progress and the fuel burning
-- now stay.
function Machine.takeInputs(state: State): { [string]: number }
	local counts = table.clone(state.inputs)
	table.clear(state.inputs)
	return counts
end

-- Takes up to `count` of one loaded item out (a chest's take). Returns how many.
function Machine.takeInput(state: State, itemId: string, count: number): number
	local taken = math.min(count, state.inputs[itemId] or 0)
	if taken > 0 then
		local left = (state.inputs[itemId] or 0) - taken
		if left > 0 then
			state.inputs[itemId] = left
		else
			state.inputs[itemId] = nil
		end
	end
	return taken
end

-- Puts inputs taken out by `takeInputs` back, whatever the room, for what a player's full
-- inventory couldn't hold.
function Machine.putBack(state: State, itemId: string, count: number)
	if count > 0 then
		addCounts(state.inputs, itemId, count)
	end
end

-- Saving or picking up refunds an unfinished recipe; no partial product is minted.
function Machine.inputCounts(state: State): { [string]: number }
	local counts = table.clone(state.inputs)
	if state.job and state.job.recipe then
		for itemId, count in state.job.recipe.inputs do
			addCounts(counts, itemId, count)
		end
	end
	return counts
end

-- Everything a player gets back when they pick the machine up, removed from it.
function Machine.drain(state: State): { [string]: number }
	local counts = Machine.inputCounts(state)
	state.job = nil
	for itemId, count in Machine.takeOutputs(state) do
		addCounts(counts, itemId, count)
	end
	table.clear(state.inputs)
	return counts
end

local function take(state: State, itemId: string, count: number)
	local left = (state.inputs[itemId] or 0) - count
	if left > 0 then
		state.inputs[itemId] = left
	else
		state.inputs[itemId] = nil
	end
end

-- Keeps fuel burning for `dt` more seconds, lighting a new fuel item when the last runs
-- out. Returns whether the machine has power.
local function burn(state: State, dt: number): boolean
	local fuels = state.def.fuel
	if not fuels then
		return true
	end
	if state.fuel <= 0 then
		for itemId, seconds in fuels do
			if (state.inputs[itemId] or 0) > 0 then
				take(state, itemId, 1)
				state.fuel += seconds
				break
			end
		end
	end
	if state.fuel <= 0 then
		state.status = "Needs fuel"
		return false
	end
	state.fuel = math.max(0, state.fuel - dt)
	return true
end

local function outputCount(recipe: Factory.Recipe): number
	return total(recipe.outputs)
end

-- Recipes are static defs, so each one's variants are worked out once (false: none).
local variantCache: { [Factory.Recipe]: { [string]: Factory.Recipe | false } } = {}

local function buildVariant(recipe: Factory.Recipe, mutation: string): Factory.Recipe?
	local inputs: { [string]: number } = {}
	for itemId, need in recipe.inputs do
		local id = itemId .. "+" .. mutation
		if not Inventory.find(id) then
			return nil
		end
		inputs[id] = need
	end
	local outputs: { [string]: number } = {}
	for itemId, count in recipe.outputs do
		local id = itemId .. "+" .. mutation
		outputs[if Inventory.find(id) then id else itemId] = count
	end
	return { inputs = inputs, outputs = outputs, time = recipe.time }
end

-- `recipe` made in one variant ("" for plain): every input and product in that mutation, or
-- nil when an input has no such variant.
local function inVariant(recipe: Factory.Recipe, mutation: string): Factory.Recipe?
	if mutation == "" then
		return recipe
	end
	local cached = variantCache[recipe]
	if not cached then
		cached = {}
		variantCache[recipe] = cached
	end
	local found = cached[mutation]
	if found == nil then
		found = buildVariant(recipe, mutation) or false
		cached[mutation] = found
	end
	return if found then found else nil
end

-- Whether the machine holds everything a batch consumes, exactly those items.
local function hasInputs(state: State, recipe: Factory.Recipe): boolean
	for itemId, need in recipe.inputs do
		if (state.inputs[itemId] or 0) < need then
			return false
		end
	end
	return true
end

-- Whether a batch's products would fit beside what is already waiting to leave.
local function hasRoom(state: State, recipe: Factory.Recipe): boolean
	return #state.outputs + outputCount(recipe) <= OUTPUT_CAP
end

local function stepRecipes(state: State, dt: number)
	local job = state.job
	local blocked = false
	if not job then
		for _, recipe in state.def.recipes or NO_RECIPES do
			for _, mutation in VARIANTS do
				local batch = inVariant(recipe, mutation)
				local ready = batch ~= nil and hasInputs(state, batch)
				blocked = blocked or (batch ~= nil and ready and not hasRoom(state, batch))
				if batch and ready and hasRoom(state, batch) then
					-- The job keeps the exact variants it took, so saving or pickup refunds them.
					for itemId, need in batch.inputs do
						take(state, itemId, need)
					end
					job = { recipe = batch, time = batch.time, elapsed = 0 }
					state.job = job
					break
				end
			end
			if job then
				break
			end
		end
	end
	if not job then
		-- "Output full" whenever a batch is ready but its products have nowhere to go yet.
		state.status = if blocked or #state.outputs >= OUTPUT_CAP then "Output full" else "Idle"
		return
	end
	if not burn(state, dt) then
		return
	end
	state.status = "Working"
	job.elapsed += dt
	local recipe = job.recipe
	if job.elapsed >= job.time and recipe then
		for itemId, count in recipe.outputs do
			for _ = 1, count do
				table.insert(state.outputs, itemId)
			end
		end
		state.job = nil
	end
end

local function stepProducer(state: State, dt: number, env: Env)
	local produce = state.def.produce
	local findSource = env.source
	if not produce or not findSource then
		return
	end
	local job = state.job
	if not job then
		if #state.outputs >= OUTPUT_CAP then
			state.status = "Output full"
			return
		end
		local source, why = findSource()
		if not source then
			state.status = why or "Idle"
			return
		end
		state.job = { source = source, time = source.every, elapsed = 0 }
	end
	job = state.job
	if not job or not burn(state, dt) then
		return
	end
	state.status = "Working"
	job.elapsed += dt
	if job.elapsed < job.time then
		return
	end
	state.job = nil
	-- A player may have harvested the crop while this job ran.
	local source, why = findSource()
	if not source then
		state.status = why or "Idle"
		return
	end
	local reap = env.reap
	if #state.outputs + (source.count or 1) > OUTPUT_CAP then
		state.status = "Output full"
		return
	end
	if source.reaps and not (reap and reap(source)) then
		state.status = "Idle"
		return
	end
	local drops: { [string]: number } = { [source.item] = source.count or 1 }
	for itemId, count in drops do
		for _ = 1, count do
			table.insert(state.outputs, itemId)
		end
	end
end

local function stepPlanter(state: State, dt: number, env: Env)
	local plants = state.def.plants
	local canPlant, plant = env.canPlant, env.plant
	if not plants or not canPlant or not plant then
		return
	end
	-- The first loaded item that could go in the planting cell now.
	local held, chosen = false, nil
	for _, itemId in plants do
		if (state.inputs[itemId] or 0) > 0 then
			held = true
			if canPlant(itemId) then
				chosen = itemId
				break
			end
		end
	end
	if not chosen then
		state.status = if held then "No empty soil in its patch" else "Needs seeds"
		state.job = nil
		return
	end
	local job = state.job
	if not job then
		state.job = { time = state.def.plantEvery or 10, elapsed = 0 }
	end
	job = state.job
	if not job or not burn(state, dt) then
		return
	end
	state.status = "Working"
	job.elapsed += dt
	if job.elapsed >= job.time then
		state.job = nil
		if plant(chosen) then
			take(state, chosen, 1)
		end
	end
end

local function stepSeller(state: State, dt: number, env: Env)
	if total(state.inputs) == 0 then
		state.status = "Idle"
		state.timer = 0
		return
	end
	state.status = "Selling"
	state.timer += dt
	while state.timer >= SELL_EVERY do
		state.timer -= SELL_EVERY
		local itemId = next(state.inputs)
		if not itemId then
			break
		end
		take(state, itemId, 1)
		state.sold += 1
		if env.sell then
			env.sell(itemId)
		end
	end
end

function Machine.step(state: State, dt: number, env: Env)
	local def = state.def
	if def.sells then
		stepSeller(state, dt, env)
	elseif def.sprinkles then
		state.status = "Watering"
	elseif def.stores then
		local used = Machine.slotsUsed(state)
		state.status = if used == 0 then "Empty" elseif used >= def.stores then "Full" else "Storing"
	elseif def.plants then
		stepPlanter(state, dt, env)
	elseif def.produce then
		stepProducer(state, dt, env)
	elseif def.recipes then
		stepRecipes(state, dt)
	end
end

-- How far through its job the machine is, 0 to 1.
function Machine.progress(state: State): number
	local job = state.job
	return if job and job.time > 0 then math.clamp(job.elapsed / job.time, 0, 1) else 0
end

return Machine
