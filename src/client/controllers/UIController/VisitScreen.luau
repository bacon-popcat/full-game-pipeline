-- VisitScreen: the Visit card (HUD.Visit) and the Gift prompt on other players.
--
-- The card opens two ways, and the server's VisitSync (SocialService) says which (`via`):
--   "Sign": the Visit prompt on a garden's sign. The card shows the garden's likes and Like
--     (once a day; reads Liked today, or Your garden).
--   "Player": the Gift prompt this screen hangs on every other player's character, shown only
--     while both players have the Gifting setting On (Shared/Settings, a Player attribute).
--     The card shows what the player holds (Held), GiftOne and GiftAll (one of the held item, or
--     as many as today's cap allows).
-- Body.Note says why something is closed (level, caps, gifting off) or what can still be given.
-- Every press is a request; the server's next VisitSync repaints the card. Nothing here decides
-- anything: the prompt, the setting and the caps shown are all checked again by the server.
-- tools/hud/visit_hud.luau authors the nodes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Social = require(ReplicatedStorage.Shared.Social)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local InventoryClient = require(Libraries.InventoryClient)
local UI = require(Libraries.UI)

-- Seconds a press waits for the server's answer before the buttons wake again anyway.
local PENDING_FOR = 2
local PROMPT = "GiftPrompt"
local PROMPT_DISTANCE = 8

type Visit = {
	open: boolean,
	via: string,
	gifting: boolean,
	owner: number,
	name: string,
	mine: boolean,
	likes: number,
	liked: boolean,
	level: number,
	capLeft: number,
	receiverLeft: number,
}
type Press = { button: TextButton, label: TextLabel, transparency: number }

local VisitScreen = {}

local function press(hud: ScreenGui, name: string): Press?
	local button = Hud.find(hud, `Visit.Body.{name}`, "TextButton")
	local label = Hud.find(hud, `Visit.Body.{name}.Label`, "TextLabel")
	if not button or not button:IsA("TextButton") or not label or not label:IsA("TextLabel") then
		return nil
	end
	return { button = button, label = label, transparency = button.BackgroundTransparency }
end

local function setEnabled(target: Press, enabled: boolean, text: string)
	target.button.Active = enabled
	target.button.Selectable = enabled
	target.button.BackgroundTransparency = if enabled
		then target.transparency
		else target.transparency + (1 - target.transparency) * 0.5
	target.label.TextTransparency = if enabled then 0 else 0.5
	target.label.Text = text
end

-- Hangs a Gift prompt on every other player's character, enabled while both have gifting on.
-- PromptController draws it; triggering it asks the server to open the card for that player.
local function watchPlayers(trove: any)
	local me = Players.LocalPlayer
	local prompts: { [Player]: ProximityPrompt } = {}

	local function refresh(other: Player)
		local prompt = prompts[other]
		if prompt then
			prompt.Enabled = Social.gifting(me) and Social.gifting(other) and me:GetAttribute("DataReady") == true
		end
	end
	local function attach(other: Player, character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or other.Character ~= character then
			return
		end
		local old = root:FindFirstChild(PROMPT)
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT
		prompt.ActionText = "Gift"
		prompt.ObjectText = other.DisplayName
		prompt.MaxActivationDistance = PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function()
			Remotes.Social:FireServer("Meet", other.UserId)
		end)
		prompt.Parent = root
		prompts[other] = prompt
		refresh(other)
	end
	local function watch(other: Player)
		if other == me then
			return
		end
		trove:Connect(other.CharacterAdded, function(character: Model)
			attach(other, character)
		end)
		trove:Connect(other:GetAttributeChangedSignal("Gifting"), function()
			refresh(other)
		end)
		if other.Character then
			task.spawn(attach, other, other.Character)
		end
	end
	local function refreshAll()
		for other in prompts do
			refresh(other)
		end
	end
	trove:Connect(Players.PlayerAdded, watch)
	trove:Connect(Players.PlayerRemoving, function(other: Player)
		prompts[other] = nil
	end)
	trove:Connect(me:GetAttributeChangedSignal("Gifting"), refreshAll)
	trove:Connect(me:GetAttributeChangedSignal("DataReady"), refreshAll)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
end

function VisitScreen.init(hud: ScreenGui)
	local title = Hud.find(hud, "Visit.Header.Title", "TextLabel")
	local subtitle = Hud.find(hud, "Visit.Header.Subtitle", "TextLabel")
	local likes = Hud.find(hud, "Visit.Body.Likes", "TextLabel")
	local held = Hud.find(hud, "Visit.Body.Held", "TextLabel")
	local note = Hud.find(hud, "Visit.Body.Note", "TextLabel")
	local like, giftOne, giftAll = press(hud, "Like"), press(hud, "GiftOne"), press(hud, "GiftAll")
	if
		not title
		or not title:IsA("TextLabel")
		or not likes
		or not likes:IsA("TextLabel")
		or not held
		or not held:IsA("TextLabel")
		or not note
		or not note:IsA("TextLabel")
		or not like
		or not giftOne
		or not giftAll
	then
		return
	end
	local trove = Trove.new()
	local latest: Visit? = nil
	local pendingSince: number? = nil

	-- The held stack, what one of it counts for, and how many of it today's cap still allows.
	local function holding(visit: Visit): (Inventory.Stack?, number?, number)
		local stack = InventoryClient.getSlot(InventoryClient.getSelected())
		local worth = if stack then Social.giftWorth(stack.itemId) else nil
		if not stack or not worth then
			return stack, nil, 0
		end
		return stack, worth, math.min(stack.count, visit.capLeft // worth)
	end

	local function render()
		local visit = latest
		if not visit then
			return
		end
		local waiting = pendingSince ~= nil
		local atSign = visit.via ~= "Player"
		title.Text = if atSign then `{visit.name}'s garden` else visit.name
		if subtitle and subtitle:IsA("TextLabel") then
			subtitle.Text = if atSign then "Leave a like" else "Give what you are holding"
		end
		likes.Visible = atSign
		like.button.Visible = atSign
		held.Visible = not atSign
		giftOne.button.Visible = not atSign
		giftAll.button.Visible = not atSign
		if atSign then
			likes.Text = `{Hud.number(visit.likes)} {if visit.likes == 1 then "like" else "likes"}`
			setEnabled(
				like,
				not visit.mine and not visit.liked and not waiting,
				if visit.mine then "Your garden" elseif visit.liked then "Liked today" else "Like"
			)
			note.Text = if visit.mine
				then "Visit another garden to leave a like."
				else "To give a gift, walk up to a player."
			return
		end
		local stack, worth, most = holding(visit)
		local closed: string? = if not visit.gifting
			then "Gifting is off for one of you. It is in Settings."
			elseif visit.level < Social.GIFT_LEVEL then `Gifting opens at level {Social.GIFT_LEVEL}.`
			elseif visit.receiverLeft <= 0 then `{visit.name} has had their gifts for today.`
			else nil
		held.Text = if not stack
			then "Hold a crop, a product or a seed to give it."
			elseif not worth then `{Inventory.getItem(stack.itemId).name} cannot be given.`
			else `Holding {Inventory.getItem(stack.itemId).name} x{Hud.number(stack.count)}`
		note.Text = closed
			or (
				if worth and most <= 0
					then "That is more than you can give today."
					else `You can still give {Hud.number(visit.capLeft)} coins' worth today.`
			)
		local can = closed == nil and worth ~= nil and most > 0 and not waiting
		setEnabled(giftOne, can, "Give 1")
		setEnabled(giftAll, can and most > 1, if most > 1 then `Give {Hud.number(most)}` else "Give more")
	end

	local window = HubWindow.bind(hud, "Visit", {}, render)
	if not window then
		trove:Destroy()
		return
	end

	local function send(action: string, count: number?)
		local visit = latest
		if visit and not pendingSince then
			pendingSince = os.clock()
			Remotes.Social:FireServer(action, visit.owner, count)
			render()
		end
	end
	trove:Add(UI.bindButton(like.button, {
		onActivate = function()
			if like.button.Active then
				send("Like")
			end
		end,
	}))
	trove:Add(UI.bindButton(giftOne.button, {
		onActivate = function()
			if giftOne.button.Active then
				send("Gift", 1)
			end
		end,
	}))
	trove:Add(UI.bindButton(giftAll.button, {
		onActivate = function()
			local visit = latest
			if visit and giftAll.button.Active then
				local _, _, most = holding(visit)
				send("Gift", most)
			end
		end,
	}))
	trove:Connect(Remotes.VisitSync.OnClientEvent, function(visit: Visit)
		pendingSince = nil
		latest = visit
		if visit.open then
			if window.isOpen() then
				render()
			else
				window.open()
			end
		elseif window.isOpen() then
			render()
		end
	end)
	trove:Connect(InventoryClient.changed, function()
		if window.isOpen() then
			render()
		end
	end)
	trove:Connect(RunService.Heartbeat, function()
		if pendingSince and os.clock() - pendingSince > PENDING_FOR then
			pendingSince = nil
			render()
		end
	end)
	watchPlayers(trove)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return VisitScreen
