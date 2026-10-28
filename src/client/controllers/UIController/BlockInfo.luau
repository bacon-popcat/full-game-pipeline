-- BlockInfo: the panel saying what the aimed-at factory block or world node is doing -- a
-- machine's state, fuel, contents and output, a router's setting, a node's use -- and what
-- a press would do with what is in hand. It only reads: the attributes FactoryService
-- publishes on placed blocks (Status, Fuel, Contents, Output, Fluid, Progress, Sold,
-- Powered, Filter) and the hints in Shared/World.
--
-- The panel is authored in StarterGui.HUD.BlockInfo, sized by its Content frame (the
-- corner brackets stay outside it, since they size to the panel), and its rows are clones
-- of Assets.UI.BlockInfo.Row. It follows the cursor with a mouse; with touch or a gamepad it
-- sits at the top of the screen, clear of thumbs and the hotbar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local World = require(ReplicatedStorage.Shared.World)

local Aim = require(Players.LocalPlayer.PlayerScripts.Libraries.Aim)
local InventoryClient = require(Players.LocalPlayer.PlayerScripts.Libraries.InventoryClient)

type Row = { key: string, value: string }
type Info = { title: string, status: string?, working: boolean, rows: { Row }, hint: string }

-- Studs the panel looks; as far as the hand reaches is plenty, but a little more lets a
-- player read a machine on their way to it.
local LOOK_DISTANCE = 60
-- Seconds between content refreshes; position follows the cursor every frame.
local REFRESH_EVERY = 0.1
local WORKING = { Working = true, Selling = true, Feeding = true }
-- Where the panel sits when there is no cursor to follow.
local DOCKED_POSITION = UDim2.new(0.5, 0, 0, 64)

local BlockInfo = {}

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function itemName(itemId: string): string
	local ok, item = pcall(Inventory.getItem, itemId)
	return if ok then item.name else itemId
end

-- "IronOre:2,Coal:1" -> "2 Iron Ore · 1 Coal", with fluids left as named.
local function describe(encoded: unknown, names: (string) -> string): string?
	if typeof(encoded) ~= "string" or encoded == "" then
		return nil
	end
	local parts = {}
	for id, count in string.gmatch(encoded, "([^:,]+):(%d+)") do
		table.insert(parts, `{count} {names(id)}`)
	end
	return table.concat(parts, " · ")
end

local function fluidName(fluid: string): string
	return fluid
end

local function heldItem(): Inventory.Item?
	local selected = InventoryClient.getSelected()
	local stack = if selected > 0 then InventoryClient.getSlot(selected) else nil
	return if stack then Inventory.getItem(stack.itemId) else nil
end

local function blockInfo(model: Model, itemId: string, def: Factory.Def): Info
	local held = heldItem()
	local rows: { Row } = {}
	local status = model:GetAttribute("Status")
	local info: Info = {
		title = itemName(itemId),
		status = if typeof(status) == "string" then status else nil,
		working = typeof(status) == "string" and WORKING[status] == true,
		rows = rows,
		hint = Inventory.getItem(itemId).description or "",
	}
	local function add(key: string, value: string?)
		if value and value ~= "" then
			table.insert(rows, { key = key, value = value })
		end
	end

	if def.kind == "Machine" then
		if def.fuel then
			local fuel = model:GetAttribute("Fuel")
			add("Fuel", if typeof(fuel) == "number" and fuel > 0 then `{fuel}s` else "Empty")
		end
		add("Holding", describe(model:GetAttribute("Contents"), itemName))
		add("Fluid", describe(model:GetAttribute("Fluid"), fluidName))
		add("Output", describe(model:GetAttribute("Output"), itemName))
		local progress = model:GetAttribute("Progress")
		if typeof(progress) == "number" and progress > 0 then
			add("Progress", `{math.round(progress * 100)}%`)
		end
		local sold = model:GetAttribute("Sold")
		if def.sells and typeof(sold) == "number" then
			add("Sold", tostring(sold))
		end
	elseif def.route == "Split" then
		local powered = model:GetAttribute("Powered") == true
		info.status = if powered then "Powered: to the side" else "Unpowered: straight on"
		info.working = powered
	elseif def.route == "Filter" then
		local filter = model:GetAttribute("Filter")
		local names = {}
		if typeof(filter) == "string" then
			for id in string.gmatch(filter, "[^,]+") do
				table.insert(names, itemName(id))
			end
		end
		add("Sends left", if #names > 0 then table.concat(names, ", ") else "Nothing yet")
	end

	local isConveyor = def.kind == "Conveyor"
	if held and Factory.takesByHand(itemId, held.id) then
		info.hint = if def.route == "Filter"
			then `Click to toggle sending {held.name} left.`
			else `Click to put in {held.name}.`
	elseif held and held.kind == "Resource" and isConveyor then
		info.hint = `Click to drop a {held.name} onto it.`
	elseif not held then
		if def.kind == "Machine" and describe(model:GetAttribute("Output"), itemName) then
			info.hint = "Click to collect the output."
		elseif def.route == "Split" then
			info.hint = "Click to switch it."
		elseif def.route == "Filter" then
			info.hint = "Click to clear the filter."
		elseif isConveyor then
			info.hint = "Click to take the items on it."
		end
	end
	return info
end

local function nodeInfo(model: Model, nodeType: string): Info?
	local node = World.NODES[nodeType]
	if not node then
		return nil
	end
	local held = heldItem()
	local hint = node.hint
	if held and node.tool == held.id then
		hint = `Click to {if held.id == "Axe" then "chop" else "mine"} it.`
	elseif not held and node.pick then
		hint = `Click to pick a {itemName(node.pick.item):lower()}.`
	end
	return { title = node.name, status = nil, working = false, rows = {}, hint = hint }
end

-- What the aim is on, if it is something the panel describes.
local function target(): Info?
	local character = player.Character
	raycastParams.FilterDescendantsInstances = if character then { character } else {}
	local result = Aim.cast(raycastParams, LOOK_DISTANCE)
	if not result then
		return nil
	end
	local placed = Aim.modelUnder(result.Instance, "Placed")
	local itemId = if placed then placed:GetAttribute("ItemId") else nil
	local def = if typeof(itemId) == "string" then Factory.get(itemId) else nil
	if placed and typeof(itemId) == "string" and def then
		return blockInfo(placed, itemId, def)
	end
	local node = Aim.modelUnder(result.Instance, "World")
	local nodeType = if node then node:GetAttribute("NodeType") else nil
	if node and typeof(nodeType) == "string" then
		return nodeInfo(node, nodeType)
	end
	return nil
end

function BlockInfo.init(hud: ScreenGui)
	local panel = hud:FindFirstChild("BlockInfo")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = if assets then assets:FindFirstChild("UI") else nil
	local templates = if ui then ui:FindFirstChild("BlockInfo") else nil
	local rowTemplate = if templates then templates:FindFirstChild("Row") else nil
	local content = if panel then panel:FindFirstChild("Content") else nil
	local title = if content then content:FindFirstChild("Title") else nil
	local status = if content then content:FindFirstChild("Status") else nil
	local rowsFrame = if content then content:FindFirstChild("Rows") else nil
	local hint = if content then content:FindFirstChild("Hint") else nil
	if
		not panel
		or not panel:IsA("GuiObject")
		or not rowTemplate
		or not rowTemplate:IsA("Frame")
		or not title
		or not title:IsA("TextLabel")
		or not status
		or not status:IsA("TextLabel")
		or not rowsFrame
		or not hint
		or not hint:IsA("TextLabel")
	then
		warn("BlockInfo: HUD.BlockInfo.Content (Title, Status, Rows, Hint) or Assets.UI.BlockInfo.Row is missing")
		return
	end
	local successColor = panel:GetAttribute("SuccessColor")
	local warningColor = panel:GetAttribute("WarningColor")
	local cursorOffset = panel:GetAttribute("CursorOffset")
	local working = if typeof(successColor) == "Color3" then successColor else status.TextColor3
	local idle = if typeof(warningColor) == "Color3" then warningColor else status.TextColor3
	local offset = if typeof(cursorOffset) == "Vector2" then cursorOffset else Vector2.new(20, 16)

	local rows: { Frame } = {}
	local function setRows(wanted: { Row })
		for index, row in wanted do
			local frame = rows[index]
			if not frame then
				local clone = rowTemplate:Clone()
				clone.LayoutOrder = index
				clone.Parent = rowsFrame
				frame = clone
				rows[index] = clone
			end
			local key = frame:FindFirstChild("Key")
			local value = frame:FindFirstChild("Value")
			if key and key:IsA("TextLabel") and value and value:IsA("TextLabel") then
				key.Text = row.key
				value.Text = row.value
			end
			frame.Visible = true
		end
		for index = #wanted + 1, #rows do
			rows[index].Visible = false
		end
	end

	local elapsed = REFRESH_EVERY
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= REFRESH_EVERY then
			elapsed = 0
			local info = target()
			panel.Visible = info ~= nil
			if info then
				title.Text = `[ {info.title} ]`
				status.Visible = info.status ~= nil
				status.Text = info.status or ""
				status.TextColor3 = if info.working then working else idle
				setRows(info.rows)
				hint.Text = info.hint
				hint.Visible = info.hint ~= ""
			end
		end
		if panel.Visible then
			if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
				-- Mouse location is in viewport space; the HUD starts below the inset.
				local mouse = UserInputService:GetMouseLocation() - hud.AbsolutePosition + offset
				local room = hud.AbsoluteSize - panel.AbsoluteSize
				panel.AnchorPoint = Vector2.zero
				panel.Position = UDim2.fromOffset(
					math.clamp(mouse.X, 0, math.max(room.X, 0)),
					math.clamp(mouse.Y, 0, math.max(room.Y, 0))
				)
			else
				panel.AnchorPoint = Vector2.new(0.5, 0)
				panel.Position = DOCKED_POSITION
			end
		end
	end)
end

return BlockInfo
