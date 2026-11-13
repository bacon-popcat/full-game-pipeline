--!strict
-- ResearchSky: the night field behind the Research tree (ResearchView.Research.Sky, authored by
-- tools/hud/polish_hud.luau), in the loading screen's look but livelier. Under Sky, back to front:
-- Nebulae, a few huge soft clouds (Shared/Icons' Nebula) that drift, turn and breathe, the first
-- tinted like the glow; Glow, a radial light leaning toward the colour the screen asks for (the
-- fan in view); Far and Mid, small stars that twinkle; Near, glowing seed motes that rise; Streaks,
-- shooting stars that cross now and then; and Vignette, darkening the corners over it all. Every
-- layer moves with the canvas at its own rate as it pans and zooms (the nebulae least, the motes
-- most), the stars and motes wrapping round the screen so the field never runs out.
--
-- Invariants:
-- * The pool is fixed when bound (LAYERS, the authored nebulae and streaks); nothing is made or
--   destroyed after that. On the Low lighting quality (Lighting.quality, docs/lighting.md) every
--   other star, all the motes and the shooting stars rest hidden, and the nebulae stop turning.
-- * Nothing in it catches input: every node is a plain Frame or ImageLabel left inactive.
-- * Its RenderStepped connection exists only between start and stop, which the screen calls as
--   it opens and once its closing ripple has finished. Each frame it reads the view once from the
--   screen (`view`): the canvas focus and zoom, the tint, and how far faded in the whole sky is (0
--   gone, 1 shown), which the screen eases with its ripple. The ripple leaves Sky alone, so this is
--   the only writer of every transparency under it.
-- * Star positions are rewritten only on frames where the view moved; no table, closure or
--   instance is made per frame.
-- * Reduced motion: the field holds still (no twinkle, drift, turn or shooting stars) but still
--   follows the canvas and fades with the view.
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Lighting = require(script.Parent.Lighting)

-- Stars per layer, how much each follows the canvas (1 would move with it), their opacity and
-- size range (pixels).
local LAYERS = {
	{ name = "Far", count = 34, follow = 0.08, opacity = 0.6, size = { 1.5, 2.5 } },
	{ name = "Mid", count = 22, follow = 0.22, opacity = 0.85, size = { 2, 3.5 } },
	{ name = "Near", count = 12, follow = 0.45, opacity = 0.85, size = { 9, 16 } },
}
-- How much the nebulae and the glow follow the canvas.
local NEBULA_FOLLOW, GLOW_FOLLOW = 0.04, 0.02
-- Pixels round the screen the field wraps through, so a star never pops at an edge.
local MARGIN = 24
-- How fast motes rise (shares of the screen's height a second), and the twinkle's speed range.
local RISE = { 0.012, 0.03 }
local TWINKLE = { 0.7, 2.6 }
-- How quickly the tint follows the view (per second).
local TINT_RATE = 2.5
-- Seconds between shooting stars, how long one takes to cross, and how far it goes (shares of
-- the screen's width).
local STREAK_EVERY, STREAK_FOR, STREAK_REACH = { 1.6, 4.2 }, 0.75, 0.55

type Star = {
	frame: GuiObject,
	image: boolean,
	u: number,
	v: number,
	size: number,
	phase: number,
	speed: number,
	rise: number,
	shown: boolean,
}
type Layer = { follow: number, opacity: number, stars: { Star }, drifting: boolean }
type Cloud = {
	image: ImageLabel,
	base: number,
	position: UDim2,
	rotation: number,
	phase: number,
	tinted: boolean,
}
type Streak = {
	image: ImageLabel,
	base: number,
	age: number,
	from: Vector2,
	way: Vector2,
	flying: boolean,
}
type Shade = { image: ImageLabel, base: number }

local ResearchSky = {}

-- Binds the sky. `view` returns the canvas focus (canvas pixels) and zoom, the tint and the fade.
-- Returns `start`, `stop` and `cleanup`.
function ResearchSky.bind(
	sky: GuiObject,
	star: GuiObject,
	mote: GuiObject,
	view: () -> (Vector2, number, Color3, number)
): (() -> (), () -> (), () -> ())
	local random = Random.new()
	local layers: { Layer } = {}
	for _, spec in LAYERS do
		local holder = sky:FindFirstChild(spec.name)
		if not holder then
			continue
		end
		local drifting = spec.name == "Near"
		local layer: Layer = { follow = spec.follow, opacity = spec.opacity, stars = {}, drifting = drifting }
		for index = 1, spec.count do
			local frame = (if drifting then mote else star):Clone()
			frame.Name = (if drifting then "Mote" else "Star") .. index
			frame.Active = false
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Parent = holder
			table.insert(layer.stars, {
				frame = frame,
				image = frame:IsA("ImageLabel"),
				u = random:NextNumber(),
				-- denser toward the top, like the loading screen's sky
				v = if drifting then random:NextNumber() else random:NextNumber() ^ 1.25,
				size = random:NextNumber(spec.size[1], spec.size[2]),
				phase = random:NextNumber(0, math.pi * 2),
				speed = random:NextNumber(TWINKLE[1], TWINKLE[2]),
				rise = if drifting then random:NextNumber(RISE[1], RISE[2]) else 0,
				shown = true,
			})
		end
		table.insert(layers, layer)
	end
	local clouds: { Cloud } = {}
	local nebulae = sky:FindFirstChild("Nebulae")
	if nebulae then
		for index, cloud in nebulae:GetChildren() do
			if cloud:IsA("ImageLabel") then
				table.insert(clouds, {
					image = cloud,
					base = cloud.ImageTransparency,
					position = cloud.Position,
					rotation = cloud.Rotation,
					phase = index * 1.7,
					tinted = cloud:GetAttribute("Tinted") == true,
				})
			end
		end
	end
	local streaks: { Streak } = {}
	local streakHolder = sky:FindFirstChild("Streaks")
	if streakHolder then
		for _, streak in streakHolder:GetChildren() do
			if streak:IsA("ImageLabel") then
				table.insert(streaks, {
					image = streak,
					base = streak.ImageTransparency,
					age = 0,
					from = Vector2.zero,
					way = Vector2.zero,
					flying = false,
				})
				streak.Visible = false
			end
		end
	end
	local found = sky:FindFirstChild("Glow")
	local glow: Shade? = if found and found:IsA("ImageLabel")
		then { image = found, base = found.ImageTransparency }
		else nil
	local glowPosition = if found and found:IsA("GuiObject") then found.Position else UDim2.new()
	local glowSize = if found and found:IsA("GuiObject") then found.Size else UDim2.new()
	found = sky:FindFirstChild("Vignette")
	local vignette: Shade? = if found and found:IsA("ImageLabel")
		then { image = found, base = found.ImageTransparency }
		else nil

	local connection: RBXScriptConnection? = nil
	local clock = 0
	local low = false
	local nextStreak = 1
	local lastFocus, lastScale, lastSize = Vector2.new(math.huge, 0), 0, Vector2.zero
	local tintR, tintG, tintB = -1, 0, 0

	local function place(screen: Vector2, focus: Vector2, scale: number)
		local width, height = screen.X + MARGIN * 2, screen.Y + MARGIN * 2
		local middle = screen / 2
		for _, layer in layers do
			-- the layer's own zoom, a fraction of the canvas's
			local zoom = scale ^ layer.follow
			local shiftX, shiftY = focus.X * scale * layer.follow, focus.Y * scale * layer.follow
			for _, each in layer.stars do
				if not each.shown then
					continue
				end
				local x = (each.u * width - shiftX) % width - MARGIN
				local y = (each.v * height - shiftY) % height - MARGIN
				x = middle.X + (x - middle.X) * zoom
				y = middle.Y + (y - middle.Y) * zoom
				local side = each.size * (0.7 + 0.3 * zoom)
				each.frame.Position = UDim2.fromOffset(x, y)
				each.frame.Size = UDim2.fromOffset(side, side)
			end
		end
	end

	-- A shooting star sets off from somewhere in the upper sky, slanting down left or right.
	local function launch(streak: Streak, screen: Vector2)
		local leftward = random:NextNumber() < 0.5
		local angle = math.rad(random:NextNumber(14, 34))
		streak.way = Vector2.new(if leftward then -math.cos(angle) else math.cos(angle), math.sin(angle))
		streak.from = Vector2.new(random:NextNumber(0.15, 0.85) * screen.X, random:NextNumber(0.04, 0.4) * screen.Y)
		streak.age = 0
		streak.flying = true
		streak.image.Rotation = math.deg(math.atan2(streak.way.Y, streak.way.X))
		streak.image.Visible = true
	end

	local function step(dt: number)
		local focus, scale, tint, fade = view()
		local calm = not GuiService.ReducedMotionEnabled
		if calm then
			clock += dt
		end
		local screen = sky.AbsoluteSize
		local moved = (focus - lastFocus).Magnitude > 0.01 or math.abs(scale - lastScale) > 1e-4 or screen ~= lastSize
		-- motes drift on their own, so their layer moves every frame
		for _, layer in layers do
			if layer.drifting and calm and not low then
				for _, each in layer.stars do
					each.v = (each.v - each.rise * dt) % 1
				end
				moved = true
			end
		end
		if moved then
			lastFocus, lastScale, lastSize = focus, scale, screen
			place(screen, focus, scale)
		end
		for _, layer in layers do
			for _, each in layer.stars do
				if each.shown then
					local twinkle = if calm then 0.5 + 0.5 * math.sin(clock * each.speed + each.phase) else 0.8
					local glowing = layer.opacity * (0.35 + 0.65 * twinkle)
					if layer.drifting then
						-- a mote fades in as it rises from the bottom and out near the top
						glowing *= math.sin(math.clamp(1 - each.v, 0, 1) * math.pi)
					end
					local value = 1 - glowing * fade
					if each.image then
						(each.frame :: ImageLabel).ImageTransparency = value
					else
						each.frame.BackgroundTransparency = value
					end
				end
			end
		end

		local blend = if tintR < 0 or not calm then 1 else 1 - math.exp(-dt * TINT_RATE)
		local r = if tintR < 0 then tint.R else tintR + (tint.R - tintR) * blend
		local g = if tintR < 0 then tint.G else tintG + (tint.G - tintG) * blend
		local b = if tintR < 0 then tint.B else tintB + (tint.B - tintB) * blend
		if math.abs(r - tintR) + math.abs(g - tintG) + math.abs(b - tintB) > 0.002 then
			tintR, tintG, tintB = r, g, b
			local color = Color3.new(r, g, b)
			if glow then
				glow.image.ImageColor3 = color
			end
			for _, cloud in clouds do
				if cloud.tinted then
					cloud.image.ImageColor3 = color
				end
			end
		end

		local panX, panY = -focus.X * scale, -focus.Y * scale
		for _, cloud in clouds do
			local sway = if calm then clock * 0.05 + cloud.phase else cloud.phase
			local x = math.sin(sway) * 30 + panX * NEBULA_FOLLOW
			local y = math.cos(sway * 0.8) * 22 + panY * NEBULA_FOLLOW
			cloud.image.Position = cloud.position + UDim2.fromOffset(x, y)
			if calm and not low then
				cloud.image.Rotation = cloud.rotation + clock * (if cloud.phase % 2 < 1 then 1.2 else -0.9)
			end
			local breath = if calm then 0.5 + 0.5 * math.sin(clock * 0.35 + cloud.phase) else 0.5
			cloud.image.ImageTransparency = 1 - (1 - cloud.base) * (0.7 + 0.3 * breath) * fade
		end
		if glow then
			local pulse = if calm then 1 + 0.05 * math.sin(clock * 0.9) else 1
			glow.image.Position = glowPosition + UDim2.fromOffset(panX * GLOW_FOLLOW, panY * GLOW_FOLLOW)
			glow.image.Size = UDim2.fromScale(glowSize.X.Scale * pulse, glowSize.Y.Scale * pulse)
			glow.image.ImageTransparency = 1 - (1 - glow.base) * fade
		end
		if vignette then
			vignette.image.ImageTransparency = 1 - (1 - vignette.base) * fade
		end

		if calm and not low and #streaks > 0 then
			nextStreak -= dt
			if nextStreak <= 0 then
				nextStreak = random:NextNumber(STREAK_EVERY[1], STREAK_EVERY[2])
				for _, streak in streaks do
					if not streak.flying then
						launch(streak, screen)
						break
					end
				end
			end
		end
		for _, streak in streaks do
			if streak.flying then
				streak.age += dt
				local alpha = streak.age / STREAK_FOR
				if alpha >= 1 or not calm then
					streak.flying = false
					streak.image.Visible = false
				else
					-- quick off the mark, slowing as it burns out
					local travelled = (1 - (1 - alpha) ^ 2) * STREAK_REACH * screen.X
					local at = streak.from + streak.way * travelled
					streak.image.Position = UDim2.fromOffset(at.X, at.Y)
					local bright = math.sin(alpha * math.pi)
					streak.image.ImageTransparency = 1 - (1 - streak.base) * bright * fade
				end
			end
		end
	end

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		for _, streak in streaks do
			streak.flying = false
			streak.image.Visible = false
		end
	end

	local function start()
		low = Lighting.quality() == "Low"
		for _, layer in layers do
			for index, each in layer.stars do
				each.shown = not low or (not layer.drifting and index % 2 == 0)
				each.frame.Visible = each.shown
			end
		end
		lastFocus = Vector2.new(math.huge, 0)
		nextStreak = random:NextNumber(0.6, 1.4)
		step(0)
		if not connection then
			connection = RunService.RenderStepped:Connect(step)
		end
	end

	return start,
		stop,
		function()
			stop()
			for _, layer in layers do
				for _, each in layer.stars do
					each.frame:Destroy()
				end
			end
			table.clear(layers)
		end
end

return ResearchSky
