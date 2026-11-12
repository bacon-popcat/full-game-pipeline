-- ResearchService: owns each loaded profile's research line: one paid, wall-clock project
-- running, more lined up behind it (paid when lined up) and finished ones waiting for their
-- Complete (rules: Shared/Research). Requests validate before spending or refunding without
-- yielding. When the running project's timer runs out the next queued one starts; a finished
-- project waits, saved, until its player completes it, and completing alone applies its bonus
-- (a rank, for a ranked project) and announces ResearchDone. The one-second loop moves the line
-- along and tells the player when something more is ready.
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
-- How many finished projects each player has been told about, so the loop says each once.
local announced: { [Player]: number } = {}
local ResearchService = {}

local function wallTime(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function wholeSeconds(value: any): boolean
	return finite(value) and value >= 1 and value % 1 == 0
end

local function plotOf(player: Player): Model?
	local index = PlotService.get(player)
	return if index then Plot.model(index) else nil
end

-- Whether a running project's timer has run out (with Research.READY_EARLY to spare).
local function isReady(active: Research.Active, early: number?): boolean
	return Research.isReady(active.startedAt + active.seconds, wallTime() + (early or 0))
end

local function linedOf(state: Research.Saved): { [string]: number }
	return Research.lined(if state.active then state.active.id else nil, state.queue, state.ready)
end

local function roomOf(player: Player): number
	return Research.ROOM + Bonuses.get(player, "researchQueue")
end

-- Finished projects waiting for Complete, the running one included once its timer runs out.
local function readyCount(state: Research.Saved): number
	return #state.ready + (if state.active and isReady(state.active) then 1 else 0)
end

-- "Rich Soil II", or "Farming Mastery 4" for a ranked project's rank.
local function title(project: Research.Project, rank: number?): string
	return if project.ranked and rank then `{project.name} {rank}` else project.name
end

local function publish(player: Player, state: Research.Saved)
	local stats = Research.bonuses(state.done, state.ranks)
	Bonuses.set(player, state.done, stats, state.ranks)
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
	local queue = {}
	for _, entry in if state then state.queue else {} do
		table.insert(queue, { id = entry.id, seconds = entry.seconds })
	end
	local snapshot: Research.Snapshot = {
		done = done,
		ranks = if state then table.clone(state.ranks) else {},
		active = if active
			then {
				id = active.id,
				endsAt = workspace:GetServerTimeNow() + (active.startedAt + active.seconds - wallTime()),
				seconds = active.seconds,
			}
			else nil,
		queue = queue,
		ready = if state then table.clone(state.ready) else {},
		room = roomOf(player),
		bonuses = Research.bonuses(if state then state.done else {}, if state then state.ranks else nil),
	}
	Remotes.ResearchSync:FireClient(player, snapshot)
end

-- Reads a saved research table, dropping (with a warning) anything that no longer checks out.
local function sanitize(player: Player, saved: any): Research.Saved
	local state: Research.Saved = { done = {}, ranks = {}, active = nil, queue = {}, ready = {} }
	local function drop(what: string)
		warn(`ResearchService: dropped {what} for {player.UserId}`)
	end
	if typeof(saved) ~= "table" then
		drop("invalid research")
		return state
	end
	if typeof(saved.done) == "table" then
		for id, done in saved.done do
			local project = if typeof(id) == "string" then Research.get(id) else nil
			if project and not project.ranked and typeof(done) == "boolean" then
				if done then
					state.done[id] = true
				end
			else
				drop("an invalid finished project")
			end
		end
	else
		drop("invalid finished projects")
	end
	if typeof(saved.ranks) == "table" then
		for id, rank in saved.ranks do
			local project = if typeof(id) == "string" then Research.get(id) else nil
			if project and project.ranked and wholeSeconds(rank) then
				state.ranks[id] = rank
			else
				drop("an invalid rank")
			end
		end
	end
	-- An unranked project may be in the line only once, and not once done.
	local seen: { [string]: boolean } = {}
	local function lineable(id: any): boolean
		local project = if typeof(id) == "string" then Research.get(id) else nil
		if not project or (not project.ranked and (state.done[id] or seen[id])) then
			return false
		end
		seen[id] = true
		return true
	end
	if typeof(saved.ready) == "table" then
		for _, id in saved.ready do
			if lineable(id) then
				table.insert(state.ready, id)
			else
				drop("an invalid finished-and-waiting project")
			end
		end
	end
	local active = saved.active
	if active ~= nil then
		if
			typeof(active) == "table"
			and lineable(active.id)
			and finite(active.startedAt)
			and active.startedAt >= 0
			and wholeSeconds(active.seconds)
			and finite(active.startedAt + active.seconds)
		then
			state.active = { id = active.id, startedAt = active.startedAt, seconds = active.seconds }
		else
			drop("an invalid active project")
		end
	end
	if typeof(saved.queue) == "table" then
		for _, entry in saved.queue do
			if
				typeof(entry) == "table"
				and lineable(entry.id)
				and wholeSeconds(entry.seconds)
				and finite(entry.at)
				and entry.at >= 0
			then
				table.insert(state.queue, { id = entry.id, seconds = entry.seconds, at = entry.at })
			else
				drop("an invalid queued project")
			end
		end
	end
	if not state.active and #state.queue > 0 then
		local nextUp = table.remove(state.queue, 1) :: Research.Queued
		state.active = { id = nextUp.id, startedAt = nextUp.at, seconds = nextUp.seconds }
	end
	return state
end

function ResearchService.load(player: Player, saved: any)
	local state = sanitize(player, saved)
	-- Time away moves the line along; nothing finishes until its Complete.
	Research.advance(state, wallTime())
	states[player] = state
	lastAction[player] = nil
	announced[player] = nil
	publish(player, state)
	sync(player)
end

function ResearchService.snapshot(player: Player): Research.Saved?
	local state = states[player]
	if not state then
		return nil
	end
	local queue = {}
	for _, entry in state.queue do
		table.insert(queue, table.clone(entry))
	end
	return {
		done = table.clone(state.done),
		ranks = table.clone(state.ranks),
		active = if state.active then table.clone(state.active) else nil,
		queue = queue,
		ready = table.clone(state.ready),
	}
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
	local now = wallTime()
	Research.advance(state, now)
	local lined = linedOf(state)
	local full = not Research.fits(state.active ~= nil, #state.queue + #state.ready, roomOf(player))
	local reason = Research.blocker(project, state.done, economy.level, lined, full)
	if reason and full and readyCount(state) > 0 then
		return "Your research queue is full. Complete a finished project to make room."
	elseif reason then
		return reason
	end
	local rank = Research.nextRank(project, state.ranks, lined)
	local price = Research.price(project, rank)
	local held: { [string]: number } = {}
	for _, stack in slots do
		if stack then
			held[stack.itemId] = (held[stack.itemId] or 0) + stack.count
		end
	end
	for itemId, count in price.items do
		if (held[itemId] or 0) < count then
			return `You need {count} {Inventory.getItem(itemId).name}.`
		end
	end
	if not EconomyService.trySpend(player, price.coins) then
		return `You need {price.coins} coins.`
	end
	for itemId, count in price.items do
		InventoryService.take(player, itemId, count)
	end
	local seconds = Research.duration(price.seconds, Bonuses.get(player, "researchSpeed"))
	local name = title(project, rank)
	local running = state.active
	if not running then
		state.active = { id = project.id, startedAt = now, seconds = seconds }
	else
		local entry: Research.Queued = { id = project.id, seconds = seconds, at = now }
		table.insert(state.queue, entry)
		Research.advance(state, now)
		if table.find(state.queue, entry) then
			local ahead = Research.get(running.id)
			return `Queued {name}. It starts after {if ahead then ahead.name else "the running project"}.`, "Success"
		end
	end
	return string.format("Researching %s (%d:%02d).", name, seconds // 60, seconds % 60), "Success"
end

-- Takes a queued project (`queueIndex`), or the running one when nil, out of a copy of the line,
-- then every queued project that no longer has its needs, and starts the next. Returns the copy,
-- what it all refunds and how many projects were taken out.
local function withdraw(
	state: Research.Saved,
	queueIndex: number?
): (Research.Saved, number, { [string]: number }, number)
	local copy: Research.Saved = {
		done = state.done,
		ranks = state.ranks,
		active = state.active,
		queue = table.clone(state.queue),
		ready = state.ready,
	}
	local coins, items, removed = 0, {}, 0
	-- A ranked project refunds its highest lined rank, so what stays lined stays paid for.
	local function refund(id: string)
		local project = Research.get(id)
		assert(project, "ResearchService: a lined project must exist")
		local lined = Research.lined(if copy.active then copy.active.id else nil, copy.queue, copy.ready)
		local price = Research.price(project, (copy.ranks[id] or 0) + (lined[id] or 1))
		coins += price.coins
		for itemId, count in price.items do
			items[itemId] = (items[itemId] or 0) + count
		end
		removed += 1
	end
	if queueIndex then
		refund(copy.queue[queueIndex].id)
		table.remove(copy.queue, queueIndex)
	else
		local active = copy.active
		assert(active, "ResearchService: withdraw needs a running project")
		refund(active.id)
		copy.active = nil
	end
	repeat
		local dropped = false
		local lined = Research.lined(if copy.active then copy.active.id else nil, copy.queue, copy.ready)
		for index, entry in copy.queue do
			local project = Research.get(entry.id)
			assert(project, "ResearchService: a queued project must exist")
			for _, need in project.needs do
				if not copy.done[need] and not lined[need] then
					refund(entry.id)
					table.remove(copy.queue, index)
					dropped = true
					break
				end
			end
			if dropped then
				break
			end
		end
	until not dropped
	if not copy.active and #copy.queue > 0 then
		local nextUp = table.remove(copy.queue, 1) :: Research.Queued
		copy.active = { id = nextUp.id, startedAt = math.max(wallTime(), nextUp.at), seconds = nextUp.seconds }
	end
	return copy, coins, items, removed
end

-- Cancels a queued project by id (its last place in the line), or the running one.
local function cancel(player: Player, state: Research.Saved, id: unknown): (string, Notices.Kind?)
	Research.advance(state, wallTime())
	local queueIndex: number? = nil
	if typeof(id) == "string" then
		for index = #state.queue, 1, -1 do
			if state.queue[index].id == id then
				queueIndex = index
				break
			end
		end
	end
	local active = state.active
	if not queueIndex then
		if not active or (typeof(id) == "string" and active.id ~= id) then
			return "That research isn't running or queued."
		elseif isReady(active, Research.READY_EARLY) then
			return "This research is done. Complete it instead."
		end
	end
	local copy, coins, items, removed = withdraw(state, queueIndex)
	if not InventoryService.canGiveAll(player, items) then
		return "Make room in your inventory for the research refund."
	end
	if not EconomyService.add(player, coins) then
		return "Your garden is still loading."
	end
	for itemId, count in items do
		InventoryService.give(player, itemId, count)
	end
	state.active = copy.active
	state.queue = copy.queue
	local also = if removed > 1
		then ` ({removed - 1} queued project{if removed > 2 then "s" else ""} that needed it too)`
		else ""
	return `Research cancelled{also}. Refunded {coins} coins.`, "Success"
end

-- Finishes a project whose timer has run out (by id, else the first waiting): its bonus or rank
-- applies and ResearchDone fires.
local function complete(player: Player, state: Research.Saved, id: unknown): (string, Notices.Kind?)
	Research.advance(state, wallTime())
	local active = state.active
	local activeReady = active ~= nil and isReady(active, Research.READY_EARLY)
	local index: number? = nil
	local fromActive = false
	if typeof(id) == "string" then
		index = table.find(state.ready, id)
		fromActive = not index and activeReady and active ~= nil and active.id == id
	else
		index = if #state.ready > 0 then 1 else nil
		fromActive = not index and activeReady
	end
	local finishedId: string
	if index then
		finishedId = table.remove(state.ready, index) :: string
	elseif fromActive and active then
		finishedId = active.id
		state.active = nil
		if #state.queue > 0 then
			-- Only within READY_EARLY of its end can a queue still stand behind it.
			local nextUp = table.remove(state.queue, 1) :: Research.Queued
			state.active = { id = nextUp.id, startedAt = math.max(wallTime(), nextUp.at), seconds = nextUp.seconds }
		end
	elseif active then
		return "That research isn't finished yet."
	else
		return "No research is ready."
	end
	local project = Research.get(finishedId)
	assert(project, "ResearchService: a finished project must exist")
	local rank: number? = nil
	if project.ranked then
		rank = (state.ranks[finishedId] or 0) + 1
		state.ranks[finishedId] = rank
	else
		state.done[finishedId] = true
	end
	announced[player] = readyCount(state)
	publish(player, state)
	GardenEvents.ResearchDone:Fire(player, finishedId)
	return `Research complete! {title(project, rank)}`, "Reward"
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
			message, kind = cancel(player, state, id)
		elseif action == "Complete" then
			message, kind = complete(player, state, id)
		else
			message = "Choose Start, Cancel or Complete."
		end
	end
	-- A finished project has its own sound (ResearchDone, through Fx).
	Remotes.Notify:FireClient(player, message, kind or "Error", if kind == "Reward" then { quiet = true } else nil)
	sync(player)
end

-- Moves the line along and tells the player when another project is ready, once each.
local function tick(player: Player, state: Research.Saved)
	local moved = Research.advance(state, wallTime())
	local count = readyCount(state)
	local told = announced[player] or 0
	if count <= told then
		announced[player] = count
		if moved then
			sync(player)
		end
		return
	end
	announced[player] = count
	local active = state.active
	local newest = if active and isReady(active) then active.id else state.ready[#state.ready]
	local project = Research.get(newest)
	assert(project, "ResearchService: a finished project must exist")
	local message = if count - told > 1
		then `{count - told} research projects are ready! Open Research to complete them.`
		else `{project.name} is ready! Open Research to complete it.`
	Remotes.Notify:FireClient(player, message, "Quest", { open = "Research" })
	sync(player)
end

function ResearchService.init()
	Remotes.Research.OnServerEvent:Connect(onResearch)
	while true do
		task.wait(1)
		for player, state in states do
			if player.Parent == Players and player:GetAttribute("DataReady") == true then
				tick(player, state)
			end
		end
	end
end

return ResearchService
