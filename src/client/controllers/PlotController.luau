-- PlotController: this player's view of their own garden's locked sections. PlotService builds
-- every garden's ground with each locked tile's Price and whether it is Buyable now, and its
-- BuySection prompts disabled; on the local player's own garden only, this writes each price on
-- its tile (bright when it can be bought, dimmed when not) and enables the prompts, so nobody
-- else sees either. Holding a prompt asks the server to buy that section
-- (Remotes.PlotBuySection), which checks everything again.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlotController = {}

local player = Players.LocalPlayer

local PRICE_TEXT = Color3.fromRGB(246, 238, 214)

-- The garden model an instance stands in, if it is the local player's.
local function ownGarden(instance: Instance): Model?
	local plots = workspace:FindFirstChild("Plots")
	local garden: Instance? = instance
	while garden and garden.Parent ~= plots do
		garden = garden.Parent
	end
	return if garden and garden:IsA("Model") and garden:GetAttribute("Owner") == player.UserId then garden else nil
end

-- 2500 -> "2,500".
local function commas(amount: number): string
	local text = tostring(amount)
	while true do
		local spaced, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		text = spaced
		if count == 0 then
			return text
		end
	end
end

local function label(parent: Instance, name: string, text: string, font: Enum.Font, fade: number): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = name
	textLabel.BackgroundTransparency = 1
	textLabel.Font = font
	textLabel.TextScaled = true
	textLabel.TextColor3 = PRICE_TEXT
	textLabel.TextTransparency = fade
	textLabel.Text = text
	textLabel.Parent = parent
	return textLabel
end

-- A locked section's price, lying face up on its ground tile.
local function price(tile: BasePart, coins: number, buyable: boolean)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Price"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 12
	gui.LightInfluence = 0.6
	gui.MaxDistance = 400
	local fade = if buyable then 0.05 else 0.6
	local amount = label(gui, "Amount", commas(coins), Enum.Font.GothamBold, fade)
	amount.AnchorPoint = Vector2.new(0.5, 1)
	amount.Position = UDim2.fromScale(0.5, 0.58)
	amount.Size = UDim2.fromScale(0.9, 0.28)
	local unit = label(gui, "Unit", "coins", Enum.Font.GothamMedium, fade)
	unit.AnchorPoint = Vector2.new(0.5, 0)
	unit.Position = UDim2.fromScale(0.5, 0.6)
	unit.Size = UDim2.fromScale(0.5, 0.11)
	gui.Parent = tile
end

local function show(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Name == "BuySection" then
		instance.Enabled = ownGarden(instance) ~= nil
	elseif instance:IsA("BasePart") and instance.Name == "LockedLand" then
		local coins = instance:GetAttribute("Price")
		if typeof(coins) == "number" and ownGarden(instance) and not instance:FindFirstChild("Price") then
			price(instance, coins, instance:GetAttribute("Buyable") == true)
		end
	end
end

function PlotController.init()
	local plots = workspace:WaitForChild("Plots")
	for _, descendant in plots:GetDescendants() do
		show(descendant)
	end
	plots.DescendantAdded:Connect(show)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "BuySection" or not ownGarden(prompt) then
			return
		end
		local x, z = prompt:GetAttribute("SectionX"), prompt:GetAttribute("SectionZ")
		if typeof(x) == "number" and typeof(z) == "number" then
			Remotes.PlotBuySection:FireServer(x, z)
		end
	end)
end

return PlotController
