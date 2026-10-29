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
  Sensor routing remain supported.
- **Items move on the server.** Clients receive changed lane lists through FactorySync and
  interpolate with Lane. A machine starts a job only when its outputs fit.
- **Queued input can bypass an unwanted item.** A machine checks up to twelve queued items,
  including through a Merger. Other routers decide per item.
- **Only Industrial Smelter burns fuel.** It consumes coal while working and smelts iron or
  copper ore. Farm machines and processors run without fuel.
- **Industrial Chest** (stores) accepts belt items into twelve stack slots. Its panel takes
  individual item types or all contents; it still does not accept hand loading.
- **Industrial Merchant Teleseller** (sells) retains its one-item-per-second sale counter.
  Currency payout and priced selling belong to the garden/automation phases.
- **Planter and picker** retain their planting cell, radius and timings. Their source queries
  and completed actions stay inside their own plot.
- **Cut systems are removed.** Tubes, sap, deposits, lumber, animals and walking, petroleum,
  polishing/cutting, alloys and presses are gone. PlotService removes the live showcase;
  Studio source assets are untouched.

## Transitional processors

Until the automation roster arrives, Food Processor uses two Wheat and one Carrot to make
BerryDough; Industrial Oven bakes it into BerryBread. Crate Packer accepts twenty Carrot or
twenty Wheat; its retained tier 2 accepts fifty. Existing product ids/art and timings remain.
Recipes live in Blocks; these replacements keep machines usable after milk/fruit suppliers go.

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

## Machine panel and hand

E / D-pad up (Open on touch) opens an owned machine, Split or Filter within reach. The panel
closes when ownership/reach is lost or the block disappears. Every request is checked again
on the server, including item ids from the panel.

| Target | Controls |
|---|---|
| Machine | Load from inventory, Collect output, Take back unused inputs |
| Industrial Chest | Take one item type, Take all |
| Split | Switch side / straight |
| Filter | Toggle an inventory item, Clear filter |

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
