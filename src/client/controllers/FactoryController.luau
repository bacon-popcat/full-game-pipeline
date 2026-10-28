-- FactoryController: draws the items riding conveyors and routers. FactoryService sends a
-- lane's item list whenever an item joins or leaves it (FactorySync); between updates this
-- slides the items along with the same Lane rule the server runs, so positions are never
-- streamed. An item keeps one model for its whole trip, however many lanes it crosses,
-- and loses it the moment no lane holds it (it went into a machine or a hand).
--
-- Lanes are found by the BlockId attribute FactoryService puts on each placed block. An
-- update for a block that hasn't replicated yet waits until it has.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Lane = require(ReplicatedStorage.Shared.Factory.Lane)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type LaneView = {
	model: Model,
	points: { Vector3 },
	length: number,
	speed: number,
	items: { Lane.Item },
}

type Visual = {
	model: Model,
	-- The model's pivot relative to the bottom-centre of its bounding box.
	offset: CFrame,
}

type Pending = { items: { Lane.Item }, t: number }

-- Studs along an item's longest side as it rides a belt.
local ITEM_SIZE = 1.2

local FactoryController = {}

local lanes: { [string]: LaneView } = {}
local pending: { [string]: Pending } = {}
local blockModels: { [number]: Model } = {}
local visuals: { [number]: Visual } = {}
-- Which lane holds each item, so a lane rewrite only drops items no other lane has.
local itemLane: { [number]: string } = {}

local container = Instance.new("Folder")
container.Name = "FactoryItems"

local function makeVisual(itemId: string): Visual?
	local model = ItemArt.copy(itemId)
	if not model then
		return nil
	end
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * ITEM_SIZE / longest)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	local box, extent = model:GetBoundingBox()
	local bottom = box * CFrame.new(0, -extent.Y / 2, 0)
	model.Parent = container
	return { model = model, offset = bottom:ToObjectSpace(model:GetPivot()) }
end

local function viewFor(key: string): LaneView?
	local existing = lanes[key]
	if existing then
		return existing
	end
	local blockId = tonumber(string.match(key, "^(%d+)/"))
	local index = tonumber(string.match(key, "/(%d+)$"))
	local model = if blockId then blockModels[blockId] else nil
	local itemId = if model then model:GetAttribute("ItemId") else nil
	local frame = if model then Factory.originFrame(model) else nil
	if not model or typeof(itemId) ~= "string" or not frame or not index then
		return nil
	end
	local def = Factory.lanes(itemId)[index]
	if not def then
		return nil
	end
	local points = Factory.worldPoints(frame, def.points)
	local view: LaneView =
		{ model = model, points = points, length = Lane.length(points), speed = def.speed, items = {} }
	lanes[key] = view
	return view
end

local function sweep()
	for id, visual in visuals do
		if not itemLane[id] then
			visual.model:Destroy()
			visuals[id] = nil
		end
	end
end

local function apply(key: string, items: { Lane.Item }, t: number)
	local view = viewFor(key)
	if not view then
		pending[key] = { items = items, t = t }
		return
	end
	pending[key] = nil
	for _, item in view.items do
		if itemLane[item.id] == key then
			itemLane[item.id] = nil
		end
	end
	view.items = table.clone(items)
	local behind = workspace:GetServerTimeNow() - t
	if behind > 0 then
		Lane.advance(view.items, behind, view.speed, view.length)
	end
	for _, item in view.items do
		itemLane[item.id] = key
	end
end

-- The payload comes from the server (Remotes.FactorySync documents it).
local function onSync(update: { t: number, lanes: { [string]: { Lane.Item } } })
	for key, items in update.lanes do
		apply(key, items, update.t)
	end
	sweep()
end

local function dropBlock(blockId: number)
	blockModels[blockId] = nil
	local prefix = `{blockId}/`
	for key, view in lanes do
		if string.sub(key, 1, #prefix) == prefix then
			for _, item in view.items do
				if itemLane[item.id] == key then
					itemLane[item.id] = nil
				end
			end
			lanes[key] = nil
		end
	end
	sweep()
end

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function record()
		local blockId = model:GetAttribute("BlockId")
		if typeof(blockId) == "number" then
			blockModels[blockId] = model
		end
	end
	record()
	model:GetAttributeChangedSignal("BlockId"):Connect(record)
end

local function untrack(model: Instance)
	local blockId = model:GetAttribute("BlockId")
	if typeof(blockId) == "number" and blockModels[blockId] == model then
		dropBlock(blockId)
	end
end

local function render(dt: number)
	for key, waiting in pending do
		if viewFor(key) then
			apply(key, waiting.items, waiting.t)
		end
	end
	for _, view in lanes do
		Lane.advance(view.items, dt, view.speed, view.length)
		for _, item in view.items do
			local visual = visuals[item.id]
			if not visual then
				visual = makeVisual(item.itemId)
				if not visual then
					continue
				end
				visuals[item.id] = visual
			end
			local point, direction = Lane.pointAt(view.points, item.d)
			visual.model:PivotTo(CFrame.lookAlong(point, direction) * visual.offset)
		end
	end
end

function FactoryController.init()
	container.Parent = workspace
	local placed = workspace:WaitForChild("Placed")
	placed.ChildAdded:Connect(track)
	placed.ChildRemoved:Connect(untrack)
	for _, model in placed:GetChildren() do
		track(model)
	end
	Remotes.FactorySync.OnClientEvent:Connect(onSync)
	RunService.RenderStepped:Connect(render)
end

return FactoryController
