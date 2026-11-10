--!strict
-- Hud: safe authored-instance binding and shared number/countdown text for garden screens.
-- Missing or mistyped nodes warn once; no screen creates its own authored hierarchy.
local Hud = {}
local warned: { [string]: boolean } = {}

-- The screen the always-on HUD is drawn for. Its pieces are authored in Scale, each a share of
-- a REFERENCE_WIDTH x REFERENCE_HEIGHT screen, with a UIAspectRatioConstraint keeping its shape
-- (so it follows whichever of the two axes is tighter). Code that sizes HUD pieces in pixels
-- uses `zoom`. No piece has a minimum size: on a phone a floor would push the left column and
-- the hotbar into each other, while pure proportion keeps the reference arrangement.
Hud.REFERENCE_WIDTH = 1280
Hud.REFERENCE_HEIGHT = 720

-- How many times the reference size the HUD is drawn on a screen of `size`.
function Hud.zoom(size: Vector2): number
	return math.min(size.X / Hud.REFERENCE_WIDTH, size.Y / Hud.REFERENCE_HEIGHT)
end

function Hud.find(root: Instance, path: string, className: string): Instance?
	local node: Instance? = root
	for name in string.gmatch(path, "[^%.]+") do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node and node:IsA(className) then
		return node
	end
	local key = root:GetFullName() .. "." .. path
	if not warned[key] then
		warned[key] = true
		warn(`HUD: {key} must be an authored {className}`)
	end
	return nil
end

function Hud.number(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse(text):gsub("(%d%d%d)", "%1,")
	return (string.reverse(formatted):gsub("^,", ""))
end

function Hud.time(seconds: number): string
	local left = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(left / 60), left % 60)
end

-- A stretch of time in words: "5h 12m", "12m", "under a minute".
function Hud.span(seconds: number): string
	local minutes = math.ceil(math.max(0, seconds) / 60)
	if minutes >= 60 then
		return `{minutes // 60}h {minutes % 60}m`
	end
	return if minutes > 1 then `{minutes}m` else "under a minute"
end
return Hud
