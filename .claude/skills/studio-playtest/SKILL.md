---
name: studio-playtest
description: >
  Get repo code into an open Roblox Studio place and prove a game change works there: syncing
  with Rojo or an HTTP push, running long scripts, playtesting through Studio MCP, driving
  the live services, two-player checks and screenshots. Use after any gameplay, UI or art
  change before calling it done, when Rojo isn't running, when a playtest misbehaves, or when
  the user asks to test, verify or check something in game.
---

# Studio playtest

Lint, type checks and reading code don't prove a game works, so every gameplay change ends
with a playtest in the real place. For the MCP tools themselves, see
`roblox-skills:roblox-studio-mcp`.

## Which place

Call `list_roblox_studios` / `get_studio_state` first. If more than one place could be the
target, confirm which is open before writing to it. Record the target place's name and
placeId in memory once the user names it.

## Getting code in

1. **Rojo:** `rojo serve` (port 34872 by default) with the plugin connected. Check that
   something is listening on that port before assuming it's syncing.
2. **No Rojo:** serve the repo with `python -m http.server <port> --bind 127.0.0.1`. Then, in
   an Edit-mode `execute_luau`, fetch each file with HttpService and assign it to
   `Script.Source`, stripping `\r` if the repo uses CRLF. This needs Allow HTTP Requests on.
   Afterwards, compare every synced file against Studio, so a missed file isn't mistaken for
   a bug.
3. Some instances exist only in the place file (authored UI, asset templates). Edit those in
   Studio and say so in the project's docs.

## Running long scripts

Don't paste a long script into the tool call. Fetch it from the same local server, put it in
a temporary ModuleScript's `Source`, `require` it, then destroy the ModuleScript. gsub the
source first to limit it to what changed.

## Playtesting

- Use `start_stop_play` to start, `get_console_output` for errors and warnings, and
  `screen_capture` to see the result.
- **In Play mode, `require` and `_G` inside `execute_luau` give separate copies** of the
  modules. Calling a service that way creates state that nothing in the running game
  processes. To drive the live game:
  - fire the **client remotes** in the order a player would; or
  - create a server Script at runtime that listens on a BindableEvent in ServerStorage, and
    fire that event to call into the real services.
- Use `character_navigation` and `user_keyboard_input` / `user_mouse_input` for anything that
  depends on the character: reach, walking, pickups.
- **Know the world's bounds.** A default baseplate is 512 studs wide (±256). Objects placed
  past its edge fall through, which looks like a physics bug but isn't.
- Without API access, data stores need a mock, so saves last for one server only.

## What to check

Write the checklist before you start, from the domain doc if one exists:

- the happy path end to end;
- refusals: out of reach, not the owner, inventory full, wrong tool, can't afford it;
- edge cases: rotations, area borders, backed-up queues, leaving mid-action, rejoining;
- two players, wherever ownership or sync is involved;
- UI at desktop, phone and gamepad (`roblox-ui`);
- a clean console, with no new warnings or errors.

## Report

Say what you ran and what you saw, with a screenshot of the visible result. List anything you
couldn't check, and why.
