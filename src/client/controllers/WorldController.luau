-- WorldController: animates the world's animals. WorldService moves an animal straight to
-- each destination and publishes the walk on the model (WalkFrom, WalkTo, WalkStart,
-- WalkTime); this plays it back locally with a little bob, so the server sends one update
-- per walk instead of a stream of positions. Once a walk ends the animal rests exactly
-- where the server already put it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Trove = require(ReplicatedStorage.Packages.Trove)

-- Studs an animal bobs up while it walks, and bobs per second.
local BOB_HEIGHT = 0.15
local BOB_RATE = 4

type Walk = { from: CFrame, to: CFrame, start: number, time: number }

local WorldController = {}

local walks: { [Model]: Walk } = {}
local troves: { [Model]: typeof(Trove.new()) } = {}

local function readWalk(model: Model)
	local from = model:GetAttribute("WalkFrom")
	local to = model:GetAttribute("WalkTo")
	local start = model:GetAttribute("WalkStart")
	local time = model:GetAttribute("WalkTime")
	if
		typeof(from) == "CFrame"
		and typeof(to) == "CFrame"
		and typeof(start) == "number"
		and typeof(time) == "number"
	then
		walks[model] = { from = from, to = to, start = start, time = time }
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or troves[model] then
		return
	end
	local trove = Trove.new()
	troves[model] = trove
	-- WalkStart is written last on the server, so it marks a complete walk.
	trove:Connect(model:GetAttributeChangedSignal("WalkStart"), function()
		readWalk(model)
	end)
	readWalk(model)
end

local function untrack(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local trove = troves[model]
	if trove then
		trove:Destroy()
		troves[model] = nil
	end
	walks[model] = nil
end

local function render()
	local now = workspace:GetServerTimeNow()
	for model, walk in walks do
		local alpha = if walk.time > 0 then (now - walk.start) / walk.time else 1
		if alpha >= 1 then
			model:PivotTo(walk.to)
			walks[model] = nil
		elseif alpha >= 0 then
			local bob = math.abs(math.sin(now * BOB_RATE * math.pi)) * BOB_HEIGHT
			model:PivotTo(walk.from:Lerp(walk.to, alpha) + Vector3.yAxis * bob)
		end
	end
end

function WorldController.init()
	local world = workspace:WaitForChild("World")
	local animals = world:WaitForChild("Animals")
	animals.ChildAdded:Connect(track)
	animals.ChildRemoved:Connect(untrack)
	for _, model in animals:GetChildren() do
		track(model)
	end
	RunService.RenderStepped:Connect(render)
end

return WorldController
