-- MusicController: plays Shared/Music's calm tracks in the background, flat to this player.
-- Each track fades in, plays through, fades out, then a quiet gap of a random length before the
-- next; the order is reshuffled every pass and never repeats the track that just played. Tracks
-- with no id are skipped, so the game is whole without music. The playing track's name is the
-- Sound's `Track` attribute, for the now-playing card. The music button (UIController/MusicPlayer)
-- pauses, resumes and skips through isPaused/setPaused/skip.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Music = require(ReplicatedStorage.Shared.Music)
local AudioSettings = require(script.Parent.Parent.Libraries.AudioSettings)

local MusicController = {}

-- The music button's controls (UIController/MusicPlayer). Both live on the one Sound.
local paused = false
local skipping = false
local music: Sound? = nil
local SKIP_FADE = 0.6

function MusicController.isPaused(): boolean
	return paused
end

function MusicController.setPaused(value: boolean)
	paused = value
	if music then
		music:SetAttribute("Paused", value)
		if value then
			music:Pause()
		else
			music:Resume()
		end
	end
end

-- Fades the current track (or the gap before the next one) out early and moves on.
function MusicController.skip()
	skipping = true
	if paused then
		MusicController.setPaused(false)
	end
end

-- Waits `seconds` of unpaused time; returns true if the player skipped meanwhile.
local function rest(seconds: number): boolean
	local waited = 0
	while waited < seconds do
		task.wait(0.1)
		if skipping then
			return true
		end
		if not paused then
			waited += 0.1
		end
	end
	return false
end

local function shuffled(last: string?): { Music.Track }
	local order = {}
	for _, track in Music.TRACKS do
		if track.id ~= "" then
			table.insert(order, track)
		end
	end
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	if #order > 1 and order[1].id == last then
		order[1], order[#order] = order[#order], order[1]
	end
	return order
end

local function play(sound: Sound, track: Music.Track)
	sound.SoundId = track.id
	sound.Volume = 0
	sound.TimePosition = 0
	pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
	if not sound.IsLoaded or sound.TimeLength <= 0 then
		return
	end
	local fade = TweenInfo.new(Music.FADE, Enum.EasingStyle.Sine)
	skipping = false
	sound:Play()
	-- The now-playing card (UIController/NowPlaying) reads this.
	sound:SetAttribute("Track", track.name)
	TweenService:Create(sound, fade, { Volume = Music.VOLUME }):Play()
	-- TimePosition stands still while paused, so the track's length is counted in played time.
	while sound.TimePosition < sound.TimeLength - Music.FADE and not skipping do
		task.wait(0.1)
	end
	local out = TweenService:Create(
		sound,
		if skipping then TweenInfo.new(SKIP_FADE, Enum.EasingStyle.Sine) else fade,
		{ Volume = 0 }
	)
	out:Play()
	out.Completed:Wait()
	sound:Stop()
	sound:SetAttribute("Track", nil)
end

function MusicController.init()
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Looped = false
	AudioSettings.attachMusic(sound)
	sound.Parent = SoundService
	music = sound
	sound:SetAttribute("Paused", false)
	task.spawn(function()
		-- a short breath after joining before the first track
		rest(3)
		local last: string? = nil
		while true do
			local order = shuffled(last)
			if #order == 0 then
				return
			end
			for _, track in order do
				play(sound, track)
				last = track.id
				rest(Music.GAP_MIN + math.random() * (Music.GAP_MAX - Music.GAP_MIN))
			end
		end
	end)
end

return MusicController
