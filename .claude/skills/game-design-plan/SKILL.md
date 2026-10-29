---
name: game-design-plan
description: >
  Plan a game, an overhaul or a big feature as a design doc before code: the core loop, the
  feel, a decisions table, content tables with real numbers, what gets cut, and phases that
  each end playable. Use when the user asks for a new game direction ("make it like Grow a
  Garden"), an overhaul, a new progression system, a roadmap, or "plan this out", or when a
  request is too big to build in one change.
---

# Game design plan

A design doc decides what to build before anyone builds it. This project's
[docs/overhaul.md](../../../docs/overhaul.md) (branch `garden-overhaul`) is the worked example:
use its shape.

## Workflow

1. **Name the feel first.** One or two sentences about how the game should feel to play. Here
   that is "calm and satisfying industrialized farming": soft, light art, things you enjoy
   watching grow and flow, no harsh fail states. Every later choice is checked against it.
2. **Name the reference games and say what each one is a reference for.** Grow a Garden is
   the reference for the loop, Islands for how machines and conveyors play, Sol's RNG for the
   UI's look. Say what is *not* borrowed too: Islands' models and Sol's layouts are off limits.
3. **Ask the user the forks, then record them.** Ask only about choices that change the build,
   such as the core loop, one world or a plot each, how players get machines, and whether art
   comes first or gameplay. Put the answers in a **Decisions** table (Question | Choice). If you
   decided something yourself, say so in the doc.
4. **Write the core loop as verbs.** For example: buy seeds, grow, sell, buy machines, automate.
   A second progression, such as mining into crafting into tier 2 machines, should feed back
   into the first one.
5. **Put real numbers in tables.** Crops, prices, grow times, mutations, the machine roster,
   recipes and the level curve all get tables. A table can be reviewed and tuned; prose can't.
   Give each table a formula when one exists (level n costs `100 * n^1.5` XP).
6. **Map the world in the engine's units.** Here that means Build cells (3 studs) inside the
   baseplate's ±256 studs. Draw a text map of the plots, the hub and the shared areas.
7. **List what is cut.** Removing content is a decision too. Git history keeps the old work, so
   say that and move on.
8. **Phase the work so every phase ends playable.** The overhaul used foundation, loop,
   automation, crafting, art, polish. Do gameplay before art and use placeholder models with a
   written mapping (Harvester = Industrial Flower Picker). Add a checkbox to each phase and tick
   it when the phase lands.
9. **Record decisions made during implementation** under the phase that made them, such as a
   transitional recipe, a save-format name or a rule that was deferred. The next phase starts
   from there.

## Rules

- A design doc is the plan, not the map. Once a system exists, the domain doc
  (`docs/<domain>.md`) describes how it works and the design doc points to it.
- Keep each fact in one place. If balance numbers live in code (`Shared/World.CROPS`), the doc
  gives the design intent and names the module.
- Every probability, timer and price has a reason, or it is marked as a first guess to tune
  in the polish phase.
- Check that the loop works out before building it: time to the first sale, time to the first
  machine, and the payback time of each machine at its unlock level. If a step needs hours of
  waiting at level 1, it breaks a calm game.
- Prefer stackable item ids over per-instance data (crop weight was cut so that conveyors,
  stacks and machines keep working). A mutation is its own id (`Carrot+Golden`).
- If an external agent shares the implementation (Codex, see the garden-overhaul memory), hand
  it one phase at a time against the doc. Review the result and verify it in Studio before
  ticking the phase.

## Output

A `docs/<name>.md` with these sections: summary, Decisions, Map, Economy, content tables,
what is cut, Phases (with checkboxes), and implementation decisions. Link it from `CLAUDE.md`.
