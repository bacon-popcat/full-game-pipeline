-- DropService: items lying loose in the world, in Workspace.Drops. A player drops one from
-- their hand (DropItem), and a conveyor or machine throws one off an end with nothing in
-- front of it. Drops are real physics, simulated by the server: they fall, tumble and pile
-- up until a player walks into one, which picks it up, or a belt takes it. Which belts take
-- a drop, and where a drop aimed at a block appears, are FactoryService's rules; it
-- registers them through `setBelts`, so the two services never require each other. A drop
-- nobody takes despawns after LIFETIME.
-- Drops of the same item and owner that come to rest near each other merge into one stack:
-- one model and one physics body with a Count attribute, however many items it holds, so a
-- flood of drops stays cheap. A pickup takes as much of a stack as the inventory has room
-- for. A stack draws a little bigger the more it holds; DropController labels its count.
-- A drop lying on a belt, or a settled one beside any belt, joins it whole as one stack
-- (FactoryService's `catch` rule), unless it was thrown off a belt end.
-- A drop that is picked up or merged lingers for COLLECT_TIME, anchored and out of play,
-- while DropCollected has every client draw it being sucked into its target.
-- Drops retain their owner even outside a plot; pickup and absorption cannot transfer
-- them to another player's plot. DataService clears these transient items on departure.
--
-- A drop's root collides, so CanQuery can't hide it from spatial queries; placement, the
-- aim and open belt ends skip Workspace.Drops by hand (Build.isLoose).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Build = require(ReplicatedStorage.Shared.Build)
local ItemArt = require(ReplicatedStorage.Shared.ItemArt)
local Plot = require(ReplicatedStorage.Shared.Plot)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local InventoryService = require(script.Parent.InventoryService)

type Drop = {
	itemId: string,
	count: number,
	model: Model,
	root: BasePart,
	-- os.clock() when it appeared, and when it despawns.
	born: number,
	expires: number,
	-- The model's scale for a single item; a stack grows from it.
	baseScale: number,
	-- The player who dropped it, if one did.
	dropper: Player?,
	-- Whether a belt beside it carrying the same item may pull it on; false for drops a belt
	-- threw off its end, which would ride round and be thrown off again.
	pullable: boolean,
	owner: number,
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
-- Studs between the centres of two drops that merge into one stack.
local MERGE_RADIUS = 3
-- Seconds a new drop flies before it can merge, so a toss lands before it joins a pile.
local MERGE_DELAY = 0.6
-- Seconds between merge (and despawn) passes.
local MERGE_EVERY = 0.4
-- Seconds a collected drop stays, out of play, while clients draw it flying into its target.
local COLLECT_TIME = 0.6

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
type Catch = (itemId: string, count: number, position: Vector3, dropper: Player?, reach: boolean) -> (number, Vector3?)

local absorber: Catch? = nil
local beltPoint: ((model: Model) -> Vector3?)? = nil
local lastAction: { [Player]: number } = {}
local absorbTimer = 0
local mergeTimer = 0

local function remove(drop: Drop)
	if drops[drop.model] == drop then
		drops[drop.model] = nil
		drop.model:Destroy()
	end
end

-- Takes a drop out of play and has clients draw it sucked into `target` (a character's or
-- stack's root, or a point on a belt). With `whole` false only part of the stack went, so
-- the drop stays and clients draw a copy leaving it.
local function collect(drop: Drop, target: BasePart | Vector3, whole: boolean)
	Remotes.DropCollected:FireAllClients(drop.model, target, whole)
	if not whole or drops[drop.model] ~= drop then
		return
	end
	-- Kept for the animation's sake only: out of the table, no belt, pickup or merge sees it.
	drops[drop.model] = nil
	drop.root.Anchored = true
	drop.root.CanCollide = false
	drop.root.CanTouch = false
	task.delay(COLLECT_TIME, function()
		drop.model:Destroy()
	end)
end

-- Grows (or shrinks) a drop to suit its count, lifted so it doesn't sink into the floor.
local function resize(drop: Drop)
	local scale = drop.baseScale * ItemArt.stackScale(drop.count)
	local current = drop.model:GetScale()
	if math.abs(scale - current) < 0.01 then
		return
	end
	local height = drop.root.Size.Y
	drop.model:ScaleTo(scale)
	drop.model:PivotTo(drop.model:GetPivot() + Vector3.yAxis * (drop.root.Size.Y - height) / 2)
end

local function setCount(drop: Drop, count: number)
	drop.count = count
	drop.model:SetAttribute("Count", count)
	resize(drop)
end

-- Takes `count` units out of a drop, removing it when none are left.
local function use(drop: Drop, count: number)
	if drop.count - count <= 0 then
		drop.count = 0
		remove(drop)
	else
		setCount(drop, drop.count - count)
	end
end

-- Folds `from` into `into`, drawing `from` flying into the stack it joined.
local function merge(into: Drop, from: Drop)
	collect(from, into.root, true)
	into.expires = math.max(into.expires, from.expires)
	into.dropper = into.dropper or from.dropper
	into.pullable = into.pullable and from.pullable
	setCount(into, into.count + from.count)
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
	if drop.owner ~= 0 and drop.owner ~= player.UserId then
		return
	end
	local cell =
		Vector3.new(math.floor(drop.root.Position.X / Build.GRID), 0, math.floor(drop.root.Position.Z / Build.GRID))
	if Plot.at(cell) and not Build.canEdit(player, cell, Vector3.one) then
		return
	end
	local left = InventoryService.give(player, drop.itemId, drop.count)
	local taken = drop.count - left
	if taken <= 0 then
		return
	end
	local target = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if target and target:IsA("BasePart") then
		collect(drop, target, left == 0)
	end
	-- After a whole collect the drop is already out of play, so this only zeroes it.
	use(drop, taken)
end

-- A physical item in the world at `cframe`, moving at `velocity`, and who dropped it.
-- `pullable` false keeps belts beside it from pulling it on (see Drop).
function DropService.spawn(
	itemId: string,
	cframe: CFrame,
	velocity: Vector3,
	count: number?,
	dropper: Player?,
	pullable: boolean?
)
	local position = cframe.Position / Build.GRID
	local index = Plot.at(Vector3.new(math.floor(position.X), 0, math.floor(position.Z)))
	local plots = workspace:FindFirstChild("Plots")
	local plot = if index and plots then plots:FindFirstChild(tostring(index)) else nil
	local owner = if dropper then dropper.UserId else if plot then plot:GetAttribute("Owner") else 0
	if typeof(owner) ~= "number" then
		owner = 0
	end
	dropper = dropper or Players:GetPlayerByUserId(owner)
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
	local now = os.clock()
	local drop: Drop = {
		itemId = itemId,
		count = 0,
		model = model,
		root = root,
		born = now,
		expires = now + LIFETIME,
		baseScale = model:GetScale(),
		dropper = dropper,
		owner = owner,
		pullable = pullable ~= false,
	}
	setCount(drop, count or 1)
	drops[model] = drop
	model.Parent = folder
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = velocity
	root.Touched:Connect(function(hit)
		onTouched(drop, hit)
	end)
end

-- Sets the rules for belts: `catch` takes what it can of a drop of `count` at `position` onto
-- a belt (or into a machine), reaching for belts beside it when `reach` is set, and says how
-- many it took and where they went; `dropPoint` says where a drop aimed at a placed block
-- appears, or nil when it has no belt.
function DropService.setBelts(catch: Catch, dropPoint: (model: Model) -> Vector3?)
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
	local now = os.clock()
	for _, drop in drops do
		-- Settled first, so a toss lands before a belt beside it pulls it in.
		local reach = drop.pullable and now - drop.born >= MERGE_DELAY
		local taken, point = rule(drop.itemId, drop.count, drop.root.Position, drop.dropper, reach)
		if taken > 0 then
			if point then
				collect(drop, point, taken >= drop.count)
			end
			use(drop, taken)
		end
	end
end

local function bucketKey(drop: Drop, cell: Vector3): string
	return `{drop.owner}|{drop.itemId}|{cell}`
end

-- A settled drop already bucketed this pass that `drop` can merge with, or nil.
local function partnerOf(buckets: { [string]: { Drop } }, drop: Drop, cell: Vector3): Drop?
	local position = drop.root.Position
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				for _, other in buckets[bucketKey(drop, cell + Vector3.new(dx, dy, dz))] or {} do
					if drops[other.model] == other and (other.root.Position - position).Magnitude <= MERGE_RADIUS then
						return other
					end
				end
			end
		end
	end
	return nil
end

-- Despawns expired drops and merges settled drops of one item and owner within
-- MERGE_RADIUS. Drops are hashed into MERGE_RADIUS cells, so a pass is linear in the number
-- of drops however many lie on the ground. The bigger stack survives and stays put.
local function settle(dt: number)
	mergeTimer += dt
	if mergeTimer < MERGE_EVERY then
		return
	end
	mergeTimer = 0
	local now = os.clock()
	local buckets: { [string]: { Drop } } = {}
	for _, drop in drops do
		if now >= drop.expires then
			remove(drop)
			continue
		end
		if now - drop.born < MERGE_DELAY then
			continue
		end
		local position = drop.root.Position
		local cell = Vector3.new(
			math.floor(position.X / MERGE_RADIUS),
			math.floor(position.Y / MERGE_RADIUS),
			math.floor(position.Z / MERGE_RADIUS)
		)
		local partner = partnerOf(buckets, drop, cell)
		if partner and partner.count >= drop.count then
			merge(partner, drop)
			continue
		end
		if partner then
			-- Its entry goes stale: partnerOf skips drops no longer in play.
			merge(drop, partner)
		end
		local key = bucketKey(drop, cell)
		buckets[key] = buckets[key] or {}
		table.insert(buckets[key], drop)
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
	if typeof(onto) == "Instance" and onto:IsA("Model") then
		local origin = onto:GetAttribute("Origin")
		if typeof(origin) ~= "Vector3" or not Build.canEdit(player, origin, Vector3.one) then
			return
		end
	end
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

function DropService.clear(player: Player)
	for _, drop in drops do
		if drop.owner == player.UserId then
			remove(drop)
		end
	end
end

function DropService.init()
	Remotes.DropItem.OnServerEvent:Connect(onDrop)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
	RunService.Heartbeat:Connect(function(dt)
		absorb(dt)
		settle(dt)
	end)
end

return DropService
