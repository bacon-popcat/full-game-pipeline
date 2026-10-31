-- Expansion: clones the authored Sell shell so garden purchases share the HUD's layout,
-- buttons and modal lifecycle. Only an expected next tier is sent; the server owns price,
-- payment and entitlement. Replicated plot attributes recover state even after a late bind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local UI = require(Libraries.UI)

local Expansion = {}

-- Called before any HUD screen starts, so the copy keeps authored button baselines
-- rather than inheriting Sell's transient disabled/pending styles.
function Expansion.prepare(hud: ScreenGui)
	local template = Hud.find(hud, "Sell", "Frame")
	if not template or not template:IsA("Frame") then
		return
	end
	local frame = template:Clone()
	frame.Name = "Expansion"
	frame.Visible = false
	frame.Parent = hud
end

function Expansion.init(hud: ScreenGui)
	local frame = Hud.find(hud, "Expansion", "Frame")
	if not frame or not frame:IsA("Frame") then
		return
	end
	local title = Hud.find(frame, "Header.Title", "TextLabel")
	local description = Hud.find(frame, "Body.Held", "TextLabel")
	local price = Hud.find(frame, "Body.Total", "TextLabel")
	local buy = Hud.find(frame, "Body.SellHeld", "TextButton")
	local cancel = Hud.find(frame, "Body.SellAll", "TextButton")
	local buyLabel = Hud.find(frame, "Body.SellHeld.Label", "TextLabel")
	local cancelLabel = Hud.find(frame, "Body.SellAll.Label", "TextLabel")
	if
		not title
		or not title:IsA("TextLabel")
		or not description
		or not description:IsA("TextLabel")
		or not price
		or not price:IsA("TextLabel")
		or not buy
		or not buy:IsA("TextButton")
		or not cancel
		or not cancel:IsA("TextButton")
		or not buyLabel
		or not buyLabel:IsA("TextLabel")
		or not cancelLabel
		or not cancelLabel:IsA("TextLabel")
	then
		frame:Destroy()
		return
	end
	title.Text = "Expand your garden"
	cancelLabel.Text = "Cancel"
	cancel.Active = true
	cancel.Selectable = true
	local trove = Trove.new()
	local plotTrove = Trove.new()
	trove:Add(plotTrove)
	local selected = 0
	local expected = 0
	local pending = false
	local request = 0
	local baseline = buy.BackgroundTransparency
	local textBaseline = buyLabel.TextTransparency
	local function render()
		local tier = Plot.tier(selected)
		local size = Plot.size(tier)
		local offer = Plot.EXPANSIONS[tier + 1]
		expected = tier + 1
		local enabled = not pending and offer ~= nil and EconomyClient.get().coins >= offer.price
		buy.Active = enabled
		buy.Selectable = enabled
		buy.BackgroundTransparency = if enabled then baseline else baseline + (1 - baseline) * 0.5
		buyLabel.TextTransparency = if enabled then textBaseline else textBaseline + (1 - textBaseline) * 0.5
		if offer then
			description.Text = `{size} x {size} -> {offer.size} x {offer.size} cells`
			price.Text = `{Hud.number(offer.price)} coins for +{offer.size ^ 2 - size ^ 2} cells`
			buyLabel.Text = if pending then "..." elseif enabled then "Buy expansion" else "Need coins"
		else
			description.Text = `{size} x {size} cells - fully expanded!`
			price.Text = "All your garden space is unlocked."
			buyLabel.Text = "Owned"
		end
	end
	local window = HubWindow.bind(hud, "Expansion", { "0" }, render, function(opener: string)
		selected = tonumber(opener) or 0
		pending = false
		request += 1
		plotTrove:Clean()
		local model = Plot.model(selected)
		if model then
			plotTrove:Connect(model:GetAttributeChangedSignal("Expansion"), render)
		end
		render()
	end, {
		inReach = function(player: Player, opener: string): boolean
			local index = tonumber(opener)
			return index ~= nil and Plot.inReach(player, index)
		end,
		opener = function(prompt: ProximityPrompt): string?
			local anchor = prompt.Parent
			local model = if anchor then anchor.Parent else nil
			local index = if model then tonumber(model.Name) else nil
			return if prompt.Name == "ExpandPlot"
					and anchor
					and anchor.Name == "ExpansionSign"
					and model
					and index
					and Plot.model(index) == model
				then model.Name
				else nil
		end,
	})
	if not window then
		trove:Destroy()
		frame:Destroy()
		return
	end
	trove:Add(UI.bindButton(cancel, { onActivate = window.close }))
	trove:Add(UI.bindButton(buy, {
		onActivate = function()
			if not buy.Active or pending then
				return
			end
			local nextTier = expected
			pending = true
			request += 1
			local token = request
			render()
			Remotes.PlotExpand:FireServer(nextTier)
			-- A throttled request has no response. Never leave the confirmation disabled forever.
			task.delay(2, function()
				if token == request and frame.Parent then
					pending = false
					render()
				end
			end)
		end,
	}))
	trove:Connect(Remotes.Notify.OnClientEvent, function()
		pending = false
		render()
	end)
	trove:Connect(EconomyClient.changed, render)
	trove:Connect(hud.Destroying, function()
		request += 1
		trove:Destroy()
	end)
end

return Expansion
