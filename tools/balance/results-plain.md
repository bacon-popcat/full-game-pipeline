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
| Level 8 | 79.8 | 42.8 |
| Level 9 | 98.2 | 48.1 |
| Level 10 | 117.8 | 53.5 |
| Level 11 | 130.8 | 60.4 |
| Level 12 | 145.5 | 68.8 |

Beyond level 12 the run is extrapolated, not simulated: the model keeps playing one hour past
level 12 and takes the XP/min earned in that hour (every tier-one machine owned, no new
expansion, no tier-two machines, no rare crops) as a flat rate for all later levels.
| Milestone | Before | After | After lifetime XP |
|---|---:|---:|---:|
| Level 15 (extrapolated) | 202.5 | 105.1 | 17,321 |
| Level 20 (extrapolated) | 344.7 | 213.6 | 44,071 |
| Level 30 (extrapolated) | 838.0 | 692.9 | 162,431 |
| Level 40 (extrapolated) | 1660.3 | 1685.8 | 407,448 |
| Level 50 (extrapolated) | 2863.6 | 3396.2 | 829,520 |
| steady XP/min | 247.1 | 246.8 | |
| hand net coins/min | 346.3 | 171.5 |
| automation net coins/min | 762.1 | 941.9 |
| processors net coins/min | 1345.1 | 1813.0 |

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
First-harvest seed losses before / after: ['Strawberry'] / []
All valued recipes beat their immediate inputs, for every mutation.
