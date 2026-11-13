--[[
Authors the UI polish pass's nodes in StarterGui.HUD, StarterGui.ResearchView and
ReplicatedStorage.Assets.UI (the place file only; conventions.md § UI). Images come from
Shared/Icons (tools/hud/icons.py draws them; assets/icons/README.md lists the ids).

  * Header.Divider.Sweep and Header.Divider.Glint on every modal window (ZIndex 30): a clipping
    strip over the divider holding Light, a soft capsule in the window's accent colour, and a
    four-point twinkle beside it, which WindowReveal runs along the divider as the window opens.
    Both hidden at rest.
  * ResearchView.Research.Sky (under the canvas): Nebulae (three clouds, one Tinted), Glow, the
    Far/Mid/Near star layers, Streaks (three shooting stars) and Vignette; and the Star and Mote
    templates in Assets.UI.Research that ResearchSky clones into the layers.
  * Image icons: each Frame-built `Icon` (the six SideButtons, the Menu rows but Robux, the
    Backpack and Crafting search boxes) becomes an ImageLabel named Icon at the same place and
    layer, tinted its old colour, with a UIScale for UI.bindButton's hover hop; every window's
    Header.Close and each search box's Clear lose their two crossed bars to a Cross Icon; and
    Assets.UI.Toast.Icons.<Kind> become white ImageLabels that Toasts tints.
  * Assets.UI.Tab.Highlight, the box TabSlide slides between tabs.
  * HUD.Fx, a clear layer over everything (ZIndex 60) for Flair's sparks, and Assets.UI.Flair's
    Flash and Spark.
  * Cascade settings: the Welcome card's Cascade = false (WelcomeScreen pops its parts in
    itself) and the Menu's CascadeOffset, so its rows slide in from the left.

Run it last, after every other builder in tools/hud (they rebuild windows, rows and the notice
icons it replaces), through the Studio MCP in the Edit datamodel the same way: serve the repo
(python -m http.server 34998 --bind 127.0.0.1), fetch this file into a temporary ModuleScript,
require it and call the function it returns. Safe to rerun: what it makes is removed and rebuilt,
and an icon already swapped keeps its tint.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Icons = require(ReplicatedStorage.Shared.Icons)

local WHITE = Color3.new(1, 1, 1)
-- The modal windows' layer (conventions.md § UI).
local WINDOW_Z = 30

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local node = Instance.new(className)
	for key, value in props do
		node[key] = value
	end
	node.Parent = parent
	return node
end

local function windowsOf(hud: Instance): { Frame }
	local list = {}
	for _, child in hud:GetChildren() do
		if child:IsA("Frame") and child.ZIndex == WINDOW_Z and child:FindFirstChild("Header") then
			table.insert(list, child)
		end
	end
	return list
end

return function()
	local hud = StarterGui:WaitForChild("HUD")
	local log = {}

	---------------------------------------------------------------- divider sweeps
	do
		local count = 0
		for _, window in windowsOf(hud) do
			local divider = window.Header:FindFirstChild("Divider")
			if not divider then
				continue
			end
			for _, name in { "Sweep", "Glint" } do
				local old = divider:FindFirstChild(name)
				if old then
					old:Destroy()
				end
			end
			local accent = window:FindFirstChild("Accent")
			local color = if accent and accent:IsA("GuiObject")
				then accent.BackgroundColor3
				else divider.BackgroundColor3
			local sweep = new("Frame", {
				Name = "Sweep",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, 3),
				ClipsDescendants = true,
				ZIndex = divider.ZIndex + 1,
			}, divider)
			local light = new("Frame", {
				Name = "Light",
				BorderSizePixel = 0,
				BackgroundColor3 = color:Lerp(WHITE, 0.55),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(-0.25, 0.5),
				Size = UDim2.fromScale(0.3, 1),
				Visible = false,
				ZIndex = divider.ZIndex + 1,
			}, sweep)
			new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, light)
			new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0.05),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}, light)
			-- A four-point twinkle riding the light's head, outside the clip so it can stand tall.
			new("ImageLabel", {
				Name = "Glint",
				BackgroundTransparency = 1,
				Image = Icons.TEXTURES.Spark,
				ImageColor3 = color:Lerp(WHITE, 0.75),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(-0.25, 0.5),
				Size = UDim2.fromOffset(26, 26),
				Visible = false,
				ZIndex = divider.ZIndex + 2,
			}, divider)
			count += 1
		end
		table.insert(log, `divider sweeps: {count}`)
	end

	---------------------------------------------------------------- the Research sky
	do
		local research = StarterGui:WaitForChild("ResearchView").Research
		local assets = ReplicatedStorage.Assets.UI.Research
		for _, parent in { research, assets } do
			for _, name in { "Sky", "Star", "Mote" } do
				local old = parent:FindFirstChild(name)
				if old then
					old:Destroy()
				end
			end
		end
		-- Under the canvas (ZIndex 1) and everything else in the view; children draw back to front.
		local sky = new("Frame", {
			Name = "Sky",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, research)
		local function image(name: string, texture: string, props: { [string]: any }, parent: Instance): ImageLabel
			local label = new("ImageLabel", {
				Name = name,
				BackgroundTransparency = 1,
				Image = Icons.TEXTURES[texture],
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 0,
			}, parent)
			for key, value in props do
				(label :: any)[key] = value
			end
			return label
		end
		-- Huge soft clouds; the Tinted one takes the glow's colour, the others keep their own.
		local nebulae = new(
			"Frame",
			{ Name = "Nebulae", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 },
			sky
		)
		local clouds = {
			{ UDim2.fromScale(0.3, 0.32), 1.25, Color3.fromRGB(255, 214, 110), 0.62, 20, true },
			{ UDim2.fromScale(0.74, 0.62), 1.4, Color3.fromRGB(120, 92, 230), 0.7, -35, false },
			{ UDim2.fromScale(0.18, 0.84), 1.05, Color3.fromRGB(56, 150, 210), 0.76, 70, false },
		}
		for index, cloud in clouds do
			local label = image(`Nebula{index}`, "Nebula", {
				Position = cloud[1],
				Size = UDim2.fromScale(cloud[2], cloud[2]),
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				ImageColor3 = cloud[3],
				ImageTransparency = cloud[4],
				Rotation = cloud[5],
			}, nebulae)
			label:SetAttribute("Tinted", cloud[6])
		end
		image("Glow", "Glow", {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.6, 1.6),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ImageColor3 = Color3.fromRGB(255, 214, 110),
			ImageTransparency = 0.72,
		}, sky)
		for _, name in { "Far", "Mid", "Near" } do
			new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, sky)
		end
		local streaks = new(
			"Frame",
			{ Name = "Streaks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 },
			sky
		)
		for index = 1, 3 do
			-- anchored at the head, so the tail trails behind where it is going
			image(`Streak{index}`, "Streak", {
				AnchorPoint = Vector2.new(1, 0.5),
				Size = UDim2.fromOffset(240, 14),
				ImageColor3 = Color3.fromRGB(236, 238, 255),
				ImageTransparency = 0.05,
				Visible = false,
			}, streaks)
		end
		-- The edges darken over the field, so the corners sink and the tree reads in the middle.
		image("Vignette", "Vignette", {
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Stretch,
			ImageTransparency = 0,
		}, sky)
		new("Frame", {
			Name = "Star",
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(230, 232, 255),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
			ZIndex = 0,
		}, assets)
		new("ImageLabel", {
			Name = "Mote",
			BackgroundTransparency = 1,
			Image = Icons.TEXTURES.Glow,
			ImageColor3 = Color3.fromRGB(255, 226, 130),
			ImageTransparency = 1,
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 0,
		}, assets)
		table.insert(
			log,
			"Research sky: Nebulae (3), Glow, Far/Mid/Near, Streaks (3), Vignette; Star and Mote templates"
		)
	end

	---------------------------------------------------------------- image icons
	do
		-- The colour a Frame-built icon was drawn in: its first filled part or stroke. An icon that
		-- is already an image (a rerun) keeps its own tint.
		local function colourOf(icon: Instance): Color3
			if icon:IsA("ImageLabel") then
				return icon.ImageColor3
			end
			for _, part in icon:GetDescendants() do
				if part:IsA("GuiObject") and part.BackgroundTransparency < 1 then
					return part.BackgroundColor3
				elseif part:IsA("UIStroke") and part.Transparency < 1 then
					return part.Color
				end
			end
			return WHITE
		end
		-- Puts an ImageLabel called `name` where `old` was, same place, size and layer, with a
		-- UIScale for UI.bindButton's hover hop; `old` goes.
		local function swap(old: GuiObject, glyph: string, name: string, color: Color3?): ImageLabel
			local image = new("ImageLabel", {
				Name = name,
				BackgroundTransparency = 1,
				Image = Icons.GLYPHS[glyph],
				ImageColor3 = color or colourOf(old),
				ScaleType = Enum.ScaleType.Fit,
				AnchorPoint = old.AnchorPoint,
				Position = old.Position,
				Size = old.Size,
				ZIndex = old.ZIndex,
				LayoutOrder = old.LayoutOrder,
				Visible = old.Visible,
			}, nil)
			new("UIScale", {}, image)
			image.Parent = old.Parent
			old:Destroy()
			return image
		end
		local count = 0

		local side = hud.SideButtons
		for button, glyph in
			{ Shop = "Shop", Sell = "Coin", Research = "Flask", Menu = "Menu", Quests = "Quests", Crafting = "Hammer" }
		do
			local icon = side:FindFirstChild(button) and side[button]:FindFirstChild("Icon")
			if icon then
				-- the glyphs carry their own padding, so they sit larger than the old drawings
				swap(icon, glyph, "Icon").Size = UDim2.fromScale(0.7, 0.7)
				count += 1
			end
		end
		-- The Robux row keeps Roblox's own Robux mark.
		for row, glyph in { Index = "Book", Achievements = "Medal", Stats = "Chart", Settings = "Gear" } do
			local icon = hud.Menu.Body:FindFirstChild(row) and hud.Menu.Body[row]:FindFirstChild("Icon")
			if icon then
				swap(icon, glyph, "Icon").Size = UDim2.fromOffset(30, 30)
				count += 1
			end
		end

		-- Close buttons (and the search boxes' clear buttons) lose their two crossed bars to a
		-- Cross image filling most of the button.
		local function cross(button: Instance)
			local bar = button:FindFirstChild("Stroke1")
			local old = button:FindFirstChild("Icon")
			local color = if bar and bar:IsA("GuiObject")
				then bar.BackgroundColor3
				elseif old then colourOf(old)
				else WHITE
			for _, name in { "Stroke1", "Stroke2" } do
				local stroke = button:FindFirstChild(name)
				if stroke then
					stroke:Destroy()
				end
			end
			if old then
				old:Destroy()
			end
			local holder = new("Frame", {
				Name = "Icon",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.9, 0.9),
			}, nil)
			holder.Parent = button
			swap(holder, "Cross", "Icon", color)
			count += 1
		end
		local windows = windowsOf(hud)
		table.insert(windows, StarterGui.ResearchView.Research)
		for _, window in windows do
			local close = window:FindFirstChild("Header") and window.Header:FindFirstChild("Close")
			if close then
				cross(close)
			end
		end
		for _, search in { hud.Backpack.Body.Main.Search, hud.Crafting.Body.Main.Search } do
			swap(search.Icon, "Search", "Icon")
			count += 1
			local clear = search:FindFirstChild("Clear")
			if clear then
				cross(clear)
			end
		end

		-- Notice kinds: each is the kind's glyph in white; Toasts tints it with the kind's colour.
		local kinds = ReplicatedStorage.Assets.UI.Toast.Icons
		for kind, glyph in
			{
				Info = "Info",
				Success = "Check",
				Error = "Cross",
				Reward = "Coin",
				Achievement = "Medal",
				Quest = "Quests",
				Rare = "Sparkle",
				Stock = "Sparkle",
				Level = "Level",
			}
		do
			local old = kinds:FindFirstChild(kind)
			if old and old:IsA("GuiObject") then
				swap(old, glyph, kind, WHITE)
				count += 1
			end
		end
		table.insert(log, `image icons: {count}`)
	end

	---------------------------------------------------------------- the sliding tab highlight
	do
		local folder = ReplicatedStorage.Assets.UI:FindFirstChild("Tab")
		if folder then
			folder:Destroy()
		end
		folder = new("Folder", { Name = "Tab" }, ReplicatedStorage.Assets.UI)
		-- White here; TabSlide tints the fill and stroke with the screen's picked colour. Under the
		-- tab's label (ZIndex 0 among the tab's children).
		local highlight = new("Frame", {
			Name = "Highlight",
			BorderSizePixel = 0,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.8,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, folder)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, highlight)
		new("UIStroke", {
			Color = WHITE,
			Thickness = 2,
			Transparency = 0.05,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, highlight)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0, 0.7),
		}, highlight)
		table.insert(log, "Assets.UI.Tab.Highlight")
	end

	---------------------------------------------------------------- Flair's pieces
	do
		local old = hud:FindFirstChild("Fx")
		if old then
			old:Destroy()
		end
		-- A clear layer over every window (30) and notice (50) for sparks; it catches no input.
		new("Frame", {
			Name = "Fx",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 60,
			Interactable = false,
		}, hud)
		local folder = ReplicatedStorage.Assets.UI:FindFirstChild("Flair")
		if folder then
			folder:Destroy()
		end
		folder = new("Folder", { Name = "Flair" }, ReplicatedStorage.Assets.UI)
		-- A bright band Flair.pulse sweeps across a piece (its gradient's Offset runs -1 to 1) while
		-- the whole fades out.
		local flash = new("Frame", {
			Name = "Flash",
			BorderSizePixel = 0,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.25,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 40,
		}, folder)
		new("UIGradient", {
			Rotation = 20,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.85),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.65, 0.85),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, flash)
		new("ImageLabel", {
			Name = "Spark",
			BackgroundTransparency = 1,
			Image = Icons.TEXTURES.Spark,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			ZIndex = 60,
		}, folder)
		table.insert(log, "HUD.Fx; Assets.UI.Flair.Flash and Spark")
	end

	---------------------------------------------------------------- cascade settings
	do
		local welcome = hud:FindFirstChild("Welcome")
		if welcome then
			welcome:SetAttribute("Cascade", false)
			table.insert(log, "Welcome: Cascade = false")
		end
		-- The Menu's rows slide in from the left rather than rising.
		hud.Menu:SetAttribute("CascadeOffset", Vector2.new(-40, 0))
		table.insert(log, "Menu: CascadeOffset (-40, 0)")
	end

	return table.concat(log, "\n")
end
