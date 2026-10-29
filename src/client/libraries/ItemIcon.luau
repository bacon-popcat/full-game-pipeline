--!strict
-- ItemIcon: draws an item's 3D art into a ViewportFrame, framed the same way everywhere
-- (slots, the drag ghost, the backpack preview). Showing the item a viewport already
-- shows is free, so callers can call `show` on every render.
--
-- Only the model and camera added here are ever removed, so anything authored inside a
-- viewport survives a redraw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemArt = require(ReplicatedStorage.Shared.ItemArt)

type Drawn = { itemId: string?, model: Model?, camera: Camera? }

-- Camera sits up and to the front-right of the item.
local VIEW_DIRECTION = Vector3.new(1, 0.75, -1).Unit
local FIELD_OF_VIEW = 30
-- Above 1 leaves a margin around the item.
local FRAMING = 0.95

local ItemIcon = {}

local drawn: { [ViewportFrame]: Drawn } = {}

function ItemIcon.clear(viewport: ViewportFrame)
	local current = drawn[viewport]
	if current then
		if current.model then
			current.model:Destroy()
		end
		if current.camera then
			current.camera:Destroy()
		end
	end
	drawn[viewport] = nil
end

function ItemIcon.show(viewport: ViewportFrame, itemId: string?)
	local current = drawn[viewport]
	if current and current.itemId == itemId then
		return
	end
	ItemIcon.clear(viewport)
	local entry: Drawn = { itemId = itemId }
	drawn[viewport] = entry
	if not itemId then
		return
	end

	local model = ItemArt.copy(itemId)
	if not model then
		return
	end
	local box, size = model:GetBoundingBox()
	local distance = (size.Magnitude / 2) * FRAMING / math.sin(math.rad(FIELD_OF_VIEW / 2))
	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.lookAt(box.Position + VIEW_DIRECTION * distance, box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport
	entry.model = model
	entry.camera = camera
end

return ItemIcon
