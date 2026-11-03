--!strict
-- ResearchClient: the latest ResearchSync, what this player has researched and what is running
-- (ResearchService). Screens read it and hear `changed`. The server sends a fresh one on load
-- and after every start, cancel and finish, so nothing here predicts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Research = require(ReplicatedStorage.Shared.Research)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ResearchClient = {}
ResearchClient.changed = Signal.new()

local state: Research.Snapshot = { done = {}, active = nil, bonuses = {} }
local done: { [string]: boolean } = {}
-- Whether a sync has arrived yet, so screens can say they're loading rather than empty.
local synced = false

Remotes.ResearchSync.OnClientEvent:Connect(function(snapshot: Research.Snapshot)
	state = snapshot
	done = {}
	for _, id in snapshot.done do
		done[id] = true
	end
	synced = true
	ResearchClient.changed:Fire()
end)

function ResearchClient.get(): Research.Snapshot
	return state
end

-- Finished projects by id.
function ResearchClient.done(): { [string]: boolean }
	return done
end

function ResearchClient.isSynced(): boolean
	return synced
end

return ResearchClient
