# Progress

`Shared/Progress` owns the ordered stats, achievement tiers, quest pool, rewards and save
sanitization. `ProgressService` owns live progress for each loaded garden. Content names,
goals and level gates belong in that shared module, not in this document.

## Counting

Only live `server/libraries/GardenEvents` actions with a loaded state and DataReady count.
Restoring inventory, crops, ground, research or balances never announces these actions.

| Evidence | Stat change |
|---|---|
| Harvested, by hand or machine | One cropsHarvested; one mutatedHarvested when mutation is present, regardless of yield |
| Planted / Tilled / Watered | One seedsPlanted / groundTilled / cropsWatered |
| Chopped / Mined | One treesChopped / rocksMined; WorldService announces non-Axe node breaks, GroundService also announces dug ground as Mined |
| Crafted | itemsCrafted increases by Shared/Crafting's output count times the number of crafts; belt processors do not announce Crafted |
| ResearchDone / Placed / SectionBought | One researchDone / blocksPlaced / sectionsBought |
| Bought | itemsBought increases by the purchased item count |
| Sold | salesCoins increases by sale proceeds, including Shipping Bins |
| Earned / Spent | coinsEarned / coinsSpent increases by successful positive EconomyService additions / spends |
| Successful quest claim / achievement unlock | One questsCompleted / achievementsUnlocked |

Playtime banks elapsed whole seconds while DataReady, carrying fractional seconds between
ticks. Loading, the save menu and offline time do not count. Live rewards and refunds count
as coins earned; load-time rewards do not, because DataReady is still false.

## Achievements and quests

Achievements unlock when their lifetime stat reaches the goal. The service marks the id
before awarding coins and XP through EconomyService, then sends an Achievement notice.
Reward-triggered stat changes are checked too. Loading checks all saved totals, so a newly
introduced achievement can unlock immediately, but an already-unlocked id never pays again.

Load preserves valid active quests, including ones above the player's current level, and
fills empty slots with uniformly random eligible definitions, without duplicate active ids.
A new quest starts at its stat's current value. Done means the increase since that baseline
has reached its goal. The first transition sends a Quest notice; an already-done saved
quest remains claimable without repeating that notice on load.

A valid claim pays coins and XP, counts the completion, sends a Reward notice and replaces
that slot. The replacement excludes other active ids and avoids the claimed id whenever
another eligible choice exists. It starts after the claim's rewards and achievements settle.
Chopping and basic crafting use the level-one access gates in `Shared/Economy/Shops`;
research quests start with the research system's early level gates.

## Saving and remotes

Each profile has `progress = { stats = {[id] = number}, achievements = {[id] = true},
quests = {{id = string, start = number}} }`. DataService reconciles and sanitizes it, loads
ProgressService after EconomyService, snapshots it with balances, and releases it during
cleanup. Missing stats become zero; unknown ids, invalid numbers, malformed quests and
duplicate active quest ids are dropped. Quests are kept in slot order up to the slot limit.
Snapshots copy every nested save table. Other profile lifecycle rules are in [plots.md](plots.md).

`Shared/Remotes` owns the payload contracts; `default.project.json` authors both events.
`Progress("ClaimQuest", slot)` accepts only a whole in-range slot, DataReady and a completed
quest, with a per-player cooldown. Invalid requests have no reply or reward.
`ProgressSync` sends stats, unlocked ids, clamped quest progress and a server timestamp for
client playtime extrapolation. Ordinary changes coalesce at most twice a second; playtime
alone syncs at most once per thirty seconds. Load and successful claims sync immediately.
Queued syncs cannot outlive their garden state. Notice kinds belong to `Shared/Notices`.

## Studio playtest

1. Load a new and an old garden. Check all stats and three different eligible quests; till,
   plant, water, harvest, chop, mine ground and quarry nodes, buy, sell, place, research and
   craft. Craft Wood Planks several times and verify output units, not recipe executions.
2. Reach an achievement and finish a quest. Check each notice once, claim once, verify
   balances/XP, completion counts and replacement baseline. Spam claims and send bad actions,
   strings, fractional slots, NaN, infinity, out-of-range slots and unfinished quests.
3. Rejoin with both unfinished and done quests; progress and achievements must persist,
   done quests must not re-notify, and rewards must not repeat. With Studio mock saves,
   quit/reload in the same server; cross-server persistence needs API access (plots.md).
4. Switch saves while a sync is queued; check isolation and no menu/offline playtime.
   Watch remote traffic during idle play and rapid actions for the two sync intervals.

## Screens

The side `SideButtons.Menu` button opens `HUD.Menu`, a small popup whose rows (Achievements,
Stats, Settings) open those windows through `libraries/Screens.open`, so the Menu requires
none of their controllers (`UIController/MenuScreen`). `SideButtons.Quests` toggles
`HUD.Quests` directly through its HubWindow. `QuestsScreen` updates that button's gold
`Badge.Count` from `ProgressClient.claimable()` on every progress sync, even while closed;
zero hides the badge and counts above nine show `9+`. Menu has no quests row or badge.
`libraries/ProgressClient` holds the latest ProgressSync and extrapolates playtime between syncs.

- `HUD.Achievements` (`AchievementsScreen`): a Summary line and one
  `Assets.UI.Progress.Achievement` row per achievement, in `Shared/Progress` order, with its
  goal, a progress bar and the reward; unlocked rows turn gold.
- `HUD.Quests` (`QuestsScreen`): one `Assets.UI.Progress.Quest` row per active slot, with a
  Claim button that wakes once the quest is done.
- `HUD.Stats` (`StatsScreen`): a "Now" heading (level, coins) and "All time" with every stat,
  from `Assets.UI.Progress.Heading` and `Stat`; time played counts up while it is open.

Each is a HubWindow with the Crafting window's shell. `tools/hud/progress_hud.luau` authors
them, their templates, the Menu and Quests side buttons and the Crafting window in the place
file; its header says how to run it. After syncing code, run that builder once in Studio's
Edit datamodel (no other HUD builder is needed for this change), then playtest. Rerunning
replaces both buttons and rebuilds Menu without its old Quests row, preserving side-button
size and spacing. Check a second run for duplicates, and check Quests toggle/close, switching
to other windows, and badge changes after completing and claiming a quest.
