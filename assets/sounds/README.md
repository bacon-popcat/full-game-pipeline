# Sounds

The game's sound palette (`src/shared/Sounds.luau`), generated with ElevenLabs sound effects
(`eleven_text_to_sound_v2`) in one family of material words: warm wood, soil, soft chimes, no
voice or melody. `Garden_<Role>.mp3` are the chosen takes; `takes/` holds every take so a role
can be swapped by ear. The `Garden_*.mp3` files are uploaded as audio assets with the Open Cloud
Assets API (`POST apis.roblox.com/assets/v1/assets`, a key with asset write access in
`ROBLOX_API_KEY`, creator user 1636829198); each asset id sits in its role in `Sounds.luau`. To
swap a take, upload the new file the same way and replace that role's id.

| Role | Asset id |
|---|---|
| Plant | 90385484162031 |
| Harvest | 140384005911871 |
| Coin | 126449219917694 |
| Buy | 133840506516150 |
| Water | 95345293500300 |
| Step | 110055073598907 |
| LevelUp | 138182978724965 |

| Role | File | Prompt |
|---|---|---|
| Plant | Garden_Plant.mp3 (Plant_1) | soft pat of damp garden soil, a small muffled earthy thump |
| Harvest | Garden_Harvest.mp3 (Harvest_2) | gentle pluck from soft soil with a light rounded pop and leaf rustle |
| Coin | Garden_Coin.mp3 (Coin_1) | soft coin chime, two small rounded bell notes |
| Buy | Garden_Buy.mp3 (Buy_1) | soft dry wooden click with a tiny bell tick |
| Water | Garden_Water.mp3 (Water_2) | gentle splash from a small watering can onto soil |
| Step | Garden_Step.mp3 (Step_1) | soft warm two-note wooden marimba confirmation |
| LevelUp | Garden_LevelUp.mp3 (LevelUp_1) | sparkling upward shimmer of soft chimes |

## Phase 7 roles (synthesized)

ElevenLabs sound generation failed on every attempt while phase 7 was built (its shared pool
refused or failed each take), so these roles are synthesized by `tools/sounds/synth.py` with the
standard library, in the same family: decaying sine partials for chimes, a struck tone with a
filtered noise click for wood, band-passed noise for leaves. `python tools/sounds/synth.py`
rebuilds the WAVs exactly; `python tools/sounds/upload.py <file> "<name>" "<description>"` uploads
one. The new Harvest replaces the ElevenLabs pluck (140384005911871); put that id back in
`Sounds.luau` to return to it. None of these was chosen by ear.

| Role | File | Asset id | Sound |
|---|---|---|---|
| Harvest | Garden_Harvest.wav | 121632984070614 | leaves rustling (scattered noise grains), a dry green stem snap, a soft soil thump with crumbs pattering down, and the leaves settling; no tones, 0.6 s. Replaced the phase 7 rustle-pop-sparkle (85383832508508) to sound more like nature |
| HarvestRare | Garden_HarvestRare.wav | 126550585056131 | three soft chimes rising (G6, B6, D7), layered over Harvest for a mutated crop, 1 s |
| Chop | Garden_Chop.wav | 136761976782388 | a soft low wooden thock with a little crack, 0.4 s |
| TreeFall | Garden_TreeFall.wav | 118623246906163 | a low creak, a leafy whoosh and a soft thud, 1.7 s |
| Craft | Garden_Craft.wav | 104446383390823 | two quick wooden taps and a click, 0.5 s |
| ResearchDone | Garden_ResearchDone.wav | 82850696869958 | a rising two-note chime (E5, B5) over a warm fifth that swells and fades, 1.9 s |
