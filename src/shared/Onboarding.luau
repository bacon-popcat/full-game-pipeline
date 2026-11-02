--!strict
-- Onboarding: the ordered first-session objectives and their coin rewards. The saved step
-- names the next objective; #STEPS + 1 means finished. Only the server completes objectives.
-- The first five walk through farming by hand: seeds, tilling, planting, harvesting, selling.
-- Inserting a step moves saved steps (DataService migrates them).

export type Condition =
	"SeedBought"
	| "Tilled"
	| "Planted"
	| "Harvested"
	| "StandSold"
	| "LevelTwo"
	| "BinBought"
	| "BinPlaced"
export type Step = { text: string, reward: number, condition: Condition }
export type Snapshot = { step: number, total: number, text: string, done: boolean }

local STEPS: { Step } = {
	{ text = "Open the Shop and buy some Carrot Seeds", reward = 10, condition = "SeedBought" },
	{ text = "Hold your Hoe and click the grass in your garden to till Farmland", reward = 10, condition = "Tilled" },
	{ text = "Hold your seeds and click the Farmland to plant them", reward = 10, condition = "Planted" },
	{ text = "Wait for a crop to ripen, then click it to harvest", reward = 20, condition = "Harvested" },
	{ text = "Open Sell and sell your harvest for coins", reward = 20, condition = "StandSold" },
	{ text = "Reach level 2", reward = 30, condition = "LevelTwo" },
	{ text = "Buy a Shipping Bin at the Machine Shop", reward = 20, condition = "BinBought" },
	{ text = "Place your Shipping Bin on your plot", reward = 50, condition = "BinPlaced" },
}

local Onboarding = { STEPS = STEPS }

function Onboarding.sanitize(value: unknown): number
	if typeof(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 1
	end
	return math.clamp(math.floor(value), 1, #STEPS + 1)
end

function Onboarding.snapshot(step: number): Snapshot
	local objective = STEPS[step]
	return { step = step, total = #STEPS, text = if objective then objective.text else "", done = objective == nil }
end

return Onboarding
