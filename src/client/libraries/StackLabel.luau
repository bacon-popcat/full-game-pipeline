-- StackLabel: the count badge over a stack of items in the world, a loose drop (DropController)
-- or a stack riding a belt (FactoryController), so the two read the same. One item shows no
-- badge. A count that grows pops the badge; reduced motion skips the pop.
--
-- The badge is ReplicatedStorage.Assets.UI.Stack.Count: a BillboardGui with a TextLabel named
-- Label somewhere inside it, authored in Studio, and its size and offset are the authored
-- ones. Until it is authored a plain dark pill stands in, silently, since that is expected.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NAME = "StackCount"
-- Studs above the top of the stack the stand-in badge floats.
local LIFT = 0.6
-- How much bigger a badge starts when its count grows, and how it settles back.
local POP_SCALE = 1.3
local POP_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local StackLabel = {}

local function template(): BillboardGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local folder = ui and ui:FindFirstChild("Stack")
	local count = folder and folder:FindFirstChild("Count")
	if count and count:IsA("BillboardGui") and count:FindFirstChild("Label", true) then
		return count
	end
	return nil
end

-- The stand-in: a dark rounded pill with the count in white.
local function plain(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(46, 22)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = Color3.fromRGB(40, 36, 32)
	pill.BackgroundTransparency = 0.25
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 250, 240)
	label.Parent = pill
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.Parent = label
	return gui
end

local function adorneeOf(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Shows `count` over `model`, or removes its badge when `count` is one or less. Call it again
-- whenever the count changes; the badge is kept and its text updated.
function StackLabel.set(model: Model, count: number)
	local existing = model:FindFirstChild(NAME)
	local adornee = adorneeOf(model)
	if count <= 1 or not adornee then
		if existing then
			existing:Destroy()
		end
		return
	end
	local gui = if existing and existing:IsA("BillboardGui") then existing else nil
	local previous = if gui then gui:GetAttribute("Count") else nil
	if not gui then
		local authored = template()
		local made = if authored then authored:Clone() else plain()
		made.Name = NAME
		made:SetAttribute("BaseSize", made.Size)
		made:SetAttribute("Authored", authored ~= nil)
		made.Parent = model
		gui = made
	end
	assert(gui, "a badge was made")
	gui.Adornee = adornee
	if gui:GetAttribute("Authored") ~= true then
		-- Over the top of the stack, which grows with its count.
		local height = model:GetExtentsSize().Magnitude / 2
		gui.StudsOffsetWorldSpace = Vector3.new(0, height + LIFT, 0)
	end
	gui:SetAttribute("Count", count)
	local label = gui:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		label.Text = `x{count}`
	end
	local base = gui:GetAttribute("BaseSize")
	if
		typeof(previous) == "number"
		and count > previous
		and typeof(base) == "UDim2"
		and not GuiService.ReducedMotionEnabled
	then
		gui.Size = UDim2.new(
			base.X.Scale * POP_SCALE,
			base.X.Offset * POP_SCALE,
			base.Y.Scale * POP_SCALE,
			base.Y.Offset * POP_SCALE
		)
		TweenService:Create(gui, POP_TWEEN, { Size = base }):Play()
	end
end

-- Hides or shows a model's badge without removing it.
function StackLabel.setVisible(model: Model, visible: boolean)
	local gui = model:FindFirstChild(NAME)
	if gui and gui:IsA("BillboardGui") then
		gui.Enabled = visible
	end
end

return StackLabel
