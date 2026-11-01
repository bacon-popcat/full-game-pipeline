-- Settings: binds the authored side button and session music toggle. Screens owns window
-- exclusivity; AudioSettings owns audio state independently of this screen's lifecycle.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = script.Parent.Parent.Parent.Libraries
local AudioSettings = require(Libraries.AudioSettings)
local Controls = require(Libraries.Controls)
local Hud = require(Libraries.Hud)
local Screens = require(Libraries.Screens)
local UI = require(Libraries.UI)
local PopupMotion = require(Libraries.PopupMotion)
local Settings = {}

function Settings.init(hud: ScreenGui)
	local frame = Hud.find(hud, "Settings", "Frame")
	local opener = Hud.find(hud, "SideButtons.Settings", "TextButton")
	local closeButton = Hud.find(hud, "Settings.Header.Close", "TextButton")
	local music = Hud.find(hud, "Settings.Body.Music", "TextButton")
	local label = Hud.find(hud, "Settings.Body.Music.Label", "TextLabel")
	local controlsHint = Hud.find(hud, "Settings.Body.ControlsHint", "TextLabel")
	if not frame or not opener or not closeButton or not music or not label then
		return
	end
	local trove = Trove.new()
	local prior: GuiObject? = nil
	local animateWindow, cleanup = PopupMotion.bind(frame)
	trove:Add(cleanup)
	local opened = false
	local function render()
		label.Text = if AudioSettings.musicEnabled() then "Music: On" else "Music: Off"
		if controlsHint and controlsHint:IsA("TextLabel") then
			local input = UserInputService.PreferredInput
			controlsHint.Text = if input == Enum.PreferredInput.Touch
				then "Tap the side buttons to open menus."
				elseif input == Enum.PreferredInput.Gamepad then "Y  Inventory   •   D-pad up  Interact"
				else `{Controls.TOGGLE_BACKPACK[1].Name}  Inventory   •   {Controls.INTERACT[1].Name}  Interact\n{Controls.ROTATE[1].Name}  Rotate   •   {Controls.DROP[1].Name}  Drop`
		end
	end
	local function close()
		opened = false
		animateWindow(false)
		ContextActionService:UnbindAction("SettingsBack")
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(frame) then
			GuiService.SelectedObject = if prior and prior.Parent and prior.Visible then prior else nil
		end
		prior = nil
	end
	local function focus()
		render()
		if opened and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			GuiService.SelectedObject = music
		end
	end
	Screens.register("Settings", close)
	trove:Add(UI.bindButton(opener, {
		hoverScale = 1.08,
		onActivate = function()
			if opened then
				close()
				return
			end
			Screens.claim("Settings")
			prior = GuiService.SelectedObject
			opened = true
			animateWindow(true)
			render()
			focus()
			ContextActionService:BindActionAtPriority("SettingsBack", function(_, state)
				if state == Enum.UserInputState.Begin then
					close()
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, table.unpack(Controls.BACK))
		end,
	}))
	trove:Add(UI.bindButton(closeButton, { onActivate = close }))
	trove:Add(UI.bindButton(music, {
		onActivate = function()
			AudioSettings.setMusicEnabled(not AudioSettings.musicEnabled())
			render()
		end,
	}))
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), focus)
	trove:Connect(hud.Destroying, function()
		close()
		trove:Destroy()
	end)
	render()
end

return Settings
