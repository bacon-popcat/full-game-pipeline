-- ConveyorRideController: carries the local character along any conveyor or router belt it
-- stands on, at that belt's speed, the way items ride it. Characters are client-owned
-- physics, so this runs only here; the server sends nothing. The belt under the feet is
-- found by a downward ray. The root is moved toward a point just ahead on the nearest lane,
-- horizontally only so ramps are climbed by the Humanoid; aiming ahead rounds turns and
-- keeps the character centred, and a standing character turns to face the belt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)

-- How far below the root part the ray looks for a belt.
local RAY_DEPTH = 6
-- Studs ahead along the lane the push steers toward.
local LOOKAHEAD = 1.5
-- How quickly a standing character turns to face the belt (fraction per second).
local TURN_RATE = 8

type WorldLane = { points: { Vector3 }, length: number, speed: number }

local ConveyorRideController = {}

-- World lanes per placed belt, keyed by model; dropped when the model leaves the world.
local laneCache: { [Model]: { WorldLane } } = {}

local function beltModel(part: Instance): Model?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:IsA("Model") then
			local itemId = current:GetAttribute("ItemId")
			local def = if typeof(itemId) == "string" then Factory.get(itemId) else nil
			if def and (def.kind == "Conveyor" or def.kind == "Router") then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function lanesOf(model: Model): { WorldLane }
	local cached = laneCache[model]
	if cached then
		return cached
	end
	local frame = Factory.originFrame(model)
	local itemId = model:GetAttribute("ItemId") :: string
	local result: { WorldLane } = {}
	if frame then
		for _, def in Factory.lanes(itemId) do
			local points = Factory.worldPoints(frame, def.points)
			table.insert(result, { points = points, length = Lane.length(points), speed = def.speed })
		end
	end
	laneCache[model] = result
	model.AncestryChanged:Once(function()
		laneCache[model] = nil
	end)
	return result
end

local function step(dt: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not root
		or not humanoid
		or humanoid.Health <= 0
		or humanoid.FloorMaterial == Enum.Material.Air
	then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -RAY_DEPTH, 0), params)
	local model = if hit then beltModel(hit.Instance) else nil
	if not model or not hit then
		return
	end

	local best: WorldLane?, bestD, bestDistance = nil, 0, math.huge
	for _, lane in lanesOf(model) do
		local d, distance = Lane.project(lane.points, hit.Position)
		if distance < bestDistance then
			best, bestD, bestDistance = lane, d, distance
		end
	end
	if not best then
		return
	end
	-- Steer at a point a little ahead on the lane, so a turn is rounded off instead of
	-- overshot, and pull back toward the belt's centre line.
	local here = Lane.pointAt(best.points, bestD)
	local ahead, travel = Lane.pointAt(best.points, math.min(bestD + LOOKAHEAD, best.length))
	local target = if bestD + LOOKAHEAD <= best.length then ahead else here + travel * LOOKAHEAD
	local toward = Vector3.new(target.X - hit.Position.X, 0, target.Z - hit.Position.Z)
	if toward.Magnitude < 1e-3 then
		return
	end
	local direction = toward.Unit
	local position = root.Position + direction * best.speed * dt
	-- Turn to face the belt while standing; walking leaves turning to the Humanoid.
	local facing = root.CFrame.LookVector
	if humanoid.MoveDirection.Magnitude < 0.1 then
		local flat = Vector3.new(facing.X, 0, facing.Z)
		facing = if flat.Magnitude > 1e-3 then flat.Unit:Lerp(direction, math.min(1, TURN_RATE * dt)) else direction
	end
	root.CFrame = CFrame.lookAt(position, position + facing)
end

function ConveyorRideController.init()
	RunService.Heartbeat:Connect(step)
end

return ConveyorRideController
