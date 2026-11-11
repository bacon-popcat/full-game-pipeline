--!strict
-- Social: the rules for what players do for each other, as numbers and pure checks
-- (SocialService applies them): which harvests the whole server hears about, liking a garden,
-- and gifting. Why these numbers: docs/retention.md § Social.
--
-- Likes: a visitor may like each garden once a UTC day, at its sign. The count is the owner's.
-- Gifts: one-way, of what the giver holds, to a player they have walked up to, and only while
-- both have the Gifting setting On (Shared/Settings; mirrored as a Player attribute).
-- Only crops, valued products and seeds can be given, never coins, tools, machines or materials.
-- Two daily caps bound what a gift can move: the giver's, as worth (GIFT_SCALE times
-- Economy.scale of their level, so a new account can pass on very little), and the receiver's,
-- as a number of gifts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local World = require(ReplicatedStorage.Shared.World)

export type Saved = {
	-- Likes this garden has been given.
	likes: number,
	-- The UTC day `liked` belongs to, and the owners (user ids as strings) liked that day.
	likedDay: number,
	liked: { [string]: boolean },
	-- The UTC day the gift counters belong to; the worth given and the gifts received that day.
	giftDay: number,
	given: number,
	received: number,
}

local Social = {}

-- Studs from a garden's sign a player may stand to like it, and from another player to give
-- them a gift.
Social.REACH = 16
Social.GIFT_REACH = 12
-- The level gifting opens at, the giver's daily worth as a multiple of Economy.scale, and the
-- gifts one garden takes in a day.
Social.GIFT_LEVEL = 5
Social.GIFT_SCALE = 2
Social.GIFTS_RECEIVED = 5
-- Seconds between one player's server-wide rare-harvest notices.
Social.NOTICE_COOLDOWN = 60
-- A harvest is told to the server when it carries WONDER, or FINE on a crop of FINE_RARITY or better.
Social.WONDER = "Rainbow"
Social.FINE = "Golden"
Social.FINE_RARITY = "Epic"

local seeds: { [string]: World.Crop } = {}
for _, crop in World.CROPS do
	seeds[crop.seed] = crop
end

-- Whether `player` has gifting switched on.
function Social.gifting(player: Player): boolean
	return player:GetAttribute("Gifting") == "On"
end

-- Whether a harvest of `cropId` carrying `mutation` (a Mutations key, "Wet+Golden") is news.
function Social.isNews(cropId: string, mutation: string?): boolean
	local crop = World.CROPS[cropId]
	if not crop or not mutation then
		return false
	end
	local names = string.split(mutation, "+")
	if table.find(names, Social.WONDER) then
		return true
	end
	return table.find(names, Social.FINE) ~= nil
		and Content.RARITIES[crop.rarity].order >= Content.RARITIES[Social.FINE_RARITY].order
end

-- What one of an item counts for against the giver's cap: its sell value, or a seed's price.
-- nil when the item cannot be gifted.
function Social.giftWorth(itemId: string): number?
	local crop = seeds[itemId]
	if crop then
		return crop.price
	end
	local item = Inventory.find(itemId)
	if item and item.kind == "Resource" and item.value and item.value > 0 then
		return item.value
	end
	return nil
end

-- The worth a player at `level` may give in a day.
function Social.giftCap(level: number): number
	return Social.GIFT_SCALE * Economy.scale(level)
end

function Social.empty(): Saved
	return { likes = 0, likedDay = 0, liked = {}, giftDay = 0, given = 0, received = 0 }
end

local function amount(value: any): number
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return 0
	end
	return math.floor(value)
end

function Social.sanitize(value: any): Saved
	local saved = Social.empty()
	if typeof(value) ~= "table" then
		return saved
	end
	saved.likes = amount(rawget(value, "likes"))
	saved.likedDay = amount(rawget(value, "likedDay"))
	saved.giftDay = amount(rawget(value, "giftDay"))
	saved.given = amount(rawget(value, "given"))
	saved.received = amount(rawget(value, "received"))
	local liked = rawget(value, "liked")
	if typeof(liked) == "table" then
		for owner, flag in liked do
			if typeof(owner) == "string" and tonumber(owner) and flag == true then
				saved.liked[owner] = true
			end
		end
	end
	return saved
end

-- Moves a save's daily counters on to `day`.
function Social.roll(saved: Saved, day: number)
	if saved.likedDay ~= day then
		saved.likedDay = day
		saved.liked = {}
	end
	if saved.giftDay ~= day then
		saved.giftDay = day
		saved.given = 0
		saved.received = 0
	end
end

return Social
