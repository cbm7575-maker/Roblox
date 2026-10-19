# 2. Game passes and cash packs (Creator Hub)

Create these after the private publish (step 1). Prices are the starting prices from your PRD; the
game reads live prices from Roblox, so you can change them later without touching code. Icons are
in `launch/icons/` (512 x 512 PNG).

**Where:** Creator Hub > Creations > Neon Coast > Monetization. Passes: *Passes > Create a Pass*
(upload the icon, name, description), then open the pass and turn on *Item for Sale* with the price.
Cash packs: *Developer Products > Create*. Menu names may have moved slightly; the fields are the same.

## 5 game passes

| Key | Name | Price (Robux) | Icon | Description |
|---|---|---|---|---|
| VIP | VIP | 499 | `pass_vip.png` | +25% cash from heists and arrest bounties, 3 VIP neon paints (Gold, Hot Pink, Aqua) and a gold [VIP] tag in chat. |
| BigDuffel | Big Duffel Bag | 299 | `pass_bigduffel.png` | Carry 50% more loot before you have to bank it: your bag holds $22,500 instead of $15,000. |
| SWATUnit | SWAT Unit | 399 | `pass_swatunit.png` | Unlocks the Riot Truck for the police team: the toughest police vehicle on the coast, built to shove cars and block roads. |
| NeonGarage | Neon Garage | 249 | `pass_neongarage.png` | 6 extra underglow colors for every car: Red, Gold, Blue, Magenta, Teal and Violet. Underglow is still installed per car in the Garage. |
| Hypercar | Hypercar | 599 | `pass_hypercar.png` | The Vortex: the fastest car on the coast, with a 200 top speed. |

Every description matches what the code actually does (checked on 2026-10-19). Your PRD also
mentioned "animated neon patterns" for Neon Garage; those aren't built, so the description leaves
them out. The PRD's **Coast Club** monthly subscription isn't built either, so it isn't on this list.

## 5 cash packs (developer products)

| Key | Name | Price (Robux) | Icon | Description |
|---|---|---|---|---|
| Cash1 | $5,000 Cash | 49 | `cash1.png` | Adds $5,000 to your bank instantly. |
| Cash2 | $18,000 Cash | 149 | `cash2.png` | Adds $18,000 to your bank instantly. |
| Cash3 | $55,000 Cash | 399 | `cash3.png` | Adds $55,000 to your bank instantly. |
| Cash4 | $120,000 Cash | 799 | `cash4.png` | Adds $120,000 to your bank instantly. |
| Cash5 | $250,000 Cash | 1,499 | `cash5.png` | Adds $250,000 to your bank instantly. |

## Send me the IDs

Each pass and product page shows a long number (the asset or product ID). Send them in this form
and I'll put them in `src/shared/Config/Shop.lua`:

```
VIP=
BigDuffel=
SWATUnit=
NeonGarage=
Hypercar=
Cash1=
Cash2=
Cash3=
Cash4=
Cash5=
```

Until an ID is filled in, its shop button says "Coming soon", so nothing breaks in the meantime.

**Test purchases in Studio, not in the live game.** In Studio, purchase prompts are test purchases
and cost nothing. In the live game, even the owner pays real Robux.
