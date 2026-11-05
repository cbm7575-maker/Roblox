# Empire M1: Foundation + Car Wash — Studio test guide

**Status (Nov 4, 2026):** built locally, not committed, not published. Nothing here is live: the feature is off in live servers until `Config.Businesses.Live = true` (owner's go-ahead only). In Studio it always runs.
**Source of truth:** `launch/10-BUSINESSES-PRD.md` (v2). This file is the M1 test plan and the numbers.

---

## 1. What M1 contains

| Piece | Where |
|---|---|
| Every number, place and rule | `src/shared/Config/Businesses.lua` |
| Ownership, saving, registers, jobs, shine, break-ins, Empire XP, the building | `src/server/Services/BusinessService.lua` |
| Cards, wash mini-game, delivery HUD, level props per device, alerts, map data | `src/client/Controllers/BusinessClient.lua` |
| EMPIRE phone app | `PhoneUI.lua` (`PAGES.Empire`, the app tile, `PhoneUI.Refresh`) |
| Offline maths tests | `tools/logic-tests/businesses.sh` |

Only the **Suds & Shine Car Wash** is built and buyable. The other four are `Enabled = false` placeholders that the EMPIRE app lists under **COMING SOON**.

## 2. Studio helpers (Studio only)

Run these in the **server** Command Bar. `require` there gets a separate module copy, so use DebugService's `NCCmd` door. Read the answer with `print(workspace:GetAttribute("NCResult"))`. `"$me"` means the first player. Use `"Player2"` for the second one.

| What | Command |
|---|---|
| Test cash | `workspace:SetAttribute("NCCmd", '["cash","$me",100000]')` |
| Own the Car Wash free | `workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","give","CarWash"]')` |
| Remove it | `... "Debug","$me","remove","CarWash"]` |
| Set its level (1-5) | `... "Debug","$me","level","CarWash",3]` |
| Fill the register / set it | `... "Debug","$me","fill","CarWash"]` / `... "register","CarWash",1500]` |
| Add Empire XP | `... "Debug","$me","xp","",3500]` |
| Force a break-in now (timer in seconds) | `... "Debug","$me","breakin","CarWash",120]` |
| Clear your shine | `... "Debug","$me","shine"]` |
| Summary | `... "Debug","$me","state"]` |
| Time scale (register and break-in clocks) | `workspace:SetAttribute("BusinessTimeScale", 60)`. 60 means a minute passes every second. Set it back to 1 after. |
| Treat the test players as crewmates | `workspace:SetAttribute("BizTestCrew", true)`. Set it to `false` for strangers. |
| Night (neon check) | `workspace:SetAttribute("NCCmd", '["clock",22]')` |
| Phone layout (client bar) | `game.Players.LocalPlayer:SetAttribute("PreviewTouch", true)` |

## 3. One player

1. **Map.** Check the Car Wash appears in three places:
   - PHONE > GPS > PLACES lists "Suds & Shine Car Wash · Business · $25k".
   - The minimap shows a blue **W** disc.
   - The big map (M) shows **W** with its name. Tapping it sets the GPS.
2. **The lot at level 1.** Drive there. Check:
   - One wash bay is open. Bays 2 and 3 have cones and a COMING SOON barrier.
   - A painted roof sign, with a gold "FOR SALE · $25,000" plate on the blue bay header.
   - The shine-lane gantry ("DRIVE-THRU SHINE $100") and the yellow PICK-UP box.
   - The detailing room's roll-up door is down. There's an office with a counter and a register.
   - Nothing blocks the street. Cars and people can't walk through the walls.
3. **Buy.**
   - Give yourself cash. The door bubble reads "View / Buy $25,000".
   - The buy card shows the price, "The job: …", the register line, the blurb and "Level 5: …".
   - Press **BUY**. You should see:
     - the "YOU OWN IT" stamp, and the plate reads "★ YOUR SUDS & SHINE ★";
     - the bubble reads "Manage", and the minimap W gets a gold ring;
     - EMPIRE shows rank 1 with 100/300 XP.
4. **Trickle.**
   - Set `BusinessTimeScale` to 60. Within 30 s the manage card's register shows about $1,800 and its bar fills live.
   - At $2,000 the "register is full" toast shows once.
   - **COLLECT** adds the cash and shows a toast.
5. **Upgrade and props.**
   - **UPGRADE $10,000** shows the "LEVEL 2" stamp. Bay 2 opens (partition, brush, board, lane arrows) and the vacuum station appears.
   - Then set levels 3, 4 and 5 with Debug and check:
     - **L3:** bay 3 opens; neon round the roof sign, header and office roof (check at night); the pole sign with bubbles; a bench; a red car waiting.
     - **L4:** the roll-up door is up, showing a lift with a car, tool chests, lights and a DETAILING sign; a second waiting car.
     - **L5:** the tunnel over the shine lane (arches with LED strips, roller brushes, "★ TUNNEL WASH ★").
6. **Wash.** Press **START JOB > WASH A CAR**.
   - A car rolls into your bay (bay 1) with 4-6 mud discs.
   - **HOLD TO SPRAY**: hold the button, F or RT until the bar fills. Water falls and foam appears.
   - Tap each **SCRUB** circle 3 times.
   - **HOLD TO RINSE**. Then:
     - a toast reads "Car washed: +$560 (clean finish tip $140)";
     - the AFTER panel offers NEXT CAR, DELIVER and END.
   - **NEXT CAR**: the old car backs out and a new one pulls in.
   - Let go of a hold early. You should see "Hold it until the bar is full!", and that wash pays no tip.
   - **END**: you see "Job over. 2 jobs, $1,270."
   - Walk more than 45 studs from the bay. The job ends after 10 s with "you walked away from the bay".
7. **Delivery.** Press **START JOB > DELIVER A CAR** (or **DELIVER** after a wash).
   - You're seated in a customer car (a Palmetto, Gatorback or Mangrove at level 1) on the PICK-UP box. You also get a GPS route, a gold ring and beam at the address, and a strip that reads "DETAIL · DELIVER THE … TO …" with "TIP 30s".
   - Hit a wall at speed. You should see "Dent! -$60 off the tip".
   - Stop in the ring. You should see:
     - the DELIVERED stamp with the pay and tip;
     - you're put out at the kerb and the car disappears;
     - the toast "Tap CAR to call yours".
   - Also check each of these:
     - Get out for more than 10 s. You see "you left the customer's car", and the car goes.
     - Get wanted mid-delivery (`["heat","$me",1]`). The job ends and the car goes.
     - Drive it to the Chop Shop. Nothing happens.
     - Other players can't drive or ride it. After you get out, the "Drive" bubble shows only to you.
8. **Shine.**
   - Drive your own car into the shine lane and stop under the gantry. "Shine $100" shows (only from your driver's seat).
   - Press it. You pay $100 and the car sparkles (and looks glossier) for 30 min.
   - Press it again. You see "still sparkling".
   - As the only owner, you pay and nobody gets a share.
9. **Break-in.** Buy a pistol at Coast Arms first.
   - Run `breakin CarWash 120`. Check:
     - a red toast with a 2:00 timer, and the GPS routes to the wash;
     - the W flashes red on the minimap and the big map;
     - the strip reads "BREAK-IN · STOP THE ROBBERS AT YOUR CAR WASH 1:58";
     - 1-2 "Robber" NPCs (beanie and bandana) stand at the counter.
   - Aim at a robber (Z or right mouse) within ~22 studs. It raises its hands, says "Whoa! Okay…" and runs out the door. You get "+$250".
   - Punch the other. It goes down, then fades. You get "+$250", the BREAK-IN STOPPED stamp and +50 Empire XP.
   - Run it again with a 15 s timer and do nothing. The robbers leave and the toast reads "got away with $X" (10% of the register).
   - Natural timing: with time scale 60 and $800+ in the register, the first break-in comes 10-25 s after the save loads (10-25 min in a live game).
10. **Empire 5.** Add 3,500 XP. You get RANK UP stamps up to 5. EMPIRE now has a **COLLECT $X** button per business that works from anywhere.
11. **Panels.** With a pistol out, open the manage card and play a wash:
    - the gun lowers;
    - clicks hit the buttons and the SCRUB circles, never a shot;
    - E / F don't start GET IN behind them.

## 4. Two players (Test > Clients and Servers, 2 players)

1. **Featured-owner sign.**
   - P1 owns the wash at level 3 and P2 owns nothing. P2 sees the plate "Player1's Suds & Shine" and the level 3 props.
   - Give P2 the wash (`"Player2","give","CarWash"`). P2 now sees "★ YOUR…" and its own level 1 props, while P1 still sees level 3.
   - The featured owner is the highest level; on a tie, more lifetime earnings.
2. **A customer shine pays the owner.**
   - P2 (not an owner) shines their own car.
   - P1 gets "Player2 got a shine at your Car Wash +$70" and +10 Empire XP. P2 pays $100.
3. **The crew.** Turn on `BizTestCrew`, or make a real crew in PHONE > CREW.
   - P2 at the door gets the CREW card ("Player1's Suds & Shine · LEVEL n") with WASH A CAR, DELIVER A CAR, BUY YOUR OWN and CLOSE.
   - P2 washes a car. P2 gets the normal pay, and P1 gets "Player2 worked your Car Wash: +$127 crew cut".
   - While P2 is on the lot, P1's manage card reads "(+25% busy: crew here)".
   - P2 sees P1's props and a purple "Player1's…" plate.
4. **Crew break-in.** Both get the alert, and either can scare or punch the robbers. With `BizTestCrew = false`, P2's aim or punches do nothing to P1's robbers.
5. **Bays.**
   - At level 1, when P1 is washing, P2 gets "Every bay is busy".
   - At level 2+, they get different bays.

## 5. Phone layout (PreviewTouch)

Check each of these:
- **Cards:** centred, with 44 px buttons. CLOSE / CANCEL sit on the left; the text fits.
- **HOLD button:** right of centre, above the jump area.
- **SCRUB circles:** 66 px.
- **AFTER panel:** low and a little right of centre.
- **Strip:** in the Banner zone, with gold words only.
- **END JOB tile:** in the side column.
- **EMPIRE:** the phone's home screen has 4 rows (10 apps). Check the icons still read on a 390 px-tall screen, and that the EMPIRE page scrolls.

## 6. The numbers (Config.Businesses)

| | Level 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Trickle ($/min online) | 60 | 83 | 105 | 128 | 150 |
| Register size | $2,000 | $3,750 | $5,500 | $7,250 | $9,000 |
| Job pay multiplier | 1.00 | 1.06 | 1.12 | 1.18 | 1.25 |
| Upgrade price (to this level) | — | $10,000 | $15,000 | $20,000 | $25,000 |
| Wash bays | 1 | 2 | 3 | 3 | 3 |

**Jobs**
- **Wash:**
  - Pays $420 plus a $140 clean-finish tip (both holds done in one go, inside 40 s). Re-tuned after the code review; time real washes and adjust.
  - The holds are 5 s each; there are 4-6 spots, each needing 3 taps.
  - A wash under 11.5 s isn't paid ("NOT PAID · TOO FAST"), but the job goes on.
  - About 30 s per car (85% of washes clean) works out to **~$1,080/min** (~$1,350 for a fast player), as the config's re-tuned maths says.
- **Delivery:**
  - The address is 600-1,500 studs away (straight line).
  - Pays $500 plus 65¢ a stud of road.
  - The speed tip is $300 at or under the estimate (road ÷ 75 + 12 s), falling to $0 at 1.5× the estimate.
  - Each dent costs $60 (a crash-hard stop, or another car shoving yours).
  - About 85 s round trip works out to **~$1,134/min**.
  - The speed check is the taxi's (FastSlack 1.15, VehicleGuard).

**Players and crews**
- Shine: $100 for 30 min. The featured owner gets 70% ($70) and 30% is a sink.
- Crew cut: 20% of the crewmate's pay, paid by the game.
- Busy-shop bonus: +25% trickle.

**Break-ins**
- Only after 10 min of play this session, at most one per 20 min (a random moment within the next 15 min).
- The register must hold $800 or more.
- 1-2 robbers and 2 minutes to stop them. Each one stopped pays $250.
- Stopping them all gives the owner +50 Empire XP. If the timer runs out, they take 10% of the register.

**Empire XP and ranks**
- XP:

  | Event | XP |
  |---|---|
  | Buy | 100 |
  | Upgrade | 50 × new level |
  | Wash | 5 |
  | Delivery | 10 |
  | Customer served | 10 |
  | Break-in stopped | 50 |

- Ranks: 2 at 300, 3 at 900, 4 at 2,000, 5 at 3,500, 6 at 5,500, 7 at 8,000, 8 at 11,000, 9 at 15,000, 10 at 20,000.
- Unlocks:
  - Empire 2: Boat Rentals.
  - Empire 3: the Nightclub.
  - Empire 5: phone collect.
  - Empire 7: the "Mogul" title.
  - Empire 10: the gold sign and "Kingpin of the Coast".

**Payback**
- The trickle alone pays back the price in 6.9 h online.
- Working 40% of the time adds ~$100/min over normal work, for about 2.6 h.

**One knob:** `Businesses.RateScale` scales all trickle, job pay and the break-in reward.

## 7. Not verified offline (check these in Studio)

- **The building's look.**
  - Lot space is −Z toward Solana Ave. It has never been seen.
  - The plate's position on the header, the sign readability, and props clipping.
  - `checkLot` warns in Output if the lot overlaps city parts.
- **The local wash car.**
  - A `TrafficModels` body's pivot and orientation in the bay.
  - Mud discs placed by raycast on mesh bodies: they could float or sink with box collision.
  - BillboardGui taps on touch.
- **Customer car handover.**
  - The server seats the worker (`seat:Sit`), passes network ownership, and DriveController takes it.
  - After `EjectAll`, the worker should stand beside the car before it's destroyed.
- **Dent detection.**
  - It uses a server-sampled deceleration over 180 studs/s². It may be too strict or too loose; tune `Detail.DentDecel` / `DentMinSpeed`.
- **Robbers.**
  - Spawn height (HipHeight on PedTemplates), the run-out tween, and the ragdoll on knock-down.
  - Shooting robbers is still gunfire: a cop who sees it can give a star (the normal gunfire rule).
- **Saving.** `data.businesses` and `data.empireXP` only persist with Studio API access or in a private live test (PRD risk table).
- **Other screens.**
  - The phone home grid with 4 rows on a small phone.
  - The break-in GPS route replaces whatever route the player had set (only when they're not on a job).

## 8. Left for M2+

- **M2:** Palm Grind Coffee (rush orders, cold brew for players).
- **M3:** Backlot Print Shop (presses, laundering, dirty cash, police raids with the AI fallback).
- **M4:** Coastline Boat Rentals (lot, tours, jet ski rental; Empire 2).
- **M5:** Afterglow Nightclub (lot, limo VIP pickups, night ×2, interior, cover and VIP booth; Empire 3).
- **Each needs:** its `Layout` and `Style` in the config, a `STYLES.<Style>` building, and its job module. The framework already handles registers, levels and props, featured owners, Empire XP, crew cuts and map icons.
- **Polish, later:**
  - Show Empire rank and title next to the normal rank (GOALS, name tag).
  - The gold business sign at Empire 10.
  - Customer cars and the shine sparkle for NPC traffic.
  - A HOW TO PLAY section.
  - A private live test of saving before M6.

## Studio test, Nov 4 evening (M1 + M2, two players, in a separate copy of the place)

Run in a scratch copy of the place file with only the working tree synced. The copy has no DataStore access, so nothing was saved for real.

**Worked:**
- **Car Wash building:** FOR SALE sign, owner plate and minimap W.
- **Buying:** the buy card, BUY (cash −$25,000 exactly) and the manage card.
- **Wash:** START JOB > WASH A CAR, the customer car pulling into the bay, spray > scrub 6 spots > rinse, paid +$420.
- **Delivery:** DELIVER puts you at the wheel of the customer car with GPS; END JOB removes it, with no leftover cars and no warnings.
- **Shine:** Player2 bought it (−$100) and the owner got +$70.
- **Break-in:** the alert strip and red map icon, then punching the robber paid +$250.
- **Palm Grind:** building, buy (−$45,000), rush order GRAB > "Order up! Take it to Professor Lane".
- **Cold brew:** −$60, "Player1 says thanks".

**Found and fixed:**
- **Level props never showed after an upgrade.** Every prop stayed see-through. The client kept each prop's own look in a weak-keyed table, and Roblox can drop entries from those. Now the server stamps it on the part (attribute BizT), and the client always restores from that. Re-tested: at level 5, all level 2–5 props show (the TUNNEL WASH arch, brushes, queue cars, vacuum) and the level-1-only ones hide.
- **A wash started at the door ended by itself.** Bay 1 is about 46 studs away, and LeaveRange was 45. Now:
  - LeaveRange is 70 with 15 s grace;
  - the strip says WALK TO BAY n with the distance;
  - HOLD only shows at the bay.
- **The business card sat over the Coast Feed** on PC. It's centred now.
- **The rush-order hint was cut off.** It now says "STAND ON THE YELLOW PICK-UP MAT".

**Still to look at:**
- On a phone, two of the scrub spots can overlap.
- At the pick-up box, a palm tree hides the driver's camera.
- The rush delivery hasn't been driven end to end.
- The phone layout of the cards hasn't been checked.
