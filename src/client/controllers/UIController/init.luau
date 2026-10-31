-- UIController: finds the player's HUD and starts every screen module beneath this one,
-- passing the HUD down as `init(hud)`.
--
-- The HUD is authored in StarterGui (place file only) with ResetOnSpawn = false, so the
-- clone found here lives for the whole session and screens bind to it exactly once. If
-- that flag is ever flipped, every screen would be left holding a destroyed clone after
-- the first respawn -- hence the warning below rather than a silent rebind.
-- Expansion copies the untouched Sell shell before any screen changes its visual state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = require(ReplicatedStorage.Shared.ModuleLoader)
local Expansion = require(script.Expansion)

local UIController = {}

function UIController.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD")
	assert(hud:IsA("ScreenGui"), "PlayerGui.HUD must be a ScreenGui")
	if hud.ResetOnSpawn then
		warn("UIController: HUD.ResetOnSpawn is true; screens will lose their bindings on respawn")
	end
	Expansion.prepare(hud)
	ModuleLoader.startChildren(script, hud)
end

return UIController
