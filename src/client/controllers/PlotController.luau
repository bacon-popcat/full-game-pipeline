-- PlotController: shows this player the BuySection prompts on their own garden (PlotService
-- builds them disabled, so nobody else sees them) and asks the server to buy the section when
-- one is held (Remotes.PlotBuySection). The server checks everything again.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlotController = {}

local player = Players.LocalPlayer

-- The garden model a prompt stands in, if it is the local player's.
local function ownGarden(prompt: ProximityPrompt): Model?
	local plots = workspace:FindFirstChild("Plots")
	local garden: Instance? = prompt
	while garden and garden.Parent ~= plots do
		garden = garden.Parent
	end
	return if garden and garden:IsA("Model") and garden:GetAttribute("Owner") == player.UserId then garden else nil
end

local function show(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance.Name == "BuySection" then
		instance.Enabled = ownGarden(instance) ~= nil
	end
end

function PlotController.init()
	local plots = workspace:WaitForChild("Plots")
	for _, descendant in plots:GetDescendants() do
		show(descendant)
	end
	plots.DescendantAdded:Connect(show)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name ~= "BuySection" or not ownGarden(prompt) then
			return
		end
		local x, z = prompt:GetAttribute("SectionX"), prompt:GetAttribute("SectionZ")
		if typeof(x) == "number" and typeof(z) == "number" then
			Remotes.PlotBuySection:FireServer(x, z)
		end
	end)
end

return PlotController
