-- WelcomeScreen: the welcome-back card (HUD.Welcome), opened by itself once a garden has loaded
-- when WelcomeService has something to greet the player with: time away, crops that are ripe, a
-- research project waiting, offline coins and the daily gift (Remotes.WelcomeSync).
--
-- Body holds Away (a line), Rows (Crops, Research, Coins: each a Frame with a rich-text Text),
-- Gift (Label, Reward and a Track of Day1..Day7 pips) and Collect, which takes the coins and the
-- gift (the server answers with a new sync) or, with nothing owed, just closes the card. Each part
-- shows only when it has something to say, and the card's height follows what is shown. Closing
-- without collecting loses nothing: what is owed is saved and offered again next time.
--
-- Motion, while the card is open: the rows and gift pop in one after another, coin amounts count
-- up, the Header's Rays turn, a Shine sweeps the gift and the button, and today's pip pulses.
-- tools/hud/welcome_hud.luau authors the nodes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TextColors = require(ReplicatedStorage.Shared.TextColors)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Welcome = require(ReplicatedStorage.Shared.Welcome)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local UI = require(Libraries.UI)

-- Seconds after the garden opens before the card appears, so the save menu and the loading
-- screen (ReplicatedFirst.LoadingScreen) have cleared.
local OPEN_DELAY = 2.2
-- Seconds a Collect waits for the server's answer before the button wakes again anyway.
local PENDING_FOR = 2
local ROWS = { "Crops", "Research", "Coins" }
-- How long coin amounts take to count up, and the gap between parts popping in.
local COUNT_FOR = 1.1
local STAGGER = 0.08
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Seconds for one sweep of the shines, and how far the rays turn each second (degrees).
local SHINE_EVERY = 2.6
local RAY_SPEED = 9
-- The card's fixed heights, as welcome_hud authors them: header, body padding, the gap
-- between parts, and each part.
local HEADER = 64
local PADDING = 26
local GAP = 10
local ROW_HEIGHT = 40
local ROW_GAP = 6
local HEIGHTS = { Away = 24, Gift = 108, Collect = 46 }
local PIP_DIM = Color3.fromRGB(24, 22, 30)
local INK = Color3.fromRGB(20, 16, 8)

type Gift = { day: number, coins: number, rarity: string?, count: number? }
type Snapshot = { greet: boolean, away: number, ripe: number, research: string?, coins: number, gift: Gift? }
type Row = { frame: Frame, text: TextLabel, pop: UIScale }
type Pip = { frame: Frame, number: TextLabel, stroke: UIStroke, scale: UIScale }

local WelcomeScreen = {}

-- The colour a day of the cycle's gift reads in: gold for coins, its rarity's for seeds.
local function dayColor(day: number): Color3
	local gift = Welcome.GIFTS[day]
	return if gift and gift.rarity then TextColors.rarity(gift.rarity) else TextColors.COINS
end

local function seeds(count: number): string
	return if count == 1 then "seed" else "seeds"
end

function WelcomeScreen.init(hud: ScreenGui)
	local card = Hud.find(hud, "Welcome", "Frame")
	local limit = Hud.find(hud, "Welcome.UISizeConstraint", "UISizeConstraint")
	local away = Hud.find(hud, "Welcome.Body.Away", "TextLabel")
	local rays = Hud.find(hud, "Welcome.Header.Rays", "Frame")
	local gift = Hud.find(hud, "Welcome.Body.Gift", "Frame")
	local giftLabel = Hud.find(hud, "Welcome.Body.Gift.Label", "TextLabel")
	local giftReward = Hud.find(hud, "Welcome.Body.Gift.Reward", "TextLabel")
	local giftPop = Hud.find(hud, "Welcome.Body.Gift.Pop", "UIScale")
	local giftShine = Hud.find(hud, "Welcome.Body.Gift.Shine.UIGradient", "UIGradient")
	local collect = Hud.find(hud, "Welcome.Body.Collect", "TextButton")
	local collectLabel = Hud.find(hud, "Welcome.Body.Collect.Label", "TextLabel")
	local collectShine = Hud.find(hud, "Welcome.Body.Collect.Shine.UIGradient", "UIGradient")
	if
		not (card and card:IsA("Frame"))
		or not (limit and limit:IsA("UISizeConstraint"))
		or not (away and away:IsA("TextLabel"))
		or not (rays and rays:IsA("Frame"))
		or not (gift and gift:IsA("Frame"))
		or not (giftLabel and giftLabel:IsA("TextLabel"))
		or not (giftReward and giftReward:IsA("TextLabel"))
		or not (giftPop and giftPop:IsA("UIScale"))
		or not (giftShine and giftShine:IsA("UIGradient"))
		or not (collect and collect:IsA("TextButton"))
		or not (collectLabel and collectLabel:IsA("TextLabel"))
		or not (collectShine and collectShine:IsA("UIGradient"))
	then
		return
	end
	local rows: { [string]: Row } = {}
	for _, name in ROWS do
		local frame = Hud.find(hud, `Welcome.Body.Rows.{name}`, "Frame")
		local text = Hud.find(hud, `Welcome.Body.Rows.{name}.Text`, "TextLabel")
		local pop = Hud.find(hud, `Welcome.Body.Rows.{name}.Pop`, "UIScale")
		if not (frame and frame:IsA("Frame") and text and text:IsA("TextLabel") and pop and pop:IsA("UIScale")) then
			return
		end
		rows[name] = { frame = frame, text = text, pop = pop }
	end
	local pips: { Pip } = {}
	for day = 1, #Welcome.GIFTS do
		local frame = Hud.find(hud, `Welcome.Body.Gift.Track.Day{day}`, "Frame")
		local number = Hud.find(hud, `Welcome.Body.Gift.Track.Day{day}.Number`, "TextLabel")
		local stroke = frame and frame:FindFirstChildOfClass("UIStroke")
		local scale = frame and frame:FindFirstChildOfClass("UIScale")
		if not (frame and frame:IsA("Frame") and number and number:IsA("TextLabel") and stroke and scale) then
			return
		end
		pips[day] = { frame = frame, number = number, stroke = stroke, scale = scale }
	end
	local rayBars: { { node: GuiObject, base: number } } = {}
	for _, bar in rays:GetChildren() do
		if bar:IsA("GuiObject") then
			table.insert(rayBars, { node = bar, base = bar.Rotation })
		end
	end
	for _, label in { away, giftLabel, giftReward } do
		label.RichText = true
	end
	for _, row in rows do
		row.text.RichText = true
	end

	local trove = Trove.new()
	local latest: Snapshot? = nil
	-- Whether the latest sync still waits to greet the player.
	local greeting = false
	local pendingSince: number? = nil
	-- When the amounts started counting up (os.clock), or nil once they have landed.
	local countFrom: number? = nil
	local clock = 0

	local function owed(snapshot: Snapshot): boolean
		return snapshot.coins > 0 or snapshot.gift ~= nil
	end

	-- `amount` as far as the count-up has got.
	local function counted(amount: number): number
		if not countFrom then
			return amount
		end
		local t = math.clamp((os.clock() - countFrom) / COUNT_FOR, 0, 1)
		return math.floor(amount * (1 - (1 - t) ^ 3) + 0.5)
	end

	local function giftText(snapshot: Gift): string
		if snapshot.rarity then
			local count = snapshot.count or 1
			return `{TextColors.paint(`{count} {snapshot.rarity}`, TextColors.rarity(snapshot.rarity))} {seeds(count)}`
		end
		return TextColors.paint(`{Hud.number(counted(snapshot.coins))} coins`, TextColors.COINS)
	end

	local function paintTrack(today: number)
		for day, pip in pips do
			local color = dayColor(day)
			if day < today then
				pip.frame.BackgroundColor3 = color:Lerp(PIP_DIM, 0.55)
				pip.number.TextColor3 = TextColors.WHITE
				pip.stroke.Color = color
				pip.stroke.Transparency = 0.4
			elseif day == today then
				pip.frame.BackgroundColor3 = color
				pip.number.TextColor3 = INK
				pip.stroke.Color = TextColors.WHITE
				pip.stroke.Transparency = 0
			else
				pip.frame.BackgroundColor3 = PIP_DIM
				pip.number.TextColor3 = TextColors.MUTED
				pip.stroke.Color = color
				pip.stroke.Transparency = 0.45
			end
			local stroke = pip.number:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = day ~= today
			end
		end
	end

	local function render()
		local snapshot = latest
		if not snapshot then
			return
		end
		local lines: { [string]: string? } = {
			Crops = if snapshot.ripe > 0
				then `{TextColors.paint(
					`{Hud.number(snapshot.ripe)} {if snapshot.ripe == 1 then "crop" else "crops"}`,
					TextColors.GOOD
				)} {if snapshot.ripe == 1 then "is" else "are"} ready to harvest.`
				else nil,
			Research = if snapshot.research
				then `{TextColors.paint(snapshot.research, TextColors.RESEARCH)} is ready to complete in Research.`
				else nil,
			Coins = if snapshot.coins > 0
				then `Your Shipping Bins earned {TextColors.paint(
					`{Hud.number(counted(snapshot.coins))} coins`,
					TextColors.COINS
				)} while you were away.`
				else nil,
		}
		local shownRows = 0
		for name, row in rows do
			local text = lines[name]
			row.frame.Visible = text ~= nil
			row.text.Text = text or ""
			shownRows += if text then 1 else 0
		end
		away.Visible = snapshot.away >= Welcome.AWAY_MIN
		away.Text = `You were away for {TextColors.paint(Hud.span(snapshot.away), TextColors.TIME)}.`
		local present = snapshot.gift
		gift.Visible = present ~= nil
		if present then
			giftLabel.Text = `DAY {present.day} GIFT`
			giftReward.Text = giftText(present)
			paintTrack(present.day)
		end
		collectLabel.Text = if pendingSince then "..." elseif owed(snapshot) then "Collect" else "Close"

		-- The card is as tall as what it shows.
		local parts = 1
		local height = HEIGHTS.Collect
		if away.Visible then
			parts += 1
			height += HEIGHTS.Away
		end
		if shownRows > 0 then
			parts += 1
			height += shownRows * ROW_HEIGHT + (shownRows - 1) * ROW_GAP
		end
		if gift.Visible then
			parts += 1
			height += HEIGHTS.Gift
		end
		height += (parts - 1) * GAP
		limit.MaxSize = Vector2.new(limit.MaxSize.X, HEADER + PADDING + height)
	end

	-- The parts pop in one after another and the amounts start counting.
	local function intro()
		countFrom = os.clock()
		local order: { UIScale } = {}
		for _, name in ROWS do
			if rows[name].frame.Visible then
				table.insert(order, rows[name].pop)
			end
		end
		if gift.Visible then
			table.insert(order, giftPop)
		end
		for index, scale in order do
			scale.Scale = 0.6
			task.delay(0.12 + index * STAGGER, function()
				TweenService:Create(scale, POP, { Scale = 1 }):Play()
			end)
		end
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
			intro()
		end
	end

	trove:Add(UI.bindButton(collect, {
		onActivate = function()
			local snapshot = latest
			if not snapshot or not owed(snapshot) then
				window.close()
			elseif not pendingSince then
				pendingSince = os.clock()
				countFrom = nil
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
	trove:Connect(RunService.RenderStepped, function(dt: number)
		if not card.Visible then
			return
		end
		clock += dt
		for _, bar in rayBars do
			bar.node.Rotation = bar.base + clock * RAY_SPEED
		end
		local sweep = (clock % SHINE_EVERY) / SHINE_EVERY
		collectShine.Offset = Vector2.new(sweep * 2.4 - 1.2, 0)
		giftShine.Offset = Vector2.new(((sweep + 0.5) % 1) * 2.4 - 1.2, 0)
		local present = latest and latest.gift
		if present and pips[present.day] then
			pips[present.day].scale.Scale = 1 + (0.5 + 0.5 * math.sin(clock * 4)) * 0.12
		end
		if countFrom then
			render()
			if os.clock() - countFrom >= COUNT_FOR then
				countFrom = nil
			end
		end
	end)
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return WelcomeScreen
