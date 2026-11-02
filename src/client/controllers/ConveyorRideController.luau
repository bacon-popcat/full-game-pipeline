-- ConveyorRideController: carries the local character along any conveyor or router belt it
-- stands on, at that belt's speed, the way items ride it. Characters are client-owned
-- physics, so this runs only here; the server sends nothing. The belt under the feet is
-- found by a downward ray. A LinearVelocity (horizontal plane only, so ramps and jumps stay
-- the Humanoid's) steers toward a point just ahead on the nearest lane, which rounds turns
-- and keeps the character centred; an AlignOrientation faces it along the belt while it
-- stands still.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)

-- How far below the root part the ray looks for a belt.
local RAY_DEPTH = 6
-- Studs ahead along the lane the push steers toward.
local LOOKAHEAD = 1.5
-- Push force per unit of character mass: enough to carry, not enough to fling.
local PUSH_FORCE = 400

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

-- The constraints the push uses, made on the root part of each new character.
local mover: LinearVelocity? = nil
local turner: AlignOrientation? = nil

local function rig(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ConveyorRide"
	attachment.Parent = root
	-- Plane mode drives only horizontal velocity, so gravity, jumps and ramps stay the Humanoid's.
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 0
	velocity.Enabled = false
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.Responsiveness = 12
	align.MaxTorque = math.huge
	align.Enabled = false
	align.Parent = root
	mover, turner = velocity, align
end

local function release()
	if mover then
		mover.Enabled = false
	end
	if turner and turner.Enabled then
		turner.Enabled = false
		local humanoid = turner.Parent and turner.Parent.Parent
			and (turner.Parent.Parent :: Instance):FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
end

local function step()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		not root
		or not humanoid
		or not mover
		or not turner
		or humanoid.Health <= 0
		or humanoid.FloorMaterial == Enum.Material.Air
	then
		release()
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -RAY_DEPTH, 0), params)
	local model = if hit then beltModel(hit.Instance) else nil
	if not model or not hit then
		release()
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
		release()
		return
	end
	-- Steer at a point a little ahead on the lane, so a turn is rounded off instead of
	-- overshot, and pull back toward the belt's centre line.
	local here = Lane.pointAt(best.points, bestD)
	local ahead, travel = Lane.pointAt(best.points, math.min(bestD + LOOKAHEAD, best.length))
	local target = if bestD + LOOKAHEAD <= best.length then ahead else here + travel * LOOKAHEAD
	local toward = Vector3.new(target.X - hit.Position.X, 0, target.Z - hit.Position.Z)
	if toward.Magnitude < 1e-3 then
		release()
		return
	end
	local belt = toward.Unit * best.speed
	local walk = humanoid.MoveDirection * humanoid.WalkSpeed
	mover.PlaneVelocity = Vector2.new(belt.X + walk.X, belt.Z + walk.Z)
	mover.MaxForce = root.AssemblyMass * PUSH_FORCE
	mover.Enabled = true
	-- Face the way the belt runs while standing; walking leaves turning to the Humanoid.
	local standing = humanoid.MoveDirection.Magnitude < 0.1
	turner.Enabled = standing
	humanoid.AutoRotate = not standing
	if standing then
		turner.CFrame = CFrame.lookAt(Vector3.zero, toward.Unit)
	end
end

function ConveyorRideController.init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		mover, turner = nil, nil
		rig(character)
	end)
	if player.Character then
		task.spawn(rig, player.Character)
	end
	RunService.Heartbeat:Connect(step)
end

return ConveyorRideController
