-- ResearchService: owns one paid, wall-clock project per loaded profile. Requests validate
-- before spending or refunding without yielding; completion alone announces ResearchDone.
-- DataService loads before machines/crops and releases before the plot. Invalid saved entries
-- are skipped with a warning, so a retired project can never prevent a garden from loading.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Research = require(ReplicatedStorage.Shared.Research)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)

local COOLDOWN = 0.3
local states: { [Player]: Research.Saved } = {}
local lastAction: { [Player]: number } = {}
local ResearchService = {}

local function wallTime(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function plotOf(player: Player): Model?
	local index = PlotService.get(player)
	return if index then Plot.model(index) else nil
end

local function publish(player: Player, state: Research.Saved)
	local stats = Research.bonuses(state.done)
	Bonuses.set(player, state.done, stats)
	local plot = plotOf(player)
	if plot then
		plot:SetAttribute("BeltSpeed", 1 + (stats.beltSpeed or 0))
	end
end

local function sync(player: Player)
	local state = states[player]
	local done = {}
	for _, project in Research.PROJECTS do
		if state and state.done[project.id] then
			table.insert(done, project.id)
		end
	end
	local active = if state then state.active else nil
	local snapshot: Research.Snapshot = {
		done = done,
		active = if active
			then {
				id = active.id,
				endsAt = workspace:GetServerTimeNow() + (active.startedAt + active.seconds - wallTime()),
				seconds = active.seconds,
			}
			else nil,
		bonuses = Research.bonuses(if state then state.done else {}),
	}
	Remotes.ResearchSync:FireClient(player, snapshot)
end

function ResearchService.load(player: Player, saved: any)
	local state: Research.Saved = { done = {}, active = nil }
	if typeof(saved) ~= "table" then
		warn(`ResearchService: reset invalid research for {player.UserId}`)
	else
		if typeof(saved.done) == "table" then
			for id, done in saved.done do
				if typeof(id) == "string" and Research.get(id) and typeof(done) == "boolean" then
					if done then
						state.done[id] = true
					end
				else
					warn(`ResearchService: dropped invalid finished project for {player.UserId}`)
				end
			end
		else
			warn(`ResearchService: reset invalid finished projects for {player.UserId}`)
		end
		local active = saved.active
		if active ~= nil then
			if
				typeof(active) == "table"
				and typeof(active.id) == "string"
				and Research.get(active.id)
				and not state.done[active.id]
				and finite(active.startedAt)
				and active.startedAt >= 0
				and finite(active.seconds)
				and active.seconds >= 1
				and active.seconds % 1 == 0
				and finite(active.startedAt + active.seconds)
			then
				state.active = { id = active.id, startedAt = active.startedAt, seconds = active.seconds }
			else
				warn(`ResearchService: dropped invalid active project for {player.UserId}`)
			end
		end
	end
	states[player] = state
	lastAction[player] = nil
	publish(player, state)
	sync(player)
end

function ResearchService.snapshot(player: Player): Research.Saved?
	local state = states[player]
	return if state
		then {
			done = table.clone(state.done),
			active = if state.active then table.clone(state.active) else nil,
		}
		else nil
end

function ResearchService.release(player: Player)
	local plot = plotOf(player)
	if plot then
		plot:SetAttribute("BeltSpeed", nil)
	end
	states[player] = nil
	lastAction[player] = nil
	Bonuses.clear(player)
end

local function start(player: Player, state: Research.Saved, id: unknown): string
	local project = if typeof(id) == "string" then Research.get(id) else nil
	if not project then
		return "Choose a research project."
	end
	local economy = EconomyService.get(player)
	local slots = InventoryService.snapshot(player)
	if not economy or not slots then
		return "Your garden is still loading."
	end
	local reason = Research.blocker(project, state.done, economy.level, if state.active then state.active.id else nil)
	if reason then
		return reason
	end
	local held: { [string]: number } = {}
	for _, stack in slots do
		if stack then
			held[stack.itemId] = (held[stack.itemId] or 0) + stack.count
		end
	end
	for itemId, count in project.items do
		if (held[itemId] or 0) < count then
			return `You need {count} {Inventory.getItem(itemId).name}.`
		end
	end
	if not EconomyService.trySpend(player, project.coins) then
		return `You need {project.coins} coins.`
	end
	for itemId, count in project.items do
		InventoryService.take(player, itemId, count)
	end
	local seconds = Research.duration(project, Bonuses.get(player, "researchSpeed"))
	state.active = { id = project.id, startedAt = wallTime(), seconds = seconds }
	return string.format("Researching %s (%d:%02d).", project.name, seconds // 60, seconds % 60)
end

local function cancel(player: Player, state: Research.Saved): string
	local active = state.active
	if not active then
		return "No research is running."
	end
	local project = Research.get(active.id)
	assert(project, "ResearchService: active project must exist")
	if not InventoryService.canGiveAll(player, project.items) then
		return "Make room in your inventory for the research refund."
	end
	if not EconomyService.add(player, project.coins) then
		return "Your garden is still loading."
	end
	for itemId, count in project.items do
		InventoryService.give(player, itemId, count)
	end
	state.active = nil
	return `Research cancelled. Refunded {project.coins} coins.`
end

local function onResearch(player: Player, action: unknown, id: unknown)
	local state = states[player]
	local now = os.clock()
	local message: string
	if player:GetAttribute("DataReady") ~= true or not state then
		message = "Your garden is still loading."
	elseif now - (lastAction[player] or -math.huge) < COOLDOWN then
		message = "Please wait a moment."
	else
		lastAction[player] = now
		if action == "Start" then
			message = start(player, state, id)
		elseif action == "Cancel" then
			message = cancel(player, state)
		else
			message = "Choose Start or Cancel."
		end
	end
	Remotes.Notify:FireClient(player, message)
	sync(player)
end

local function finish(player: Player, state: Research.Saved)
	local active = state.active
	if not active or wallTime() < active.startedAt + active.seconds then
		return
	end
	local project = Research.get(active.id)
	assert(project, "ResearchService: active project must exist")
	state.done[active.id] = true
	state.active = nil
	publish(player, state)
	GardenEvents.ResearchDone:Fire(player, active.id)
	Remotes.Notify:FireClient(player, `Research done: {project.name}!`)
	sync(player)
end

function ResearchService.init()
	Remotes.Research.OnServerEvent:Connect(onResearch)
	while true do
		task.wait(1)
		for player, state in states do
			if player.Parent == Players and player:GetAttribute("DataReady") == true then
				finish(player, state)
			end
		end
	end
end

return ResearchService
