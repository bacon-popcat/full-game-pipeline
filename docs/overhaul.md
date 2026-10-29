# Garden overhaul

The plan for turning the Islands-style factory sandbox into an industrialized farming game in the
spirit of Grow a Garden: each player has their own plot, buys seeds from a shop that restocks,
grows crops that can come out mutated and worth more, sells them, and saves up for machines that
farm, process and sell for them. A second progression mines ore and crafts it into parts for
higher machine tiers. Work happens on the `garden-overhaul` branch, phase by phase; each phase
ends playable.

The feel is calm and satisfying (see the game-vision note): soft, light art, things you enjoy
watching grow and flow, no harsh fail states. Islands is a reference for how machines and
conveyors play, never for their models.

## Decisions

| Question | Choice |
|---|---|
| Core loop | Grow a Garden's buy seeds, grow, sell loop, plus mining and crafting as a second progression |
| World | One plot per player on a shared map, with shops and a quarry in the middle; plots are saved |
| Getting machines | Bought with coins from a machine shop, unlocked by level; tier 2 also costs crafted parts |
| Machine art | Gameplay first with the current or simple placeholder models; new soft models in phase 5 |
| Crop weight | Cut. Every crop item is a stackable id so conveyors, stacks and machines keep working; value comes from rarity and mutations instead |
| Fuel | Cut for farm machines (calm: they run on their own). Only the smelter burns coal |

## The map

Cells are `Build` cells (3 studs). The baseplate is ±256 studs, so everything stays inside ±80 cells.

```text
          z = -40 ... -17      [Plot 1] [Plot 2] [Plot 3]
          z = -12 ...  12      Seed Shop · Gear Shop · Machine Shop · Sell Stand · Quarry  (hub)
          z =  17 ...  40      [Plot 4] [Plot 5] [Plot 6]
```

- **Plots.** Six, 24 x 24 cells each, centred at x = -30, 0, 30. A player who joins takes the first
  free plot; it is released when they leave. A plot has a sign with its owner's name, a fence,
  and a farm of Farmland in front of the open build area. A player can place, plant and pick up only
  inside their own plot (`Shared/Plot`), and machines work only inside the plot they stand on.
- **Hub.** NPC stalls opened with a ProximityPrompt: Seed Shop, Gear Shop, Machine Shop and
  Sell Stand. The quarry's rocks (stone, coal, iron, copper) respawn and are shared.
- Everything else from the old world goes: the ore field, the grove, the meadow, the pens and the
  `Workspace.IslandsMachines` showcase.

## Economy

- **Coins** are the currency, shown on the HUD and in `leaderstats`.
- **XP and level.** XP comes from harvesting (the crop's rarity) and from selling (1 per 10 coins).
  The level unlocks machines in the Machine Shop. Level n needs `100 * n^1.5` XP, rounded.
- **Selling.** At the Sell Stand: sell what's in your hand, or sell every crop and product you
  carry. A Shipping Bin on your plot sells what a belt brings it. Price is the item's `value`
  times its mutation's multiplier.

## Crops

Each crop has a rarity, a seed price, a sell value, a total grow time and a harvest kind.
A **single** crop is uprooted when harvested and must be replanted (a machine replants it from
the seed it keeps). A **multi** crop is a plant that stays: when ripe it shows its fruit, a harvest
takes the fruit, and the fruit grows back after `regrow` seconds, for ever.

| Crop | Rarity | Seed | Value | Grow (s) | Kind | Per harvest |
|---|---|---|---|---|---|---|
| Carrot | Common | 10 | 18 | 60 | single | 1 |
| Wheat | Common | 15 | 12 | 75 | single | 2 |
| Strawberry | Uncommon | 50 | 15 | 90 | multi, regrow 45 | 3 |
| Potato | Uncommon | 60 | 70 | 120 | single | 1 |
| Tomato | Rare | 150 | 35 | 150 | multi, regrow 60 | 2 |
| Corn | Rare | 250 | 160 | 240 | single | 1 |
| Blueberry | Rare | 400 | 30 | 180 | multi, regrow 50 | 4 |
| Pumpkin | Epic | 1,200 | 1,100 | 480 | single | 1 |
| Apple | Epic | 3,000 | 90 | 360 | multi, regrow 90 | 3 |
| Watermelon | Legendary | 6,000 | 3,500 | 600 | single | 1 |
| Grape | Legendary | 10,000 | 260 | 480 | multi, regrow 120 | 4 |
| Starfruit | Mythic | 30,000 | 1,800 | 720 | multi, regrow 150 | 2 |

Stages stay `Sprout`, `Young`, `Mature`, `Ripe`, each a quarter of the grow time. Growth is
timestamp based, so crops keep growing while the player is away and the plot is saved.

### Mutations

A crop rolls a mutation when it ripens (a multi crop rolls again each time its fruit grows back).
A mutated harvest is its own item id, `<Crop>+<Mutation>` (`Carrot+Golden`), so it stacks with its
own kind, rides belts and can be sorted by a Filter Conveyor. Processing machines take any
mutation of their input and output the plain product.

| Mutation | Multiplier | Comes from |
|---|---|---|
| Wet | x2 | 25% while it rains, 10% under a sprinkler |
| Shocked | x10 | 5% during a thunderstorm |
| Golden | x20 | 1% always |
| Rainbow | x50 | 0.1% always |

### Weather

The server rolls an event every 8 to 12 minutes, shown as a banner for everyone:

| Event | Lasts | Effect |
|---|---|---|
| Rain | 2 min | Crops grow 1.5x faster; Wet chance |
| Thunderstorm | 90 s | Rain's effects plus the Shocked chance |
| Golden Hour | 60 s | Golden chance x5 |

## Shops

- **Seed Shop.** It restocks every 5 minutes for the whole server, and each player has their own
  stock of each seed: Common 5 to 15, Uncommon 3 to 8, Rare 1 to 4 (60%), Epic 1 to 2 (25%),
  Legendary 1 (8%), Mythic 1 (2%); otherwise none. The screen shows the countdown.
- **Gear Shop.** Watering Can (a tool: one splash takes 20% off what's left of a crop's stage),
  Pickaxe, Hammer, and decorative blocks (Grass, Dirt, Stone, Wood Planks, Bricks, Glass).
- **Machine Shop.** Every machine, with its level, coin price and, for tier 2, the parts it needs.

## Machines

Machines still run on the factory engine (`Shared/Factory`, `FactoryService`): lanes, routers,
ports, belts out of output faces and the machine panel. The old Islands roster is replaced:

| Machine | Level | Coins | Does |
|---|---|---|---|
| Conveyor, turns, ramps | 1 | 25 | Carry items (tier 2 runs twice as fast) |
| Split, Merger, Filter, Sensor | 3 | 150 | Route items; the filter sorts mutations |
| Shipping Bin | 2 | 300 | Sells what a belt brings it for the owner |
| Storage Chest | 2 | 200 | Holds 12 slots from a belt (the Industrial Chest) |
| Seed Planter | 4 | 800 | Plants seeds from its hopper into empty soil in a 3 x 5 patch in front |
| Sprinkler | 5 | 1,000 | Crops within 3 cells grow 1.25x faster and can turn out Wet |
| Harvester | 6 | 2,000 | Harvests ripe crops within 4 cells onto its output belt; it keeps a seed of each single crop for the planter beside it |
| Mill | 7 | 2,500 | 2 Wheat -> Flour (value 40) |
| Juicer | 8 | 4,000 | 3 Strawberry, Blueberry, Grape, Apple or Tomato -> that Juice (3.5x the fruit) |
| Oven | 10 | 8,000 | Flour + 2 Strawberry, Blueberry or Apple -> that Pie (value 250, 400, 600) |
| Crate Packer | 9 | 6,000 | 10 of any crop -> its Crate (12x the crop) |
| Smelter | 3 | 500 | Ore + Coal -> Bar |
| Workbench | 3 | 400 | Bars -> parts (below) |

Tier 2 Harvester, Sprinkler, Planter and Mill (faster, wider) cost coins plus parts.

## Crafting

The quarry in the hub gives Stone, Coal, Iron Ore and Copper Ore to the Pickaxe. A Smelter makes
Iron and Copper Bars, and a Workbench makes parts:

| Part | From |
|---|---|
| Gear | 2 Iron Bar |
| Copper Wire | 1 Copper Bar |
| Circuit | 2 Copper Wire + 1 Gear |
| Steel Frame | 4 Iron Bar + 1 Stone |

## Persistence

ProfileStore (`ServerPackages.ProfileStore`) keeps, per player: coins, XP, inventory slots, seed
stock and the time of the restock it belongs to, discovered crops, and the plot. The plot is saved
relative to its own origin, so it loads into whichever plot is free: each placed block's item id,
cell, rotation and `Against`, and each crop's type, plant time, mutation and harvest count. Machine
contents are saved as their item counts. A profile autosaves every 2 minutes and on leave.

## What is cut

Oil, petroleum and fuel barrels, the pumpjack and drill and deposits, maple sap and every wood tube,
trees and the lumber chain, animals and their machines (milker, trough, wool vacuum, truffle
barrel), the stone polishing and cutting chain, the steel, bronze and press chain, and the Axe.
Git history keeps all of it.

## Phases

1. **Foundation.** Cut the content above; plots and ownership; coins, XP and levels; ProfileStore
   saving inventory, coins and plots; offline growth.
2. **Garden loop.** The crop table, multi-harvest plants, mutations, the Seed Shop with restocks,
   the Sell Stand, weather, and the HUD for coins, level and weather.
3. **Automation.** The machine roster and Machine Shop, with Planter, Sprinkler, Harvester, the
   processors and the Shipping Bin.
4. **Crafting.** The quarry, Smelter, Workbench, parts and tier 2 machines.
5. **Art.** New soft Blender models for crops, machines, stalls, plots and props, through the
   `IslandsMachines/build` pipeline.
6. **Polish.** Onboarding, sounds, VFX, balance.

Placeholder art until phase 5: the current machine models stand in for the new machines (Seed
Planter = Sapling Automatic Planter, Harvester = Industrial Flower Picker, Shipping Bin =
Industrial Merchant Teleseller, Mill = Industrial Sawmill, Juicer = Food Processor, Oven =
Industrial Oven, Crate Packer = Crate Packer, Smelter = Industrial Smelter, Workbench = Copper
Press), and new crops borrow an existing crop's stage art tinted their colour.
