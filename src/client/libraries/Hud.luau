--!strict
-- Hud: safe authored-instance binding and shared number/countdown text for garden screens.
-- Missing or mistyped nodes warn once; no screen creates its own authored hierarchy.
local Hud = {}
local warned: { [string]: boolean } = {}

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
return Hud
