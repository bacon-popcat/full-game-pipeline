--!strict
-- Turntable: shows one item's art large in a ViewportFrame, turning slowly on the spot, and
-- lets the player drag it (mouse or finger) to look at it from any side. Dragging turns it
-- left and right and tips it up and down; letting go hands it back to the slow turn after a
-- moment. With reduced motion it only turns when dragged.
--
-- The item turns, not the camera, so the viewport's authored light stays put and the lit
-- side moves across it like a real turntable. The camera frames the item's bounding sphere,
-- so no turn ever clips it.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Trove = require(ReplicatedStorage.Packages.Trove)

-- Radians a second of the slow turn, and per pixel dragged.
local SPIN_SPEED = math.rad(24)
local DRAG_TURN = math.rad(0.6)
local MAX_PITCH = math.rad(70)
-- Seconds after a drag ends before the slow turn picks up again.
local RESUME_AFTER = 1.5
-- Where an item starts: its front-right, like its inventory icon, seen slightly from above.
local START_YAW = math.rad(-35)
local START_PITCH = math.rad(12)
local FIELD_OF_VIEW = 30
-- Above 1 leaves a margin around the item.
local FRAMING = 1.05

export type Turntable = {
	show: (itemId: string?) -> (),
	destroy: () -> (),
}

local Turntable = {}

function Turntable.bind(view: ViewportFrame): Turntable
	local trove = Trove.new()
	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.Parent = view
	view.CurrentCamera = camera
	trove:Add(camera)

	local model: Model? = nil
	local shownId: string? = nil
	-- The model's pivot relative to its bounding-box centre, which it turns about.
	local offset = CFrame.identity
	local center = Vector3.zero
	local yaw, pitch = START_YAW, START_PITCH
	local dragging: InputObject? = nil
	local last = Vector2.zero
	local releasedAt = -math.huge

	local function pose()
		if model then
			model:PivotTo(CFrame.new(center) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, yaw, 0) * offset)
		end
	end

	local function show(itemId: string?)
		if itemId == shownId then
			return
		end
		shownId = itemId
		if model then
			model:Destroy()
			model = nil
		end
		yaw, pitch = START_YAW, START_PITCH
		local copy = if itemId then ItemArt.copy(itemId) else nil
		if not copy then
			return
		end
		local box, size = copy:GetBoundingBox()
		center = box.Position
		offset = CFrame.new(center):Inverse() * copy:GetPivot()
		local distance = (size.Magnitude / 2) * FRAMING / math.sin(math.rad(FIELD_OF_VIEW / 2))
		-- The camera looks down -Z at the item, so turning about X tips it toward the viewer.
		camera.CFrame = CFrame.lookAt(center + Vector3.zAxis * distance, center)
		copy.Parent = view
		model = copy
		pose()
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	-- A press is hit-tested against the viewport's rectangle (input and AbsolutePosition share
	-- GUI space), as InventoryScreen does: the viewport's own InputBegan misses mouse presses.
	trove:Connect(UserInputService.InputBegan, function(input: InputObject)
		if not model or not isPress(input) then
			return
		end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		local min, max = view.AbsolutePosition, view.AbsolutePosition + view.AbsoluteSize
		if point.X >= min.X and point.X <= max.X and point.Y >= min.Y and point.Y <= max.Y then
			dragging = input
			last = point
		end
	end)
	trove:Connect(UserInputService.InputChanged, function(input: InputObject)
		local held = dragging
		if not held then
			return
		end
		local moved = input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == held)
		if moved then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local delta = point - last
			last = point
			yaw += delta.X * DRAG_TURN
			pitch = math.clamp(pitch + delta.Y * DRAG_TURN, -MAX_PITCH, MAX_PITCH)
			pose()
		end
	end)
	trove:Connect(UserInputService.InputEnded, function(input: InputObject)
		if dragging and isPress(input) then
			dragging = nil
			releasedAt = os.clock()
		end
	end)
	trove:Connect(RunService.RenderStepped, function(dt: number)
		if
			model
			and view.Visible
			and not dragging
			and not GuiService.ReducedMotionEnabled
			and os.clock() - releasedAt > RESUME_AFTER
		then
			yaw += SPIN_SPEED * dt
			pose()
		end
	end)

	return {
		show = show,
		destroy = function()
			show(nil)
			trove:Destroy()
		end,
	}
end

return Turntable
