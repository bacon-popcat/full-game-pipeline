# Recipes

Timings are in effect seconds. Layers are listed in draw-priority order.
"Mesh:" notes name the MeshFactory generator to use (see `meshes.md`).
The studied numbers behind these (palette, value, brightness, timing) are in `design.md`;
fire and smoke in `explosions.md`; projectiles, slashes, beams and auras in `motion.md`.

**Recreating a reference: Oscar's corrections so far** (they came from playtest
screenshots, not from the reference video). Apply them where Roqer's guidance says nothing;
where they conflict, follow `design.md` / `explosions.md` / `motion.md` (`SKILL.md`,
Precedence). The main conflict: a fire body is a boiling mass of flipbook particles
(`explosions.md`), not beam sheets carrying one image.
- Big flame sheets (walls, curtains, central columns) stay fixed in the world, lying
  along the effect's shape, not turned to the camera. Use beams with `FaceCamera = false`
  (orientation rule in `structure.md` "Engine gotchas"). Particles can only face the
  camera, so they can't be fixed this way; say so instead of trying.
- Fire walls must be dense with no see-through gaps, including at the sides. Leave no
  gaps between particles, back the particles with an opaque layer, and don't thin the
  edges (details in the lava fissure recipe).
- Flames should rush upward, not drift. Speed them up and cut their lifetime by the same
  factor so the height stays put (height ≈ Speed × Lifetime, a bit less with Drag).
- Fire walls sway side to side while they burn.
- Wind and swirl arcs should rise as they spin out, not sit flat on the ground, and stay
  subtle (start ~0.4 transparent).

## Impact skeleton (studied)
From Roqer's measurements of published effects (https://github.com/S4US/Roqer, `vfx-craft.md`,
AGPL-3.0-or-later). A floor, not a target: fill each role with your own texture and colour,
add or drop roles as the idea needs. R = the effect's radius in studs; times from the hit.
Each layer is usually its own single-sprite burst (`ctx.Emit(emitter, 1-6)`), timed with
`ctx.Wait`.

| Time | Role | Make |
| --- | --- | --- |
| -0.15 s | Anticipation | A glow that shrinks from 1.5R to 0 over 0.1-0.15 s, spinning fast (`RotSpeed` -700 to -500) |
| 0 | Flash | A soft ball or four-point flare growing 0 to 2.5R, Lifetime 0.06-0.1, Brightness 10, `ZOffset` in front |
| +0.03 s | Impact stars | A 4x4 sheet that bursts open (`drawing-textures.md`), Lifetime 0.075-0.15, 2-6 particles, as the three-value stack: colour (`ZOffset` z, `LightEmission` -1, Brightness 5), its black twin (same size, life and count, z to z + 0.25) and a small white copy (z + 1, Brightness ~60) |
| +0.03 s | Black backing | A soft black blob behind (`ZOffset` -1), 2-4R, Transparency 0.35 → 1 |
| +0.05 s | Streaks | `VelocityParallel` with `Squash` 3 → 1, Speed 60-200, Drag 8-12, size with an envelope, a few black twins |
| +0.05 s | Ring | A flat `VelocityPerpendicular` ring (Speed ~0.01, `EmissionDirection` Top, attachment level with the ground) growing to 2-3R over 0.2-0.4 s, Transparency 0 → 1.3 |
| +0.03 s | Fire body | For fire: 2-4 fire-burst flipbook layers, never one image scaling (`explosions.md`) |
| +0.05 s | Smoke | The same burst living 1.5-3 times as long: self-lit mid-grey sheets (or tinted by the fire), half transparent at their most solid, slowed, gone by about 1.5 s for a hit |
| +0.05 s | Embers | Dots at `LightEmission` 1, Speed 10-120, Drag 10, Lifetime 0.75-2 |
| 0 | Light | A PointLight at Brightness 7-16, Range 7-15, fading over 0.5 s |

**Wind and smoke** around an impact:
- **Wind:** 3-6 nearly transparent grey arcs and rings: crescent and radial-streak textures,
  flat (`VelocityPerpendicular`), growing to 25-35 studs by 60% of life, Transparency from
  0.45-0.85 to above 1, `LightEmission` 1, `RotSpeed` ±15-20, `ZOffset` 0.5, over the smoke.
- **Smoke:** self-lit puffs in warm and grey pairs.
- **A ground skirt:** a flat copy of the smoke, squashed.
- **Black grit:** a few dark dust particles.

## Impact (melee hit, punch, slash contact)
Duration 0.3-0.6. See `examples/SlashImpact.luau`: the skeleton above for one hit of many
(R = 4 studs): spiky flash + flare line, colour/black/white impact stars, black backing, a
claw stroke with its dim twin (one shared angle), streaks with black twins, a flat shock
ring facing the attacker, embers, and a light that fades while its range grows.

## Slash (weapon swing arc)
Duration 0.2-0.4.
1. Arc: crescent mesh, Neon, oriented along the swing plane. Mesh: Crescent.
   Tween a slight scale-up (1 -> 1.15) and Transparency 0.1 -> 1. Fade fast.
2. Optional second, wider and fainter arc behind it, delayed ~0.03s.
3. Sparks shed along the arc: small burst, VelocityParallel streaks.
4. On contact: play an Impact effect at the hit point.

## Spin slash / wind vortex (AoE swing around the caster)
Duration ~0.3 for the vortex, ~1.5 with residue. See `src/shared/VFX/Effects/WindSpinSlash.luau`.
1. Vortex: 4-6 flat spinning particles (VelocityPerpendicular, tilted attachment,
   RotSpeed 800-1000), slash flipbooks played OneShot. Dark layers under solid lime ones
   (LightEmission 0, Brightness ~3.5) and one thin additive hot stroke. Phase each layer's start angle (every texture's arc sits at a
   different angle in its quad) so together they form one ~180 deg crescent (an open C,
   not a closed ring); verify with VFXScrub frames. Steep tilt (~20 deg) so one side
   rises: reads as volume.
2. Flash at ~0.01: a filled spiky shape over a squashed flare line above the caster, gone by
   ~0.08 (a thin four-ray star as the whole flash reads as a V once rotated).
3. Ground: wind-ring texture lying flat (0.35-0.6s), self-lit mottled smoke (a grey pair)
   as flat haze on a Disc emitter, slowed to 0.8x.
4. Thin bright crescents rising out of the vortex (0.06-0.27).
5. Residue: leaves (MeshParticles), sparkles and glow spots on a Disc emitter, debris.

## Suction / gravity pull / black hole (channelled, 1-3 s)
See `src/shared/VFX/Effects/MagnetPull.luau`. Driven by a per-frame loop for `Duration`
(add the value `ctx.Wait` returns to the loop clock, never a fixed 1/60).
1. Implosion pulses every ~0.17 s, each living ~0.13 s: a faint dome (camera-facing disc
   centred on the ground, so the ground hides its lower half; kept 0.7+ transparent so it
   doesn't read as tinted plastic, its rim carrying the shape) + a dark flat ground disc.
   They pop in ~1.25x as a faint first frame, snap to full size, then shrink to ~0.3.
2. The ring at the disc edge: a soft medium-width band (`thick ring 2`) while the pulse is
   big, cross-faded into a crisp neon ring (`thick ring 3`) as it closes. Both exactly at
   the dome's base radius; two copies of the band (1.04 R and 0.94 R) give the reference's
   ~25%-wide band. Size the fill disc so its edge hides under the band (~0.97 R), or the
   disc reads as two rings. A ring texture with a wide soft glow (`glowing ring 2`) at high
   Brightness reads as a halo, not a ring: choose ring textures by edge profile.
   If there is a core ring, make it a faint base slightly inside where each closing ring
   ends, not a second bright ring next to it. For more distinct rings: a darker fill
   (contrast) whose edge sits under the band (outside it shows a navy rim), the outer band
   copy at LightEmission ~0.85 and the overlapping inner copy at ~0.3 (two additive copies
   blow out to white), and a faint crisp ring at the peak that brightens as it closes.
3. Inward motion: specks and pale smoke wisps from an upper-hemisphere `Sphere` emitter
   (`ShapeInOut = Inward`, Lifetime ~ radius / Speed so they vanish before the centre),
   dark shards (MeshParticles with inward Acceleration), streaks skating across the floor.
4. Flicker layers on a Box volume: short-lived lightning clusters, black jagged streaks,
   thin vertical lines (FacingCameraWorldUp keeps them upright).
5. Optional core: an anticipation first (a spiky star and its black twin swell while
   spinning, then implode to nothing over ~0.4 s), a pop as the hole opens, then a held core
   built as the orb skeleton (`motion.md`): black linework, a hard ring, swirling rays, a
   black pupil, an outer ring, a halo and a black backdrop, every layer cross-fading (Rate
   ~3, Transparency 1-0-1, random Rotation) so it holds but shimmers, raised half its size
   so the ground cuts only its bottom. For a bold, fully dark pupil put a dark `Neon` Ball
   part inside (particles alone stay semi-transparent) and give the layers in front
   `ZOffset` > the ball's radius. Arcs flash with each pulse. Keep the palette to five
   colours (violet, magenta, pale lilac, dark violet, near black).

## Projectile (fireball, energy bolt)
Persistent while flying, plus an impact on hit. Studied heads, ribbons, paths and volleys:
`motion.md`, which wins where this list differs.
1. Head: one sprite (a `VelocityParallel` diamond aimed along the path, or a camera-facing
   core), cleared at impact.
2. Ribbons: 2-3 textured Trails (a sharp one ~0.6 s with a gap behind the head, a soft one
   ~0.85 s, a tendril ~0.3 s; shorter on a fast straight shot), `Lifetime` divided by
   `ctx.TimeScale`.
3. Shed particles: Rate 30-60, small, inherit some velocity (`VelocityInheritance` 0.2-0.4).
4. On hit: play an Impact effect at the hit point.

## Aura (buff, charge-up, status)
Looping until stopped. The cross-fade stack, size ladder and orb skeleton: `motion.md`.
1. Base glow: Highlight or ground disc, low alpha, slow pulse (tween loop 0.8-1.5s).
2. Rising particles: Rate 10-25, upward Acceleration, long Lifetime (1-2).
3. Accent: occasional bright sparks, Rate 3-8.
Keep total under budget; auras are on screen for a long time. Avoid mesh particles here.

## Explosion
Duration 0.8-1.5. Studied anatomy (flash, boiling fire body, burn-out, smoke) and the
layer numbers: `explosions.md`. A finisher should keep growing in mass for 0.25-1.35 s after
the flash while its brightness falls (`design.md` section 6).
1. Flash: very bright, very short (0.05-0.1s).
2. Fireball: large particles, quick growth then shrink, orange -> red -> dark.
3. Shockwave: expanding ground ring or flared wall. Mesh: Ring or Tube.
4. Debris: MeshParticles.Burst with rocks, gravity (Acceleration y -80 to -110),
   10-20 pieces. Mesh: Rock (2-3 seeds). Add texture-particle sparks too.
5. Smoke: dark, slow, large, LightEmission 0, 1-1.5s, rises slightly.
6. Light pop: larger range, longer fade.

### Fireball explosion (a skill's finisher)
See `src/shared/VFX/Effects/FireballExplosion.luau`, built to `explosions.md`. R = 7 studs.
1. 0 s: a filled spiky flash to 2.5 R, a white-hot core (Brightness ~40) and a cross flare,
   gone by ~0.09 s. A light pops (Brightness ~12) and fades over ~0.9 s while its range grows
   to ~36.
2. 0.03 s: impact stars (colour/black/white) and the fire body: two drawn fire-burst sheets,
   8 each, Speed 12-28 R/5, Drag 4, Lifetime 0.45-0.8, Brightness 5, LightEmission 0.2,
   cooling yellow-white → orange → red; a small hot copy at Brightness 18 dies by 0.3 s.
   A slower, bigger late wave at 0.1 s keeps the mass growing.
3. 0.035 s: comets: a hot head, a sharp textured trail (~0.22 s) and a soft one (~0.4 s),
   lifetimes divided by `ctx.TimeScale`, shedding sparks, on a parabola.
4. 0.06 s: black backing, smoke from the same burst (grey and a fire-tinted twin, Lifetime
   0.9-1.4 slowed to 0.75x, Transparency 0.3 at its most solid), streaks with black twins,
   a ground ring, embers.
5. 0.26 s: a charcoal burn-out behind the body; 0.3 s: a scorch and lava cracks that cool
   from orange to dark over ~2.4 s, with thin smoke wisps.

### Lava fissure eruption (curtain of fire from a crack)
See `src/shared/VFX/Effects/LavaEruption.luau`. ~3.65 s of flame, then the crack cools to
~4.35 s. Size the big shapes off the fissure length F (body B = 0.72 F).
1. Anticipation 0-0.6 s: streak bursts (orange + their black twins), grey rock chips (gone by
   ~0.4 s), upright flame bursts in the middle 0.6 F, lava rings and ring curls, a grey smoke
   veil (never a dense black puff) shooting up under heavy drag, embers. The crack heats up
   red-orange from 0.3 s.
2. Onset ~0.7 s: a spiky flash and a flare line along the crack, a spike row, a splash, and
   within ~0.035 s a dense curtain of solid tongues (Fire Tower flipbooks: hot roots, orange,
   deep red tops; LightEmission 0.3, Brightness 3) ~0.5 F wide, the centre band ~1.4x taller,
   over a boiling base of drawn fire bursts, with a soft yellow core glow low in the middle. Wind
   arcs from ~0.72 s: thin, peach, flat ellipses 1.3-1.6 F across (plus a raised, tilted
   layer), rising as they spin, gone by ~1.25 s.
3. Burn: the curtain is ~0.46 F wide and sways (two mixed sines,
   `0.75 sin(5.7t) + 0.25 sin(10.1t + 1.3)`, pushing every live tongue sideways), with dark
   charcoal tongues at its edges, curls, flecks, embers,
   and a hot orange line along the crack. The centre loops a ~0.49 s pulse: a bright blob, a
   darker flame burning up through it (an arch), then a tall teardrop and a small V.
4. Die-down ~2.85-3.65 s: the curtain narrows to a bundle ~0.2 F wide while it stays tall.
   Stop emitting early and shrink lifetimes so nothing lingers; the crack cools to dark.
5. Kept from Oscar's playtests: `Scale = 2.5` (fissure ~50 studs); tongues rush
   (`TONGUE_RUSH = 1.6`× faster, living 1/1.6 as long; the per-frame loop rewrites their
   `Lifetime`, so the factor is applied there too); `FlameRate = 100`; wide tongues
   (`Squash` 0.3→0.6) so the wall has no gaps; the opening wall rushes up 2.8x faster and is
   2.5x thicker for ~0.25 s; the heart pulse timing. The scrolling beam veils were replaced
   by flipbook fire (`explosions.md`): a fire body is a boiling mass of sheets. The central
   column and its glow stay fixed beams (`FaceCamera = false`): they are light, not body.

## Ground slam / earth ability
Duration 0.6-1.2 (the crater stays ~2.8 s). See `examples/GroundSlam.luau`.
1. The impact skeleton at the hit (flash, stars, backing, streaks), R = 6.
2. Shock ring mesh that flattens (height x0.2) while it widens and spins ~150 degrees
   (Cubic Out, 0.35 s), over a flat ground ring particle. Mesh: Ring.
3. Dust body that keeps swelling for ~1 s after the flash: warm and cool mottled dust (the
   drawn DustPuff sheet), self-lit, ~0.3 transparent at its peak, slowed to 0.75x; a flat
   squashed skirt; a short dust column so it isn't a flat splash; black grit.
4. Rock debris via MeshParticles, upward cone (Spread 45-60). Mesh: Rock.
5. Wind arcs: nearly transparent grey crescents, flat, growing to ~5 R by 60% of life.
6. Crater: 6-36 rocks round the hit, tilted outward, in the hit surface's material
   (`RaycastResult.Material`); they grow over 0.4 s (Back Out), hold, then sink over 1 s.
7. Optional spikes erupting: tween Spike meshes up from below ground, hold, sink. Mesh: Spike.

## Ice / crystal
Duration 0.5-1.
1. Shards: MeshParticles burst or static shards tweened up from the ground. Mesh: Shard.
2. Frost mist: pale soft particles, slow.
3. Glints: a few small sparkles, LightEmission 1.

## Movement (dash, double jump, landing)
Duration 0.3-0.5.
1. Afterimage or Trail along the path.
2. Ground puff: flat ring of dust at start/landing, LightEmission 0.
3. Speed lines: few long thin particles, `Orientation = VelocityParallel`.

## Buff / Heal
Duration 0.6-1.2.
1. Upward column or spiral of soft particles. Mesh (optional): Tube with a scrolling texture.
2. Ground ring expanding and fading. Mesh: Ring.
3. Gentle Highlight flash on the character (FillTransparency 0.6 -> 1).
