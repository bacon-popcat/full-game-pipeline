--!strict
-- TextColors: the game's text palette and the rich-text helpers that apply it. Every screen that
-- colours a word by what it means (coins, XP, a time, a level, an item, a rarity) takes the colour
-- from here, so gold always means coins and mint always means XP.
--
-- `paint` wraps one already-known piece; `highlight` finds the meaningful pieces in a sentence the
-- screen did not write itself (an onboarding step, a notice, a block hint) and paints those. Both
-- escape their text, so a player's name or an item with "<" in it can't break the markup. The
-- label they are shown in needs RichText on; the screen sets it when it binds the label.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = require(ReplicatedStorage.Shared.Economy.Content)
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local World = require(ReplicatedStorage.Shared.World)

local TextColors = {}

TextColors.WHITE = Color3.fromRGB(245, 245, 250)
TextColors.MUTED = Color3.fromRGB(176, 178, 196)
TextColors.COINS = Color3.fromRGB(255, 214, 102)
TextColors.XP = Color3.fromRGB(126, 226, 160)
TextColors.TIME = Color3.fromRGB(142, 197, 255)
TextColors.LEVEL = Color3.fromRGB(255, 160, 92)
TextColors.NUMBER = Color3.fromRGB(255, 238, 196)
TextColors.GOOD = Color3.fromRGB(157, 220, 154)
TextColors.BAD = Color3.fromRGB(240, 140, 130)
TextColors.RESEARCH = Color3.fromRGB(193, 173, 244)
-- Item names, by kind; a crop or its seeds takes the crop's own colour instead.
TextColors.ITEM = Color3.fromRGB(255, 205, 150)
TextColors.TOOL = Color3.fromRGB(150, 215, 200)
TextColors.BLOCK = Color3.fromRGB(222, 196, 160)
TextColors.MACHINE = Color3.fromRGB(186, 170, 255)

local KIND_COLORS: { [string]: Color3 } = {
	Tool = TextColors.TOOL,
	Block = TextColors.BLOCK,
	Machine = TextColors.MACHINE,
	Resource = TextColors.ITEM,
}

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

function TextColors.escape(text: string): string
	return (
		text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
	)
end

-- `text`, escaped, in `color`.
function TextColors.paint(text: string, color: Color3): string
	return `<font color="{hex(color)}">{TextColors.escape(text)}</font>`
end

function TextColors.rarity(name: string): Color3
	local rarity = Content.RARITIES[name]
	return if rarity then rarity.color else TextColors.WHITE
end

-- "+120 coins  ·  30 XP", painted; the empty string when both are zero.
function TextColors.reward(coins: number, xp: number, format: (number) -> string): string
	local parts = {}
	if coins > 0 then
		table.insert(parts, TextColors.paint(`+{format(coins)} coins`, TextColors.COINS))
	end
	if xp > 0 then
		table.insert(parts, TextColors.paint(`+{format(xp)} XP`, TextColors.XP))
	end
	return table.concat(parts, `<font color="{hex(TextColors.MUTED)}">  ·  </font>`)
end

type Rule = { pattern: string, color: Color3 }

local function literal(text: string): string
	return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Built on first use: every plain item's name, longest first so "Wood Planks" wins over "Wood".
local names: { Rule }? = nil
local function itemRules(): { Rule }
	if names then
		return names
	end
	local list: { Rule } = {}
	local seen: { [string]: boolean } = {}
	local cropColors: { [string]: Color3 } = {}
	for _, crop in World.CROPS do
		cropColors[crop.produce] = crop.color
		cropColors[crop.seed] = crop.color
	end
	for id, item in Inventory.ITEMS do
		if item.base or seen[item.name] then
			continue
		end
		seen[item.name] = true
		local color = cropColors[id] or KIND_COLORS[item.kind] or TextColors.ITEM
		table.insert(list, { pattern = `%f[%w]{literal(item.name)}%f[%W]`, color = color })
	end
	table.sort(list, function(a, b)
		return #a.pattern > #b.pattern
	end)
	names = list
	return list
end

local RULES: { Rule } = {
	{ pattern = "[%+%-]?%d[%d,]* coins?", color = TextColors.COINS },
	{ pattern = "[%+%-]?%d[%d,]* XP", color = TextColors.XP },
	{ pattern = "%f[%w]Level %d+", color = TextColors.LEVEL },
	{ pattern = "%f[%w]Lv %d+", color = TextColors.LEVEL },
	{ pattern = "%d+h %d+m", color = TextColors.TIME },
	{ pattern = "%d+m %d+s", color = TextColors.TIME },
	{ pattern = "%f[%d]%d+:%d%d", color = TextColors.TIME },
	{ pattern = "%f[%d]%d+[hms]%f[%W]", color = TextColors.TIME },
}

-- Recent results, since panels repaint the same few lines several times a second; cleared
-- whole when it fills rather than tracking age.
local CACHE_LIMIT = 512
local cache: { [string]: string } = {}
local cached = 0

local function find(text: string): string
	local spans: { { number } } = {}
	local colors: { Color3 } = {}
	local taken: { [number]: boolean } = {}
	local function claim(pattern: string, color: Color3)
		local init = 1
		while init <= #text do
			local first, last = string.find(text, pattern, init)
			if not first or not last then
				return
			end
			while last >= first and string.find(string.sub(text, last, last), "[,%.%s]") do
				last -= 1
			end
			if last < first then
				init = first + 1
				continue
			end
			local free = true
			for index = first, last do
				if taken[index] then
					free = false
					break
				end
			end
			if free then
				for index = first, last do
					taken[index] = true
				end
				table.insert(spans, { first, last })
				table.insert(colors, color)
			end
			init = last + 1
		end
	end
	for _, rule in RULES do
		claim(rule.pattern, rule.color)
	end
	for name, rarity in Content.RARITIES do
		claim(`%f[%w]{name}%f[%W]`, rarity.color)
	end
	for _, rule in itemRules() do
		claim(rule.pattern, rule.color)
	end
	claim("%f[%d]%d[%d,%.]*", TextColors.NUMBER)
	if #spans == 0 then
		return TextColors.escape(text)
	end
	local order = {}
	for index in spans do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		return spans[a][1] < spans[b][1]
	end)
	local out = {}
	local at = 1
	for _, index in order do
		local first, last = spans[index][1], spans[index][2]
		table.insert(out, TextColors.escape(string.sub(text, at, first - 1)))
		table.insert(out, TextColors.paint(string.sub(text, first, last), colors[index]))
		at = last + 1
	end
	table.insert(out, TextColors.escape(string.sub(text, at)))
	return table.concat(out)
end

-- `text` with its coins, XP, levels, times, rarities, item names and numbers painted.
function TextColors.highlight(text: string): string
	local hit = cache[text]
	if hit then
		return hit
	end
	if cached >= CACHE_LIMIT then
		table.clear(cache)
		cached = 0
	end
	local painted = find(text)
	cache[text] = painted
	cached += 1
	return painted
end

return TextColors
