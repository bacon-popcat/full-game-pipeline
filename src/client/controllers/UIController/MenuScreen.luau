-- MenuScreen: the side Menu button (SideButtons.Menu) and the small popup it opens (HUD.Menu),
-- whose rows open the Achievements, Quests, Stats and Settings windows by name (Screens.open), so
-- this screen requires none of their controllers. The button's and the Quests row's `Badge` count
-- quests that are done and waiting to be claimed (ProgressClient).
local Players = game:GetService("Players")
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local HubWindow = require(Libraries.HubWindow)
local ProgressClient = require(Libraries.ProgressClient)
local Screens = require(Libraries.Screens)
local UI = require(Libraries.UI)

local ROWS = { "Achievements", "Quests", "Stats", "Settings" }

local MenuScreen = {}

local function paintBadge(badge: Instance?, count: number)
	if not badge or not badge:IsA("GuiObject") then
		return
	end
	badge.Visible = count > 0
	local text = badge:FindFirstChild("Count")
	if text and text:IsA("TextLabel") then
		text.Text = if count > 9 then "9+" else tostring(count)
	end
end

function MenuScreen.init(hud: ScreenGui)
	local opener = Hud.find(hud, "SideButtons.Menu", "TextButton")
	local window = HubWindow.bind(hud, "Menu", {}, function() end)
	if not opener or not window then
		return
	end
	local cleanups = {}
	table.insert(
		cleanups,
		UI.bindButton(opener, {
			hoverScale = 1.08,
			onActivate = function()
				if window.isOpen() then
					window.close()
				else
					window.open()
				end
			end,
		})
	)
	for _, name in ROWS do
		local row = Hud.find(hud, `Menu.Body.{name}`, "TextButton")
		if row then
			table.insert(
				cleanups,
				UI.bindButton(row, {
					hoverScale = 1.03,
					onActivate = function()
						-- Opening the target claims the screen, which closes this popup.
						if not Screens.open(name) then
							warn(`MenuScreen: no window named {name} can be opened`)
						end
					end,
				})
			)
		end
	end
	local questsRow = window.frame:FindFirstChild("Body")
	questsRow = if questsRow then questsRow:FindFirstChild("Quests") else nil
	local function paint()
		local count = ProgressClient.claimable()
		paintBadge(opener:FindFirstChild("Badge"), count)
		paintBadge(if questsRow then questsRow:FindFirstChild("Badge") else nil, count)
	end
	local changed = ProgressClient.changed:Connect(paint)
	paint()
	hud.Destroying:Once(function()
		changed:Disconnect()
		for _, cleanup in cleanups do
			cleanup()
		end
	end)
end

return MenuScreen
