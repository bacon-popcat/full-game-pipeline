--!strict
-- ItemGained: a small card in the bottom-right corner for each item the player gains,
-- with its icon and "+count Name". A repeat gain of an item still on screen adds to that
-- card instead of stacking a new one. At most MAX_CARDS show; each fades after LIFETIME.
-- Built in code; the place has no template for it. Like the authored HUD it is in Scale: the
-- holder is a share of the reference screen (Hud.REFERENCE_WIDTH x REFERENCE_HEIGHT) with its
-- shape kept by a UIAspectRatioConstraint, and the cards are shares of the holder.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local InventoryClient = require(Libraries.InventoryClient)
local ItemIcon = require(Libraries.ItemIcon)

-- Pixels from the screen's bottom-right corner, clear of the hotbar's sides.
local MARGIN = 16
-- A card's size, its gap and its text, in pixels at Hud.REFERENCE_HEIGHT.
local CARD_WIDTH = 220
local CARD_HEIGHT = 48
local CARD_GAP = 6
local TEXT_SIZE = 16
local MAX_CARDS = 4
local HOLDER_HEIGHT = (CARD_HEIGHT + CARD_GAP) * MAX_CARDS
local LIFETIME = 3
local IN_TWEEN = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Card = { frame: Frame, label: TextLabel, scale: UIScale, itemId: string, count: number, expires: number }

local ItemGained = {}

function ItemGained.init(hud: ScreenGui)
	local holder = Instance.new("Frame")
	holder.Name = "ItemGained"
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	holder.Size = UDim2.fromScale(CARD_WIDTH / Hud.REFERENCE_WIDTH, HOLDER_HEIGHT / Hud.REFERENCE_HEIGHT)
	holder.BackgroundTransparency = 1
	holder.Parent = hud
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(CARD_GAP / HOLDER_HEIGHT, 0)
	layout.Parent = holder
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = CARD_WIDTH / HOLDER_HEIGHT
	shape.Parent = holder

	local cards: { Card } = {}
	local order = 0

	local function remove(card: Card)
		local index = table.find(cards, card)
		if not index then
			return
		end
		table.remove(cards, index)
		if GuiService.ReducedMotionEnabled then
			card.frame:Destroy()
			return
		end
		local tween = TweenService:Create(card.scale, OUT_TWEEN, { Scale = 0 })
		tween:Play()
		tween.Completed:Once(function()
			card.frame:Destroy()
		end)
	end

	local function expireLater(card: Card)
		local expires = card.expires
		task.delay(LIFETIME, function()
			if card.expires == expires then
				remove(card)
			end
		end)
	end

	local function render(card: Card)
		local item = Inventory.find(card.itemId)
		card.label.Text = `+{card.count} {if item then item.name else card.itemId}`
	end

	local function pop(card: Card)
		if GuiService.ReducedMotionEnabled then
			card.scale.Scale = 1
			return
		end
		card.scale.Scale = 0.85
		TweenService:Create(card.scale, IN_TWEEN, { Scale = 1 }):Play()
	end

	local connection = InventoryClient.gained:Connect(function(itemId: string, count: number)
		for _, card in cards do
			if card.itemId == itemId then
				card.count += count
				card.expires = os.clock()
				render(card)
				pop(card)
				expireLater(card)
				return
			end
		end
		while #cards >= MAX_CARDS do
			remove(cards[1])
		end

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, CARD_HEIGHT / HOLDER_HEIGHT)
		frame.BackgroundColor3 = Color3.fromRGB(20, 24, 22)
		frame.BackgroundTransparency = 0.35
		order += 1
		frame.LayoutOrder = order
		Instance.new("UICorner").Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.8
		stroke.Parent = frame
		local scale = Instance.new("UIScale")
		scale.Parent = frame

		local viewport = Instance.new("ViewportFrame")
		viewport.BackgroundTransparency = 1
		viewport.Position = UDim2.fromScale(4 / CARD_WIDTH, 4 / CARD_HEIGHT)
		viewport.Size = UDim2.fromScale((CARD_HEIGHT - 8) / CARD_WIDTH, (CARD_HEIGHT - 8) / CARD_HEIGHT)
		viewport.Parent = frame
		ItemIcon.show(viewport, itemId)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		-- The box is the text's height, so TextScaled draws it at TEXT_SIZE at the reference height.
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.Position = UDim2.fromScale((CARD_HEIGHT + 2) / CARD_WIDTH, 0.5)
		label.Size = UDim2.fromScale(1 - (CARD_HEIGHT + 10) / CARD_WIDTH, TEXT_SIZE / CARD_HEIGHT)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Parent = frame

		local card: Card =
			{ frame = frame, label = label, scale = scale, itemId = itemId, count = count, expires = os.clock() }
		frame.Destroying:Once(function()
			ItemIcon.clear(viewport)
		end)
		render(card)
		frame.Parent = holder
		table.insert(cards, card)
		pop(card)
		expireLater(card)
	end)

	hud.Destroying:Once(function()
		connection:Disconnect()
		holder:Destroy()
	end)
end

return ItemGained
