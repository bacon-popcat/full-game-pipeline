-- WelcomeScreen: the welcome-back card (HUD.Welcome), opened by itself once a garden has loaded
-- when WelcomeService has something to greet the player with: time away, crops that are ripe, a
-- research project waiting, offline coins and the daily gift (Remotes.WelcomeSync). Body holds
-- one line each (Away, Crops, Research, Coins, Gift), shown only when it has something to say,
-- and Collect, which takes the coins and the gift (the server answers with a new sync) or, with
-- nothing owed, just closes the card. Closing without collecting loses nothing: what is owed is
-- saved and offered again next time. tools/hud/welcome_hud.luau authors the nodes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Welcome = require(ReplicatedStorage.Shared.Welcome)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local UI = require(Libraries.UI)

-- Seconds after the garden opens before the card appears, so the save menu has cleared.
local OPEN_DELAY = 1.5
-- Seconds a Collect waits for the server's answer before the button wakes again anyway.
local PENDING_FOR = 2
local LINES = { "Away", "Crops", "Research", "Coins", "Gift" }

type Gift = { day: number, coins: number, rarity: string?, count: number? }
type Snapshot = { greet: boolean, away: number, ripe: number, research: string?, coins: number, gift: Gift? }

local WelcomeScreen = {}

local function giftText(gift: Gift): string
	if gift.rarity then
		local count = gift.count or 1
		return `Day {gift.day} gift  ·  {count} {gift.rarity} {if count == 1 then "seed" else "seeds"}`
	end
	return `Day {gift.day} gift  ·  {Hud.number(gift.coins)} coins`
end

function WelcomeScreen.init(hud: ScreenGui)
	local labels: { [string]: TextLabel } = {}
	for _, name in LINES do
		local label = Hud.find(hud, `Welcome.Body.{name}`, "TextLabel")
		if not label or not label:IsA("TextLabel") then
			return
		end
		labels[name] = label
	end
	local collect = Hud.find(hud, "Welcome.Body.Collect", "TextButton")
	local collectLabel = Hud.find(hud, "Welcome.Body.Collect.Label", "TextLabel")
	if not collect or not collect:IsA("TextButton") or not collectLabel or not collectLabel:IsA("TextLabel") then
		return
	end
	local trove = Trove.new()
	local latest: Snapshot? = nil
	-- Whether the latest sync still waits to greet the player.
	local greeting = false
	local pendingSince: number? = nil

	local function owed(snapshot: Snapshot): boolean
		return snapshot.coins > 0 or snapshot.gift ~= nil
	end

	local function render()
		local snapshot = latest
		if not snapshot then
			return
		end
		local lines: { [string]: string? } = {
			Away = if snapshot.away >= Welcome.AWAY_MIN then `You were away for {Hud.span(snapshot.away)}.` else nil,
			Crops = if snapshot.ripe > 0
				then `{Hud.number(snapshot.ripe)} {if snapshot.ripe == 1 then "crop is" else "crops are"} ready to harvest.`
				else nil,
			Research = if snapshot.research then `{snapshot.research} is ready to complete in Research.` else nil,
			Coins = if snapshot.coins > 0
				then `Your Shipping Bins earned {Hud.number(snapshot.coins)} coins while you were away.`
				else nil,
			Gift = if snapshot.gift then giftText(snapshot.gift) else nil,
		}
		for name, label in labels do
			local text = lines[name]
			label.Visible = text ~= nil
			label.Text = text or ""
		end
		collectLabel.Text = if pendingSince then "..." elseif owed(snapshot) then "Collect" else "Close"
	end

	local window = HubWindow.bind(hud, "Welcome", {}, render)
	if not window then
		trove:Destroy()
		return
	end

	local function greet()
		if greeting and latest and Players.LocalPlayer:GetAttribute("DataReady") == true then
			greeting = false
			window.open()
		end
	end

	trove:Add(UI.bindButton(collect, {
		onActivate = function()
			local snapshot = latest
			if not snapshot or not owed(snapshot) then
				window.close()
			elseif not pendingSince then
				pendingSince = os.clock()
				Remotes.Welcome:FireServer("Collect")
				render()
			end
		end,
	}))
	trove:Connect(Remotes.WelcomeSync.OnClientEvent, function(snapshot: Snapshot)
		local answered = pendingSince ~= nil
		pendingSince = nil
		latest = snapshot
		if snapshot.greet then
			-- The load sync comes before the garden is ready; the card waits for it.
			greeting = true
			task.delay(OPEN_DELAY, greet)
		elseif window.isOpen() then
			if answered and not owed(snapshot) then
				window.close()
			else
				render()
			end
		end
	end)
	trove:Connect(Players.LocalPlayer:GetAttributeChangedSignal("DataReady"), function()
		if Players.LocalPlayer:GetAttribute("DataReady") == true then
			task.delay(OPEN_DELAY, greet)
		else
			-- Back at the save menu: this garden's greeting is over.
			greeting = false
			latest = nil
		end
	end)
	trove:Connect(RunService.Heartbeat, function()
		if pendingSince and os.clock() - pendingSince > PENDING_FOR then
			pendingSince = nil
			render()
		end
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return WelcomeScreen
