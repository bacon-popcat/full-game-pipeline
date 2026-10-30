--!strict
-- Onboarding: the ordered first-session objectives and their coin rewards. The saved step
-- names the next objective; #STEPS + 1 means finished. Only the server completes objectives.

export type Condition = "SeedBought" | "Planted" | "Harvested" | "StandSold" | "LevelTwo" | "BinBought" | "BinPlaced"
export type Step = { text: string, reward: number, condition: Condition }
export type Snapshot = { step: number, total: number, text: string, done: boolean }

local STEPS: { Step } = {
	{ text = "Buy seeds at the Seed Shop", reward = 10, condition = "SeedBought" },
	{ text = "Plant a seed on your farm", reward = 10, condition = "Planted" },
	{ text = "Harvest a ripe crop", reward = 20, condition = "Harvested" },
	{ text = "Sell your harvest at the Sell Stand", reward = 20, condition = "StandSold" },
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
