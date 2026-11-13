--!strict
-- UI: the shared button layer. Every clickable thing gets its hover, press and gamepad
-- focus feedback here, so the whole interface responds the same way.
--
-- A clickable thing is a bare GuiButton or a Frame wrapping a `Trigger` button;
-- `resolveButton` handles both. Feedback animates a UIScale on `target` (found, or added
-- once); the resting scale is captured from that UIScale, so a scale authored in Studio
-- is kept. Hover and focus spring it up and brighten the target's own UIStroke (thicker,
-- more opaque); a press squashes it quickly and the release springs it back past its place.
-- A button with an image `Icon` child (the side buttons, Menu rows, close buttons) also makes
-- its icon hop once as the pointer arrives: it pops up and wobbles back to rest, on the
-- Icon's own UIScale and Rotation. Activation is `Activated` only -- it already unifies
-- mouse, touch and gamepad. Roblox fires no Activated on a button that is not Active, so a
-- click or tap on one goes to the optional `onRefused` instead, for the screen to say why.
--
-- The stroke lift is relative and gives way: it remembers the stroke as it was when the hover
-- began and puts that back on leave, unless the screen changed the stroke meanwhile (a tab
-- picked, a card selected), whose value then stands.
--
-- Hover is ignored while the preferred input is touch: a tap fires MouseEnter with no
-- reliable MouseLeave, which would leave the button stuck enlarged. Hover also ends when the
-- button's ScreenGui is disabled (HudVisibility hides the HUD under the pointer, and no
-- MouseLeave follows).
-- An optional authored Tooltip child shares hover/focus state with the button feedback.
-- Sound rides the same moments (UISound): a tick as the pointer or gamepad focus arrives, a pop
-- on Activated, and two dull taps on a click that went to `onRefused`.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Trove = require(ReplicatedStorage.Packages.Trove)
local UISound = require(script.Parent.UISound)

export type ButtonOptions = {
	-- What scales; defaults to the node passed to bindButton.
	target: GuiObject?,
	hoverScale: number?,
	pressScale: number?,
	-- Receives Activated's InputObject, for callers that treat devices differently.
	onActivate: ((input: InputObject) -> ())?,
	-- Called when the button is clicked or tapped while not Active (Roblox fires no Activated
	-- then), so a screen can say why nothing happened.
	onRefused: (() -> ())?,
}

local HOVER_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local STROKE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOOLTIP_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The icon hop: how far it pops and tilts as the pointer arrives, and how it settles.
local HOP_SCALE, HOP_TILT = 1.3, -16
local HOP_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local WOBBLE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
-- How much a hover lifts the stroke: thicker by this many pixels, and this share less clear.
local STROKE_THICKER, STROKE_CLEARER = 1, 0.6
local DEFAULT_HOVER_SCALE = 1.06
local DEFAULT_PRESS_SCALE = 0.9

local UI = {}

function UI.resolveButton(node: GuiObject): GuiButton?
	if node:IsA("GuiButton") then
		return node
	end
	local trigger = node:FindFirstChild("Trigger")
	if trigger and trigger:IsA("GuiButton") then
		return trigger
	end
	return nil
end

-- Keep authored geometry/opacity as the open state; reversals start from the current
-- tweened values, and a cancelled exit must never hide a newly reopened tooltip.
local function bindTooltip(tooltip: GuiObject): ((boolean) -> (), () -> ())
	local size, position = tooltip.Size, tooltip.Position
	local collapsed = UDim2.new(size.X.Scale * 0.15, size.X.Offset * 0.15, size.Y.Scale, size.Y.Offset)
	local tucked = position - UDim2.new(size.X.Scale * 0.12, size.X.Offset * 0.12, 0, 0)
	local visible = false
	local tweens: { Tween } = {}
	local completion: RBXScriptConnection? = nil
	local opacity: { [Instance]: { [string]: number } } = {}
	local nodes = tooltip:GetDescendants()
	table.insert(nodes, tooltip)
	for _, child in nodes do
		local values = {}
		if child:IsA("GuiObject") then
			values.BackgroundTransparency = child.BackgroundTransparency
		end
		if child:IsA("TextLabel") then
			values.TextTransparency = child.TextTransparency
			values.TextStrokeTransparency = child.TextStrokeTransparency
		elseif child:IsA("UIStroke") then
			values.Transparency = child.Transparency
		end
		opacity[child] = values
	end
	local function cancel()
		if completion then
			completion:Disconnect()
			completion = nil
		end
		for _, active in tweens do
			active:Cancel()
		end
		table.clear(tweens)
	end
	local function paint(show: boolean, instant: boolean)
		local info = if instant then TweenInfo.new(0) else TOOLTIP_TWEEN_INFO
		local geometry = { Size = if show then size else collapsed, Position = if show then position else tucked }
		local motion = TweenService:Create(tooltip, info, geometry)
		table.insert(tweens, motion)
		for child, baseline in opacity do
			local goal = {}
			for property, value in baseline do
				goal[property] = if show then value else 1
			end
			table.insert(tweens, TweenService:Create(child, info, goal))
		end
		for _, active in tweens do
			active:Play()
		end
		if instant then
			tooltip.Visible = show
		elseif not show then
			completion = motion.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and not visible then
					tooltip.Visible = false
				end
			end)
		end
	end
	tooltip.Visible = false
	tooltip.Size, tooltip.Position = collapsed, tucked
	paint(false, true)
	return function(show: boolean)
		if show == visible then
			return
		end
		visible = show
		cancel()
		tooltip.Visible = true
		paint(show, GuiService.ReducedMotionEnabled)
	end, function()
		cancel()
		tooltip.Visible = false
		tooltip.Size, tooltip.Position = size, position
	end
end

-- Returns a cleanup that disconnects everything this call made; hand it to a Trove.
function UI.bindButton(node: GuiObject, options: ButtonOptions): () -> ()
	local button = UI.resolveButton(node)
	if not button then
		warn(`UI.bindButton: {node:GetFullName()} is not a GuiButton and has no Trigger`)
		return function() end
	end

	local target = options.target or node
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Parent = target
		scale = created
	end
	assert(scale, "UIScale was just ensured")

	local rest = scale.Scale
	local hoverScale = options.hoverScale or DEFAULT_HOVER_SCALE
	local pressScale = options.pressScale or DEFAULT_PRESS_SCALE
	local hovered = false
	local focused = false
	local pressed = false
	-- Whether the last change was a release, which springs back rather than easing.
	local released = false
	local tween: Tween? = nil
	local stroke = target:FindFirstChildOfClass("UIStroke")
	-- The stroke as it was when the lift began, and what the lift aimed at.
	local strokeRest: { transparency: number, thickness: number }? = nil
	local strokeLift: { transparency: number, thickness: number }? = nil
	local strokeTween: Tween? = nil
	-- Where a return still easing is headed, so a hover arriving meanwhile lifts from there.
	local returning: { transparency: number, thickness: number }? = nil
	local icon = node:FindFirstChild("Icon")
	local iconScale = if icon and icon:IsA("ImageLabel") then icon:FindFirstChildOfClass("UIScale") else nil
	local iconRest = if iconScale then iconScale.Scale else 1
	local iconRotation = if icon and icon:IsA("GuiObject") then icon.Rotation else 0
	local hops: { Tween } = {}
	local tooltip = node:FindFirstChild("Tooltip")
	local updateTooltip: ((boolean) -> ())? = nil
	local cleanupTooltip: (() -> ())? = nil
	if tooltip and tooltip:IsA("GuiObject") then
		updateTooltip, cleanupTooltip = bindTooltip(tooltip)
	end

	local function lift(on: boolean)
		if not stroke or on == (strokeRest ~= nil) then
			return
		end
		-- a lift or return still easing is this layer's own, whatever value it has reached
		local moving = strokeTween ~= nil and strokeTween.PlaybackState == Enum.PlaybackState.Playing
		if strokeTween then
			strokeTween:Cancel()
			strokeTween = nil
		end
		if on then
			local from = if moving and returning
				then returning
				else { transparency = stroke.Transparency, thickness = stroke.Thickness }
			returning = nil
			strokeRest = from
			local goal = {
				transparency = from.transparency * (1 - STROKE_CLEARER),
				thickness = from.thickness + STROKE_THICKER,
			}
			strokeLift = goal
			if GuiService.ReducedMotionEnabled then
				stroke.Transparency, stroke.Thickness = goal.transparency, goal.thickness
				return
			end
			strokeTween = TweenService:Create(stroke, STROKE_INFO, {
				Transparency = goal.transparency,
				Thickness = goal.thickness,
			})
			strokeTween:Play()
		elseif strokeRest then
			local before, aimed = strokeRest, strokeLift
			strokeRest, strokeLift = nil, nil
			-- the screen restyled the stroke while hovered: its value stands
			if
				not moving
				and aimed
				and (
					math.abs(stroke.Transparency - aimed.transparency) > 0.02
					or math.abs(stroke.Thickness - aimed.thickness) > 0.02
				)
			then
				return
			end
			if GuiService.ReducedMotionEnabled then
				stroke.Transparency, stroke.Thickness = before.transparency, before.thickness
				return
			end
			returning = before
			strokeTween = TweenService:Create(stroke, STROKE_INFO, {
				Transparency = before.transparency,
				Thickness = before.thickness,
			})
			strokeTween:Play()
		end
	end

	local function hop()
		if not iconScale or not icon or not icon:IsA("GuiObject") or GuiService.ReducedMotionEnabled then
			return
		end
		for _, playing in hops do
			playing:Cancel()
		end
		table.clear(hops)
		iconScale.Scale = iconRest * HOP_SCALE
		icon.Rotation = iconRotation + HOP_TILT
		table.insert(hops, TweenService:Create(iconScale, HOP_INFO, { Scale = iconRest }))
		table.insert(hops, TweenService:Create(icon, WOBBLE_INFO, { Rotation = iconRotation }))
		for _, playing in hops do
			playing:Play()
		end
	end

	local function apply()
		if updateTooltip then
			updateTooltip((hovered or focused) and UserInputService.PreferredInput ~= Enum.PreferredInput.Touch)
		end
		lift(hovered or focused)
		local factor = if pressed then pressScale elseif hovered or focused then hoverScale else 1
		if tween then
			tween:Cancel()
			tween = nil
		end
		if GuiService.ReducedMotionEnabled then
			scale.Scale = rest * factor
			return
		end
		local info = if pressed
			then PRESS_INFO
			elseif released then RELEASE_INFO
			elseif hovered or focused then HOVER_INFO
			else LEAVE_INFO
		released = false
		local nextTween = TweenService:Create(scale, info, { Scale = rest * factor })
		nextTween:Play()
		tween = nextTween
	end

	local trove = Trove.new()
	trove:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"), function()
		hovered = false
		apply()
	end)
	trove:Connect(button.MouseEnter, function()
		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			return
		end
		if not hovered then
			hop()
			UISound.hover()
		end
		hovered = true
		apply()
	end)
	trove:Connect(button.MouseLeave, function()
		hovered = false
		pressed = false
		apply()
	end)
	trove:Connect(button.SelectionGained, function()
		if not focused and not hovered then
			hop()
			UISound.hover()
		end
		focused = true
		apply()
	end)
	trove:Connect(button.SelectionLost, function()
		focused = false
		apply()
	end)
	trove:Connect(button.MouseButton1Down, function()
		pressed = true
		apply()
	end)
	trove:Connect(button.MouseButton1Up, function()
		released = pressed
		pressed = false
		apply()
	end)
	trove:Connect(button.Activated, function(input: InputObject)
		released = pressed or released
		pressed = false
		apply()
		UISound.click()
		if options.onActivate then
			options.onActivate(input)
		end
	end)
	local refused = options.onRefused
	if refused then
		trove:Connect(button.MouseButton1Click, function()
			if not button.Active then
				UISound.deny()
				refused()
			end
		end)
	end
	local screen = button:FindFirstAncestorOfClass("ScreenGui")
	if screen then
		trove:Connect(screen:GetPropertyChangedSignal("Enabled"), function()
			if not screen.Enabled and (hovered or pressed) then
				hovered, pressed = false, false
				apply()
			end
		end)
	end
	trove:Add(function()
		if cleanupTooltip then
			cleanupTooltip()
		end
		if tween then
			tween:Cancel()
		end
		if strokeTween then
			strokeTween:Cancel()
		end
		for _, playing in hops do
			playing:Cancel()
		end
	end)

	return function()
		trove:Destroy()
	end
end

return UI
