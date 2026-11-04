-- SaveMenuController: the save menu, the authored PlayerGui.SaveMenu screen. It is open
-- whenever no garden is loaded (the player's DataReady isn't true): on joining, after "Save &
-- quit to menu" in Settings, and after a load the server turned down. While it is open the
-- HUD is hidden and the character can't walk.
--
-- One card per save file, cloned from Assets.UI.SaveMenu.Card into Window.Body.Slots, says
-- what the server's latest SaveSlots holds. Play loads a slot (an empty one starts a new
-- garden); Delete asks first in Window.Confirm. Only one request is out at a time: the cards
-- go quiet and Window.Body.Status says what's happening until the server answers with
-- DataReady or a new SaveSlots. On join the server opens the garden played last by itself
-- (SaveSlots `loading`), so a returning player only sees the menu while it opens.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = script.Parent.Parent.Libraries
local Hud = require(Libraries.Hud)
local HudVisibility = require(Libraries.HudVisibility)
local UI = require(Libraries.UI)

type Slot = { empty: boolean, level: number?, coins: number?, savedAt: number? }
type Card = Frame & { Title: TextLabel, Details: TextLabel, Play: TextButton, Delete: TextButton }

local SaveMenuController = {}

-- "2 days ago", from Unix seconds.
local function ago(at: number): string
	local seconds = math.max(0, os.time() - at)
	for _, unit in { { 86400, "day" }, { 3600, "hour" }, { 60, "minute" } } do
		local count = seconds // unit[1]
		if count >= 1 then
			return `{count} {unit[2]}{if count == 1 then "" else "s"} ago`
		end
	end
	return "just now"
end

local function describe(slot: Slot): string
	if slot.empty then
		return "Empty"
	end
	local text = `Level {slot.level or 1}  •  {Hud.number(slot.coins or 0)} coins`
	return if slot.savedAt then `{text}\nSaved {ago(slot.savedAt)}` else text
end

function SaveMenuController.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild("SaveMenu", 10)
	if not screen or not screen:IsA("ScreenGui") then
		warn("SaveMenuController: PlayerGui.SaveMenu must be an authored ScreenGui")
		return
	end
	local list = Hud.find(screen, "Window.Body.Slots", "Frame")
	local status = Hud.find(screen, "Window.Body.Status", "TextLabel")
	local confirm = Hud.find(screen, "Window.Confirm", "Frame")
	local confirmText = Hud.find(screen, "Window.Confirm.Text", "TextLabel")
	local yes = Hud.find(screen, "Window.Confirm.Yes", "TextButton")
	local no = Hud.find(screen, "Window.Confirm.No", "TextButton")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.SaveMenu.Card", "Frame")
	if not list or not status or not confirm or not confirmText or not yes or not no or not template then
		return
	end
	assert(status:IsA("TextLabel") and confirmText:IsA("TextLabel"), "SaveMenu labels must be TextLabels")
	assert(yes:IsA("TextButton") and no:IsA("TextButton"), "SaveMenu confirm buttons must be TextButtons")
	-- HudVisibility hides the HUD while the menu is open; wait for it to be there to hide.
	playerGui:WaitForChild("HUD", 10)
	local controls = nil
	local playerModule = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
	if playerModule and playerModule:IsA("ModuleScript") then
		local ok, module = pcall(require, playerModule)
		controls = if ok then module:GetControls() else nil
	end

	local trove = Trove.new()
	local cards: { Card } = {}
	local slots: { Slot } = {}
	-- What the request under way is doing, while one is.
	local pending: string? = nil
	local message: string? = nil
	local deleting: number? = nil

	local function isOpen(): boolean
		return player:GetAttribute("DataReady") ~= true
	end

	local function render()
		local open = isOpen()
		screen.Enabled = open
		HudVisibility.hide("SaveMenu", open)
		if controls then
			if open then
				controls:Disable()
			else
				controls:Enable()
			end
		end
		if not open then
			return
		end
		local waiting = pending ~= nil or #slots == 0
		for index, card in cards do
			local slot = slots[index]
			card.Details.Text = if slot then describe(slot) else ""
			card.Play.Text = if slot and slot.empty then "New garden" else "Play"
			card.Play.Active = not waiting
			card.Play.AutoButtonColor = not waiting
			card.Delete.Visible = slot ~= nil and not slot.empty
			card.Delete.Active = not waiting
		end
		status.Text = pending or message or (if #slots == 0 then "Finding your gardens…" else "")
		confirm.Visible = deleting ~= nil and not waiting
		if deleting then
			confirmText.Text = `Delete Garden {deleting}? This can't be undone.`
		end
	end

	local function focus()
		if not isOpen() or UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad then
			return
		end
		GuiService.SelectedObject = if deleting then no elseif cards[1] then cards[1].Play else nil
	end

	local function request(action: "Load" | "Delete", slot: number, doing: string)
		if pending then
			return
		end
		pending = doing
		message = nil
		deleting = nil
		Remotes.SaveMenu:FireServer(action, slot)
		render()
	end

	local function addCard(index: number)
		local card = template:Clone() :: Card
		card.Name = `Slot{index}`
		card.LayoutOrder = index
		card.Title.Text = `Garden {index}`
		card.Parent = list
		cards[index] = card
		trove:Add(UI.bindButton(card.Play, {
			onActivate = function()
				local slot = slots[index]
				if slot and not pending then
					request(
						"Load",
						index,
						if slot.empty then `Planting Garden {index}…` else `Opening Garden {index}…`
					)
				end
			end,
		}))
		trove:Add(UI.bindButton(card.Delete, {
			onActivate = function()
				if not pending and slots[index] and not slots[index].empty then
					deleting = index
					render()
					focus()
				end
			end,
		}))
	end
	trove:Add(UI.bindButton(yes, {
		onActivate = function()
			if deleting then
				request("Delete", deleting, `Deleting Garden {deleting}…`)
			end
		end,
	}))
	trove:Add(UI.bindButton(no, {
		onActivate = function()
			deleting = nil
			render()
			focus()
		end,
	}))

	trove:Connect(Remotes.SaveSlots.OnClientEvent, function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.slots) ~= "table" then
			return
		end
		slots = payload.slots
		-- One card per slot the server says there are; DataService owns the count.
		for index = #cards + 1, #slots do
			addCard(index)
		end
		message = if typeof(payload.message) == "string" then payload.message else nil
		-- On join the server is already opening the garden played last; wait for it.
		pending = if typeof(payload.loading) == "number" then `Opening Garden {payload.loading}…` else nil
		render()
		focus()
	end)
	local wasReady = not isOpen()
	trove:Connect(player:GetAttributeChangedSignal("DataReady"), function()
		local ready = not isOpen()
		if wasReady and not ready then
			-- Quitting: the garden is saving, and the server sends the slots when it has.
			pending = pending or "Saving your garden…"
		elseif ready then
			pending = nil
			deleting = nil
		end
		wasReady = ready
		render()
		focus()
	end)
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), focus)
	render()
	focus()
end

return SaveMenuController
