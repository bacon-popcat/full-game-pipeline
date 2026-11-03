# Research

`Shared/Research` owns the ordered projects, costs, prerequisites, descriptions, categories,
effect numbers and shared start/duration rules. Crafting recipes (`Shared/Crafting`) name the
project that unlocks them; research stores no recipe links. The Research window shows it all
(§ Window).

## Flow

```text
DataService: assign plot -> ResearchService.load -> restore ground, blocks, crops
    -> inventory/economy/garden/onboarding -> DataReady
Research Start -> readiness/cooldown/id/level/prerequisites/items/coins -> pay -> active -> sync
Research Cancel -> all refund items fit -> refund coins/items -> clear active -> sync
one-second loop, DataReady only -> elapsed project -> done -> Bonuses + BeltSpeed
    -> GardenEvents.ResearchDone -> Notify -> sync
DataService: snapshot research with balances -> clear research before releasing the plot
```

One project runs at a time on fractional Unix seconds. Duration is fixed when it starts,
using the current research-speed bonus. Starting and cancelling validate before changing
anything and do not yield between checks and mutation. Requests share a per-player cooldown;
each one, including a refusal or malformed payload, gets a toast and authoritative snapshot.
Cancellation leaves everything unchanged if the refund cannot fit.

`server/libraries/Bonuses` stores copies of finished ids and summed stats; it imports only
shared modules and Signal. Services read `get` or `at`, and crafting can read `has`, without
requiring ResearchService. `ownerAt` uses Plot's owned-section check and the plot's Owner
attribute. `changed(player)` fires after set/clear. Missing players/stats have zero bonus.
ResearchService publishes the multiplier `BeltSpeed` on the assigned plot model on load and
completion, then removes it before release.

## Remotes

`Shared/Remotes` owns payload contracts; `default.project.json` authors the events.

- `Research`, client to server: `("Start" | "Cancel", id?)`. Start requires a known id.
- `ResearchSync`, server to client: `{done = {id, ...}, active = {id, endsAt, seconds}?,
  bonuses = {[stat] = number}}`. Sent on load, start, cancel, finish and every refusal.
  Finished ids follow catalogue order. The deadline converts saved Unix seconds to
  `workspace:GetServerTimeNow()`, so device clocks do not affect the countdown.
- `Notify` explains successful actions and refusals and announces completion.

## Saving

The profile's `research` defaults to `{done = {}, active = nil}`. Done is an id-to-boolean
map; active holds `{id, startedAt, seconds}`. Snapshots copy both tables. Research loads
immediately after plot assignment, before machines and crops, so restored crops' offline
mutation rolls see finished bonuses. Load never announces garden actions or finishes a
project: the same one-second loop completes an overdue project once DataReady is true,
giving the arriving player its toast once.

Unknown finished ids, malformed entries and unknown/malformed active projects are dropped
with warnings. Active timestamps and durations must be finite, the timestamp nonnegative
and the duration a positive whole second; an already-finished active id is dropped too.
These errors never fail a profile load. Quit, session loss and failed-load cleanup clear
bonuses and the plot multiplier. XP and Shipping Bin fractional carries are session-only
and reset with the profile. See [plots.md](plots.md) for the full lifecycle.

## Effect hooks

All numbers and additive tier totals stay in `Shared/Research`.

| Effect | Runtime owner |
|---|---|
| beltSpeed | `Shared/Factory.beltMultiplier` reads the plot attribute; `FactoryService.stepLanes` scales advance and throw-off; `FactoryController.apply/render` scales every item lane, including machine belts and router arms; `ConveyorRideController.step` scales existing conveyor/router riding |
| machineSpeed | `FactoryService.stepMachines` supplies Machine.Env; `Machine.step` scales recipe-time progression for processors, Workbench and Smelter, including coal burn so fuel per bar stays the same |
| harvesterSpeed | The same Env scales Harvester and Seed Planter progression in `Machine.step` |
| sprinklerRadius | `FactoryService.sprinklerAt` expands the rectangle horizontally, still inside its own plot and at its own level |
| cropYield | `WorldService.harvestCount` rolls floor plus fractional chance; hand `onInteract` and machine `FactoryService.envFor` / `Machine.stepProducer` share that result between capacity and output |
| growSpeed | `WorldService.growthSpeed` multiplies the sprinkler provider; `bankGrowth/grow` bank online credit with rain and update deadlines; offline time stays normal |
| mutationChance | `WorldService.chanceModifiers` supplies the owner's multiplier; `World/Mutations.roll` multiplies every final chance before clamping, including Rainbow, weather and offline always-on rolls |
| sellPrice | `GardenService.sell` floors the boosted whole transaction; `FactoryService.paySale` carries fractional coins per player and bases sale XP on paid coins |
| xpGain | `EconomyService.addXp` multiplies all earned XP and carries its fraction per player |
| seedStock | `GardenService.restock` adds to positive rolls only; load validation allows boosted saved stock |
| researchSpeed | `ResearchService.start` calls `Research.duration` once |
| chopYield / mineYield | `WorldService.onInteract` adds the acting player's bonus to the node's named boost item before checking room |

Unripe digging and uprooting keep their original yields. Full inventories and machine outputs
leave the crop or node intact. Research alone does not make Farmland wet: GroundService's
sprinkler-speed query stays separate from combined growth speed. Sprinkler placing previews
and the machine panel still show the base area; those UI modules are unchanged.
Machine belts retain their existing item-only behavior: enabling player riding there would
change play even with zero research. Their item simulation and drawing still use BeltSpeed.

## Window

`UIController/ResearchScreen` binds the authored `HUD.Research` window, opened by
`SideButtons.Research` from anywhere (HubWindow, with no stalls). `client/libraries/ResearchClient`
keeps the latest ResearchSync. `Body.Tabs.Farming`, `Automation`, `Economy`, `Tools` and
`Crafting` pick a category; its projects are rows cloned from `Assets.UI.Research.Row` (Icon,
Name, Description, Cost, Needs, Start with its Label), lowest level first and finished ones last
and faded. Needs shows the time and any items, or `Research.blocker`'s reason; the button reads
Research, Locked, Busy, Running, Done, Need coins or Need items. `Body.Active` shows the running
project (Text, Time, a Bar with its Fill) and its Cancel. A press waits for the next sync. A
row's icon is an item standing for its line (Belts a belt, Rich Soil a carrot, a crafting
project its recipe's output). A finished project also gets a warm ring and the ResearchDone
sound (FxService `Research`).

```text
StarterGui.HUD.Research [Frame]          cloned from Shop: Header.Title/Close, UIScale
  Body.Tabs.<Category> [TextButton]
  Body.Active [Frame]  Text, Time [TextLabel]; Bar.Fill [Frame]; Cancel [TextButton]
  Body.List [ScrollingFrame]
ReplicatedStorage.Assets.UI.Research.Row [Frame]  Icon, Name, Description, Cost, Needs, Start.Label
StarterGui.HUD.SideButtons.Research [TextButton]  a flask icon, Tooltip
```

Played through in Studio: the window and tabs, a start and its 30 s finish (toast, sync, ring),
a cancel with its exact refund, and research-locked recipes at the Crafting Bench.

## Studio playtest

1. Join old and fresh saves without research; compare normal belts, machines, crops, sales,
   XP and stock. Inspect ResearchSync and BeltSpeed.
2. Start with enough coins/items and verify exact debit/deadline. Test low level, missing
   prerequisites/items/coins, unknown/non-string id, malformed action, spam, another active
   project, already-finished id and DataReady false. Refusals must resync without spending.
3. Cancel with room and a full inventory, including multi-item refunds. Verify exact refunds
   once or no changes, then retry after making room.
4. Finish online and offline, quit/reload another slot and lose the session. Check one
   completion event/toast, saved duration, separate slot bonuses and BeltSpeed removal.
   Load malformed research, unknown ids, NaN/infinite times and already-done active ids;
   expect warnings and a playable garden.
5. Compare two owners' conveyor/router/machine item lanes, drawing and throw-off, plus
   conveyor/router riding.
   Check processor/Workbench/Smelter timing and coal per bar, Planter/Harvester intervals,
   and sprinkler reach at owned-section boundaries.
6. Hand/machine harvest with fractional yield and nearly full inventory/output; harvest by
   hand while a Harvester waits. Check all-or-nothing output and one XP award. Verify normal
   unripe digging/uprooting, growth with rain/sprinklers, normal offline growth, and every
   mutation during Golden Hour, storms and offline ripening.
7. Compare Sell Stand totals and repeated low-value sales from several Shipping Bins for
   one player. Check fractional coin/XP carry, all XP sources, positive/zero stock rolls,
   same-window rejoin and study speed on new projects.
8. Two players chop/mine shared nodes with different research: only the acting player's
   named drop increases; full inventory leaves the node intact.

Formatting, lint and static checks do not replace these Studio tests.
