--!strict
-- Weather: every weather event and what it does, the one table WeatherService (scheduling, growth
-- clock), WorldService (mutation chances), GroundService (wet soil) and the client (rain, tint,
-- wind) read. No event harms crops.
--
-- growth: extra growth seconds per real second (0.5 = crops grow 1.5x as fast).
-- wets: waters Farmland like a sprinkler. wet/shocked/golden/rainbow: added mutation chances.
-- rain: client drop rate (0 = none). tint/brightness/contrast: the Lighting request.
-- wind: plant sway multiplier. lightning: occasional soft flashes.

export type Event = {
	duration: number,
	weight: number,
	growth: number,
	wets: boolean,
	wet: number,
	shocked: number,
	golden: number,
	rainbow: number,
	rain: number,
	tint: Color3?,
	brightness: number,
	contrast: number,
	wind: number,
	lightning: boolean,
}

local function event(fields: { [string]: any }): Event
	return {
		duration = fields.duration,
		weight = fields.weight or 1,
		growth = fields.growth or 0,
		wets = fields.wets or false,
		wet = fields.wet or 0,
		shocked = fields.shocked or 0,
		golden = fields.golden or 0,
		rainbow = fields.rainbow or 0,
		rain = fields.rain or 0,
		tint = fields.tint,
		brightness = fields.brightness or 0,
		contrast = fields.contrast or 0,
		wind = fields.wind or 1,
		lightning = fields.lightning or false,
	}
end

local EVENTS: { [string]: Event } = {
	Rain = event({
		duration = 300,
		growth = 0.5,
		wets = true,
		wet = 0.25,
		rain = 380,
		tint = Color3.fromRGB(196, 209, 230),
		brightness = -0.1,
		contrast = 0.05,
		wind = 1.6,
	}),
	Drizzle = event({
		duration = 360,
		growth = 0.25,
		wets = true,
		wet = 0.12,
		rain = 140,
		tint = Color3.fromRGB(214, 222, 236),
		brightness = -0.05,
		contrast = 0.02,
		wind = 1.2,
	}),
	Thunderstorm = event({
		duration = 240,
		weight = 0.8,
		growth = 0.5,
		wets = true,
		wet = 0.25,
		shocked = 0.05,
		rain = 380,
		tint = Color3.fromRGB(172, 186, 214),
		brightness = -0.18,
		contrast = 0.05,
		wind = 2.4,
		lightning = true,
	}),
	["Golden Hour"] = event({
		duration = 180,
		golden = 0.05,
		tint = Color3.fromRGB(255, 231, 187),
		brightness = 0.03,
		contrast = 0.02,
		wind = 0.6,
	}),
	Fog = event({
		duration = 300,
		growth = 0.15,
		wet = 0.06,
		tint = Color3.fromRGB(226, 230, 236),
		brightness = 0.02,
		contrast = -0.12,
		wind = 0.4,
	}),
	Breezy = event({
		duration = 300,
		growth = 0.2,
		wind = 3.2,
	}),
	Rainbow = event({
		duration = 150,
		weight = 0.5,
		growth = 0.25,
		golden = 0.02,
		rainbow = 0.004,
		tint = Color3.fromRGB(250, 236, 246),
		brightness = 0.04,
		contrast = 0.03,
		wind = 0.8,
	}),
}

local NAMES: { string } = {}
for name in EVENTS do
	table.insert(NAMES, name)
end
table.sort(NAMES)

local Weather = { EVENTS = EVENTS, NAMES = NAMES }
-- Seconds of clear sky between one event's end and the next one's start.
Weather.GAP_MIN = 300
Weather.GAP_MAX = 480

function Weather.get(name: string?): Event?
	return if name then EVENTS[name] else nil
end

-- One weighted pick.
function Weather.pick(random: Random): string
	local total = 0
	for _, name in NAMES do
		total += EVENTS[name].weight
	end
	local roll = random:NextNumber() * total
	for _, name in NAMES do
		roll -= EVENTS[name].weight
		if roll <= 0 then
			return name
		end
	end
	return NAMES[#NAMES]
end

return Weather
