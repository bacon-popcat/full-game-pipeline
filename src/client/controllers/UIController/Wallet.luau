-- Wallet: binds the authored balance/level labels and eases XP from authoritative state.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local Wallet = {}
function Wallet.init(hud: ScreenGui)
	local coins = Hud.find(hud, "Wallet.Coins", "TextLabel")
	local level = Hud.find(hud, "Wallet.Level", "TextLabel")
	local fill = Hud.find(hud, "Wallet.XpBar.Fill", "Frame")
	if
		not coins
		or not coins:IsA("TextLabel")
		or not level
		or not level:IsA("TextLabel")
		or not fill
		or not fill:IsA("Frame")
	then
		return
	end
	local baseline = fill.Size
	local tween: Tween? = nil
	local function render()
		local state = EconomyClient.get()
		local current, xp, needed = Economy.progress(state.xp)
		coins.Text = Hud.number(state.coins)
		level.Text = `Lv {current}`
		local size = UDim2.new(xp / needed, 0, baseline.Y.Scale, baseline.Y.Offset)
		if tween then
			tween:Cancel()
		end
		if GuiService.ReducedMotionEnabled then
			fill.Size = size
		else
			local nextTween = TweenService:Create(
				fill,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = size }
			)
			tween = nextTween
			nextTween:Play()
		end
	end
	local connection = EconomyClient.changed:Connect(render)
	hud.Destroying:Once(function()
		connection:Disconnect()
		if tween then
			tween:Cancel()
		end
	end)
	render()
end
return Wallet
