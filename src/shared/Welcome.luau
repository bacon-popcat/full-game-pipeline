--!strict
-- Welcome: what a garden gets for coming back, as rules and numbers (WelcomeService applies
-- them): the daily gift, and coins for the time away. Why these numbers: docs/retention.md §
-- Daily gift, welcome back and offline coins.
--
-- Daily gift: the first time a garden is opened on a UTC day counts one more day played, and
-- that day's gift waits to be collected. It counts days played, not days in a row, so a missed
-- day costs nothing. The cycle repeats every #GIFTS days; a garden's first day has no gift.
-- Offline coins: while its owner plays, a garden's Shipping Bin coins are kept in buckets; its
-- rate is their median, so a stockpile sold just before leaving does not count. Time away pays
-- a share of that rate, up to a cap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)

-- A day's gift: `coins` times Economy.scale of the player's level, or `count` seeds of `rarity`.
export type Gift = { coins: number?, rarity: string?, count: number? }
export type Saved = {
	-- Days this garden has been played, and the UTC day last counted.
	days: number,
	giftDay: number,
	-- The day number (1..days) whose gift is still to be collected; 0 when none.
	giftOwed: number,
	-- Unix seconds the garden was last saved while open; 0 before its first save.
	leftAt: number,
	-- Shipping Bin coins a minute over its last stretch of play.
	binRate: number,
	-- Offline coins worked out and not yet collected.
	coinsOwed: number,
}

local Welcome = {}

-- Seconds away before the card greets a returning player and offline coins are paid.
Welcome.AWAY_MIN = 600
-- The share of the bin rate paid for time away, and the most minutes that count.
Welcome.OFFLINE_SHARE = 0.25
Welcome.OFFLINE_CAP_MINUTES = 480
-- A bucket of bin coins is this long; the rate is the median of up to BUCKETS finished ones,
-- and stands only once MIN_BUCKETS are in (a shorter visit keeps the rate it loaded with).
Welcome.BUCKET_SECONDS = 300
Welcome.BUCKETS = 6
Welcome.MIN_BUCKETS = 3
-- Every this many cycles, the last day's seed is the rarity above.
Welcome.GRAND_EVERY = 4
Welcome.GRAND_RARITY = "Mythic"

Welcome.GIFTS = {
	{ coins = 1 },
	{ rarity = "Rare", count = 1 },
	{ coins = 2 },
	{ rarity = "Epic", count = 1 },
	{ coins = 3 },
	{ rarity = "Rare", count = 2 },
	{ rarity = "Legendary", count = 1 },
} :: { Gift }

-- The gift for a garden's `day`th day played (1 is its second day open: the first has none).
function Welcome.gift(day: number): Gift
	local cycle = #Welcome.GIFTS
	local index = (day - 1) % cycle + 1
	local gift = Welcome.GIFTS[index]
	if index == cycle and ((day - 1) // cycle + 1) % Welcome.GRAND_EVERY == 0 then
		return { rarity = Welcome.GRAND_RARITY, count = gift.count }
	end
	return gift
end

-- The coins a coin gift pays at `level`.
function Welcome.giftCoins(gift: Gift, level: number): number
	return if gift.coins then gift.coins * Economy.scale(level) else 0
end

-- Coins for `seconds` away at `rate` bin coins a minute; nothing under AWAY_MIN. Research
-- (Night Shift) adds `extraShare` to the share and `extraMinutes` to the cap.
function Welcome.offlineCoins(rate: number, seconds: number, extraShare: number?, extraMinutes: number?): number
	if seconds < Welcome.AWAY_MIN or rate <= 0 then
		return 0
	end
	local share = Welcome.OFFLINE_SHARE + (extraShare or 0)
	local cap = Welcome.OFFLINE_CAP_MINUTES + (extraMinutes or 0)
	return math.floor(share * rate * math.min(seconds / 60, cap))
end

-- The median of finished buckets, as coins a minute; nil while too few are in.
function Welcome.rate(buckets: { number }): number?
	if #buckets < Welcome.MIN_BUCKETS then
		return nil
	end
	local sorted = table.clone(buckets)
	table.sort(sorted)
	local middle = #sorted // 2
	local median = if #sorted % 2 == 1 then sorted[middle + 1] else (sorted[middle] + sorted[middle + 1]) / 2
	return median / (Welcome.BUCKET_SECONDS / 60)
end

function Welcome.empty(): Saved
	return { days = 0, giftDay = 0, giftOwed = 0, leftAt = 0, binRate = 0, coinsOwed = 0 }
end

local function amount(value: any, whole: boolean): number
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return 0
	end
	return if whole then math.floor(value) else value
end

function Welcome.sanitize(value: any): Saved
	local saved = Welcome.empty()
	if typeof(value) ~= "table" then
		return saved
	end
	saved.days = amount(rawget(value, "days"), true)
	saved.giftDay = amount(rawget(value, "giftDay"), true)
	saved.giftOwed = math.min(amount(rawget(value, "giftOwed"), true), saved.days)
	saved.leftAt = amount(rawget(value, "leftAt"), false)
	saved.binRate = amount(rawget(value, "binRate"), false)
	saved.coinsOwed = amount(rawget(value, "coinsOwed"), true)
	return saved
end

return Welcome
