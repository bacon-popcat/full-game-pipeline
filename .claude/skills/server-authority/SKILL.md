---
name: server-authority
description: >
  Split a multiplayer game feature between server and client: the server decides, the client
  sends intents and predicts the result with the same shared rules, and a full snapshot
  corrects any wrong guess. Covers documented remotes, syncing on discrete events instead of
  streaming positions, and what to validate. Use when adding a remote or network message, a
  player action (place, mine, buy, sell, interact), client prediction, or state sync
  (inventory, moving items, balances), or when the client and server disagree.
---

# Server authority and sync

Players can only ask. The server holds the truth and checks every request. The client keeps
a copy it predicts from, so the game responds at once. On Roblox, also see
`roblox-skills:roblox-networking` and `roblox-skills:roblox-security`.

## The pattern

```text
shared module     pure rules + data shapes, run by BOTH sides
server service    owns state, validates intents, applies the shared rules, sends a snapshot
client library    holds the last snapshot, predicts its own intents, sends the intent
```

- **Put the rules in shared code, as pure functions** (inventory move/add/take, placement
  checks, how an item moves along a path, whether a cell can be planted). The client's
  preview and the server's check run the same code, so a green preview means the server will
  accept it.
- **Answer every intent with a full snapshot,** including rejected ones. The client replaces
  its state with the snapshot, so a wrong prediction undoes itself with no rollback code.
- **Never take an authoritative value from the client.** Place what is actually in the
  player's held slot, not the item id they send. Read a target's owner and contents from the
  server's own record. Never accept a plot, team or balance from a request. When a payload
  names an item, check that the player has it.
- **Sync on events, not every frame.** For anything that moves by a deterministic rule (items
  on a conveyor, a creature walking to a point), send its start state and a server timestamp
  when it changes. Clients run the same rule in between, so positions are never streamed.
- **Publish read-only state on the world object** (on Roblox, attributes on the model), such
  as status, contents and progress. Every client can read it for hover text and panels with
  no extra message.

## Remotes

- Look every remote up from one module, with a comment beside each giving its direction and
  payload. That comment is a contract, not a guarantee, so the receiver still validates
  everything.
- Prefer one remote per domain with an action string (`Interact` with `Load`, `Collect`,
  `Switch`) to one remote per button.
- Sync remotes (server to client) for balances and inventories have no inbound counterpart.
  Nothing a client sends sets a balance.

## Validate every request, in this order

1. **Type and shape.** Check the type of every argument. Numbers must be finite, and integers
   where expected. Clamp coordinates to sane bounds.
2. **Identity.** The target belongs to the expected container and to this system.
3. **Permission.** The player owns it, and the player's data has finished loading.
4. **Reach.** Measure from the character to the target's bounds.
5. **Rate.** Put a per-player cooldown on actions a client could spam.
6. **The rule itself.** It fits, it doesn't overlap, the player can afford it, it's in stock.

## Common bugs

- **Gaps in arrays.** Many serializers (Roblox remotes included) cut an array short at its
  first `nil`. Mark empty slots with `false` so the list stays whole.
- **Updates for things the client doesn't have yet.** Queue the update until the object
  replicates, and drop updates for objects that were removed.
- **Two services that require each other.** Have one register a hook with the other instead
  of requiring it.
- **A reward that only partly fits.** Check the whole bundle against a copy of the inventory
  before removing its source, or part of the reward is lost.
- **Yielding between a check and its effect.** Another request can pass the same check in
  between. Apply the change first, then do anything async.
- **Testing from tooling.** Code run from an editor or MCP tool may get its own copy of
  modules, not the live game's. Drive the real game through its remotes (see
  `studio-playtest`).
