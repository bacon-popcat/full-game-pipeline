-- OnboardingService: observes authoritative garden actions without gating play. The saved
-- next step prevents duplicate rewards; earlier actions in this session are remembered.
-- The first eight steps are named conditions: restored tilled ground, crops, discoveries, level
-- and Shipping Bin ownership satisfy theirs, but a seed purchase or stand sale has no saved
-- evidence, so it must be observed live.
-- Later steps are goals (Shared/Onboarding) checked against what the garden has: items crafted,
-- made by a machine, placed or carried (the Index, the inventory and the plot's blocks stand in
-- on load), the crafting tier, finished research, Shipping Bin sales (each bin's saved count)
-- and orders filled (the saved stat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Research = require(ReplicatedStorage.Shared.Research)
local World = require(ReplicatedStorage.Shared.World)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local BuildService = require(script.Parent.BuildService)
local CraftingService = require(script.Parent.CraftingService)
local EconomyService = require(script.Parent.EconomyService)
local GardenService = require(script.Parent.GardenService)
local GroundService = require(script.Parent.GroundService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)
local ProgressService = require(script.Parent.ProgressService)
local WorldService = require(script.Parent.WorldService)

-- Bin sales between progress updates while the count goal is the current one.
local SALES_PER_SYNC = 5

type State = {
	step: number,
	met: { [string]: boolean },
	-- Items crafted, made by a machine, placed or carried, and blocks standing on the plot.
	had: { [string]: boolean },
	placed: { [string]: boolean },
	research: boolean,
	binSales: number,
	orders: boolean,
}
local states: { [Player]: State } = {}
local started = false
local OnboardingService = {}

local function tierOf(player: Player): number
	return CraftingService.snapshot(player) or 1
end

-- The current goal's progress in words, "" when it has none to show.
local function detail(player: Player, state: State): string
	local objective = Onboarding.STEPS[state.step]
	local goal = if objective then objective.goal else nil
	if not goal then
		return ""
	end
	if goal.kind == "BinSales" and goal.count then
		return `{math.min(state.binSales, goal.count)} / {goal.count} sold`
	elseif goal.kind == "Tier" and goal.tier then
		local economy = EconomyService.get(player)
		local need = Crafting.TIERS[goal.tier].level
		if economy and economy.level < need then
			return `Level {economy.level} / {need}`
		end
	end
	return ""
end

local function sync(player: Player, state: State): ()
	-- The attribute recovers a load event sent before the authored HUD binds.
	player:SetAttribute("OnboardingStep", state.step)
	Remotes.Objective:FireClient(player, Onboarding.snapshot(state.step, detail(player, state)))
end

local function satisfied(player: Player, state: State, index: number): boolean
	local objective = Onboarding.STEPS[index]
	if objective.condition then
		return state.met[objective.condition] == true
	end
	local goal = objective.goal
	if not goal then
		return false
	end
	if goal.kind == "Tier" then
		return tierOf(player) >= (goal.tier or math.huge)
	elseif goal.kind == "Research" then
		return state.research
	elseif goal.kind == "BinSales" then
		return state.binSales >= (goal.count or math.huge)
	elseif goal.kind == "Orders" then
		return state.orders
	end
	local seen = if goal.kind == "Placed" then state.placed else state.had
	for _, itemId in goal.items or {} do
		if seen[itemId] then
			return true
		end
	end
	return false
end

local function advance(player: Player, state: State): ()
	local economy = EconomyService.get(player)
	if economy and economy.level >= 2 then
		state.met.LevelTwo = true
	end
	while state.step <= #Onboarding.STEPS do
		local objective = Onboarding.STEPS[state.step]
		if not satisfied(player, state, state.step) then
			break
		end
		-- Advance before publishing any reward or objective; repeated signals cannot repay it.
		state.step += 1
		EconomyService.add(player, objective.reward)
		Remotes.Notify:FireClient(player, `Done! +{objective.reward} coins`, "Reward")
		sync(player, state)
		if state.step > #Onboarding.STEPS then
			Remotes.Notify:FireClient(player, "Your garden is yours to grow. Happy gardening!", "Success")
		end
	end
end

-- The player's live state while there are goals left, for a signal to record evidence in.
local function live(player: Player): State?
	local state = states[player]
	if not state or player:GetAttribute("DataReady") ~= true or state.step > #Onboarding.STEPS then
		return nil
	end
	return state
end

local function observe(player: Player, condition: Onboarding.Condition): ()
	local state = live(player)
	if state then
		state.met[condition] = true
		advance(player, state)
	end
end

local function observeHad(player: Player, itemId: string): ()
	local state = live(player)
	if state and not state.had[itemId] then
		state.had[itemId] = true
		advance(player, state)
	end
end

-- Whether the current goal is of `kind`, so its progress line is worth sending again.
local function current(state: State, kind: string): boolean
	local objective = Onboarding.STEPS[state.step]
	return objective ~= nil and objective.goal ~= nil and objective.goal.kind == kind
end

function OnboardingService.init(): ()
	if started then
		return
	end
	started = true
	GardenEvents.Bought:Connect(function(player: Player, itemId: string)
		if World.PLANTS[itemId] then
			observe(player, "SeedBought")
		elseif itemId == "ShippingBin" then
			observe(player, "BinBought")
		end
	end)
	GardenEvents.Crafted:Connect(function(player: Player, recipeId: string)
		local recipe = Crafting.get(recipeId)
		if not recipe then
			return
		end
		if recipe.output == "ShippingBin" then
			observe(player, "BinBought")
		end
		if recipe.upgrade then
			-- The tier is read when a goal is checked; an upgrade only needs the check.
			local state = live(player)
			if state then
				advance(player, state)
			end
		else
			observeHad(player, recipe.output)
		end
	end)
	GardenEvents.Processed:Connect(function(player: Player, itemId: string)
		-- A mutated product ("Flour+Golden") is still its product.
		observeHad(player, string.split(itemId, "+")[1])
	end)
	GardenEvents.Tilled:Connect(function(player: Player)
		observe(player, "Tilled")
	end)
	GardenEvents.Planted:Connect(function(player: Player)
		observe(player, "Planted")
	end)
	GardenEvents.Harvested:Connect(function(player: Player)
		observe(player, "Harvested")
	end)
	GardenEvents.Sold:Connect(function(player: Player, coins: number, at: Vector3?)
		if coins <= 0 then
			return
		end
		if at == nil then
			observe(player, "StandSold")
			return
		end
		-- A Shipping Bin pays once per item, so each of its sales is one item.
		local state = live(player)
		if state then
			state.binSales += 1
			local step = state.step
			advance(player, state)
			if state.step == step and current(state, "BinSales") and state.binSales % SALES_PER_SYNC == 0 then
				sync(player, state)
			end
		end
	end)
	GardenEvents.LevelUp:Connect(function(player: Player, level: number)
		if level >= 2 then
			observe(player, "LevelTwo")
		end
		local state = live(player)
		if state and current(state, "Tier") then
			sync(player, state)
		end
	end)
	GardenEvents.Placed:Connect(function(player: Player, itemId: string)
		if itemId == "ShippingBin" then
			observe(player, "BinPlaced")
		end
		local state = live(player)
		if state then
			state.placed[itemId] = true
			state.had[itemId] = true
			advance(player, state)
		end
	end)
	GardenEvents.ResearchDone:Connect(function(player: Player)
		local state = live(player)
		if state then
			state.research = true
			advance(player, state)
		end
	end)
	GardenEvents.OrderFilled:Connect(function(player: Player)
		local state = live(player)
		if state then
			state.orders = true
			advance(player, state)
		end
	end)
end

function OnboardingService.load(player: Player, step: number): ()
	OnboardingService.init()
	local state: State = {
		step = Onboarding.sanitize(step),
		met = {},
		had = {},
		placed = {},
		research = false,
		binSales = 0,
		orders = false,
	}
	states[player] = state
	local index = PlotService.get(player)
	if index then
		state.met.Planted = #WorldService.snapshot(index) > 0
		state.met.Tilled = state.met.Planted or #GroundService.snapshot(index).tilled > 0
		for _, block in BuildService.snapshot(player, index) do
			state.placed[block.itemId] = true
			state.had[block.itemId] = true
			if block.itemId == "ShippingBin" then
				state.met.BinPlaced = true
				state.met.BinBought = true
				local sold = if block.contents then block.contents.sold else nil
				if typeof(sold) == "number" then
					state.binSales += sold
				end
			end
		end
	end
	local inventory = InventoryService.snapshot(player)
	if inventory then
		for _, stack in inventory do
			if stack then
				state.had[stack.itemId] = true
				if stack.itemId == "ShippingBin" then
					state.met.BinBought = true
				end
			end
		end
	end
	local garden = GardenService.snapshot(player)
	if garden then
		for _, discovered in garden.discovered do
			if discovered then
				state.met.Harvested = true
				state.met.Planted = true
				state.met.Tilled = true
				break
			end
		end
		for itemId in garden.indexed do
			state.had[itemId] = true
		end
	end
	local progress = ProgressService.snapshot(player)
	state.orders = progress ~= nil and progress.stats.ordersFilled > 0
	for _, project in Research.PROJECTS do
		if Bonuses.has(player, project.id) then
			state.research = true
			break
		end
	end
	sync(player, state)
	advance(player, state)
end

function OnboardingService.snapshot(player: Player): number?
	local state = states[player]
	return if state then state.step else nil
end

function OnboardingService.release(player: Player): ()
	states[player] = nil
	player:SetAttribute("OnboardingStep", nil)
end

return OnboardingService
