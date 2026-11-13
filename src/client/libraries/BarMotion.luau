--!strict
-- BarMotion: progress bars and counters that ease to a new value instead of snapping. A screen
-- calls `bar` with a fill and its share (0 to 1) every time it renders, however often; the fill's
-- width (its Size.X.Scale, height kept) glides there. `count` does the same for a number written
-- into a label through the screen's own `format`.
--
-- Rules, so a bar rendered every frame (a machine's job, the running research) stays cheap and
-- honest:
-- * A bar seen for the first time fills from empty.
-- * A small step (under STEP) is written at once, unless a glide is already on its way to about
--   that value, which is left to finish; only a real jump starts a glide. So steady progress makes
--   no tweens, and a glide is never restarted every frame.
-- * A big drop (a job cycle starting again, a daily reset) snaps rather than draining backwards.
-- * A counter seen for the first time is written as it is, with no count-up.
-- * Reduced motion: everything is written at once.
-- Bars are held in a weak table, so a destroyed row lets go of its state. A counter keeps an
-- unparented NumberValue (what its tween drives) for as long as its label lives; counters are
-- for long-lived rows, not for labels made per render.
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local GLIDE = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local COUNT = TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
-- Shares under which a change is a step, not a jump, and over which a drop snaps.
local STEP, DROP = 0.03, 0.5

type Bar = { target: number, tween: Tween? }
type Counter = { value: NumberValue, target: number, format: (number) -> string, tween: Tween? }

local bars: { [GuiObject]: Bar } = setmetatable({}, { __mode = "k" }) :: any
local counters: { [TextLabel]: Counter } = setmetatable({}, { __mode = "k" }) :: any

local BarMotion = {}

local function playing(tween: Tween?): boolean
	return tween ~= nil and tween.PlaybackState == Enum.PlaybackState.Playing
end

-- Eases `fill`'s width to `share` of its track.
function BarMotion.bar(fill: GuiObject, share: number)
	share = math.clamp(share, 0, 1)
	local size = fill.Size
	local state = bars[fill]
	if not state then
		state = { target = share, tween = nil }
		bars[fill] = state
		if not GuiService.ReducedMotionEnabled and share > 0 then
			fill.Size = UDim2.new(0, size.X.Offset, size.Y.Scale, size.Y.Offset)
			local tween = TweenService:Create(
				fill,
				GLIDE,
				{ Size = UDim2.new(share, size.X.Offset, size.Y.Scale, size.Y.Offset) }
			)
			state.tween = tween
			tween:Play()
			return
		end
	end
	if playing(state.tween) and math.abs(share - state.target) < STEP then
		return
	end
	local shown = size.X.Scale
	state.target = share
	if state.tween then
		state.tween:Cancel()
		state.tween = nil
	end
	local goal = UDim2.new(share, size.X.Offset, size.Y.Scale, size.Y.Offset)
	if GuiService.ReducedMotionEnabled or math.abs(share - shown) < STEP or share < shown - DROP then
		if shown ~= share then
			fill.Size = goal
		end
		return
	end
	local tween = TweenService:Create(fill, GLIDE, { Size = goal })
	state.tween = tween
	tween:Play()
end

-- Counts `label` up (or down) to `value`, writing each step with `format`.
function BarMotion.count(label: TextLabel, value: number, format: (number) -> string)
	local state = counters[label]
	if not state then
		local holder = Instance.new("NumberValue")
		holder.Value = value
		local created: Counter = { value = holder, target = value, format = format, tween = nil }
		holder.Changed:Connect(function(current: number)
			label.Text = created.format(math.round(current))
		end)
		counters[label] = created
		label.Text = format(value)
		return
	end
	state.format = format
	if value == state.target then
		if not playing(state.tween) then
			label.Text = format(value)
		end
		return
	end
	state.target = value
	if state.tween then
		state.tween:Cancel()
		state.tween = nil
	end
	if GuiService.ReducedMotionEnabled then
		state.value.Value = value
		label.Text = format(value)
		return
	end
	local tween = TweenService:Create(state.value, COUNT, { Value = value })
	state.tween = tween
	tween:Play()
end

return BarMotion
