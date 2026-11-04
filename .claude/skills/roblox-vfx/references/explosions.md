# Explosions, fire and smoke

Read with `design.md` for any explosion, fireball, blast, burning or smoke. It fills in the
explosion and impact entries in `recipes.md`, and wins where they or Oscar's corrections
disagree (`SKILL.md`, Precedence); `FireballExplosion` and `LavaEruption` are built examples
made before it.

Adapted from Roqer's VFX skill (https://github.com/S4US/Roqer, `roblox-animation-vfx`
reference `vfx-explosions.md`, AGPL-3.0-or-later). *(measured)* marks numbers from 5,010
studied emitters, 1,427 textures and 6 explosion videos stepped frame by frame; none was
checked in Studio. The Luau below is `Layers` spec tables as `FireballExplosion` uses
them (`att` an Attachment, `p` the Params, `R` the blast's radius).

## 1. The mass is a flipbook

297 studied fiery layers are big enough to be a body (camera-facing, 4 studs or more, living
0.25 s or more) *(measured)*:
- 152 play a flipbook.
- Of the 145 that use one image, 138 use a soft light texture: a glow, flare, lens streak or
  ring.

**One image is for light.** Fire, smoke and bursts are sheets whose frames grow, boil and
break apart. A static puff that only scales reads as a growing sticker. The built-in
`fire_main.dds`, `smoke_main.dds` and `explosion01_core_main.dds` are single images: stand-ins
for blocking out only. Library flipbooks (`textures.md`) or drawn sheets
(`drawing-textures.md`, `FireBurst` and `BurnOut` in `tools/vfx/examples.py`) carry the body.

## 2. Anatomy and timing

From the flash, in three studied explosions *(measured)*:

| Beat | Stylized (two artists) | Realistic |
| --- | --- | --- |
| Flash | 1-2 frames: a big soft glow, a yellow-white core, a thin cross flare | a white-out that lights the floor |
| Fire body | 0.05-0.33 s: boiling flame shapes, yellow-white core, orange, red rim | to about 0.5 s, in burning patches by 0.3 s |
| Burn-out | 0.3-0.5 s: the core turns charcoal while red rims and cracks glow | 0.4-0.8 s: dark smoke eats the fire |
| Smoke peak | 0.33-0.6 s, half the fire body's area or less | 0.8 s, spreading low |
| Gone | 0.6-1.2 s, embers a little later | smoke lingers 2-3 s |

Brightness only falls. The body cools from yellow-white to orange to red, then dark, and
nothing re-ignites.

## 3. The fire body

The 152 fire-body flipbooks *(measured)*:

| Property | Measured |
| --- | --- |
| Sheet | 4x4 on 84; 8x8 (rendered, realistic) on 46; `OneShot` 97% |
| Count | 1-7 layers per explosion (median 3), each a burst of 3-28 or a short `Rate` burst |
| Lifetime | 0.45-1 s in a hit; 1-7 s in a nuke or slam |
| Motion | Speed median 88 (up to 190-460), Drag about 3: they burst out, then hang |
| Size | 45% keep one `Size` and let the frames grow; the rest ease out |
| Variety | random `Rotation` on 73%, a Size spread on 60% |
| Light | `Brightness` median 5 (2.7-15), `LightEmission` median 0.2 (0-0.5); one hot layer may run 15-25 |
| Colour at the end | deeper in its hue 73%, grey 24%, black 3% |
| Frames | largest a median 27% of the way through; 55 of 79 sheets end blank |

A studied fireball boils by overlap: three drawn 4x4 flame sheets stream at `Rate` 55-90,
Speed 225-380, Drag 3-4, each particle easing out at a random angle for 0.35-0.75 s.

A fire-body layer for a hit with a radius of about 5 studs, 0.03 s after the flash:

```luau
-- R = the blast's radius (studs); FireballExplosion's fireLayer
local fireBody = Layers.Emitter(att, {
	Texture = Textures.FireBurstA, -- drawn 4x4 fire-burst sheet (Layers sets Grid4x4, OneShot)
	Lifetime = { 0.45, 0.8 },
	Speed = { 12 * R / 5, 28 * R / 5 },
	SpreadAngle = 180,
	Drag = 4,
	Rotation = { 0, 360 },
	RotSpeed = { -40, 40 },
	LightEmission = 0.2,
	Brightness = 5,
	ZOffset = 1,
	Color = { { 0, p.HotColor }, { 0.25, p.Color:Lerp(p.HotColor, 0.35) }, { 0.6, p.Color:Lerp(p.DeepColor, 0.5) }, { 1, p.DeepColor } },
	Size = { { 0, 0.6 * R, 0.15 * R }, { 0.3, 1.6 * R, 0.35 * R }, { 1, 1.8 * R, 0.35 * R } },
})
-- ... 0.03 s after the flash:
ctx.Emit(fireBody, p.FireCount) -- Defaults: FireCount = 8
```

Add a second layer from another sheet or seed, and a smaller hot copy at Brightness 15-25
that dies by 0.3 s. Keep Transparency at 0: the sheet breaks itself apart, and a fade on top
only blurs it.

## 4. From fire to smoke

**Smoke fires in the same burst** as the fire, within 0.05 s, and outlives it by up to 1 s in
a hit, 2-11 s in a slam *(measured)*. Three ways:
- smoke layers living 1.5-3 times as long, often slowed (emitter `TimeScale` 0.55-0.9; see
  `design.md` section 6 for doing that with `ctx.Emit`);
- a fire layer whose Colour ends grey: `#ff7f29` → `#ff5506` → `#313131` while Transparency
  rises 0 → 0.56 → 0.87;
- a rendered 8x8 sheet with the change baked in: fire for 24 frames, cooling for 8, dark
  smoke for 16, then wisps.

**The burn-out** is the charcoal core the fire leaves, with glowing cracks. In the videos it
is the darkest moment, lasting 0.1-0.3 s before it thins and lightens. Put a burn-out sheet
(section 6) just behind the fire body, so the fire covers it until it breaks up:

```luau
local burnOut = Layers.Emitter(att, {
	Texture = Textures.BurnOut, -- drawn 4x4 burn-out sheet
	Lifetime = { 0.5, 0.7 },
	Speed = { 1 * R / 5, 3 * R / 5 },
	SpreadAngle = 180,
	Drag = 4,
	Rotation = { 0, 360 },
	LightEmission = 0,
	Brightness = 2.5,
	ZOffset = 0.5, -- just behind the fire body
	Color = { { 0, p.Color:Lerp(p.DeepColor, 0.3) }, { 1, p.DeepColor } },
	Size = { { 0, 1.4 * R }, { 1, 1.8 * R } },
	Transparency = { { 0, 0.1 }, { 0.6, 0.3 }, { 1, 1 } },
})
-- about 0.25 s after the fire body: ctx.Emit(burnOut, 2)
```

## 5. Smoke

320 studied smoke layers *(measured)*:

| Property | Measured |
| --- | --- |
| Lighting | `LightInfluence` 0 on 68%; 0.5 or more on 20%, mostly one piece |
| Sheet | a flipbook on 71%, mostly 4x4 `OneShot` |
| Value | about texture x Colour x Brightness; self-lit solid smoke has a median of 0.71 (0.34-1.2), mid to light grey |
| Opacity | at its most solid, a median Transparency of 0.59 (0.26-0.79); 20% go below 0.2; 23% fade in |
| Hue | grey 63%; tinted 30%, warm beside fire or in the effect's hue |
| Texture | soft or mottled 72%; cel puffs peak at Transparency 0.53 |
| Lifetime | median 1.0 s (0.56-1.39); 3-7 s only for a slam's last cloud |

Make smoke self-lit (`LightInfluence` 0), as most studied smoke is: scene-lit smoke goes dark
in shade.

**A dark Colour is not dark smoke.** At `LightInfluence` 0, Brightness multiplies Colour:
studied smoke of `#3f3f3f` at Brightness 16 and 5 renders white and light grey, and a fire
ending at `#2b190c` with Brightness 15-65 is a glowing brown. Copied at Brightness 1, both are
black. Brightness with `LightInfluence` above 0 is unchecked.

**Dark smoke is a veil.** 40 of the 320 layers are dark, with a median peak Transparency of
0.5, many at 0.8-0.92, usually paired with light smoke (one fire dragon runs 18 black layers
beside 15 white ones). Dense black that lingers is a ground crack, a sigil or linework. In the
videos, smoke darkens what is behind it by 0.05-0.2 in luminance.

**Over a bright sky, half-transparent smoke turns into sky.** The measured opacity comes from
darker scenes than a new place's daylight. A fireball's grey smoke took the sky's hue within
3 degrees, a pale blue cloud *(seen in a Roqer run)*. In daylight make it more solid at its
peak (Transparency 0.2-0.35) so it shows its own grey, warm where the fire lights it
*(starting point)*.

Cel puffs suit a clearly toon game, half transparent. Opaque two-tone puffs read as cotton
balls; otherwise use soft or mottled smoke.

Self-lit smoke that bursts out with the fire, fades in, hangs and fades:

```luau
local smoke = Layers.Emitter(att, {
	Texture = Textures.DustPuff, -- drawn 4x4 mottled smoke
	Lifetime = { 0.9, 1.4 },
	Speed = { 8 * R / 5, 16 * R / 5 },
	SpreadAngle = 180,
	Drag = 6,
	Acceleration = Vector3.new(0, 2 * s, 0),
	Rotation = { 0, 360 },
	RotSpeed = { -20, 20 },
	LightEmission = 0,
	Brightness = 1.6,
	Color = p.SmokeColor, -- a twin with { { 0, grey }, { 0.25, p.Color }, { 1, grey } } beside fire
	Size = { { 0, 0.8 * R, 0.2 * R }, { 1, 2.1 * R, 0.4 * R } },
	Transparency = { { 0, 0.75 }, { 0.15, 0.3 }, { 1, 1.15 } }, -- above 1: gone before the lifetime ends
})
-- with the fire body (+0.05 s), slowed while it hangs:
Layers.Emit(ctx, smoke, 6, 0.75)
```

- **Beside fire,** add a twin whose Colour runs from the fire's orange to grey.
- **Away from fire,** pair a warm grey with a cool one.

## 6. Drawing the sheets

Draw fire bursts and burn-outs with `tools/vfx/vfxtex.py` (`drawing-textures.md`);
`FireBurst` and `BurnOut` in `tools/vfx/examples.py` are worked examples:
- **Fire burst:** a white-hot puff grows by a third of the way and breaks up. Its value
  falls: under the fire body's Colour it runs white, yellow, orange, then chars inside while
  its edges glow red in places. At Brightness 5 only a value under about 0.1 reads dark; one
  flat value stays one flat orange, a paper cut-out.
- **Burn-out:** mottled charcoal that swells, churns and lifts while its few cracks cool and
  it thins and tears.

Neither holds a shape: their outlines move a median 30% and 20% a frame, studied sheets about
40% (`flipbook.mjs` reports it). Draw two or three bursts with other seeds so overlapping
layers differ.

**Realistic explosions** use 8x8 sheets rendered from a fire and smoke simulation, with the
colour baked in. We can't render one with these tools yet; for a realistic brief, say so and
look for an explosion flipbook in the art library (`textures.md`).

## 7. Checks

Add these to the capture review in `review.md`:
- At 0.1-0.3 s, is the body a boiling mass of overlapping sheets, or one image scaling up?
- Does it cool from yellow-white to a charred centre with red edges and break up by about
  0.5 s in a hit, or end as one flat orange?
- Is the darkest moment the burn-out, gone within about 0.3 s?
- Is any smoke darker than what is behind it by more than about 0.2 for longer than that, or
  dark and below Transparency 0.5?
- Is any dark Colour at Brightness 1 where the studied ones used 5-60?
- Is a hit's smoke gone by about 1.5 s?
