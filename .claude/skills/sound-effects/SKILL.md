---
name: sound-effects
description: Generate a small, coherent sound palette for game moments (UI presses, pickups, rewards, jobs finishing, rare drops, ambience) through interchangeable provider adapters, starting with ElevenLabs Sound Effects, then wire it into Roblox and check in a playtest that the cues clarify rather than distract. Use when the game needs interaction sounds, feedback cues, gameplay sounds, ambience, or audio polish. Triggers on sound effects, SFX, UI sounds, harvest sound, click sound, machine sound, ambience, ElevenLabs sound effects, audio feedback.
---

# Sound Effects

Sound is feedback, not wallpaper. Generate a short cue only when it confirms a change the
player needs to feel: an item landing in the inventory, a reward, a job finishing, a rare
drop, a panel opening. Never add one just because something moves. This is rung 4 of the
`game-feel` feedback ladder: check that the lower rungs aren't already enough.

## Before generating

1. Name the moment and the change it confirms. If the screen or the world already makes it
   obvious (something visibly moving or changing state), don't add a sound.
2. Match the game's target feel (from its design doc, or ask). Settle on a few material
   words, such as "wood, soil, soft chimes" for a cozy game or "metal, servo, punchy" for a
   mech game, and use them in every prompt, so the palette sounds like one game.
3. Sounds never carry meaning on their own, never autoplay loud, and the game must work with
   them muted.

## Generate a palette, not isolated noises

Start with three to five roles. Keep each one short, and quieter than music.

| Moment | Duration | Prompt shape (cozy example) |
| --- | --- | --- |
| UI press / select | 0.50 s | soft dry wooden click, no voice, no melody |
| Pick up / collect | 0.50 s | gentle pluck with a soft thump, warm |
| Currency gained | 0.50–0.70 s | small soft coin chime, rounded, short decay |
| Job finished | 0.50–0.80 s | muted mechanical clunk and a soft bell tick |
| Rare reward | 0.80–1.20 s | sparkling upward shimmer, airy |
| Ambience (loop) | 10–20 s | the world's background, quiet, no voice |

Swap in the game's own material words; keep the durations and the roles.

Always exclude voice and melody, and generate two or three alternatives per role so the user
can choose by listening side by side.

## Provider adapters

ElevenLabs is the first adapter, not the architecture. The generator takes a `--provider` name
and loads `scripts/providers/<name>.py`; every adapter shares the same prompt, duration, loop,
output and receipt contract. Read `references/provider-adapters.md` before adding one.

The ElevenLabs adapter calls `POST /v1/sound-generation` with `ELEVENLABS_API_KEY` from the
local environment. Never put the key in a prompt, source code, the repo or a committed `.env`.

```bash
python scripts/generate_sound.py --provider elevenlabs --name harvest-pluck --text "A gentle leafy pluck with a soft soil thump; warm, calm, quiet, no voice, no melody" --duration 0.5 --out "<scratchpad>/sounds/harvest-pluck.mp3"
```

Write generated audio to the session scratchpad (or a `sounds/` folder the user names), not
into `src/`, because Rojo doesn't sync audio files. ElevenLabs accepts durations from 0.5 s.
Use `--loop` only for ambience. The script writes the audio plus a JSON receipt with the
prompt and parameters, never the key.

## Wire into Roblox

- **Upload**: the user uploads the chosen files as Audio assets (Creator Hub or Studio's
  Asset Manager). Record each asset id with its role in one shared module (for example
  `SFX`), so swapping a sound is a single edit.
- **Play on the client** for the local player's own actions, after the visual change starts.
  A sound that plays before a change the server then rejects is misleading. For other players'
  actions, play the sound spatially at its source, and only within a sensible distance.
- Route everything through SoundGroups (SFX, Ambience, Music), so there can be a volume and
  mute setting per group. Use one sound per completed gesture, and rate-limit repeats, such as
  many pickups in a row.
- For the Audio API, emitters and mixing, see `roblox-skills:roblox-audio`.

## Check

Playtest it (`studio-playtest`): do the action normally, quickly over and over, and with
several players near each other. Ask whether each cue makes clear what happened. If one only
repeats what the screen shows, or gets tiring after a minute, remove it.

## Boundaries

- Never generate speech here; use a speech tool for narration.
- Never spend credits or call the API until the user approves the chosen prompts and the
  number of variations.
