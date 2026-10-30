# Polish verification

The work remains on `garden-overhaul`; no commit, push or branch switch was made.
Only the task's allowlisted files were edited by this implementation. Other working-tree
changes belong to the concurrent effects/sound work.

## Executed checks

- `python tools/balance/model.py --runs 9`: passed; output in `results-ev.md`.
- `python tools/balance/model.py --plain --runs 9`: passed; output in `results-plain.md`.
- Additional minimum-stock EV/plain runs: level 6 at 42.4/47.6 minutes; level 10 at
  180.3/218.6. Set each loaded rarity band's `max` to its `min` before `Model.run`.
- The model asserts nonnegative wallets, at most 96 planted cells, every valued recipe's
  premium over its inputs for every mutation, Common/Uncommon first-harvest payback, and
  20-30 minute serial supplied crafting for each tier-two bundle.
- Selene 0.31.0 over `src`: 0 errors, 0 warnings, 0 parse errors.
- Rojo 7.7.0 sourcemap generation: passed. The `rojo` command on PATH is an Aftman shim
  whose tool is not installed; used the existing RoKit executable with the same arguments.
- StyLua 2.5.2: formatted `src` with allowlist globs; edited files pass. Full-tree check
  still reports `src/client/controllers/BuildController.luau` and
  `src/server/services/BuildService.luau`. They are outside the edit allowlist.
- Luau LSP 1.69.0 with `sourcemap.json` and the supplied
  `$LOCALAPPDATA/Temp/claude_globalTypes.d.luau`: no diagnostics in this change's files;
  the full analysis still fails on the unrelated diagnostics below.
- `git diff --check`: passed.

## Unrelated type diagnostics left untouched

| File | Lines | Diagnostic |
|---|---|---|
| `src/client/libraries/BlockText.luau` | 77 | Optional string used as a string key |
| `src/client/libraries/BlockText.luau` | 87, 90, 170, 173, 175 | Inferred string does not narrow to `"Left" \| "Right"` |
| `src/client/controllers/UIController/MachinePanel.luau` | 501 | Generalized iteration over array-or-empty-table union |
| `src/server/libraries/Machine.luau` | 294, 296 | Boolean inference does not narrow to `Recipe \| false` / `Recipe?` |
| `src/server/services/DropService.luau` | 302 | Generalized iteration over array-or-empty-table union |
| `src/server/services/FactoryService.luau` | 1136, 1139 | Generalized iteration over array-or-empty-table union |

## Runtime work remaining

Studio was not driven while Claude was authoring the place file. The onboarding scenario,
rejoin/duplicate-event checks, late/missing HUD and reduced-motion checks are listed in
`docs/economy.md`. Real-session economy pacing, belt buffering, quarry supply and
mobile/controller layout still need Studio validation. Static checks and an EV simulation
do not establish runtime correctness or observed player pacing.
