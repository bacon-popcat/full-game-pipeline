--!strict
-- WindowReveal: what plays inside a modal window while PopupMotion pops it open. The window's
-- outline flashes bright and settles; its corner brackets snap in from outside, overshooting, as
-- their arms draw out from the corners; the top Accent springs out from its middle; a light runs
-- once along the header's divider with a spinning glint riding it (Header.Divider.Sweep.Light and
-- Header.Divider.Glint, authored by tools/hud/polish_hud.luau); and the content fades and rises in
-- a quick cascade, top to bottom, each piece springing a little past its place and back. Every
-- piece is optional: a window without one simply skips it.
--
-- The cascade's items are found under Body: the shown children of any list or grid (a frame
-- holding a UIListLayout or UIGridLayout), and the other shown pieces as they stand. A frame that
-- only holds a list further down is looked through, so its own panel stays put while its rows
-- come in. Items outside the window or their scroller are left alone, and the whole cascade ends
-- within TOTAL seconds however long the list is. A window opts out of the cascade (keeping the
-- rest) with the authored attribute Cascade = false, as the Welcome card does, which pops its own
-- parts in; a Vector2 attribute CascadeOffset moves where its pieces come from (the Menu's rows
-- slide in from the left).
--
-- Invariants:
-- * It plays on an open only, never on a re-render: what a window lists after it opened just
--   shows. The items are gathered one deferred step after the open, once the screen's render
--   (which HubWindow runs right after the pop starts) has filled the lists.
-- * It never touches Visible, Interactable or Active (except the glint and light it owns), so
--   nothing waits on it.
-- * A transparency the screen's own code changes mid-reveal is the screen's from then on: each
--   frame checks the value is still the one written last and lets go of it if not.
-- * settle puts back at once everything still held. PopupMotion calls it on every close, on
--   reduced motion and on cleanup, so a window closed and reopened mid-reveal never keeps
--   half-faded content.
-- * The RenderStepped connection exists only while a cascade runs; transparencies are eased in
--   a loop over tables built once at the open, and the UDim2 motion is left to tweens.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Seconds before the first item moves, each item's own fade, and the whole cascade's limit.
local FIRST = 0.04
local ITEM = 0.24
local TOTAL = 0.4
-- The most seconds between two items; a long list draws them closer.
local STAGGER = 0.045
-- Pixels an item rises as it fades in (it springs a little past and back), and how much longer
-- than its fade the spring takes.
local RISE, SPRING = 18, 0.08
-- How deep under Body the cascade looks through frames that only hold a list further down.
local DEPTH = 3
-- A transparency read back further than this from the last one written was changed by the screen.
local EPSILON = 1e-3
local BRACKETS = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0.06)
local SNAP = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.02)
local ACCENT = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.08)
local FLASH = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWEEP = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, 0.1)
-- The glint rides the light only while the light is over the divider (it is not clipped, so it
-- must not stray past the ends): it crosses 0 to 1 as the light does, growing to its size and back
-- and turning as it goes.
local GLINT_TRAVEL = TweenInfo.new(0.28, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.26)
local GLINT = TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true, 0.26)
local GLINT_SPIN = TweenInfo.new(0.28, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.26)
-- Pixels each corner bracket starts outside its place, and the outline's flash thickness.
local SNAP_FROM, FLASH_THICKNESS = 18, 2.5
-- The share of the divider the sweep's light starts and ends at (it is clipped to the divider).
local SWEEP_FROM, SWEEP_TO = -0.25, 1.25
local FADED: { [string]: { string } } = {
	GuiObject = { "BackgroundTransparency" },
	TextLabel = { "TextTransparency" },
	TextButton = { "TextTransparency" },
	TextBox = { "TextTransparency" },
	ImageLabel = { "ImageTransparency" },
	ImageButton = { "ImageTransparency" },
	ViewportFrame = { "ImageTransparency" },
	UIStroke = { "Transparency" },
}

type Fade = { instance: Instance, property: string, base: number, last: number, held: boolean }
type Rise = { object: GuiObject, base: UDim2 }
type Item = { start: number, fades: { Fade } }
type Bar = { object: GuiObject, base: UDim2, from: UDim2 }

local WindowReveal = {}

type Corner = { object: GuiObject, base: UDim2, from: UDim2 }

local function hasLayout(node: Instance): boolean
	return node:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- Whether a list sits somewhere under `node`, within `depth` levels.
local function listBelow(node: Instance, depth: number): boolean
	for _, child in node:GetChildren() do
		if
			child:IsA("GuiObject")
			and child.Visible
			and (hasLayout(child) or (depth > 0 and listBelow(child, depth - 1)))
		then
			return true
		end
	end
	return false
end

local function collect(node: Instance, depth: number, into: { GuiObject })
	for _, child in node:GetChildren() do
		if not child:IsA("GuiObject") or not child.Visible then
			continue
		end
		if hasLayout(child) then
			local before = #into
			for _, entry in child:GetChildren() do
				if entry:IsA("GuiObject") and entry.Visible then
					table.insert(into, entry)
				end
			end
			if #into == before then
				table.insert(into, child)
			end
		elseif depth < DEPTH and listBelow(child, 1) then
			collect(child, depth + 1, into)
		else
			table.insert(into, child)
		end
	end
end

-- The on-screen rectangle `object` can be seen in: its nearest clipping ancestor's, else the window's.
local function viewOf(object: GuiObject, window: GuiObject): (Vector2, Vector2)
	local current = object.Parent
	while current and current ~= window do
		if current:IsA("GuiObject") and (current:IsA("ScrollingFrame") or current.ClipsDescendants) then
			return current.AbsolutePosition, current.AbsolutePosition + current.AbsoluteSize
		end
		current = current.Parent
	end
	return window.AbsolutePosition, window.AbsolutePosition + window.AbsoluteSize
end

local function onScreen(object: GuiObject, window: GuiObject): boolean
	local low, high = viewOf(object, window)
	local from = object.AbsolutePosition
	local to = from + object.AbsoluteSize
	return to.X > low.X and to.Y > low.Y and from.X < high.X and from.Y < high.Y
end

local function addFades(node: Instance, into: { Fade })
	for className, properties in FADED do
		if node:IsA(className) then
			for _, property in properties do
				local base = (node :: any)[property]
				-- already clear: nothing to fade
				if base < 1 then
					table.insert(into, { instance = node, property = property, base = base, last = base, held = true })
				end
			end
		end
	end
end

-- Binds the reveal for `window`; returns `play` (on open) and `settle` (on close, reduced motion
-- and cleanup).
function WindowReveal.bind(window: GuiObject): (() -> (), () -> ())
	local bars: { Bar } = {}
	local corners: { Corner } = {}
	local brackets = window:FindFirstChild("Brackets")
	if brackets then
		for _, corner in brackets:GetChildren() do
			if corner:IsA("GuiObject") then
				-- outward, away from the window's middle, by the corner's anchor
				local out = Vector2.new(corner.AnchorPoint.X * 2 - 1, corner.AnchorPoint.Y * 2 - 1) * SNAP_FROM
				table.insert(corners, {
					object = corner,
					base = corner.Position,
					from = corner.Position + UDim2.fromOffset(out.X, out.Y),
				})
			end
		end
		for _, bar in brackets:GetDescendants() do
			if bar:IsA("GuiObject") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
				local base = bar.Size
				local from = if bar.Name == "Horizontal"
					then UDim2.new(0, 0, base.Y.Scale, base.Y.Offset)
					else UDim2.new(base.X.Scale, base.X.Offset, 0, 0)
				table.insert(bars, { object = bar, base = base, from = from })
			end
		end
	end
	local accent = window:FindFirstChild("Accent")
	if accent and accent:IsA("GuiObject") then
		local base = accent.Size
		table.insert(bars, { object = accent, base = base, from = UDim2.new(0, 0, base.Y.Scale, base.Y.Offset) })
	end
	local light: GuiObject? = nil
	local found = window:FindFirstChild("Header")
	for _, name in { "Divider", "Sweep", "Light" } do
		found = if found then found:FindFirstChild(name) else nil
	end
	if found and found:IsA("GuiObject") then
		light = found
		found.Visible = false
	end
	local glint: GuiObject? = nil
	local glintSize = UDim2.new()
	found = window:FindFirstChild("Header")
	for _, name in { "Divider", "Glint" } do
		found = if found then found:FindFirstChild(name) else nil
	end
	if found and found:IsA("GuiObject") then
		glint = found
		glintSize = found.Size
		found.Visible = false
	end
	local outline = window:FindFirstChildOfClass("UIStroke")
	local outlineBase = if outline then outline.Transparency else 0
	local outlineThickness = if outline then outline.Thickness else 1
	local body = window:FindFirstChild("Body")

	local items: { Item } = {}
	local rises: { Rise } = {}
	local tweens: { Tween } = {}
	local stepper: RBXScriptConnection? = nil
	local started = 0
	-- Bumped by every play and settle, so a deferred gather from an earlier open does nothing.
	local generation = 0

	local function release()
		if stepper then
			stepper:Disconnect()
			stepper = nil
		end
		for _, item in items do
			for _, fade in item.fades do
				if fade.held then
					local target: any = fade.instance
					if math.abs(target[fade.property] - fade.last) <= EPSILON then
						target[fade.property] = fade.base
					end
				end
			end
		end
		table.clear(items)
	end

	local function step()
		local elapsed = os.clock() - started
		local busy = false
		for _, item in items do
			local alpha = math.clamp((elapsed - item.start) / ITEM, 0, 1)
			busy = busy or elapsed - item.start < ITEM + SPRING
			local hidden = (1 - alpha) ^ 3
			for _, fade in item.fades do
				if fade.held then
					local target: any = fade.instance
					if math.abs(target[fade.property] - fade.last) > EPSILON then
						fade.held = false
					else
						local value = fade.base + (1 - fade.base) * hidden
						target[fade.property] = value
						fade.last = value
					end
				end
			end
		end
		if not busy then
			release()
			-- the rises have landed with the fades; from here a piece's place is the screen's own
			table.clear(rises)
		end
	end

	-- Hides the items and starts them on their way.
	local function gather()
		if not body or not body:IsA("GuiObject") or window:GetAttribute("Cascade") == false then
			return
		end
		local candidates: { GuiObject } = {}
		collect(body, 0, candidates)
		local shown: { GuiObject } = {}
		for _, object in candidates do
			if onScreen(object, window) then
				table.insert(shown, object)
			end
		end
		if #shown == 0 then
			return
		end
		table.sort(shown, function(a, b)
			local ay, by = math.floor(a.AbsolutePosition.Y), math.floor(b.AbsolutePosition.Y)
			if ay ~= by then
				return ay < by
			end
			return a.AbsolutePosition.X < b.AbsolutePosition.X
		end)
		local gap = if #shown > 1 then math.min(STAGGER, (TOTAL - FIRST - ITEM) / (#shown - 1)) else 0
		local authored = window:GetAttribute("CascadeOffset")
		local shift = if typeof(authored) == "Vector2" then authored else Vector2.new(0, RISE)
		for index, object in shown do
			local start = FIRST + (index - 1) * gap
			local fades: { Fade } = {}
			addFades(object, fades)
			for _, descendant in object:GetDescendants() do
				addFades(descendant, fades)
			end
			table.insert(items, { start = start, fades = fades })
			-- A list places its rows itself, so a row's own pieces rise inside it instead.
			local parent = object.Parent
			local moving: { GuiObject } = {}
			if parent and hasLayout(parent) then
				if not hasLayout(object) then
					for _, child in object:GetChildren() do
						if child:IsA("GuiObject") then
							table.insert(moving, child)
						end
					end
				end
			else
				table.insert(moving, object)
			end
			local info = TweenInfo.new(ITEM + SPRING, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, start)
			for _, piece in moving do
				local base = piece.Position
				table.insert(rises, { object = piece, base = base })
				piece.Position = base + UDim2.fromOffset(shift.X, shift.Y)
				local tween = TweenService:Create(piece, info, { Position = base })
				table.insert(tweens, tween)
				tween:Play()
			end
		end
		started = os.clock()
		step()
		stepper = RunService.RenderStepped:Connect(step)
	end

	local function settle()
		generation += 1
		release()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
		for _, rise in rises do
			rise.object.Position = rise.base
		end
		table.clear(rises)
		for _, bar in bars do
			bar.object.Size = bar.base
		end
		for _, corner in corners do
			corner.object.Position = corner.base
		end
		if outline then
			outline.Transparency = outlineBase
			outline.Thickness = outlineThickness
		end
		if light then
			light.Visible = false
		end
		if glint then
			glint.Visible = false
		end
	end

	local function play()
		settle()
		local current = generation
		for _, bar in bars do
			bar.object.Size = bar.from
			local tween = TweenService:Create(bar.object, if bar.object == accent then ACCENT else BRACKETS, {
				Size = bar.base,
			})
			table.insert(tweens, tween)
			tween:Play()
		end
		for _, corner in corners do
			corner.object.Position = corner.from
			local tween = TweenService:Create(corner.object, SNAP, { Position = corner.base })
			table.insert(tweens, tween)
			tween:Play()
		end
		if outline then
			outline.Transparency = 0
			outline.Thickness = FLASH_THICKNESS
			local tween =
				TweenService:Create(outline, FLASH, { Transparency = outlineBase, Thickness = outlineThickness })
			table.insert(tweens, tween)
			tween:Play()
		end
		local spark = glint
		if spark then
			spark.Visible = true
			spark.Position = UDim2.new(0, 0, spark.Position.Y.Scale, spark.Position.Y.Offset)
			spark.Size = UDim2.new()
			spark.Rotation = 0
			for _, tween in
				{
					TweenService:Create(spark, GLINT_TRAVEL, {
						Position = UDim2.new(1, 0, spark.Position.Y.Scale, spark.Position.Y.Offset),
					}),
					TweenService:Create(spark, GLINT, { Size = glintSize }),
					TweenService:Create(spark, GLINT_SPIN, { Rotation = 180 }),
				}
			do
				table.insert(tweens, tween)
				tween:Play()
			end
		end
		local sweep = light
		if sweep then
			sweep.Visible = true
			sweep.Position = UDim2.new(SWEEP_FROM, 0, sweep.Position.Y.Scale, sweep.Position.Y.Offset)
			local tween = TweenService:Create(sweep, SWEEP, {
				Position = UDim2.new(SWEEP_TO, 0, sweep.Position.Y.Scale, sweep.Position.Y.Offset),
			})
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					sweep.Visible = false
					if glint then
						glint.Visible = false
					end
				end
			end)
			table.insert(tweens, tween)
			tween:Play()
		end
		task.defer(function()
			if generation == current then
				gather()
			end
		end)
	end

	return play, settle
end

return WindowReveal
