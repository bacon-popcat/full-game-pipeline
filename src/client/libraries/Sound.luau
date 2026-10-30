--!strict
-- Sound: plays a role from Shared/Sounds. A spatial role played with a position sounds from that
-- spot (quieter with distance); anything else plays flat to this player. A role with no id is
-- silent. Each play is a short-lived Sound, cleaned up when it ends.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local Sound = {}

-- Studs within which a spatial sound plays at full volume, and past which it is silent.
local NEAR, FAR = 12, 90

function Sound.play(role: string, position: Vector3?)
	local def = Sounds[role]
	if not def or def.id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume
	-- a hair of variation so repeated plays don't sound stamped out
	sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	if def.spatial and position then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = workspace.Terrain
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = NEAR
		sound.RollOffMaxDistance = FAR
		sound.Parent = holder
		sound:Play()
		Debris:AddItem(holder, 4)
	else
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

return Sound
