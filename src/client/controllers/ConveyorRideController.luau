-- ConveyorRideController: carries the local character along any conveyor or router belt it
-- stands on, at that belt's speed, the way items ride it. Characters are client-owned
-- physics, so this runs only here; the server sends nothing. The belt under the feet is
-- found by a downward ray, and the push follows the nearest of its lanes (Factory.lanes),
-- flattened so ramps are climbed by the Humanoid rather than lifted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)

-- How far below the root part the ray looks for a belt.
local RAY_DEPTH = 6

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
	if not root or not humanoid or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
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
	local _, direction = Lane.pointAt(best.points, math.min(bestD, best.length))
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	root.CFrame += flat.Unit * best.speed * dt
end

function ConveyorRideController.init()
	RunService.Heartbeat:Connect(step)
end

return ConveyorRideController
