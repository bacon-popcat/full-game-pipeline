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
