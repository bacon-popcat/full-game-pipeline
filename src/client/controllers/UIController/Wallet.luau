-- Wallet: binds the authored balance/level labels and eases XP from authoritative state. It sits
-- in the bottom-left corner, and the XP bar reads "xp / needed" for the current level: an
-- authored XpBar.Text label, or a plain one made here until the place has it.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
-- Pixels between the wallet and the screen's bottom-left corner.
local MARGIN = 16

local Wallet = {}

-- The XP bar's "xp / needed" label: authored, or a plain one laid over the bar.
local function xpLabel(bar: Instance): TextLabel
	local found = bar:FindFirstChild("Text")
	if found and found:IsA("TextLabel") then
		return found
	end
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 10
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	label.Parent = bar
	return label
end
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
	local wallet = coins.Parent
	if wallet and wallet:IsA("GuiObject") then
		wallet.AnchorPoint = Vector2.new(0, 1)
		wallet.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
	end
	local progress = xpLabel(fill.Parent :: Instance)
	local baseline = fill.Size
	local tween: Tween? = nil
	local function render()
		local state = EconomyClient.get()
		local current, xp, needed = Economy.progress(state.xp)
		coins.Text = Hud.number(state.coins)
		level.Text = `Lv {current}`
		progress.Text = `{Hud.number(xp)} / {Hud.number(needed)} XP`
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
