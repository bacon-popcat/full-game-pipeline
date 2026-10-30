-- EconomyService: owns live balances, mirrors Coins and Level to leaderstats and publishes
-- EconomySync. DataService supplies and snapshots state; no client can change a balance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GardenEvents = require(game:GetService("ServerScriptService").Libraries.GardenEvents)

type State = { coins: number, xp: number, level: number }
local states: { [Player]: State } = {}
local EconomyService = {}

local function sync(player: Player, state: State)
	player:SetAttribute("Coins", state.coins)
	player:SetAttribute("Xp", state.xp)
	player:SetAttribute("Level", state.level)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	for name, value in { Coins = state.coins, Level = state.level } do
		local stat = stats:FindFirstChild(name)
		if not stat then
			stat = Instance.new("IntValue")
			stat.Name = name
			stat.Parent = stats
		end
		assert(stat:IsA("IntValue"), "EconomyService: leaderstat must be an IntValue")
		stat.Value = value
	end
	Remotes.EconomySync:FireClient(player, table.clone(state))
end

local function valid(amount: number): boolean
	return amount >= 0 and amount < math.huge and amount % 1 == 0
end

function EconomyService.load(player: Player, coins: number, xp: number)
	assert(valid(coins) and valid(xp), "EconomyService: invalid saved balance")
	local level = Economy.progress(xp)
	states[player] = { coins = coins, xp = xp, level = level }
	sync(player, states[player])
end

function EconomyService.get(player: Player): State?
	local state = states[player]
	return if state then table.clone(state) else nil
end

function EconomyService.add(player: Player, amount: number): boolean
	local state = states[player]
	if not state or not valid(amount) then
		return false
	end
	state.coins += amount
	sync(player, state)
	return true
end

function EconomyService.trySpend(player: Player, amount: number): boolean
	local state = states[player]
	if not state or not valid(amount) or state.coins < amount then
		return false
	end
	state.coins -= amount
	sync(player, state)
	return true
end

function EconomyService.addXp(player: Player, amount: number): boolean
	local state = states[player]
	if not state or not valid(amount) then
		return false
	end
	local before = state.level
	state.xp += amount
	state.level = Economy.progress(state.xp)
	sync(player, state)
	if state.level > before then
		GardenEvents.LevelUp:Fire(player, state.level)
	end
	return true
end

function EconomyService.release(player: Player)
	states[player] = nil
end

return EconomyService
