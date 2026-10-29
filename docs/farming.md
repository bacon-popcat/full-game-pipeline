# Farming

Crops are WorldService nodes. Seeds plant on soil in the owner's plot, grow through stages,
and are harvested by hand or machine. Each module's header owns its rules;
[plots.md](plots.md) covers assignment, ownership and persistence.

## Flow

```text
seed -> PlaceBlock -> BuildService (held item, ownership, reach, overlap, Soil)
                         -> WorldService.plant -> Workspace.World
                              | wall-clock plantedAt -> elapsed stage
                              | GrowsAt -> BlockInfo "Next stage"
                              + Interact Take -> owned crop's seed or ripe harvest
                              + FactoryService -> reap -> new Sprout, new plantedAt

DataService load -> restore blocks/soil -> WorldService.restore -> elapsed stage
DataService snapshot <- relative cells, crop ids, plantedAt, harvest state
```

Seeds no longer briefly become placed blocks. BuildService calls WorldService directly,
so saving cannot catch a seed between its block and crop representations.

## Crops

Shared/World.CROPS owns seeds, harvests, machine yields and stage durations. It generates
the stage definitions and PLANTS mapping. Foundation retains the existing three crops and
balance; the twelve-crop table, multi-harvest behavior and mutations arrive in Garden loop.

| Crop | Seed | Seconds per transition | Ripe, by hand | Reaped by machine |
|---|---|---|---|---|
| Wheat | Wheat Seeds | 15 | 1 Wheat, 2 Wheat Seeds | 1 Wheat |
| Carrot | Carrot Seeds | 20 | 2 Carrots, 1 Carrot Seeds | 2 Carrots |
| Potato | Potato Seeds | 25 | 3 Potatoes, 1 Potato Seeds | 3 Potatoes |

Unripe crops return their seed. Hand harvesting uproots the crop; machine reaping keeps the
seed by restarting a Sprout. Saved harvestCount advances on machine reaping; mutation is
reserved and not rolled in Foundation.

## Rules worth knowing

- **Soil is required.** World.SOIL_BLOCKS names placed soil blocks; nodes marked soil also
  qualify. World/Soil queries the world. PlotService creates Farmland through WorldService;
  there is no public farm in World/Layout.
- **Seed placements and harvests require ownership.** Build's shared check turns the ghost
  red outside the plot. The server independently checks it. Quarry mining stays shared.
- **Growth uses wall-clock time.** plantedAt is os.time(); WorldService derives the stage
  from elapsed time. Offline crops jump directly to their reached stage. Foundation retains
  three transitions to Ripe. GrowsAt remains a GetServerTimeNow deadline for BlockInfo.
- **Removing soil uproots its crop into owned drops.** Plot cleanup removes crops before
  blocks, preventing duplicate cleanup harvests. Deferred removal checks current soil again.
- **Farm machines need no fuel.** Sapling Automatic Planter tries loaded seeds in its cell
  past the forks. Industrial Flower Picker reaps ripe crops in its current radius. Targets
  must be inside the machine's own plot at selection and completion. New patch sizes and
  radii belong to Automation.
- **Only crops grow offline.** Machine jobs do not simulate elapsed offline time.

## Place-file art and adding crops

Assets.World holds Farmland and each crop's Sprout, Young, Mature and Ripe models;
Assets.Blocks holds seed ghosts and Assets.Items produce. Crop art is authored non-colliding
but queryable. Missing world art uses a one-cell placeholder. Foundation edits no art assets.

Add a seed and produce to Inventory/Items, data to World.CROPS, and stage/seed/item art in
Studio. Add the seed to the planter's plants list in Factory/Blocks; the picker derives its
sources from the crop catalogue. Saves store crop ids, not stage-art ids.

There is no hoe, water, fertilizer, weather or mutation roll yet. Harvest/sale XP awards and
new progression values arrive with the later garden loop; Foundation provides the economy API.
