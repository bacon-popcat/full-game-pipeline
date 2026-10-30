# Inventory and building

How items get from a player's inventory into their hand and onto the build grid. Each
module's header owns its own rules; this page is the map between them.

## Flow

```text
InventoryService (server)  --InventorySync-->  InventoryClient (client)  -->  InventoryScreen
        ^  owns slots + hand                     predicts own moves            hotbar + backpack
        |
        +--InventoryMove / InventorySelect--  InventoryScreen
        |
        +--Tool with ItemId attribute-->  character  -->  BuildController (ghost, outline)
                                                                |
BuildService (server)  <--PlaceBlock / PickUpBlock-------------+
        |  calls InventoryService.consumeHeld / give
        v
  Workspace.Placed
```

- `Shared/Inventory` holds the slot shape and the move/add/take rules both sides run.
- `Shared/Build` holds the 3-stud grid, footprints, reach, ownership and overlap checks both sides run.
- [plots.md](plots.md) maps profile loading, plot assignment, economy and saving.
- `Shared/Remotes` names every RemoteEvent and documents its payload.
- `client/libraries/Controls` owns every key binding and the hint text that names them.

The server never takes an item id from a client: placing uses whatever is in the
player's held hotbar slot, and picking up reads the placed model's own attributes.

## What lives only in the place file

These are authored in Studio and are **not** in git (see `conventions.md`, UI):

| Instance | What it is |
|---|---|
| `StarterGui.HUD` | `Hotbar`, `Backpack` window, `DragGhost`, `ItemName`, `SideButtons.Backpack` |
| `ReplicatedStorage.Assets.UI.Inventory` | `Slot` cell template, `SelectionImage` |
| `ReplicatedStorage.Assets.UI.Stack` | `Count`, a BillboardGui with a TextLabel `Label` inside, cloned over every stack of more than one item, loose or on a belt, to show "x24"; until it is authored StackLabel draws a plain dark pill, without a warning |
| `ReplicatedStorage.Assets.Blocks` | One Model per placeable item, named by item id, each with a hitbox `PrimaryPart` (below): the retained building cubes, machines and seed ghosts; unused templates do not create items |
| Cube studs | Each building cube (Grass, Dirt, Stone, Bricks...) is Plastic with `TopSurface = Studs` (Roblox's built-in surface, which only draws on Plastic), Grow a Garden style; `IslandsMachines/build/studio_studs.luau` sets it, and nothing else is studded |
| `ReplicatedStorage.Assets.Tools` | `Hammer`, `Pickaxe` Tools; the unused Axe template is harmless |

The RemoteEvents are the exception: they are declared in `default.project.json`.

## Block templates

A block template's `PrimaryPart` is its hitbox, and the hitbox's pivot is the template's only
pivot. The hitbox is a box of whole 3-stud cells: its size is the footprint, and placing the
block fills the placement's cells with it. A cube is its own hitbox. A machine has an
invisible, queryable, non-colliding part named `Hitbox` around its art. The art may poke out
of the hitbox by up to 0.15 studs, which `Build`'s overlap margin allows for. The pivot sits
on the floor at a convenient cell centre (the conveyor's, or under a machine column); placement reads it relative to the hitbox, so where it sits never changes placement.
Machine parts collide with their exact shape.

A placement must fit entirely inside the loaded player's own plot; the ghost uses the same
check as the server and is red elsewhere. A placement is blocked by anything but a character (or a loose drop) inside its cells, and
by a character only where the block's own colliding parts would clip them
(`Build.clipsCharacter`, which tests a shrunken copy of the art). A player can stand in a
machine's empty corner, or beside a conveyor's belt, and still place it.

A machine's hitbox also carries `PortDepthBack` and `PortDepthFront`: how far the belt at
its -Z and +Z face runs before it meets the machine's port. `Shared/Factory` turns the input
face's depth into the belt items ride in on (docs/factory.md).

For conveyors to connect, a machine's conveyor runs down the middle of a column of cells,
and a conveyor end that meets a neighbour sits on a hitbox face. The Islands pipeline builds
the hitboxes and the copies in `Assets.Blocks` with `IslandsMachines/build/studio_blocks.luau`.
That folder is outside git, and its README covers the rules.

## Adding an item

1. Add it to `src/shared/Inventory/Items.luau`. Crops are the exception: `World.CROPS`
   generates their seeds, produce and mutation variants, including sell values.
2. Put its art in `Assets.Blocks` (blocks and machines) or `Assets.Tools` (a Tool), named
   exactly the item id. A block also needs its hitbox `PrimaryPart` (above). The footprint
   comes from the hitbox, so no size is entered.

What placed blocks do once they are down -- and what the Pickaxe and an empty hand do --
is docs/factory.md.

## Loading and saving

DataService supplies InventoryService's slots after locking the profile and restoring the plot.
New profiles receive the starter kit defined in DataService; the old full test kit is gone.
Inventory mutations wait for DataReady. InventoryService snapshots slots and releases its held
Tool only after the final save snapshot. The selected slot resets to one on load.

BuildService.place is shared by normal placement and profile restoration. It synchronously
registers factories, while seeds go directly to WorldService.plant. Saved blocks retain item id,
plot-relative cell, rotation, Against and factory contents. See [plots.md](plots.md).

The garden HUD contract is in [economy.md](economy.md#authored-hud-contract-place-file-only).
Shared/ItemArt owns tinted seed/produce fallbacks and mutation icons; Build delegates its
template lookup there. Shop and Sell share window exclusivity with Backpack/MachinePanel
through libraries/Screens. Sell All removes matching stacks and syncs once through
InventoryService.takeWhere; currency pricing stays in GardenService.
