# Farming

Crops are world nodes, built on the same system as saplings, bushes and trees (docs/factory.md).
A seed placed on soil becomes a crop's first stage. Each stage grows into the next until the crop
is ripe, and an empty hand or a machine harvests it. Each module's header owns its own rules; this
page is the map between them.

## Flow

```text
seed item (Block)  --PlaceBlock-->  BuildService  -- Soil.canPlant? (Shared/World/Soil)
                                        |  places it in Workspace.Placed
                                        v
WorldService.onPlaced  -- swaps it for the crop's Sprout node (World.PLANTS) in Workspace.World
   |  grow(): GrowsAt attribute, then Sprout -> Young -> Mature -> Ripe   (World.CROPS `every`)
   |
   +-- Interact "Take" (empty hand)  -> uproot: its seed back, or when ripe its harvest
   +-- FactoryService (Sapling Automatic Planter)  -> WorldService.plant(cell, seed)
   +-- FactoryService (Industrial Flower Picker)   -> WorldService.reap(ripe) -> back to Sprout
   +-- soil block picked up or broken             -> uprooted, its harvest dropped (DropService)

BlockInfo (hover)  -- stage ("Growing 2 / 4", "Ripe") and "Next stage" from GrowsAt
```

## Crops

`World.CROPS` holds each crop's seed, what a ripe harvest gives by hand, what a machine reaps, and
how long each stage takes. One node type per stage is generated from it: `<Crop><Stage>`, with the
stages `Sprout`, `Young`, `Mature` and `Ripe` (`World.STAGES`).

| Crop | Seed | Seconds per stage | Ripe, by hand | Reaped by a machine |
|---|---|---|---|---|
| Wheat | Wheat Seeds | 15 | 1 Wheat, 2 Wheat Seeds | 1 Wheat |
| Carrot | Carrot Seeds | 20 | 2 Carrots, 1 Carrot Seeds | 2 Carrots |
| Potato | Potato Seeds | 25 | 3 Potatoes, 1 Potato Seeds | 3 Potatoes |

An unripe crop dug up by hand gives its one seed back. A reaped crop starts again from a sprout in
the same cell, so the machine keeps the seed.

## Rules worth knowing

- **Seeds need soil under them.** Soil is a placed Grass or Dirt block (`World.SOIL_BLOCKS`) or a
  Farmland node (`soil` in `Shared/World`). The farm field in `World/Layout` has 18 Farmland nodes.
  `Soil` reads the world with an overlap query each time, so placing or breaking a soil block needs
  no bookkeeping. The client's ghost is red off soil, and BuildService refuses the placement.
- **Seeds are Block items** so the hand places them with a ghost. Their `Assets.Blocks` template
  is a copy of the crop's Sprout art. A placed seed never stays a block: WorldService turns it
  into the Sprout node at once.
- **Crops have no collisions.** Their art parts (`Crop`, `Grain`, `Bloom`, `Tuber`) don't
  collide, so players walk through a field, but aim rays still hit them.
- **Machines.** The Sapling Automatic Planter plants the first of its loaded items (saplings, then
  each seed) that fits the cell past its forks. A seed only fits when soil is under that cell, so
  stand the planter on a floor of grass or dirt blocks. The Industrial Flower Picker reaps any
  ripe crop within 6 cells, as well as picking tulips. The Automated Trough also feeds wheat and
  carrots.

## What lives only in the place file

| Instance | What it is |
|---|---|
| `ReplicatedStorage.Assets.World` | `Farmland` (a soil cube with a damp, striped top, never turned so a field's stripes line up) and every crop stage (`WheatSprout` ... `PotatoRipe`), each with a one-cell hitbox |
| `ReplicatedStorage.Assets.Blocks` | `WheatSeeds`, `CarrotSeeds`, `PotatoSeeds`: copies of each crop's Sprout |
| `ReplicatedStorage.Assets.Items` | `Wheat`, `Carrot`, `Potato` |
| `ReplicatedStorage.Assets.Blocks.Dirt` | Restyled to match the farm: SmoothPlastic in the same brown as the crops' soil and the Farmland cube (`#9C6A3C`) |

The art is built in `IslandsMachines/build/assets.py` (the farming section) and imported like the
rest of the world art. `studio_blocks.luau` copies the sprouts into `Assets.Blocks` (`alsoBlocks`).

## Adding a crop

1. Add a seed (`seed(...)`) and its produce (`resource(...)`) to `Shared/Inventory/Items`.
2. Add an entry to `World.CROPS`.
3. Build art for its four stages (`<Crop>Sprout` ... `<Crop>Ripe`) and its produce in `assets.py`,
   add its Sprout to `alsoBlocks` in `studio_blocks.luau` under the seed's id, and import them.
4. Add the seed to the planter's `plants` in `Shared/Factory/Blocks`. The picker picks up every
   crop on its own.

## Not built yet

- Persistence: crops and planted fields reset with the server, like everything else.
- No hoe: tilling isn't needed, since grass and dirt blocks are soil as they are.
- No water, fertiliser or seasons. A crop grows on a fixed timer wherever it stands.
