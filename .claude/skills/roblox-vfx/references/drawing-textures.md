# Drawing textures and flipbooks

What good VFX textures look like, and how to draw your own with numpy
(`tools/vfx/vfxtex.py`), check them (`tools/vfx/flipbook.mjs`) and get them into the game.
Read it when nothing in the library (`textures.md`) fits, and before generating a texture
with Gemini: the "what textures look like" rules apply to every texture, however it is made.

Adapted from Roqer's VFX skill (https://github.com/S4US/Roqer, `roblox-animation-vfx`
references `vfx-textures.md` and `vfx-rendered-flipbooks.md`, AGPL-3.0-or-later). Marks as in
`design.md`.

## What textures look like

- **They are custom.** In the first study 915 distinct textures appear, and only 8 emitters
  used a Roblox built-in *(measured)*.
- **White, with the shape in alpha.** The particle's `Color` tints them.
- **Two families, and the blend tells them apart** *(measured: the 1,215 textures behind
  4,950 studied emitters)*:
  - **Drawn matter:** slashes and claws, puffs, cel bursts, splashes, debris, flame tongues.
    Edges are crisp: alpha is binary with a 1-2 px anti-aliased rim, or posterised to about 16
    steps. Most of it sits at `LightEmission` 0, where 57% of emitters use a crisp or nearly
    crisp texture; 65% of flipbook emitters use a crisp or nearly crisp sheet.
  - **Light:** flares and glints, glows, halos, lens streaks, soft shock rings, ray bursts and
    dots. Brightness falls off smoothly from a hot core or line, and the shape keeps the
    symmetry of light (below). 83% of `LightEmission` 1 emitters use a texture that falls off
    softly.
- **Little of a texture is at full brightness** *(measured: 1,393 textures)*: a median 1% of
  the drawn pixels in soft light (a small hot core), 19% in crisp drawn matter and 29% in
  textures that mix the two. In 752 line textures a median 13% of a stroke is near full and
  40% faint: bright at an accent, fading along the rest. Spikes, a ring and a sigil drawn
  48-82% at full looked cheap *(seen in a Roqer run)*. `Brightness` makes a texture bright; the
  value inside it reads as craft.
- **Smoke is where the styles part.** Of a community kit's 113 smoke, fog and cloud textures,
  73 are soft-edged billows with light and dark mottling inside, 29 put a crisp silhouette
  around a soft, mottled inside, and 11 are flat cel puffs *(measured)*. In studied effects 72%
  of smoke layers use a soft or mottled texture, and even cel puffs play about half
  transparent. Cel puffs are the clean toon look; a brief that asks for weight or grit, or says
  "not cartoonish", wants the mottled kind. A ground slam asked to be "heavy and brutal" got
  two-tone cel dust that read as cotton balls. Soft is not the failure; no silhouette and no
  contrast inside is.
- **Detail from negative space, not shading.** Holes, notches, overhangs and scribbled
  interior strokes. Stroke width tapers as with pen pressure. Drawn silhouettes are
  asymmetric. Shading, when there is any, is one or two flat tones (a lit and a shadow side).
  - Holes belong where a shape breaks apart (a puff thinning out, a burst's last frames) or
    where the cut-out is the design (a ring, a crescent).
  - **A flash's centre is solid, glowing, or a deliberate ring.** A few small holes punched
    into a solid core read as beads, eyes or a face, not as detail.
- **Common shapes:** crescents and claws, lumpy puffs, wobbly rings, wisps, flame tongues,
  zig-zags, spiky stars, splinters, shaded rocks and dots.
- **Frames grow, then break apart.** A shape grows with an ease-out to a peak around frame
  4-6, then is eaten into 2-6 fragments. Across 463 one-shot sheets, 57% break apart, 15%
  shrink and fade, 6% erode in one piece; the drawing is largest a median 27% of the way
  through, and half end in blank cells. 4 x 4 is on 81% of flipbook emitters *(measured)*.
- **Every frame changes shape.** In 455 one-shot sheets the outline moves a median 44% from
  one 4 x 4 frame to the next; 5% hold, nearly all rings, cracks and glows that only fade
  *(measured)*. A sheet that grows and then keeps one drawing plays as a still image. Drift
  the warp fast, flicker strokes and open holes early; `flipbook.mjs` names a stretch that
  barely changes.
- **Impact stars burst open** *(measured: 18 sheets)*. Either shards fly out from a solid
  heart and their inner ends follow, so the centre empties into a ring, or a four-point flare
  turns. The drawing is largest about a fifth of the way in, and the last drawn cell comes a
  median 73% of the way through. The flash is another layer: one big filled shape for a frame
  or two. A round puff with even, straight spikes that holds its shape reads as a comic
  sticker.
- **Size within the cell varies:** many sheets fill most of the cell at their largest; a
  hand-drawn set keeps half under 27% of it and lets the particle's `Size` scale them.
- **Drawn matter is not symmetric, not even.** Uneven counts, lengths and spacing, strokes
  that taper. Draw tapered strokes, lumpy blobs and warped coordinates, not rays and rings
  around a centre. A perfectly radial star with even outlines, a snowflake-symmetric frost
  patch and a ring with gear-like notches read as clip art.
- **Light keeps the symmetry of light.**
  - **Four-point flares and glints** *(measured: 19, on 124 emitters)*: in 16 of the 19, four
    straight arms of the same length (within 4%), each thinning and fading toward its tip from
    one smooth hot core, often with a faint halo. None has bent arms or a lumpy core.
  - **The texture stays symmetric; the emitter stretches it.** 41% of those emitters squash
    the flare, and most rotate it. They live about 0.35 s, at `LightEmission` 1 and Brightness
    5-12 mostly.
  - **Glows and dots** are round. **Lens streaks** are a thin horizontal line through a hot
    centre. **Ray bursts** are straight rays of uneven length from one hot centre.
  - **Rings are round, not even** *(measured: 159 ring textures)*. 84% vary round the circle:
    a bright, thick arc that thins and fades round the rest, brush strokes with breaks, or
    radial streaks. Brightness spreads a median 32% round a ring and width 51%, and about 8% of
    it is at full brightness. Vary both smoothly with the angle, not in lumps. A band of one
    width at full brightness all round reads as clip art.
  - Made lopsided, lumpy or hard-cut, light reads as a broken drawing.
- **Symbols are precise.** Sigils, runes and magic circles have clean geometry and even line
  weight; their richness comes from density (ornament inside the circle; a rune band of many
  small glyphs in a thin ring, which reads as script). Make the effect around a sigil lopsided,
  not the sigil.

## Flipbook rules

- `FlipbookLayout` is `Grid2x2`, `Grid4x4` or `Grid8x8` (4, 16 or 64 frames); 4 x 4 is the
  usual choice. `Custom` is on 7% of studied emitters; check it plays before relying on it.
- Make a sheet 1024 x 1024, the size seen playing frame by frame (512 px a frame at 2 x 2, 256
  at 4 x 4, 128 at 8 x 8). Some library sheets are 512 (`textures.md`), so this is the rule for
  sheets we make, not a test of library ones.
- Don't judge a sheet by `FlipbookIncompatible`: Studio shows "must be 1024 by 1024" on every
  studied emitter, even a 1024 sheet that plays.
- Leave a few pixels empty inside each cell (`padding`): a frame that touches its cell edge
  bleeds into its neighbour.
- `FlipbookMode`: `OneShot` plays once across the particle's lifetime and is almost always the
  choice for a burst *(measured)*; `Loop` repeats at `FlipbookFramerate` (at most 30);
  `PingPong` plays forward and back; `Random` shows one random frame. `Loop` with
  `FlipbookStartRandom = true` for a burning fire (our gotcha: flame sheets with tiny first
  frames need it). For variety, draw 4 or 16 variants (rocks, debris, splashes) on one sheet
  and use `Loop`, `FlipbookStartRandom = true`, `FlipbookFramerate` 0, so each particle keeps
  a different one.
- Some low-memory devices switch flipbooks off, so the first frame should still read alone.
- To check a sheet in Studio, hold one particle at a few ages (VFXScrub) and screenshot it:
  each capture should show one frame, not the whole grid.

## Drawing with vfxtex

`tools/vfx/vfxtex.py` needs only numpy. Run it in Blender's Python through the Blender MCP
(`mcp__Blender__execute_blender_code`; system Python on Oscar's PC has no numpy):

```python
import sys, importlib
sys.path.insert(0, r"C:\Users\oscar\Documents\Rojo Roblox\VFX\tools\vfx")
import vfxtex; importlib.reload(vfxtex)
vfxtex.OUTPUT_DIR = r"C:\Users\oscar\Documents\Rojo Roblox\VFX\assets\textures"

def burst(t, size):
    x, y = vfxtex.tex_coords(size)
    ...
    return alpha              # or (alpha, value), or an RGB/RGBA array

vfxtex.draw_flipbook("ImpactBurst", burst, grid=4, fps=30)   # one-shot burst sheet
vfxtex.draw_texture("Glint", glint, size=512)                # single image
```

- `draw_flipbook(name, frame, grid=4, loop=False, fps=None, mode="alpha", padding=4)` calls
  `frame(t, size)` once per cell (`t` 0 at the first frame, 1 at the last) and writes
  `<name>.flipbook.png`, `<name>.flipbook.json` (what it meant to make) and
  `<name>.preview.png` (half size, over a dark ground, as a white texture reads when it
  glows). `frame` returns the alpha of a white shape; `(alpha, value)` where value is a grey
  level, so one shape carries a lit and a shadow tone under one `Color`; or an RGB/RGBA array
  when the colour must be baked in.
- `draw_texture(name, image, size=512, mode="alpha")` writes one `<name>.png` (+ preview).
- `mode="additive"` bakes onto black, only for a layer that will only ever be additive. Roblox
  has no multiply mode: for darkening, use a black layer at `LightEmission` 0, or negative
  `LightEmission`.
- **Size:** square. 93% of studied flipbooks and 42% of single images are 1024 px; a crisp
  edge drawn small blurs when the particle fills the screen. Draw a large or crisp texture at
  1024; a soft glow or a dot can be 256-512.

| Helper | Gives |
| --- | --- |
| `tex_coords(size)` | `x, y` arrays from -1 to 1, x right and y up |
| `tex_polar(x, y)` | `r, angle`: distance from the centre and the angle |
| `tex_noise(size, scale, octaves, seed)` | Smooth noise in 0..1 that tiles |
| `tex_cells(size, cells, seed)` | Voronoi `near, edge`: detail inside a shape. Even cells drawn as the whole shape read as floor tiles or a turtle shell |
| `tex_sample(image, u, v)` | `image` looked up at 0..1 with wrapping, to scroll or warp noise per frame |
| `tex_curve(points, samples, closed)` | A smooth path through control points |
| `tex_stroke(x, y, path, width, start, end)` | A brush stroke along a path, width tapering from head to tail, drawn on or erased by `start` and `end` |
| `tex_blob(x, y, radius, lumps, roughness, seed)` | A lumpy, lopsided blob in one solid piece, for a puff or a body |
| `tex_warp(x, y, amount, scale, seed, t)` | Coordinates pushed around by noise, so whatever is drawn with them is organic |
| `tex_edge(value, at, soft)` | The hard edge of drawn matter: 0 below `at`, 1 above it, blended over `soft` |
| `tex_ease(t, power)` | Ease out, for a burst that grows fast then slows |

`tex_stroke`, `tex_blob` and the shapes are fields: positive inside, negative outside. Combine
them with `numpy.maximum` (union) and `numpy.minimum` (intersection), and subtract one with
`numpy.minimum(a, -b)`. The helpers are shortcuts, not the whole vocabulary: a texture is any
numpy array.

**The pattern behind drawn matter:**
1. **Draw the shape the way an artist would:** tapering strokes (`tex_stroke` along a
   `tex_curve`) for claws, crescents, wisps, cracks and splinters; lumpy blobs (`tex_blob`)
   for puffs; a disc minus an offset disc for a crescent.
2. **Make it lopsided.** Draw with `tex_warp` coordinates and uneven random counts, lengths
   and widths.
3. **Cut it** with `tex_edge` (soft about 0.006-0.01) for a crisp silhouette.
4. **Animate it:** grow it with `tex_ease(t)`, or draw a stroke on by raising `end`; break it
   apart with a rising threshold on noise (`tex_edge(noise - t * 1.1)`), or erase a stroke from
   its head by raising `start`.

**Light** is a falloff, not a cut shape: smooth functions of the distance to a centre or a line
(`numpy.exp`), keeping its symmetry, leaving variety to the emitter's `Rotation`, `Squash`,
`Size` and `Brightness`. A round glow is `numpy.exp(-(r / radius) ** 2)`; a lens streak is a
glint's horizontal arm alone. A shock ring that varies round the circle: with
`r, a = vfxtex.tex_polar(x, y)` and `w = 0.5 + 0.5 * numpy.cos(a)`,
`numpy.exp(-((r - 0.75) / (0.015 + 0.05 * w)) ** 2) * (0.3 + 0.7 * w)`.

**Worked examples** are in `tools/vfx/examples.py`: `ClawSlash`, `SmokePuff` (cel),
`HeavyDust` (mottled), `Splinters`, `GroundCracks`, `ImpactStar`, `Glint`, `CrispStar`,
`FireBurst` and `BurnOut` (`explosions.md`). Copy one and change its shapes, counts and curves;
they show the pattern, not a house style. `flipbook.mjs` notes that `SmokePuff` and
`HeavyDust` barely change shape after they grow: push their holes and drift further for a burst.
All ten run in about 15 s.

## Check, then upload

1. **Check every sheet:** `node tools/vfx/flipbook.mjs assets/textures/<name>.flipbook.png`.
   It reads the sheet's note and reports the grid, coverage per cell in play order (it should
   grow and shrink as the effect does), problems (empty cells, drawing cut off at a cell
   edge) and notes (repeated frames, a stretch that barely changes shape), plus the
   `FlipbookLayout`, `FlipbookMode`, `LightEmission` and `Lifetime` (one-shot) or
   `FlipbookFramerate` (loop) to use. Fix every problem before uploading and weigh every note.
2. **Look at it:** read `<name>.preview.png` and ask:
   - **Symmetry:** is anything radially or mirror symmetric, evenly spaced, or of uniform
     line width? Break it up, unless it is a symbol's geometry or light's shape.
   - **Value:** how much is at full brightness? Light is a small hot core; a stroke is bright
     at an accent and faint along the rest.
   - **Light:** is a flare one smooth hot core with straight arms of equal length that fade
     toward their tips, and a glow round?
   - **Holes:** is there a small hole or dot inside a shape that should be solid, such as a
     flash's centre? Fill it.
   - **Silhouette:** does it read at a glance, with a thick-to-thin taper, lobes, notches and
     holes? Or is it an outline, an icon or a gear?
   - **Edges:** is drawn matter crisp? Soft is for light, and for mottled smoke on purpose.
   - **Change:** does the shape change in every frame, or only scale, fade or hold?
   - **Distance:** would it survive at game distance, or is it too thin?
   - **Ground marks:** does it spread from the point of impact, or is it an even pattern of
     cells that reads as tiles?
3. **Upload only the settled set**, the way `textures.md` "Making new textures" describes
   (serve the folder over HTTP, `upload_image`, verify by reading pixels back). Every upload is
   moderated and permanent, so say how many uploads a request will use first. Reuse one
   texture across layers by changing `Color`, `Size`, `Rotation` and `Squash`.
4. **Use it:** put the id in the effect's `ASSETS` with a comment naming the drawing
   (`-- drawn: assets/textures/<name>.py, Grid4x4`), apply the settings `flipbook.mjs`
   listed, add a row to `textures.md`, and confirm it plays (one frame per capture).

Keep each drawing's script in `assets/textures/<name>.py` beside its PNGs, so a texture can be
redrawn instead of repainted.

## Rendered flipbooks

When a 3D look is the point (a simulation, a lit volume, shaded debris, a realistic
fireball), render the scene's animation instead of drawing, with
`vfxtex.render_flipbook(name, grid=4, mode="alpha", start=None, end=None, loop=False, padding=4)`
in Blender (through the Blender MCP, in a separate scene so the user's scene is untouched).
It samples the frames evenly to fill every cell (Roblox plays every cell; with fewer frames
than cells some are held, which `flipbook.mjs` reports), renders each at the cell size minus
padding with the Standard view transform, and writes the same files as `draw_flipbook`, so it
is checked and uploaded the same way. Not yet run in this project.
- Frame an orthographic camera so the subject stays inside the view on every frame, at the
  size you want in the cell.
- `mode="alpha"` renders on a transparent film; `"additive"` on black for `LightEmission` 1.
- Eevee for emission (about 0.06 s a frame) or Workbench for flat shapes; Cycles took 0.28 s a
  frame at 32 samples for a simple sphere, and volumes far longer. The note records each
  frame's render time.

```python
import bpy, math
scene = bpy.data.scenes.new("FlipbookRender")
bpy.context.window.scene = scene
try:
    scene.render.engine = "BLENDER_EEVEE"        # Blender 5 (and before 4.2)
except TypeError:
    scene.render.engine = "BLENDER_EEVEE_NEXT"   # Blender 4.2-4.x
scene.frame_start, scene.frame_end = 1, 16
camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
scene.collection.objects.link(camera)
camera.data.type = "ORTHO"
camera.data.ortho_scale = 4.0
camera.location = (0, -10, 0)
camera.rotation_euler = (math.radians(90), 0, 0)
scene.camera = camera
# ... a glowing ball (emission material) whose scale and strength are keyframed:
#     grows fast by frame 6, then fades out while it keeps spreading ...
vfxtex.render_flipbook("GlowBurst", grid=4, mode="additive")
```
