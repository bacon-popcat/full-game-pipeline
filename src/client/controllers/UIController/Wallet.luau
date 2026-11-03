-- Wallet: binds the authored balance/level labels and eases XP from authoritative state. The
-- panel, its place in the bottom-left corner and the XP bar's authored "xp / needed" label
-- (XpBar.Text) are all in Scale, so it grows with the screen like the rest of the HUD. The balance
-- counts up or down to a new amount over COUNT_TIME instead of jumping, and a gain pops the
-- balance and floats a green "+amount" up from it. Reduced motion jumps straight to the amount
-- with no pop.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Economy = require(ReplicatedStorage.Shared.Economy)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local EconomyClient = require(Libraries.EconomyClient)
local Hud = require(Libraries.Hud)
local COUNT_TIME = 0.6
local COUNT_TWEEN = TweenInfo.new(COUNT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SETTLE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOAT_TWEEN = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_SCALE = 1.15
-- How far the "+amount" floats up, in heights of the balance label.
local FLOAT_RISE = 1.7
local GAIN_COLOR = Color3.fromRGB(120, 230, 120)

local Wallet = {}

function Wallet.init(hud: ScreenGui)
	local coins = Hud.find(hud, "Wallet.Coins", "TextLabel")
	local level = Hud.find(hud, "Wallet.Level", "TextLabel")
	local fill = Hud.find(hud, "Wallet.XpBar.Fill", "Frame")
	local progress = Hud.find(hud, "Wallet.XpBar.Text", "TextLabel")
	if
		not coins
		or not coins:IsA("TextLabel")
		or not level
		or not level:IsA("TextLabel")
		or not fill
		or not fill:IsA("Frame")
		or not progress
		or not progress:IsA("TextLabel")
	then
		return
	end
	-- The balance as shown, counted toward the real one.
	local shown = Instance.new("NumberValue")
	shown.Value = EconomyClient.get().coins
	local counting: Tween? = nil
	-- The last real balance, so a gain mid-count is measured from it, not from the shown number.
	local last = shown.Value
	shown.Changed:Connect(function(value: number)
		coins.Text = Hud.number(math.round(value))
	end)
	local pop = Instance.new("UIScale")
	pop.Parent = coins

	local function gained(amount: number)
		pop.Scale = 1
		local up = TweenService:Create(pop, POP_TWEEN, { Scale = POP_SCALE })
		up.Completed:Once(function()
			TweenService:Create(pop, SETTLE_TWEEN, { Scale = 1 }):Play()
		end)
		up:Play()
		local float = Instance.new("TextLabel")
		float.Name = "CoinGain"
		float.BackgroundTransparency = 1
		float.AnchorPoint = Vector2.new(0, 1)
		float.Position = UDim2.new(
			0,
			coins.AbsolutePosition.X - hud.AbsolutePosition.X,
			0,
			coins.AbsolutePosition.Y - hud.AbsolutePosition.Y
		)
		float.Size = UDim2.fromOffset(coins.AbsoluteSize.X, coins.AbsoluteSize.Y)
		float.Font = Enum.Font.GothamBold
		float.TextScaled = true
		float.TextXAlignment = Enum.TextXAlignment.Left
		float.TextColor3 = GAIN_COLOR
		float.TextStrokeTransparency = 0.3
		float.Text = `+{Hud.number(amount)}`
		float.ZIndex = 20
		float.Parent = hud
		local rise = TweenService:Create(float, FLOAT_TWEEN, {
			Position = float.Position - UDim2.fromOffset(0, coins.AbsoluteSize.Y * FLOAT_RISE),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		rise.Completed:Once(function()
			float:Destroy()
		end)
		rise:Play()
	end
	local baseline = fill.Size
	local tween: Tween? = nil
	local function render()
		local state = EconomyClient.get()
		local current, xp, needed = Economy.progress(state.xp)
		if counting then
			counting:Cancel()
			counting = nil
		end
		local before = last
		last = state.coins
		if GuiService.ReducedMotionEnabled then
			shown.Value = state.coins
			coins.Text = Hud.number(state.coins)
		elseif state.coins ~= shown.Value then
			local nextCount = TweenService:Create(shown, COUNT_TWEEN, { Value = state.coins })
			counting = nextCount
			nextCount:Play()
			if state.coins > before then
				gained(state.coins - before)
			end
		else
			coins.Text = Hud.number(state.coins)
		end
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
		if counting then
			counting:Cancel()
		end
		shown:Destroy()
	end)
	render()
end
return Wallet
