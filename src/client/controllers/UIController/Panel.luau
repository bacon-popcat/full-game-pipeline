-- Panel: the HUD's bracketed panel look, shared by the code-built top-right pieces (DayClock,
-- MusicPlayer) so they match the authored sidebar buttons and windows: a near-black fill, a thin
-- light stroke and four white L-shaped corner brackets, sized in pixels.
local Panel = {}

Panel.FILL = Color3.fromRGB(10, 10, 18)
Panel.FILL_ALPHA = 0.15
Panel.EDGE = Color3.fromRGB(205, 205, 220)
Panel.FONT = Font.fromName("Sarpanch", Enum.FontWeight.Bold)

function Panel.apply(target: GuiObject, arm: number, thickness: number)
	target.BackgroundColor3 = Panel.FILL
	target.BackgroundTransparency = Panel.FILL_ALPHA
	target.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Panel.EDGE
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = target
	local brackets = Instance.new("Frame")
	brackets.Name = "Brackets"
	brackets.BackgroundTransparency = 1
	brackets.Size = UDim2.fromScale(1, 1)
	brackets.ZIndex = target.ZIndex + 2
	brackets.Parent = target
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local x, y = corner[1], corner[2]
		local h = Instance.new("Frame")
		h.AnchorPoint = Vector2.new(x, y)
		h.Position = UDim2.fromScale(x, y)
		h.Size = UDim2.fromOffset(arm, thickness)
		h.BackgroundColor3 = Color3.new(1, 1, 1)
		h.BorderSizePixel = 0
		h.ZIndex = brackets.ZIndex
		h.Parent = brackets
		local v = h:Clone()
		v.Size = UDim2.fromOffset(thickness, arm)
		v.Parent = brackets
	end
end

return Panel
