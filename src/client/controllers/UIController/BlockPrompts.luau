-- BlockPrompts: a local ProximityPrompt on each thing of the player's that the interact key
-- works (Controls.INTERACT, or a tap on the card PromptController draws):
--
--   * a placed machine or router (Factory.hasControls) opens MachinePanel;
--   * a placed Crafting Bench opens CraftingScreen;
--   * a ripe crop in the player's garden is harvested (Interact "Harvest"; digging a crop up
--     is the Hammer's job, in BuildController).
--
-- Only the nearest prompt shows at a time, and none show while either window is open, so the
-- same key closes it. The card sits on the thing itself -- each prompt hangs from an attachment
-- at the centre of its box -- and the thing is highlighted while its card shows. Only blocks
-- with something to work have a prompt (Factory.hasControls: not a Sprinkler). A machine's prompt also carries `Status` and `Working`
-- (BlockText's wording) for the card's status line.
--
-- The prompts are made here on the client; the windows and the server still check reach,
-- ownership and ripeness on every request. Blocks and crops replicate (and stream in and
-- out) in pieces, and crops ripen and regrow, so every watched model is re-checked each
-- refresh rather than trusted from the moment it arrived.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Build = require(ReplicatedStorage.Shared.Build)
local Crafting = require(ReplicatedStorage.Shared.Crafting)
local Factory = require(ReplicatedStorage.Shared.Factory)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Trove = require(ReplicatedStorage.Packages.Trove)
local World = require(ReplicatedStorage.Shared.World)

local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local BlockText = require(Libraries.BlockText)
local CraftingScreen = require(script.Parent.CraftingScreen)
local MachinePanel = require(script.Parent.MachinePanel)

local PROMPT_NAME = "BlockPrompt"
-- Studs from the edge of a block's box a prompt reaches (well inside Build.REACH).
local PROMPT_REACH = 8
-- Seconds between re-checks of every watched model and of whether a window is open.
local REFRESH_EVERY = 0.25

-- What a model's prompt says and does; `key` changes whenever the prompt must be remade.
type Spec = { key: string, action: string, object: string, centre: Vector3, size: Vector3, open: () -> () }
type Entry = { prompt: ProximityPrompt, key: string, trove: any }

local BlockPrompts = {}

local player = Players.LocalPlayer
local trove = Trove.new()
-- Every model that might have a prompt, and the prompts made so far.
local watched: { [Model]: true } = {}
local prompts: { [Model]: Entry } = {}
-- Whether prompts show: not while a window is open.
local shown = true

local function blockSpec(model: Model): Spec?
	local itemId = model:GetAttribute("ItemId")
	local origin, rotation = model:GetAttribute("Origin"), model:GetAttribute("Rotation")
	if
		model:GetAttribute("Owner") ~= player.UserId
		or typeof(itemId) ~= "string"
		or not (itemId == Crafting.BENCH or Factory.hasControls(itemId))
		or typeof(origin) ~= "Vector3"
		or typeof(rotation) ~= "number"
	then
		return nil
	end
	local footprint = Build.footprint(itemId, rotation)
	if not footprint then
		return nil
	end
	local centre, size = Build.box(origin, footprint)
	local bench = itemId == Crafting.BENCH
	return {
		key = itemId,
		action = if bench then "Craft" else "Open",
		object = BlockText.itemName(itemId),
		centre = centre.Position,
		size = size,
		open = function()
			if bench then
				CraftingScreen.open(model)
			else
				MachinePanel.open(model, itemId)
			end
		end,
	}
end

local function cropSpec(model: Model): Spec?
	local nodeType = model:GetAttribute("NodeType")
	local cell = model:GetAttribute("Cell")
	local node = if typeof(nodeType) == "string" then World.NODES[nodeType] else nil
	if not node or not node.crop or not World.isRipe(node) or typeof(cell) ~= "Vector3" then
		return nil
	end
	local root = model.PrimaryPart
	if not root or not Build.canEdit(player, cell, Vector3.one) then
		return nil
	end
	local mutation = model:GetAttribute("Mutation")
	local produce = World.CROPS[node.crop].produce .. (if typeof(mutation) == "string" then "+" .. mutation else "")
	return {
		key = `{nodeType}/{produce}`,
		action = "Harvest",
		object = Inventory.getItem(produce).name,
		centre = root.Position,
		size = root.Size,
		open = function()
			Remotes.Interact:FireServer(model, "Harvest")
		end,
	}
end

local function specOf(model: Model): Spec?
	local folder = model.Parent
	if folder and folder.Name == "Placed" then
		return blockSpec(model)
	elseif folder and folder.Name == "World" then
		return cropSpec(model)
	end
	return nil
end

local function remove(model: Model)
	local entry = prompts[model]
	if entry then
		prompts[model] = nil
		entry.trove:Destroy()
	end
end

local function make(model: Model, spec: Spec): Entry?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local entryTrove = trove:Extend(true)
	local attachment = entryTrove:Add(Instance.new("Attachment"))
	attachment.Name = PROMPT_NAME
	-- Relative to the root: a world position set before parenting would be taken as local.
	attachment.Position = root.CFrame:PointToObjectSpace(spec.centre)
	local prompt = entryTrove:Add(Instance.new("ProximityPrompt"))
	prompt.Name = PROMPT_NAME
	prompt.ActionText = spec.action
	prompt.ObjectText = spec.object
	prompt.HoldDuration = 0
	prompt.Enabled = shown
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Highlight", true)
	-- The prompt measures from the box's centre, so a big machine reaches as far past its edge.
	prompt.MaxActivationDistance = PROMPT_REACH + math.max(spec.size.X, spec.size.Z) / 2
	entryTrove:Connect(prompt.Triggered, spec.open)
	prompt.Parent = attachment
	attachment.Parent = root
	return { prompt = prompt, key = spec.key, trove = entryTrove }
end

local function refreshStatus(model: Model, prompt: ProximityPrompt)
	local itemId = model:GetAttribute("ItemId")
	local def = if typeof(itemId) == "string" then Factory.get(itemId) else nil
	if def then
		local status, working = BlockText.status(model, def)
		prompt:SetAttribute("Status", status)
		prompt:SetAttribute("Working", working)
	end
end

-- Makes, remakes or removes `model`'s prompt to match what it is now.
local function check(model: Model)
	if not model.Parent then
		watched[model] = nil
		remove(model)
		return
	end
	local spec = specOf(model)
	local entry = prompts[model]
	-- A prompt whose root streamed out went with it; one whose spec changed is stale.
	if entry and (not spec or entry.key ~= spec.key or not entry.prompt:IsDescendantOf(workspace)) then
		remove(model)
		entry = nil
	end
	if spec and not entry then
		entry = make(model, spec)
		if entry then
			prompts[model] = entry
		end
	end
	if entry then
		if entry.prompt.Enabled ~= shown then
			entry.prompt.Enabled = shown
		end
		refreshStatus(model, entry.prompt)
	end
end

-- Whether a model in `folder` could ever have a prompt. World also holds rocks, trees and
-- ground, which never do; a node that hasn't said what it is yet is watched until it does.
local function mayPrompt(model: Model, folder: string): boolean
	if folder == "Placed" then
		return true
	end
	local nodeType = model:GetAttribute("NodeType")
	local node = if typeof(nodeType) == "string" then World.NODES[nodeType] else nil
	return node == nil or node.crop ~= nil
end

local function watch(folder: Instance)
	local function consider(child: Instance)
		if child:IsA("Model") and mayPrompt(child, folder.Name) then
			watched[child] = true
		end
	end
	trove:Connect(folder.ChildAdded, consider)
	trove:Connect(folder.ChildRemoved, function(child)
		if child:IsA("Model") then
			watched[child] = nil
			remove(child)
		end
	end)
	for _, child in folder:GetChildren() do
		consider(child)
	end
end

function BlockPrompts.init(_hud: ScreenGui)
	for _, name in { "Placed", "World" } do
		task.spawn(function()
			watch(workspace:WaitForChild(name))
		end)
	end
	local elapsed = 0
	trove:Connect(RunService.Heartbeat, function(dt)
		elapsed += dt
		if elapsed < REFRESH_EVERY then
			return
		end
		elapsed = 0
		-- Hidden while a window is open, so the interact key reaches the window to close it.
		shown = not MachinePanel.isOpen() and not CraftingScreen.isOpen()
		for model in watched do
			check(model)
		end
	end)
end

return BlockPrompts
