---
name: blender-studio-assets
description: >
  This project's pipeline for game art from Blender into Roblox Studio: blocks, machines,
  items, world nodes and crops modelled in studs with vertex colours and named parts, checked,
  uploaded as mesh assets through Studio MCP, then given hitboxes, materials and collisions
  and copied into ReplicatedStorage.Assets. Use when making or changing any 3D model, prop,
  machine, crop or block art, re-uploading a changed mesh, fixing art that is the wrong size or
  doesn't line up, or setting the game's art direction.
---

# Blender to Studio assets

The kit lives in `IslandsMachines/`. It is **gitignored**, so it exists only on this machine
and its [README](../../../IslandsMachines/README.md) is the reference. Read the
`islands-factory-blocks` memory for its history. For general Blender work, load
`blender-agent-skills:blender-core` first and run `blender-agent-skills:blender-asset-qa` as
the QA gate. Rigged pets use `blender-roblox-pets`.

## Art direction

The game is a **calm, satisfying industrial farming game**:

- soft, smooth shapes with more segments, rounded edges and no jagged or jittered hulls;
- light, warm, low-contrast colours. The soil is a light warm brown (`SOIL` in
  `build/assets.py`), never dark or rough Ground material;
- a silhouette of its own. Islands (and Grow a Garden) are references for gameplay and
  scale, and **their models are not to be copied**;
- building cubes use Roblox's built-in `TopSurface = Studs` on Plastic (`studio_studs.luau`),
  Grow a Garden style.

## Conventions (don't change them to fix a size bug)

- 1 Blender unit = 1 stud, and 1 block = 3 studs. +Z is up, conveyors run along +Y, and every
  machine's conveyor or tube runs down X = 0.
- Keep the art inside whole cells (it may poke out by 0.15 studs at most), and run every end
  that meets a neighbour to a cell face. The hitbox is computed from this, and placement and
  connections depend on it.
- Shared heights and profiles come from `build/islandskit.py` (`BELT_TOP`, `RAIL_TOP`,
  `conveyor`, `port`, `ramp`, ...), and the tube shapes share `wood_tube.LOG_R`. Reuse them, so
  pieces line up without steps.
- Flat colours are vertex colours (`Color`, sRGB, per face corner), with no textures or
  materials. Keep `MeshPart.Color` white in Studio.
- One mesh per semantic part, `Mesh_<Block>_<Part>` (Belt, Body, Glass, Glow, Light, Fluid,
  ...). The suffix drives Studio setup: `*_Glass` is about 0.5 transparent, `*_Glow`/`*_Light`
  are Neon, `*_Fluid` starts hidden. Wood parts get `Wood`, rock gets `Slate`, everything else
  `SmoothPlastic` (Metal dulled the colours).
- If a size is wrong in game, change `L`/`span` in `build/machines/<block>.py` or the
  importer unit, never the stud convention.

## Pipeline

1. **Model**: one script per block in `build/machines/`. Items, world nodes, animals and crops
   are in `build/assets.py`. Build them with `runner.run([...])`, which also renders review
   images.
2. **QA and export**: `export.run()` checks for z-fighting, floating parts, flipped normals,
   open geometry, triangle count and UVs, then re-imports to compare. Without the Blender MCP,
   run Blender headless: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b
   IslandsMachines.blend --python <script>`, Eevee renders included.
3. **Mesh data**: `roblox_data.run()` (or `run(assets.ORDER_ITEMS, 'items.json')` /
   `ORDER_WORLD, 'world.json'`). Serve it with `python -m http.server 34999 --bind 127.0.0.1`.
4. **Import**: run `build/studio_import.luau` through Studio MCP `execute_luau` (Edit). It
   builds EditableMeshes and uploads each part with `AssetService:CreateAssetAsync`, and its
   `SET` picks IslandsMachines, IslandsItems or IslandsWorld. Allow HTTP Requests must be on.
   It runs in the background, so watch the folder's Status, Progress and Failed attributes.
5. **Finish**: run `build/studio_blocks.luau`. It sets materials, collisions
   (`PreciseConvexDecomposition`), the whole-cell `Hitbox` PrimaryPart, `AuthoredOrigin` and
   `PortDepth*`, then copies everything into `ReplicatedStorage.Assets.Blocks/World/Items`.
   It reports any conveyor end that stops short of its face. Rerun it after **any** import.
6. **Check in Studio**: take a screenshot next to a reference, place the block in game, and
   connect a belt or tube to each port.

## Re-uploading a changed part

The importer reuses mesh ids by part name. Clear the changed parts' ids in
`Workspace.IslandsMachines._MeshAssetIds` and delete that model, then import. For a few
blocks, prefer a small inline import over a full rerun: the importer's "complete" check
counts the Hitbox child, so a full rerun after `studio_blocks` rebuilds every block. Then run
`studio_blocks.luau` again, limited with gsub to the changed blocks if it's long (see
`studio-playtest` for running long scripts).

## References

The Islands wiki is `robloxislands.fandom.com` (not islands.fandom.com). WebFetch gets 402 and
its images get 403, so use the MediaWiki `api.php` with curl for text, and **ask the user for
renders or screenshots**. Compare sheets go in `IslandsMachines/review/`. When you choose a
layout the user didn't specify, say so.
