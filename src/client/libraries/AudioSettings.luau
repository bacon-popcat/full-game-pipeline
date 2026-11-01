-- AudioSettings: session-local music preference. A separate group preserves track fades
-- while muted and applies the preference to future tracks as well as the current one.
local SoundService = game:GetService("SoundService")
local AudioSettings = {}
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "GardenMusic"
musicGroup.Volume = 1
musicGroup.Parent = SoundService

function AudioSettings.attachMusic(sound: Sound)
	sound.SoundGroup = musicGroup
end

function AudioSettings.musicEnabled(): boolean
	return musicGroup.Volume > 0
end

function AudioSettings.setMusicEnabled(enabled: boolean)
	musicGroup.Volume = if enabled then 1 else 0
end

return AudioSettings
