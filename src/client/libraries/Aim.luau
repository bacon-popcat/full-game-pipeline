-- Aim: where the player points into the world -- the mouse, the last touch on the world,
-- or the screen centre on a gamepad -- shared by everything that acts on or describes
-- what is aimed at. The hand aims at hitboxes (placing snaps to their faces); the hover
-- panel and the machine panel aim at the art (`castArt`). Touch has no live cursor, so
-- whoever sees touches report them through `setTouch`.

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

-- Loose drops (Workspace.Drops) collide, so CanQuery can't hide them from a ray; an
-- excluding `params` gets their folder added, so the aim passes through them.
function Aim.cast(params: RaycastParams, distance: number): RaycastResult?
	local drops = workspace:FindFirstChild("Drops")
	local excluding = params.FilterType == Enum.RaycastFilterType.Exclude
	if drops and excluding and not table.find(params.FilterDescendantsInstances, drops) then
		params:AddToFilter(drops)
	end
	local ray = Aim.ray()
	return if ray then workspace:Raycast(ray.Origin, ray.Direction * distance, params) else nil
end

-- Most invisible hitboxes one `castArt` passes through before giving up.
local MAX_HITBOXES = 8

-- Whether `part` is an invisible hitbox around a block's or node's art (a placeholder's
-- hitbox is visible, and counts as art).
local function isHitbox(part: Instance): boolean
	return part.Name == "Hitbox" and part:IsA("BasePart") and part.Transparency >= 1
end

-- Like `cast`, but passes through invisible hitboxes, so it only lands on what the player
-- can see: describing or opening a block takes pointing at its art, not the empty cells of
-- its box. `params` is left as it was.
function Aim.castArt(params: RaycastParams, distance: number): RaycastResult?
	local result = Aim.cast(params, distance)
	if not result or not isHitbox(result.Instance) then
		return result
	end
	local through = RaycastParams.new()
	through.FilterType = params.FilterType
	through.FilterDescendantsInstances = params.FilterDescendantsInstances
	through.CollisionGroup = params.CollisionGroup
	through.RespectCanCollide = params.RespectCanCollide
	for _ = 1, MAX_HITBOXES do
		if not result or not isHitbox(result.Instance) then
			return result
		end
		through:AddToFilter(result.Instance)
		result = Aim.cast(through, distance)
	end
	return nil
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
