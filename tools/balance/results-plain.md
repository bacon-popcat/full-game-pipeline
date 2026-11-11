Median of 9 stock rolls; plain; miners 1; quarry share 1; build share 0.5; minutes from join.
Before = before.json with the coin Machine Shop; After = current content, machines crafted.
| Milestone | Before | After |
|---|---:|---:|
| Level 2 | 11.6 | 2.5 |
| Level 3 | 23.5 | 9.2 |
| Level 4 | 32.7 | 16.7 |
| Level 5 | 41.1 | 24.1 |
| Level 6 | 50.6 | 29.3 |
| Level 7 | 64.3 | 36.2 |
| Level 8 | 79.8 | 42.2 |
| Level 9 | 98.2 | 47.5 |
| Level 10 | 117.8 | 52.7 |
| Level 11 | 130.8 | 59.2 |
| Level 12 | 145.5 | 67.1 |

Beyond level 12 the run is extrapolated, not simulated: the model keeps playing one hour past
level 12 and takes the XP/min earned in that hour (every tier-one machine owned, no new
expansion, no tier-two machines, no rare crops) as a flat rate for all later levels.
| Milestone | Before | After | After lifetime XP |
|---|---:|---:|---:|
| Level 15 (extrapolated) | 202.5 | 101.7 | 17,321 |
| Level 20 (extrapolated) | 344.7 | 204.5 | 44,071 |
| Level 30 (extrapolated) | 838.0 | 658.9 | 162,431 |
| Level 40 (extrapolated) | 1660.3 | 1599.6 | 407,448 |
| Level 50 (extrapolated) | 2863.6 | 3220.2 | 829,520 |
| steady XP/min | 247.1 | 260.4 | |
| hand net coins/min | 346.3 | 171.5 |
| automation net coins/min | 762.1 | 941.9 |
| processors net coins/min | 1345.1 | 1926.1 |

Crafted machines, in the order the model builds them (median minutes from join; level then).
Raw is what one costs from an empty inventory, belts included; coal is the Smelter's fuel.
| Machine | Bench tier | Before bought | After crafted | Level then | Raw |
|---|---:|---:|---:|---:|---|
| ShippingBin | 1 | 11.9 | 3.0 | 2 | 3 wood |
| Smelter | 1 | 23.7 | 4.0 | 2 | 16 stone, 1 wood |
| BenchTier2 | 2 | - | 9.2 | 3 | 8 iron, 3 coal, 30 stone, 10 wood |
| Workbench | 2 | 24.4 | 12.0 | 3 | 8 iron, 2 copper, 4 coal, 2 wood |
| SeedPlanter | 2 | 33.0 | 14.8 | 3 | 10 iron, 4 coal, 2 wood |
| Sprinkler | 2 | 41.2 | 16.8 | 4 | 4 iron, 4 copper, 3 coal |
| BenchTier3 | 3 | - | 29.3 | 6 | 48 iron, 12 copper, 20 coal, 8 wood |
| Harvester | 3 | 51.0 | 34.5 | 6 | 17 iron, 4 copper, 7 coal, 5 wood |
| Mill | 2 | 64.3 | 36.4 | 7 | 7 iron, 3 coal, 20 stone, 3 wood |
| Juicer | 2 | 79.8 | 38.7 | 7 | 11 iron, 4 coal, 1 wood, 4 glass |
| CratePacker | 3 | 98.2 | 43.0 | 8 | 17 iron, 6 coal, 5 wood |
| Oven | 3 | 117.8 | 44.9 | 8 | 7 iron, 2 copper, 3 coal, 1 wood, 20 bricks |

To the first Harvester, from nothing: 95 iron, 22 copper, 41 coal, 46 stone, 31 wood.
Hand time gathering (walks, mining, chopping, waiting at rocks) before it: 13.8 of 34.5 min.

Mk II machines (Fabricator), parts only, not crafted in the run; supplied minutes are one
Smelter and one Assembler working serially from ore, excluding mining:
SeedPlanterTier2: {'SteelFrame': 3, 'Gear': 6}, 4.7 min supplied, 24 iron, 8 coal, 3 stone
SprinklerTier2: {'Circuit': 4, 'CopperWire': 6}, 5.0 min supplied, 8 iron, 14 copper, 8 coal
MillTier2: {'SteelFrame': 2, 'Gear': 8}, 4.7 min supplied, 24 iron, 8 coal, 2 stone
HarvesterTier2: {'SteelFrame': 3, 'Circuit': 6}, 7.9 min supplied, 24 iron, 12 copper, 12 coal, 3 stone
JuicerTier2: {'SteelFrame': 2, 'Circuit': 4}, 5.3 min supplied, 16 iron, 8 copper, 8 coal, 2 stone
OvenTier2: {'SteelFrame': 3, 'Circuit': 4}, 6.0 min supplied, 20 iron, 8 copper, 10 coal, 3 stone
First-harvest seed losses before / after: ['Strawberry', 'Corn', 'Pumpkin', 'Watermelon'] / []
Coins a minute from one cell on a Harvester, plain, by rarity (lowest-highest): Common 18-19, Uncommon 55-60, Rare 90-144, Epic 180-200, Legendary 400-520, Mythic 1440-1440
Rarities out-earned by the one below, before / after: ['Uncommon over Rare', 'Rare over Epic'] / []
All valued recipes beat their immediate inputs, for every mutation.

Mid-game products: value over the plain worth of the crops inside (1 machine x1.5, 2 x3, 3 x4.5).
| Product | Machine | Machines deep | Crops inside | Their worth | Value |
|---|---|---:|---|---:|---:|
| Crisps | Roaster | 1 | 2 Potato | 220 | 330 |
| Popcorn | Roaster | 1 | 2 Corn | 720 | 1,100 |
| RoastPumpkin | Roaster | 1 | 1 Pumpkin | 1,600 | 2,400 |
| TomatoSauce | Kettle | 1 | 4 Tomato | 180 | 270 |
| StrawberryJam | Kettle | 2 | 5 Strawberry | 75 | 230 |
| BlueberryJam | Kettle | 2 | 5 Blueberry | 150 | 450 |
| AppleJam | Kettle | 2 | 5 Apple | 450 | 1,400 |
| GrapeJam | Kettle | 2 | 5 Grape | 1,300 | 3,900 |
| Pizza | Oven | 2 | 2 Wheat, 4 Tomato | 204 | 610 |
| PumpkinPie | Oven | 2 | 2 Wheat, 1 Pumpkin | 1,624 | 4,900 |
| StrawberryJamTart | Oven | 3 | 2 Wheat, 5 Strawberry | 99 | 450 |
| BlueberryJamTart | Oven | 3 | 2 Wheat, 5 Blueberry | 174 | 780 |
| AppleJamTart | Oven | 3 | 2 Wheat, 5 Apple | 474 | 2,100 |
| GrapeJamTart | Oven | 3 | 2 Wheat, 5 Grape | 1,324 | 6,000 |
| WatermelonSorbet | Chiller | 2 | 1 Watermelon, 3 Strawberry | 4,045 | 12,000 |
| StarfruitSorbet | Chiller | 2 | 2 Starfruit, 3 Blueberry | 3,690 | 11,000 |

One Harvester Mk II patch (35 cells) of a crop, plain coins a minute: sold raw, and as the
best product it is the main crop of (other inputs grown elsewhere, machines as needed).
| Crop | Rarity | Raw | Best product | Through it | Machines for it |
|---|---|---:|---|---:|---|
| Carrot | Common | 630 | CarrotCrate | 756 | 0.2 CratePacker |
| Wheat | Common | 672 | Flour | 1,120 | 1.9 Mill |
| Strawberry | Uncommon | 2,100 | StrawberryPie | 17,500 | 9.3 Oven |
| Potato | Uncommon | 1,925 | Crisps | 2,888 | 0.9 Roaster |
| Tomato | Rare | 3,150 | Pizza | 10,675 | 2.3 Oven |
| Corn | Rare | 3,150 | Popcorn | 4,812 | 0.4 Roaster |
| Blueberry | Rare | 5,040 | BlueberryPie | 33,600 | 11.2 Oven |
| Pumpkin | Epic | 7,000 | PumpkinPie | 21,438 | 0.6 Oven |
| Apple | Epic | 6,300 | AppleJamTart | 29,400 | 1.9 Oven |
| Watermelon | Legendary | 14,000 | WatermelonSorbet | 42,000 | 0.6 Chiller |
| Grape | Legendary | 18,200 | GrapeJamTart | 84,000 | 1.9 Oven |
| Starfruit | Mythic | 50,400 | StarfruitSorbet | 154,000 | 2.3 Chiller |

Every coin sink: research 5,268,400 + garden sections 1,027,500 = 6,295,900 coins.
One raw Blueberry patch pays for all of it in 20.8 hours.
One raw Apple patch pays for all of it in 16.7 hours.
One raw Grape patch pays for all of it in 5.8 hours.
One raw Starfruit patch pays for all of it in 2.1 hours.
The best patch above (154,000 a minute) pays for all of it in 0.7 hours.

Orders and daily quests against a level (an order asks for Economy.scale coins of goods):
| Level | Order's goods | Order XP | Over selling them | Level costs | Order / level | Day's quests / level |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 2,000 | 400 | +200 | 382 | 105% | 15% |
| 10 | 6,000 | 1,200 | +600 | 1,695 | 71% | 15% |
| 15 | 11,000 | 2,200 | +1,100 | 4,053 | 54% | 15% |
| 20 | 18,000 | 3,600 | +1,800 | 7,523 | 48% | 15% |
| 30 | 35,000 | 7,000 | +3,500 | 17,988 | 39% | 15% |
An order pays 1.5x its goods' coins and 2x their sale XP. In the steady hour the run nets 1,926 coins a minute, so delivering all of it as orders adds at most 193 XP a minute to 260 (74%).
Minutes from join, with orders at that most from level 12 on (the first column is the table above):
| Milestone | No orders | Every sale an order |
|---|---:|---:|
| Level 15 | 101.7 | 86.9 |
| Level 20 | 204.5 | 146.0 |
| Level 30 | 658.9 | 407.5 |
