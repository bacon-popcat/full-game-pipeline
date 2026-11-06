-- MusicPlayer: a small sidebar-style music button (white double note) under the day clock at
-- the top right, and the bracketed card it opens to its left: the playing track's name,
-- Pause/Play and Next. It drives MusicController (pause, resume, skip) and reads the Music Sound's `Track` and `Paused` attributes. Built
-- here, like DayClock, so it needs nothing in the place file.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage.Packages.Trove)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local UI = require(Libraries.UI)
local MusicController = require(script.Parent.Parent.MusicController)

local Panel = require(script.Parent.Panel)

local FONT = Panel.FONT
local EDGE = Panel.EDGE
-- The white double note (assets/ui/MusicNote.png).
local NOTE_IMAGE = "rbxassetid://131704354197300"
local WHITE = Color3.new(1, 1, 1)
local BUTTON = 40

local MusicPlayer = {}

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, colour: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.ZIndex = if parent:IsA("GuiObject") then parent.ZIndex + 1 else 1
	f.Parent = parent
	return f
end

local function round(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
end

local function text(parent: GuiObject, name: string, size: UDim2, position: UDim2, textSize: number, colour: Color3)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.FontFace = FONT
	label.TextSize = textSize
	label.TextColor3 = colour
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = parent.ZIndex + 1
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = label
	return label
end

local function pill(parent: GuiObject, name: string, label: string, position: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = position
	button.Size = UDim2.new(0.5, -16, 0, 30)
	button.FontFace = FONT
	button.TextSize = 15
	button.TextColor3 = WHITE
	button.Text = label
	button.ZIndex = parent.ZIndex + 1
	button.Parent = parent
	Panel.apply(button, 5, 1)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	return button
end

-- The white double note image, centred on the button.
local function doubleNote(parent: GuiObject)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.6, 0.6)
	icon.BackgroundTransparency = 1
	icon.Image = NOTE_IMAGE
	icon.ZIndex = parent.ZIndex + 1
	icon.Parent = parent
	return icon
end

function MusicPlayer.init(hud: ScreenGui)
	-- The button: a smaller sidebar button under the day clock.
	local opener = Instance.new("TextButton")
	opener.Name = "MusicButton"
	opener.AutoButtonColor = false
	opener.Text = ""
	opener.AnchorPoint = Vector2.new(1, 0)
	opener.Position = UDim2.new(1, -12, 0, 76)
	opener.Size = UDim2.fromOffset(BUTTON, BUTTON)
	opener.ZIndex = 5
	opener.Parent = hud
	Panel.apply(opener, 6, 2)
	Instance.new("UIScale").Parent = opener
	doubleNote(opener)
	-- A slash across the notes while the music is paused.
	local slash = frame(opener, "Slash", UDim2.fromOffset(3, 30), UDim2.fromScale(0.5, 0.5), WHITE)
	slash.Rotation = 45
	slash.ZIndex = opener.ZIndex + 3
	slash.Visible = false

	-- The card it opens, to the left of the button.
	local card = Instance.new("Frame")
	card.Name = "MusicCard"
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.new(1, -12 - BUTTON - 8, 0, 76)
	card.Size = UDim2.fromOffset(220, 100)
	card.Visible = false
	card.ZIndex = 30
	card.Parent = hud
	Panel.apply(card, 10, 2)
	local heading = text(card, "Heading", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 10), 13, EDGE)
	heading.Text = "NOW PLAYING"
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local track = text(card, "Track", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 26), 19, WHITE)
	track.TextXAlignment = Enum.TextXAlignment.Left
	local toggle = pill(card, "Toggle", "PAUSE", UDim2.new(0.25, 2, 0, 58))
	local skip = pill(card, "Next", "NEXT", UDim2.new(0.75, -2, 0, 58))

	local trove = Trove.new()
	local function render()
		local paused = MusicController.isPaused()
		local music = SoundService:FindFirstChild("Music")
		local name = if music then music:GetAttribute("Track") else nil
		track.Text = if typeof(name) == "string" and name ~= "" then name else "Between tracks"
		toggle.Text = if paused then "PLAY" else "PAUSE"
		slash.Visible = paused
	end
	trove:Add(UI.bindButton(opener, {
		hoverScale = 1.08,
		onActivate = function()
			card.Visible = not card.Visible
			render()
		end,
	}))
	trove:Add(UI.bindButton(toggle, {
		hoverScale = 1.04,
		onActivate = function()
			MusicController.setPaused(not MusicController.isPaused())
			render()
		end,
	}))
	trove:Add(UI.bindButton(skip, {
		hoverScale = 1.04,
		onActivate = function()
			MusicController.skip()
			render()
		end,
	}))
	task.spawn(function()
		local music = SoundService:WaitForChild("Music", 30)
		if not music then
			return
		end
		trove:Connect(music:GetAttributeChangedSignal("Track"), render)
		trove:Connect(music:GetAttributeChangedSignal("Paused"), render)
		render()
	end)
	render()
	trove:Connect(hud.Destroying, function()
		trove:Destroy()
	end)
end

return MusicPlayer
