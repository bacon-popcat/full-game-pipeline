"""Garden progression model. Run from the repo root: python tools/balance/model.py

Standard library only; --capture-before writes the immutable pre-polish input fixture.
--runs N samples N reproducible seed-shop rolls; --plain disables mutation EV.
Current numbers are read from the Luau owners, not copied into this script. before.json
is historical evidence, not runtime content. Results are estimates, not Studio timings.

Policy: 50 coins and the actual starter seeds, 96 cells, 2 s per hand action,
20 s round-trip hub travel, Sell All roughly once a minute, buy seeds one per click.
Fill a modest garden with 12 Wheat and 24 Strawberry cells, using starter Carrots
until they are spent. No Rare+ seeds are purchased. Stock rolls use every rarity's
actual bands and 300 s restocks; a fresh window begins at join (conservative).
Buy one of each tier-one machine at unlock, farming equipment before optional
storage/crafting, and two 25-coin belts per farm/processing machine. After buying
the Harvester, tend one 20-cell patch (12 Wheat, 8 Strawberry) automatically;
stop hand harvesting to leave time for building/mining/exploring. The remaining
soil is expansion headroom, not assumed free income. One sprinkler covers this
compact patch; its centre is within 3 cells of all 20 crop centres. A Harvester
within 4 cells services it. Planter handles initial filling, not free new seeds.

One Mill/Juicer/Crate Packer/Oven, actual recipe times, same-variant fractional
EV inventories, one 60-item/min Shipping Bin. No mixed-mutation batches. Mutations
are expected fractional yields, never sampled jackpots; fractional rare batches
must accumulate before processing. Overflow stays queued. Plain mode proves the
path needs no rare seeds or mutations. Weather growth is omitted conservatively;
mutation EV uses clear weather for the first 10 min, then long-run event weights.
Tier-two affordability is a separate wallet observation, not another purchase;
parts timing is a serial upper bound for one supplied Smelter + Workbench, including
recursive ingredients and coal, excluding quarry travel and ore contention.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from copy import deepcopy
import json
import math
from pathlib import Path
import random
import re
import statistics

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ACTION = 2
TRAVEL = 20
CELLS = 96
HORIZON = 12 * 60 * 60
VARIANTS = ("Plain", "Wet", "Shocked", "Golden", "Rainbow")


def source(path):
    return (ROOT / path).read_text(encoding="utf-8-sig")


def number(text, pattern):
    match = re.search(pattern, text, re.S)
    assert match, pattern
    return float(match[1])


def counts(text):
    return {key: int(value) for key, value in re.findall(r'(\w+)\s*=\s*(\d+)', text)}


def read_content():
    world = source("src/shared/World/init.luau")
    crops = {}
    pattern = r'(\w+) = defineCrop\(\s*"[^"]+",\s*"(\w+)",\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(nil|\d+)'
    for key, rarity, price, value, grow, amount, regrow in re.findall(pattern, world):
        crops[key] = dict(rarity=rarity, price=int(price), value=int(value), grow=int(grow),
                          yield_count=int(amount), regrow=None if regrow == "nil" else int(regrow))
    assert len(crops) == 12
    content = source("src/shared/Economy/Content.luau")
    rarities = {}
    for key, body in re.findall(r'\t(\w+) = \{ ([^\n]+) \}', content):
        rarities[key] = {field: number(body, rf'\b{field} = ([\d.]+)')
                         for field in ("xp", "min", "max", "chance")}
    shops = source("src/shared/Economy/Shops.luau")
    offers = {}
    for key, price, level, category, parts in re.findall(
        r'offer\("(\w+)", (\d+), (\d+), "(\w+)"(?:, \{ ([^}]+) \})?\)', shops
    ):
        offers[key] = dict(price=int(price), level=int(level), category=category, parts=counts(parts))
    blocks = source("src/shared/Factory/Blocks.luau")
    products = source("src/shared/Factory/Products.luau")
    recipes = {"Flour": dict(machine="Mill", value=number(products, r'value = (\d+)'),
                             inputs={"Wheat": 2}, time=number(products, r'time = ([\d.]+)'))}
    for fruit in re.search(r'local JUICE_FRUITS = \{([^}]+)', products)[1].split(","):
        fruit = fruit.strip(' "')
        recipes[fruit + "Juice"] = dict(machine="Juicer", inputs={fruit: int(number(products, r'JUICE_FRUIT_COUNT = (\d+)'))},
            value=math.floor(crops[fruit]["value"] * number(products, r'JUICE_MULTIPLIER = ([\d.]+)') + .5),
            time=number(products, r'machine = "Juicer".*?time = ([\d.]+)'))
    for fruit, value in counts(re.search(r'local PIES[^=]*= \{([^}]+)', products)[1]).items():
        recipes[fruit + "Pie"] = dict(machine="Oven", inputs={"Flour": 1, fruit: 2}, value=value,
                                     time=number(products, r'machine = "Oven".*?time = ([\d.]+)'))
    for crop, data in crops.items():
        recipes[crop + "Crate"] = dict(machine="CratePacker", inputs={crop: int(number(products, r'CRATE_SIZE = (\d+)'))},
            value=data["value"] * number(products, r'CRATE_MULTIPLIER = ([\d.]+)'),
            time=number(products, r'machine = "CratePacker".*?time = ([\d.]+)'))
    for key, ingredients, seconds in re.findall(r'part\(\s*"(\w+)",\s*"[^"]+",\s*"[^"]+",\s*\{([^}]+)\},\s*(\d+)', products):
        recipes[key] = dict(machine="Workbench", inputs=counts(ingredients), time=int(seconds), value=0)
    assert len([r for r in recipes.values() if r["machine"] == "Workbench"]) == 4
    economy = source("src/shared/Economy/init.luau")
    data = source("src/server/services/DataService.luau")
    mutations = source("src/shared/World/Mutations.luau")
    rewards = [int(v) for v in re.findall(r'reward = (\d+)', source("src/shared/Onboarding.luau"))]
    return dict(crops=crops, rarities=rarities, offers=offers, recipes=recipes,
        coefficient=number(economy, r'math.round\(([\d.]+) \* level'),
        exponent=number(economy, r'level \^ ([\d.]+)'),
        starter_coins=number(data, r'local PROFILE_TEMPLATE.*?coins = (\d+)'),
        starter_seeds={key: int(value) for key, value in re.findall(r'itemId = "(\w+)Seeds", count = (\d+)', data)},
        restock=int(number(content, r'RESTOCK_SECONDS = (\d+)')),
        harvest_seconds=number(blocks, r'Harvester = harvester\(\d+, ([\d.]+)\)'),
        plant_seconds=number(blocks, r'SeedPlanter = planter\(\d+, \d+, ([\d.]+)\)'),
        growth_speed=number(blocks, r'Sprinkler = sprinkler\(\d+, ([\d.]+)'),
        wet=number(blocks, r'Sprinkler = sprinkler\(\d+, [\d.]+, ([\d.]+)'),
        smelt_seconds=number(blocks, r'recipe\(\{ IronOre = 1 \}, \{ IronBar = 1 \}, ([\d.]+)\)'),
        coal_seconds=number(blocks, r'Coal = ([\d.]+)'),
        multipliers={"Plain": 1, **{key: int(value) for key, value in re.findall(r'(\w+) = \{ multiplier = (\d+)', mutations)}},
        rewards=rewards)


def parts_time(config, parts):
    raw = Counter()
    bench_seconds = 0

    def expand(item, amount):
        nonlocal bench_seconds
        recipe = config["recipes"].get(item)
        if recipe and recipe["machine"] == "Workbench":
            bench_seconds += recipe["time"] * amount
            for ingredient, count in recipe["inputs"].items():
                expand(ingredient, count * amount)
        else:
            raw[item] += amount

    for item, amount in parts.items():
        expand(item, amount)
    smelt = (raw["IronBar"] + raw["CopperBar"]) * config["smelt_seconds"]
    return dict(minutes=(smelt + bench_seconds) / 60, raw=dict(raw), coal=math.ceil(smelt / config["coal_seconds"]))


class Model:
    def __init__(self, config, seed=0, plain=False):
        self.c = config
        self.rng = random.Random(seed)
        self.plain = plain
        self.coins = config["starter_coins"]
        self.xp = 0
        self.level = 1
        self.threshold = self.required(1)
        self.seeds = Counter(config["starter_seeds"])
        self.plants = []
        self.stock = {}
        self.owned = set()
        self.bought = {}
        self.afford = {}
        self.wallet_at_unlock = {}
        self.levels = {}
        self.hand = defaultdict(float)
        self.queue = defaultdict(float)
        self.jobs = {}
        self.hand_at = TRAVEL // 2
        self.harvest_at = 0
        self.plant_at = 0
        self.hopper = Counter()
        self.sell_at = 60
        self.bin_remainder = 0
        self.step = 0
        self.met = set()
        self.stats = defaultdict(lambda: [0, 0., 0.])
        self.time = 0

    def required(self, level):
        return math.floor(self.c["coefficient"] * level ** self.c["exponent"] + .5)

    def event(self, name):
        self.met.add(name)
        sequence = ("buy", "plant", "harvest", "sell", "level", "bin", "place")
        while self.step < len(sequence) and sequence[self.step] in self.met:
            self.coins += self.c["rewards"][self.step]
            self.step += 1

    def gain_xp(self, amount):
        self.xp += amount
        while self.xp >= self.threshold:
            self.level += 1
            self.levels[self.level] = self.time / 60
            self.threshold += self.required(self.level)
            self.event("level")
            for item, offer in self.c["offers"].items():
                if offer["level"] == self.level:
                    self.wallet_at_unlock[item] = self.coins

    def stage(self):
        if "Mill" in self.owned:
            return "processors"
        return "automation" if "Harvester" in self.owned else "hand"

    def sale(self, amount, stand):
        self.coins += amount
        self.stats[self.stage()][1] += amount
        if stand:
            self.gain_xp(math.floor(amount / 10))
            self.event("sell")
        else:
            self.bin_remainder += amount
            xp = math.floor(self.bin_remainder / 10)
            self.bin_remainder -= xp * 10
            self.gain_xp(xp)

    def distribution(self):
        if self.plain:
            return {"Plain": 1}
        wet = self.c["wet"] if "Sprinkler" in self.owned else 0
        golden, shocked = .01, 0
        if self.time >= 600:
            wet += .25 * (120 + 90) / (3 * 600)
            shocked = .05 * 90 / (3 * 600)
            golden += .04 * 60 / (3 * 600)
        return dict(Plain=1 - wet - golden - shocked - .001, Wet=wet, Shocked=shocked, Golden=golden, Rainbow=.001)

    def price(self, item, variant):
        base = self.c["crops"].get(item) or self.c["recipes"][item]
        return base["value"] * self.c["multipliers"][variant]

    def harvest(self, plant, automatic):
        crop = self.c["crops"][plant[0]]
        target = self.queue if automatic else self.hand
        for variant, probability in self.distribution().items():
            target[plant[0], variant] += crop["yield_count"] * probability
        self.gain_xp(self.c["rarities"][crop["rarity"]]["xp"])
        self.event("harvest")
        if crop["regrow"] or automatic:
            plant[1] = crop["regrow"] or crop["grow"]
        else:
            self.plants.remove(plant)

    def desired(self):
        present = Counter(p[0] for p in self.plants)
        if "ShippingBin" not in self.owned:
            return {"Strawberry": max(0, 1 - present["Strawberry"] - self.seeds["Strawberry"])}
        return {"Wheat": max(0, 12 - present["Wheat"] - self.seeds["Wheat"] - self.hopper["Wheat"]),
                "Strawberry": max(0, (8 if "Harvester" in self.owned else 24) - present["Strawberry"] - self.seeds["Strawberry"] - self.hopper["Strawberry"])}

    def buy_machine(self):
        order = ("ShippingBin", "SeedPlanter", "Sprinkler", "Harvester", "Mill", "Juicer", "CratePacker", "Oven", "Smelter", "Workbench", "StorageChest")
        for item in order:
            offer = self.c["offers"][item]
            if item in self.owned or offer["level"] > self.level:
                continue
            belts = 0 if item in ("Sprinkler", "Smelter", "Workbench", "StorageChest") else 2 * self.c["offers"]["ConveyorBelt"]["price"]
            if self.coins < offer["price"] + belts:
                continue
            self.coins -= offer["price"] + belts
            self.owned.add(item)
            self.bought[item] = self.time / 60
            self.hand_at = self.time + TRAVEL + 4 * ACTION
            if item == "ShippingBin":
                self.event("bin")
                self.event("place")
            if item == "Harvester":
                # Extra soil is available for expansion, not assumed to be automated.
                present = Counter()
                for plant in self.plants:
                    present[plant[0]] += 1
                    plant[2] = present[plant[0]] <= {"Wheat": 12, "Strawberry": 8}.get(plant[0], 0)
            return True
        return False

    def process(self):
        for machine in ("Mill", "Oven", "Juicer", "CratePacker"):
            if machine not in self.owned:
                continue
            if machine in self.jobs:
                end, item, variant = self.jobs[machine]
                if self.time < end:
                    continue
                self.queue[item, variant] += 1
                del self.jobs[machine]
            for item, recipe in self.c["recipes"].items():
                if recipe["machine"] != machine:
                    continue
                # Reserve wheat for flour, and fruit for pies once the Oven is owned.
                if machine == "CratePacker" and item == "WheatCrate":
                    continue
                for variant in VARIANTS:
                    if machine == "Juicer" and "Oven" in self.owned and self.queue["Strawberry", variant] < 4:
                        continue
                    if machine == "CratePacker" and item == "StrawberryCrate" and self.queue["Strawberry", variant] < 14:
                        continue
                    if all(self.queue[ingredient, variant] + 1e-9 >= count for ingredient, count in recipe["inputs"].items()):
                        for ingredient, count in recipe["inputs"].items():
                            self.queue[ingredient, variant] -= count
                        self.jobs[machine] = (self.time + recipe["time"], item, variant)
                        break
                if machine in self.jobs:
                    break

    def retained(self, item):
        return ((item == "Wheat" and "Mill" in self.owned)
                or (item == "Strawberry" and "Juicer" in self.owned)
                or (item == "Flour" and "Oven" in self.owned))

    def tick(self):
        self.stats[self.stage()][0] += 1
        if self.time % self.c["restock"] == 0:
            for item, crop in self.c["crops"].items():
                band = self.c["rarities"][crop["rarity"]]
                self.stock[item] = self.rng.randint(int(band["min"]), int(band["max"])) if self.rng.random() < band["chance"] else 0
        speed = self.c["growth_speed"] if "Sprinkler" in self.owned else 1
        for plant in self.plants:
            plant[1] = max(0, plant[1] - (speed if plant[2] else 1))
        if self.time >= self.plant_at and len(self.plants) < CELLS:
            item = next((item for item, count in self.hopper.items() if count), None)
            if item:
                self.hopper[item] -= 1
                self.plant(item)
                self.plant_at = self.time + self.c["plant_seconds"]
        if "Harvester" in self.owned and self.time >= self.harvest_at:
            ripe = next((p for p in self.plants if p[2] and p[1] <= 0), None)
            if ripe:
                self.harvest(ripe, True)
                self.harvest_at = self.time + self.c["harvest_seconds"]
        self.process()
        if "ShippingBin" in self.owned:
            left = 1.
            for (item, variant), count in list(self.queue.items()):
                if self.retained(item):
                    continue
                amount = min(left, count)
                if amount > 0:
                    self.queue[item, variant] -= amount
                    self.sale(amount * self.price(item, variant), False)
                    left -= amount
                if left <= 1e-9:
                    break
        for item, offer in self.c["offers"].items():
            if self.level >= offer["level"] and self.coins >= offer["price"]:
                self.afford.setdefault(item, self.time / 60)
        if self.time < self.hand_at:
            return
        if self.time >= self.sell_at and sum(self.hand.values()) > 0:
            self.sale(sum(count * self.price(item, variant) for (item, variant), count in self.hand.items()), True)
            self.hand.clear()
            self.hand_at = self.time + TRAVEL + ACTION
            self.sell_at = self.time + 60
            return
        if self.buy_machine():
            return
        # Buy an initial carrot to perform onboarding without spending the whole wallet.
        wanted = {"Carrot": 1} if "buy" not in self.met else self.desired()
        for item, count in wanted.items():
            price = self.c["crops"][item]["price"]
            if count and self.stock[item] and self.coins >= price:
                self.stock[item] -= 1
                self.seeds[item] += 1
                self.coins -= price
                self.stats[self.stage()][2] += price
                self.hand_at = self.time + ACTION
                # Shopping while already at the hub is batched; one trip per stock window.
                if getattr(self, "shop_window", -1) != self.time // self.c["restock"]:
                    self.shop_window = self.time // self.c["restock"]
                    self.hand_at += TRAVEL
                self.event("buy")
                return
        if len(self.plants) < CELLS:
            for item in ("Carrot", "Wheat", "Strawberry"):
                if self.seeds[item] > 0:
                    if "SeedPlanter" in self.owned:
                        amount = min(10, self.seeds[item])
                        self.hopper[item] += amount
                        self.seeds[item] -= amount
                        # Two actions allow loading and repositioning its 15-cell patch.
                        self.hand_at = self.time + 2 * ACTION
                        return
                    self.seeds[item] -= 1
                    self.plant(item)
                    self.hand_at = self.time + ACTION
                    self.event("plant")
                    return
        if "Harvester" not in self.owned:
            ripe = next((p for p in self.plants if p[1] <= 0), None)
            if ripe:
                self.harvest(ripe, False)
                self.hand_at = self.time + ACTION

    def plant(self, item):
        covered = sum(p[2] and p[0] == item for p in self.plants) < {"Wheat": 12, "Strawberry": 8}.get(item, 0)
        self.plants.append([item, self.c["crops"][item]["grow"], covered])

    def run(self):
        for self.time in range(HORIZON):
            self.tick()
            assert len(self.plants) <= CELLS and self.coins >= -1e-9
            if self.level >= 12:
                break
        return dict(levels=self.levels, afford=self.afford, bought=self.bought, wallet_at_unlock=self.wallet_at_unlock,
                    rates={stage: (gross - seeds) * 60 / seconds for stage, (seconds, gross, seeds) in self.stats.items() if seconds})


def audit(config):
    values = {key: crop["value"] for key, crop in config["crops"].items()}
    values.update({key: recipe["value"] for key, recipe in config["recipes"].items()})
    losses = []
    for key, recipe in config["recipes"].items():
        if recipe["value"]:
            cost = sum(values[item] * count for item, count in recipe["inputs"].items())
            assert recipe["value"] > cost, (key, cost, recipe["value"])
            for multiplier in config["multipliers"].values():
                assert recipe["value"] * multiplier > cost * multiplier
    for key, crop in config["crops"].items():
        if crop["rarity"] in ("Common", "Uncommon") and crop["value"] * crop["yield_count"] < crop["price"]:
            losses.append(key)
    return losses


def median(results, group, key):
    values = [r[group][key] for r in results if key in r[group]]
    return statistics.median(values) if len(values) == len(results) else None


def fmt(value):
    return "unreached" if value is None else f"{value:.1f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-before", action="store_true")
    parser.add_argument("--runs", type=int, default=9)
    parser.add_argument("--plain", action="store_true")
    args = parser.parse_args()
    assert args.runs > 0
    current = read_content()
    if args.capture_before:
        assert not (HERE / "before.json").exists(), "Never overwrite historical input"
        baseline = deepcopy(current)
        baseline["rewards"] = [0] * 7
        (HERE / "before.json").write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
    before = json.loads((HERE / "before.json").read_text(encoding="utf-8"))
    print(f"Median of {args.runs} stock rolls; {'plain' if args.plain else 'mutation EV'}; minutes from join.")
    results = [[Model(config, seed, args.plain).run() for seed in range(args.runs)] for config in (before, current)]
    print("| Milestone | Before | After |\n|---|---:|---:|")
    for level in range(2, 13):
        print(f"| Level {level} | " + " | ".join(fmt(median(r, "levels", level)) for r in results) + " |")
    for stage in ("hand", "automation", "processors"):
        print(f"| {stage} net coins/min | " + " | ".join(fmt(median(r, "rates", stage)) for r in results) + " |")
    print("\n| Machine | Level | Before coin-affordable | After coin-affordable | After bought | Parts min before / after |\n|---|---:|---:|---:|---:|---:|")
    for item, offer in current["offers"].items():
        if offer["category"] not in ("Machine", "Crafting", "Router", "Conveyor"):
            continue
        timing = " / ".join(fmt(parts_time(c, c["offers"][item]["parts"])["minutes"]) for c in (before, current)) if offer["parts"] else "-"
        purchase = fmt(median(results[1], 'bought', item)) if offer["category"] in ("Machine", "Crafting") and not offer["parts"] else "not purchased"
        print(f"| {item} | {offer['level']} | {fmt(median(results[0], 'afford', item))} | {fmt(median(results[1], 'afford', item))} | {purchase} | {timing} |")
    print("\nShipping Bin wallet at level 2:", " / ".join(fmt(median(r, "wallet_at_unlock", "ShippingBin")) for r in results))
    print("First-harvest seed losses before / after:", audit(before), "/", audit(current))
    assert not audit(current), "A Common/Uncommon seed must repay in one plain harvest"
    print("All valued recipes beat their immediate inputs, for every mutation.")
    for item, offer in current["offers"].items():
        if offer["parts"]:
            print(item, parts_time(current, offer["parts"]))
            assert 20 <= parts_time(current, offer["parts"])["minutes"] <= 30


if __name__ == "__main__":
    main()
