# Factory and world

How placed blocks carry and process items, and how players mine the shared quarry. Each
module's header owns its rules; this page maps the flow. [plots.md](plots.md) covers ownership
and persistence, and [farming.md](farming.md) covers crops.

## Flow

```text
BuildService.place -> Workspace.Placed -> FactoryService.register
                                           | lanes, router hubs, Machine states
                                           | FactorySync -> FactoryController draws items
                                           | attributes -> BlockInfo / MachinePanel
                                           v
                                       WorldService -> crops on this machine's plot

World/Layout -> WorldService -> Workspace.World (quarry rocks)
GroundService -> WorldService -> Workspace.World (garden ground, farming.md)
Interact -> WorldService -> Pickaxe drops -> InventoryService
Interact -> GroundService -> dig (Pickaxe) or till (Hoe) the owner's ground
Interact -> FactoryService -> owner/reach/payload checks -> machine or router
```

- Shared/Factory/Blocks owns the roster, recipes, fuels, lanes and ports.
- Shared/Factory translates authored geometry into world space; Factory/Lane owns movement
  and spacing. server/libraries/Machine processes items without requiring services.
- Shared/World owns node/crop content. World/Layout contains only the hub quarry.
- Shared/ItemArt locates art; unused place-file templates do not create catalogue items.

## Rules worth knowing

- **Ports connect on faces.** An exit and entry must share a point, face each other and
  belong to the same plot. Hitbox PortDepthBack / PortDepthFront defines short belts between
  machine faces and ports. All conveyor variants and Split, Merger, Filter, Randomizer and
  Sensor routing remain supported. A Filter sends each item it is set for to its left or
  right arm (up to 4 items a side) and everything else straight on. It is set only in its
  panel: a click with an item or an empty hand does nothing to it, so a Hammer picks it up
  like any other block.
- **Items move on the server.** Clients receive changed lane lists through FactorySync and
  interpolate with Lane. A machine starts a job only when its outputs fit.
  Research's replicated plot BeltSpeed scales every item lane and existing conveyor/router riding (research.md).
- **Players ride belts too.** ConveyorRideController (client only, since characters are
  client-owned) moves the local character along the nearest lane of
  any conveyor or router it stands on, at that lane's speed, and turns it to face the belt. Machine belts don't carry players.
- **Queued input can bypass an unwanted item.** A machine checks up to twelve queued items,
  including through a Merger. Other routers decide per item.
- **Only the Smelter and the Rock Drill burn fuel.** Each consumes coal while working (30 s a
  coal); the Smelter smelts iron or copper ore. Farm machines and other processors run
  without fuel. Machine-speed research scales work and coal burn together, preserving fuel per
  bar.
- **Rock Drill** (crafted at a Machine Works bench from 2 Steel Frame, 4 Gear and 4 Copper Wire) is the
  automated source of quarry materials. Its one recipe has no inputs and `rolls` instead of
  outputs: every 6 s of work it adds one item picked by weight (Stone 30, Iron Ore 30, Copper
  Ore 20, Coal 20) to its output, which leaves by its +Z belt like any processor's. It takes
  only coal, by hand or on its -Z belt, so a Filter sending its Coal back round keeps it
  roughly fuel-neutral (5 rolls a coal, a fifth of them coal). One drill makes about 3 Iron
  Ore, 2 Copper Ore and 3 Stone a minute. A rolled recipe never runs in a mutation, and an
  interrupted roll mints nothing. The hover panel lists what it digs.
- **The roster** is the Automation phase's (docs/overhaul.md § Machines): Seed Planter,
  Sprinkler, Harvester, Mill, Juicer, Oven, Crate Packer, Shipping Bin and Storage Chest, plus
  the Smelter, Assembler (id `Workbench`) and Rock Drill for crafting, and the Mk II Seed Planter,
  Sprinkler, Grain Mill and Harvester (bigger patch, faster). Every one is crafted at the
  Crafting Bench (§ Crafting Bench); a Mk II is built on the machine it replaces. Mk II defs come
  from the same constructors as tier 1 in Blocks, so a tier differs only in its numbers.
- **Names.** Players see logical names; ids stay as they were so saves and `Assets.Blocks`
  templates keep matching: `Workbench` is the **Assembler**, `SplitConveyor` the **Belt Switch**,
  `Merger` the **Belt Merger**, `Randomizer` the **Random Splitter**, `FilterConveyor` the
  **Sorter**, `ConveyorSensor` the **Belt Sensor**, `Mill` the **Grain Mill**, `Juicer` the
  **Fruit Press**, `Oven` the **Baking Oven**, turns and ramps are "Conveyor Turn (Left)" or
  "Conveyor Ramp (Up)", the `Tier2` belts are "Fast ..." and the `Tier2` machines "... Mk II".
- **Own art.** The conveyors (belts, turns, ramps, sensor), the Seed Planter, Sprinkler,
  Harvester, Shipping Bin and Storage Chest (one cell wide, two deep) and the processors (one
  wide, three deep) and the routers have templates of their own, and their tier 2s draw them
  too. No placeable block uses Islands art any more.
- **Borrowed art.** An item with no template of its own can name one in its `art`
  (Shared/Inventory/Items); no machine does any more, but products and parts still borrow
  Assets.Items art this way. `ItemArt.blockTemplate` is the one place that resolves it, so
  placement, the ghost, icons and the factory all agree. Placed models are named for the
  item, not the template.
- **Storage Chest** (stores) accepts belt items into twelve stack slots. Its panel takes
  individual item types or all contents; it does not accept hand loading.
- **Shipping Bin** (sells) takes any item with a value from a belt and sells one a second,
  paying its owner the item's value and Sell Stand XP (1 per 10 coins, remainders carried per
  player). Its owner sees one "Shipping Bin +N coins" toast every 2 s at most. It publishes
  `Sold` and `Earned`.
  Sale research multiplies item value with fractional coins carried per player; XP uses paid coins.
- **Work areas.** A planter, harvester or sprinkler works only on cells at its own level (its
  bottom cell row), never above or below; `Factory.area` gives the rectangle and the server and
  the placing ghost share its base area. While placing one, BuildController lays a soft yellow sheet over
  that rectangle.
- **Seed Planter** plants the first loaded seed that fits into the first free cell of a patch
  3 wide and 5 deep past its forks (`plantArea` in Blocks), every 2 s.
  Harvester-speed research divides both Planter and Harvester intervals.
- **Harvester** harvests every ripe crop in a patch 5 wide and 3 deep behind it (the side away
  from its output belt, centred on its belt line; `produce.area` in Blocks), one every 3 s,
  onto its output belt. The tier 2 patch is 7 wide and 5 deep.
  A single crop restarts from a sprout, so it replants itself; a multi crop regrows its fruit.
  Each harvest gives the owner harvest XP, as a hand harvest does.
  Yield research rolls once before the output-room check and uses that same count for the harvest.
- **Sprinkler** has no ports. Crops within 3 cells across on its plot grow
  1.25x as fast and gain +10% Wet chance. The best sprinkler over a crop counts; several don't
  stack. FactoryService hands WorldService the speed and chance providers; SprinklerController
  draws a soft spray.
  Radius research extends its reach; growth and mutation research multiply its crop effects (research.md).
- Source queries and completed actions of every machine stay inside its own plot.
- **Cut systems are removed.** Tubes, sap, deposits, lumber, animals and walking, petroleum,
  polishing/cutting, alloys and presses are gone. PlotService removes the live showcase;
  Studio source assets are untouched.

## Processors

`Shared/Factory/Products` owns every processed product: its inputs, machine, batch time,
value and borrowed art. Items makes the product items from it and Blocks the recipes, so a
product is one entry. Mill: 2 Wheat -> Flour. Juicer: 3 of a fruit -> its Juice. Oven:
Flour + 2 of a fruit -> its Pie. Crate Packer: 10 of any crop -> its Crate. Workbench: the
crafting parts (Gear, Copper Wire, Circuit, Steel Frame) from bars, which have no value.
Machine-speed research divides batch times for processors, Workbench and Smelter.
Mutated inputs are never grouped with plain ones or each other. Each variant has its own
input room; a batch takes every input in one set of mutations (plain first, then rising
value, `Mutations.KEYS`) and makes its product in that set, `<Product>+<Mutations>` worth the
product's value times the set's multiplier (Items makes every variant of every valued product). A recipe with an input that has
no variant (bars, parts) only runs plain, so a Golden Pie needs Golden Flour as well as Golden
fruit. Rare variants wait inside until a whole batch is in, without blocking plain ones. An
active job refunds its exact variants when saved or picked up. The Harvester sources the current
mutated item and checks the full yield fits before reaping. Its single crops restart; multi
plants regrow (see farming.md).

A Filter's picks match an item by its exact id, or else by its base crop or product, so a
pick of a plain crop covers every mutation of it. A pick that comes in mutations
(`Inventory.hasMutations`) has its own mutation checklist (Plain, Wet, Shocked, Golden,
Rainbow): with any ticked, the pick takes items carrying any of those, so Carrot with Golden
ticked sends Golden and Wet Golden Carrots to its side. A pick with none ticked takes every variant. Ticks are saved as
"Carrot:Golden" and go when the pick goes back to straight on.

## Loose items (DropService)

- The drop key tosses one held item, or places it above an owned belt within reach. A resource
  clicked onto an owned conveyor/router does the same.
- Drops are server-simulated physics in Workspace.Drops. DropService owns pickup grace and
  lifetime. Placement and aim queries ignore them.
- Drops retain their player or machine owner's user id even after leaving the plot. Other
  players cannot pick them up and other plots cannot absorb them. Pickup inside a plot also
  requires ownership of that plot.
- Walking over an owned belt picks up items underfoot, subject to the dropper's pickup grace.
- Unconnected outputs throw items off only when the cell ahead is clear. Loose drops are
  transient, cleared on the owner's departure, and not saved as profile contents.
- **Drops stack.** Once a drop has flown for 0.6 s, drops of the same item and owner whose
  centres are within 3 studs merge into one: a single model and physics body whose `Count`
  attribute holds the stack, so a flood of drops costs one part per pile. The bigger stack
  survives where it lies and keeps the later despawn time; it draws up to 1.6x bigger at 100
  items (`ItemArt.stackScale`). Walking into a stack takes as much as the inventory has room
  for. Merging is a spatial-hash pass every 0.4 s, linear in the number of drops.
- **Drops join belts as stacks.** A drop lying on an owned belt, or a settled one within 4
  studs across (and 3 up or down) of any owned belt, goes onto it whole as one belt stack
  (`Lane.Item.count`): into a stack of the same item within one spacing of where it lands, or
  as a new stack there or a spacing either side (FactoryService `catch`). One lying on a
  machine's beltless input goes in, as much as fits. Drops a belt or machine threw off an
  open end are never pulled from beside a belt, since they would ride round and be thrown off
  again; a stack merged with one isn't either.
- **Belt stacks travel as one item**, taking one item's room. A machine, the Shipping Bin, a
  chest, a hand or walking over it takes as many as fit and leaves the rest on the belt; a
  stack reaching an open end is thrown off as one stacked drop. Saves keep belt counts, and a
  lane restores one stack per item.
- **Pickup animation.** A drop that is picked up, merged or taken onto a belt stays 0.6 s
  on the server, anchored and out of play, and `DropCollected` has every client within 150
  studs draw it. DropController hides the real one and flies a local copy into the player
  (or the stack it joined, or its spot on the belt) on an ease-in arc, shrinking, spinning
  and fading over 0.35 s. A partial pickup flies a smaller copy and leaves the stack. Reduced
  motion fades it where it lies.
- **Stack badge.** Every stack of more than one, loose or on a belt, shows its count over
  it ("x24") through `client/libraries/StackLabel`, which pops the badge when the count grows
  (not with reduced motion). The badge is `Assets.UI.Stack.Count` when authored (inventory.md).

## Machine panel and hand

Each of the player's blocks with controls (`Factory.hasControls`: a machine with something to
load, collect or take out, a Split or a Filter; not a Sprinkler) gets a local ProximityPrompt
from `UIController/BlockPrompts`, hung at the centre of its box. Walking up to it shows the
custom card PromptController draws on the block and highlights the block; the interact key
(`Controls.INTERACT`: F, D-pad up) or a tap on the card opens the panel, and the same key closes
it (prompts hide while a panel is open). The mouse aim no longer opens anything, and the hover
panel doesn't describe these blocks: the card names them and their status. The panel
closes when ownership/reach is lost or the block disappears. Every request is checked again
on the server, including item ids from the panel.

| Target | Controls |
|---|---|
| Machine | Load from inventory, Collect output, Take back unused inputs |
| Storage Chest | Take one item type, Take all |
| Split | Switch side / straight |
| Filter | Click an inventory item to send it left, again for right, again straight on (its slot shows L or R); the status half shows each side's items as slots under its row, and clicking one moves it on; an item with mutations has an arrow under it that opens its coloured mutation checklist; Clear filter (also unticks every mutation) |

Hammer picks up owned blocks; Pickaxe breaks matching cubes, mines quarry rocks and digs the
owner's ground; Hoe tills the owner's grass and dirt into Farmland. An empty
hand takes belt items or switches routers. Ripe crops are harvested at their prompt, and only
the Hammer digs a crop up (farming.md). Machines are worked through
their panel. Picking up a machine refunds active recipe ingredients with its contents; partial
processing progress is discarded. Inventory overflow on block pickup retains the existing
behavior: it is lost, so empty a full machine before picking it up.
Mining/chopping research boosts the acting player's named node drop before the inventory-room check.

## The forest

Shared like the quarry: ForestOak (3 Wood), ForestPine (4) and ForestBirch (2) are World nodes,
chopped by anyone with the Axe (Gear Shop, 60 coins), plus their Sharp Axe research
(`World.Node.boost`, research.md). `World/Layout` stands them through the forest ring
(plots.md § The map round the gardens). A chopped tree leaves its `ForestStump` art as scenery
(no collisions or queries, so it never blocks the respawn) and grows back after 90 s. Like
crops, a tree comes in looks (`ForestOakVariant2` ...), picked per cell; its model carries the
look as `Look`. Chopping fires `GardenEvents.Chopped`, and FxService has every client nearby
draw that look tipping over away from the chopper and settling into the ground, with wood
chips, leaves and the Chop and TreeFall sounds. Wood has no sell value, so Sell All keeps it.

## Crafting Bench

A block that crafts by hand, not from belts: the Assembler stays the belt-fed parts machine.
Every new garden's starter kit has one, and DataService gives one to any save that has none,
placed or carried; more are crafted from 8 Wood Planks and 4 Stone. Crafting is the only way to
get a machine, conveyor or router. `Shared/Crafting` owns the bench's tiers and recipes, each an
output and count from inputs, needing a bench tier and sometimes a research project.

**Tiers.** The player's bench tier is saved with the garden (`benchTier`), applies to every bench
they own and replicates as the player's `BenchTier` attribute. Upgrading is a recipe of its own,
`BenchTier<N>` in the window's Upgrades category (the next one is listed first): it needs the
level its tier names, spends its inputs and raises the tier by one, with no item made.

| Tier | Name | Upgrade (level, materials) | Adds |
|---|---|---|---|
| 1 | Crafting Bench | start | Wood Planks, Timber Frame, Crafting Bench, Smelter, Shipping Bin, Storage Chest (Carpentry), belts and turns, ramps (Conveyor Ramps), Gear by hand (Hand-Cut Gears) |
| 2 | Workshop | 3: 40 Wood Planks, 30 Stone, 8 Iron Bar | Assembler, Seed Planter, Sprinkler, Grain Mill, Fruit Press, Belt Switch, Belt Merger, Random Splitter, Sorter, Belt Sensor |
| 3 | Machine Works | 6: 8 Timber Frame, 20 Iron Bar, 12 Copper Bar, 10 Gear | Harvester, Baking Oven, Crate Packer (Crate Making), Rock Drill, fast belts, turns and ramps |
| 4 | Fabricator | 9: 8 Steel Frame, 6 Circuit, 12 Gear, 10 Copper Wire | Seed Planter Mk II (Planter Mk II Plans), Sprinkler Mk II (Sprinkler Mk II Plans), Grain Mill Mk II, Harvester Mk II (Harvester Mk II Plans) |

Recipes follow what a machine is made of: wood and iron for belts and frames, stone for the
Smelter and the Grain Mill's millstones, glass for the Fruit Press and the Belt Sensor, bricks
for the Baking Oven, copper for the Sprinkler's pipes, gears, wire and circuits from the Assembler
for anything that moves or thinks, and steel frames for the heavy machines. `Shared/Crafting`
holds every number. Its owner opens the Crafting window from its Craft prompt (BlockPrompts: the interact key or a
tap on the card, within reach; `UIController/CraftingScreen`), and it closes on the same key or
on walking away. Its `Header.Title` names the bench's tier. The window is laid out like a
catalogue: `Body.Categories` (Craftable, All, Upgrades and one per output kind, from `Assets.UI.Crafting.Category`), `Body.Main` with a `Search`
box and a `Grid` of `Assets.UI.Crafting.Card`s (the output, its count, a gold `Ready` tick when
the inventory can make it now and a `Lock` while research or the bench tier hasn't unlocked it;
the next upgrade first, then craftable, locked last; upgrades already made are hidden), and `Body.Details` for the picked recipe: the output turning in `Preview`, one
`Assets.UI.Crafting.Ingredient` per input showing have / need in green or red, a `Status` line
naming what's missing, the `Amount` stepper (1 to `Crafting.MAX_TIMES` crafts, Max for as many as
the inventory allows) and `Craft`. Hovering a card shows `HUD.Crafting.Tooltip` (name,
description, each input's have / need) beside the pointer. `CraftingScreen.luau`'s header lists
every node. `Remotes.Craft(recipeId, times)`
goes to `CraftingService`, which rechecks DataReady, a cooldown, that one of the player's own
benches is in reach, the research (`Bonuses.has`), the bench tier, the level an upgrade needs and
every input, then tries the trade on a
copy of the inventory (inputs out, output in, so the room the inputs free counts) and applies
it whole without yielding, with a toast and `GardenEvents.Crafted` (a puff of wood shavings
and the Craft sound). The window and its templates are authored in the place file, by `tools/hud/progress_hud.luau`.

Played through in Studio: opening it with F at the bench, 1 Wood into 4 Wood Planks, a Timber
Frame, a x5 craft, and a locked recipe refused ("Research Crate Making first").

## Place-file art and adding content

Assets.Blocks holds block/machine hitboxes and art, Assets.Items resource art, and Assets.World
quarry, Farmland and crop stages. HUD.BlockInfo, HUD.MachinePanel and their row/slot templates
remain authored in Studio. CopperRock uses a copper-coloured cell when no template exists.

A machine needs an Inventory/Items entry, a Factory/Blocks definition and a matching block
template. A recipe uses known item ids. Quarry nodes need a World definition and Layout spot.
See farming.md for crops. Power remains sensor pulses plus the Split's manual switch.
