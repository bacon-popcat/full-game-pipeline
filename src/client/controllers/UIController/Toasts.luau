-- Toasts: at most four template clones; each expires after 2.5 seconds and fades calmly.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(Players.LocalPlayer.PlayerScripts.Libraries.Hud)
local Toasts = {}
function Toasts.init(hud: ScreenGui)
	local holder = Hud.find(hud, "Toasts", "Frame")
	local template = Hud.find(ReplicatedStorage, "Assets.UI.Toast.Toast", "TextLabel")
	if not holder or not template or not template:IsA("TextLabel") then
		return
	end
	local active: { TextLabel } = {}
	local order = 0
	local connection = Remotes.Notify.OnClientEvent:Connect(function(message: string)
		while #active >= 4 do
			local old = table.remove(active, 1)
			if old then
				old:Destroy()
			end
		end
		local label = template:Clone()
		order += 1
		label.LayoutOrder = order
		label.Text = message
		label.Visible = true
		label.Parent = holder
		table.insert(active, label)
		task.delay(2.5, function()
			if not label.Parent then
				return
			end
			local tween = TweenService:Create(
				label,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad),
				{ TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }
			)
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
		for _, label in active do
			label:Destroy()
		end
		table.clear(active)
	end)
end
return Toasts
