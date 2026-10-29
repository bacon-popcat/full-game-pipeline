---
name: inventory-hotbar
description: >
  Build or change a slot-based game inventory: an item catalogue, stack sizes, a hotbar and
  backpack, moving stacks by drag or click, the held item, granting rewards and starter
  kits. Use when adding items or item kinds, changing stacks or slot counts, building the
  hotbar or backpack UI, making something the player holds, or when items disappear,
  duplicate or show up in the wrong slot.
---

# Inventory and hotbar

The server owns the inventory and the client predicts it. The sync pattern is in
`server-authority`.

## Model

- **The catalogue is data.** One module lists every item in display order, built with small
  constructors (`tool(...)`, `block(...)`, `resource(...)`). Each item has an `id`, `name`,
  `kind`, `stack`, and only the fields its kind needs (for example `breaksWith` for blocks).
  Duplicate ids assert when the module loads.
- **Slots are dense.** `Slots = { Stack | false }`, where `Stack = { itemId, count }`. An empty
  slot is `false`, never `nil`, so the list survives the network. Slots `1..HOTBAR_SIZE` are
  the hotbar and the rest are the backpack. `selected` is a hotbar index, with `0` for an
  empty hand.
- **The rules are pure functions on a slot list**: `move` (merge, swap, split), `add`, `take`,
  `stackAt`, `emptySlots`. The server applies them and the client predicts with them.
- **The hand is derived, not tracked.** After anything that could change the selected slot,
  re-read the slot. Swap the held object only when the item id actually changed.
- **Every item can be held.** Tools use their authored model. Blocks and resources get a
  generated holdable carrying a small copy of their art. On Roblox it's a Tool with an
  `ItemId` attribute, `CanBeDropped` off and `CanQuery` off on every part, so the player's own
  hand never blocks their aim or a placement.
- **Look art up by id** from asset folders named after item ids. Missing art draws a
  placeholder cube and warns once, so a gap in the art never breaks the game.

## Adding an item

1. Add a catalogue entry using the right constructor and stack size.
2. Add its art under its id (a block also needs its hitbox; see `grid-building`).
3. Give it a value and a use: a recipe (`factory-automation`), a price
   (`economy-progression`), a drop source (`world-resources-and-drops`).
4. Variants that should stack separately (rarities, mutations, tiers) get their own id
   (`Carrot+Golden`). Don't hang per-instance data on a stack.

## Granting and taking

- Check first (`canGive(id, count)`, `canGiveAll(bundle)`), then give. Never remove a source
  (a node, a machine's output, a chest) before you know the whole reward fits.
- When a block that holds items is picked up, its contents come back with it. Decide on
  purpose what happens to overflow (drop it, refuse the pickup, or lose it) and write that
  down in the module header.
- Starter kits belong in the save template, not the inventory module.

## UI

- Put every key binding, and the hint text that names it, in one controls module with a hint
  for each input type (keyboard, touch, gamepad), so a rebind can't leave a hint wrong.
- Render from the client's snapshot, and redraw on a single "changed" signal.
- Moves: click-click and drag on desktop, tap-tap on touch, lift and drop on gamepad. Show a
  ghost of the lifted stack.
- Building the UI itself on Roblox: see `roblox-ui`.

## Check

- Move, swap, merge and split stacks. Select an empty slot (the hand empties). Use up the
  last item in a stack.
- Overflow from mining, collecting and picking up blocks never silently loses part of a
  reward.
- Respawn: the held item comes back in the new character's hand.
- With two players, one player's moves never reach the other's snapshot.
