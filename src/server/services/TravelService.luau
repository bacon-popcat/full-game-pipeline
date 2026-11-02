-- TravelService: two counter-running loops beside both garden rows, joined by rounded
-- end turns. Anchored surface velocity carries riders without changing character state.
-- Public map scenery is independent of factory conveyors and saved plot contents. Both loops
-- are soft grey with low darker curbs and pale chevrons pointing the way they run.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)
local Plot = require(ReplicatedStorage.Shared.Plot)
local TravelService = {}

local SPEED = 32
local WIDTH = 8
local TURN_STEPS = 18
local BELT_COLOR = Color3.fromRGB(163, 167, 172)
local CURB_COLOR = Color3.fromRGB(118, 122, 128)
local ARROW_COLOR = Color3.fromRGB(232, 234, 236)
local LOOPS = {
	{ name = "OuterLoop", radius = 22, direction = -1 },
	{ name = "InnerLoop", radius = 12, direction = 1 },
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Anchored = true
	result.Size = size
	result.CFrame = cf
	result.Color = color
	result.Material = Enum.Material.SmoothPlastic
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.CanCollide = false
	result.CanTouch = false
	result.CanQuery = false
	result.Parent = parent
	return result
end

function TravelService.init()
	if workspace:FindFirstChild("TravelLanes") then
		return
	end
	local low, high = math.huge, -math.huge
	for index = 1, Plot.COUNT do
		local x = Plot.origin(index).X * Build.GRID
		low = math.min(low, x)
		high = math.max(high, x + Plot.WIDTH * Build.GRID)
	end
	local folder = Instance.new("Folder")
	folder.Name = "TravelLanes"
	local velocities: { [BasePart]: Vector3 } = {}
	-- Shared arc centers keep the loops parallel, clear of the plaza and inside the road.
	local corners = {
		Vector3.new(high - 22, 0.2, -19),
		Vector3.new(high - 22, 0.2, 19),
		Vector3.new(low + 22, 0.2, 19),
		Vector3.new(low + 22, 0.2, -19),
	}
	for _, loop in LOOPS do
		local model = Instance.new("Model")
		model.Name = loop.name
		local points: { Vector3 } = {}
		for corner, center in corners do
			for step = 0, TURN_STEPS do
				local angle = math.rad((corner - 2) * 90 + step * 90 / TURN_STEPS)
				table.insert(points, center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * loop.radius)
			end
		end
		for index, start in points do
			local finish = points[index % #points + 1]
			local delta = finish - start
			local direction = delta.Unit
			local frame =
				CFrame.fromMatrix((start + finish) / 2, direction, Vector3.yAxis, direction:Cross(Vector3.yAxis))
			-- Overlap the short tangent segments enough to cover the outside of each bend.
			local length = delta.Magnitude + (if delta.Magnitude < 5 then 0.6 else 0.05)
			local belt = part(model, "Belt", Vector3.new(length, 0.4, WIDTH), frame, BELT_COLOR)
			belt.CanCollide = true
			belt.CanQuery = true
			belt.CustomPhysicalProperties = PhysicalProperties.new(1, 1, 0, 100, 100)
			velocities[belt] = direction * loop.direction * SPEED
			for _, side in { -1, 1 } do
				part(
					model,
					"Curb",
					Vector3.new(length, 0.2, 0.6),
					frame * CFrame.new(0, 0.3, side * (WIDTH / 2 - 0.3)),
					CURB_COLOR
				)
			end
			if delta.Magnitude > 5 then
				for x = -delta.Magnitude / 2 + 6, delta.Magnitude / 2 - 3, 18 do
					for _, side in { -1, 1 } do
						part(
							model,
							"Arrow",
							Vector3.new(2.6, 0.04, 0.5),
							frame
								* CFrame.new(x, 0.23, side * 0.9)
								* CFrame.Angles(0, side * loop.direction * math.pi / 4, 0),
							ARROW_COLOR
						)
					end
				end
			end
		end
		model.Parent = folder
	end
	folder.Parent = workspace
	for belt, velocity in velocities do
		belt.AssemblyLinearVelocity = velocity
	end
end

return TravelService
