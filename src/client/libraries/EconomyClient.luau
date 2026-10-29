--!strict
-- EconomyClient: the latest authoritative wallet. Replicated player attributes provide
-- the initial snapshot even if EconomySync arrived before the HUD finished binding.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyClient = {}
EconomyClient.changed = Signal.new()
local player = Players.LocalPlayer
local state = { coins = 0, xp = 0, level = 1 }

local function refresh()
	for key, attribute in { coins = "Coins", xp = "Xp", level = "Level" } do
		local value = player:GetAttribute(attribute)
		if typeof(value) == "number" then
			state[key] = value
		end
	end
	EconomyClient.changed:Fire()
end
for _, attribute in { "Coins", "Xp", "Level" } do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
Remotes.EconomySync.OnClientEvent:Connect(function(snapshot: { coins: number, xp: number, level: number })
	state = snapshot
	EconomyClient.changed:Fire()
end)
refresh()
function EconomyClient.get(): { coins: number, xp: number, level: number }
	return table.clone(state)
end
return EconomyClient
