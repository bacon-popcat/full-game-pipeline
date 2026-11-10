--[[
Authors two side-column changes in StarterGui.HUD (the place file only; conventions.md § UI):

  * SideButtons.Crafting: a lavender button with a hammer, after Shop, that opens the Crafting
    window (CraftingScreen.luau). It takes the place of SideButtons.Robux, which goes.
  * Menu.Body.Robux: a Robux row in the Menu popup, before Settings, that opens the Robux Shop
    window (MenuScreen.luau); the popup grows to fit it.

Run it after progress_hud.luau and shop_hud.luau (progress_hud rebuilds the Menu popup with its own
rows), through the Studio MCP in the Edit datamodel the same way: serve the repo (python -m
http.server 34998 --bind 127.0.0.1), fetch this file into a temporary ModuleScript, require it and
call the function it returns. Safe to rerun: what it makes is removed and rebuilt, and the side
column keeps its authored button size and gap however many buttons it ends up with.
]]
local StarterGui = game:GetService("StarterGui")

local CRAFT = Color3.fromRGB(184, 168, 242)
local ROBUX = Color3.fromRGB(110, 214, 146)
-- Roblox's own Robux image, shipped with the client.
local ROBUX_IMAGE = "rbxasset://textures/ui/common/robux.png"
-- The Menu popup's row height and gap, and its height with four rows (progress_hud).
local ROW, ROW_GAP, FOUR_ROWS = 44, 8, 304

local function paintBars(root: Instance, color: Color3)
	for _, bar in root:GetDescendants() do
		if bar:IsA("Frame") and (bar.Name == "Horizontal" or bar.Name == "Vertical") then
			bar.BackgroundColor3 = color
		end
	end
end

local function rect(parent: Instance, name: string, position: UDim2, size: UDim2, rotation: number, color: Color3)
	local node = Instance.new("Frame")
	node.Name = name
	node.BackgroundColor3 = color
	node.BorderSizePixel = 0
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.Position = position
	node.Size = size
	node.Rotation = rotation
	node.Parent = parent
	return node
end

-- A hammer leaning right: a handle from the bottom left and a head across its top end.
local function hammerIcon(icon: Instance, color: Color3)
	rect(icon, "Handle", UDim2.fromScale(0.42, 0.58), UDim2.fromScale(0.13, 0.62), 45, color)
	local head = rect(icon, "Head", UDim2.fromScale(0.64, 0.36), UDim2.fromScale(0.62, 0.24), 45, color)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = head
end

local function buttonsOf(side: Instance): { GuiButton }
	local list = {}
	for _, child in side:GetChildren() do
		if child:IsA("GuiButton") then
			table.insert(list, child)
		end
	end
	return list
end

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local log = {}

	---------------------------------------------------------------- side Crafting button
	do
		local side = hud.SideButtons
		local layout = side:FindFirstChildOfClass("UIListLayout")
		-- The column's height in pixels at a 1280x720 reference, and one button's and gap's within it,
		-- measured before anything changes so they are kept.
		local reference = 720
		local height = side.Size.Y.Scale * reference + side.Size.Y.Offset
		local buttonPx = side.Research.Size.Y.Scale * height + side.Research.Size.Y.Offset
		local gapPx = layout.Padding.Scale * height + layout.Padding.Offset

		local old = side:FindFirstChild("Robux")
		if old then
			old:Destroy()
		end
		old = side:FindFirstChild("Crafting")
		if old then
			old:Destroy()
		end
		local crafting = side.Research:Clone()
		crafting.Name = "Crafting"
		crafting.LayoutOrder = 2
		crafting.Icon:ClearAllChildren()
		hammerIcon(crafting.Icon, CRAFT)
		paintBars(crafting, CRAFT)
		crafting.UIStroke.Color = CRAFT
		crafting.Tooltip.Label.Text = "Crafting"
		crafting.Tooltip.Label.TextColor3 = CRAFT
		crafting.Parent = side

		local count = #buttonsOf(side)
		local newHeight = buttonPx * count + gapPx * (count - 1)
		for _, child in buttonsOf(side) do
			child.Size = UDim2.fromScale(1, buttonPx / newHeight)
		end
		layout.Padding = UDim.new(gapPx / newHeight, 0)
		local width = side.Size.X.Scale * 1280 + side.Size.X.Offset
		side.Size = UDim2.new(side.Size.X, UDim.new(newHeight / reference, 0))
		side:FindFirstChildOfClass("UIAspectRatioConstraint").AspectRatio = width / newHeight
		table.insert(log, `side buttons: {count}, Crafting in place of Robux`)
	end

	---------------------------------------------------------------- Menu popup Robux row
	do
		local menu = hud.Menu
		local body = menu.Body
		local old = body:FindFirstChild("Robux")
		if old then
			old:Destroy()
		end
		local row = body.Stats:Clone()
		row.Name = "Robux"
		row.LayoutOrder = 4
		body.Settings.LayoutOrder = 5
		row.UIStroke.Color = ROBUX
		paintBars(row, ROBUX)
		row.Icon:ClearAllChildren()
		local image = Instance.new("ImageLabel")
		image.Name = "Image"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(1, 1)
		image.Image = ROBUX_IMAGE
		image.ImageColor3 = ROBUX
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = row.Icon
		row.Label.Text = "Robux Shop"
		row.Parent = body

		local rows = 0
		for _, child in body:GetChildren() do
			if child:IsA("GuiButton") then
				rows += 1
			end
		end
		local limit = menu:FindFirstChildOfClass("UISizeConstraint")
		limit.MaxSize = Vector2.new(limit.MaxSize.X, FOUR_ROWS + (rows - 4) * (ROW + ROW_GAP))
		table.insert(log, `Menu popup: {rows} rows, Robux before Settings`)
	end

	return table.concat(log, "\n")
end
