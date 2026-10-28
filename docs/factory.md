# Factory and world

How placed blocks do things: conveyors carry items, machines turn them into other items,
producers draw resources from the world, and players feed and empty it all by hand. Each
module's header owns its own rules; this page is the map between them.

## Flow

```text
WorldService (server)  -- nodes and animals in Workspace.World (Shared/World, World/Layout)
   ^   ^   mined / picked by players (Interact)         animals: walks published as attributes
   |   |                                                         -> WorldController animates
   |   +-- "what is near / below / in front of this machine?", chop, plant, feed
   |
FactoryService (server)  -- every block in Workspace.Placed with a Shared/Factory/Blocks entry
   |  lanes (Shared/Factory/Lane), router hubs, machines (server/libraries/Machine), wood tubes
   |  status attributes on each block model ----------------> UIController/BlockInfo (hover panel)
   |  FactorySync: a lane's items whenever one joins or leaves --> FactoryController (draws items)
   ^
   +-- Interact (feed, take, set a filter, switch a split) <-- BuildController (what the hand does)
```

- `Shared/Factory/Blocks` is the content: each block's lanes, route, ports, recipes, fuel,
  and what a producer needs from the world. `Shared/Factory` turns that into world space.
- `Shared/World` is the node and animal content; `Shared/World/Layout` places them.
- `Shared/ItemArt` owns where every item's art lives (blocks, tools, resources).

## Rules worth knowing

- **Ports.** Two blocks connect when one's exit and the other's entry share a point and face
  each other. Lanes and machine ports sit on hitbox faces at belt height, on the conveyor axis,
  so any conveyor placed against a machine's port connects. A machine with conveyor art on one
  end still has its other port on the opposite face.
- **Items move only on the server.** Clients get a lane's item list when an item joins or
  leaves it and slide items with the same Lane rule in between.
- **Machines never lose items.** A job starts only when its output fits; a full machine stops,
  its input belt backs up, and so does everything behind it.
- **Fuel burns only while working.** Coal and petrified petroleum (or petroleum for planters,
  pickers and shakers) arrive by belt or by hand.
- **Producers check the world when a job starts and again when it ends**, so a chopped tree or
  a wandering animal stops production cleanly.

## Loose items (DropService)

- **Q / Backspace / D-pad down** drops one of the held item: onto the belt aimed at (any
  conveyor or router, or a machine's input end), or tossed in front of the player. Clicking a
  conveyor or router while holding a resource does the same; clicking a machine feeds it.
- Drops are real physics in `Workspace.Drops`. Walking into one picks it up (after a 1 s
  grace), and they despawn after 5 minutes.
- A drop over any block's belt (in the belt's cell, at belt height or resting on art above
  it) joins that lane there if there is room. One over a machine's input end goes in if the
  machine takes it. `FactoryService` registers both rules, and where an aimed drop appears,
  with `DropService.setBelts`.
- An item reaching a lane end, or a machine's output face, that connects to nothing is thrown
  off as a drop when the cell in front holds nothing but characters and other drops;
  anything else standing there blocks it.
- Drops collide, so `CanQuery` can't hide them: placement (`Build.isFree`), the aim
  (`Aim.cast`) and open-end checks skip `Workspace.Drops` by hand (`Build.isLoose`).

## What the hand does

| Held | Aimed at | Press does |
|---|---|---|
| Anything a machine takes (`Factory.takesByHand`) | that machine | Puts in as many as it has room for |
| Any item | a Filter Conveyor | Toggles sending that item left |
| Placeable | anything else | Places it (ghost) |
| Hammer | your placed block | Picks it up, with whatever it held |
| Pickaxe / Axe | your placed cube it breaks (`breaksWith`) | Breaks it back into your inventory |
| Pickaxe / Axe | a world node it fits | Mines or chops it |
| Nothing | a machine | Collects its output |
| Nothing | a conveyor | Takes the items on it |
| Nothing | a Split Conveyor / Filter | Switches it / clears the filter |
| Nothing | a berry bush or flower patch | Picks one |

## What lives only in the place file

| Instance | What it is |
|---|---|
| `ReplicatedStorage.Assets.Items` | One Model per resource item (from `IslandsMachines/build/assets.py`) |
| `ReplicatedStorage.Assets.World` | One Model per node type and animal, each with a hitbox `PrimaryPart` |
| `StarterGui.HUD.BlockInfo` | The hover panel: brackets around a `Content` frame (Title, Status, Rows, Hint) |
| `ReplicatedStorage.Assets.UI.BlockInfo.Row` | One Key/Value row of that panel |

The `Interact` and `FactorySync` RemoteEvents are declared in `default.project.json`.

## Adding things

- **A recipe:** a `recipe(...)` line in the machine's `Shared/Factory/Blocks` entry. New
  ingredients and products are items in `Shared/Inventory/Items` (kind `Resource`) with a model
  in `Assets.Items`.
- **A machine:** its block art and hitbox as for any block (docs/inventory.md), an item in
  `Items`, and an entry in `Blocks`.
- **A node type or animal:** an entry in `Shared/World`, art in `Assets.World`, and spots or a
  pen in `Shared/World/Layout`.

## Not built yet

- Persistence: machines, belts and the world reset with the server.
- The Teleseller counts what it sells (`Sold`) but there is no currency to pay out.
- Wood tubes carry sap and syrup only; oil and petroleum ride belts as items (no pipes).
- Power is only sensors pulsing the split conveyors they touch (and a manual switch).
- Conveyors don't carry players.
