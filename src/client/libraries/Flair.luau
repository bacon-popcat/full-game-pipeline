--!strict
-- Flair: one-off moments on HUD pieces, for screens to call when something happens. The pieces it
-- clones are authored by tools/hud/polish_hud.luau: Assets.UI.Flair.Flash (a bright band that
-- sweeps across whatever it is put in) and Assets.UI.Flair.Spark, drawn on HUD.Fx, a clear layer
-- over every window (ZIndex 60).
--
--   pulse(object)          a confirmation: the object pops (on its UIScale, added once if missing)
--                          and springs back while a flash sweeps across it (not across a label,
--                          where a band over the text reads as a smudge).
--   refuse(object, warn?)  a refusal: the object shakes side to side, damped (its Position, so it
--                          must be one a list does not place), and `warn`, a label such as the
--                          cost, turns TextColors.BAD and fades back.
--   burst(object, color)   sparks fly out of the object's middle, spinning and shrinking away.
--   attention(object)      an idle beat for something waiting on the player (a claim badge): it
--                          pulses on its UIScale until the returned stop is called.
--
-- Invariants: everything settles where it started (a pop, shake or pulse caught by another restarts
-- from the resting value it captured first, not from mid-motion); nothing touches Visible, Active or
-- Interactable; reduced motion skips all of it except refuse's colour, which carries the meaning.
-- The sparks are a fixed pool per HUD (SPARKS), made the first time they are wanted and reused
-- oldest first; every motion is a tween, with no per-frame Lua.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextColors = require(ReplicatedStorage.Shared.TextColors)

local POP_UP = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_BACK = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local FLASH = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHAKE = TweenInfo.new(0.42, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local WARN_BACK = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BEAT = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- How far a pulse pops, how far a refusal first throws (pixels), and an attention beat's swell.
local POP, THROW, SWELL = 1.14, 12, 1.16
-- Sparks in each HUD's pool, and how far and long they fly.
local SPARKS, REACH, FLIGHT = 24, 70, 0.6

type Pool = { layer: GuiObject, sparks: { ImageLabel }, next: number }

local rests: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local places: { [Instance]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local colors: { [Instance]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local pools: { [Instance]: Pool } = setmetatable({}, { __mode = "k" }) :: any

local Flair = {}

local function asset(name: string): GuiObject?
	local found: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, step in { "UI", "Flair", name } do
		found = if found then found:FindFirstChild(step) else nil
	end
	return if found and found:IsA("GuiObject") then found else nil
end

local function scaleOf(object: GuiObject): UIScale
	local scale = object:FindFirstChildOfClass("UIScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Parent = object
		scale = created
	end
	assert(scale, "UIScale was just ensured")
	if rests[scale] == nil then
		rests[scale] = scale.Scale
	end
	return scale
end

function Flair.pulse(object: GuiObject)
	if GuiService.ReducedMotionEnabled then
		return
	end
	local scale = scaleOf(object)
	local rest = rests[scale]
	local up = TweenService:Create(scale, POP_UP, { Scale = rest * POP })
	up.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(scale, POP_BACK, { Scale = rest }):Play()
		end
	end)
	up:Play()
	local template = asset("Flash")
	if template and not object:IsA("TextLabel") then
		local flash = template:Clone()
		local gradient = flash:FindFirstChildOfClass("UIGradient")
		flash.Parent = object
		local fade = TweenService:Create(flash, FLASH, { BackgroundTransparency = 1 })
		if gradient then
			gradient.Offset = Vector2.new(-1, 0)
			TweenService:Create(gradient, FLASH, { Offset = Vector2.new(1, 0) }):Play()
		end
		fade.Completed:Connect(function()
			flash:Destroy()
		end)
		fade:Play()
	end
end

function Flair.refuse(object: GuiObject, warn: TextLabel?)
	if warn then
		if colors[warn] == nil then
			colors[warn] = warn.TextColor3
		end
		local color = colors[warn]
		warn.TextColor3 = TextColors.BAD
		local back = TweenService:Create(warn, WARN_BACK, { TextColor3 = color })
		back:Play()
	end
	if GuiService.ReducedMotionEnabled then
		return
	end
	if places[object] == nil then
		places[object] = object.Position
	end
	local place = places[object]
	-- thrown to one side and let go: the elastic ease swings it back and forth to rest
	object.Position = place + UDim2.fromOffset(THROW, 0)
	TweenService:Create(object, SHAKE, { Position = place }):Play()
end

local function poolOf(object: GuiObject): Pool?
	local screen = object:FindFirstAncestorOfClass("ScreenGui")
	local layer = if screen then screen:FindFirstChild("Fx") else nil
	if not screen or not layer or not layer:IsA("GuiObject") then
		return nil
	end
	local pool = pools[screen]
	if pool then
		return pool
	end
	local template = asset("Spark")
	if not template or not template:IsA("ImageLabel") then
		return nil
	end
	local made: Pool = { layer = layer, sparks = {}, next = 1 }
	for index = 1, SPARKS do
		local spark = template:Clone() :: ImageLabel
		spark.Name = "Spark" .. index
		spark.Visible = false
		spark.Parent = layer
		table.insert(made.sparks, spark)
	end
	pools[screen] = made
	return made
end

function Flair.burst(object: GuiObject, color: Color3, count: number?)
	if GuiService.ReducedMotionEnabled then
		return
	end
	local pool = poolOf(object)
	if not pool then
		return
	end
	local origin = object.AbsolutePosition + object.AbsoluteSize / 2 - pool.layer.AbsolutePosition
	local many = math.min(count or 10, #pool.sparks)
	for index = 1, many do
		local spark = pool.sparks[pool.next]
		pool.next = pool.next % #pool.sparks + 1
		local angle = (index / many + math.random() * 0.1) * math.pi * 2
		local distance = REACH * (0.6 + math.random() * 0.6)
		local side = math.random(16, 28)
		local seconds = FLIGHT * (0.8 + math.random() * 0.4)
		spark.ImageColor3 = color:Lerp(Color3.new(1, 1, 1), math.random() * 0.4)
		spark.Position = UDim2.fromOffset(origin.X, origin.Y)
		spark.Size = UDim2.fromOffset(side, side)
		spark.Rotation = 0
		spark.ImageTransparency = 0
		spark.Visible = true
		-- out fast and slowing, while it holds its size and only shrinks and fades at the end
		local flight =
			TweenService:Create(spark, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(
					origin.X + math.cos(angle) * distance,
					origin.Y + math.sin(angle) * distance - 10
				),
				Rotation = math.random(-200, 200),
			})
		TweenService:Create(spark, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromOffset(2, 2),
			ImageTransparency = 0.5,
		}):Play()
		flight.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				spark.Visible = false
			end
		end)
		flight:Play()
	end
end

-- Starts the idle beat; returns its stop, which puts the scale back.
function Flair.attention(object: GuiObject): () -> ()
	if GuiService.ReducedMotionEnabled then
		return function() end
	end
	local scale = scaleOf(object)
	local rest = rests[scale]
	scale.Scale = rest
	local beat = TweenService:Create(scale, BEAT, { Scale = rest * SWELL })
	beat:Play()
	return function()
		beat:Cancel()
		scale.Scale = rest
	end
end

return Flair
