---
name: server-authority
description: >
  Split a multiplayer game feature between server and client: the server decides, the client
  sends intents and predicts with the same shared rules, and a full snapshot corrects any
  wrong guess. Also covers documented remotes, sending changes only on discrete events,
  and what to validate. Use when adding a RemoteEvent, a new player action (place, mine,
  buy, sell, interact), client prediction, syncing state such as an inventory, belts or a
  balance, or when the client and server disagree.
---

# Server authority and sync

Players can only ask. The server holds the truth and checks every request. The client keeps a
copy that it predicts from, so the game responds instantly. This skill is how this project
does that. For general Roblox remote API detail, see `roblox-skills:roblox-networking` and
`roblox-skills:roblox-security`.

## The pattern

```text
Shared/<Domain>   pure rules + data shapes, run by BOTH sides
server service    owns state, validates intents, applies Shared rules, sends a snapshot
client library    holds last snapshot, predicts own intents with Shared rules, fires intent
```

- **Shared rules are pure and run on both sides.** `Shared/Inventory` (move/add/take),
  `Shared/Build` (grid, reach, overlap), `Shared/Factory/Lane` (how items move) and
  `Shared/World/Soil` (can I plant here). The client's preview and the server's check use the
  same code, so a green ghost means the server will accept the placement.
- **Answer every intent with a full snapshot.** `InventoryService` sends `InventorySync` after
  every move, including rejected ones, and the snapshot replaces the client's state outright.
  Undoing a wrong prediction needs no extra code.
- **Never take an authoritative value from the client.** Placing uses the held hotbar slot,
  never an item id sent in the request. Picking up reads the placed model's own attributes.
  Plot indices and owners never come from a request. If a payload names an item, check it
  against what the player actually has.
- **Send discrete events, not positions.** Conveyor items move by a shared deterministic rule
  (`Lane.advance`). The server sends a lane's item list only when an item joins or leaves it
  (`FactorySync`, stamped with server time `t`), and clients slide the items in between. Use
  the same idea for anything that moves predictably: send the start, the end and the start
  time (animals publish `WalkFrom/WalkTo/WalkStart/WalkTime` as attributes).
- **Publish read-only state as attributes** on the world model (machine `Status`, `Contents`,
  `Progress`). All clients read them for the hover text and the machine panel, with no remote.

## Remotes

- Declare every RemoteEvent in `default.project.json` and look each one up once in
  [src/shared/Remotes.luau](../../../src/shared/Remotes.luau), with a comment giving its
  direction and payload. That comment is a contract, not a guarantee, so the receiver still
  validates everything.
- Prefer one verb-shaped remote with an action string per domain (`Interact` with `Load`,
  `Collect`, `TakeBack`, `Switch`, `Filter`) over one remote per button.
- Server-to-client sync remotes (`InventorySync`, `EconomySync`, `FactorySync`) have no
  inbound counterpart. Nothing a client can send changes a balance.

## Validate every request, in this order

1. Type and shape: `typeof` each argument; numbers must be finite and integer where expected
   (`amount % 1 == 0`, `< math.huge`); cells are clamped (`MAX_CELL` in `Build`).
2. Identity: the target Instance is a descendant of the right folder (`Workspace.Placed`,
   `Workspace.World`) and is a model this system owns.
3. Permission: owner checks (`Owner` attribute or plot), `DataReady` before any edit.
4. Reach: distance from the character's root to the target's box (`Build.REACH`).
5. Rate: a per-player cooldown on spammable actions (BuildService has one).
6. Rule: the shared rule itself (fits, overlaps, soil, stock, can afford).

## Pitfalls this project hit

- **`nil` holes cut arrays short in transit.** Keep slot lists dense with `false` for empty.
- **Updates for instances that haven't replicated yet.** FactoryController holds a lane update
  until its block appears, and the server drops queued updates for removed blocks.
- **Two services that need each other.** Pass a hook in instead of requiring both ways
  (`DropService.setBelts` is registered by FactoryService).
- **A multi-item reward that partly fits.** Check the whole bundle against a copy of the
  inventory before removing the source, or a mined node can drop part of its yield.
- **Testing from MCP.** In a playtest, `require` in `execute_luau` gets a separate module copy,
  so it can't reach the running services. Drive the real game through the client remotes, or
  through a BindableEvent bridge (see `studio-playtest`).
