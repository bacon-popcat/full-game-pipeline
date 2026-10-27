# Conventions

The short version. Read this before your first commit; it should take ten minutes.
`CLAUDE.md` is the long version — the *why* behind each rule and the per-system detail.
When the two disagree, the code wins and both docs are wrong; fix them.

## Running it

```sh
rokit trust JohnnyMorganz/luau-lsp   # rokit refuses untrusted tools, silently when non-interactive
rokit install                 # selene, stylua, blink, wally, luau-lsp, rojo
wally install                 # populates Packages/ and ServerPackages/
rojo serve                    # sync into Studio, with the Rojo plugin connected
bash ./scripts/check.sh            # run this before every commit
```

`check.sh` is the gate: stylua, selene, luau-lsp, and a set of greps for the naming,
structure, bootstrap and documentation rules no linter can express. **It should be
green.** If it isn't, that's the commit's problem, not the gate's — a check that always
fails is one everyone learns to scroll past. Read the script for the current list; each
check carries a comment saying which real failure it exists to prevent.

`blink config.blink` regenerates both `BlinkNetworker.luau` files. They are generated
output: edit `config.blink` and rerun, never the files.

## Naming

| Thing | Case |
|---|---|
| Modules, classes, types, Instance names | `PascalCase` |
| Functions, locals, fields, parameters | `camelCase` |
| Module-level constants (including `TweenInfo`s) | `SCREAMING_SNAKE_CASE` |

Lifecycle hooks are functions, so they're lowercase: `init`, `open`, `close`. A
capitalized `Init` is **silently never started** — no error, just a feature that quietly
does nothing.

**No `_` prefix.** Private is `local function`, which the language actually enforces;
public is on the module table. There is no third category. (The one exception is a field
on a real class instance, like `Slider._trove`, where a local genuinely can't work.)

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
`check.sh` rejects these.

**Real classes are fine** where there's genuinely one object per instance — `Slider`,
`Toggle`, `Onboarding`. Those set `__index` and are exempt.

A real class declares its methods with an **explicit typed `self`**, and is still called with `:`

```lua
function Onboarding.start(self: Onboarding)   -- not  function Onboarding:start()
```

Colon syntax leaves `self` loosely inferred, so the type checker stops looking. Explicit `self`
is what caught a `Tween?` being called with no nil check on one of these classes, invisible until
then.

## Starting up

`ModuleLoader.startChildren(container, ...)` is the only way a container of modules gets
started, and it defines the whole contract:

```lua
function Module.init(...)   -- lowercase, no self, args explicit, optional
```

It requires every `ModuleScript` child and `task.spawn`s `init` if one exists. Modules
start in **arbitrary order and each in its own thread**, so:

- Never assume a sibling's `init` has run. Set your state up at *require* time and use
  `init` only to push that state at the world.
- Yielding in `init` is safe (it can't stall a sibling) — but the data you're waiting for
  still isn't there for anyone else.
- Player data does not exist during `init`. Anything needing it goes inside a
  `task.spawn` around `ReplicaManager.observe`.

## Where things go

| Path | Holds |
|---|---|
| `Shared/<Domain>` | A feature package: `init.luau` is its public module, with focused config, runtime, and type children (`Pet`, `Pet/Scale`, `Sled/Team`, `Pet/Plot/PublicTypes`) |
| `Shared/Info` | Standalone authored content that has not grown into a package (`BoostInfo`, `ZoneInfo`) |
| `Shared/Data` | Cross-boundary persistence and replication infrastructure (`Template`, `ReplicaTyped`) |
| `Shared/Format` | Player-facing value formatters (`Number`, `Time`) |
| `Shared/` root | Generic primitives with no feature owner (`SFX`, `ModuleLoader`) |
| `server/services`, `client/controllers` | Feature modules, auto-started, expose `init` |
| `server/libraries`, `client/libraries` | Classes and helpers, **not** auto-started |

Use `init.luau` when a ModuleScript owns real child modules. A module with no
children is `<Name>.luau`; do not add a wrapper directory solely to hold `init.luau`.

Dependencies point **Services → Libraries, never back**. Libraries must not require a
controller either — that's why `Notification` re-resolves the camera itself instead of
using `EffectsController.Camera`.

**Require shared modules by absolute path** (`require(ReplicatedStorage.Shared.Pet.Scale)`),
never `script.Parent`. A relative chain re-breaks the next time anything moves. Only a
same-group sibling stays relative.

## Types

`luau-lsp` runs in `check.sh`, so type errors are build errors. `.luaurc` pins `nonstrict`
as the default.

New modules under `src/shared` start with `--!strict`. Existing non-strict shared
modules are the exact migration baseline in `scripts/non-strict-shared.txt`: do not
add entries. Remove a path from that file in the same change that migrates it. The
gate rejects both new non-strict shared modules and stale baseline entries.

- Annotate parameters and return types. An annotated `Instance`/`Folder` parameter is
  checked against that class's real API even outside `--!strict`, so define a narrow
  intersection for known shapes: `type Plot = Folder & { Pads: Folder }`.
- **`assert`, don't cast.** A `:: Frame` silences the checker and then parents your node
  to nowhere at runtime; `assert(frame, "bindUI must run first")` narrows the type *and*
  tells whoever broke the invariant.
- Types that describe **data** move to the owning package in `Shared` (for example,
  `Shared/Pet/Plot/PublicTypes`). Types that describe **behaviour** stay with the
  behaviour — moving an identity type means requiring its module, which is the cycle
  you were avoiding. Move a type when a *second* consumer appears, not before.

## UI

The HUD is authored by hand in `StarterGui.HUD`, which is **not** in
`default.project.json` — it lives in the `.rbxl` only. So:

- Bind to what's authored. Don't `Instance.new` a hierarchy; clone a template from
  `ReplicatedStorage.Assets.UI.<Consumer>`.
- **Capture baselines from the instance**, never hardcode them. A constant here drifts
  silently the moment someone retunes the scene in Studio, and git never sees it.
- Look children up with `FindFirstChild` and warn, rather than dot-indexing and throwing.

`libraries/UI.luau` owns the button layer. Use it rather than hand-rolling hover/press:

```lua
UI.bindButton(node, {
    target = icon,            -- what animates; defaults to the button
    hoverScale = 1.12,
    hitTest = isOverHexagon,  -- for non-rectangular buttons
    shine = true,
    onActivate = function() end,
})
```

A clickable thing is either a bare `GuiButton` or a `Frame` wrapping a `Trigger` button;
`UI.resolveButton` handles both, so neither needs a convention of its own.

`libraries/Tooltip.luau` owns hover tooltips the same way, and resolves buttons through
that same function:

```lua
Tooltip.new():addTitle("Shop"):attach(button)
```

A tooltip follows the cursor while it is over the button, placed straight into
`Position` — no tween, because an eased tooltip lags the cursor it is attached to.

Each row is a template under `Assets.UI.Effects.Tooltip.Components`, so a new row type is
a template in Studio plus a one-line method beside `addTitle` — never a hierarchy built
here. Adds are idempotent, so refreshing live text is the call that built the tooltip.

## Global properties get arbitrated, never assigned

FOV, blur, and anything else with one value and several would-be writers is **derived
from named requests**, not written directly:

```lua
Lighting.set("Blur.Size", "sideButtons", 10, Lighting.TWEEN_INFO)
Lighting.clear("Blur.Size", "sideButtons", Lighting.TWEEN_INFO)
```

Each feature owns a source id, so it can only ever fight itself, and releasing one falls
back to whatever the *other* live requests want rather than snapping to a default. A
plain boolean lock can say "nobody else may write" but has no answer for what the value
should be afterwards — which is how you strand a player behind a permanent blur.

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
