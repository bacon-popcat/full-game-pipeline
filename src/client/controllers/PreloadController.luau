-- PreloadController: downloads the game's content on join, so a first look at a crop, a
-- machine, a backpack icon or a sound isn't a blank or a silence while it streams in. It
-- only warms ContentProvider's cache and never blocks play: everything works before it
-- finishes, just with a moment's pop-in.
--
-- Order is what a new player meets first: the HUD and its UI templates, the sound palette,
-- then the templates in ReplicatedStorage.Assets from the small and soon-seen (Items, Tools)
-- to the large (Blocks, World). Each group is its own PreloadAsync so the early ones land
-- before the later ones start. A group missing from the place is skipped quietly; the
-- screens that use it warn on their own (Hud.find). Music goes last: MusicController waits
-- a few seconds before its first track and checks that track's own load.
--
-- The world itself isn't here: workspace streams (StreamingEnabled), so its parts arrive
-- with their content as the player walks.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Music = require(ReplicatedStorage.Shared.Music)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local PreloadController = {}

local ASSET_GROUPS = { "UI", "Items", "Tools", "Props", "Blocks", "World" }

local function preload(label: string, content: { any })
	if #content == 0 then
		return
	end
	local started = os.clock()
	local failed = 0
	local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, content, function(id, status)
		-- an unset Image or Texture reports as a failed fetch of ""
		if status == Enum.AssetFetchStatus.Failure and id ~= "" then
			failed += 1
		end
	end)
	if not ok then
		warn(`PreloadController: {label} failed to preload: {err}`)
	elseif failed > 0 then
		warn(`PreloadController: {failed} asset(s) in {label} failed to download`)
	end
	PreloadController.loaded[label] = os.clock() - started
end

-- A bare id string is fetched as an image, so audio has to go in as Sound instances.
local function sounds(ids: { string }): { Sound }
	local list = {}
	for _, id in ids do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(list, sound)
		end
	end
	return list
end

-- Seconds each finished group took, by label; read it in a playtest to see what's slow.
PreloadController.loaded = {} :: { [string]: number }

function PreloadController.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD", 10)
	preload("HUD", { hud })

	local soundIds = {}
	for _, role in Sounds do
		table.insert(soundIds, role.id)
	end
	preload("Sounds", sounds(soundIds))

	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	for _, name in ASSET_GROUPS do
		local group = assets and assets:FindFirstChild(name)
		preload(name, { group })
	end

	local trackIds = {}
	for _, track in Music.TRACKS do
		table.insert(trackIds, track.id)
	end
	preload("Music", sounds(trackIds))
end

return PreloadController
