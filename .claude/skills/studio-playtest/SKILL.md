---
name: studio-playtest
description: >
  Get repo code into the open Roblox Studio place and prove a game change works there:
  syncing with Rojo or an HTTP push, running long pipeline scripts, playtesting through Studio
  MCP, driving the real running services, two-player checks, and screenshots. Use after any
  gameplay, UI or art change before calling it done, when Rojo isn't running, when a playtest
  misbehaves, or when the user asks to test, verify or check it in game.
---

# Studio playtest

Lint, type checks and reading code don't prove a game works. Every gameplay change ends with
a playtest in the real place. For the MCP tools themselves, see
`roblox-skills:roblox-studio-mcp`.

## Which place

`mcp__Roblox_Studio__list_roblox_studios` / `get_studio_state` first. The work on
`garden-overhaul` goes to **"farming game"** (placeId 138368191071189). The older place
"Full game test" (71707877047488) holds master's showcase. Confirm which one is open before
writing to it.

## Getting the code in

1. **Rojo**: `rojo serve` (port 34872) with the plugin connected. Check something is
   listening on that port before assuming it is.
2. **Without Rojo**: serve the repo root with `python -m http.server 34998 --bind 127.0.0.1`.
   Then, in an Edit-mode `execute_luau`, fetch each file with HttpService and assign
   `Script.Source`, stripping `\r` (the repo uses CRLF). Afterwards, **compare every `src/`
   file against Studio**, so a missed file isn't mistaken for a bug.
3. Pieces that live only in the place file (the `StarterGui.HUD`, `ReplicatedStorage.Assets`,
   UI templates) aren't in git. Edit them in Studio and say so in the docs.

## Running long scripts (pipeline, fixtures)

Don't paste a long script into the tool call. Fetch it over the same local HTTP server, put
it in a temporary ModuleScript's `Source`, `require` it, then destroy the ModuleScript. gsub
the source first to limit it to what changed (for example the blocks list in
`studio_blocks.luau`).

## Playtesting

- `start_stop_play` to start; read `get_console_output` for errors and warnings, and
  `screen_capture` to see it.
- **In Play mode, `require` and `_G` inside `execute_luau` are separate copies** of the
  modules. Calling a service that way (`DropService.spawn`) makes state nothing processes.
  To drive the real game, either:
  - fire the **client remotes** as the player does, e.g. `InventorySelect 2`, `Interact "Use"`
    on a rock to mine it, `InventoryMove` to slot 1, then `DropItem` onto a belt; or
  - create a server Script at runtime that listens on a BindableEvent in ServerStorage, and
    fire that event to call the real services.
- Use `character_navigation` and `user_keyboard_input` / `user_mouse_input` for anything that
  depends on the character (reach, walking over belts, picking up drops).
- **The baseplate is ±256 studs.** Things placed beyond it fall through the world, which
  looks like a physics bug but isn't.
- With API access off, ProfileStore uses its mock store: saves last for one server only.

## What to check

Write the checklist before playtesting, from the domain doc's "Studio playtest" list
(`docs/plots.md` has one), and cover:

- the happy path end to end (place, run, collect, sell);
- refusals: out of reach, not the owner, a full inventory, the wrong tool, not enough money;
- edges: rotations, plot edges, a backed-up belt, leaving mid-job, rejoining;
- two players, when ownership or sync is involved;
- the UI at desktop, phone and gamepad (see `roblox-ui`);
- the console: no new warnings or errors.

## Reporting

Say what you ran and what you saw, with a screenshot of the visible result. List anything
you couldn't check (for example "session locking needs API access, not tested").
