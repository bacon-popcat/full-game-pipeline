# Making meshes

Mesh assets for effects are generated with code, never sculpted.
Tool: `ReplicatedStorage/Shared/VFX/MeshFactory`. Run it in Edit mode only (via
execute_luau). Effects must never require it.

```luau
local MF = require(game.ReplicatedStorage.Shared.VFX.MeshFactory)
```

## Workflow

1. **Reuse first.** Look in `ReplicatedStorage/Assets/Meshes` (a Studio-only folder that
   MeshFactory creates; it is not on disk and is separate from the code folder
   `ReplicatedStorage/Shared/VFX`). Each template has
   `Generator`, `Params`, and `AssetId` attributes. If a close match exists, use it
   and scale it in the effect instead of making a new mesh.
   `MF.FindExisting(generator, params)` checks for an exact match.
   The art library's `MigratedMeshes` folder also has ready-made meshes (see
   `textures.md`, "Asset library").
2. **Pick a generator** from the table below. Tune its params.
3. **Preview before publishing.**
   ```luau
   local mesh = MF.Generators.Crescent({ Radius = 4, Arc = 170 })
   local preview = MF.Preview(mesh) -- temporary MeshPart at (0, 6, 0), not saved
   ```
   Screenshot it from 2 angles with screen_capture. Check: right shape, no holes,
   no inside-out faces (looks dark or invisible from outside), sensible size.
   Destroy the preview after. Adjust params and repeat if needed.
4. **Publish** with `MF.Make(name, generator, params)`. It reuses an exact match
   if one exists, otherwise uploads and saves a template to `ReplicatedStorage/Assets/Meshes/<name>`.
   Names are PascalCase and describe the shape, not the effect:
   `CrescentThin170`, not `RangerSlash`.
5. **Use it** in the effect: clone `Meshes.<Name>` for a single animated mesh, or
   pass the template to `MeshParticles.Burst` for many pieces. Include a plain-Part
   fallback in case the template is missing (see `examples/GroundSlam.luau`).

## Generators

All shapes have Y up. U runs along the length or around the shape, V across it.

| Generator | Shape | Key params |
|---|---|---|
| Crescent | Flat tapered slash arc, centered on +X | Radius, Width, Arc (deg), Segments, Taper |
| Ring | Flat ring | InnerRadius, OuterRadius, Segments |
| Tube | Open (flared) cylinder wall | Radius, Height, Flare, Segments |
| Spike | Cone pointing up | Radius, Height, Sides |
| Shard | Jittered crystal double-pyramid | Length, Width, Sides, Seed |
| Rock | Lumpy noise sphere | Radius, Rings, Segments, Roughness, Squash (Vector3), Seed |
| Sphere | Smooth UV sphere, equirect UVs (U around Y, V = 0 at the top pole) | Radius, Rings, Segments |
| Swirl | Ribbon spiralling up around Y (tornado, aura, charge-up), open, double-sided | Radius, TopRadius, Height, Width, Turns, Segments |
| Dome | Open half sphere standing on Y = 0 (barrier, blast bubble), double-sided | Radius, Segments, Rings |

A flared `Tube` (Flare > 1) is a blast wall; `Flare` near 0 makes it an open cone (a muzzle
blast pointed along the LookVector).

For variety (debris), publish 2-3 seeds of the same generator rather than one.

## When no generator fits

For an open sheet you can describe as a function, use
`MeshFactory.Surface(point, columns, rows)`: `point(u, v)` returns the Vector3 of each grid
corner for u, v in 0..1, that corner's UV is (u, v), and collapsed triangles (a pole, a tip)
are skipped. A torn shockwave ring:

```luau
local rng = Random.new(4)
local spikes = {}
for i = 1, 24 do
	spikes[i] = 1 + rng:NextNumber(-0.25, 0.45)
end
local mesh = MF.Surface(function(u, v)
	local i = u * #spikes
	local a, b = spikes[math.floor(i) % #spikes + 1], spikes[(math.floor(i) + 1) % #spikes + 1]
	local spike = a + (b - a) * (i % 1)
	local radius = 4 + v * 1.5 * spike
	return Vector3.new(math.cos(2 * math.pi * u) * radius, 0, math.sin(2 * math.pi * u) * radius)
end, 96, 2)
MF.Preview(mesh) -- check it, then MF.Publish(mesh, "TornRing", "Surface", { Seed = 4 })
```

`Surface` isn't in `Generators` (a function can't be saved as `Params`), so `MF.Make` can't
rebuild it: keep the code that made it in the effect's notes or here.

Otherwise write a new generator in MeshFactory using `MeshFactory.Build(positions, uvs, tris, opts)`:
- `positions` and `uvs` are parallel arrays (one entry per vertex); `tris` are
  `{i, j, k}` index triples.
- Y up; flat shapes in the XZ plane.
- U along the length or around the shape, V across it (0 -> 1).
- Thin/open shapes: `doubleSided = true`. Closed convex shapes: `orientOutward = true`.
- Under ~1000 triangles (the budget in `SKILL.md`).
Add it to `MeshFactory.Generators` and to the table above once it works.

## Troubleshooting

- **Publish fails with "CreateAssetAsync and CreateAssetVersionAsync are not available
  yet":** the Studio beta feature for asset creation is off. Ask the user to enable it
  (and restart Studio). Fallback: export FBX to `assets/meshes/` for the 3D Importer.
- **Wrong owner:** if the game is group-owned, pass
  `{ Id = groupId, Type = Enum.AssetCreatorType.Group }` as the creator so the mesh
  loads in that game.
- **New mesh shows blank or fails to load:** it may still be in moderation. Use the
  fallback and check again later.

## Not for this tool

Detailed organic or prop models (a sword, a creature, a tree), or shapes that are much
easier to model than to write as a generator. Model those in Blender
(`mcp__Blender__execute_blender_code`, in a separate scene so the user's scene is
untouched). Export triangles + UVs as JSON (convert Blender Z-up to Roblox Y-up as
`(x, z, -y)`), then get the data into Studio without retyping it: write the JSON to
`src/shared/TempMeshData.json` (Rojo syncs it as a ModuleScript), check a checksum
(triangle count and index sum) against the file, `require` it, `MeshFactory.Build` +
`MeshFactory.Publish` (generator name "Blender"), then delete the temp file. Never paste
large mesh data into execute_luau by hand; it gets corrupted. Also save an FBX to
`assets/meshes/` as the source. The Studio MCP's generate_mesh is the quick AI alternative.

| Mesh | Id | Use |
|---|---|---|
| SpiralRibbon | rbxassetid://129291594721141 | Blender: 2-turn tapering spiral ribbon, ~5.6 x 6.7 x 4.9; vortex/tornado layer (`assets/meshes/SpiralRibbon.fbx`) |
| SmoothSphere | rbxassetid://132254310752039 | MeshFactory Sphere (Radius 0.5, 14 x 28, 728 tris): 1-stud textured ball (fireball balls, spot/lava/band/ash shells) |
| TubeBand | rbxassetid://91818310113323 | MeshFactory Tube (Radius 1, Height 0.2): short open band; currently unused |
| BlobDome | rbxassetid://77391562621395 | Blender metaballs: rounded squashed dome with soft lobes, 2 x 0.88 x 1.9, 758 tris, spherical UVs (v ~0.45 at mid height); currently unused (`assets/meshes/BaseBlob.fbx`) |
| ShellShard1 / ShellShard2 | rbxassetid://88449942291976 / 87477348430076 | Blender: jagged curved fragments of a 0.07-thick sphere shell (~1.2 / 1.0 studs, 268 / 196 tris); crumbling-shell chips for MeshParticles (`assets/meshes/ShellShard.fbx`) |

## Mesh effects

Shapes that grow, spin and fade: a crescent slash, a shockwave ring, a twisting swirl, a
sphere shell, a ground wave. Strong battleground-style games are built on them: 20 of 48
studied effect files add glowing meshes beside their particles. From Roqer's VFX skill
(https://github.com/S4US/Roqer, `vfx-mesh-shapes.md`, AGPL-3.0-or-later); marks as in
`design.md`.

**How the studied artists tween them** *(measured)*, with `ctx.Tween` on `Size`, `CFrame` and
`Transparency`:
- ease out (Cubic or Quart) over 0.2-1 s;
- a shockwave flattens (height x0.1-0.3) while it widens (x2-7) and spins 120-170 degrees;
- a swirl stretches upward as it narrows.

**How they surface them** *(measured)*:
- Faint `Neon` that fades out: starting `Transparency` 0.9-0.96 for white wind swirls, or 0
  for a coloured one.
- Black `Neon` swirls as dark accents (our gotcha: dark Neon renders flat and unlit).
- A FileMesh (`SpecialMesh`) on an invisible part with a Decal whose `Color3` is above 1 so it
  blooms (`Color3.new(4, 6, 8)`), fading the Decal. On a FileMesh part the studied Decals
  follow the mesh's surface *(measured; not checked)*. On a MeshPart a Decal is projected
  across the part's box face and ignores UVs, so its texture must be drawn for that flat
  projection.
- A `SurfaceAppearance` with `AlphaMode = Transparency` follows the UVs but rendered dithered
  in Studio, and scripts cannot change its maps at runtime.

**Rules that keep them clean:**
- Set `RenderFidelity = Precise` on thin curved shapes. With Automatic, Roblox simplifies a
  thin card at distance until a crescent reads as a straight-sided wedge *(verified)*. It is
  set when a MeshPart is created, and `MeshFactory.Publish` now creates templates with
  `RenderFidelity = Precise`. Templates published before that keep Automatic: set it on the
  template in Studio, or re-publish one that shows wedges at range.
- MeshFactory's flat shapes are double-sided geometry already.
- Under vertex colours keep the part's `Color` white, because `Color` multiplies them.
- A MeshPart's texture cannot scroll (`TextureID` has no offset). Animate size, rotation and
  `Transparency`, or put a scrolling Beam alongside.
- `MeshPart.TextureID` ignores alpha: the texture's colour covers the whole surface and
  nothing shows through *(verified)*. Don't put a fading texture there; fade the part's
  `Transparency` (a `Neon` card fading from about 0 to 1 is the reliable mesh effect), or a
  Decal on a part with `Transparency = 1`.
- `Material = ForceField` with a texture gives a shimmering, edge-lit shell. Its animation
  speed cannot be controlled, so it suits a shield or aura, not a timed wipe.
- **Big shells, domes and columns** that are half transparent across their whole surface read
  as tinted plastic and cover the screen; below a `Transparency` of about 0.75 they look solid
  against a bright sky. Keep a big shell faint (0.85-0.96), or give it surface shape (streaks,
  a broken edge in a Decal), and let particles and a flash carry the brightness.

**Verified crescent slash** *(verified by Roqer)*: two crescents (MeshFactory `Crescent`). A
white `Neon` core goes from `Transparency` 0.05 to 1 over 0.2 s; a larger blue `Neon` glow goes
from 0.55 to 1 over 0.32 s. Each grows from about 0.8 to 1.2 times its size while turning 50
degrees (`Quart` Out), and sparks come off the edge.

**Ground wave without a mesh:** a flat Neon cylinder part (axis along X: size
`(0.1, 2, 2)`, rotated 90 degrees about Z) tweened over 0.35 s (Cubic Out) to `(0.05, 20, 20)`,
`Transparency` 0.55 to 1, colour from `(1, 0.75, 0.4)` to `(1, 0.45, 0.15)`. A `Ring` mesh can
also spin.

