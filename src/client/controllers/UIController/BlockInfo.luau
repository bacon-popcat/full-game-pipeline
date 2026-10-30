-- BlockInfo: the panel saying what the aimed-at factory block or world node is doing -- a
-- machine's state, fuel, contents and output, a router's setting, a node's use, a crop's
-- growth -- and what
-- a press would do with what is in hand. It only reads: the attributes FactoryService
-- publishes on placed blocks, worded by BlockText, and the hints in Shared/World. It shows
-- only while the aim is on a block's or node's art, not the empty cells of its hitbox.
--
-- The panel is authored in StarterGui.HUD.BlockInfo, sized by its Content frame (the
-- corner brackets stay outside it, since they size to the panel), and its rows are clones
-- of Assets.UI.BlockInfo.Row. It follows the cursor with a mouse; with touch or a gamepad it
-- sits at the top of the screen, clear of thumbs and the hotbar. It hides while the
-- machine panel is open, which shows the same block in full.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local World = require(ReplicatedStorage.Shared.World)

local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Aim = require(Libraries.Aim)
local BlockText = require(Libraries.BlockText)
local Hud = require(Libraries.Hud)
local Controls = require(Libraries.Controls)
local InventoryClient = require(Libraries.InventoryClient)

type Row = BlockText.Row
type Info = { title: string, status: string?, working: boolean, rows: { Row }, hint: string }

-- Studs the panel looks; as far as the hand reaches is plenty, but a little more lets a
-- player read a machine on their way to it.
local LOOK_DISTANCE = 60
-- Seconds between content refreshes; position follows the cursor every frame.
local REFRESH_EVERY = 0.1
-- Where the panel sits when there is no cursor to follow.
local DOCKED_POSITION = UDim2.new(0.5, 0, 0, 64)

local BlockInfo = {}

local player = Players.LocalPlayer
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local itemName = BlockText.itemName

local function heldItem(): Inventory.Item?
	local selected = InventoryClient.getSelected()
	local stack = if selected > 0 then InventoryClient.getSlot(selected) else nil
	return if stack then Inventory.getItem(stack.itemId) else nil
end

local function blockInfo(model: Model, itemId: string, def: Factory.Def): Info
	local held = heldItem()
	local status, working = BlockText.status(model, def)
	local info: Info = {
		title = itemName(itemId),
		status = status,
		working = working,
		rows = BlockText.rows(model, def, true),
		hint = Inventory.getItem(itemId).description or "",
	}

	local isConveyor = def.kind == "Conveyor"
	local hasLanes = def.lanes ~= nil
	local onInput = def.input ~= nil
	-- Machines are only worked through their panel, so a click does nothing to them.
	if def.kind == "Machine" then
		if held and held.kind == "Resource" and onInput and not Factory.takesByHand(itemId, held.id) then
			info.hint = `It doesn't take {held.name}.`
		end
	elseif def.route == "Filter" then
		info.hint = if held
			then `Click to send {held.name} left, then right, then straight on.`
			else "Click to clear the filter."
	elseif held and held.kind == "Resource" and hasLanes then
		info.hint = `Click to drop a {held.name} onto it.`
	elseif not held then
		if def.route == "Split" then
			info.hint = "Click to switch it."
		elseif isConveyor then
			info.hint = "Click to take the items on it."
		end
	end
	if Factory.hasControls(itemId) then
		local open = Controls.interactHint(UserInputService.PreferredInput)
		info.hint = if info.hint == "" then open else `{info.hint}\n{open}`
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
	local ripe = World.isRipe(node)
	if held and node.tool == held.id then
		hint = "Click to mine it."
	elseif not held and node.harvest then
		hint = if ripe then "Click to harvest it." else "Click to dig it up for its seed."
	end
	local info: Info = { title = node.name, status = nil, working = false, rows = {}, hint = hint }
	local stage = node.stage
	if node.crop and stage then
		local crop = World.CROPS[node.crop]
		local mutation = model:GetAttribute("Mutation")
		local produce = crop.produce .. (if typeof(mutation) == "string" then "+" .. mutation else "")
		info.title = Inventory.getItem(produce).name
		info.status = if ripe
			then "Ripe"
			elseif model:GetAttribute("Regrowing") then "Regrowing"
			elseif model:GetAttribute("Ripening") then "Ripening"
			else "Growing"
		table.insert(info.rows, { key = "Stage", value = World.STAGES[stage] })
		if ripe then
			local value = Inventory.getItem(produce).value or 0
			table.insert(info.rows, { key = "Sell value", value = Hud.number(value * crop.yield) .. " coins" })
		end
		info.working = ripe
		local growsAt = model:GetAttribute("GrowsAt")
		if not ripe and typeof(growsAt) == "number" then
			local left = math.max(0, math.ceil(growsAt - workspace:GetServerTimeNow()))
			table.insert(info.rows, { key = "Next stage", value = `{left}s` })
		end
	end
	return info
end

-- What the aim is on, if it is something the panel describes.
local function target(): Info?
	local character = player.Character
	raycastParams.FilterDescendantsInstances = if character then { character } else {}
	local result = Aim.castArt(raycastParams, LOOK_DISTANCE)
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

	local windows = {}
	for _, name in { "Backpack", "MachinePanel", "Shop", "Sell" } do
		local window = hud:FindFirstChild(name)
		if window and window:IsA("GuiObject") then
			table.insert(windows, window)
		end
	end
	local elapsed = REFRESH_EVERY
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= REFRESH_EVERY then
			elapsed = 0
			local covered = false
			for _, window in windows do
				covered = covered or window.Visible
			end
			local info = if covered then nil else target()
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
