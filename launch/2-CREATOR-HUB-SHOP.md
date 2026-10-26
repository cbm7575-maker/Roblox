# 2. Game passes and cash packs (Creator Hub)

Create these after the private publish (step 1). Prices are the starting prices from your PRD (the
same numbers are in `Price` in `src/shared/Config/Shop.lua`, which the shop shows until an ID is in);
once an ID is in, the game reads the live price from Roblox, so you can change prices later without
touching code. Icons are in `launch/icons/` (512 x 512 PNG).

**Where:** Creator Hub > Creations (switch to NightShift Dev if it's a group) > your game (Theft Miami Coast) > Monetization. Passes: *Passes > Create a Pass*
(upload the icon, name, description), then open the pass and turn on *Item for Sale* with the price.
Cash packs: *Developer Products > Create*. Menu names may have moved slightly; the fields are the same.

## 5 game passes

| Key | Name | Price (Robux) | Icon | Description |
|---|---|---|---|---|
| VIP | VIP | 499 | `pass_vip.png` | +25% cash from heists and arrest bounties, 3 VIP neon paints (Gold, Hot Pink, Aqua) free on every car you own, and a gold [VIP] tag in chat. |
| BigDuffel | Big Duffel Bag | 299 | `pass_bigduffel.png` | Carry 50% more loot before you have to bank it: your bag holds $33,000 instead of $22,000. |
| SWATUnit | SWAT Unit | 399 | `pass_swatunit.png` | Unlocks the Riot Truck for the police team: the toughest police vehicle on the coast, built to shove cars and block roads. |
| NeonGarage | Neon Garage | 249 | `pass_neongarage.png` | 6 extra underglow colors for every car: Red, Gold, Blue, Magenta, Teal and Violet. Underglow is still installed per car in the Garage. |
| Hypercar | Hypercar | 599 | `pass_hypercar.png` | The Vortex hypercar (125 mph top speed), yours right away with no saving up. |

Every description matches what the code actually does (checked again on 2026-10-26: the bag is
$22,000, $33,000 with the pass; the Vortex is not the fastest car, two heist-unlocked cars beat it, and
saying otherwise would be pay-to-win advertising). Your PRD also
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

PHONE > SHOP lists all 5 passes and all 5 cash packs with these prices. Until an ID is filled in,
a player's button says SOON (the row reads "COMING SOON"), so nothing breaks in the meantime. Once an
ID is in, the button says BUY (Roblox's own purchase prompt) and the shop shows the live price.

**Free for you.** In Studio (Play or Play Here) every pass and cash pack has a green FREE button and
the shop says "STUDIO TEST": no Roblox prompt, granted instantly (passes last for that test session,
since Studio saves nothing). In a live server the game's owner (you, if the game is on your account,
or the owner of the group that owns it, rank 255) gets every pass automatically on join, and each cash
pack has a FREE button ("YOUR GAME" at the top of the shop); free cash goes into your real save. The
server checks this itself, so nobody else can use those buttons. This means you never see the real
purchase prompt yourself: to test a real purchase, ask a friend (or use a second account) once the IDs
are in. Everyone else pays real Robux.
