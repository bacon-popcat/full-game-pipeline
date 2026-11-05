-- Toasts: the notices Remotes.Notify sends, stacked just above the hotbar (over the held item's
-- name), newest nearest the hotbar, each in its kind's colour (Shared/Notices). At most MAX show;
-- each fades after LIFETIME seconds.
--
-- HUD.Toasts is the authored holder (its UIListLayout stacks from the bottom) and
-- Assets.UI.Toast.Toast the authored card: a TextLabel whose text and `Border` UIStroke take the
-- kind's colour. The holder keeps its authored size but follows HUD.ItemName, which
-- InventoryScreen moves with the hotbar, so the stack never covers the slots at any screen size.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Notices = require(ReplicatedStorage.Shared.Notices)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)

local MAX = 4
local LIFETIME = 3
-- Pixels at the reference size between the item name's top and the lowest toast.
local GAP = 4

local Toasts = {}

function Toasts.init(hud: ScreenGui)
	local holder = Hud.find(hud, "Toasts", "Frame")
	local itemName = Hud.find(hud, "ItemName", "TextLabel")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Toast.Toast", "TextLabel")
	if not holder or not holder:IsA("Frame") or not itemName or not itemName:IsA("TextLabel") then
		return
	end
	if not template or not template:IsA("TextLabel") then
		return
	end
	holder.AnchorPoint = Vector2.new(0.5, 1)

	local function follow()
		local zoom = Hud.zoom(hud.AbsoluteSize)
		local top = itemName.AbsolutePosition.Y - hud.AbsolutePosition.Y
		holder.Position = UDim2.new(0.5, 0, 0, top - GAP * zoom)
	end
	local followed = {
		itemName:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow),
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow),
	}
	follow()

	local active: { TextLabel } = {}
	local order = 0
	local connection = Remotes.Notify.OnClientEvent:Connect(function(message: string, kind: unknown)
		while #active >= MAX do
			local old = table.remove(active, 1)
			if old then
				old:Destroy()
			end
		end
		local color = Notices.color(if Notices.isKind(kind) then kind :: Notices.Kind else Notices.DEFAULT)
		local label = template:Clone()
		order += 1
		label.LayoutOrder = order
		label.Text = message
		label.TextColor3 = color
		local border = label:FindFirstChild("Border")
		if border and border:IsA("UIStroke") then
			border.Color = color
		end
		label.Visible = true
		label.Parent = holder
		local scale = label:FindFirstChildOfClass("UIScale")
		local baseline = if scale then scale.Scale else 1
		if scale and not GuiService.ReducedMotionEnabled then
			scale.Scale = baseline * 0.9
			TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back), { Scale = baseline }):Play()
		end
		table.insert(active, label)
		task.delay(LIFETIME, function()
			if not label.Parent then
				return
			end
			local fade = TweenInfo.new(0.25, Enum.EasingStyle.Quad)
			local tween = TweenService:Create(
				label,
				fade,
				{ TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
			)
			for _, stroke in label:GetChildren() do
				if stroke:IsA("UIStroke") then
					TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
				end
			end
			if scale and not GuiService.ReducedMotionEnabled then
				TweenService:Create(scale, fade, { Scale = baseline * 0.94 }):Play()
			end
			tween:Play()
			tween.Completed:Once(function()
				local index = table.find(active, label)
				if index then
					table.remove(active, index)
				end
				label:Destroy()
			end)
		end)
	end)
	hud.Destroying:Once(function()
		connection:Disconnect()
		for _, each in followed do
			each:Disconnect()
		end
		for _, label in active do
			label:Destroy()
		end
		table.clear(active)
	end)
end
return Toasts
