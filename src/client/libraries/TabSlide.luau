--!strict
-- TabSlide: the highlight that slides between a window's tabs as the picked one changes (Quests'
-- Daily and Orders, the Shop's stalls, Crafting's categories). One clone of
-- Assets.UI.Tab.Highlight (tools/hud/polish_hud.luau) lives inside the picked tab; when another is
-- picked it moves into that one and glides over from where it was, stretching to the new tab's
-- size, and springs a little past as it lands. It takes the screen's picked colour. The screen
-- keeps its own picked look; this only adds the moving box.
--
-- The glide is in Scale (shares of the new tab), so a window's UIScale or a tab's hover scale
-- never throws it off. The first pick, a pick while the window is hidden, and reduced motion all
-- place it at once. Without the template it does nothing.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SLIDE = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local TabSlide = {}

local function template(): GuiObject?
	local found: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in { "UI", "Tab", "Highlight" } do
		found = if found then found:FindFirstChild(name) else nil
	end
	return if found and found:IsA("GuiObject") then found else nil
end

-- Returns `pick(tab)` and `cleanup`.
function TabSlide.bind(color: Color3): ((GuiObject) -> (), () -> ())
	local source = template()
	if not source then
		return function() end, function() end
	end
	local highlight = source:Clone()
	highlight.BackgroundColor3 = color
	for _, part in highlight:GetDescendants() do
		if part:IsA("UIStroke") then
			part.Color = color
		end
	end
	local current: GuiObject? = nil
	local tween: Tween? = nil
	return function(tab: GuiObject)
		if tab == current then
			return
		end
		local from = current
		current = tab
		if tween then
			tween:Cancel()
			tween = nil
		end
		local size = tab.AbsoluteSize
		local glide = from ~= nil
			and from.Parent ~= nil
			and highlight.Parent == from
			and tab.Visible
			and size.X > 0
			and size.Y > 0
			and not GuiService.ReducedMotionEnabled
		highlight.Parent = tab
		if glide and from then
			local offset = (from.AbsolutePosition - tab.AbsolutePosition) / size
			local stretch = from.AbsoluteSize / size
			highlight.Position = UDim2.fromScale(offset.X, offset.Y)
			highlight.Size = UDim2.fromScale(stretch.X, stretch.Y)
			local moving = TweenService:Create(highlight, SLIDE, {
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 1),
			})
			tween = moving
			moving:Play()
		else
			highlight.Position = UDim2.fromScale(0, 0)
			highlight.Size = UDim2.fromScale(1, 1)
		end
	end, function()
		if tween then
			tween:Cancel()
		end
		highlight:Destroy()
	end
end

return TabSlide
