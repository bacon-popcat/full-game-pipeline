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
- `client/libraries/ItemDetails` owns the facts an item's info panel lists (amount, sell and
  stack value, mutation bonus, rarity, grow time, seed or shop price, footprint), for the
  backpack's sidebar and the Index's.

The server never takes an item id from a client: placing uses whatever is in the
player's held hotbar slot, and picking up reads the placed model's own attributes.

## What lives only in the place file

These are authored in Studio and are **not** in git (see `conventions.md`, UI):

| Instance | What it is |
|---|---|
| `StarterGui.HUD` | `Hotbar`, `Backpack` window (its sidebar is Preview and Information; the Controls panel is gone), `Index` window (item list in `Body.Main`, the `Body.Showcase` with its `View` viewport, `ItemName`, `Kind`, `Glow` and `Hint`, and facts in `Body.Sidebar.Information`), `DragGhost`, `ItemName`, `SideButtons.Backpack`, `SideButtons.Index` (a book icon) |
| `ReplicatedStorage.Assets.UI.Inventory` | `Slot` cell template, `SelectionImage`, `InfoRow` (a Key/Value row ItemDetails clones into a panel's `Rows`, ahead of its `Description` at LayoutOrder 100) |
| `ReplicatedStorage.Assets.UI.Stack` | `Count`, a BillboardGui with a TextLabel `Label` inside, cloned over every stack of more than one item, loose or on a belt, to show "x24"; until it is authored StackLabel draws a plain dark pill, without a warning |
| `ReplicatedStorage.Assets.Blocks` | One Model per placeable item, named by item id, each with a hitbox `PrimaryPart` (below): the retained building cubes, machines and seed ghosts; unused templates do not create items |
| Cube materials | Grass and Dirt are a MeshPart of one cube mesh (`GroundCubeMesh` attribute of `Assets.Blocks`) wearing the game's own textures (`Shared/World/GroundLook`, drawn by `tools/textures/ground.py`): Grass has grass on top, dirt sides with grass hanging over their top edge, and dirt underneath; Dirt is dirt all round. `tools/textures/studio_cubes.luau` sets them up. The other cubes (Stone, Bricks...) have a Roblox material that says what it is (Slate, Concrete, Cobblestone, Brick, WoodPlanks) and Smooth surfaces, set by `IslandsMachines/build/studio_cubes.luau`, which must leave Grass and Dirt alone |
| `ReplicatedStorage.Assets.Tools` | `Hammer`, `Pickaxe`, `WateringCan` Tools, and optionally a `Hoe` (until then ItemArt builds a plain wooden one); the unused Axe template is harmless |

The RemoteEvents are the exception: they are declared in `default.project.json`.

## Block templates

A block template's `PrimaryPart` is its hitbox, and the hitbox's pivot is the template's only
pivot. The hitbox is a box of whole 3-stud cells: its size is the footprint, and placing the
block fills the placement's cells with it. A cube is its own hitbox. A machine has an
invisible, queryable, non-colliding part named `Hitbox` around its art. The art may poke out
of the hitbox by up to 0.15 studs, which `Build`'s overlap margin allows for. The pivot sits
on the floor at a convenient cell centre (the conveyor's, or under a machine column); placement reads it relative to the hitbox, so where it sits never changes placement.
Machine parts collide with their exact shape.

A machine whose art leaves some of its cells empty (a Randomizer fills a 1×3 belt and one
side cell of its 3×1×3 box) keeps that box as its `PrimaryPart` for the footprint, pivot and
ports, but the box is not queryable. Smaller parts, also named `Hitbox`, sit inside it and
cover only the filled cells, and aim rays and overlap tests meet those. Other blocks can go
in the empty cells. Overlap tests skip the art of any model whose `PrimaryPart` is a
`Hitbox` (`Build.isCoveredArt`), because a mesh's bounding box can span cells its shape
leaves empty. `IslandsMachines/build/studio_cells.luau` makes the cell boxes from the art:
a cell is filled when the art reaches more than 0.5 studs into it. Run it again after every
run of `studio_blocks.luau`. The routers' art stays under 3 studs tall, so they fill one level
and blocks can stand on top of them. BuildController outlines a ghost or target by those same
boxes, tracing only the outer edges of the cells they cover (a thin BoxHandleAdornment per
cell edge where the shape turns a corner), so seams between boxes and empty corners stay
unmarked and the outline shows the cells the block really takes.

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
New profiles receive the starter kit defined in DataService (a Hammer, Pickaxe and Hoe; seeds
are bought); the old full test kit is gone.
Inventory mutations wait for DataReady. InventoryService snapshots slots and releases its held
Tool only after the final save snapshot. The selected slot resets to one on load.

BuildService.place is shared by normal placement and profile restoration. It synchronously
registers factories, while seeds go directly to WorldService.plant. Saved blocks retain item id,
plot-relative cell, rotation, Against and factory contents. See [plots.md](plots.md).

## Index

The Index side button opens a window of every plain item in the catalogue (IndexScreen).
GardenService keeps the item ids each player has had, in their inventory (any
`InventoryService.give`) or harvested on their plot, and sends them all over `IndexSync` on load
and on each new one; at load, whatever the inventory already holds counts. Items not yet had are
dark silhouettes named "???". The window has three areas: the item list, a showcase where the
picked item turns slowly in a large viewport and can be dragged to look at it from any side
(`libraries/Turntable`; with reduced motion it only turns when dragged), and the facts:
ItemDetails' rows, how many of its mutation sets have been found, and which. Products a machine sends straight to a Shipping Bin
are not counted until one reaches the inventory.

The garden HUD contract is in [economy.md](economy.md#authored-hud-contract-place-file-only).
Shared/ItemArt owns tinted seed/produce fallbacks and mutation icons; Build delegates its
template lookup there. Shop and Sell share window exclusivity with Backpack/MachinePanel
through libraries/Screens. Sell All removes matching stacks and syncs once through
InventoryService.takeWhere; currency pricing stays in GardenService.
