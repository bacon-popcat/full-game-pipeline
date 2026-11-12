-- LoadingScreen: the first thing a joining player sees, in place of Roblox's default screen,
-- until their garden is open (DataReady) or the save menu is waiting for a choice.
--
-- It is drawn in code, not authored like the HUD (conventions.md § UI): it runs from
-- ReplicatedFirst before StarterGui and ReplicatedStorage.Assets have arrived, so there is no
-- template to clone yet. Everything it makes is one ScreenGui, destroyed when it leaves.
--
-- The look is the HUD's (near-black, thin strokes, white corner brackets, Sarpanch) over a night
-- field that turns to dawn as loading goes on: the name drops in letter by letter round a turning
-- gear with a sprout in it, a row of seedlings along the hill grows with the progress bar, and
-- fireflies drift up. Progress is three stages, each a share of the bar: the game's content
-- (game.Loaded and ContentProvider's queue), the HUD and character, then the garden. It shows for
-- at least MIN_SHOWN seconds so the title can finish, and never more than MAX_SHOWN.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Brand = require(ReplicatedFirst:WaitForChild("Brand"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MIN_SHOWN = 3.6
local MAX_SHOWN = 30
local TIP_EVERY = 4.5
-- The reference stage, like the HUD's (Hud.REFERENCE_WIDTH x REFERENCE_HEIGHT).
local STAGE = Vector2.new(1280, 720)
local FONT = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Bold)
local FONT_REGULAR = Font.new("rbxasset://fonts/families/Sarpanch.json", Enum.FontWeight.Medium)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(8, 9, 16)
local PANEL = Color3.fromRGB(10, 10, 18)
local EDGE = Color3.fromRGB(205, 205, 220)
local MUTED = Color3.fromRGB(176, 178, 196)
local GOLD = Color3.fromRGB(255, 214, 102)
local LEAF = Color3.fromRGB(126, 214, 120)
local LEAF_DARK = Color3.fromRGB(72, 160, 92)
local SPROUTS = 15
local FIREFLIES = 22
local STARS = 46

local started = os.clock()

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local node = Instance.new(className)
	for key, value in props do
		node[key] = value
	end
	if parent then
		node.Parent = parent
	end
	return node
end

local function corner(parent: Instance, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

local function tween(node: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local playing = TweenService:Create(node, info, props)
	playing:Play()
	return playing
end

-- The HUD's white L-shaped corners round `frame`.
local function brackets(frame: GuiObject, color: Color3, size: number)
	local holder = new("Frame", { Name = "Brackets", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20 }, frame)
	for _, at in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local out = Vector2.new(if at.X == 0 then -3 else 3, if at.Y == 0 then -3 else 3)
		local box = new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = at,
			Position = UDim2.new(at.X, out.X, at.Y, out.Y),
			Size = UDim2.fromOffset(size, size),
			ZIndex = 20,
		}, holder)
		new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			AnchorPoint = at,
			Position = UDim2.fromScale(at.X, at.Y),
			Size = UDim2.new(1, 0, 0, 3),
			ZIndex = 20,
		}, box)
		new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			AnchorPoint = at,
			Position = UDim2.fromScale(at.X, at.Y),
			Size = UDim2.new(0, 3, 1, 0),
			ZIndex = 20,
		}, box)
	end
end

------------------------------------------------------------------------------------------------
-- The scene

local screen = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ScreenInsets = Enum.ScreenInsets.None,
})
-- One group, so leaving is one fade.
local canvas = new("CanvasGroup", {
	Name = "Canvas",
	BorderSizePixel = 0,
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
}, screen)
-- The night sky is its own frame: a UIGradient on the CanvasGroup itself would tint everything in it.
local night = new("Frame", {
	Name = "Night",
	BorderSizePixel = 0,
	BackgroundColor3 = WHITE,
	Size = UDim2.fromScale(1, 1),
}, canvas)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 8, 20)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(16, 20, 42)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 30, 52)),
	}),
}, night)

-- Dawn: a warm glow on the horizon that rises as loading goes on.
local dawn = new("Frame", {
	Name = "Dawn",
	BorderSizePixel = 0,
	BackgroundColor3 = WHITE,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromScale(1, 0.75),
	BackgroundTransparency = 0,
}, canvas)
local dawnGradient = new("UIGradient", {
	Rotation = -90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 176, 110)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(214, 120, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 60, 130)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Offset = Vector2.new(0, 0.55),
}, dawn)

-- Stars: small points in the upper sky that twinkle and fade as dawn comes.
local sky = new("Frame", { Name = "Stars", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.62) }, canvas)
local stars = {}
local random = Random.new()
for _ = 1, STARS do
	local size = random:NextNumber(1.5, 3.5)
	local star = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(230, 232, 255),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(random:NextNumber(), random:NextNumber() ^ 1.4),
		Size = UDim2.fromOffset(size, size),
	}, sky)
	corner(star)
	table.insert(stars, { node = star, phase = random:NextNumber(0, math.pi * 2), speed = random:NextNumber(0.8, 2.2) })
end

-- Hills: three huge circles whose tops make the horizon, sized off the screen's width.
local function hill(name: string, x: number, top: number, diameter: number, color: Color3): Frame
	local node = new("Frame", {
		Name = name,
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(x, top),
		Size = UDim2.fromScale(diameter, diameter),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
	}, canvas)
	corner(node)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(color:Lerp(Color3.fromRGB(255, 200, 150), 0.12), color:Lerp(INK, 0.5)),
		Transparency = NumberSequence.new(0),
	}, node)
	return node
end
local backHill = hill("BackHill", 0.2, 0.64, 1.5, Color3.fromRGB(28, 44, 52))
local midHill = hill("MidHill", 0.85, 0.69, 1.6, Color3.fromRGB(30, 58, 48))
hill("FrontHill", 0.5, 0.845, 2.6, Color3.fromRGB(38, 78, 52))

-- Seedlings along the front hill's crest, one per share of the bar.
local field = new("Frame", { Name = "Field", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, canvas)
local sprouts = {}
for index = 1, SPROUTS do
	local root = new("Frame", {
		Name = "Sprout",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(30, 34),
	}, field)
	local zoom = new("UIScale", {}, root)
	-- The plant inside grows from its base, under the zoom that fits it to the screen.
	local plant = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1),
	}, root)
	local scale = new("UIScale", { Scale = 0 }, plant)
	-- A mound of soil, the stem and two leaves.
	local mound = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(70, 50, 38),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(26, 9),
	}, plant)
	corner(mound)
	new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = LEAF_DARK,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(4, 20),
	}, plant)
	for side = -1, 1, 2 do
		local leaf = new("Frame", {
			BorderSizePixel = 0,
			BackgroundColor3 = LEAF,
			AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
			Position = UDim2.new(0.5, side * 1, 0, 12),
			Size = UDim2.fromOffset(14, 8),
			Rotation = side * -28,
		}, plant)
		corner(leaf)
	end
	table.insert(sprouts, { root = root, zoom = zoom, scale = scale, grown = false, phase = index * 0.7 })
end

-- Fireflies: soft points that rise, sway and fade.
local motes = {}
for _ = 1, FIREFLIES do
	local size = random:NextNumber(3, 6)
	local mote = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = if random:NextNumber() < 0.6 then Color3.fromRGB(255, 226, 130) else Color3.fromRGB(170, 240, 150),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, canvas)
	corner(mote)
	new("UIStroke", { Color = mote.BackgroundColor3, Thickness = 2, Transparency = 0.6 }, mote)
	table.insert(motes, {
		node = mote,
		x = random:NextNumber(),
		life = random:NextNumber(5, 9),
		age = random:NextNumber(0, 8),
		sway = random:NextNumber(0.006, 0.02),
		phase = random:NextNumber(0, math.pi * 2),
	})
end

-- Everything else sits on a stage at the reference size, scaled to fit the screen.
local stage = new("Frame", {
	Name = "Stage",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(STAGE.X, STAGE.Y),
	ZIndex = 5,
}, canvas)
local stageScale = new("UIScale", {}, stage)

-- The logo: a gear turning round a sprout.
local logo = new("Frame", {
	Name = "Logo",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(STAGE.X / 2, 178),
	Size = UDim2.fromOffset(150, 150),
	ZIndex = 5,
}, stage)
local logoScale = new("UIScale", { Scale = 0 }, logo)
-- A soft glow: nested faint discs, so it falls off towards the edge without a gradient's seam.
local halo = new("Frame", {
	Name = "Halo",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(250, 250),
	ZIndex = 5,
}, logo)
for _, share in { 1, 0.82, 0.66, 0.52 } do
	local disc = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.955,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(share, share),
		ZIndex = 5,
	}, halo)
	corner(disc)
end
local TEETH = 10
local GEAR_RADIUS = 52
local teeth = {}
for index = 1, TEETH do
	local tooth = new("Frame", {
		Name = "Tooth",
		BorderSizePixel = 0,
		BackgroundColor3 = GOLD,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(22, 26),
		ZIndex = 6,
	}, logo)
	corner(tooth, UDim.new(0, 4))
	new("UIStroke", { Color = INK, Thickness = 3 }, tooth)
	teeth[index] = tooth
end
local wheel = new("Frame", {
	Name = "Wheel",
	BorderSizePixel = 0,
	BackgroundColor3 = GOLD,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(GEAR_RADIUS * 2, GEAR_RADIUS * 2),
	ZIndex = 7,
}, logo)
corner(wheel)
new("UIStroke", { Color = INK, Thickness = 3 }, wheel)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), Color3.fromRGB(222, 150, 60)),
}, wheel)
local hub = new("Frame", {
	Name = "Hub",
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(20, 26, 30),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(64, 64),
	ZIndex = 8,
}, logo)
corner(hub)
new("UIStroke", { Color = Color3.fromRGB(120, 80, 30), Thickness = 3 }, hub)
-- The sprout in the gear's hub, which grows in after the gear.
local seedling = new("Frame", {
	Name = "Seedling",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.5, 22),
	Size = UDim2.fromOffset(60, 60),
	ZIndex = 9,
}, logo)
local seedlingScale = new("UIScale", { Scale = 0 }, seedling)
new("Frame", {
	BorderSizePixel = 0,
	BackgroundColor3 = LEAF_DARK,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromOffset(6, 40),
	ZIndex = 9,
}, seedling)
local seedLeaves = {}
for side = -1, 1, 2 do
	local leaf = new("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = LEAF,
		AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5),
		Position = UDim2.new(0.5, side * 2, 0, 24),
		Size = UDim2.fromOffset(26, 14),
		Rotation = side * -30,
		ZIndex = 10,
	}, seedling)
	corner(leaf)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(190, 250, 160), LEAF_DARK) }, leaf)
	new("UIStroke", { Color = Color3.fromRGB(20, 50, 28), Thickness = 2 }, leaf)
	seedLeaves[side] = leaf
end

-- The name, one label per letter so each can drop in and wave.
local title = new("Frame", {
	Name = "Title",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(STAGE.X / 2, 316),
	Size = UDim2.fromOffset(0, 104),
	AutomaticSize = Enum.AutomaticSize.X,
	ZIndex = 10,
}, stage)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 2),
}, title)
local titleScale = new("UIScale", {}, title)
local letters = {}
for _, half in Brand.TITLE do
	for character in string.gmatch(half.text, ".") do
		local holder = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = #letters + 1,
			ZIndex = 10,
		}, title)
		local glyph = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = FONT,
			Text = character,
			TextSize = 100,
			TextColor3 = WHITE,
			TextTransparency = 1,
			ZIndex = 11,
		}, holder)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(half.top, half.bottom) }, glyph)
		local stroke = new("UIStroke", { Color = INK, Thickness = 5, Transparency = 1 }, glyph)
		local scale = new("UIScale", {}, glyph)
		-- A soft shadow under each letter.
		local shadow = new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = FONT,
			Text = character,
			TextSize = 100,
			TextColor3 = INK,
			TextTransparency = 1,
			ZIndex = 10,
		}, holder)
		table.insert(letters, { glyph = glyph, stroke = stroke, scale = scale, shadow = shadow, landed = false })
	end
end

local tagline = new("TextLabel", {
	Name = "Tagline",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(STAGE.X / 2, 384),
	Size = UDim2.fromOffset(600, 26),
	FontFace = FONT,
	Text = Brand.TAGLINE,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(226, 220, 255),
	TextTransparency = 1,
	ZIndex = 10,
}, stage)
local taglineStroke = new("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, tagline)

-- The loading panel: status, percent, the bar and a tip, in a HUD-style card.
local panel = new("Frame", {
	Name = "Panel",
	BorderSizePixel = 0,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.15,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromOffset(STAGE.X / 2, 444),
	Size = UDim2.fromOffset(580, 118),
	ZIndex = 10,
}, stage)
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(26, 26, 40), Color3.fromRGB(6, 6, 12)),
}, panel)
new("UIStroke", { Color = EDGE, Thickness = 1, Transparency = 0.55 }, panel)
brackets(panel, WHITE, 16)
local status = new("TextLabel", {
	Name = "Status",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 14),
	Size = UDim2.new(1, -140, 0, 22),
	FontFace = FONT,
	Text = "Waking up the garden",
	TextSize = 18,
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 11,
}, panel)
local percent = new("TextLabel", {
	Name = "Percent",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -24, 0, 14),
	Size = UDim2.fromOffset(100, 22),
	FontFace = FONT,
	Text = "0%",
	TextSize = 18,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 11,
}, panel)
local track = new("Frame", {
	Name = "Track",
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(30, 32, 46),
	Position = UDim2.fromOffset(24, 46),
	Size = UDim2.new(1, -48, 0, 12),
	ClipsDescendants = true,
	ZIndex = 11,
}, panel)
corner(track)
new("UIStroke", { Color = Color3.fromRGB(70, 72, 96), Thickness = 1 }, track)
local fill = new("Frame", {
	Name = "Fill",
	BorderSizePixel = 0,
	BackgroundColor3 = WHITE,
	Size = UDim2.fromScale(0, 1),
	ZIndex = 12,
}, track)
corner(fill)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 210, 120)),
		ColorSequenceKeypoint.new(1, GOLD),
	}),
}, fill)
-- A bright band that sweeps along the fill.
local shine = new("Frame", {
	Name = "Shine",
	BorderSizePixel = 0,
	BackgroundColor3 = WHITE,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 13,
}, fill)
corner(shine)
local shineGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, shine)
local tip = new("TextLabel", {
	Name = "Tip",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 70),
	Size = UDim2.new(1, -48, 0, 36),
	FontFace = FONT_REGULAR,
	Text = "",
	RichText = true,
	TextSize = 16,
	TextWrapped = true,
	TextColor3 = MUTED,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 11,
}, panel)

local flash = new("Frame", {
	Name = "Flash",
	BorderSizePixel = 0,
	BackgroundColor3 = Color3.fromRGB(255, 244, 214),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 50,
}, canvas)

screen.Parent = playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

------------------------------------------------------------------------------------------------
-- Layout and motion

local camera = workspace.CurrentCamera
local function viewport(): Vector2
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- Seedlings sit on the front hill's crest, which is a circle's top arc.
local function layout()
	local size = viewport()
	local zoom = math.min(size.X / STAGE.X, size.Y / STAGE.Y)
	stageScale.Scale = zoom
	local radius = size.X * 1.3
	local top = size.Y * 0.845
	for index, sprout in sprouts do
		local x = size.X * (0.1 + 0.8 * (index - 1) / (SPROUTS - 1))
		local dx = x - size.X / 2
		local y = top + radius - math.sqrt(radius * radius - dx * dx)
		sprout.root.Position = UDim2.fromOffset(x, y + 4 * zoom)
		sprout.zoom.Scale = zoom * 1.2
	end
end
layout()
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end

-- The intro: gear pops, the sprout grows, the letters drop one after another, then the line.
task.spawn(function()
	tween(logoScale, 0.7, { Scale = 1 }, Enum.EasingStyle.Back)
	task.wait(0.35)
	tween(seedlingScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back)
	for index, letter in letters do
		task.delay(0.35 + index * 0.075, function()
			letter.glyph.Position = UDim2.fromOffset(0, -70)
			letter.scale.Scale = 1.4
			tween(letter.glyph, 0.55, { Position = UDim2.new(), TextTransparency = 0 }, Enum.EasingStyle.Back)
			tween(letter.scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(letter.stroke, 0.4, { Transparency = 0 })
			tween(letter.shadow, 0.6, { TextTransparency = 0.55 })
			task.delay(0.55, function()
				letter.landed = true
			end)
		end)
	end
	task.wait(0.4 + #letters * 0.075 + 0.4)
	tween(tagline, 0.6, { TextTransparency = 0 })
	tween(taglineStroke, 0.6, { Transparency = 0.2 })
end)

-- Tips, painted by Shared/TextColors once it has replicated.
local highlight: ((string) -> string)? = nil
local function paintTip(text: string): string
	if not highlight then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("TextColors")
		if module and module:IsA("ModuleScript") then
			local ok, colors = pcall(require, module)
			if ok then
				highlight = colors.highlight
			end
		end
	end
	if highlight then
		local ok, painted = pcall(highlight, text)
		if ok then
			return painted
		end
	end
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
task.spawn(function()
	local order = {}
	for index in Brand.TIPS do
		table.insert(order, random:NextInteger(1, #order + 1), index)
	end
	local at = 0
	task.wait(0.8)
	while screen.Parent do
		at = at % #order + 1
		tip.TextTransparency = 1
		tip.Text = paintTip(Brand.TIPS[order[at]])
		tween(tip, 0.4, { TextTransparency = 0 })
		task.wait(TIP_EVERY)
		tween(tip, 0.3, { TextTransparency = 1 })
		task.wait(0.3)
	end
end)

------------------------------------------------------------------------------------------------
-- Progress

local target = 0
local shown = 0
local finished = false
local stageText = "Loading the world"
local biggestQueue = 1

-- Whether the save menu is up and waiting for a choice rather than opening a garden by itself.
local function menuWaiting(): boolean
	local menu = playerGui:FindFirstChild("SaveMenu")
	local window = menu and menu:FindFirstChild("Window")
	local body = window and window:FindFirstChild("Body")
	local menuStatus = body and body:FindFirstChild("Status")
	local slots = body and body:FindFirstChild("Slots")
	if not (menuStatus and menuStatus:IsA("TextLabel") and slots) then
		return false
	end
	return menuStatus.Text == "" and slots:FindFirstChildWhichIsA("GuiObject") ~= nil
end

local function gardenReady(): boolean
	return player:GetAttribute("DataReady") == true or menuWaiting()
end

local clock = 0
local connection: RBXScriptConnection
connection = RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local size = viewport()
	local zoom = math.min(size.X / STAGE.X, size.Y / STAGE.Y)

	-- Where loading is.
	if not finished then
		if not game:IsLoaded() then
			local queue = ContentProvider.RequestQueueSize
			biggestQueue = math.max(biggestQueue, queue)
			target = math.max(target, 0.5 * (1 - queue / biggestQueue))
			stageText = "Loading the world"
		elseif not (playerGui:FindFirstChild("HUD") and player.Character) then
			target = math.max(target, 0.6)
			stageText = "Waking up the garden"
		elseif not gardenReady() then
			target = math.max(target, 0.75)
			stageText = "Opening your garden"
			-- Creep on while the server loads the save, never reaching the end by itself.
			target = math.min(0.95, target + dt * 0.02)
		else
			target = 1
			stageText = "Ready!"
		end
	end
	shown += (target - shown) * math.min(1, dt * 4)
	if target >= 1 and shown > 0.995 then
		shown = 1
	end
	fill.Size = UDim2.fromScale(shown, 1)
	percent.Text = `{math.floor(shown * 100 + 0.5)}%`
	local dots = string.rep(".", math.floor(clock * 2.5) % 4)
	status.Text = if stageText == "Ready!" then stageText else stageText .. dots
	shineGradient.Offset = Vector2.new(((clock * 0.6) % 1.6) - 0.8, 0)

	-- Dawn rises with the bar; the stars fade with it.
	dawnGradient.Offset = Vector2.new(0, 0.55 - 0.45 * shown)
	for _, star in stars do
		local twinkle = 0.5 + 0.5 * math.sin(clock * star.speed + star.phase)
		star.node.BackgroundTransparency = 0.15 + 0.55 * twinkle + 0.3 * shown
	end

	-- The gear turns; its teeth ride round the wheel.
	local turn = clock * 0.6
	for index, tooth in teeth do
		local angle = turn + (index - 1) * (math.pi * 2 / TEETH)
		tooth.Position = UDim2.new(0.5, math.sin(angle) * GEAR_RADIUS, 0.5, -math.cos(angle) * GEAR_RADIUS)
		tooth.Rotation = math.deg(angle)
	end
	halo.Size = UDim2.fromOffset(250 + math.sin(clock * 1.6) * 14, 250 + math.sin(clock * 1.6) * 14)
	for side, leaf in seedLeaves do
		leaf.Rotation = side * (-30 + math.sin(clock * 1.8) * 6)
	end

	-- The letters bob in a wave once they have landed.
	for index, letter in letters do
		if letter.landed then
			local wave = math.sin(clock * 2.4 - index * 0.55)
			letter.glyph.Position = UDim2.fromOffset(0, wave * 5)
			letter.scale.Scale = 1 + math.max(0, wave) * 0.04
		end
	end

	-- Seedlings grow as the bar passes them, then sway.
	for index, sprout in sprouts do
		if not sprout.grown and shown >= (index - 0.5) / SPROUTS then
			sprout.grown = true
			tween(sprout.scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		if sprout.grown then
			sprout.root.Rotation = math.sin(clock * 1.5 + sprout.phase) * 5
		end
	end

	-- Fireflies drift up from the fields and fade out.
	for _, mote in motes do
		mote.age += dt
		if mote.age >= mote.life then
			mote.age = 0
			mote.x = random:NextNumber()
		end
		local t = mote.age / mote.life
		local x = mote.x + math.sin(clock * 1.3 + mote.phase) * mote.sway
		local y = 0.98 - t * 0.6
		mote.node.Position = UDim2.fromScale(x, y)
		mote.node.BackgroundTransparency = 1 - math.sin(t * math.pi) * 0.85
		mote.node.Size = UDim2.fromOffset(4 * zoom + 2, 4 * zoom + 2)
	end

	-- Parallax: the hills breathe a little.
	backHill.Position = UDim2.fromScale(0.2 + math.sin(clock * 0.2) * 0.01, 0.64)
	midHill.Position = UDim2.fromScale(0.85 - math.sin(clock * 0.25) * 0.012, 0.69)
end)

------------------------------------------------------------------------------------------------
-- Leaving

local function ready(): boolean
	return game:IsLoaded() and playerGui:FindFirstChild("HUD") ~= nil and player.Character ~= nil and gardenReady()
end

repeat
	task.wait(0.1)
until (ready() and os.clock() - started >= MIN_SHOWN) or os.clock() - started >= MAX_SHOWN

finished = true
target = 1
stageText = "Ready!"
task.wait(0.6)
-- A last flourish: the title swells, the screen flashes warm, and the whole thing fades.
tween(titleScale, 0.5, { Scale = 1.08 }, Enum.EasingStyle.Back)
tween(logoScale, 0.5, { Scale = 1.15 }, Enum.EasingStyle.Back)
tween(flash, 0.25, { BackgroundTransparency = 0.55 })
task.wait(0.25)
tween(flash, 0.6, { BackgroundTransparency = 1 })
tween(canvas, 0.8, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
task.wait(0.85)
connection:Disconnect()
screen:Destroy()
