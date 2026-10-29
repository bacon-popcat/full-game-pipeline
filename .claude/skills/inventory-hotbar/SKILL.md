---
name: inventory-hotbar
description: >
  Build or change a slot-based game inventory: an item catalogue, stack sizes, a hotbar and
  backpack, drag or click moves, the held item as a Tool, and starter kits. Use when adding
  items or item kinds, changing stacks or slot counts, working on the hotbar or backpack UI,
  making something the player holds or swings, granting rewards, or when items disappear,
  duplicate or show in the wrong slot.
---

# Inventory and hotbar

This is the Islands-style inventory: a 9-slot hotbar plus an 81-slot backpack, owned by the
server and predicted by the client. Read [docs/inventory.md](../../../docs/inventory.md)
first. The sync pattern is in the `server-authority` skill.

## Model

- **Catalogue as data.** [src/shared/Inventory/Items.luau](../../../src/shared/Inventory/Items.luau)
  lists every item in catalogue order, built with small constructors (`tool`, `block`, ...).
  Each item has an `id`, `name`, `kind` (`Tool | Block | Machine | Resource`), `stack`, and
  optional fields only some kinds use (`picksUp`, `breaksWith`). Duplicate ids assert at
  require time.
- **Slots are dense.** `Slots = { Stack | false }`. An empty slot is `false`, never `nil`,
  because nil holes truncate arrays sent over a remote. Slots `1..HOTBAR_SIZE` are the
  hotbar, and `selected` is a hotbar index, with `0` for an empty hand.
- **The rules are pure functions on a slot list** (`move`, `add`, `take`, `stackAt`,
  `emptySlots`) in `Shared/Inventory`. The server applies them and the client predicts with
  them (`InventoryClient`).
- **The hand is derived, never tracked separately.** `refreshHeld` re-reads the selected slot
  after anything that could change it, and swaps the Tool only when the item id changed.
- **Every item can be held.** `HeldItem` clones the authored Tool for tools, and gives blocks,
  machines and resources a generated Tool holding a shrunken copy of their art. Each one carries
  an `ItemId` attribute, can't be dropped by Roblox, and has `CanQuery` off on every part, so
  the hand never blocks a placement.
- **Art is looked up by id** through `Shared/ItemArt`: Blocks, Tools or Items in
  `ReplicatedStorage.Assets`. Missing art draws a grey cube and warns once, so a gap in the art
  never stops the game.

## Adding an item

1. Add an entry to `Items.luau` with the right kind constructor and stack.
2. Put its art in `Assets.Blocks`, `Assets.Tools` or `Assets.Items`, named exactly the id.
   A block also needs its whole-cell `Hitbox` PrimaryPart (see `grid-building`).
3. If a machine uses it, add it to that machine's recipe (see `factory-automation`). If it
   has a value, give it one in the economy content (see `economy-progression`).
4. Variants that must stack separately (mutations, tiers) get their own id
   (`Carrot+Golden`). Don't put per-instance data on a stack.

## Granting and taking

- Server code checks with `InventoryService.canGive` / `canGiveAll` (a whole bundle), then calls `give`;
  never remove a source (a node, a machine's output) before you know the whole reward
  fits.
- When picking up a block, whatever it held comes back with it (`FactoryService.drain`).
  Decide on purpose what happens to overflow: on master it is lost. Saying so in the module
  header is part of the decision.
- The starter kit is part of the save template (`DataService` on `garden-overhaul`), not the
  inventory module.

## UI

The HUD (`StarterGui.HUD`: `Hotbar`, `Backpack`, `DragGhost`, `ItemName`) is authored in
the place file, not in git. `UIController/InventoryScreen` binds to it and clones the
`Assets.UI.Inventory.Slot` template. Every key binding and its hint text lives in
`client/libraries/Controls`, one table per `PreferredInput`, so a rebind can't leave a
hint out of date. Look and feel: see `roblox-ui` (project section).

## Check

- Move, swap and merge stacks; select an empty slot (the hand empties); drop the last one.
- Overflow while mining, collecting and taking blocks back must never lose part of a reward
  silently.
- Respawn: the held Tool comes back in the new character's hand.
- Two players: one player's moves never appear in the other's snapshot.
