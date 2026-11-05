# Empire M3: Backlot Print Shop — Studio test guide

**Status (Nov 4, 2026):** built locally, not committed, not published. Nothing here is live: the whole feature stays off in live servers until `Config.Businesses.Live = true` (owner's go-ahead only). In Studio it always runs.
**Source of truth:** `launch/10-BUSINESSES-PRD.md` (v2, sections 5, 9, 11, 14 and 18). M1 is in `launch/12-BUSINESS-M1-TEST.md`, M2 in `launch/15-BUSINESS-M2-TEST.md`.

---

## 1. What M3 contains

| Piece | Where |
|---|---|
| Every number: the Print Shop entry, `Print`, `Launder`, `Raid`, the maths (`PrintGrade`, `PrintBatch`, `HeatStep`, `WarrantChance`, `RaidReward`...) | `src/shared/Config/Businesses.lua` |
| The building (levels 1-5), the shift (PRINT and LAUNDER), the police raids (player cops and the AI) | `src/server/Services/BusinessJobs/PrintShop.lua` (new) |
| The job-module hooks (switch, wanted runs, end summary, raids each second, state, alarms, debug), dirty cash saved, no break-ins at shady businesses | `src/server/Services/BusinessService.lua` |
| The timing gauge, streak, heat meter, count-up, shift summary, raid strip, siren, prompts, effects | `src/client/Controllers/BusinessClient.lua` |
| `Coffee.Kinds` (one line, the new hook) | `src/server/Services/BusinessJobs/Coffee.lua` |
| The EMPIRE app line for the dirty cash and the raid | `src/client/Controllers/PhoneUI.lua` (2 lines) |
| Offline maths tests | `tools/logic-tests/businesses.sh` |

**The lot moved.** The first draft's spot (x 807, z -895) turned out to be on Palm Hills ground. The Print Shop now stands in Rustwater Docks' back streets: on the north side of the z = 1650 street, between the x = -650 and x = -300 streets, with the container stacks behind it. Its world box is x -424..-368, z 1562..1612. It was checked against the place file: nothing inside it, 22 studs from the road, and 200+ studs from the Hideout, the Chop Shop, ATM3, the ramps, every home and the other two businesses.

## 2. Studio helpers (Studio only)

Run them in the **server** Command Bar through DebugService's `NCCmd` door, as in M1. Read the answer with `print(workspace:GetAttribute("NCResult"))`. `"$me"` is the first player; use `"Player2"` for the second.

| What | Command |
|---|---|
| Test cash | `workspace:SetAttribute("NCCmd", '["cash","$me",200000]')` |
| Own the Print Shop free | `workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","give","PrintShop"]')` |
| Its level (1-5) | `... "Debug","$me","level","PrintShop",4]` |
| Set your dirty cash (none = full) | `... "Debug","$me","dirty","PrintShop",12000]` |
| A raid warrant now (player cops if one is eligible) | `... "Debug","$me","raid","PrintShop"]` |
| A raid warrant now, AI raid | `... "Debug","$me","raid","PrintShop","ai"]` |
| A short warrant (seconds, 20-600) | `... "Debug","$me","raid","PrintShop",60]` |
| End the raid | `... "Debug","$me","endraid","PrintShop"]` |
| Treat Player2 as an on-duty cop (raids only) | `... "Debug","$me","testcop","","Player2"]`; `""` for none |
| Your launder run's heat meter (0-1) | `... "Debug","$me","heat","",0.9]` |
| Summary (now shows `dirty=`) | `... "Debug","$me","state"]` |
| Time scale (play clocks: raids' first roll, the roll each minute, the gaps) | `workspace:SetAttribute("BusinessTimeScale", 60)` (set it back to 1). The warrant's own 3 minutes is not scaled. |
| Crewmates | `workspace:SetAttribute("BizTestCrew", true)`. **Set it to `false` for a player-cop raid:** crewmates are never sent as cops. |

## 3. One player: print and launder

1. **Map.** The minimap and the big map show a violet **X** on the Docks' z = 1650 street, by the container lot. PHONE > GPS > PLACES lists "Backlot Print Shop · Business · $90k". EMPIRE lists it under FOR SALE, and only Boat Rentals and the Nightclub under COMING SOON.
2. **The lot at level 1.** Drive there and check:
   - a dark brick shop, the small PRINT & COPY board over the shop door, the roll-up door half up with its floodlight, and the plate "FOR SALE · $90,000" on its header;
   - the painted LOADING bay, the cash cart (LOAD HERE) by the roll-up door, yellow bollards, the BACKLOT tag;
   - inside: the office (counter, till, copier, flyers, OPEN sign), the doorway at its back, and the workshop with three stations on yellow mats: 1 · PAPER (a pallet of reams), 2 · PLATES (the bench), 3 · PRESS (the green press with rollers and a flywheel);
   - the side yard with the dumpster, pallets, oil drums and a chain-link fence;
   - you can't walk through walls, nothing blocks the street, and Output has no "lot overlaps" warning.
3. **Buy.** The card shows $90,000, "Print and launder fake cash (cops can spot you)", and "Level 5: a full counterfeit floor · the biggest loads". **BUY** gives the YOU OWN IT stamp and the gold ring on the X.
4. **Manage card.** It reads "Register +$192 a minute · 0 jobs done" and, under it, "Dirty cash $0 / $14,000 · a run carries $5,600". START JOB offers **PRINT | LAUNDER | BACK | CLOSE**.
5. **PRINT** (the timing game).
   - The strip reads "WALK TO THE PAPER" with the distance. On the mat, the HOLD button shows "LOAD PAPER" with a **green band** drawn in it.
   - Hold it (F, RT, mouse or finger). The fill is grey, then green inside the band, then orange past it. Let go in the green: "PERFECT!" pops over the button with a ding. Before the band: "OK". Very early (under 2.5 s): "TOO EARLY", and you hold it again.
   - On to "WALK TO THE PLATE BENCH", then "WALK TO THE PRESS". Each gauge has its band in a different place.
   - After the press: the **ka-chunk**, sheets flutter out of the out tray, "+$1,250 DIRTY" (or more) rises over it, and the stack of bills on the counting table grows.
   - Two PERFECTs in a row show "PERFECT! ×1.10" and the strip's right side reads "STREAK ×1.10". An OK resets it.
   - Fill the stock (`dirty` helper, then print): "The back room is full!" and station 1 refuses.
6. **LAUNDER.**
   - With $5,600+ in stock the strip says "PARK YOUR CAR IN THE BAY". Call your car, park in the LOADING box, get out: "WALK TO THE CASH CART", then "HOLD TO LOAD THE BAGS" (3 s).
   - You get "$5,600 of fake cash loaded. Drop it at <the arcade>…", a gold ring and beam, the GPS, and the strip "DROP AT THE ARCADE" with the distance. A **HEAT** bar shows under the strip.
   - Drive near a police car (or the police HQ in Solana Heights): the bar fills, orange then red. Drive away and it drains. If it fills: "SPOTTED!" and 1-2 stars.
   - Stop in the ring: the cash **counts up** on screen with a cash register, then the **LAUNDERED** stamp with "+$6,160" and "Clean run · bonus $560" (or "Spotted: no clean-run bonus").
   - The GPS goes back to the shop, and the strip reads "BACK TO THE PRINT SHOP".
7. **The endings with bags in the car.** Check each:
   - Get out for 20 s: "The bags are gone: $5,600 of dirty cash lost", then "Job over: you left the car with the bags."
   - Get arrested mid-run: the same, "(the police took them)".
   - Being wanted does **not** end the run: deliver while wanted and you're still paid (no clean bonus). Once you're back at the shop, still wanted, the shift ends ("you're wanted").
   - END JOB at the shop right after loading: "Bags unloaded back into the stock".
8. **The shift summary.** END JOB shows the SHIFT OVER card: press runs, PERFECTs, best streak (×), runs, clean runs, $ printed and $ earned. Tap it or wait 9 s.
9. **Break-ins.** `["call","BusinessService","Debug","$me","breakin","PrintShop"]` answers "PrintShop is shady: it gets police raids, not break-ins". Own the Car Wash too: natural break-ins only ever pick the Car Wash.

## 4. Two players: a raid with a player cop (Test > Clients and Servers, 2 players)

Set `BizTestCrew` to **false**. P1 owns the Print Shop. P2 goes on duty from PHONE > JOBS > GO ON DUTY. If the cop cap refuses it, use `testcop` with `"Player2"`.

1. **The warrant.** Give P1 $10,000 of dirty cash and run `raid PrintShop`.
   - **P1:** the red toast "Police are on their way to your Print Shop! Hold the door for 3:00…", the GPS, the X flashing red, the strip's red RAID line with the clock, and the siren near the shop.
   - **P2:** "DISPATCH: raid warrant on Player1's Print Shop…", the GPS, the X flashing, the strip "BREACH THE PRINT SHOP DOOR".
2. **Breach.** At the shop door, P2 sees **Breach** (6 s hold; 9 s at level 4+). P1 sees no Breach prompt, and P2's door "Manage/Buy" bubble is gone during the warrant.
   - Let go early: nothing. Hold it through: both get the breach news ("The door's open!"), and P2 sees **Search** at the presses (8 s).
3. **Seize.** P2 holds Search.
   - P2 gets the **SEIZED $10,000** stamp with +$2,800 (the $300 base + 25%).
   - P1 gets the red **RAIDED** stamp. P1's dirty cash is $0; clean cash, the register and the level are unchanged.
   - Everyone sees the Coast Feed post.
4. **Hold the door.** Run `raid PrintShop 70` and keep P1 inside the shop. P2 stays away.
   - The strip reads "HOLD THE DOOR!".
   - When it runs out, P1 gets the **RAID FAILED** stamp with +$1,000 and +75 XP. P2 gets "They held the door…".
5. **Fight.** In a new warrant, P1 punches or shoots P2 while P2 holds Breach. The hold breaks; the normal combat rules apply (P1 can get stars, PASSIVE players can't be hit).
6. **Crew.** Set `BizTestCrew` to true and run `raid PrintShop`. Now P2 is a crewmate: P2 gets "Police are raiding Player1's Print Shop! Help hold the door". With no other cop, it's an AI raid. If P2 stays inside 60 s and it's held, P2 also gets RAID FAILED +$500 +75 XP.
7. **The cop goes off duty** during the warrant (before the breach). It turns into an AI raid ("No cops took the warrant…").
8. **Crew launder.** With `BizTestCrew` on, P2 runs LAUNDER for P1. P2 is paid; P1 gets "+$… crew cut".

## 5. One player: the AI raid

1. Give yourself $10,000 of dirty cash. Stand far from the shop and run `raid PrintShop ai`.
2. After about 30 s a police car pulls in off the street and parks on the forecourt, with its light bar flashing red and blue and a siren. Two officers get out and walk to the shop door ("POLICE! Open up…").
3. Stay away. The strip counts "COPS BREAKING IN 40%"…. After 40 s they walk in through the office to the presses, then "COPS SEARCHING…". After 15 s you get **RAIDED**, and half the stock ($5,000) is gone.
4. Again, but get inside before they finish. Their clock stops ("Open the door! Police!"), and the strip reads "HOLD THE DOOR!". Stay for the warrant: you get **RAID FAILED**. The officers fade and the car goes.
5. **Natural timing:** set `BusinessTimeScale` to 60 with $6,000+ of stock.
   - The first roll comes about 10 s after the save loads (10 min of play).
   - Then one comes every second (a minute of play), with a 10-40% chance each.
   - After a raid, the owner's next roll is 15 s away (15 min of play). The building itself waits 5 real minutes (`Raid.SiteGap` isn't scaled): use `raid` to test again sooner.

## 6. Fun and feel (check by hand: offline tests can't)

**PRINT**
- **The gauge.** The green band is visible and readable on PC and phone. The fill turns green inside it, and you can tell where to let go by the 3rd press run.
- **Difficulty.** PERFECT should land about 1 try in 2 for a new player and most of the time after a few minutes. If it's never or always, move the `Print.Stations` bands (they're 0.8 s wide, plus 0.15 s slack each side).
- **Rhythm.** The three bands sit at different places (about 66-77%, 62-74%, 73-83% of each gauge). Check it feels like a rhythm, not a chore, on the 10th press run.
- **Feedback.** PERFECT! / OK / TOO EARLY over the button, readable and not covering the strip. The ding on PERFECT.
- **The press run.** The ka-chunk (the "Stamp" sound), the sheets fluttering out of the tray (a short burst, not a fountain), "+$X DIRTY" rising and fading.
- **The stack.** The bills on the counting table grow as the stock fills, up to 12 bundles. Check they sit on the table and don't float.
- **The streak.** It shows on the strip as ×1.05 … ×1.30. Does chasing it make you want one more run?

**LAUNDER**
- **The heat meter.** It's readable under the strip on PC and phone. It fills visibly faster the closer you drive to a police car, and slower behind buildings. Check it really can be dodged by driving around the police. Tune `Launder.HeatRise` / `HeatRange` if it's too twitchy or too slack.
- **The tension.** With no cops on the server, only tip-offs spot you (~14% of runs). Check that still feels risky enough. If not, raise `SpotChance`.
- **The route.** The GPS route and the drop ring (64 studs across, a beam) are easy to follow at speed.
- **The drop.** The count-up runs about 1.3 s with the register sound. Then the LAUNDERED stamp follows, and the clean-run bonus line reads as a reward.

**RAIDS**
- **The warning.** It feels urgent: the toast, the siren, the red X flashing, the countdown on the strip.
- **Holding the door.** It's clear you have to be **inside**: the strip switches to "HOLD THE DOOR!" the moment you step in.
- **The AI car.** It pulls in smoothly and parks on the forecourt, not in the loading bay. The officers walk to the door, then inside to the presses, without sliding through the counter.
- **The stamps.** RAID FAILED, SEIZED $X and RAIDED are readable and don't fight the other stamps.

**SHIFT SUMMARY**
- It's short, readable on a phone, and it goes away by itself. Does it make you want another shift?

**PERFORMANCE**
- On a phone: no hitch on the press run's burst, the stack rebuild, or the siren starting.

## 7. Phone layout (PreviewTouch)

- The HOLD button with its green band, right of centre; the grade pop above it.
- The heat bar under the strip, clear of the Banner zone's other pieces.
- The summary card low in the middle, clear of the thumbstick.
- The strip shows the streak as "×1.15" only (no "STREAK").
- The manage card shows START JOB's PRINT | LAUNDER.

## 8. The numbers (Config.Businesses)

| | Level 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Trickle ($/min online) | 192 | 257 | 321 | 386 | 450 |
| Register size | $7,000 | $11,750 | $16,500 | $21,250 | $26,000 |
| Job pay multiplier | 1.00 | 1.06 | 1.12 | 1.18 | 1.25 |
| Upgrade price (to this level) | — | $36,000 | $54,000 | $72,000 | $90,000 |
| Dirty cash the back room holds | $14,000 | $17,500 | $21,000 | $26,000 | $31,000 |
| A launder run carries | $5,600 | $6,100 | $6,500 | $7,000 | $7,400 |
| Tip-off chance per roll | 5% | 5% | 4% | 4% | 3.5% |
| BREACH hold | 6 s | 6 s | 6 s | 9 s | 9 s |

**PRINT**
- **Stations** (Min / green band / Full, in seconds):
  - LOAD PAPER: 2.5 / 4.6-5.4 / 7
  - SET THE PLATES: 2.5 / 4.0-4.8 / 6.5
  - RUN THE PRESS: 3 / 5.8-6.6 / 8
  - The server widens each band by 0.15 s each side for lag.
- **A press run's dirty cash:** $1,250 × JobMult × (1 + 5% per PERFECT in the run) × the streak (+0.05 per PERFECT in a row, capped at ×1.3).
  - All OK: $1,250.
  - A typical player (half the bands): ~$1,410.
  - A perfect run deep in a streak: ~$1,870.

**LAUNDER**
- **Delivery pay:** 1:1, plus a 10% clean-run bonus (never wanted on the way).
- **The drop:** 800-1,600 studs away; the ring is 32 studs; the speed check is the taxi's (FastSlack 1.15, VehicleGuard). You have 20 s to get back in the car.
- **The heat meter:**
  - Police within 260 studs fill it at 0.25 a second × closeness: ~6.5 s at 100 studs, ×0.4 behind a wall.
  - With no police in range it drains at 0.08 a second.
  - Full = 2 stars with the police within 120 studs, else 1.
  - It counts player cops, AI patrol cars, AI officers on foot and the police HQ.
- **Tip-offs:** a roll every 10-15 s while moving with the bags: ~14% of runs at level 1.

**The calibration** (the logic tests simulate it): **~$1,600 a minute of work at level 1 with the risk.**
- **The loop:** 4 press runs (~30 s each) + a launder run (~89 s).
- **The risk:** ~20% of runs spotted; a quarter of those arrested (the bags lost), the rest ~50 s escaping.
- **The spread:** an all-OK printer makes ~$1,500, a perfect one ~$1,850, and level 5 makes ~1.28×.
- **The bonuses:** the streak and the clean-run bonus are inside that average, not on top.

**RAIDS**
- **The warrant rolls:**
  - Only after 10 min of the owner's play, one roll a minute, and 15 min after the owner's last raid (5 min at the building).
  - The stock must hold $5,500+.
  - The chance is 10% a roll at $5,500, rising to 40% at a full stock.
- **The warrant:** 3 minutes. After a breach, the cops get at least 60 s more for the search.
- **A player raid:** seizes all the stock. Every cop at the shop gets $300, plus an even split of 25% of it (at most $6,000 in all).
- **An AI raid:**
  - The car arrives at 30 s.
  - The officers need 40 s to breach and 15 s to search, with their clocks paused while anyone holds the door.
  - It takes half the stock and pays nobody.
- **Held off** (no seizure, and 60 s+ of the warrant spent inside): $1,000 and +75 Empire XP for the owner; $500 and +75 XP for each crewmate who was inside 60 s+.
- **Empire XP:** 5 a press run, 15 a launder run, 75 for a raid held off.
- **Payback:** the trickle alone pays the $90,000 back in ~7.8 h online ($192/min, raised by the fun pass to sit inside the 6-8 h target). Working 40% of the time: ~3.4 h.

## 9. Not verified offline (check these in Studio)

- **The building.** It has never been seen. Check:
  - the brick walls' look and the office doorway's width;
  - the props at every level: the second press, the paper store, the drying lines, the hidden door, the counting cage, the armored door, the level 5 floor and its UV lights;
  - nothing clips (the cutter and the cage, the bills on the lines);
  - from behind, the container stacks don't hide the shop's back.
- **The loading bay.** Check a car parked in the LOADING box counts (`BayRange` 14) and loading from the cart works with the car's tail at the door.
- **Drop points.** `JobService.RoadsideSpot` has to find kerb spots 800-1,600 studs from the Docks. If "No customer is home right now" shows often, lower `Launder.DistMin`.
- **The AI car.** CarBuilder's SunrayPatrol, anchored outside Workspace.Vehicles. Check:
  - its seats really are disabled and its light bar flashes (BusinessClient does it, not VehicleFeel);
  - the glide in off the street looks fine.
- **The AI officers.** OfficerTemplates exist only once PoliceOfficerService has built them (a few seconds after start). Check their height on the floor and the walk path through the office.
- **The prompts.** Check:
  - only an eligible cop sees Breach / Search, and E goes to Breach (the door bubble steps aside);
  - a cop in a car doesn't get them (PromptGate);
  - the server's own hold timing matches the prompt's bar.
- **Siren.** `SoundClient.Loop("Siren")` near the shop; check it stops when the raid ends.
- **Saving.** `data.businesses.PrintShop.dirty` only persists with Studio API access or in a private live test.
- **Cop XP.** ProgressService has no XP for a raid yet: it gets a "BizRaid" event (listeners only). Giving it XP needs a line in ProgressService and Config.Progression (shared files, not touched).

## 10. Shared files changed

- `src/client/Controllers/PhoneUI.lua`: two lines in `PAGES.Empire`. The business line under the name uses `b.Extra` / `b.ExtraColor` when BusinessClient gives them (the Print Shop's dirty cash and raid); the other businesses are unchanged. Lint-diffed against HEAD: no new warnings.
- Nothing else outside the business files. HeatService, ArrestService, AIPoliceService, PoliceOfficerService, JobService, VehicleService, ProgressService and CombatService are only called through their public functions or read through attributes.

## Studio test, Nov 5 2026 (one player, PC and the iPhone 7 simulator)

**What worked:**
- PRINT starts with "WALK TO THE PAPER".
- On the mat, the strip reads "HOLD · LET GO IN THE GREEN" and the LOAD PAPER button shows its green band.
- Letting go at 5 s gave **PERFECT!**, and the strip moved to "WALK TO THE PLATE BENCH".
- On the phone simulator, the HOLD button, strip, PHONE / CAR / END JOB tiles, joystick, jump and SPRINT all fit without overlapping.

**Not seen yet:** LAUNDER, and raids (player cop and AI).
