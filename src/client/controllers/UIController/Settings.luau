-- Settings: binds the authored side button and the session music and sound-effect volumes.
-- Each volume row (Body.MusicVolume, Body.SfxVolume) has a Track to click or drag and a Value
-- box to type 0-100 into; both stay in step. Body.LightingQuality has one button per
-- Shared/Settings lighting quality (Low, Medium, High), each with a Selected child shown on the
-- current one; a press applies the preset at once (libraries/Lighting) and asks SettingsService
-- to save it. Screens owns window exclusivity; AudioSettings owns audio state independently of
-- this screen's lifecycle. Body.SaveQuit saves the garden and goes back to the save menu
-- (SaveMenuController).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameSettings = require(ReplicatedStorage.Shared.Settings)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = script.Parent.Parent.Parent.Libraries
local AudioSettings = require(Libraries.AudioSettings)
local Controls = require(Libraries.Controls)
local Hud = require(Libraries.Hud)
local Lighting = require(Libraries.Lighting)
local Screens = require(Libraries.Screens)
local UI = require(Libraries.UI)
local PopupMotion = require(Libraries.PopupMotion)
local Settings = {}

function Settings.init(hud: ScreenGui)
	local frame = Hud.find(hud, "Settings", "Frame")
	local opener = Hud.find(hud, "SideButtons.Settings", "TextButton")
	local closeButton = Hud.find(hud, "Settings.Header.Close", "TextButton")
	local controlsHint = Hud.find(hud, "Settings.Body.ControlsHint", "TextLabel")
	if not frame or not opener or not closeButton then
		return
	end
	local volumes = {
		{
			path = "Settings.Body.MusicVolume",
			get = AudioSettings.musicVolume,
			set = AudioSettings.setMusicVolume,
		},
		{
			path = "Settings.Body.SfxVolume",
			get = AudioSettings.sfxVolume,
			set = AudioSettings.setSfxVolume,
		},
	}
	type Slider = {
		track: GuiButton,
		fill: GuiObject,
		knob: GuiObject,
		box: TextBox,
		get: () -> number,
		set: (number) -> (),
	}
	local sliders: { Slider } = {}
	for _, volume in volumes do
		local track = Hud.find(hud, volume.path .. ".Track", "GuiButton")
		local fill = Hud.find(hud, volume.path .. ".Track.Fill", "GuiObject")
		local knob = Hud.find(hud, volume.path .. ".Track.Knob", "GuiObject")
		local box = Hud.find(hud, volume.path .. ".Value", "TextBox")
		if
			track
			and track:IsA("GuiButton")
			and fill
			and fill:IsA("GuiObject")
			and knob
			and knob:IsA("GuiObject")
			and box
			and box:IsA("TextBox")
		then
			table.insert(
				sliders,
				{ track = track, fill = fill, knob = knob, box = box, get = volume.get, set = volume.set }
			)
		end
	end
	type Choice = { quality: string, button: GuiButton, selected: GuiObject? }
	local choices: { Choice } = {}
	for _, quality in GameSettings.LIGHTING_QUALITIES do
		local button = Hud.find(hud, `Settings.Body.LightingQuality.{quality}`, "GuiButton")
		if button and button:IsA("GuiButton") then
			local selected = button:FindFirstChild("Selected")
			table.insert(choices, {
				quality = quality,
				button = button,
				selected = if selected and selected:IsA("GuiObject") then selected else nil,
			})
		end
	end
	local music: GuiObject? = if sliders[1] then sliders[1].track else nil
	local trove = Trove.new()
	local prior: GuiObject? = nil
	local animateWindow, cleanup = PopupMotion.bind(frame, true)
	trove:Add(cleanup)
	local opened = false
	local function render()
		for _, slider in sliders do
			local value = slider.get()
			slider.fill.Size = UDim2.fromScale(value, 1)
			slider.knob.Position = UDim2.fromScale(value, 0.5)
			if not slider.box:IsFocused() then
				slider.box.Text = tostring(math.round(value * 100))
			end
		end
		for _, choice in choices do
			if choice.selected then
				choice.selected.Visible = choice.quality == Lighting.quality()
			end
		end
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
	local saveQuit = Hud.find(hud, "Settings.Body.SaveQuit", "TextButton")
	if saveQuit then
		trove:Add(UI.bindButton(saveQuit, {
			onActivate = function()
				close()
				Remotes.SaveMenu:FireServer("Quit")
			end,
		}))
	end
	for _, choice in choices do
		trove:Add(UI.bindButton(choice.button, {
			onActivate = function()
				Lighting.setQuality(choice.quality)
				Remotes.Settings:FireServer("LightingQuality", choice.quality)
				render()
			end,
		}))
	end
	-- The saved quality can arrive while the window is open (LightingController applies it).
	trove:Connect(Players.LocalPlayer:GetAttributeChangedSignal("LightingQuality"), function()
		task.defer(render)
	end)
	local dragging: Slider? = nil
	local function slideTo(slider: Slider, x: number)
		local width = slider.track.AbsoluteSize.X
		if width > 0 then
			slider.set(math.clamp((x - slider.track.AbsolutePosition.X) / width, 0, 1))
			render()
		end
	end
	for _, slider in sliders do
		trove:Connect(slider.track.InputBegan, function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = slider
				slideTo(slider, input.Position.X)
			elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.DPadRight then
				local step = if input.KeyCode == Enum.KeyCode.DPadLeft then -0.1 else 0.1
				slider.set(slider.get() + step)
				render()
			end
		end)
		trove:Connect(slider.box.FocusLost, function()
			local typed = tonumber(string.match(slider.box.Text, "%-?%d+%.?%d*") or "")
			if typed then
				slider.set(math.clamp(typed, 0, 100) / 100)
			end
			render()
		end)
	end
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			slideTo(dragging, input.Position.X)
		end
	end)
	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = nil
		end
	end)
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), focus)
	trove:Connect(hud.Destroying, function()
		close()
		trove:Destroy()
	end)
	render()
end

return Settings
