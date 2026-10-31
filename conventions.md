# Conventions

The short version. Read this before your first commit. `CLAUDE.md` has the current state,
repo map and invariants; `docs/` maps each system. When a doc and the code disagree, the
code wins and the doc is wrong; fix it.

## Running it

```sh
aftman install                # rojo, pinned in aftman.toml
wally install                 # populates Packages/ and ServerPackages/
rojo serve                    # sync into Studio, with the Rojo plugin connected
```

`stylua.toml` and `selene.toml` configure formatting and linting; run them on what you
change if you have them installed. Neither replaces a Studio playtest.

## Naming

| Thing | Case |
|---|---|
| Modules, classes, types, Instance names | `PascalCase` |
| Functions, locals, fields, parameters | `camelCase` |
| Module-level constants (including `TweenInfo`s) | `SCREAMING_SNAKE_CASE` |

Lifecycle hooks are functions, so they're lowercase: `init`. A capitalized `Init` is
**silently never started** — no error, just a feature that quietly does nothing.

**No `_` prefix.** Private is `local function`, which the language actually enforces;
public is on the module table. There is no third category.

## Module shape

Modules are **static tables of functions**. No `self`, no `setmetatable`, no colon calls:

```lua
local Thing = {}

local function helper() end        -- private: unreachable from outside, by construction

function Thing.doTheWork(target: GuiObject, amount: number) end

return Thing
```

A singleton that takes `self` without an `__index` is a class pretending — `self` is
always the module table, so it buys nothing and costs a parameter on every call.

If a real class is ever needed (one object per instance), it sets `__index` and declares
its methods with an **explicit typed `self`**, still called with `:`:

```lua
function Slider.start(self: Slider)   -- not  function Slider:start()
```

Colon syntax leaves `self` loosely inferred, so the type checker stops looking.

## Starting up

`ModuleLoader.startChildren(container, ...)` (`Shared/ModuleLoader`) is the only way a
container of modules gets started: the server's `initialize` script starts
`ServerScriptService.Services`, the client's starts its `Controllers`, and `UIController`
starts its screens with the HUD. The contract:

```lua
function Module.init(...)   -- lowercase, no self, args explicit, optional
```

It requires every `ModuleScript` child and `task.spawn`s `init` if one exists. Modules
start in **arbitrary order and each in its own thread**, so:

- Never assume a sibling's `init` has run. Set your state up at *require* time and use
  `init` only to push that state at the world.
- Yielding in `init` is safe (it can't stall a sibling) — but the data you're waiting for
  still isn't there for anyone else.
- Player data does not exist during `init`. DataService loads each profile and calls the
  services' `load`/`restore` in order (plots.md § Flow); gameplay waits for `DataReady`.

## Where things go

| Path | Holds |
|---|---|
| `Shared/<Domain>` | A feature package: `init.luau` is its public module, with focused content and rule children (`World/Mutations`, `Factory/Blocks`, `Economy/Shops`) |
| `Shared/` root | Single-module rules and primitives (`Build`, `Plot`, `Hub`, `Remotes`, `ItemArt`, `ModuleLoader`) |
| `server/services`, `client/controllers` | Feature modules, auto-started, expose `init` |
| `server/libraries`, `client/libraries` | Helpers, **not** auto-started |

Use `init.luau` when a ModuleScript owns real child modules. A module with no
children is `<Name>.luau`; do not add a wrapper directory solely to hold `init.luau`.

Dependencies point **Services → Libraries, never back**. Libraries must not require a
service or controller either.

**Require shared modules by absolute path** (`require(ReplicatedStorage.Shared.World.Mutations)`),
never `script.Parent`. A relative chain re-breaks the next time anything moves. Only a
same-group sibling stays relative.

## Types

Every module under `src/shared` starts with `--!strict`; keep it that way for new ones.

- Annotate parameters and return types. An annotated `Instance`/`Folder` parameter is
  checked against that class's real API even outside `--!strict`, so define a narrow
  intersection for known shapes: `type Stall = Model & { Counter: BasePart }`.
- **`assert`, don't cast.** A `:: Frame` silences the checker and then parents your node
  to nowhere at runtime; `assert(frame, "bindUI must run first")` narrows the type *and*
  tells whoever broke the invariant.
- Types that describe **data** live with the module that owns that data (`Plot.SavedBlock`,
  `Shops.Offer`). Types that describe **behaviour** stay with the behaviour. Move a type
  when a *second* consumer appears, not before.

## UI

The HUD is authored by hand in `StarterGui.HUD`, which is **not** in
`default.project.json` — it lives in the place file only. So:

- Bind to what's authored. Don't `Instance.new` a hierarchy; clone a template from
  `ReplicatedStorage.Assets.UI.<Consumer>`.
- **Capture baselines from the instance**, never hardcode them. A constant here drifts
  silently the moment someone retunes the scene in Studio, and git never sees it.
- Look nodes up through `libraries/Hud` (`Hud.find`), which warns once and lets that screen
  return, rather than dot-indexing and throwing.

`libraries/UI.luau` owns the button layer (`UI.bindButton`, `UI.resolveButton`). Use it
rather than hand-rolling hover/press. `libraries/Screens` decides which window is open.

## Global properties get arbitrated, never assigned

Anything with one value and several would-be writers is **derived from named requests**,
not written directly. Lighting is the example:

```lua
Lighting.set("weather", tint, brightness, contrast, seconds)
Lighting.clear("weather", seconds)
```

Each feature owns a source id, so it can only ever fight itself, and releasing one falls
back to whatever the *other* live requests want rather than snapping to a default.

Derive from the source of truth, don't increment a counter. A close that got skipped then
can't leave the world stuck.

## Comments

Header on every module: its responsibility, boundaries, and the invariants it owns.
Do not impose a line limit on load-bearing invariants, but do not turn the header into
a tour of the surrounding system; cross-boundary flows belong in `docs/`.

Inline, comment the **why**, not the what — local rationale, a rejected alternative, or
a bug that a change would reintroduce. `-- increment the counter` is noise. Documentation
should point to the module that owns a computed fact instead of copying that fact.

A comment that no longer matches the code is worse than no comment, because it gets
believed. If you change the code, change the comment or delete it.
