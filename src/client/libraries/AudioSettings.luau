-- AudioSettings: session-local music and sound-effect volumes, 0 to 1. Each plays through its
-- own SoundGroup, so music keeps its track fades and every future sound follows the setting.
local SoundService = game:GetService("SoundService")
local AudioSettings = {}

local function group(name: string): SoundGroup
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Volume = 1
	created.Parent = SoundService
	return created
end
local musicGroup = group("GardenMusic")
local sfxGroup = group("GardenSfx")

function AudioSettings.attachMusic(sound: Sound)
	sound.SoundGroup = musicGroup
end

function AudioSettings.attachSfx(sound: Sound)
	sound.SoundGroup = sfxGroup
end

function AudioSettings.musicVolume(): number
	return musicGroup.Volume
end

function AudioSettings.setMusicVolume(volume: number)
	musicGroup.Volume = math.clamp(volume, 0, 1)
end

function AudioSettings.sfxVolume(): number
	return sfxGroup.Volume
end

function AudioSettings.setSfxVolume(volume: number)
	sfxGroup.Volume = math.clamp(volume, 0, 1)
end

return AudioSettings
