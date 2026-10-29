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
   +-- Interact (panel: load, collect, take back; hand: take belt items, filter, switch)
         <-- UIController/MachinePanel, BuildController (what the hand does)
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
- **Items go into a machine at its port.** A machine with belt art on its input face rides
  items along that belt (a lane `Factory.lanes` adds, as long as its hitbox's `PortDepth*`)
  and takes the front one where the belt meets the port. A face with no belt art takes items
  right at the face.
- **Items leave a machine at its port too.** A machine with belt art on its output face puts
  each finished item on that belt (a lane `Factory.lanes` adds, as long as its hitbox's
  `PortDepth*`), and it rides out to the face like any conveyor's: on to a connected entry,
  thrown off when nothing stands in front, or waiting there while something does. Every machine
  that makes items has that belt; one whose belt runs clear through its art (berry basket,
  truffle barrel) gives its depth as `belt` in `Blocks`. Only the Drill, whose port collars sit
  at its faces, puts output straight off its face.
- **Wood tubes join into networks.** A tube connects to a tube whose opening faces it, to any
  face of a sap machine (`tubes` in `Blocks`), and to a maple tree. Each tube is empty when
  placed and shows its fluid once sap or syrup has moved through its network; a network keeps
  it while a tree or a boiler still feeds it, so a tube added to a running line fills at once.
  The Sap Boiler and Syrup Bottler draw their tube ends at tube height on a cell's centre line,
  flush with the hitbox face, so a tube placed there lines up.
- **There is one Wood Tube item, and it shapes itself** (`auto` in `Blocks`). The client sends the
  axis of the surface it was placed on, and BuildService stores it as the model's `Against`.
  FactoryService joins the new tube to the block on that side, as long as that block can take it:
  - an auto tube with fewer than two links;
  - the merger's opening;
  - a sap machine;
  - a maple tree.

  It then also joins any neighbouring tube whose spare end already points at it, until it has two
  links.
  - Placed on a lone tube, both tubes become verticals.
  - Placed on a tube that is already joined beside, the lower one becomes an elbow up.
  - Placed beside the top of a column, the top becomes an elbow down.
  - Placed beside a straight end, that end turns into a corner.

  A tube's ends are its links. With one link, the other end is straight across from it; with none,
  both ends run along the way it was placed facing. The ends pick the art: `WoodTube`,
  `WoodTubeCorner`, `WoodTubeAscend` (elbow up), `WoodTubeDescend` (elbow down) or
  `WoodTubeVertical`. FactoryService swaps the art parts in under the placed model's Hitbox,
  turned to fit, and reshapes the neighbours a tube was linked to when it is picked up. Those four
  art templates are not items. The Wood Tube Merger stays its own item with fixed openings.
- **The Industrial Chest collects what a belt brings it** (`stores` in `Blocks`). It is the Islands
  chest with a conveyor attachment. It takes any item at its input face into 12 slots, each up to
  the item's stack size, and backs the belt up when the slots are full.
  - It publishes `Slots` alongside the usual `Contents`.
  - Its panel lists what it holds in the grid, one cell per slot. A cell's `TakeOut` takes that item
    out, and **Take all** (`TakeBack`) takes everything.
  - It never takes items by hand, as in Islands since December 2021.
- **Fuel burns only while working.** Coal and petrified petroleum (or petroleum for planters,
  pickers and shakers) arrive by belt or by hand.
- **Producers check the world when a job starts and again when it ends**, so a chopped tree or
  a wandering animal stops production cleanly.

## Loose items (DropService)

- **Q / Backspace / D-pad down** drops one of the held item: onto the belt aimed at (any
  conveyor or router, or a machine's input end), or tossed in front of the player. Clicking a
  conveyor or router while holding a resource does the same; clicking a machine does nothing.
- Drops are real physics in `Workspace.Drops`. Walking into one picks it up (after a 1 s
  grace), and they despawn after 5 minutes.
- Walking over a belt picks up the items under your feet (feet on the belt, not the floor
  beside it). An item you dropped onto a belt can't be walked back up by you for 1.5 s;
  anyone else can take it at once.
- A drop over any block's belt (in the belt's cell, at belt height or resting on art above
  it) joins that lane there if there is room. One over a machine's input end goes in if the
  machine takes it. `FactoryService` registers both rules, and where an aimed drop appears,
  with `DropService.setBelts`.
- An item reaching a lane end, or a machine's output face, that connects to nothing is thrown
  off as a drop when the cell in front holds nothing but characters and other drops;
  anything else standing there blocks it.
- Drops collide, so `CanQuery` can't hide them: placement (`Build.isFree`), the aim
  (`Aim.cast`) and open-end checks skip `Workspace.Drops` by hand (`Build.isLoose`).

## Machine panel

The panel is the only way to work a machine: the hand never feeds one or empties it.
**E / D-pad up** (an **Open** button on touch) while aiming at a machine, split conveyor or
filter conveyor within reach opens its panel (`UIController/MachinePanel`, which takes the
backpack's place on screen). It shows the same status as the hover panel (both word it with
`libraries/BlockText`) plus a progress bar, and:

| Block | Buttons | Item grid |
|---|---|---|
| Machine | Collect (all output), Take back (loaded items not used yet) | What it takes from anywhere in your inventory; click one to put in as many as fit |
| Split Conveyor | Send to the side / straight on | — |
| Filter Conveyor | Clear filter | Every item you carry; click to send it left, or not (up to 4) |

Each press is an `Interact` request (`Load`, `Collect`, `TakeBack`, `Switch`, `Filter`,
`ClearFilter`) the server checks for reach. The panel closes on E again, its X, gamepad B,
walking out of reach, or the block being picked up.

## What the hand does

Machines aren't in this table: a press does nothing to one (use its panel). The hover panel
and the panel's interact key only see a block's or node's art (`Aim.castArt`), not the empty
cells of its hitbox; the hand still aims at hitboxes, so placing snaps to their faces.

| Held | Aimed at | Press does |
|---|---|---|
| Any item | a Filter Conveyor | Toggles sending that item left |
| Placeable | anything else | Places it (ghost) |
| Hammer | your placed block | Picks it up, with whatever it held |
| Pickaxe / Axe | your placed cube it breaks (`breaksWith`) | Breaks it back into your inventory |
| Pickaxe / Axe | a world node it fits | Mines or chops it |
| Nothing | a conveyor | Takes the items on it |
| Nothing | a Split Conveyor / Filter | Switches it / clears the filter |
| Nothing | a berry bush or flower patch | Picks one |

## What lives only in the place file

| Instance | What it is |
|---|---|
| `ReplicatedStorage.Assets.Items` | One Model per resource item (from `IslandsMachines/build/assets.py`) |
| `ReplicatedStorage.Assets.World` | One Model per node type and animal, each with a hitbox `PrimaryPart` |
| `StarterGui.HUD.BlockInfo` | The hover panel: brackets around a `Content` frame (Title, Status, Rows, Hint) |
| `StarterGui.HUD.MachinePanel` | The machine panel: the backpack's shell (Header with Title and Close), `Body.Info` (Content with Status, Progress.Fill and Rows; Actions with Collect, TakeBack, Switch, ClearFilter) and `Body.Load` (Heading, Hint, Grid, Empty). Its cells clone `Assets.UI.Inventory.Slot`, its rows `Assets.UI.BlockInfo.Row` |
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
