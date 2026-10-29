---
name: blender-studio-assets
description: >
  A scripted pipeline for game art from Blender into Roblox Studio: blocks, machines, props,
  items, world nodes and crops modelled in studs with vertex colours and one mesh per named
  part, checked by QA, uploaded as mesh assets through Studio MCP, then given hitboxes,
  materials and collisions and copied into ReplicatedStorage. Use when making or changing a
  3D model, prop, machine, crop or block, re-uploading a changed mesh, fixing art that's the
  wrong size or doesn't line up, or setting up an art pipeline.
---

# Blender to Studio assets

Load `blender-agent-skills:blender-core` first for Blender itself, and use
`blender-agent-skills:blender-asset-qa` as the QA gate. For rigged and animated characters
or pets, use `blender-roblox-pets`. This skill is about the pipeline: keeping many game assets
consistent, rebuildable and placeable.

## Before modelling

- **Ask for the art direction** and write it down: the shapes (soft and rounded, or chunky and
  angular), the palette (light and warm, or saturated), and the contrast. Use more segments
  for soft looks, and avoid jittered hulls unless the style calls for them.
- **References are for scale and function, not for copying.** Give each asset its own
  silhouette unless the user asks for a recreation.
- When the reference site blocks fetching (some wikis return 402/403 or show a consent wall),
  try its MediaWiki `api.php` with curl for text, and **ask the user for renders or
  screenshots**. Save comparison sheets beside the build scripts.
- When you choose a layout or size the user didn't give, say so.

## Conventions to fix on day one

- **1 Blender unit = 1 stud**, with one grid cell of a fixed size (for example 3 studs). Pick
  the up axis and the direction belts and pipes run in, and write both down.
- Keep the art inside whole cells, poking out by a small tolerance at most, and put every end
  that meets a neighbour on a cell face. Hitboxes and connections depend on this (see
  `grid-building`).
- Keep shared dimensions (belt height, rail profile, pipe radius) in one kit module that every
  build script imports, so pieces line up without steps.
- Use flat vertex colours (sRGB, per face corner) and no textures, for a clean stylised look
  and cheap rebuilds. Set `MeshPart.Color` to white in Studio so the vertex colours show
  unchanged.
- Make **one mesh per semantic part**, named `Mesh_<Asset>_<Part>`. The suffix drives the
  Studio setup: `*_Glass` gets transparency, `*_Glow` and `*_Light` get Neon, `*_Fluid` starts
  hidden, wood parts get `Wood`, and the rest get `SmoothPlastic`. Metal tends to dull vertex
  colours.
- If an asset comes out the wrong size in game, fix its build script's dimensions or the
  importer's unit, never the stud convention.

## Pipeline

1. **Build scripts:** one Python script per asset (or one module for small assets), plus a
   runner that builds by name and renders review images. Everything must be rebuildable from
   scripts.
2. **QA and export:** check for z-fighting, floating parts, flipped normals, open geometry,
   triangle budgets and UVs, then re-import the export and compare. Without a live Blender
   MCP, run headless: `blender -b <file>.blend --python <script>` (Eevee renders work there).
3. **Mesh data:** write each part's vertices, faces and colours as JSON. Serve the folder with
   `python -m http.server <port> --bind 127.0.0.1`.
4. **Import:** a Luau script run through Studio MCP `execute_luau` (Edit mode) builds
   EditableMeshes from the JSON and uploads each part with `AssetService:CreateAssetAsync`.
   It needs Allow HTTP Requests, and it should record each uploaded asset id by part name so a
   rerun reuses them. Run it in the background and report progress through attributes.
5. **Finish:** a second Luau script sets materials and collisions
   (`PreciseConvexDecomposition` for shapes with tunnels or gaps), builds the whole-cell
   `Hitbox` root part and any port metadata, and copies the templates into
   `ReplicatedStorage.Assets`. Make it rerunnable and run it after every import.
6. **Check in Studio:** take a screenshot next to the reference, place the asset in game, and
   connect a belt or pipe to each of its ports.

## Re-uploading a changed part

The importer reuses asset ids by part name, so clear the changed parts' ids and delete the
model before importing again. If the importer's "already complete" check counts children
that the finish script adds, a full rerun rebuilds everything, so import only the changed
assets. For running long scripts through MCP without pasting them, see `studio-playtest`.
