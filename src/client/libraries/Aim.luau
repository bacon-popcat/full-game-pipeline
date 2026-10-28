-- Aim: where the player points into the world -- the mouse, the last touch on the world,
-- or the screen centre on a gamepad -- shared by everything that acts on or describes
-- what is aimed at, so the hand and the hover panel always agree on the target. Touch has
-- no live cursor, so whoever sees touches report them through `setTouch`.

local UserInputService = game:GetService("UserInputService")

local Aim = {}

-- Last touch on the world (not on UI), in GUI space.
local lastTouch: Vector2? = nil

function Aim.setTouch(position: Vector2)
	lastTouch = position
end

-- The ray the player aims along, or nil (touch before the first tap).
function Aim.ray(): Ray?
	local camera = workspace.CurrentCamera
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Gamepad then
		local centre = camera.ViewportSize / 2
		return camera:ViewportPointToRay(centre.X, centre.Y)
	elseif preferred == Enum.PreferredInput.Touch then
		local touch = lastTouch
		return if touch then camera:ScreenPointToRay(touch.X, touch.Y) else nil
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

function Aim.cast(params: RaycastParams, distance: number): RaycastResult?
	local ray = Aim.ray()
	return if ray then workspace:Raycast(ray.Origin, ray.Direction * distance, params) else nil
end

-- The model `part` belongs to directly under Workspace[folderName], if any.
function Aim.modelUnder(part: Instance, folderName: string): Model?
	local container = workspace:FindFirstChild(folderName)
	local node: Instance? = part
	while node and container and node.Parent ~= container do
		node = node.Parent
	end
	return if node and node:IsA("Model") then node else nil
end

return Aim
