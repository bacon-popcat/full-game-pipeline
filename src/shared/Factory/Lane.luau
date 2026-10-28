--!strict
-- Lane: how items move along one conveyor path. The server runs it to decide where items
-- are; each client runs the same rule between server updates to draw them, so a lane only
-- has to be resent when an item joins or leaves it, never as items slide.
--
-- Items are kept front first (largest `d` first). Each moves at the lane's speed until it
-- reaches the end of the lane or closes to SPACING studs behind the item ahead, so a
-- blocked front item backs the whole lane up. Only the owner of the lane (the server)
-- moves an item off the end; the rule itself never does.

export type Item = {
	-- Unique per item for its whole trip, so a client can keep drawing the same model as
	-- the item crosses from lane to lane.
	id: number,
	itemId: string,
	-- Studs travelled along the lane.
	d: number,
}

local SPACING = 1.5

local Lane = {}

Lane.SPACING = SPACING

function Lane.advance(items: { Item }, dt: number, speed: number, length: number)
	local limit = length
	for _, item in items do
		if item.d < limit then
			item.d = math.min(item.d + speed * dt, limit)
		end
		limit = item.d - SPACING
	end
end

-- Whether a new item fits at the start of the lane.
function Lane.hasRoom(items: { Item }): boolean
	local last = items[#items]
	return last == nil or last.d >= SPACING
end

-- The front item, if it has reached the end and waits to be moved on.
function Lane.waiting(items: { Item }, length: number): Item?
	local front = items[1]
	return if front and front.d >= length - 1e-3 then front else nil
end

-- Puts an item in at its own `d` if it keeps SPACING from every item already there, keeping
-- the lane front first. Returns whether it fit.
function Lane.insert(items: { Item }, item: Item): boolean
	local at = #items + 1
	for index, other in items do
		if math.abs(other.d - item.d) < SPACING then
			return false
		end
		if other.d < item.d and at > index then
			at = index
		end
	end
	table.insert(items, at, item)
	return true
end

-- Where `position` falls along a polyline: the studs along it of the nearest point on it,
-- and how far `position` is from that point.
function Lane.project(points: { Vector3 }, position: Vector3): (number, number)
	local bestD, bestDistance = 0, math.huge
	local travelled = 0
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local span = (b - a).Magnitude
		local direction = if span > 0 then (b - a) / span else Vector3.zero
		local along = math.clamp((position - a):Dot(direction), 0, span)
		local distance = (position - (a + direction * along)).Magnitude
		if distance < bestDistance then
			bestD, bestDistance = travelled + along, distance
		end
		travelled += span
	end
	return bestD, bestDistance
end

-- A point `d` studs along a polyline, with the direction it travels there.
function Lane.pointAt(points: { Vector3 }, d: number): (Vector3, Vector3)
	local left = d
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local span = (b - a).Magnitude
		if left <= span or index == #points - 1 then
			local direction = if span > 0 then (b - a) / span else Vector3.zAxis
			return a + direction * math.clamp(left, 0, span), direction
		end
		left -= span
	end
	return points[1], Vector3.zAxis
end

function Lane.length(points: { Vector3 }): number
	local total = 0
	for index = 1, #points - 1 do
		total += (points[index + 1] - points[index]).Magnitude
	end
	return total
end

return Lane
