--!strict
-- Hub: stall locations and reach shared by prompt windows and server transactions.
-- These positions stay west of the quarry and clear of the hub spawn. The Orders Board is a
-- stall only in that it stands in the hub and its prompt opens a window (Quests, on Orders).
local Hub = {}
Hub.REACH = 12
Hub.STALLS = {
	SeedShop = Vector3.new(-24, 0, -15),
	SellStand = Vector3.new(24, 0, -15),
	GearShop = Vector3.new(-24, 0, 15),
	RobuxShop = Vector3.new(24, 0, 15),
	OrdersBoard = Vector3.new(-48, 0, 0),
}

function Hub.inReach(player: Player, name: string): boolean
	local position = Hub.STALLS[name]
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return position ~= nil
		and root ~= nil
		and root:IsA("BasePart")
		and humanoid ~= nil
		and humanoid.Health > 0
		and (root.Position - (position + Vector3.new(0, 3, 0))).Magnitude <= Hub.REACH
end
return Hub
