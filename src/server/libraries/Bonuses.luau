--!strict
-- Bonuses: owns the live research effects services read, without depending on any service.
-- Plot lookups count only owned sections; clearing a profile removes all of its effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plot = require(ReplicatedStorage.Shared.Plot)
local Research = require(ReplicatedStorage.Shared.Research)
local Signal = require(ReplicatedStorage.Packages.Signal)

type State = { done: { [string]: boolean }, ranks: { [string]: number }, stats: { [Research.Stat]: number } }
local states: { [Player]: State } = {}
local Bonuses = { changed = Signal.new() }

function Bonuses.set(
	player: Player,
	done: { [string]: boolean },
	stats: { [Research.Stat]: number },
	ranks: { [string]: number }?
)
	states[player] = { done = table.clone(done), ranks = table.clone(ranks or {}), stats = table.clone(stats) }
	Bonuses.changed:Fire(player)
end

function Bonuses.clear(player: Player)
	states[player] = nil
	Bonuses.changed:Fire(player)
end

function Bonuses.get(player: Player?, stat: string): number
	local state = if player then states[player] else nil
	return if state then state.stats[stat] or 0 else 0
end

-- Whether a project is finished; a ranked one, whether it has a rank.
function Bonuses.has(player: Player, projectId: string): boolean
	local state = states[player]
	return state ~= nil and (state.done[projectId] == true or (state.ranks[projectId] or 0) > 0)
end

-- A ranked project's finished ranks.
function Bonuses.rank(player: Player, projectId: string): number
	local state = states[player]
	return if state then state.ranks[projectId] or 0 else 0
end

function Bonuses.ownerAt(cell: Vector3): Player?
	local index = Plot.at(cell)
	local plot = if index then Plot.model(index) else nil
	local owner = if plot then plot:GetAttribute("Owner") else nil
	return if typeof(owner) == "number" then Players:GetPlayerByUserId(owner) else nil
end

function Bonuses.at(cell: Vector3, stat: string): number
	return Bonuses.get(Bonuses.ownerAt(cell), stat)
end

return Bonuses
