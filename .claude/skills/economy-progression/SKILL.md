---
name: economy-progression
description: >
  Game economy and progression: a currency service, XP and level curves, item values,
  selling, restocking shops, unlocks gated by level, and balance tables. Use when adding
  coins, gems, XP or levels, a shop, a sell stand or seller block, prices, rewards, unlocks,
  leaderstats, or when tuning balance or reviewing an economy for exploits and dead ends.
---

# Economy and progression

On branch `garden-overhaul`: `Shared/Economy`, `server/services/EconomyService` and the
Economy and Shops sections of `docs/overhaul.md` and `docs/plots.md`. For Robux purchases,
see `roblox-skills:roblox-monetization`; this skill covers soft currency only.

## The service

- **One service owns live balances** and exposes a small API: `get` (returns a copy), `add`,
  `trySpend` and `addXp`. Mutators reject negative, non-integer and non-finite amounts.
  Overspending fails without changing the balance. `trySpend` returns whether it succeeded,
  so a purchase is "spend, and give only if the spend succeeded".
- **No inbound balance remote, ever.** A client asks to buy or sell an item; the server
  prices it, checks the stock and inventory, spends, then gives.
- **The level is derived from XP, never saved.** XP counts up for life; level one starts at
  zero and level n costs `round(100 * n^1.5)` more (`Economy.progress(xp)` returns the level,
  progress and cost). Saving only XP means the level can't disagree with it, and retuning the
  curve moves everyone consistently.
- **Mirror balances for display**: `leaderstats` IntValues (Coins, Level), plus a sync remote
  (`EconomySync {coins, xp, level}`) sent on load and on every change, for the HUD.
- The balances live in the profile (see `player-saves-and-plots`). The economy service
  doesn't save; the data service sends it state and reads snapshots back.

## Content

- **Value lives on content**, such as an item's `value` and a crop's seed price. The price is
  the value times the multiplier for its variant (mutation). Give formulas in the design doc.
- **XP sources** tie into the core loop: harvesting (scaled by rarity), selling (1 XP per 10
  coins). Don't add XP for idle actions that could be farmed.
- **Unlocks** gate by level. Higher tiers also cost crafted parts, so the second progression
  (mining and crafting) feeds the first.
- **Restocking shops**: one restock clock for the whole server, but each player's stock is
  rolled separately (by rarity band, with a chance per band). Save the stock with the restock
  time it belongs to, so rejoining can't reroll it. Show the countdown.
- **Sellers**: a sell stand (sell what you hold, or sell all crops and products) plus an
  automated seller block that pays the block's owner, never whoever fed it.

## Balance

Make a quick table before choosing numbers: unlock level, cost, income per minute, payback
minutes, and the time to reach that level. Aim for:

- a first sale within about a minute and a first machine within the first session;
- machine payback that shortens as tiers rise, so automating always feels like progress;
- no step that only waiting can get past at low levels (it's a calm game, but it shouldn't be
  stalled);
- rare outcomes (Rainbow ×50) that feel great but aren't needed to progress.

Mark first-guess numbers as such and tune them in the polish phase. Keep the numbers in code
(the content tables) and the intent in the design doc.

## Exploit review

- Buy, then sell: a buy price must always be above any sell price for the same id.
- A craft or process chain must never pay out more than its inputs and time are worth,
  unless that's the point. Check every loop through machines.
- Yields: never yield (no `task.wait`, no DataStore or other async call) between a balance or
  stock check and the spend. Another request could pass the same check in between. Spend
  first, then give.
- Drops and trades between plots: drops keep their owner id and other plots can't absorb them.
- Saved balances that aren't valid integers fail the load and keep the original profile, so a
  bad load never overwrites good data.
