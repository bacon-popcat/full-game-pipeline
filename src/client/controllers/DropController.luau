-- DropController: how loose drops in Workspace.Drops look beyond their physics. A stack of
-- more than one item gets a count label over it, and a drop that is picked up or merged
-- (DropService fires DropCollected) is drawn being sucked into its target -- a player, the
-- stack it joined or the belt that pulled it on: a local copy
-- flies in on an ease-in arc, shrinking and fading, while the real one is hidden for the
-- moment it lingers on the server. Nothing here changes the game; the server already has.
-- Reduced motion fades the copy where it lies instead of flying it.
--
-- The label is ReplicatedStorage.Assets.UI.Drop.Count (a BillboardGui with a TextLabel
-- named Label), authored in Studio; without it a plain label stands in. That fallback is
-- expected until the template is authored, so it is silent.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Seconds a collected drop takes to reach its target.
local FLIGHT_TIME = 0.35
-- Seconds a collected drop takes to fade where it lies, with reduced motion.
local FADE_TIME = 0.2
-- How high the flight arcs, in studs at its midpoint.
local ARC = 0.8
-- What a copy shrinks to by the time it arrives, as a fraction of its size.
local END_SCALE = 0.2
-- What a copy leaving a stack that stays starts at, as a fraction of the stack's size.
local PART_SCALE = 0.7
-- Turns a copy spins through on its way in.
local SPIN = 1
-- Studs from the camera beyond which a collected drop isn't drawn.
local DRAW_DISTANCE = 150
local LABEL_NAME = "DropCount"

local DropController = {}

local function labelTemplate(): BillboardGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local folder = ui and ui:FindFirstChild("Drop")
	local template = folder and folder:FindFirstChild("Count")
	if template and template:IsA("BillboardGui") and template:FindFirstChild("Label") then
		return template
	end
	return nil
end

-- A plain stand-in for the authored label, so stacks read before it exists.
local function plainLabel(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 24)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	gui.MaxDistance = 40
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	return gui
end

local function refreshLabel(model: Model)
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return
	end
	local count = model:GetAttribute("Count")
	local existing = root:FindFirstChild(LABEL_NAME)
	if typeof(count) ~= "number" or count <= 1 then
		if existing then
			existing:Destroy()
		end
		return
	end
	local gui = existing
	if not gui then
		local template = labelTemplate()
		local made = if template then template:Clone() else plainLabel()
		made.Name = LABEL_NAME
		made.Adornee = root
		made.Parent = root
		gui = made
	end
	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = `x{count}`
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Count"):Connect(function()
		refreshLabel(model)
	end)
	-- The root can stream in after the model.
	model.ChildAdded:Connect(function()
		refreshLabel(model)
	end)
	refreshLabel(model)
end

local function setHidden(model: Model, hidden: boolean)
	for _, node in model:GetDescendants() do
		if node:IsA("BasePart") then
			node.LocalTransparencyModifier = if hidden then 1 else 0
		elseif node:IsA("BillboardGui") then
			node.Enabled = not hidden
		end
	end
end

-- A copy of `model` that only this client sees, anchored and out of every query, with the
-- transparency each part started at.
local function ghostOf(model: Model): (Model, { [BasePart]: number })
	local ghost = model:Clone()
	local start: { [BasePart]: number } = {}
	for _, node in ghost:GetDescendants() do
		if node:IsA("BasePart") then
			node.Anchored = true
			node.CanCollide = false
			node.CanQuery = false
			node.CanTouch = false
			node.LocalTransparencyModifier = 0
			start[node] = node.Transparency
		elseif node:IsA("BillboardGui") or node:IsA("JointInstance") or node:IsA("WeldConstraint") then
			node:Destroy()
		end
	end
	return ghost, start
end

local function onCollected(model: unknown, target: unknown, whole: unknown)
	local camera = workspace.CurrentCamera
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.PrimaryPart or not camera then
		return
	end
	local from = model:GetPivot()
	if (from.Position - camera.CFrame.Position).Magnitude > DRAW_DISTANCE then
		return
	end
	local ghost, start = ghostOf(model)
	if whole == true then
		setHidden(model, true)
	end
	local scale = ghost:GetScale() * (if whole == true then 1 else PART_SCALE)
	ghost:ScaleTo(scale)
	ghost:PivotTo(from)
	ghost.Parent = camera

	local reduced = GuiService.ReducedMotionEnabled
	local duration = if reduced then FADE_TIME else FLIGHT_TIME
	local goal = from.Position
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1)
		-- Ease in: it drifts at first, then is pulled in fast, like being sucked up.
		local pull = alpha * alpha
		if typeof(target) == "Vector3" then
			goal = target
		elseif typeof(target) == "Instance" and target:IsA("BasePart") and target:IsDescendantOf(workspace) then
			goal = target.Position
		end
		if not reduced then
			local position = from.Position:Lerp(goal, pull) + Vector3.yAxis * ARC * math.sin(alpha * math.pi)
			ghost:ScaleTo(scale * (1 - (1 - END_SCALE) * pull))
			ghost:PivotTo(CFrame.new(position) * from.Rotation * CFrame.Angles(0, SPIN * 2 * math.pi * pull, 0))
		end
		for part, transparency in start do
			part.Transparency = transparency + (1 - transparency) * (if reduced then alpha else pull)
		end
		if alpha >= 1 then
			connection:Disconnect()
			ghost:Destroy()
		end
	end)
end

function DropController.init()
	local folder = workspace:WaitForChild("Drops")
	folder.ChildAdded:Connect(watch)
	for _, model in folder:GetChildren() do
		watch(model)
	end
	Remotes.DropCollected.OnClientEvent:Connect(onCollected)
end

return DropController
