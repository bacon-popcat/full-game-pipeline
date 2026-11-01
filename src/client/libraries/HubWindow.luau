-- HubWindow: authored stall windows share modal selection, pop, close, prompt and reach
-- lifecycle. Screens arbitrates Backpack/MachinePanel/Shop/Sell; each screen owns content.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Hub = require(ReplicatedStorage.Shared.Hub)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Controls = require(script.Parent.Controls)
local Hud = require(script.Parent.Hud)
local Screens = require(script.Parent.Screens)
local UI = require(script.Parent.UI)
local PopupMotion = require(script.Parent.PopupMotion)
local HubWindow = {}
export type Window = { open: () -> (), close: () -> (), frame: Frame }

-- `stalls` are the hub stalls whose prompts open this window; `onOpen` hears which one did,
-- before `render`, and the window closes when you walk away from that stall.
function HubWindow.bind(
	hud: ScreenGui,
	name: string,
	stalls: { string },
	render: () -> (),
	onOpen: ((stall: string) -> ())?
): Window?
	local frame = Hud.find(hud, name, "Frame")
	local scale = Hud.find(hud, name .. ".UIScale", "UIScale")
	local closeButton = Hud.find(hud, name .. ".Header.Close", "TextButton")
	if
		not frame
		or not frame:IsA("Frame")
		or not scale
		or not scale:IsA("UIScale")
		or not closeButton
		or not closeButton:IsA("TextButton")
	then
		return nil
	end
	local trove = Trove.new()
	local animateWindow, cleanup = PopupMotion.bind(frame)
	trove:Add(cleanup)
	local opened = false
	local prior: GuiObject? = nil
	local action = name .. "Back"
	local stall = stalls[1]
	frame.Visible = false
	frame.SelectionGroup = true
	frame.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	frame.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local function close()
		if not opened then
			return
		end
		opened = false
		animateWindow(false)
		ContextActionService:UnbindAction(action)
		local current = GuiService.SelectedObject
		if current and current:IsDescendantOf(frame) then
			GuiService.SelectedObject = if prior and prior.Parent and prior.Visible then prior else nil
		end
		prior = nil
	end
	local function focus()
		if opened and UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			GuiService.SelectedObject = closeButton
		end
	end
	local function open(opener: string)
		if not Hub.inReach(Players.LocalPlayer, opener) or Players.LocalPlayer:GetAttribute("DataReady") ~= true then
			return
		end
		Screens.claim(name)
		local switching = opener ~= stall
		stall = opener
		if onOpen then
			onOpen(opener)
		end
		if opened then
			if switching then
				render()
			end
			return
		end
		prior = GuiService.SelectedObject
		opened = true
		animateWindow(true)
		render()
		ContextActionService:BindActionAtPriority(action, function(_: string, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(Controls.BACK))
		task.spawn(function()
			RunService.RenderStepped:Wait()
			focus()
		end)
	end
	Screens.register(name, close)
	trove:Add(UI.bindButton(closeButton, { onActivate = close }))
	trove:Connect(ProximityPromptService.PromptTriggered, function(prompt: ProximityPrompt)
		local counter = prompt.Parent
		local model = if counter then counter.Parent else nil
		local hub = workspace:FindFirstChild("Hub")
		if model and table.find(stalls, model.Name) and model.Parent == hub and prompt.Name == "Prompt" then
			open(model.Name)
		end
	end)
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), focus)
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt: number)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		if
			opened
			and (Players.LocalPlayer:GetAttribute("DataReady") ~= true or not Hub.inReach(Players.LocalPlayer, stall))
		then
			close()
		end
	end)
	trove:Connect(hud.Destroying, function()
		close()
		trove:Destroy()
	end)
	return {
		open = function()
			open(stall)
		end,
		close = close,
		frame = frame,
	}
end
return HubWindow
