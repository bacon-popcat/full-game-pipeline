# Lighting

The look follows a day and night cycle. By day it is soft and filmic: gentle contrast, muted
earthy colour and a creamy golden mist over the distance, with shadows that lengthen into
the afternoon, golden sunrise and sunset, and a moonlit night under stars. Every time of day
stays easy to read. Night is lit with a bright blue ambient, a moon-tinted sun colour and
raised exposure, so crops, machines and paths are always clear. Players pick how much of the
look to pay for: Low, Medium or High.

## Who owns what

| Piece | Owner |
|---|---|
| Every Lighting property the look sets, the Sky's sun and stars, Atmosphere, `GardenGrade` and `DayTint` (ColorCorrections), Bloom, SunRays, DepthOfField, the time-of-day keyframes and the quality presets | `client/libraries/Lighting` (its `KEYS`, `GRADE` and `PRESETS` tables hold the numbers) |
| The time of day | `shared/DayCycle`: a clock derived from server time, so every player sees the same sky with no remote. One day lasts `LENGTH` (20 minutes), three quarters of it between `DAWN` and `DUSK` |
| Moving the clock each frame | `client/controllers/LightingController` (`Lighting.setClock`) |
| Tint requests on top of the grade (weather, lightning) | Features through `Lighting.set` / `Lighting.clear` (conventions.md § Global properties) |
| The popup blur | `client/libraries/Backdrop` (`PopupBlur`) |
| Applying the saved quality | `client/controllers/LightingController`, from the `LightingQuality` Player attribute |
| Saving the quality | `server/services/SettingsService`, in its own ProfileStore `GardenSettings_v1` keyed `Player_<userId>`, apart from the save files, so it holds in every garden and in the save menu |
| Allowed values and the default (High) | `shared/Settings` |
| The Settings controls | `UIController/Settings` binds `HUD.Settings.Body.LightingQuality` |

Lighting is client-side. The server never touches Lighting; MapService used to add an
Atmosphere and no longer does. The library adopts the place file's own Sky, Atmosphere,
Bloom, SunRays and DepthOfField when they exist (retuning them, never stacking a second
copy) and creates whichever is missing. It also removes extra copies of any class it owns.

## Day and night

`Lighting.setClock(hour)` sets ClockTime and blends between keyframes: night (0 and 24),
pre-dawn 5.2, sunrise 6.5, morning 9, noon 13 (dimmer and darker-exposed so the high sun
doesn't wash the pale grass out), golden afternoon 16.3, sunset 17.6 and dusk 18.6. Each key
sets Brightness, Ambient, OutdoorAmbient, ColorShift_Top, ExposureCompensation, the `DayTint`
colour and the Atmosphere's colour and decay. The sun sets at about 18:00, so the sunset key
sits before it. `DayTint` is its own ColorCorrection, so weather requests, which tween
`GardenGrade`, never fight the clock. For checking one time of day in Studio, set a number
`FixedClock` attribute on Lighting on the client; the controller holds the clock there.

## Quality presets

| | Low | Medium | High |
|---|---|---|---|
| Shadows | off | on, softness 0.25 | on, softness 0.12 |
| Environment diffuse / specular | 0.6 / 0 | 1 / 0.7 | 1 / 1 |
| Atmosphere glare / haze | 0 / 1.2 | 0.25 / 1.4 | 0.3 / 1.6 |
| Bloom (threshold 1.8, so only light well past white glows) | off | on | on |
| SunRays | off | off | on |
| DepthOfField (far only, past the plot) | off | off | on |

The colour grade and the rest of the look apply at every level. A press in Settings applies
the preset at once and sends `Remotes.Settings("LightingQuality", quality)`. The server
checks the value, saves it and mirrors it as the Player attribute, and the client
re-applies that echo, which is the same preset. A change made before the profile loads
is kept and written once it does.

## Only in the place file

- There is no lighting technology to pick: the place has been migrated to Roblox's unified
  lighting (the `RBX_LightingTechnologyUnifiedMigration` attribute on Lighting), which hides
  the old `Technology` property and renders Future-style lighting, scaled to each device.
  Its two settings are authored in Studio's Properties panel, because only plugins may set
  them: `LightingStyle` must stay **Realistic** and `PrioritizeLightingQuality` on. The
  quality presets can't change either, so they work through shadows and effects instead.
- The Sky's skybox textures (`Lighting.Sky`). The library sets only its sun, moon and stars.
- `StarterGui.HUD.Settings`: `Body.GraphicsHeading`, `Body.LightingQuality` (a `Label`
  and `Low`, `Medium` and `High` TextButtons, each with a `Selected` bar shown on the
  current one), `Body.LightingNote` and `Body.GraphicsDivider`. The window's
  UISizeConstraint is 530x470 and its size is 0.94 x 0.8 scale.

## Checking a change

Playtest in Studio. Take screenshots from the same spot at each quality and at night,
sunrise, noon, sunset and dusk (`FixedClock`), make sure each one is easy to read, check
that a quality switch applies live, and rejoin to check that a non-default quality (Medium) comes back.
Data stores need API access for that, or the mock forgets the setting with the server.
