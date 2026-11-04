-- ModuleScript: ReplicatedStorage/Shared/VFX/Textures
-- Textures drawn for our effects with tools/vfx/vfxtex.py (sources and PNGs in
-- assets/textures/). Each entry is { Id = "rbxassetid://...", Grid = 4 } (Grid = flipbook
-- grid, nil for a single image); pass it as an emitter's Texture through Layers, which sets
-- the flipbook layout from Grid.
--
-- Until a drawing is uploaded, its entry falls back to the closest library texture, so the
-- effects work right away. To switch to the drawn sheet: upload the PNG (textures.md,
-- "Making new textures"; upload the .flipbook.png, not the preview) and put its id in
-- UPLOADED below. Textures.Pending lists the ones still on a fallback.

local UPLOADED = {
	-- ImpactStar = "rbxassetid://...",
}

-- name = { file in assets/textures, grid, fallback id, fallback grid, what the fallback is }
local DRAWN = {
	ImpactStar = { "ImpactStar.flipbook.png", 4, "rbxassetid://136210055019402", nil }, -- fallback: Starburst (custom spiky flash)
	FireBurstA = { "FireBurstA.flipbook.png", 4, "rbxassetid://107423905441539", 4 }, -- fallback: FlipbookTextures/Blurry glowing flame
	FireBurstB = { "FireBurstB.flipbook.png", 4, "rbxassetid://107423905441539", 4 }, -- fallback: FlipbookTextures/Blurry glowing flame
	BurnOut = { "BurnOut.flipbook.png", 4, "rbxassetid://11866632577", 4 }, -- fallback: FlipbookTextures/Realistic Smoke Burst
	DustPuff = { "DustPuff.flipbook.png", 4, "rbxassetid://11866632577", 4 }, -- fallback: FlipbookTextures/Realistic Smoke Burst
	Splinters = { "Splinters.flipbook.png", 4, "rbxassetid://6893847210", nil }, -- fallback: StaticVFXTextures/Sideways Spec 50
	ClawSlash = { "ClawSlash.flipbook.png", 4, "rbxassetid://13580352351", 4 }, -- fallback: FlipbookTextures/Glowing Slash
	Glint = { "Glint.png", nil, "rbxassetid://16444981264", nil }, -- fallback: StaticVFXTextures/Star153
	ShockRing = { "ShockRing.png", nil, "rbxassetid://15268062056", nil }, -- fallback: StaticVFXTextures/thick ring 3
}

local Textures = { Pending = {} }

for name, entry in DRAWN do
	local id = UPLOADED[name]
	if id then
		Textures[name] = { Id = id, Grid = entry[2] }
	else
		Textures[name] = { Id = entry[3], Grid = entry[4], Fallback = true }
		table.insert(Textures.Pending, entry[1])
	end
end
table.sort(Textures.Pending)

return Textures
