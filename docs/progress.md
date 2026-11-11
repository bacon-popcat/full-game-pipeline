# Progress

`Shared/Progress` owns the ordered stats, achievement tiers, the daily quest pool, the rules
for orders, rewards and save sanitization. `ProgressService` owns live progress for each loaded
garden. Content names, goals, level gates and every number belong in that shared module, not
in this document; [retention.md](retention.md#orders-dailies-and-achievements-phase-r3) gives
the reasons for them.

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
| Sold | salesCoins increases by sale proceeds, including Shipping Bins; an order's pay is not a sale |
| Earned / Spent | coinsEarned / coinsSpent increases by successful positive EconomyService additions / spends |
| An order delivered / a daily quest claimed / an achievement unlocked | One ordersFilled / questsCompleted / achievementsUnlocked |

Playtime banks elapsed whole seconds while DataReady, carrying fractional seconds between
ticks. Loading, the save menu and offline time do not count. Live rewards and refunds count
as coins earned; load-time rewards do not, because DataReady is still false.

## Achievements

Achievements unlock when their lifetime stat reaches the goal. The service marks the id
before awarding coins and XP through EconomyService, then sends an Achievement notice.
Reward-triggered stat changes are checked too. Loading checks all saved totals, so a newly
introduced achievement can unlock immediately, but an already-unlocked id never pays again
(so one unlocked before its reward was raised keeps what it paid then). A family has three
tiers, or four where a factory can keep counting.

## Daily quests

Three a UTC day, drawn without repeats from the pool's quests at or under the player's level.
An entry saves the level it was drawn at; its goal and reward come from that level, so they do
not move as the player levels during the day. A goal grows by the quest's kind: stats a factory
raises by the level band's machine multiplier, hand actions by its gentler one, sales from
`Economy.scale`, and some not at all. A new quest starts at its stat's current value. Done
means the increase since then has reached the goal: the first time sends a Quest notice, and a
quest already done when saved stays claimable without repeating it.

A claim pays coins and XP once and counts the completion. The claim that finishes the day's
third quest also rolls a bonus seed; if the seed cannot fit, that claim is refused with a
notice and nothing is paid. When the saved quests belong to another day (on load, or as the
clock passes midnight UTC while the garden is open), every quest that was done and unclaimed is
paid, the bonus too when it fits, and three new ones are drawn. Nothing is lost by missing a
day.

## Orders

Each garden has three order slots. An order asks for one item and a count, to be delivered from
the inventory, and never expires. What can be asked for:

- Carrot and Wheat (always), and the produce of every crop the garden has discovered;
- a valued product whose machine the garden has had (its Index holds the machine or its Mk II)
  and whose every input is itself on this list;
- one order in five, a mutated crop the garden has found, in a small count.

No two slots ask for the same item. The count is sized so the goods are worth about
`Economy.scale(level)`; items whose count would hit the limits are passed over when another
fits. When everything the garden can make is already asked for, the slot waits and tries again.

**Deliver** checks the inventory holds the count, and that the bonus seed fits when this is a
fifth order, then takes the items, pays coins and XP, counts the order, announces
`GardenEvents.OrderFilled` and draws the next order, without yielding. The reward is worked out
from the item's value when it is shown and when it is paid, so a retuned value moves it.
**Skip** empties the slot for `Progress.SKIP_SECONDS`; the service's one-second loop refills
slots whose wait is over. Every fifth order filled also gives a seed one rarity above the best
crop discovered.

## Saving and remotes

Each profile has `progress = { stats = {[id] = number}, achievements = {[id] = true},
daily = { day = number, quests = {{id, start, level, claimed}}, bonus = boolean },
orders = {{item, count} | {waitUntil}} }`. DataService reconciles and sanitizes it, loads
ProgressService after EconomyService and GardenService (orders read the garden's discoveries
and Index), snapshots it with balances, and releases it during cleanup. Missing stats become
zero; unknown ids, invalid numbers, malformed or duplicate daily quests are dropped, and an
order for an item that no longer exists or has no value becomes a waiting slot. Saves from
before daily quests held `quests`, the three endless slots; that field is dropped, unpaid.
Snapshots copy every nested save table. Other profile lifecycle rules are in
[plots.md](plots.md).

`Shared/Remotes` owns the payload contracts; `default.project.json` authors both events.
`Progress(action, slot)` takes "ClaimDaily", "DeliverOrder" or "SkipOrder" with a whole
in-range slot, DataReady and a per-player cooldown. A well-formed request is always answered
with a `ProgressSync`, so a pending button wakes; a malformed one is ignored. `ProgressSync`
sends stats, unlocked ids, each daily quest's text, clamped progress, goal, reward and whether
it is done or claimed, each order's item, count and reward (or its wait), the orders left
before a bonus seed, and a server timestamp for client playtime extrapolation. Deadlines travel
on `workspace:GetServerTimeNow()`'s clock, not Unix time. Ordinary changes coalesce at most
twice a second; playtime alone syncs at most once per thirty seconds. Load and every request
sync immediately. Queued syncs cannot outlive their garden state. Notice kinds belong to
`Shared/Notices`.

## Screens

The side `SideButtons.Menu` button opens `HUD.Menu`, a small popup whose rows (Index, Achievements,
Stats, Robux Shop, Settings) open those windows through `libraries/Screens.open`, so the Menu requires
none of their controllers (`UIController/MenuScreen`). `SideButtons.Quests` toggles
`HUD.Quests` directly through its HubWindow, and the hub's Orders Board (`Hub.STALLS.OrdersBoard`,
the `OrdersBoard` prop: a notice board whose counter holds the prompt) opens it on the Orders tab. `QuestsScreen` updates
the button's gold `Badge.Count` on every progress sync and inventory change, even while closed:
daily quests waiting to be claimed plus orders the inventory can fill. Zero hides the badge and
counts above nine show `9+`. `libraries/ProgressClient` holds the latest ProgressSync and
extrapolates playtime between syncs.

- `HUD.Achievements` (`AchievementsScreen`): a Summary line and one
  `Assets.UI.Progress.Achievement` row per achievement, in `Shared/Progress` order, with its
  goal, a progress bar and the reward; unlocked rows turn gold.
- `HUD.Quests` (`QuestsScreen`): `Body.Tabs.Daily` and `Orders` switch between `Body.Daily`
  (one `Assets.UI.Progress.Quest` row per daily quest, with a Claim button that wakes once the
  quest is done and reads Claimed afterwards) and `Body.Orders` (one `Assets.UI.Progress.Order`
  row per slot: the item's `Icon`, "Pumpkin x24", the reward, how many the inventory holds,
  `Deliver` and `Skip`; a waiting slot shows `Wait`, counting down). `Body.Hint` says when the
  daily quests change and how many orders are left before a bonus seed.
- `HUD.Stats` (`StatsScreen`): a "Now" heading (level, coins) and "All time" with every stat,
  from `Assets.UI.Progress.Heading` and `Stat`; time played counts up while it is open.

Each is a HubWindow with the Crafting window's shell. `tools/hud/progress_hud.luau` authors
them, their templates, the Menu and Quests side buttons and the Crafting window in the place
file; its header says how to run it. It builds the Quests window with its old single list, so
run `tools/hud/quests_hud.luau` after it for the tabs, the two lists and the Order row (it
clones what progress_hud made, and is safe to rerun), then `tools/hud/sidebar_hud.luau` (and
after `shop_hud.luau`) to add the Robux Shop row and the Crafting side button.

## Studio playtest

Played through on 2026-11-09, on a fresh garden in an empty save slot (deleted after) and read
on an older level-32 save:

- The older save dropped its endless quests and got three daily quests at its level's goals and
  rewards ("Chop 30 trees", 19,000 coins and 1,033 XP each) and three orders it could make
  (Golden Potato x4, Pumpkin x24, Grape Juice x33), which were still there next session.
- The fresh garden got base-goal quests, orders for Wheat x13 and Carrot x9, and a third slot
  waiting. A delivery five carrots short was refused with a notice; the wheat order paid 234
  coins and 31 XP and was replaced; a skip left its slot counting down from five minutes.
- Three daily quests, finished through announced actions, each paid once (a second claim and a
  fractional slot did nothing); the third gave a bonus seed and the Little Adventures I
  achievement. The fifth order gave a Potato seed (one rarity above the garden's best).
- A reload kept the day's quests and the orders. A save moved back a day paid its done,
  unclaimed quest and drew three more at the new level's goals.
- The Orders Board's prompt opened the window on Orders after Daily had been left open; the
  side button's badge showed 1 with a fillable order.
- A garden at onboarding step 23 that had filled an order moved to step 24 on load.

Still to verify: the midnight roll while a garden is open (it runs the same code as the load
roll, reached from the one-second loop); a waiting slot refilling when its five minutes end;
an order for a processed product delivered from a real line; a full inventory refusing a bonus
seed; bad actions and spam from a second client; gamepad focus and a phone-sized screen.
