-- MenuScreen: the side Menu button (SideButtons.Menu) and the small popup it opens (HUD.Menu),
-- whose rows open the Index, Achievements, Stats and Settings windows by name (Screens.open), so
-- this screen requires none of their controllers. Quests owns its own side button and badge.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local Screens = require(Libraries.Screens)
local UI = require(Libraries.UI)

local ROWS = { "Index", "Achievements", "Stats", "Settings" }

local MenuScreen = {}

function MenuScreen.init(hud: ScreenGui)
	local opener = Hud.find(hud, "SideButtons.Menu", "TextButton")
	local window = HubWindow.bind(hud, "Menu", {}, function() end)
	if not opener or not window then
		return
	end
	local trove = Trove.new()
	-- Hide the old authored badge until the place-file builder has been rerun.
	local badge = opener:FindFirstChild("Badge")
	if badge and badge:IsA("GuiObject") then
		badge.Visible = false
	end
	trove:Add(UI.bindButton(opener, {
		hoverScale = 1.08,
		onActivate = function()
			if window.isOpen() then
				window.close()
			else
				window.open()
			end
		end,
	}))
	for _, name in ROWS do
		local row = Hud.find(hud, `Menu.Body.{name}`, "TextButton")
		if row then
			trove:Add(UI.bindButton(row, {
				hoverScale = 1.03,
				onActivate = function()
					-- Opening the target claims the screen, which closes this popup.
					if not Screens.open(name) then
						warn(`MenuScreen: no window named {name} can be opened`)
					end
				end,
			}))
		end
	end
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return MenuScreen
