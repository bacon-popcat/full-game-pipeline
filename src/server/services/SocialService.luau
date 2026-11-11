-- SocialService: what players do for each other (rules and numbers: Shared/Social).
--   * A rare harvest is told to everyone else on the server (the harvester has their own notice).
--   * Each owned garden's sign carries a Visit prompt. Triggering it sends the visitor a VisitSync,
--     which opens their Visit card; from it they like the garden or gift what they hold.
--   * A like or a gift is one server step between two loaded gardens on this server: both players
--     DataReady, the visitor within reach of the sign, every cap checked, then the change made
--     without yielding. After a gift both profiles are saved at once (DataService's saver), so a
--     crash can duplicate at most the one gift caught between the two saves.
-- DataService loads it with the plot assigned and snapshots `social` with the rest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Social = require(ReplicatedStorage.Shared.Social)
local World = require(ReplicatedStorage.Shared.World)
local GardenEvents = require(ServerScriptService.Libraries.GardenEvents)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)

local ACTION_COOLDOWN = 0.3

type State = { saved: Social.Saved, index: number, lastAction: number }
local states: { [Player]: State } = {}
local prompts: { [number]: ProximityPrompt } = {}
local lastNews: { [Player]: number } = {}
local saver: ((player: Player) -> ())?
local started = false
local SocialService = {}

local function today(): number
	return Progress.day(os.time())
end

local function likesText(likes: number): string?
	return if likes > 0 then `{likes} {if likes == 1 then "like" else "likes"}` else nil
end

-- Whether `visitor` stands within reach of garden `index`'s sign.
local function atSign(visitor: Player, index: number): boolean
	local sign = PlotService.signPart(index)
	local character = visitor.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return sign ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - sign.Position).Magnitude <= Social.REACH
end

-- Whether two players' characters stand within gifting reach of each other.
local function together(visitor: Player, owner: Player): boolean
	local mine = visitor.Character and visitor.Character:FindFirstChild("HumanoidRootPart")
	local theirs = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	return mine ~= nil
		and theirs ~= nil
		and mine:IsA("BasePart")
		and theirs:IsA("BasePart")
		and (mine.Position - theirs.Position).Magnitude <= Social.GIFT_REACH
end

-- Tells `visitor` about `owner`; `open` asks their Visit card to show. `via` is how they met:
-- at the garden's "Sign" (likes) or by walking up to the "Player" (gifts).
local function sendVisit(visitor: Player, owner: Player, open: boolean, via: string): ()
	local theirs, mine = states[owner], states[visitor]
	if not theirs or not mine then
		return
	end
	local day = today()
	Social.roll(theirs.saved, day)
	Social.roll(mine.saved, day)
	local economy = EconomyService.get(visitor)
	local level = if economy then economy.level else 1
	Remotes.VisitSync:FireClient(visitor, {
		open = open,
		via = via,
		gifting = Social.gifting(visitor) and Social.gifting(owner),
		owner = owner.UserId,
		name = owner.DisplayName,
		mine = visitor == owner,
		likes = theirs.saved.likes,
		liked = mine.saved.liked[tostring(owner.UserId)] == true,
		level = level,
		capLeft = math.max(0, Social.giftCap(level) - mine.saved.given),
		receiverLeft = math.max(0, Social.GIFTS_RECEIVED - theirs.saved.received),
	})
end

local function like(visitor: Player, owner: Player): ()
	local theirs, mine = states[owner], states[visitor]
	local key = tostring(owner.UserId)
	if visitor == owner then
		Remotes.Notify:FireClient(visitor, "This is your own garden.", "Error")
	elseif mine.saved.liked[key] then
		Remotes.Notify:FireClient(visitor, "You already liked this garden today.", "Error")
	else
		mine.saved.liked[key] = true
		theirs.saved.likes += 1
		PlotService.setSignNote(theirs.index, likesText(theirs.saved.likes))
		Remotes.Notify:FireClient(visitor, `You liked {owner.DisplayName}'s garden.`, "Success")
		Remotes.Notify:FireClient(owner, `{visitor.DisplayName} liked your garden!`, "Success")
	end
end

local function gift(visitor: Player, owner: Player, count: unknown): ()
	local theirs, mine = states[owner], states[visitor]
	local economy = EconomyService.get(visitor)
	local level = if economy then economy.level else 1
	local itemId = InventoryService.getHeldItemId(visitor)
	local worth = if itemId then Social.giftWorth(itemId) else nil
	local refusal: string? = nil
	if visitor == owner then
		refusal = "You cannot give to yourself."
	elseif not Social.gifting(visitor) then
		refusal = "Turn gifting on in Settings first."
	elseif not Social.gifting(owner) then
		refusal = `{owner.DisplayName} has gifting turned off.`
	elseif level < Social.GIFT_LEVEL then
		refusal = `Gifting opens at level {Social.GIFT_LEVEL}.`
	elseif typeof(count) ~= "number" or count % 1 ~= 0 or count < 1 then
		refusal = "Choose how many to give."
	elseif not itemId or not worth then
		refusal = "Hold a crop, a product or a seed to give it."
	elseif theirs.saved.received >= Social.GIFTS_RECEIVED then
		refusal = `{owner.DisplayName}'s garden has had its gifts for today.`
	elseif mine.saved.given + worth * count > Social.giftCap(level) then
		refusal = "That is more than you can give today."
	elseif not InventoryService.canGive(owner, itemId, count) then
		refusal = `{owner.DisplayName} has no room for it.`
	end
	if refusal or not itemId or not worth or typeof(count) ~= "number" then
		Remotes.Notify:FireClient(visitor, refusal or "That cannot be given.", "Error")
		return
	end
	-- Checked above; nothing yields from the take to the give.
	local taken = InventoryService.takeHeld(visitor, itemId, count)
	if taken ~= count then
		-- The hand held fewer than asked: give back what was taken and say so.
		if taken > 0 then
			InventoryService.give(visitor, itemId, taken)
		end
		Remotes.Notify:FireClient(visitor, "You are not holding that many.", "Error")
		return
	end
	InventoryService.give(owner, itemId, count)
	mine.saved.given += worth * count
	theirs.saved.received += 1
	local name = Inventory.getItem(itemId).name
	Remotes.Notify:FireClient(visitor, `Gave {count} {name} to {owner.DisplayName}.`, "Success", { item = itemId })
	Remotes.Notify:FireClient(owner, `{visitor.DisplayName} gave you {count} {name}!`, "Reward", { item = itemId })
	GardenEvents.Gifted:Fire(visitor, owner, itemId, count)
	if saver then
		-- Both gardens saved together, so neither side is left ahead of the other for long.
		task.spawn(saver, visitor)
		task.spawn(saver, owner)
	end
end

local function act(visitor: Player, action: unknown, ownerId: unknown, count: unknown): ()
	local mine = states[visitor]
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local theirs = if owner then states[owner] else nil
	if
		not mine
		or not owner
		or not theirs
		or typeof(action) ~= "string"
		or visitor:GetAttribute("DataReady") ~= true
		or owner:GetAttribute("DataReady") ~= true
	then
		return
	end
	local now = os.clock()
	if now - mine.lastAction < ACTION_COOLDOWN then
		return
	end
	mine.lastAction = now
	local day = today()
	Social.roll(mine.saved, day)
	Social.roll(theirs.saved, day)
	if action == "Like" then
		if atSign(visitor, theirs.index) then
			like(visitor, owner)
		else
			Remotes.Notify:FireClient(visitor, `Stand at {owner.DisplayName}'s garden sign.`, "Error")
		end
		sendVisit(visitor, owner, false, "Sign")
	elseif action == "Gift" or action == "Meet" then
		-- Meet is the prompt on a player: it opens the card; Gift hands the held item over.
		if visitor == owner then
			return
		elseif not together(visitor, owner) then
			Remotes.Notify:FireClient(visitor, `Walk up to {owner.DisplayName} first.`, "Error")
		elseif action == "Gift" then
			gift(visitor, owner, count)
		end
		-- Every request is answered, so the card always shows where things stand.
		sendVisit(visitor, owner, action == "Meet" and together(visitor, owner), "Player")
	end
end

-- The Visit prompt on garden `index`'s sign, made once and switched on while the garden is owned.
local function promptFor(index: number): ProximityPrompt?
	local found = prompts[index]
	if found then
		return found
	end
	local sign = PlotService.signPart(index)
	if not sign then
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Visit"
	prompt.ActionText = "Visit"
	prompt.ObjectText = "Garden"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Triggered:Connect(function(visitor: Player)
		for owner, state in states do
			if state.index == index and states[visitor] and visitor:GetAttribute("DataReady") == true then
				sendVisit(visitor, owner, true, "Sign")
			end
		end
	end)
	prompt.Parent = sign
	prompts[index] = prompt
	return prompt
end

-- DataService's way to save one player's garden now.
function SocialService.setSaver(save: (player: Player) -> ()): ()
	saver = save
end

function SocialService.load(player: Player, value: unknown, index: number): ()
	SocialService.init()
	local saved = Social.sanitize(value)
	Social.roll(saved, today())
	states[player] = { saved = saved, index = index, lastAction = -math.huge }
	PlotService.setSignNote(index, likesText(saved.likes))
	local prompt = promptFor(index)
	if prompt then
		prompt.ObjectText = `{player.DisplayName}'s garden`
		prompt.Enabled = true
	end
end

function SocialService.snapshot(player: Player): Social.Saved?
	local state = states[player]
	return if state then Social.sanitize(state.saved) else nil
end

-- The likes a loaded garden has, for the leaderboard.
function SocialService.likes(player: Player): number
	local state = states[player]
	return if state then state.saved.likes else 0
end

function SocialService.release(player: Player): ()
	local state = states[player]
	if state then
		local prompt = prompts[state.index]
		if prompt then
			prompt.Enabled = false
		end
		PlotService.setSignNote(state.index, nil)
	end
	states[player] = nil
	lastNews[player] = nil
end

function SocialService.init(): ()
	if started then
		return
	end
	started = true
	Remotes.Social.OnServerEvent:Connect(act)
	GardenEvents.Harvested:Connect(function(player: Player, cropId: string, mutation: string?)
		if not mutation or not Social.isNews(cropId, mutation) then
			return
		end
		local now = os.clock()
		if now - (lastNews[player] or -math.huge) < Social.NOTICE_COOLDOWN then
			return
		end
		lastNews[player] = now
		local itemId = World.CROPS[cropId].produce .. "+" .. mutation
		local item = Inventory.find(itemId)
		if not item then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("DataReady") == true then
				Remotes.Notify:FireClient(other, `{player.DisplayName} harvested a {item.name}!`, "Rare", { item = itemId })
			end
		end
	end)
end

return SocialService
