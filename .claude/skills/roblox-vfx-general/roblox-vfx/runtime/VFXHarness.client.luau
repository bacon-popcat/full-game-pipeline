-- LocalScript: StarterPlayer/StarterPlayerScripts/VFXHarness (Studio testing only)
-- A minimal test bench for the VFX runtime. Press Play in Studio, then:
--   1-9    play the Nth effect (alphabetical) at a target 12 studs in front of you
--   R      replay the last effect          L   loop it every 1.5 s (scaled)
--   [ / ]  slower / faster (0.1, 0.25, 0.5, 1x)
--   T      move the target in front of you
-- The effect list and current speed print to the Output. Change VFX_FOLDER if the runtime
-- lives somewhere other than ReplicatedStorage.VFX. Delete this script before shipping.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return
end

local VFX_FOLDER = ReplicatedStorage:WaitForChild("VFX")
local VFXPlayer = require(VFX_FOLDER:WaitForChild("VFXPlayer"))

local SPEEDS = { 0.1, 0.25, 0.5, 1 }
local speedIndex = #SPEEDS
local looping = false
local last

local names = {}
for _, module in VFX_FOLDER:WaitForChild("Effects"):GetChildren() do
	if module:IsA("ModuleScript") then
		table.insert(names, module.Name)
	end
end
table.sort(names)
for i, name in names do
	print(("VFXHarness: [%d] %s"):format(i, name))
end

local target = Instance.new("Part")
target.Name = "VFXTarget"
target.Anchored = true
target.CanCollide = false
target.Transparency = 0.8
target.Size = Vector3.new(2, 5, 1)
target.Parent = workspace

local function moveTarget()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local pos = root.Position + flat.Unit * 12
		-- face the player, so effects' LookVector points at the viewer
		target.CFrame = CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z))
	end
end

local function play(name)
	last = name
	VFXPlayer.TimeScale = SPEEDS[speedIndex]
	VFXPlayer.Play(name, target.CFrame)
end

Players.LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	moveTarget()
end)
task.defer(moveTarget)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local key = input.KeyCode
	local digit = key.Value - Enum.KeyCode.One.Value + 1
	if digit >= 1 and digit <= 9 and names[digit] then
		play(names[digit])
	elseif key == Enum.KeyCode.R and last then
		play(last)
	elseif key == Enum.KeyCode.L then
		looping = not looping
		print("VFXHarness: loop", looping)
	elseif key == Enum.KeyCode.LeftBracket or key == Enum.KeyCode.RightBracket then
		speedIndex = math.clamp(speedIndex + (key == Enum.KeyCode.RightBracket and 1 or -1), 1, #SPEEDS)
		print("VFXHarness: speed", SPEEDS[speedIndex])
	elseif key == Enum.KeyCode.T then
		moveTarget()
	end
end)

task.spawn(function()
	while true do
		task.wait(1.5 / SPEEDS[speedIndex])
		if looping and last then
			play(last)
		end
	end
end)
