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
Interact -> WorldService -> Pickaxe drops -> InventoryService
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
  right arm (up to 4 items a side) and everything else straight on; holding an item and
  clicking the filter moves that item through the same left, right, straight cycle.
- **Items move on the server.** Clients receive changed lane lists through FactorySync and
  interpolate with Lane. A machine starts a job only when its outputs fit.
- **Queued input can bypass an unwanted item.** A machine checks up to twelve queued items,
  including through a Merger. Other routers decide per item.
- **Only the Smelter burns fuel.** It consumes coal while working and smelts iron or
  copper ore. Farm machines and processors run without fuel.
- **The roster** is the Automation phase's (docs/overhaul.md § Machines): Seed Planter,
  Sprinkler, Harvester, Mill, Juicer, Oven, Crate Packer, Shipping Bin and Storage Chest, plus
  the Smelter and Workbench for crafting, and tier 2 Seed Planter, Sprinkler, Mill and
  Harvester (bigger reach, faster). All are bought in the Machine Shop (economy.md); tier 2
  ones also cost Workbench parts. Tier 2 defs come from the same constructors as tier 1 in
  Blocks, so a tier differs only in its numbers.
- **Own art.** The conveyors (belts, turns, ramps, sensor), the Seed Planter, Sprinkler,
  Harvester, Shipping Bin and Storage Chest (one cell wide, two deep) and the processors (one
  wide, three deep) and the routers have templates of their own, and their tier 2s draw them
  too. No placeable block uses Islands art any more.
- **Borrowed art.** A machine with no template of its own names one in its item's `art`
  (Shared/Inventory/Items): the Harvester draws the Industrial Flower Picker, the Shipping Bin
  the Teleseller, and so on. `ItemArt.blockTemplate` is the one place that resolves it, so
  placement, the ghost, icons and the factory all agree, and the art phase changes one field.
  Placed models are named for the item, not the template.
- **Storage Chest** (stores) accepts belt items into twelve stack slots. Its panel takes
  individual item types or all contents; it does not accept hand loading.
- **Shipping Bin** (sells) takes any item with a value from a belt and sells one a second,
  paying its owner the item's value and Sell Stand XP (1 per 10 coins, remainders carried per
  player). Its owner sees one "Shipping Bin +N coins" toast every 2 s at most. It publishes
  `Sold` and `Earned`.
- **Seed Planter** plants the first loaded seed that fits into the first free cell of a patch
  3 wide and 5 deep past its forks (`plantArea` in Blocks), every 2 s. Each cell is tried at the
  planter's level and one cell up, so a planter standing on the grass beside a raised bed plants
  onto the bed.
- **Harvester** harvests every ripe crop within 4 cells, one every 3 s, onto its output belt.
  A single crop restarts from a sprout, so it replants itself; a multi crop regrows its fruit.
  Each harvest gives the owner harvest XP, as a hand harvest does.
- **Sprinkler** has no ports. Crops within 3 cells across (and one up or down) on its plot grow
  1.25x as fast and gain +10% Wet chance. The best sprinkler over a crop counts; several don't
  stack. FactoryService hands WorldService the speed and chance providers; SprinklerController
  draws a soft spray.
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
Mutated inputs are never grouped with plain ones or each other. Each variant has its own
input room; a batch takes every input in one mutation (plain first, then rising rarity) and
makes its product in that mutation, `<Product>+<Mutation>` worth the product's value times the
multiplier (Items makes a variant of every valued product). A recipe with an input that has
no variant (bars, parts) only runs plain, so a Golden Pie needs Golden Flour as well as Golden
fruit. Rare variants wait inside until a whole batch is in, without blocking plain ones. An
active job refunds its exact variants when saved or picked up. The picker sources the current
mutated item and checks the full yield fits before reaping. Its single crops restart; multi
plants regrow (see farming.md).

A Filter's picks match an item by its exact id or its base crop or product, so a pick covers
every mutation of it. Each side also has a mutation checklist (Plain, Wet, Shocked, Golden,
Rainbow): with any ticked, the side takes only those. A side with picks and ticks takes the
picked items in the ticked mutations; ticks alone take every item in them. When both sides
take an item, the side that picked it wins, then the side with ticks, then left.

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

E / D-pad up (Open on touch) opens an owned machine, Split or Filter within reach. The panel
closes when ownership/reach is lost or the block disappears. Every request is checked again
on the server, including item ids from the panel.

| Target | Controls |
|---|---|
| Machine | Load from inventory, Collect output, Take back unused inputs |
| Storage Chest | Take one item type, Take all |
| Split | Switch side / straight |
| Filter | Click an inventory item to send it left, again for right, again straight on (its slot shows L or R); the status half shows each side's items as slots under its row, and clicking one moves it on, then that side's mutation checklist; Clear filter (also unticks every mutation) |

Hammer picks up owned blocks; Pickaxe breaks matching cubes or mines quarry rocks. An empty
hand takes belt items, switches routers or harvests owned crops. Machines are worked through
their panel. Picking up a machine refunds active recipe ingredients with its contents; partial
processing progress is discarded. Inventory overflow on block pickup retains the existing
behavior: it is lost, so empty a full machine before picking it up.

## Place-file art and adding content

Assets.Blocks holds block/machine hitboxes and art, Assets.Items resource art, and Assets.World
quarry, Farmland and crop stages. HUD.BlockInfo, HUD.MachinePanel and their row/slot templates
remain authored in Studio. CopperRock uses a copper-coloured cell when no template exists.

A machine needs an Inventory/Items entry, a Factory/Blocks definition and a matching block
template. A recipe uses known item ids. Quarry nodes need a World definition and Layout spot.
See farming.md for crops. Power remains sensor pulses plus the Split's manual switch;
conveyors do not carry players.
