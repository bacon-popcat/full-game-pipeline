# Welcome back

`Shared/Welcome` owns the daily gift cycle, the offline-coin share, cap and buckets, and the
save's shape. `WelcomeService` applies them for each loaded garden. Every number belongs in the
shared module; [retention.md](retention.md#daily-gift-welcome-back-and-offline-coins-phase-r4)
gives the reasons.

## Flow

```text
DataService: ... plot, research, economy, garden, progress, onboarding -> WelcomeService.load
    -> a new UTC day: one more day played, its gift owed
    -> away 10 minutes or more, a bin rate and a Shipping Bin placed: offline coins owed
    -> WelcomeSync (greet: show the card) -> DataReady -> the client opens the card
Welcome "Collect" -> the gift's seed fits? -> clear what is owed -> pay coins, give the seed
    -> WelcomeSync
while open: Shipping Bin sales -> the current five-minute bucket -> finished buckets (six kept)
DataService snapshot: leftAt = now, binRate = the buckets' median once three are in
```

## Daily gift

The first load on a UTC day counts one more day played and owes that day's gift, in a cycle of
seven: coins scaled by level (`Economy.scale`) on days 1, 3 and 5, seeds on the others, a
Legendary on day 7 and a Mythic on every fourth cycle's. It counts days played, not days in a
row, so a missed day costs nothing. A gift not yet collected stays owed and the count waits
with it: the next day's gift comes only after it is taken, so none is skipped. A garden's
first day, and an older save's first day since gifts existed, has no gift.

A seed gift is one random crop of its rarity, rolled when it is collected.

## Offline coins

While a garden is open the service adds its Shipping Bin sales (`GardenEvents.Sold` with a
position) to a five-minute bucket and keeps the last six finished ones. Time in the save menu
restarts the bucket. When the garden is saved its `binRate` becomes the buckets' median as
coins a minute, once at least three are in; a shorter visit keeps the rate it loaded with. A
median, so a stockpile fed to the bins just before leaving does not raise it.

On load, a garden away ten minutes or more, with a rate and a Shipping Bin placed, is owed
`OFFLINE_SHARE * binRate * min(minutes away, OFFLINE_CAP_MINUTES)` coins. It is an estimate:
no belt or machine is simulated, nothing is taken from the garden, and crops still grow offline
as they always did. Offline coins give no XP and are not sales.

## Collecting

Nothing is paid on load. What is owed is saved (`giftOwed`, `coinsOwed`), so closing the card,
leaving, or a crash loses nothing; coins from several absences add up. `Welcome("Collect")`
checks DataReady and a cooldown, then that a seed gift fits; if it does not, a notice says so
and everything stays owed. Otherwise it clears what is owed, adds the coins through
EconomyService and gives the seed, without yielding, and answers with a `WelcomeSync`.

## The card

`WelcomeSync` carries `greet` (only the load sync asks for the card), the seconds away, how many
crops are ripe (`WorldService.ripeCount`), a research project waiting for Complete, the coins
owed and the gift owed. `UIController/WelcomeScreen` opens `HUD.Welcome` about 2.2 seconds
after DataReady when greeted (after the loading screen has faded): when a gift or coins are owed,
or the garden was away ten minutes or more. `Body` holds `Away` (a line), `Rows` (`Crops`,
`Research`, `Coins`: a notice-kind icon, a coloured stripe and a rich-text line), `Gift` (the
day's reward over a `Track` of seven day pips: past days dim, today bright and pulsing, days to
come outlined in their gift's colour) and `Collect`, which reads Close when nothing is owed. Each
part shows only when it has something to say, and the card's height follows what is shown.
Opening plays the motion: the rows and gift pop in one after another and coin amounts count up;
while open the header's sunburst turns and a shine sweeps the gift and the button. Colours come
from `Shared/TextColors`. Returning to the save menu forgets the greeting.
`tools/hud/welcome_hud.luau` authors the card in the place file as a gold clone of the Quests
window's shell; run it after progress_hud, quests_hud and notice_hud.

## Saving

The profile's `welcome = { days, giftDay, giftOwed, leftAt, binRate, coinsOwed }`
(`Welcome.sanitize` makes every field a finite, non-negative number). `leftAt` is the Unix time
of the last save while the garden was open, so after a crash the time away counts from the last
autosave.

## Studio playtest

Played through on 2026-11-09 on a fresh garden in an empty save slot (deleted after):

- A fresh garden and an older save were not greeted on their first day.
- A garden saved as last open three hours ago, yesterday, on its second day, with a rate of
  1,000 a minute and a bin placed, opened the card with "You were away for 3h 0m.", 45,000
  coins and "Day 3 gift · 300 coins". Collect paid 45,300 coins once and closed the card.
- A day-2 gift (one Rare seed) left uncollected was still owed after quitting to the save menu
  and reloading, once; Collect gave Blueberry Seeds. Reloading again the same day showed no card.
- On the older save, seen as last open an hour ago, the card read "44 crops are ready to
  harvest." and "Green Thumb II is ready to complete in Research.", with Close.
- The rules were checked directly: the seven-day cycle with its Mythic on day 28, no coins under
  ten minutes, the eight-hour cap, and a median that ignores one large bucket.

Still to verify: buckets filling and the rate changing over a real fifteen minutes of bin
sales; a real overnight absence; a full inventory refusing a seed gift; the card on a
phone-sized screen and with a gamepad.
