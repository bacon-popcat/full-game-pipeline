-- DropService: items lying loose in the world, in Workspace.Drops. A player drops one from
-- their hand (DropItem), and a conveyor or machine throws one off an end with nothing in
-- front of it. Drops are real physics, simulated by the server: they fall, tumble and pile
-- up until a player walks into one, which picks it up, or a belt takes it. Which belts take
-- a drop, and where a drop aimed at a block appears, are FactoryService's rules; it
-- registers them through `setBelts`, so the two services never require each other. A drop
-- nobody takes despawns after LIFETIME.
--
-- A drop's root collides, so CanQuery can't hide it from spatial queries; placement, the
-- aim and open belt ends skip Workspace.Drops by hand (Build.isLoose).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Build = require(ReplicatedStorage.Shared.Build)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local InventoryService = require(script.Parent.InventoryService)

type Drop = {
	itemId: string,
	count: number,
	model: Model,
	root: BasePart,
	-- os.clock() when it appeared.
	born: number,
	-- The player who dropped it, if one did.
	dropper: Player?,
}

-- Seconds an untouched drop lasts.
local LIFETIME = 300
-- Seconds before a new drop can be picked up, so a player's drop doesn't jump straight
-- back into their hand.
local PICKUP_DELAY = 1
-- Studs along a drop's longest side.
local ITEM_SIZE = 1.2
-- Seconds between checks for drops a conveyor can take.
local ABSORB_EVERY = 0.15
-- Studs in front of a player their drop appears, and how hard it is tossed.
local DROP_DISTANCE = 2.5
local TOSS = Vector3.new(0, 6, -8)
-- Seconds between one player's drops; caps how fast a client can spam remotes.
local COOLDOWN = 0.12

local DropService = {}

local function dropFolder(): Folder
	local existing = workspace:FindFirstChild("Drops")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = workspace
	return folder
end

local folder = dropFolder()
local drops: { [Model]: Drop } = {}
local absorber: ((itemId: string, position: Vector3, dropper: Player?) -> boolean)? = nil
local beltPoint: ((model: Model) -> Vector3?)? = nil
local lastAction: { [Player]: number } = {}
local absorbTimer = 0

local function remove(drop: Drop)
	if drops[drop.model] == drop then
		drops[drop.model] = nil
		drop.model:Destroy()
	end
end

-- Takes `count` units out of a drop, removing it when none are left.
local function use(drop: Drop, count: number)
	drop.count -= count
	if drop.count <= 0 then
		remove(drop)
	else
		drop.model:SetAttribute("Count", drop.count)
	end
end

local function onTouched(drop: Drop, hit: BasePart)
	if drops[drop.model] ~= drop or os.clock() - drop.born < PICKUP_DELAY then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not player or not humanoid or humanoid.Health <= 0 then
		return
	end
	local left = InventoryService.give(player, drop.itemId, drop.count)
	use(drop, drop.count - left)
end

-- A physical item in the world at `cframe`, moving at `velocity`, and who dropped it.
function DropService.spawn(itemId: string, cframe: CFrame, velocity: Vector3, count: number?, dropper: Player?)
	local model = ItemArt.copy(itemId) or Instance.new("Model")
	model.Name = itemId
	local box, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * ITEM_SIZE / longest)
		box, size = model:GetBoundingBox()
	end
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = size:Max(Vector3.one * 0.6)
	root.CFrame = box
	root.Transparency = 1
	root.CanQuery = false
	root.Parent = model
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.PrimaryPart = root
	model:PivotTo(cframe)
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Count", count or 1)
	local drop: Drop =
		{ itemId = itemId, count = count or 1, model = model, root = root, born = os.clock(), dropper = dropper }
	drops[model] = drop
	model.Parent = folder
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = velocity
	root.Touched:Connect(function(hit)
		onTouched(drop, hit)
	end)
	task.delay(LIFETIME, remove, drop)
end

-- Sets the rules for belts: `catch` decides whether a belt (or machine) takes one unit of a
-- drop at `position` (and learns who dropped it); `dropPoint` says where a drop aimed at a
-- placed block appears, or nil when it has no belt.
function DropService.setBelts(
	catch: (itemId: string, position: Vector3, dropper: Player?) -> boolean,
	dropPoint: (model: Model) -> Vector3?
)
	absorber = catch
	beltPoint = dropPoint
end

local function absorb(dt: number)
	absorbTimer += dt
	local rule = absorber
	if absorbTimer < ABSORB_EVERY or not rule then
		return
	end
	absorbTimer = 0
	for _, drop in drops do
		if rule(drop.itemId, drop.root.Position, drop.dropper) then
			use(drop, 1)
		end
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Above the belt of a placed block within reach, or nil.
local function aboveBelt(root: BasePart, onto: unknown): CFrame?
	local placed = workspace:FindFirstChild("Placed")
	local rule = beltPoint
	if typeof(onto) ~= "Instance" or not onto:IsA("Model") or not placed or onto.Parent ~= placed or not rule then
		return nil
	end
	local itemId = onto:GetAttribute("ItemId")
	local origin = onto:GetAttribute("Origin")
	local rotation = onto:GetAttribute("Rotation")
	if typeof(itemId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(rotation) ~= "number" then
		return nil
	end
	local footprint = Build.footprint(itemId, rotation)
	if not footprint or not Build.inReach(root.Position, origin, footprint) then
		return nil
	end
	local point = rule(onto)
	return if point then CFrame.new(point) else nil
end

local function onDrop(player: Player, onto: unknown)
	local now = os.clock()
	local root = rootOf(player)
	local held = InventoryService.getHeldItemId(player)
	if not root or not held or now - (lastAction[player] or 0) < COOLDOWN then
		return
	end
	lastAction[player] = now
	local above = aboveBelt(root, onto)
	if InventoryService.takeHeld(player, held, 1) < 1 then
		return
	end
	if above then
		DropService.spawn(held, above, Vector3.zero, 1, player)
	else
		local facing = root.CFrame.Rotation
		DropService.spawn(held, root.CFrame * CFrame.new(0, 0, -DROP_DISTANCE), facing * TOSS, 1, player)
	end
end

function DropService.init()
	Remotes.DropItem.OnServerEvent:Connect(onDrop)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
	RunService.Heartbeat:Connect(absorb)
end

return DropService
