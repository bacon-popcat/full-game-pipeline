--!strict
-- ProgressClient: the latest ProgressSync (ProgressService): this garden's stats, unlocked
-- achievements and active quests. Screens read it and hear `changed`. The server syncs on load,
-- after changes (throttled) and after every claim; playtime between syncs is extrapolated here
-- from the sync's server time, so the Stats screen can count up without a sync a second.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

export type QuestView = { id: string, progress: number, goal: number, done: boolean }
export type Snapshot = {
	stats: { [string]: number },
	achievements: { [string]: boolean },
	quests: { QuestView },
	syncedAt: number,
}

local ProgressClient = {}
ProgressClient.changed = Signal.new()

local state: Snapshot = { stats = {}, achievements = {}, quests = {}, syncedAt = 0 }
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

-- How many quests are done and waiting to be claimed, for the Menu's badge.
function ProgressClient.claimable(): number
	local count = 0
	for _, quest in state.quests do
		if quest.done then
			count += 1
		end
	end
	return count
end

function ProgressClient.claimQuest(slot: number)
	Remotes.Progress:FireServer("ClaimQuest", slot)
end

return ProgressClient
