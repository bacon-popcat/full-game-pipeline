# Textures

Most effects should draw their own textures (`drawing-textures.md`): what a good texture
looks like (drawn matter vs light, value, frames that break apart) and how to draw, check and
upload one. Use the textures below when one already matches the effect's style, and keep a
table like this for your own project (name | id | use).

The `rbxasset://` rows ship with Roblox and always load. The `rbxassetid://` rows are ids the
skill's original author used (library cards and their own uploads). Most images can be used in
any experience, but an asset can be private to its creator: if one shows up blank, find a
similar texture in the Creator Store (Toolbox, "Images" / "Decals") or draw your own, and
replace the id. List every id in the effect's `ASSETS` with a comment saying what it is.

| Name | Id | Use |
|---|---|---|
| sparkles | rbxasset://textures/particles/sparkles_main.dds | Built-in four-point star: sparks, glints |
| smoke | rbxasset://textures/particles/smoke_main.dds | Built-in grey cloudy puff (single image: blocking out only) |
| fire | rbxasset://textures/particles/fire_main.dds | Built-in wispy flames (single image: blocking out only) |
| implosion glow | rbxasset://textures/particles/explosion01_implosion_main.dds | Built-in soft white round glow |
| shockwave | rbxasset://textures/particles/explosion01_shockwave_main.dds | Built-in soft ring |
| core puff | rbxasset://textures/particles/explosion01_core_main.dds | Built-in orange fiery puff (single image: never an explosion's body) |
| forcefield vortex | rbxasset://textures/particles/forcefield_vortex_main.dds | Built-in thin ring with dots |
| Medium Glowing Dark Slash | rbxassetid://107491452097107 | 4x4 flipbook, multi-strand slash sweep; additive (LightEmission 1) |
| Wide Dark Slash | rbxassetid://104673447334638 | 4x4 flipbook, dark wide crescent; normal blend under additive slashes |
| Glowing Slash | rbxassetid://13580352351 | 4x4 flipbook, crisp bright crescent (hot highlight) |
| Crescent32 | rbxassetid://17388445727 | Static layered crescent strokes (flat vortex layers) |
| Crescent18 | rbxassetid://17388365742 | Static thin clean crescent (trailing lines) |
| Smokey Shockwave | rbxassetid://12318427672 | Grey wind ring lying on the ground |
| Swirls21 | rbxassetid://130391463304711 | Thin swirl lines (ground wind detail) |
| Star102 | rbxassetid://17391818367 | Long 4-point glare for flashes |
| Blurred Spec 11 | rbxassetid://284205403 | Round soft glow |
| Star153 | rbxassetid://16444981264 | Small 4-point sparkle |
| smoke 41 | rbxassetid://111394301752764 | Soft smoke puff |
| Leaf (mesh) | rbxassetid://5129539702 | MigratedMeshes leaf, native 5.45 x 1.61 x 11.0 (SpecialMesh) |
| Thin Basic Slash | rbxassetid://85263893313331 | 4x4 flipbook, thin clean arc; tinted near-black for ink strokes in a slash |
| Shaded Slash 5 | rbxassetid://118897571793559 | 4x4 flipbook, streaky arc with dark fibres |
| grass1Other | rbxassetid://91858314987113 | Three curved grass blades; as a Beam texture = wind strands on a sword |
| Sideways Spec 41 | rbxassetid://10614304526 | Thin needle; long flash rays, streak particles, blade glow |
| Sideways Spec 50 | rbxassetid://6893847210 | Tapered spike; tinted black = tiny ink streaks shed off a slash |
| BeamSoftBlurredStreaks | rbxassetid://13280046773 | Soft streaky Trail texture for weapon motion trails |
| glowing ring | rbxassetid://13580366694 | Filled disc with a bright soft rim; camera-facing = translucent dome/shell, flat = ground disc |
| Sphere_Mask_02 | rbxassetid://135297534254471 | Faint sphere shell with a lit rim; layer over a dome for its edge |
| Ring_Thick_001 | rbxassetid://70800352387937 | Very thick soft ring (hole ~50%); reads as a pancake, prefer thick ring 2 for a ring band |
| Wispy Sphere 4x4 | rbxassetid://115949955697406 | 4x4 flipbook, white wisps inside a sphere; keep very transparent |
| Lightning Scribble 4x4 | rbxassetid://137202180073755 | 4x4 flipbook, scribbly lightning strands; FacingCameraWorldUp + Squash ~0.7 = tall bolt clusters; LightEmission 0.5 keeps a saturated tint on bright ground |
| glowing ring 2 | rbxassetid://12946041355 | Thin ring with a wide soft glow; at high Brightness it reads as a halo, not a ring (prefer thick ring 3 for neon rings) |
| Purple Lightning | rbxassetid://13013256540 | 4x4 flipbook (128 cells on a 512 sheet, NOT 8x8), soft lilac bolt column; reads as white smoke if Brightness > 1 |
| Glowing Black Energy | rbxassetid://17511030724 | 4x4 flipbook, ragged black energy; tinted near-black = bold jagged dark streaks |
| thick ring 2 | rbxassetid://15058135927 | Soft medium-width ring band; magenta pulse ring on the ground |
| thick ring 3 | rbxassetid://15268062056 | Crisp inner edge with a soft outer glow; neon ring (LightEmission 1, Brightness ~1.3) |
| Whole swirl | rbxassetid://17612139917 | 4x4 flipbook, wispy strands circling a point; looped around a core |
| Blackhole Ripple | rbxassetid://13826100764 | 4x4 flipbook (Loop), black core with a swirling rim; camera-facing, raised half its size off the ground = a dark ball |
| Blackhole spec | rbxassetid://73527526679754 | 4x4 flipbook, bright arcs hugging a core |
| Blurry Black Hole | rbxassetid://107972524433656 | Soft dark disc; halo/shadow behind a core |
| Spec31 | rbxassetid://16879822194 | Small solid speck; debris chips, suction specks |
| EnergyBeamV | rbxassetid://106782541570725 | Custom (Blender-made): bright core with wispy strands, tiles along length; Beam texture |
| Starburst | rbxassetid://136210055019402 | Custom: ~22 irregular spikes on a jagged filled core, white; explosion flash (tint the big copy, white smaller copy on top), flat on the floor = floor rays |
| FireSpotsRed | rbxassetid://92499735743228 | Custom: big soft red-brown blotches (~38% cover), equirect 2:1 for SmoothSphere UVs; colour baked (MeshPart textures ignore Part.Color) |
| FireLava | rbxassetid://131956550786641 | Custom: large glowing orange lava patches (~32% cover, bright cores), equirect 2:1 for SmoothSphere |
| FireMelt 1-7 | rbxassetid://97192842313897, 107466624382592, 71343323375230, 123175405602181, 131955014206452, 89698118968969, 70595154030083 | Custom: dark maroon sphere shell with growing holes (dark charred edges) eating it from the bottom (v=1) up; swap TextureID through the frames to dissolve a ball (hold the shell upright, fade the body inside fast) |
| LavaCracks | rbxassetid://89120608419510 | Custom: ~13 large angular cells with outward tendrils, elongated 1.75:1, baked yellow core / orange glow; flat on the ground, LightEmission 1 |
| RadialDust | rbxassetid://72281968873307 | Custom: soft radial smudges around an empty centre, white; tinted dark = dust blown out across the floor |
| BandArc | rbxassetid://132232127473921 | Custom: glowing lower half of an ellipse (the front of a flat ring seen from ~25 deg up), square, white; camera-facing in front of a gas dome = a glowing band around it |
| dark glowing rift | rbxassetid://130357872021925 | Long thin jagged horizontal crack; on a Top-face SurfaceGui (LightInfluence 0) = a ground fissure, tinted dark or lava red. Its background alpha isn't quite 0: keep the face narrow |
| Upwards flame pillar | rbxassetid://70418763522849 | 4x4 flipbook, small upright flames with a grainy tip; first frames are tiny, so use Loop + FlipbookStartRandom for bursts. Precursor flame bursts; near-black = dark flame silhouettes |
| Fire Tower | rbxassetid://18456244650 | 4x4 flipbook, smooth thin upright flame wisps; FacingCameraWorldUp, Loop + StartRandom = a curtain of flame tongues (smoother than Upwards flame pillar) |
| Blurry glowing flame | rbxassetid://107423905441539 | 4x4 flipbook, soft flame blobs; behind tongues as a flame body. Squash ~1 (2:1 upright) or it reads as round balls |
| BeamFlameWisps | rbxassetid://125449362531870 | Beam: vertical flame tongues across the width; a wide faint camera-facing veil behind particle flames |
| BeamFlamePeaks | rbxassetid://118613370531472 | Beam: flame peaks rising from a base; second veil layer |
| BeamOrangeFireColumn | rbxassetid://11767688250 | Beam, coloured: orange column with a yellow core; Width0 ~0 at the top = a tapered flame |
| BeamSoftGlowCore | rbxassetid://12781750620 | Beam: soft vertical glow (behind a column, or a dim streak above it) |
| Random Rocks | rbxassetid://14305019062 | 4x4 flipbook, one grey rock per cell; Framerate 0 + StartRandom = varied flung chips |
| Realistic Smoke Burst | rbxassetid://11866632577 | 4x4 flipbook smoke puff with spiky edges; reads as star silhouettes when dark. For soft smoke shooting up use smoke 41 (Speed ~100-130, Drag 12) |
| Line Spec 3 | rbxassetid://104267390423468 | Tall flame-shaped streak; FacingCameraWorldUp spike rows and dark streak bursts |
| Basic Flame Wisp | rbxassetid://16504098653 | 4x4 flipbook, small curly flame; orange = side curls, near-black = dark flecks |
| dark fire spec | rbxassetid://77001323190674 | 4x4 flipbook (128 cells on a 512 sheet): hollow wiggly rings; orange = ring curls flung from fire |
| Blurry Horizontal Flare | rbxassetid://103854278038347 | Thin horizontal flare line; camera-facing at the ground = a hot line along a fissure or a flat flash |

Gradient strips used as mesh `TextureID` should fade left to right (along U),
matching the MeshFactory UV layout.

## Making new textures

When nothing in the library fits, make one (white RGB, shape in alpha; tint with
`Color`). Pick the tool by what the image is:

| Image | Tool |
|---|---|
| Flipbooks (frames that grow and break apart on an exact grid), crisp drawn shapes (claws, crescents, puffs, splinters, cracks, impact stars) and light (glows, glints, flares, rings, lens streaks) | Draw it with numpy: `<skill>/tools/vfxtex.py` (`drawing-textures.md`). Exact grids, padding and frame-to-frame change, checked by `<skill>/tools/flipbook.mjs` |
| Any other single texture (painterly strokes, smoke plumes, stylised flashes) | An AI image generator the user has (ComfyUI, an image MCP, another assistant's image tool). Ask which they use |
| A 3D look: a simulation, a lit volume, shaded debris | Render it in Blender with `vfxtex.render_flipbook` (`drawing-textures.md`) |

For a drawn texture, steps 1-2 below are replaced by `vfxtex` (it writes white RGB with the
shape in alpha, at the size you ask for) and `flipbook.mjs`; continue at step 3.

1. Generate the image. Prompt for a **single isolated shape, pure white on a pure black
   background, no text, no frame**, and say the layout you need (centred, square, tall
   streak for a beam, NxN grid of cells for a flipbook). Save the result to the scratchpad
   and look at it before converting.
2. Convert it to white RGB with the shape in alpha (alpha = brightness, RGB = 255) and
   resize to a power of two, with numpy or PIL (Blender's Python ships numpy). Simple exact shapes (gradients, rings, plain falloffs) can be drawn straight with
   numpy instead of generated.
3. Upload it: Studio's Asset Manager (Bulk Import) or the Creator Dashboard, or, with the
   Studio MCP, serve the folder over HTTP (`python -m http.server 8765 --bind 127.0.0.1`, in
   the background) and `upload_image` `http://127.0.0.1:8765/<file>` (it only takes http URLs).
4. Verify by reading pixels back: `AssetService:CreateEditableImageAsync(Content.fromAssetId(id))`.
5. Add a row to your project's texture table, noting which tool made it (for a drawing, keep
   its script beside the PNG).

Beam and Trail textures: X spans the beam's width, Y runs along its length and tiles,
so draw them tall (e.g. 128 x 512) with the streak running vertically. A wide texture
shows up as stripes across the beam.

`VelocityParallel` particles run the texture's **X** along the velocity, so an upright
(tall) texture needs `Rotation = -90` to point its tip along the motion.

Custom uploads by the skill's original author (white RGB, shape in alpha; drawn with PIL unless noted):

| Name | Id | Use |
|---|---|---|
| lava_streak | rbxassetid://138131925212643 | Straight flame streak, soft root, long taper to a sharp tip (128x512). |
| lava_wedge | rbxassetid://109547847796563 | Soft flare wedge, bright rounded root (64x256). Radial ground starbursts and splashes (VelocityParallel, Rotation -90). |
| lava_ring | rbxassetid://113782032324685 | Thick soft, slightly lumpy ring (128x128). Bold flung rings; reads better than the hollow curl flipbooks. |
| lava_glow | rbxassetid://87365446017300 | Round soft glow that falls to exactly zero at the edge (128x128). Use instead of Blurred Spec 11 (284205403), which has a hard bottom edge on upright quads. |
| lava_arch2 | rbxassetid://91461964686009 | Inverted U with a wobbly flame-edged rim (128x192). No longer used: as a standing glow it read as a ring sticker. |
| lava_hollow2 | rbxassetid://104220462120494 | Soft egg with a wavy flame-licked rim and wide falloff (128x128). A dark unlit particle in front of a bright glow cuts a soft hollow. lava_glow's alpha is a steep cone, so it only reads big when added; it can't darken. |
| cs_impact_flash | rbxassetid://106031250604546 | Jagged V-wing flash mass, wider than tall (512, AI image tool). Impact and launch flashes; red/blue copies behind = chromatic fringe. |
| cs_smoke_hook | rbxassetid://134858289383590 | Smoky arched hook stroke, 1:2 tall (256x512, AI image tool). Lingering arched smoke plumes (Squash ~0.6-1). |
| cs_soft_trail | rbxassetid://85104342894286 | Soft fibrous trail strip, Gaussian across, uniform along (segment joints never show) (128x512, drawn in Python). Beam texture (Wrap) for smoky projectile trails; library streaks tile with hard ends. |
| cs_rgb_bolt | rbxassetid://100904020799857 | Black-edged RGB-split zigzag bolt, colour baked, transparent (512, AI image tool). Glitch bolts at LightEmission 0. |
| cs_halo_thin | rbxassetid://118128517935651 | Crisp thin ring at 0.86 of the half-width with a tight glow (512, drawn in Python). Halo rings that must stay thin. |


## Finding library textures

- **Creator Store:** the Toolbox's Images and Decals search finds free VFX textures (search
  "slash", "flipbook", "smoke", "spark"). A decal's image id differs from the decal id: insert
  it and read `Decal.Texture`, or paste the decal id into a ParticleEmitter's Texture field
  and Studio converts it.
- **A project art library:** if the place keeps texture "cards" in a Studio-only folder
  (ImageButtons or ImageLabels named after the asset), search it from the command bar and
  copy the ids into `ASSETS` (never read cards at runtime):

```luau
local lib = game.ReplicatedStorage.Assets.VFX -- wherever the library lives
local keyword = "slash"
for _, item in lib:GetDescendants() do
	if item.Name:lower():find(keyword, 1, true) then
		local tex = item:FindFirstChild("Texture")
		local image = (item:IsA("ImageLabel") or item:IsA("ImageButton")) and item.Image
		local mesh = item:FindFirstChildWhichIsA("SpecialMesh", true)
		print(item:GetFullName(), (tex and tex.Image) or image or (mesh and mesh.MeshId),
			tex and tex:GetAttribute("OriginalRectSize") or (mesh and mesh.Scale))
	end
end
```

- **Flipbooks:** grid = sheet size / cell size. On a 1024 sheet: 512 -> `Grid2x2`,
  256 -> `Grid4x4`, 128 -> `Grid8x8`. Not every sheet is 1024: some 128-cell sheets are
  512 (`Grid4x4`). If a flipbook shows tiles or a filled square, try the next grid down.
  Use `FlipbookMode = OneShot` for bursts (plays once over each particle's lifetime).
- **Beam textures** tile vertically, so as particles they show flat cut-off ends. Prefer a
  flipbook or static texture for free-floating streaks.
- **Library meshes** are often `SpecialMesh` (FileMesh) data: rebuild them as a Part +
  SpecialMesh. A FileMesh is sized by `SpecialMesh.Scale`, not `Part.Size`.
