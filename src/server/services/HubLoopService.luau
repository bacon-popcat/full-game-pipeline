-- HubLoopService: lays the moving walkway that loops around the hub, a grey belt with raised
-- rails and chevrons, made of short straight pieces laid as one closed path, inset from the hub's ends and clear of the plaza and spawn at the centre. Each belt piece
-- carries RideDirection (a unit Vector3) and RideSpeed attributes, which
-- ConveyorRideController reads to carry players along it.

local HubLoopService = {}

-- Studs from the centre to each straight's centre line, and from the centre to where the
-- straights end and the half-circle ends begin. The plaza reaches 25 studs out and the gardens'
-- fronts 48, so the straights sit between them.
local SIDE = 36
local HALF_LENGTH = 150
local WIDTH = 6
local SPEED = 8
-- Pieces per half-circle end; more pieces round it off better.
local END_PIECES = 28
-- Studs between chevrons along a straight.
local CHEVRON_GAP = 9

local BELT_THICKNESS = 0.4
local BELT_COLOR = Color3.fromRGB(92, 96, 102)
local RAIL_COLOR = Color3.fromRGB(176, 180, 186)
local CHEVRON_COLOR = Color3.fromRGB(214, 217, 221)

local function part(parent: Instance, name: string, size: Vector3, frame: CFrame, color: Color3, collide: boolean)
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.CFrame = frame
	created.Color = color
	created.Material = Enum.Material.SmoothPlastic
	created.Anchored = true
	created.CanCollide = collide
	created.CanTouch = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- One straight piece of belt from `a` to `b` (centre line, ground level), with its rails and,
-- when `chevron` is set, a chevron at its middle pointing the way it runs.
local function piece(parent: Instance, a: Vector3, b: Vector3, overlap: number, chevron: boolean)
	local length = (b - a).Magnitude
	local direction = (b - a).Unit
	local middle = (a + b) / 2
	local frame = CFrame.lookAt(middle, middle + direction)
	local belt = part(
		parent,
		"Belt",
		Vector3.new(WIDTH, BELT_THICKNESS, length + overlap),
		frame + Vector3.new(0, BELT_THICKNESS / 2, 0),
		BELT_COLOR,
		true
	)
	belt:SetAttribute("RideDirection", direction)
	belt:SetAttribute("RideSpeed", SPEED)
	for _, side in { -1, 1 } do
		local rail = part(
			parent,
			"Rail",
			Vector3.new(0.5, 0.5, length + overlap),
			frame * CFrame.new(side * (WIDTH / 2 + 0.25), 0.25, 0),
			RAIL_COLOR,
			true
		)
		rail.Material = Enum.Material.Metal
	end
	if chevron then
		-- Two bars meeting at the front, just proud of the belt; CFrame -Z is forward.
		for _, side in { -1, 1 } do
			local bar = frame
				* CFrame.new(side * 0.8, BELT_THICKNESS + 0.03, 0.2)
				* CFrame.Angles(0, side * math.rad(40), 0)
			-- Not queryable, so the rider's ray lands on the belt beneath.
			part(parent, "Chevron", Vector3.new(0.35, 0.06, 2.4), bar, CHEVRON_COLOR, false).CanQuery = false
		end
	end
end

local function build(): Model
	local loop = Instance.new("Model")
	loop.Name = "HubLoop"
	-- Laid as one closed path: +Z straight heading +X, the +X end, -Z straight heading -X, the -X end.
	local function straight(from: Vector3, to: Vector3)
		local count = math.floor((to - from).Magnitude / CHEVRON_GAP)
		for index = 0, count - 1 do
			local a = from:Lerp(to, index / count)
			local b = from:Lerp(to, (index + 1) / count)
			piece(loop, a, b, 0, true)
		end
	end
	local function bend(centreX: number, startAngle: number)
		local centre = Vector3.new(centreX, 0, 0)
		for index = 0, END_PIECES - 1 do
			local t0 = startAngle - math.pi * index / END_PIECES
			local t1 = startAngle - math.pi * (index + 1) / END_PIECES
			local a = centre + Vector3.new(math.cos(t0), 0, math.sin(t0)) * SIDE
			local b = centre + Vector3.new(math.cos(t1), 0, math.sin(t1)) * SIDE
			-- Overlap hides the gaps on the outside of the bend.
			piece(loop, a, b, 0.6, index % 3 == 1)
		end
	end
	straight(Vector3.new(-HALF_LENGTH, 0, SIDE), Vector3.new(HALF_LENGTH, 0, SIDE))
	bend(HALF_LENGTH, math.pi / 2)
	straight(Vector3.new(HALF_LENGTH, 0, -SIDE), Vector3.new(-HALF_LENGTH, 0, -SIDE))
	bend(-HALF_LENGTH, -math.pi / 2)
	return loop
end

function HubLoopService.init()
	build().Parent = workspace
end

return HubLoopService
