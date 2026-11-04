# 8. Pre-ads audit (Nov 3): Creator Hub fixes, the five test passes, publishing

## Status, Nov 3 evening: live as version 5

The owner gave full access in the evening, and this is what Claude did:
- **Created** the 5 passes and 5 cash packs at the prices in section F. They're on sale, with Managed
  Pricing **off**. Turning it on needs you to accept Roblox's Managed Pricing terms, which is your call.
- **Set** the genre to Action / Open World Action (locked until Dec 3), max players to 30, and Studio API access on.
- **Put** the 10 IDs in `Config/Shop.lua`.
- **Ran** all five test passes below in Studio.
- **Published** version 5.

The start place's name already reads THEFT MIAMI COAST.

**Still yours:**
- **Upload the icon and thumbnails** (A1 and A2). The ready files are `launch/icons/game_icon.png`,
  `launch/thumbnails/thumb1_sunset_ocean_drive.png` and `thumb2_police_flamingo_beach.png`. This needs a
  browser that can attach files, and this session had none.
- **Join the live game once.** When Claude tried, Roblox asked the account to prove it's human.
- **Test a real purchase from a second account.** Your own account owns every pass automatically.

Test results (Studio, Nov 3):
1. **Core:** car, drive, reverse, exit, the ATM robbery, the chase, an arrest on foot, release on time,
   banking, the phone. Plus the tutorial dead end being fixed, the GPS routing itself, and Sea Dream's
   rank 3 lock.
2. **New player:** the owner's live save was effectively new (tutorial step 0), so the whole guide ran
   from the start.
3. **Two players:**
   - An idle cop stops counting after 2 minutes, an AI patrol then comes for the wanted player, and the
     idle cop gets no pay.
   - A car hit on a PASSIVE player does nothing; the same hit without PASSIVE knocks them down.
4. **Money:**
   - Saves carry over between sessions.
   - A Studio test purchase of the $5,000 pack paid $5,000 once, and the receipt was in the real
     DataStore record.
   - The shop shows the live Roblox prices.
5. **Final run:** clean start, and thumbnails captured.

Across all sessions there were no game script errors. The one error seen came from Claude anchoring
cars for a photo.

Found and fixed in play: store signs showed raw `<font color=...>` tags after a site streamed out and
back in (HeistClient).

Not testable here: a phone (Studio's simulator shows the desktop HUD), a gamepad, and a real Robux
purchase.

**Version 6 (Nov 3, later):** the owner played on a phone and reported two problems.
- **It played vertical.** StarterGui.ScreenOrientation was Sensor. It's now LandscapeSensor, set in the
  place and again in ClientMain.
- **There was no clear way to steer.** Phones now get two big ◀ ▶ STEER buttons at the bottom left, eased
  like the keyboard's A and D. The first drive of a session shows a toast: "Steer with ◀ ▶ on the left.
  GAS and BRAKE are on the right." Roblox's thumbstick still works too.

Both were tested in Studio's phone preview (`PreviewTouch`):
- After GAS took the car to 72, holding ▶ turned it right 124 degrees in 1.5 s, and holding ◀ turned it
  left 100 degrees.
- No errors.

Play once on a real phone to confirm.

---

Do it in this order: A (Creator Hub), B (load into Studio), C (the five tests), D (publish), E (ads).

## A. Creator Hub: the store page is empty (about 30 minutes, plus captures)

What a player from an ad sees today: a grey Roblox placeholder for the icon and the thumbnails, no genre,
and a Store tab that says "No passes available". In the game, every SHOP row says COMING SOON.

| # | Where (Creator Hub > Creations > THEFT MIAMI COAST) | Do this |
|---|---|---|
| 1 | Places > the start place > **Icon** > Upload image | `launch/icons/game_icon.png` |
| 2 | Places > the start place > **Thumbnails** > Upload thumbnails | 3 to 5 captures at 1920 x 1080 (how: launch/4). No guns pointed at anyone, nobody lying down, no YOU DIED |
| 3 | **Game details** > Genre | Action, and the open-world subgenre if it's listed. **It can only be changed every 3 months**, so check the list before saving |
| 4 | Monetization > **Passes** > Create a Pass | the 5 passes in launch/2, at the prices in section F if you agree with them; turn on *Item for Sale* |
| 5 | Monetization > **Developer Products** > Create | the 5 cash packs in launch/2 |
| 6 | Places > the start place > Basic Settings > Name | It's still "NightShift_Dev's Place: 11032026_1" (that's in the game's URL): **THEFT MIAMI COAST** |
| 7 | Studio: Game Settings > Places (or the place's settings in the Creator Hub) | Max players **30**, as planned. It's 50 now, which means more cars and people for each phone to draw |
| 8 | Game details > API services | Tick *Enable Studio access to API services* for test C4. A Studio test then saves to the real DataStore (your own record only, while you play alone) |

**Optional, from the Monetization pages:** Roblox offers *Managed Pricing* (regional prices and price
tests). Its page says adopters saw "up to a 10% lift". The game reads live prices from Roblox, so price
changes never need code.

Then send the 10 IDs (the form is in launch/2), or paste them into `Id = 0` in
`src/shared/Config/Shop.lua` yourself.

## B. Load this update into Studio

1. Back up first: close Studio and copy `NeonCoast.rbxl` in File Explorer. A copy of live version 4 is
   already in `Documents\THEFT MIAMI backups\`, and git has tag `pre-audit-2026-11-03`.
2. In the project folder: `python tools/manifest.py` (138 scripts). Then
   `python -m http.server 34999 --bind 127.0.0.1`.
3. Open the published place in Studio and run `print(require(game.ServerStorage.Tools.DevSync).Run())` in
   the command bar. Expect 25 UPD lines (the 24 scripts and the DesignDoc; 26 if Shop.lua has your IDs)
   and no NEW lines.
4. Press Play once: Output shows `[Main] server ready`, no `failed to start`, no red errors.

## C. The five test passes (in Studio, then on your phone)

Write OK or what went wrong for each line. **[new]** marks what this update changed.

### C1. Core gameplay (one player)

1. Drive, drift, nitro, flip, F to get out. Jack a street car (F / JACK) and sell it at the Chop Shop.
2. Rob Glow Mart with a gun on the clerk and without one; lose the cops; bank at the Hideout.
3. 1 star, stand still: the officer cuffs you at street level. **[new]** Stand on a balcony, or behind a
   wall within 5 studs of the officer: no cuffing through the floor or the wall.
4. **[new]** Get tasered: you get up after about 3 seconds, every time.
5. **[new]** An officer starts cuffing you and a friend punches him down (or you're in a crew): your hands
   come down.
6. **[new]** At the Hideout wardrobe while wanted: the first new outfit takes a star, and a second change
   in the same chase doesn't.
7. **[new]** Sea Dream at rank 1 or 2: the sign says RANK 3 NEEDED and both prompts refuse. At rank 3 it
   works as before. PHONE > HOW TO PLAY says "The Coastal Bank and the Sea Dream need rank 3."
8. **[new]** A normal taxi fare and a courier delivery still pay. Win Ocean Drive Sprint flat out with
   nitro: it pays and is never "cancelled".
9. **[new]** Press CAR next to a stunt ramp: the car appears clear of it, never inside it.
10. Night and a storm: does anything look wrong? **[new]** The sun now moves 5 times a second instead of
    every frame, so watch shadows at sunset for any visible stepping.

### C2. New player (fresh save, as someone who has never played)

Studio without API access starts everyone fresh. With API access on, use a second account.
1. **[new]** Title screen: the camera circles without going inside a building. It shouldn't jump in and
   out when it passes lamp posts or palms.
2. PLAY, then step 1: **[new]** the help line now ends "(no car? click CAR)" (on a phone, "tap CAR").
3. **[new]** Step 2 routes the GPS to a store by itself the first time it shows. SHOW ME still works.
4. **[new]** Rob a store, then get arrested before banking. After prison the guide shows "Rob a store..."
   again with SHOW ME. Rob again: it goes back to "bank", and banking moves on to the phone step.
5. **[new]** On a 667 x 375 phone (Device Simulator, or the LocalPlayer attribute `PreviewTouch` = true):
   when a goal's words are cut off, a gold toast shows them in full once.
6. Gamepad: **[new]** the phone step shows a D-PAD DOWN key cap.
7. Time it: from PLAY to driving should be about 15 seconds, and to the first robbery about 2 minutes.

### C3. Multiplayer and griefing (Test > Clients and Servers, 2-3 players)

1. **[new]** Player1 drives into Player2 standing at the spawn, in a shop, with PASSIVE on, or in the same
   crew: Player2 stays standing and takes no damage. In the open street, Player2 falls and is hurt as
   before. A cop's car only knocks down wanted players.
2. **[new]** Two players go on police duty and stand still for 2+ minutes: AI patrols come back for a
   wanted Player3, and the still cops get no patrol pay that minute. Once they drive about, both return.
3. **[new]** Cuffs and the prison vent: a full hold works, and a quick tap does nothing.
4. **[new]** One player is in prison when another leaves the game: the prisoner is still released on time.
5. Race lobby with two players, and a race challenge (K). Both players leave mid-race: no car stays frozen.
6. Watch Output for `[VehicleGuard]`, `[JobService] refused` and `[RaceService] rejected` during normal
   play. Any of those without cheating is a bug to send me.

### C4. Monetization and saving (no real Robux)

1. **[new]** With the IDs in, set the Workspace attribute `RealPrompts` = true in Studio and press Play. The
   SHOP shows BUY instead of FREE, and BUY opens Roblox's own prompt, which Studio runs as a **test purchase
   (never charged)**. Buy Cash1: +$5,000, once. Buy VIP: the [VIP] tag and paints. Without the attribute,
   the FREE buttons are back.
2. With API access on: earn some cash, stop, Play again. The cash, cars and guns are still there.
3. In a live server as the owner you get every pass free, so check what players see from a second account
   (no purchase needed): BUY buttons with prices, no COMING SOON.
4. After the first real purchases, check Creator Hub > Monetization > Developer Products > Analytics.

### C5. Release simulation (live, from your phone)

After D: on your phone (sideways), from the game page as a new player would. Second account if you have
one. Play 15 minutes straight through: tutorial, first goals, a chase, the shop. Type `/console` in chat
and screenshot any red errors. Note the fps if your phone shows Performance Stats.

## D. Publish and check live

1. When C1-C4 pass: in Studio, File > **Publish** (Alt+P). The game is already public, so this updates it
   for everyone. If the window asks about age-restricted content, answer as in launch/5.
2. File > Save to File As > `NeonCoast.rbxl` (keeps git in step), then commit.
3. Do C5. If anything is badly wrong, roll back: Creator Hub > the place > **Version History** > restore
   version 4.

## E. Ads (once A-D are done)

- **Start small.** The game has 0 visits, so there's no retention data yet. Run a small budget for 1-2
  days, then check Creator Hub > Analytics: Day 1 retention, average playtime, and the onboarding funnel
  (`Tutorial_*` and `Journey_*` steps show where new players stop). Scale up only if those look healthy.
- **Age:** only 16+ can join (Audience reach: "Ages 16+ and trusted friends"). Target 16+ if Ads Manager
  allows it, or 18+ if its brackets don't split at 16. Roblox's ad pages don't say they filter this
  for you, and ad spend on players who can't join is wasted.
- **Thumbnails:** up to 10 per campaign at 16:9. Real gameplay of a sunset chase does best for this
  genre, with the same content limits as section A.
- **Devices:** the game was built phone-first, but I couldn't confirm the phone layout has been played
  on a real phone since the October updates (Studio's Device Simulator showed the desktop HUD on Nov 2).
  Play a session on your phone (C5) before targeting phones.
- **Audience:** All Players or New Players (Recent and Lapsed need 10,000 and 20,000 players first).

## F. Price review (your call; prices are set in the Creator Hub)

| Item | Planned | Suggested | Why |
|---|---|---|---|
| VIP | 499 | **399** | A new game with no reviews yet: under 400 is easier for a first purchase. +25% cash is the best long-term value in the shop |
| Big Duffel Bag | 299 | **249** | Only matters once you're robbing $20k+ heists (rank 3) |
| SWAT Unit | 399 | **249** | Only for players on the police job, which is a small share of players |
| Neon Garage | 249 | **199** | Cosmetic only |
| Hypercar (Vortex) | 599 | **499** | Strong early value (125 mph, two heist cars beat it, so it's fair), but 599 is a lot for one car |
| Cash packs | 49 / 149 / 399 / 799 / 1,499 | keep | A good ladder: $102 to $167 per Robux, bigger packs worth more |

Nothing in the shop is pay-to-win: cash packs can't skip heist locks, cop ranks or passes, and no pass
car beats the best earned cars. Offers appear at most once every 10 minutes, never while wanted or
driving fast, never during the tutorial, and each can be hidden for good. Leave that as it is.

## What changed in this update (24 scripts)

**Saving and purchases**
- `DataService`: the final save happens once per player (shutdown used to write each record twice) and is
  retried for about 30 seconds if the DataStore fails. The server waits about 20 seconds (was 10) before
  taking over a record another server still holds. A player who leaves while their save is loading gives
  the lock back, and a save that lands after someone left no longer re-locks their record.
- `ShopService`: a repeat purchase receipt is acknowledged only after a save with it succeeds (before,
  Roblox could be told "granted" for a cash pack that was never saved). A pass check that Roblox doesn't
  answer is asked again each minute, 5 times. Added the Studio test-purchase switch `RealPrompts`.
- `EconomyService`: amounts that aren't a whole number (NaN or infinity) are refused, so they can't get
  stuck in a save.
- `Telemetry`: IDs moved out of event names into custom fields. Roblox keeps only 100 custom event names,
  and the game was making well over 100 (one per rank, challenge, offer, chase result). It also groups
  economy items past 100 as "Other", and car tuning alone made over 200.

**New players**
- `TutorialClient`: no dead end after an arrest on the bank step; the GPS routes by itself on each guide
  step's first showing; cut-off goal text is shown in full once; the CAR hint; the gamepad D-pad hint.
- `TeamUI`: the title camera stays in front of buildings.

**Griefing and exploits**
- `ImpactService`: a car hit knocks someone down only on real contact, and never someone the damage rules
  protect (safe zone, spawn protection, PASSIVE, crewmates, a cop's car against innocents).
  `CombatService` only has a comment updated to match.
- `ArrestService` / `AIPoliceService`: AFK cops no longer switch off AI patrols or earn patrol pay. Cuff
  holds can't be pre-charged. Arrests need the same floor.
- `PoliceOfficerService`: officers don't cuff through floors or walls, and the suspect's hands come down
  when the cuffing stops.
- `PrisonService`: one player's error can't stop releases for the whole server, and the vent hold can't
  be pre-charged.
- `DisguiseService`: one disguise star per chase.
- `LawClient`: you always get up after a taser.
- `JobService`: a fare reached faster than any car could drive it pays nothing, and one player's ended
  shift no longer skips everyone else's that tick.
- `RaceService` / `VehicleGuard`: a race finish or fare after the anti-cheat flagged the car pays nothing.
- `CarjackService`: no car is built for a spot with no room, and refused tries wait 2 seconds.
- `Config/Heists` + `PhoneUI`: Sea Dream needs rank 3, like the bank. Solo from minute one it paid about
  10 times a store run every 5 minutes, which skipped the whole early game.

**Performance (phones)**
- `VehicleVisuals`: parked cars stop casting wheel rays. A street of parked cars cost about 2,400 rays a
  second.
- `WorldService`: the clock is sent 5 times a second instead of every frame.
- `RoadGraph`: the road map is parsed once at start-up instead of four times.
- `VehicleService`: car spawns check for stunt ramps and the other activity props.

## Not fixed (smaller, or needs a decision)

- New players start with PASSIVE off. Turning it on by default until a player's first crime would protect
  newcomers from veterans. That's a design call for you.
- The title screen doesn't stop you walking with W, and PLAY doesn't wait for the save to load. Both are
  rare, minor and only plausible.
- Phones: night lights and engine sounds aren't reduced in Performance mode (Roblox already lowers
  lighting quality on weak phones), and several client loops copy the car list every frame.
- The police goal chain (spike, tase, arrest) needs a wanted human player, so it stalls in quiet servers.
- `WardrobeUI` still says "a new look drops 1 star" after that chase's star was used.
- Prison breakout and heist prompts trust the player's position (that's only an exploit with a hacked
  client).
