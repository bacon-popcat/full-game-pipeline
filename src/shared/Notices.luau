--!strict
-- Notices: the kinds of message Remotes.Notify carries and what each kind means on screen: its
-- colour, its sound, how long it stays, and whether it is a routine line in the stack above the
-- hotbar or a banner at the top of the screen. The server names a kind with every notice it sends,
-- and may add a Detail; the client's Toasts draw them. Only messages worth stopping for are sent at
-- all: a refusal, a reward, a rare harvest, a milestone. Routine income (a Shipping Bin's sales, a
-- common mutation) is not a notice; the wallet and the item cards already show it. Notices draw in
-- Sarpanch Bold, whose colon renders as one dot, so messages avoid colons.
--
-- A message need not be short: it wraps, and stays longer the longer it is. Notices that repeat
-- merge on screen (see `template`), so a reward message keeps the form "+N coins" for its amount.

export type Kind = "Info" | "Success" | "Error" | "Reward" | "Achievement" | "Quest" | "Rare" | "Level" | "Stock"

-- What a notice may carry besides its text.
--   item: an item id whose icon replaces the kind's icon.
--   open: a window (one of WINDOWS, a name libraries/Screens knows) that clicking the notice opens.
--   quiet: the moment already has its own sound (a level-up, a harvest), so the kind's is skipped.
export type Detail = { item: string?, open: string?, quiet: boolean? }

type Look = {
	color: Color3,
	-- A Shared/Sounds role.
	sound: string?,
	-- The banner's caption. A kind with one is a big moment, shown alone at the top of the screen.
	banner: string?,
}

local LOOKS: { [Kind]: Look } = {
	Info = { color = Color3.fromRGB(235, 235, 245) },
	Success = { color = Color3.fromRGB(157, 220, 154) },
	Error = { color = Color3.fromRGB(240, 140, 130), sound = "NoticeError" },
	Reward = { color = Color3.fromRGB(255, 214, 102), sound = "NoticeReward" },
	Quest = { color = Color3.fromRGB(142, 197, 255), sound = "NoticeReward" },
	Rare = { color = Color3.fromRGB(193, 173, 244), sound = "NoticeReward" },
	Achievement = { color = Color3.fromRGB(255, 196, 92), sound = "NoticeBanner", banner = "ACHIEVEMENT UNLOCKED" },
	Level = { color = Color3.fromRGB(255, 214, 102), sound = "NoticeBanner", banner = "LEVEL UP" },
	Stock = { color = Color3.fromRGB(193, 173, 244), sound = "NoticeBanner", banner = "SEED SHOP" },
}

local WINDOWS = { Quests = true, Research = true, Shop = true, Achievements = true }

-- Seconds a notice stays: a base, plus reading time for its length, up to a cap. A refusal answers
-- a press the player just made, so it leaves sooner; a banner is read from further away.
local BASE, PER_CHARACTER, LONGEST = 2.5, 0.045, 6
local ERROR_BASE = 1.8
local BANNER_EXTRA = 1.5

local AMOUNT = "%+([%d,]+) coins"

local Notices = {}

Notices.DEFAULT = "Info" :: Kind

-- Whether an untrusted value names a kind.
function Notices.isKind(value: unknown): boolean
	return typeof(value) == "string" and LOOKS[value :: Kind] ~= nil
end

function Notices.color(kind: Kind): Color3
	return (LOOKS[kind] or LOOKS.Info).color
end

function Notices.sound(kind: Kind): string?
	return (LOOKS[kind] or LOOKS.Info).sound
end

-- The banner caption of a big moment; nil for a routine notice.
function Notices.banner(kind: Kind): string?
	return (LOOKS[kind] or LOOKS.Info).banner
end

function Notices.lifetime(message: string, kind: Kind): number
	local base = if kind == "Error" then ERROR_BASE else BASE
	local seconds = math.min(LONGEST, base + utf8.len(message) :: number * PER_CHARACTER)
	return if Notices.banner(kind) then seconds + BANNER_EXTRA else seconds
end

-- The Detail in an untrusted value: only its known fields, each of the right type, and only a
-- window a notice may open. Whether `item` names a real item is for the caller, which has the
-- catalogue.
function Notices.detail(value: unknown): Detail
	local detail: Detail = {}
	if typeof(value) ~= "table" then
		return detail
	end
	local raw = value :: { [unknown]: unknown }
	if typeof(raw.item) == "string" then
		detail.item = raw.item
	end
	if typeof(raw.open) == "string" and WINDOWS[raw.open] then
		detail.open = raw.open
	end
	detail.quiet = raw.quiet == true
	return detail
end

-- What two notices must share to merge on screen, and the coins this one names. Two notices with
-- the same template are one line with a count; when both name coins, the line shows their sum
-- (`withAmount`). "Done! +50 coins" and "Done! +80 coins" share a template; a message without
-- "+N coins" is its own template and merges only with an exact repeat.
function Notices.template(message: string): (string, number?)
	local found = string.match(message, AMOUNT)
	if not found then
		return message, nil
	end
	local amount = tonumber((string.gsub(found, ",", "")))
	if not amount then
		return message, nil
	end
	return (string.gsub(message, AMOUNT, "+# coins", 1)), amount
end

-- A template's message with `amount` coins in it.
function Notices.withAmount(template: string, amount: number): string
	return (string.gsub(template, "%+# coins", `+{amount} coins`, 1))
end

return Notices
