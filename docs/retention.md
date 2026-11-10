# Retention plan

The plan for keeping players past the first hour and bringing them back the next day. It
follows the 2026-11-09 review of the loop: the first 45 minutes are dense, then levels 13-50
unlock only research percentages, guidance stops at minute 5, quests pay seconds of income,
some rare seeds lose money, late crops need no new factory, and nothing rewards coming back.
[overhaul.md](overhaul.md) stays the design of what is built; this doc is the target for what
comes next. Nothing here is built yet.

**Feel.** Still calm and satisfying. There is always one visible next thing to do, a level-up
always opens something you can build, and coming back is a pleasant surprise, never a
punishment for having been away.

## References

| Game | Reference for | Not borrowed |
|---|---|---|
| Grow a Garden | Excitement at rare seed stock, server-wide rare-harvest notices, gifting | Pets, stealing, its mutation list, its UI |
| Factory builders (Islands, Satisfactory) | Deliveries that ask for a specific product, so a line gets rebuilt | Their machines, models and recipe names |
| Stardew Valley | A calm request board with no failure | Its characters and items |
| Idle games | A welcome-back card with capped earnings | Streak resets, timers that take rewards away |

## Decisions

| Question | Choice | Who |
|---|---|---|
| Daily layer | Gentle: three daily quests, a daily gift that counts days played and never resets, a welcome-back card | User |
| Offline | Capped earnings: a share of recent Shipping Bin income for up to 8 hours away, an estimate and not a belt simulation | User |
| Social | Light plus gifting: rare-harvest notices, hub leaderboards, garden likes, one-way gifts of crops and seeds with daily caps. No trading | User |
| Levels 13-40 | Recipes and machines on the existing twelve crops; no new crops | User |
| Guidance | The Objective panel never empties: the authored goal chain runs to the first Mk II machine, then it shows the next level unlock | Claude |
| Repeatable quests | The three endless slots become the three daily quests; Orders are the endless source of tasks | Claude |
| Level gates for new content | Research "plans" projects in the Crafting fan, the way the Mk II machines are gated now. No fifth crafting tier | Claude |
| Rock Drill | Moves from Machine Works to Workshop, so it can feed the biggest iron bill instead of arriving after it | Claude |
| Left out | Prestige or rebirth, trading, new mutations, pets, new crops, monetization changes | Claude |

## The loop

```text
grow -> process -> deliver (an order, or sell) -> level up -> unlock a machine or recipe -> rebuild the line
                                                     ^
return next day -> collect (offline coins, daily gift) -> take the dailies -> play the loop
```

Orders are the second progression feeding the first: they pay more than selling, pay double
XP, and ask for products the player's newest machine makes, so each unlock is followed by a
reason to use it.

## Map

Hub additions, in world studs (the hub band is z -36 ... 36; first-guess spots, to check in
Studio against the paving and lamp posts):

```text
 x = -72        -48        -24 (Seed, Gear)     0 (spawn)     24 (Sell, Robux)     84 ... 120 (quarry)
     Leaderboards  Orders Board
     (0, z 0)      (0, z 0)
```

Each garden's sign gains a Like prompt for visitors and shows the garden's likes. Everything
else is reached from the side buttons, as shops are now.

## Economy

One scale is shared by orders, dailies and the daily gift, so rewards keep up with the player:

`V(level) = 150 * level^1.6` coins, rounded to two significant figures.

| Level | 1 | 5 | 10 | 12 | 20 | 30 | 40 | 50 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V | 150 | 2,000 | 6,000 | 8,000 | 18,000 | 35,000 | 55,000 | 78,000 |

Reason: through level 12 this is 3 to 6 minutes of the balance model's income (270 a minute by
hand, 2,200 with processors). Past level 12 the model has no income figure, so the exponent is
a first guess until the model has a late-game policy (phase R5).

### Goal chain (phase R1)

`Shared/Onboarding.STEPS` grows past step 8. Rewards are one to two minutes of income at the
stage the model reaches each step.

| Step | Goal | Evidence | Coins |
|---:|---|---|---:|
| 9 | Craft a Smelter from 16 Stone and 4 Wood Planks | Crafted or owns Smelter | 100 |
| 10 | Smelt an Iron Bar: load the Smelter with Iron Ore and Coal | Has had IronBar (the Index set) | 100 |
| 11 | Reach level 3 and upgrade crafting to Workshop | Crafting tier >= 2 | 250 |
| 12 | Craft an Assembler and place it | Placed Workbench | 250 |
| 13 | Make a Gear in the Assembler | Has had Gear | 150 |
| 14 | Craft a Seed Planter | Crafted or owns SeedPlanter | 300 |
| 15 | Finish a research project | researchDone >= 1 | 200 |
| 16 | Craft a Sprinkler | Crafted or owns one | 250 |
| 17 | Craft a Rock Drill | Crafted or owns one | 250 |
| 18 | Reach level 6 and upgrade crafting to Machine Works | Crafting tier >= 3 | 1,000 |
| 19 | Craft a Harvester and place it behind your crops | Placed Harvester | 1,000 |
| 20 | Sell 50 items through a Shipping Bin | Bin sales this garden | 500 |
| 21 | Craft a Grain Mill and mill some Flour | A Mill on the plot finished Flour | 750 |
| 22 | Craft a Baking Oven and bake a pie | An Oven on the plot finished a pie | 1,500 |
| 23 | Reach level 9 and upgrade crafting to Fabricator | Crafting tier >= 4 | 2,500 |
| 24 | Build your first Mk II machine | Crafted or owns any Mk II | 4,000 |

R3 inserted "Open Quests and deliver an order" (1,000 coins) before the Fabricator goal, as
step 23, with a saved-step migration like the one layout 5 did.

The chain pays 14,100 coins over about 70 minutes, roughly a fifth of what the model earns in
that time. A goal with progress shows it in place of the step count ("12 / 50 sold"). After
step 24 the panel shows the next level that opens something and the XP left ("Level 13:
Haggling II", "1,240 XP to go"), read from `Shared/Unlocks`.

No save migration: a finished save holds step 9, which becomes the first new goal, and restored
evidence (crafting tier, placed blocks, the Index set, research) skips what is already done.
Steps 21 and 22 need processors to announce a finished batch through GardenEvents.
[economy.md](economy.md#onboarding) describes what is built.

The level-up toast (`FxService.levelMessage`) also names research projects that open at the
level; today levels past 9 only say "Level 13!".

**Rock Drill at Workshop.** It costs 16 iron, 4 copper, 7 coal and 2 stone and digs about 3
Iron Ore a minute. The model reaches Workshop at 8.5 minutes and Machine Works at 28; a drill
placed by minute 14 has dug about 42 iron by then, against the upgrade's 48. First guess: it
needs a timed playtest, and the model does not include drills.

### Crops and products (phase R2)

Rules: a single crop's seed repays its price in one plain hand harvest (the harvest spends
it; a multi crop keeps its plant); coins per cell per minute on a Harvester rise with rarity; a product is worth its raw inputs times 1.5 after one machine, 3
after two and 4.5 after three. Crates stay at 1.2 as the fallback for any crop.

| Crop | Seed | Value | Coins/cell/min, was | now | Hand profit per harvest, was | now |
|---|---:|---:|---:|---:|---:|---:|
| Potato | 60 | 70 -> 110 | 35 | 55 | 10 | 50 |
| Tomato | 150 | 35 -> 45 | 70 | 90 | - | - |
| Corn | 250 | 160 -> 360 | 40 | 90 | -90 | 110 |
| Pumpkin | 1,200 | 1,100 -> 1,600 | 138 | 200 | -100 | 400 |
| Watermelon | 6,000 -> 3,000 | 3,500 -> 4,000 | 350 | 400 | -2,500 | 1,000 |

Unchanged: Carrot 18, Wheat 19, Strawberry 60, Blueberry 144, Apple 180, Grape 520, Starfruit
1,440 coins per cell per minute. After the change the bands are Common up to 19, Uncommon
55-60, Rare 90-144, Epic 180-200, Legendary 400-520, Mythic 1,440.

| Product | Was | Now | Reason |
|---|---|---|---|
| Juice | 3.5x one fruit, from three | 4.5x | One machine is 1.5x; today it adds 17% and is never worth building |
| Pies | 250 / 400 / 600 | unchanged | The first hour is tuned round them; Strawberry and Blueberry Pie sit above the rule on purpose, as the reward for the first two-machine line |

The model's assertion that Common and Uncommon seeds repay in one harvest widens to every
single crop, and it gains a second: no rarity out-earned per cell by the one below. The model plants no Rare seeds, so its milestone table moves only through the Juicer.

Also in this phase: a notice when the player's restock rolls an Epic or better seed ("A
Legendary seed is in stock: Watermelon"), so a rare roll is seen and not found by chance.

### Orders, dailies and achievements (phase R3)

**Orders.** Three open orders per garden, in the Quests window (tabs Daily and Orders) and at
the Orders Board. Each asks for one item the player can make: a discovered crop, or a product
whose machine recipe is unlocked for them. One order in five asks for a mutated crop the
player has found.

| Number | Value | Reason |
|---|---|---|
| Goods value of an order | `V(level)`, as a count of `ceil(V / item value)`, clamped to 3 ... 200 items | A few minutes of a running line |
| Coins | 1.5x the goods' sell value | Has to beat the Shipping Bin to be worth carrying |
| XP | Goods value / 5 | Twice a sale's XP |
| Every fifth order | Also a seed one rarity above the best crop discovered (Mythic at most) | A way past stock luck that play earns |
| Skip | Replaces the order after 5 minutes | No expiry and no failure |

Deliver takes the items from the inventory in one transaction; nothing is taken from belts or
bins. New stat `ordersFilled`, with achievement tiers.

**Dailies.** Three per UTC day from the present quest pool, replacing the endless slots. Goals
scale by level band: x1 for levels 1-4, x4 for 5-11, x12 for 12-24, x30 from 25 (as built, only
for stats a factory raises; see this phase's implementation decisions). Each pays
`V(level) / 2` coins and 5% of the current level's XP cost. Finishing all three opens a seed:
Rare 60%, Epic 30%, Legendary 9%, Mythic 1% (first guess). Old saves' endless quests are
dropped by sanitization, unpaid (they paid 20 to 80 coins).

**Achievements.** Tier rewards go from 50 / 250 / 2,000 coins and 5 / 15 / 40 XP to 100 /
1,500 / 25,000 coins and 10 / 150 / 2,000 XP, and a fourth tier at ten times tier three's goal
pays 250,000 coins and 10,000 XP. Reason: tier three lands around hours 3-6, where a level
costs 7,000-10,000 XP and 2,000 coins is a minute of income. Unlocked ids never pay again.

### Daily gift, welcome back and offline coins (phase R4)

**Daily gift.** Given on the first load of a UTC day. It counts days played, so a missed day
costs nothing. The cycle repeats every seven days played:

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Gift | V coins | 1 Rare seed | 2V coins | 1 Epic seed | 3V coins | 2 Rare seeds | 1 Legendary seed (every fourth cycle a Mythic) |

**Welcome back.** After 10 minutes or more away, a card shows the time away, crops that
ripened, research waiting for Complete, and offline coins with a Collect button.

**Offline coins.** While the player is online the server keeps Shipping Bin coins in
five-minute buckets. On leaving it saves `binRate`, the median of the last six buckets as
coins a minute (a median so a stockpile dumped into bins before quitting does not count).

`payout = 0.25 * binRate * min(minutes away, 480)`

It is computed on load, saved as pending until collected, gives no XP and needs a placed
Shipping Bin. Crops still ripen offline as now. Worked example: the model's level-12 line
(2,200 a minute) away for eight hours pays 264,000 coins, two hours of active play. That is
the first number to tune; 0.25 and 480 are the user's first guess.

### Mid-game machines and recipes (phase R5)

Three machines and thirteen products, gated by research plans in the Crafting fan, each needing
the one before it (from Crate Making). Costs follow the present research curve at each level.

| Project | Level | Coins | Items | Minutes | Unlocks |
|---|---:|---:|---|---:|---|
| Roaster Plans | 13 | 9,000 | 10 Potato | 10 | Roaster |
| Kettle Plans | 18 | 22,000 | 20 Tomato | 15 | Preserving Kettle |
| Recipe Book I | 22 | 40,000 | 10 Flour | 25 | Oven: Pizza, Pumpkin Pie |
| Recipe Book II | 26 | 70,000 | 5 Strawberry Jam | 40 | Oven: Jam Tarts |
| Chiller Plans | 30 | 100,000 | 4 Circuit | 45 | Chiller |
| Heavy Processor Plans | 35 | 175,000 | 6 Circuit, 4 Steel Frame | 60 | Fruit Press Mk II, Baking Oven Mk II (half the batch time) |

| Machine | Crafting tier | Recipe | Placeholder art |
|---|---:|---|---|
| Roaster | 3 | 20 Bricks, 2 Steel Frame, 4 Gear | The Oven, tinted |
| Preserving Kettle | 3 | 12 Copper Bar, 2 Steel Frame, 4 Glass | The Fruit Press, tinted |
| Chiller | 4 | 4 Steel Frame, 6 Circuit, 8 Copper Wire, 8 Glass | The Crate Packer, tinted |

Product values use the R2 crop values and the 1.5 / 3 / 4.5 rule, rounded:

| Product | Machine | From | Machines deep | Raw value | Value |
|---|---|---|---:|---:|---:|
| Crisps | Roaster | 2 Potato | 1 | 220 | 330 |
| Popcorn | Roaster | 2 Corn | 1 | 720 | 1,080 |
| Roast Pumpkin | Roaster | 1 Pumpkin | 1 | 1,600 | 2,400 |
| Tomato Sauce | Kettle | 4 Tomato | 1 | 180 | 270 |
| Strawberry / Blueberry / Apple / Grape Jam | Kettle | That Juice + 2 fruit | 2 | 75 / 150 / 450 / 1,300 | 225 / 450 / 1,350 / 3,900 |
| Pizza | Oven | Flour + Tomato Sauce | 2 | 204 | 600 |
| Pumpkin Pie | Oven | Flour + Roast Pumpkin | 2 | 1,624 | 4,900 |
| Strawberry / Blueberry / Apple / Grape Jam Tart | Oven | Flour + that Jam | 3 | 99 / 174 / 474 / 1,324 | 450 / 780 / 2,150 / 6,000 |
| Watermelon Sorbet | Chiller | 1 Watermelon + 1 Strawberry Juice | 2 | 4,045 | 12,000 |
| Starfruit Sorbet | Chiller | 2 Starfruit + 1 Blueberry Juice | 2 | 3,690 | 11,000 |

Batch times: Roaster 6 s, Kettle 8 s, Chiller 10 s (first guesses). Products are entries in
`Shared/Factory/Products`, so mutated variants, filters and Shipping Bins work unchanged.

Risk to settle before building: a Starfruit Sorbet line earns about 4,400 coins per Starfruit
cell per minute, three times the raw fruit, and every coin sink in the game totals about 5.9
million (research 4.85 million, sections 1.03 million). Mythic seeds are the brake (2% of
restocks). The model needs a late-game policy (rare crops, these products, research bonuses)
before these values are final, and the plan may need a late coin sink.

### Social (phase R6)

| Piece | Rule |
|---|---|
| Rare-harvest notice | To the whole server when a harvest carries Rainbow, or Golden on an Epic or better crop. At most one per player a minute |
| Leaderboards | Three boards in the hub: lifetime coins earned, crops harvested, garden likes. Global top 10 from OrderedDataStores, written on save, read every 5 minutes |
| Likes | A visitor may like a garden once per UTC day at its sign. The owner gets a notice; the sign shows the total, saved on the owner's profile |
| Gifts | One stack of a crop, product or seed to a player in the same server, from level 5 |

Gift caps, per UTC day: a sender may give goods worth up to `2 * V(sender level)` (sell value,
or seed price), and a receiver takes at most five gifts. The cap follows the sender's level so
a fresh alternate account can pass on about 300 coins of goods a day and never a Legendary
seed. The server checks both players' DataReady, the item id, count, caps and the receiver's
room, moves the stack without yielding, then saves both profiles at once. A crash between the
two saves can duplicate one gift; the value cap bounds it.

## What is cut

- The three endless repeatable quest slots and their flat rewards (dailies and Orders replace them).
- The Rock Drill's place in Machine Works.
- Not planned: prestige, trading, streak resets, new crops, new mutations, pets. Git keeps
  anything removed.

## Phases

Each ends playable and is playtested in Studio before the next starts. Cheap, high-effect
phases come first; the largest content phase waits until the daily layer can hold players.

1. [x] **R1 Goal chain.** Steps 9-24, the progress line, the next-unlock tail, the level-up
   toast naming research, Rock Drill at Workshop. Docs: economy.md § Onboarding, factory.md.
2. [x] **R2 Crops and juice.** The crop and juice values, the widened model assertion, the rare
   stock notice. Rerun `tools/balance/model.py`; update economy.md § Balance and overhaul.md's
   crop table.
3. [x] **R3 Orders, dailies, achievements.** `Shared/Progress` content, the Quests window's two
   tabs, the Orders Board prop (a plain board until it has art). Docs: progress.md.
4. [x] **R4 Daily gift and welcome back.** The gift cycle, the card, bin-rate buckets and
   offline coins. Docs: plots.md (profile fields), economy.md.
5. [x] **R5 Mid-game machines.** The late-game balance policy first, then the six research
   projects, three machines and thirteen products on placeholder art. Docs: research.md,
   factory.md, economy.md.
6. [ ] **R6 Social.** Notices, leaderboards, likes, gifts. Needs API access for
   OrderedDataStores and a two-player playtest. Docs: a new social.md.
7. [ ] **R7 Art and balance pass.** Models for the Roaster, Kettle, Chiller, Orders Board and
   leaderboards, product items, and a timed fresh session to level 20.

Every new saved field (`orders`, `daily`, `away`, `likes`, gift counters) gets a default in
GardenFoundation_v1 and a sanitizer; a bad entry is skipped with a warning (plots.md).

## Open questions

- Is land ever scarce? The free start block is 900 cells and a Harvester tends 15, so the
  1,027,500 coins of sections may not be a goal. Check in the R7 timed session before changing
  section prices or the start block.
- Whether 25% for eight hours of offline coins outruns the sinks (R4's worked example).
- Late-game income against sinks (R5's risk).

## Implementation decisions

### R1 Goal chain (2026-11-09)

- **Goals are data, not named conditions.** Steps 9-24 carry a `goal` (Had, Placed, Tier,
  Research, BinSales) that OnboardingService checks against the garden; steps 1-8 keep their
  named conditions. A later phase adds a goal by adding a row.
- **Sprinkler and Rock Drill are two steps** of 250 coins, since a step has one goal.
- **The order goal waits for R3**, so the chain is 24 steps and pays 13,100 coins.
- **`GardenEvents.Processed`** is new: a recipe machine announces each kind of item a finished
  batch made. Only onboarding listens; Progress stats do not count it yet (R3 can).
- **No tier shortcut.** A step is done only by its own evidence. Crafting past a tier does not
  tick the steps before it, so a player who rushes an upgrade is still shown the Seed Planter,
  Sprinkler and Rock Drill goals.
- **Bin sales resume from the bins' saved `sold` counts** on load, so the 50-sale goal survives
  a rejoin without a new saved field.
- **Progress replaces the step count** in the panel's label, which is authored 86 px wide; no
  place-file change was needed.
- **`Shared/Unlocks`** owns "what a level opens" for the level-up notice and the panel's tail.
  It hides research the Research window still shows as "?".
- **The panel forgets its step when the garden is released.** Before, switching to a save with
  a lower step from the save menu left the old save's objective on screen.
- **Rock Drill at Workshop** is one tier number in `Shared/Crafting`. The balance model does
  not build drills, so its tables are unchanged; whether a drill covers the Machine Works
  iron by minute 28 is for the R7 timed session.
- **Playtest** and what is left to verify: economy.md § Onboarding.

### R2 Crops and juice (2026-11-09)

- **Values as planned**: Potato 110, Tomato 45, Corn 360, Pumpkin 1,600, Watermelon 4,000 with a
  3,000 seed, juice 4.5x. Nothing saved changes: values are read from the tables.
- **The repay rule covers single crops, not every seed.** A multi crop keeps its plant, so its
  seed is an investment (an Apple tree pays back in about eleven harvests); only Common and
  Uncommon multis must repay at the first fruit, as before.
- **The model asserts both rules** and prints the per-cell bands; the historical fixture shows
  what was wrong (Corn, Pumpkin and Watermelon losing; Uncommon over Rare, Rare over Epic).
- **Model movement**: only through the Juicer. Level 12 at 60.3 minutes (was 61.6), processor
  income 2,313 a minute (was 2,198). economy.md § Balance has the tables.
- **The stock notice** names every Epic or better seed in a fresh roll, and again four seconds
  after a garden loads with them still in stock. With two Epic seeds at 25% each, about four
  restocks in nine send one.
- **Playtested**: the new values read in Studio; a natural restock rolled Grape and Pumpkin and
  sent "Legendary seed in stock! Grape Seeds, Pumpkin Seeds"; a reload in the same window sent
  it again after four seconds. Not driven: a real sale of each retuned crop, and a Juicer batch
  (both read the same tables).

### R3 Orders, dailies, achievements (2026-11-09)

- **Goal growth depends on the stat.** The x4 / x12 / x30 bands suit stats a factory raises
  (harvests, crafts, mutated harvests). Applied to hand actions they asked a level-25 player to
  till 600 cells or finish 30 research projects in a day, so hand quests grow x2 / x2 / x3, the
  sales quest asks for three times `Economy.scale`, and the research quest stays at one.
- **The three bigger quests left the pool** (Harvest 100, Sell 5,000, Craft 100): scaling makes
  them the same quests.
- **Mutated orders are small**: a fifth of the usual worth, ten at most. Sized like plain ones,
  a level-12 order asked for 23 Golden Carrots, hours of luck.
- **Carrot and Wheat can always be ordered**, so a fresh garden has two orders before it has
  harvested anything; a slot with nothing left to ask for waits and tries again.
- **A product is orderable when the garden has had its machine** (the Index) and can make its
  inputs, so an order never asks for something out of reach.
- **Bonus seeds must fit.** A delivery or last daily claim that would give one is refused until
  there is room; a day that ends pays its done quests anyway and drops a bonus that cannot fit.
- **Old endless quests are dropped unpaid**, not paid first as planned: their rewards were 20 to
  80 coins and their definitions are gone.
- **Fourth achievement tiers** only where a factory keeps counting: harvests, mutated harvests,
  crafts, sales and research (45 of the 49 projects). Daily quests' third tier is 100, not 250,
  now that three a day is the most.
- **The order goal is step 23** of 25; saves at or past it moved along once (layout 6).
- **Loading order**: ProgressService now loads after GardenService, whose discoveries and Index
  orders read.
- **The Orders Board** is a fifth hub stall at (-48, 0, 0) on the placeholder stall, opening the
  Quests window on Orders. The window's tabs and the Order row are authored by
  `tools/hud/quests_hud.luau`, run after progress_hud.
- **To watch**: orders pay double a sale's XP on goods worth a few minutes of income, so a
  player who sends everything to orders levels about twice as fast. That is the plan's number;
  the R7 timed session should say whether it shortens the first hour too much.
- **Playtest** and what is left to verify: progress.md § Studio playtest.

### R4 Daily gift and welcome back (2026-11-09)

- **Nothing is paid on load.** The gift and offline coins are owed and saved until the player
  presses Collect, so the card can be closed, and a seed gift that does not fit waits.
- **An uncollected gift holds the count.** The next day's gift comes only once the waiting one
  is taken, so the seven-day cycle never skips a day's gift.
- **A garden's first day has no gift**, and neither has an older save's first day with gifts:
  a new player's first minutes stay with the goal chain, and the card first appears on a return.
- **The rate needs three finished buckets** (fifteen minutes of play); a shorter visit keeps the
  rate the garden loaded with. So a quick visit to collect does not wipe the rate, and offline
  coins keep coming from the last real stretch of play. That is the return hook, and also the
  thing to watch with the 264,000-coin example: a player can collect every eight hours without
  playing.
- **Coins from several absences add up** while uncollected; each absence is capped on its own.
- **Offline coins need a Shipping Bin placed at load**, checked once from the plot's blocks.
- **The card also greets with no reward**, after ten minutes away, to say what is ripe and
  whether research is waiting; its button then reads Close.
- **`WelcomeService` and `Shared/Welcome` are their own modules**, loaded last, with `welcome`
  as a new saved field. docs/welcome.md describes what is built, its playtest and what is left
  to verify.

### R5 Mid-game machines (2026-11-09)

- **Sixteen products, not thirteen.** The plan's table listed sixteen; its text miscounted.
- **Values are computed, not written down.** A `chained` product is worth the crops inside it
  times 1.5, 3 or 4.5 by machines deep, to two significant figures, so it follows any crop
  retune. That moved five of the plan's hand-rounded numbers a little: Popcorn 1,100 (was
  1,080), Strawberry Jam 230 (225), Apple Jam 1,400 (1,350), Pizza 610 (600), Apple Jam Tart
  2,100 (2,150).
- **The Recipe Books gate bakes, not crafting recipes.** A product names its research, the
  machine's recipe carries it, and an Oven skips it until its owner has finished the project,
  reading "Needs research" while a batch waits. Orders ask for such a product only once its
  research is done.
- **Fruit Press Mk II and Baking Oven Mk II** are the Heavy Processor Plans' unlock: the same
  recipes in half the time, built on the machine they replace.
- **Placeholder art is a wash, not a repaint.** The Roaster, Kettle and Chiller borrow the Oven,
  Fruit Press and Crate Packer templates and are washed 45% toward their own colour, part by
  part, so they keep their shading and can be told apart. R7 gives them models.
- **The research plans' level gates carry the phase**: 13, 18, 22, 26, 30 and 35, one line in
  the Crafting fan. The level-up notice and the Objective panel's "next unlock" name them
  without further work (Shared/Unlocks).
- **The risk the plan raised is settled, and a bigger one named.** The audit added to the
  balance model (economy.md § Mid-game products and the late game) shows the new chains pay
  within the range the pies already set. It also shows the late game ran out of sinks before
  these products existed: all 6.3 million coins of research and sections are one raw Starfruit
  patch's income for two hours. The values stay on the rule. A late coin sink that keeps going
  is the open item, and it is not part of this plan's phases.
- **Not built**: machine-panel text listing a machine's locked recipes, and animations of the
  borrowed templates beyond what their sources already do.
- **Playtested** on a fresh garden in an empty save slot (deleted after): a Roaster, Kettle,
  Chiller, Baking Oven Mk II and Fruit Press Mk II each ran a real batch (Crisps, Strawberry
  Jam, Watermelon Sorbet, a Strawberry Pie, a Golden Tomato Juice from Golden Tomatoes); a
  Baking Oven holding Flour and Tomato Sauce read "Needs research" and baked a Pizza once
  Recipe Book I was finished; crafting refused the Chiller and the Fruit Press Mk II without
  their plans and made a Roaster with Roaster Plans; the Research window drew the new line off
  Crate Making. Not driven: the items riding belts between these machines, an order for one of
  the new products, and the Recipe Book tiles' icon (added after the session).
