--!strict
-- ResearchClient: the latest ResearchSync: what this player has researched, the ranks of ranked
-- projects, and the line (running, queued, finished and waiting) (ResearchService). Screens read
-- it and hear `changed`. The server sends a fresh one on load, after every start, cancel and
-- complete, and when the line moves or a timer runs out, so nothing here predicts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Research = require(ReplicatedStorage.Shared.Research)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Packages.Signal)

local ResearchClient = {}
ResearchClient.changed = Signal.new()

local state: Research.Snapshot =
	{ done = {}, ranks = {}, active = nil, queue = {}, ready = {}, room = Research.ROOM, bonuses = {} }
local done: { [string]: boolean } = {}
local lined: { [string]: number } = {}
-- Whether a sync has arrived yet, so screens can say they're loading rather than empty.
local synced = false

Remotes.ResearchSync.OnClientEvent:Connect(function(snapshot: Research.Snapshot)
	state = snapshot
	state.ranks = snapshot.ranks or {}
	state.queue = snapshot.queue or {}
	state.ready = snapshot.ready or {}
	state.room = snapshot.room or Research.ROOM
	done = {}
	for _, id in snapshot.done do
		done[id] = true
	end
	lined = Research.lined(if state.active then state.active.id else nil, state.queue, state.ready)
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

-- How many times each project is in the line (Research.lined).
function ResearchClient.lined(): { [string]: number }
	return lined
end

-- A ranked project's finished ranks.
function ResearchClient.rank(id: string): number
	return state.ranks[id] or 0
end

function ResearchClient.isSynced(): boolean
	return synced
end

return ResearchClient
