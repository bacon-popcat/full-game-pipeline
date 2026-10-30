-- OnboardingService: observes authoritative garden actions without gating play. The saved
-- next step prevents duplicate rewards; earlier actions in this session are remembered.
-- Restored crops, discoveries, level and Shipping Bin ownership also satisfy their steps.
-- A seed purchase or stand sale has no saved evidence, so it must be observed live.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Onboarding = require(ReplicatedStorage.Shared.Onboarding)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = require(ReplicatedStorage.Shared.World)
local GardenEvents = require(game:GetService("ServerScriptService").Libraries.GardenEvents)
local BuildService = require(script.Parent.BuildService)
local EconomyService = require(script.Parent.EconomyService)
local GardenService = require(script.Parent.GardenService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)
local WorldService = require(script.Parent.WorldService)

type State = { step: number, met: { [string]: boolean } }
local states: { [Player]: State } = {}
local started = false
local OnboardingService = {}

local function sync(player: Player, state: State): ()
	-- The attribute recovers a load event sent before the authored HUD binds.
	player:SetAttribute("OnboardingStep", state.step)
	Remotes.Objective:FireClient(player, Onboarding.snapshot(state.step))
end

local function advance(player: Player, state: State): ()
	local economy = EconomyService.get(player)
	if economy and economy.level >= 2 then
		state.met.LevelTwo = true
	end
	while state.step <= #Onboarding.STEPS do
		local objective = Onboarding.STEPS[state.step]
		if not state.met[objective.condition] then
			break
		end
		-- Advance before publishing any reward or objective; repeated signals cannot repay it.
		state.step += 1
		EconomyService.add(player, objective.reward)
		Remotes.Notify:FireClient(player, `Done! +{objective.reward} coins`)
		sync(player, state)
		if state.step > #Onboarding.STEPS then
			Remotes.Notify:FireClient(player, "Your garden is yours to grow. Happy gardening!")
		end
	end
end

local function observe(player: Player, condition: Onboarding.Condition): ()
	local state = states[player]
	if not state or player:GetAttribute("DataReady") ~= true or state.step > #Onboarding.STEPS then
		return
	end
	state.met[condition] = true
	advance(player, state)
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
	GardenEvents.Planted:Connect(function(player: Player)
		observe(player, "Planted")
	end)
	GardenEvents.Harvested:Connect(function(player: Player)
		observe(player, "Harvested")
	end)
	GardenEvents.Sold:Connect(function(player: Player, coins: number, at: Vector3?)
		if coins > 0 and at == nil then
			observe(player, "StandSold")
		end
	end)
	GardenEvents.LevelUp:Connect(function(player: Player, level: number)
		if level >= 2 then
			observe(player, "LevelTwo")
		end
	end)
	GardenEvents.Placed:Connect(function(player: Player, itemId: string)
		if itemId == "ShippingBin" then
			observe(player, "BinPlaced")
		end
	end)
end

function OnboardingService.load(player: Player, step: number): ()
	OnboardingService.init()
	local state: State = { step = Onboarding.sanitize(step), met = {} }
	states[player] = state
	local index = PlotService.get(player)
	if index then
		state.met.Planted = #WorldService.snapshot(index) > 0
		for _, block in BuildService.snapshot(player, index) do
			if block.itemId == "ShippingBin" then
				state.met.BinPlaced = true
				state.met.BinBought = true
			end
		end
	end
	local inventory = InventoryService.snapshot(player)
	if inventory then
		for _, stack in inventory do
			if stack and stack.itemId == "ShippingBin" then
				state.met.BinBought = true
			end
		end
	end
	local garden = GardenService.snapshot(player)
	if garden then
		for _, discovered in garden.discovered do
			if discovered then
				state.met.Harvested = true
				state.met.Planted = true
				break
			end
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
