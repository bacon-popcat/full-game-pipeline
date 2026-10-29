---
name: game-design-plan
description: >
  Plan a game, an overhaul or a big feature as a design doc before writing code: the target
  feel, reference games, a decisions table, content tables with real numbers, what gets cut,
  and phases that each end playable. Use when the user asks for a new game or direction
  ("make it like <game>"), an overhaul, a new progression system, a roadmap, or "plan this
  out", or when a request is too big to build in one change.
---

# Game design plan

A design doc decides what to build before anyone builds it. Write it as a file in the repo
(for example `docs/<name>.md`), link it from the project's agent instructions, and keep it
current as phases land.

## Workflow

1. **Name the feel first.** Write one or two sentences about how the game should feel to
   play ("calm and satisfying", "tense and fast", "cozy and social"). Every later choice gets
   checked against this.
2. **Name the reference games and say what each one is a reference for.** One game can be the
   reference for the loop, another for a mechanic, another for the UI's look. Also say what is
   *not* borrowed, such as models, layouts or names, so nobody copies the wrong part.
3. **Ask the user the forks, then record the answers.** Only ask about choices that change the
   build: the core loop, a shared world or one space per player, how players get new things,
   and whether art or gameplay comes first. Put the answers in a **Decisions** table
   (Question | Choice). When you decided something yourself, say so in the doc.
4. **Write the core loop as verbs.** For example: gather, make, sell, upgrade, automate. A
   second progression should feed back into the first, not run beside it.
5. **Put real numbers in tables.** Items, prices, timers, drop rates, unlocks and level
   curves all get tables. A table can be reviewed and tuned; prose can't. Give a formula
   wherever one exists (level n costs `100 * n^1.5` XP).
6. **Map the world in the engine's units.** Draw a text map with sizes, inside the playable
   bounds (shared areas, per-player spaces, spawn).
7. **List what gets cut.** Removing things is a decision too. Version control keeps the old
   work, so say so and move on.
8. **Phase the work so every phase ends playable.** A good default order is foundation, core
   loop, automation or depth, a second progression, art, polish. Do gameplay before art, and
   write down which placeholder stands in for which final asset.
9. **Record decisions made during implementation** under the phase that made them, such as
   a temporary recipe, a save-format version or a deferred rule. The next phase starts from
   those.

## Rules

- A design doc is the plan. Once a system exists, a domain doc describes how it actually
  works, and the design doc points to it.
- Keep each fact in one place. If balance numbers live in code, the doc states the intent and
  names the module that holds the numbers.
- Give every probability, timer and price a reason, or mark it as a first guess to tune in
  polish.
- Check the loop on paper before building it: the time to the first reward, to the first
  upgrade, and the payback time of each upgrade at its unlock level. Any wall that can only
  be passed by waiting, early in the game, needs to be justified.
- Prefer stackable item ids to per-instance data. A variant (a rarity, a mutation, a tier)
  gets its own id, so stacks, storage and automation keep working.
- When another agent shares the implementation, hand it one phase at a time against the doc,
  then review the result and verify it in the engine before ticking the phase.

## Output

The doc, with these sections: summary and feel, Decisions, Map, Economy, content tables,
what gets cut, Phases (with checkboxes) and implementation decisions.
