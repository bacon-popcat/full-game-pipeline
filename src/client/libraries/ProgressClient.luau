--!strict
-- ProgressClient: the latest ProgressSync (ProgressService): this garden's stats, unlocked
-- achievements, today's daily quests and its orders. Screens read it and hear `changed`. The
-- server syncs on load, after changes (throttled) and after every request; playtime between
-- syncs is extrapolated here from the sync's server time, so the Stats screen can count up
-- without a sync a second. Deadlines are on workspace:GetServerTimeNow()'s clock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type QuestView = {
	id: string,
	text: string,
	progress: number,
	goal: number,
	done: boolean,
	claimed: boolean,
	reward: Progress.Reward,
}
-- An order to deliver, or a slot waiting for its next one.
export type OrderView = { item: string?, count: number?, reward: Progress.Reward?, waitUntil: number? }
export type Snapshot = {
	stats: { [string]: number },
	achievements: { [string]: boolean },
	daily: { quests: { QuestView }, resetsAt: number, bonus: boolean },
	orders: { OrderView },
	ordersToBonus: number,
	syncedAt: number,
}

local ProgressClient = {}
ProgressClient.changed = Signal.new()

local state: Snapshot = {
	stats = {},
	achievements = {},
	daily = { quests = {}, resetsAt = 0, bonus = false },
	orders = {},
	ordersToBonus = Progress.ORDER_BONUS_EVERY,
	syncedAt = 0,
}
local synced = false

Remotes.ProgressSync.OnClientEvent:Connect(function(snapshot: Snapshot)
	state = snapshot
	synced = true
	ProgressClient.changed:Fire()
end)

function ProgressClient.get(): Snapshot
	return state
end

function ProgressClient.isSynced(): boolean
	return synced
end

-- A stat's value now; playtime keeps counting from the last sync.
function ProgressClient.stat(id: string): number
	local value = state.stats[id] or 0
	if id == "playtime" and synced then
		value += math.max(0, workspace:GetServerTimeNow() - state.syncedAt)
	end
	return value
end

-- How many daily quests are done and waiting to be claimed.
function ProgressClient.claimable(): number
	local count = 0
	for _, quest in state.daily.quests do
		if quest.done and not quest.claimed then
			count += 1
		end
	end
	return count
end

function ProgressClient.claimDaily(slot: number)
	Remotes.Progress:FireServer("ClaimDaily", slot)
end

function ProgressClient.deliverOrder(slot: number)
	Remotes.Progress:FireServer("DeliverOrder", slot)
end

function ProgressClient.skipOrder(slot: number)
	Remotes.Progress:FireServer("SkipOrder", slot)
end

return ProgressClient
