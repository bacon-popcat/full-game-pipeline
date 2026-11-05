-- SettingsService: saves each player's preferences (Shared/Settings) in their own ProfileStore
-- profile, `GardenSettings_v1` keyed by user id, apart from the save files so a preference
-- holds across every garden and in the save menu. Each value is mirrored as a Player attribute
-- of the same name for that player's client to apply. A change sent before the profile loads
-- is kept and written once it does; a profile that can't be opened leaves the defaults and
-- the session's changes unsaved.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Settings = require(ReplicatedStorage.Shared.Settings)
local ProfileStore = require(ServerStorage.ServerPackages.ProfileStore)

type Data = { [Settings.Name]: string }
type Profile = {
	Data: Data,
	EndSession: (Profile) -> (),
	IsActive: (Profile) -> boolean,
	AddUserId: (Profile, number) -> (),
	Reconcile: (Profile) -> (),
}

local store = ProfileStore.New("GardenSettings_v1", table.clone(Settings.DEFAULTS))
local profiles: { [Player]: Profile } = {}
-- Changes made before the player's profile loaded, written into it once it does.
local pending: { [Player]: Data } = {}
local closing = false
local SettingsService = {}

local function mirror(player: Player, values: Data)
	for name, value in values do
		player:SetAttribute(name, value)
	end
end

local function onPlayer(player: Player)
	mirror(player, Settings.DEFAULTS)
	local profile: Profile? = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return closing or player.Parent ~= Players
		end,
	})
	if not profile then
		return
	end
	if closing or player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	for name, value in profile.Data do
		if not Settings.valid(name, value) then
			warn(`SettingsService: skipping saved {name} = {value} for {player.UserId}`)
			profile.Data[name] = Settings.DEFAULTS[name]
		end
	end
	for name, value in pending[player] or {} do
		profile.Data[name] = value
	end
	pending[player] = nil
	profiles[player] = profile
	mirror(player, profile.Data)
end

local function onChange(player: Player, name: any, value: any)
	if not Settings.valid(name, value) then
		return
	end
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile.Data[name] = value
	else
		local queued = pending[player] or {}
		queued[name] = value
		pending[player] = queued
	end
	player:SetAttribute(name, value)
end

function SettingsService.init()
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
		local profile = profiles[player]
		profiles[player] = nil
		if profile then
			profile:EndSession()
		end
	end)
	Remotes.Settings.OnServerEvent:Connect(onChange)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	game:BindToClose(function()
		closing = true
	end)
end

return SettingsService
