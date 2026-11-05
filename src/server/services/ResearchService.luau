-- ResearchService: owns one paid, wall-clock project per loaded profile. Requests validate
-- before spending or refunding without yielding. A project whose timer has run out waits,
-- saved as active, until its player completes it; completing alone applies its bonus and
-- announces ResearchDone. The one-second loop only tells the player, once a session, that it
-- is ready.
-- DataService loads before machines/crops and releases before the plot. Invalid saved entries
-- are skipped with a warning, so a retired project can never prevent a garden from loading.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Research = require(ReplicatedStorage.Shared.Research)
local Notices = require(ReplicatedStorage.Shared.Notices)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Bonuses = require(ServerScriptService.Libraries.Bonuses)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)

local COOLDOWN = 0.3
local states: { [Player]: Research.Saved } = {}
local lastAction: { [Player]: number } = {}
-- The running project each player has already been told is ready, so the loop says it once.
local announced: { [Player]: string } = {}
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

-- Whether a running project's timer has run out (with Research.READY_EARLY to spare).
local function isReady(active: Research.Active): boolean
	return Research.isReady(active.startedAt + active.seconds, wallTime() + Research.READY_EARLY)
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
	announced[player] = nil
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
	announced[player] = nil
	Bonuses.clear(player)
end

-- Each action answers with its message, and "Success" when it went through (else a refusal).
local function start(player: Player, state: Research.Saved, id: unknown): (string, Notices.Kind?)
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
	if reason and state.active and isReady(state.active) then
		local running = Research.get(state.active.id)
		return `Complete {if running then running.name else "your research"} first.`
	elseif reason then
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
	return string.format("Researching %s (%d:%02d).", project.name, seconds // 60, seconds % 60), "Success"
end

local function cancel(player: Player, state: Research.Saved): (string, Notices.Kind?)
	local active = state.active
	if not active then
		return "No research is running."
	elseif isReady(active) then
		return "This research is done. Complete it instead."
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
	return `Research cancelled. Refunded {project.coins} coins.`, "Success"
end

-- Finishes a project whose timer has run out: its bonus applies and ResearchDone fires.
local function complete(player: Player, state: Research.Saved): (string, Notices.Kind?)
	local active = state.active
	if not active then
		return "No research is running."
	elseif not isReady(active) then
		return "That research isn't finished yet."
	end
	local project = Research.get(active.id)
	assert(project, "ResearchService: active project must exist")
	state.done[active.id] = true
	state.active = nil
	announced[player] = nil
	publish(player, state)
	GardenEvents.ResearchDone:Fire(player, active.id)
	return `Research complete! {project.name}`, "Reward"
end

local function onResearch(player: Player, action: unknown, id: unknown)
	local state = states[player]
	local now = os.clock()
	local message: string
	local kind: Notices.Kind? = nil
	if player:GetAttribute("DataReady") ~= true or not state then
		message = "Your garden is still loading."
	elseif now - (lastAction[player] or -math.huge) < COOLDOWN then
		message = "Please wait a moment."
	else
		lastAction[player] = now
		if action == "Start" then
			message, kind = start(player, state, id)
		elseif action == "Cancel" then
			message, kind = cancel(player, state)
		elseif action == "Complete" then
			message, kind = complete(player, state)
		else
			message = "Choose Start, Cancel or Complete."
		end
	end
	Remotes.Notify:FireClient(player, message, kind or "Error")
	sync(player)
end

-- Tells the player, once, that their running project's timer has run out.
local function announce(player: Player, state: Research.Saved)
	local active = state.active
	if
		not active
		or announced[player] == active.id
		or not Research.isReady(active.startedAt + active.seconds, wallTime())
	then
		return
	end
	announced[player] = active.id
	local project = Research.get(active.id)
	assert(project, "ResearchService: active project must exist")
	Remotes.Notify:FireClient(player, `{project.name} is ready! Open Research to complete it.`, "Success")
	sync(player)
end

function ResearchService.init()
	Remotes.Research.OnServerEvent:Connect(onResearch)
	while true do
		task.wait(1)
		for player, state in states do
			if player.Parent == Players and player:GetAttribute("DataReady") == true then
				announce(player, state)
			end
		end
	end
end

return ResearchService
