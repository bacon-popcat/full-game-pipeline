--!strict
-- Props: places decorative models from ReplicatedStorage.Assets.Props (the hub stalls, plot fences,
-- signs, lamps and flower boxes, built in IslandsMachines/build/garden_props.py). A placed prop is
-- scenery only: it never collides, catches an aim ray or blocks a placement. Its pivot is the
-- bottom centre of its art and its front faces -Z, so callers turn it to face where it should.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Props = {}

function Props.template(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = if assets then assets:FindFirstChild("Props") else nil
	local found = if folder then folder:FindFirstChild(name) else nil
	return if found and found:IsA("Model") then found else nil
end

-- A copy of the prop at `cframe` under `parent`, or nil when the place has no such prop yet.
function Props.place(name: string, cframe: CFrame, parent: Instance): Model?
	local template = Props.template(name)
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model:PivotTo(cframe)
	model.Parent = parent
	return model
end

-- The first part of a prop whose name ends in `_<key>` (an art part key, such as Counter or Board).
function Props.part(model: Model, key: string): BasePart?
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and string.sub(part.Name, -#key - 1) == "_" .. key then
			return part
		end
	end
	return nil
end

return Props
