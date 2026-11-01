-- PromptController: reserve the inventory key by mapping world prompts to Controls.INTERACT.
-- Applies locally, including prompts streamed in after startup; server validation is unchanged.
local Controls = require(script.Parent.Parent.Libraries.Controls)
local PromptController = {}

local function bind(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.KeyboardKeyCode = Controls.INTERACT[1]
	end
end

function PromptController.init()
	workspace.DescendantAdded:Connect(bind)
	for _, instance in workspace:GetDescendants() do
		bind(instance)
	end
end

return PromptController
