-- QuestsScreen: the Quests window (HUD.Quests), toggled by SideButtons.Quests, whose Badge.Count
-- shows ProgressClient.claimable() even while the window is closed. One Assets.UI.Progress.Quest
-- row per active quest slot (ProgressClient), in slot order: what to do, its reward, progress and
-- a Claim button that wakes once the quest is done. A claim waits for the next ProgressSync
-- (ProgressService replaces the quest and pays out), or PENDING_FOR seconds on a dropped answer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Progress = require(ReplicatedStorage.Shared.Progress)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local ProgressClient = require(Libraries.ProgressClient)
local UI = require(Libraries.UI)

local PENDING_FOR = 2
local SKY = Color3.fromRGB(142, 197, 255)
local DONE = Color3.fromRGB(157, 220, 154)

type Row = {
	frame: Frame,
	text: TextLabel,
	reward: TextLabel,
	count: TextLabel,
	fill: Frame,
	claim: TextButton,
	label: TextLabel,
	transparency: number,
}

local QuestsScreen = {}

local function rewardText(reward: Progress.Reward): string
	local parts = {}
	if reward.coins > 0 then
		table.insert(parts, `+{Hud.number(reward.coins)} coins`)
	end
	if reward.xp > 0 then
		table.insert(parts, `{Hud.number(reward.xp)} XP`)
	end
	return table.concat(parts, "  ·  ")
end

function QuestsScreen.init(hud: ScreenGui)
	local list = Hud.find(hud, "Quests.Body.List", "ScrollingFrame")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Progress.Quest", "Frame")
	if not list or not template or not template:IsA("Frame") then
		return
	end
	local trove = Trove.new()
	local rows: { Row } = {}
	local pendingSince: number? = nil

	local function rowFor(slot: number): Row?
		if rows[slot] then
			return rows[slot]
		end
		local frame = template:Clone()
		local text = Hud.find(frame, "Text", "TextLabel")
		local reward = Hud.find(frame, "Reward", "TextLabel")
		local count = Hud.find(frame, "Count", "TextLabel")
		local fill = Hud.find(frame, "Track.Fill", "Frame")
		local claim = Hud.find(frame, "Claim", "TextButton")
		local label = Hud.find(frame, "Claim.Label", "TextLabel")
		if not (text and reward and count and fill and claim and label) then
			frame:Destroy()
			return nil
		end
		assert(text:IsA("TextLabel") and reward:IsA("TextLabel") and count:IsA("TextLabel"), "Quest row labels")
		assert(fill:IsA("Frame") and claim:IsA("TextButton") and label:IsA("TextLabel"), "Quest row parts")
		frame.Name = `Quest{slot}`
		frame.LayoutOrder = slot
		frame.Parent = list
		trove:Add(frame)
		trove:Add(UI.bindButton(claim, {
			onActivate = function()
				if claim.Active and not pendingSince then
					pendingSince = os.clock()
					ProgressClient.claimQuest(slot)
				end
			end,
		}))
		local row = {
			frame = frame,
			text = text,
			reward = reward,
			count = count,
			fill = fill,
			claim = claim,
			label = label,
			transparency = claim.BackgroundTransparency,
		}
		rows[slot] = row
		return row
	end

	local function render()
		local quests = ProgressClient.get().quests
		for slot = 1, math.max(#quests, #rows) do
			local view = quests[slot]
			local quest = if view then Progress.getQuest(view.id) else nil
			local row = if quest then rowFor(slot) else rows[slot]
			if row then
				row.frame.Visible = quest ~= nil
			end
			if row and view and quest then
				local enabled = view.done and pendingSince == nil
				row.text.Text = quest.text
				row.reward.Text = rewardText(quest.reward)
				row.count.Text = `{Hud.number(view.progress)} / {Hud.number(view.goal)}`
				row.fill.Size = UDim2.fromScale(if view.goal > 0 then math.min(1, view.progress / view.goal) else 1, 1)
				row.fill.BackgroundColor3 = if view.done then DONE else SKY
				row.claim.Active = enabled
				row.claim.Selectable = enabled
				row.claim.BackgroundTransparency = if enabled
					then row.transparency
					else row.transparency + (1 - row.transparency) * 0.5
				row.label.TextTransparency = if enabled then 0 else 0.5
				row.label.Text = if pendingSince and view.done
					then "..."
					elseif view.done then "Claim"
					else "In progress"
			end
		end
	end

	local window = HubWindow.bind(hud, "Quests", {}, render)
	if not window then
		trove:Destroy()
		return
	end
	local opener = Hud.find(hud, "SideButtons.Quests", "TextButton")
	local badge = Hud.find(hud, "SideButtons.Quests.Badge", "Frame")
	local badgeCount = Hud.find(hud, "SideButtons.Quests.Badge.Count", "TextLabel")
	local function paintBadge()
		local count = ProgressClient.claimable()
		if badge and badge:IsA("GuiObject") then
			badge.Visible = count > 0
		end
		if badgeCount and badgeCount:IsA("TextLabel") then
			badgeCount.Text = if count > 9 then "9+" else tostring(count)
		end
	end
	if opener then
		trove:Add(UI.bindButton(opener, {
			hoverScale = 1.08,
			onActivate = function()
				if window.isOpen() then
					window.close()
				else
					window.open()
				end
			end,
		}))
	end
	trove:Connect(ProgressClient.changed, function()
		pendingSince = nil
		paintBadge()
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
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
	paintBadge()
	render()
end

return QuestsScreen
