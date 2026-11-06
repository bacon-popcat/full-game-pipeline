-- MonetizationService: grants the Robux Shop's packs (Shared/Economy/Shops.ROBUX_PACKS) from
-- MarketplaceService.ProcessReceipt. GardenService shows the purchase prompt; only a receipt
-- here pays out. Each granted receipt's PurchaseId is kept with the garden (DataService loads
-- and snapshots the last RECEIPTS_KEPT of them), so a receipt Roblox sends again is
-- acknowledged without paying twice. A receipt for a player whose garden isn't loaded waits
-- (NotProcessedYet) until they are in one.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shops = require(ReplicatedStorage.Shared.Economy.Shops)
local EconomyService = require(script.Parent.EconomyService)

local RECEIPTS_KEPT = 50

local MonetizationService = {}

-- Each loaded player's granted PurchaseIds, oldest first.
local receipts: { [Player]: { string } } = {}

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local granted = if player then receipts[player] else nil
	if not player or not granted or player:GetAttribute("DataReady") ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if table.find(granted, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local pack = Shops.packForProduct(info.ProductId)
	if not pack then
		warn(`MonetizationService: no Robux pack sells product {info.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not EconomyService.add(player, pack.coins) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(granted, purchaseId)
	while #granted > RECEIPTS_KEPT do
		table.remove(granted, 1)
	end
	Remotes.Notify:FireClient(player, `Thanks! +{pack.coins} coins from the {pack.name}.`, "Reward")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt
end

function MonetizationService.load(player: Player, saved: unknown)
	local kept = {}
	if typeof(saved) == "table" then
		for _, id in saved :: { any } do
			if typeof(id) == "string" then
				table.insert(kept, id)
			end
		end
	end
	receipts[player] = kept
end

function MonetizationService.snapshot(player: Player): { string }?
	local granted = receipts[player]
	return if granted then table.clone(granted) else nil
end

function MonetizationService.release(player: Player)
	receipts[player] = nil
end

return MonetizationService
