# Sounds

The game's sound palette (`src/shared/Sounds.luau`). Each role's file is uploaded as an audio asset
with the Open Cloud Assets API (`POST apis.roblox.com/assets/v1/assets`, a key with asset write
access in `ROBLOX_API_KEY`, creator user 1636829198) by
`python tools/sounds/upload.py <file> "<name>" "<description>"`, which prints the asset id; that id
goes in the role in `Sounds.luau`. To swap a take, upload the new file and replace the role's id.

## The game cues: Roblox style (synthesized)

The garden, reward and notice cues sound like a Roblox simulator: bright, bouncy and short, built
by `tools/sounds/synth.py` with the standard library from blips (a rounded square wave that scoops
up a semitone into its note), bubble pops (a near-sine sweeping in pitch), bell pings, quick major
arpeggios and scattered sparkles, all in C major or G so overlapping cues agree.
`python tools/sounds/synth.py [Role ...]` rebuilds the WAVs exactly. They replaced a softer
palette of wood, soil and chimes (ElevenLabs takes and earlier synth recipes, kept in git history
and in the last column, so a role can go back by its id). None of these was chosen by ear.

Volumes in `Sounds.luau` are set from measured loudness so each cue sits about as loud as the one
it replaced: a brighter cue gets a lower volume.

| Role | File | Asset id | Sound | Earlier id |
|---|---|---|---|---|
| Plant | Garden_Plant.wav | 108581884979353 | a bubbly bloop dropping in pitch over a soft soil pat, 0.3 s | 90385484162031 (ElevenLabs soil pat) |
| Harvest | Garden_Harvest.wav | 120566065392427 | a quick leafy tug and stem snap, then a bright bubble pop rising out of it with a small G6 blip, 0.45 s | 121632984070614 (rustle, snap, crumbs) |
| HarvestRare | Garden_HarvestRare.wav | 116274355495687 | a twinkling run up C6 D6 E6 G6 A6 C7 at 35 ms a note, then sparkles, layered over Harvest, 1 s | 90954647450235 |
| Coin | Garden_Coin.wav | 80805932029640 | the classic coin: a short B5 jumping to a ringing E6, 0.4 s | 126449219917694 (ElevenLabs chime) |
| Buy | Garden_Buy.wav | 118394111171147 | a bubble pop up into a C6-G6 ding, 0.45 s | 133840506516150 (ElevenLabs click) |
| Craft | Garden_Craft.wav | 104827661586586 | a wooden tap, a pop and a quick C6 E6 G6 arpeggio to a ping, 0.6 s | 104446383390823 |
| Step | Garden_Step.wav | 110150377452756 | two blips up a fourth, G5 to C6, 0.45 s | 110055073598907 (ElevenLabs marimba) |
| LevelUp | Garden_LevelUp.wav | 78053196984145 | a C5 E5 G5 arpeggio up to a ringing C major chord with sparkles, 1.7 s | 138182978724965 (ElevenLabs shimmer) |
| ResearchDone | Garden_ResearchDone.wav | 110212030422183 | a slower bell arpeggio up G major (G5 B5 D6 G6) over a warm swell, then twinkles, 1.9 s | 117847291795847 |
| NoticeError | Garden_NoticeError.wav | 94091563133765 | a low "nuh-uh": E4 then C4 sagging flat, low-passed, 0.35 s | 88770489922620 |
| NoticeReward | Garden_NoticeReward.wav | 115224806235121 | a three-note bling up C6 E6 G6 with a few sparkles, 0.7 s | 128450852333088 |
| NoticeBanner | Garden_NoticeBanner.wav | 103094767156685 | a five-note run up C5 to E6 over a chord swell, with sparkles, 1.5 s | 82992648114553 |

## World sounds

These stay material, not game-like. Water is an ElevenLabs take (`eleven_text_to_sound_v2`):
`Garden_Water.mp3`, "gentle splash from a small watering can onto soil", asset 95345293500300.
`takes/` holds every ElevenLabs take; the other `Garden_*.mp3` files are the replaced ElevenLabs
cues. Chop and TreeFall are synthesized by `synth.py` (wood is a struck tone with a filtered noise
click, leaves are band-passed noise grains):

| Role | File | Asset id | Sound |
|---|---|---|---|
| Chop | Garden_Chop.wav | 110876799577978 | a soft low wooden thock with a little crack, 0.4 s |
| TreeFall | Garden_TreeFall.wav | 97110688548965 | a low creak, a leafy whoosh and a soft thud, 1.7 s |

## Checking a recipe

Every synthesized tone eases out at its end (`fade_out`): a tone still ringing at about -22 dB
that stops dead is heard as a click.

`python tools/sounds/analyze.py [Role ...]` measures the WAVs so they can be tuned by numbers:
length, peak, loudness, brightness, each note's start time and pitch, and a spectrogram PNG per
sound in `tools/sounds/analysis/` (not in git). Rerun it after changing a recipe: the note times
and pitches should match the recipe, and the spectrogram should show no vertical smear where a
sound ends (a click).
