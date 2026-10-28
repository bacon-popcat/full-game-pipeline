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
- `Shared/Build` holds the 3-stud grid, footprints, reach and the overlap test both sides run.
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
| `ReplicatedStorage.Assets.Blocks` | One Model per placeable item, named by item id, each with a hitbox `PrimaryPart` (below): six cubes plus copies of the 53 `Workspace.IslandsMachines` models |
| `ReplicatedStorage.Assets.Tools` | `Hammer`, `Pickaxe`, `Axe` Tools |

The RemoteEvents are the exception: they are declared in `default.project.json`.

## Block templates

A block template's `PrimaryPart` is its hitbox, and its centre is the template's only pivot.
The hitbox is a box of whole 3-stud cells: its size is the footprint, and placing the block
fills the placement's cells with it. A cube is its own hitbox. A machine has an invisible,
queryable, non-colliding part named `Hitbox` around its art. The art may poke out of the
hitbox by up to 0.15 studs, which `Build`'s overlap margin allows for.

For conveyors to connect, a machine's conveyor runs down the middle of a column of cells,
and a conveyor end that meets a neighbour sits on a hitbox face. The Islands pipeline builds
the hitboxes and the copies in `Assets.Blocks` with `IslandsMachines/build/studio_blocks.luau`.
That folder is outside git, and its README covers the rules.

## Adding an item

1. Add it to `src/shared/Inventory/Items.luau`.
2. Put its art in `Assets.Blocks` (blocks and machines) or `Assets.Tools` (a Tool), named
   exactly the item id. A block also needs its hitbox `PrimaryPart` (above). The footprint
   comes from the hitbox, so no size is entered.

## Not built yet

- Persistence: inventories reset on join (everyone gets a full stack of every item) and
  placed blocks only last as long as the server.
- Pickaxe and Axe equip and swing but have nothing to act on.
