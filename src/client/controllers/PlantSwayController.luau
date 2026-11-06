-- PlantSwayController: crops sway in the wind and bend away from anyone walking through
-- them, then spring back. It is only a look, drawn here: it moves each crop's living parts
-- locally with BulkMoveTo and never sends anything, so the server's copy, saves and aim stay
-- where they are. No physics either: each plant is one tilt about its foot, a wind term plus
-- a damped spring for pushes.
--
-- What moves: every part of a crop node except its Hitbox and the parts keyed in STILL (stakes,
-- and roots in the ground; art keys are in IslandsMachines/build/crops.py). A
-- part's rest pose is taken the first time it is seen, before this has moved it, and restored
-- whenever the plant goes out of range, so a streamed-in part never bakes in a lean.
--
-- Cost: plants past FAR from the camera rest and are skipped; those past NEAR update every
-- other frame; a plant whose tilt barely changed isn't moved. Pushes look up plants by cell
-- around each character, so they cost nothing far from players. Reduced motion stills the
-- wind but keeps the push, which answers the player's own movement.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Build = require(ReplicatedStorage.Shared.Build)
local World = require(ReplicatedStorage.Shared.World)
local Weather = require(ReplicatedStorage.Shared.World.Weather)

-- Art keys (the `_<Key>` suffix of a part's name) that never move.
local STILL = { Stake = true, Tuber = true }
-- How far each crop gives, relative to a soft plant (1). Trees and trained vines give less; the
-- tilt is an angle, so the 13-stud trees (Apple, Starfruit) give far less to sweep as gently.
local FLEX: { [string]: number } = { Apple = 0.16, Starfruit = 0.22, Grape = 0.3, Tomato = 0.55, Corn = 0.85 }

local FAR = 120
local NEAR = 60
-- Wind, in radians: a steady lean downwind, gusts that roll across the garden as a wave, and a
-- small flutter across the wind at each plant's own pace.
local WIND_LEAN = math.rad(1.8)
local WIND_GUST = math.rad(2.6)
local WIND_FLUTTER = math.rad(0.9)
local GUST_WAVELENGTH = 26 -- studs between gust fronts
local GUST_SPEED = 0.16 -- gust fronts per second
-- Pushes: how close a character must be (studs, across the ground), how far it bends a plant
-- at the centre, and the spring that brings it back, a little underdamped so it settles with
-- one soft overshoot.
local PUSH_RADIUS = 2.6
local PUSH_ANGLE = math.rad(30)
local MAX_ANGLE = math.rad(38)
local SPRING_RATE = 2 * math.pi * 1.4
local SPRING_DAMPING = 0.32
local SETTLED = 1e-4
local MOVE_EPSILON = math.rad(0.08)

type Plant = {
	model: Model,
	rest: { [BasePart]: CFrame },
	-- Each moving part relative to the foot's position, rebuilt from `rest`.
	parts: { BasePart },
	locals: { CFrame },
	foot: Vector3,
	height: number,
	flex: number,
	flutterRate: number,
	flutterPhase: number,
	tilt: Vector3,
	velocity: Vector3,
	shown: Vector3,
	posed: boolean,
	key: string,
}

local PlantSwayController = {}

local plants: { [Model]: Plant } = {}
local byCell: { [string]: { Plant } } = {}

local function artKey(part: BasePart): string?
	return string.match(part.Name, "_(%w+)$")
end

local function cellKey(x: number, z: number): string
	return `{x},{z}`
end

local function cellOf(position: Vector3): (number, number)
	return math.floor(position.X / Build.GRID), math.floor(position.Z / Build.GRID)
end

local function rebuild(plant: Plant)
	table.clear(plant.parts)
	table.clear(plant.locals)
	local top = 0
	local origin = CFrame.new(-plant.foot)
	for part, rest in plant.rest do
		table.insert(plant.parts, part)
		table.insert(plant.locals, origin * rest)
		top = math.max(top, rest.Position.Y + part.Size.Magnitude / 2 - plant.foot.Y)
	end
	plant.height = math.max(top, 1)
end

local function restore(plant: Plant)
	if not plant.posed then
		return
	end
	local parts, cframes = {}, {}
	for part, rest in plant.rest do
		if part.Parent then
			table.insert(parts, part)
			table.insert(cframes, rest)
		end
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	plant.posed = false
	plant.shown = Vector3.zero
end

local function track(plant: Plant, part: Instance)
	if not part:IsA("BasePart") or part.Name == "Hitbox" or plant.rest[part] then
		return
	end
	local key = artKey(part)
	if key and STILL[key] then
		return
	end
	-- Seen before this controller moves it, so its CFrame now is its rest pose.
	plant.rest[part] = part.CFrame
end

local function unbind(model: Model)
	local plant = plants[model]
	if not plant then
		return
	end
	-- No restore: the model has left the world (harvested, grown into its next stage, or
	-- streamed out), and a streamed-in copy comes back at its rest pose.
	plants[model] = nil
	local list = byCell[plant.key]
	if list then
		local index = table.find(list, plant)
		if index then
			table.remove(list, index)
		end
		if #list == 0 then
			byCell[plant.key] = nil
		end
	end
end

local function bind(model: Instance)
	if not model:IsA("Model") or plants[model] then
		return
	end
	local def = World.NODES[model.Name]
	if not def or not def.crop then
		return
	end
	-- The foot is the centre of the cell's floor. Read from the Cell attribute rather than the
	-- pivot: a streamed-in model may not have its Hitbox (PrimaryPart) yet.
	local cell = model:GetAttribute("Cell")
	local foot = if typeof(cell) == "Vector3"
		then Vector3.new((cell.X + 0.5) * Build.GRID, cell.Y * Build.GRID, (cell.Z + 0.5) * Build.GRID)
		else model:GetPivot().Position
	local x, z = cellOf(foot)
	-- Each plant moves at its own pace, picked from its cell so it is the same every visit.
	local seed = Random.new(x * 7919 + z * 104729)
	local plant: Plant = {
		model = model,
		rest = {},
		parts = {},
		locals = {},
		foot = foot,
		height = 1,
		flex = FLEX[def.crop] or 1,
		flutterRate = seed:NextNumber(0.55, 0.85) * 2 * math.pi,
		flutterPhase = seed:NextNumber(0, 2 * math.pi),
		tilt = Vector3.zero,
		velocity = Vector3.zero,
		shown = Vector3.zero,
		posed = false,
		key = cellKey(x, z),
	}
	plants[model] = plant
	local list = byCell[plant.key] or {}
	byCell[plant.key] = list
	table.insert(list, plant)
	for _, part in model:GetDescendants() do
		track(plant, part)
	end
	rebuild(plant)
	-- Parts stream in and out on their own; bring the moving set up to date as they do.
	model.DescendantAdded:Connect(function(part)
		if plants[model] == plant and part:IsA("BasePart") then
			track(plant, part)
			rebuild(plant)
		end
	end)
	model.DescendantRemoving:Connect(function(part)
		if plants[model] == plant and part:IsA("BasePart") and plant.rest[part] then
			plant.rest[part] = nil
			rebuild(plant)
		end
	end)
end

-- Where every character's root is this frame.
local function bodies(): { BasePart }
	local found = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			table.insert(found, root)
		end
	end
	return found
end

-- Each nearby plant's push target this frame: away from every character standing in it.
local function pushes(roots: { BasePart }): { [Plant]: Vector3 }
	local targets: { [Plant]: Vector3 } = {}
	local reach = math.ceil(PUSH_RADIUS / Build.GRID)
	for _, root in roots do
		local at = root.Position
		local cx, cz = cellOf(at)
		for dx = -reach, reach do
			for dz = -reach, reach do
				local list = byCell[cellKey(cx + dx, cz + dz)]
				if not list then
					continue
				end
				for _, plant in list do
					local rise = at.Y - plant.foot.Y
					if rise < -1 or rise > plant.height + 3.5 then
						continue
					end
					local away = Vector3.new(plant.foot.X - at.X, 0, plant.foot.Z - at.Z)
					local distance = away.Magnitude
					if distance >= PUSH_RADIUS then
						continue
					end
					-- Standing right on a plant pushes it the way the body faces.
					local direction = if distance > 0.15
						then away / distance
						else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
					local strength = (1 - distance / PUSH_RADIUS) ^ 1.3
					targets[plant] = (targets[plant] or Vector3.zero) + direction * (strength * PUSH_ANGLE)
				end
			end
		end
	end
	return targets
end

local weatherWind = 1

local function step(dt: number, frame: number)
	dt = math.min(dt, 1 / 20)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	local targets = pushes(bodies())
	local wind = if GuiService.ReducedMotionEnabled then 0 else weatherWind
	-- The wind slowly veers, so rows don't all lean one fixed way all day.
	local heading = 0.6 + 0.5 * math.sin(now / 47)
	local downwind = Vector3.new(math.cos(heading), 0, math.sin(heading))
	local across = Vector3.new(-downwind.Z, 0, downwind.X)
	local k = SPRING_RATE * SPRING_RATE
	local c = 2 * SPRING_DAMPING * SPRING_RATE
	local parts, cframes = {}, {}
	local index = 0
	for _, plant in plants do
		index += 1
		local target = targets[plant]
		-- The spring runs for every plant that is pushed or still moving, whatever its distance.
		if target or plant.tilt.Magnitude > SETTLED or plant.velocity.Magnitude > SETTLED then
			local goal = target or Vector3.zero
			if goal.Magnitude > PUSH_ANGLE then
				goal = goal.Unit * PUSH_ANGLE
			end
			plant.velocity += (k * (goal - plant.tilt) - c * plant.velocity) * dt
			plant.tilt += plant.velocity * dt
		end
		local distance = (plant.foot - eye).Magnitude
		if distance > FAR or #plant.parts == 0 then
			restore(plant)
			continue
		end
		if distance > NEAR and (index + frame) % 2 == 1 then
			continue
		end
		local lean = plant.tilt
		if wind > 0 then
			local front = (plant.foot:Dot(downwind) / GUST_WAVELENGTH - now * GUST_SPEED) * 2 * math.pi
			local gust = 0.5 + 0.5 * math.sin(front) * (0.7 + 0.3 * math.sin(front * 0.37 + 1.3))
			local flutter = math.sin(now * plant.flutterRate + plant.flutterPhase)
			lean += (downwind * (WIND_LEAN + WIND_GUST * gust) + across * (WIND_FLUTTER * flutter)) * wind
		end
		lean *= plant.flex
		if lean.Magnitude > MAX_ANGLE then
			lean = lean.Unit * MAX_ANGLE
		end
		if (lean - plant.shown).Magnitude < MOVE_EPSILON then
			continue
		end
		plant.shown = lean
		plant.posed = true
		local angle = lean.Magnitude
		-- Tipping toward `lean` turns about the level axis square to it.
		local pose = if angle > 1e-6
			then CFrame.new(plant.foot) * CFrame.fromAxisAngle(Vector3.new(lean.Z, 0, -lean.X) / angle, angle)
			else CFrame.new(plant.foot)
		for i, part in plant.parts do
			table.insert(parts, part)
			table.insert(cframes, pose * plant.locals[i])
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PlantSwayController.init()
	local folder = workspace:WaitForChild("World")
	local weather = ReplicatedStorage:WaitForChild("Weather")
	local function readWeather()
		local event = weather:GetAttribute("Event")
		local def = if typeof(event) == "string" then Weather.get(event) else nil
		weatherWind = if def then def.wind else 1
	end
	weather:GetAttributeChangedSignal("Event"):Connect(readWeather)
	readWeather()
	folder.ChildAdded:Connect(bind)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			unbind(child)
		end
	end)
	for _, child in folder:GetChildren() do
		bind(child)
	end
	local frame = 0
	RunService.Heartbeat:Connect(function(dt)
		frame += 1
		step(dt, frame)
	end)
end

return PlantSwayController
