# Empire M4: Coastline Boat Rentals — Studio test guide

**Status (Nov 4, 2026):** built locally, not committed, not published. Nothing here is live: the whole feature stays off in live servers until `Config.Businesses.Live = true` (owner's go-ahead only). In Studio it always runs.
**Source of truth:** `launch/10-BUSINESSES-PRD.md` (v2, sections 4-6, 9, 14 and 19). The fun rules are in `launch/18-BUSINESS-FUN-PASS.md`. The M1-M3 guides are `launch/12-`, `15-` and `17-BUSINESS-M*-TEST.md`.

---

## 1. What M4 contains

| Piece | Where |
|---|---|
| Every number and place: the BoatRentals entry, `Tour` (boats, routes, landmarks, photo stops, mood, pay, specials), `Rental`, and the maths (`TourPay`, `PhotoStep`, `TourMood`, `TourReached`, `PickRoute`, `RollTourSpecial`...) | `src/shared/Config/Businesses.lua` |
| The floating dock (levels 1-5), BOAT TOURS (the boat, the tourists, the route, the mood, the pay), the JET SKI RENTAL | `src/server/Services/BusinessJobs/BoatRentals.lua` (new) |
| A job module's own customer service (`Module.Service`), `Api.serveCustomer`, the Studio `rank` helper, the header | `src/server/Services/BusinessService.lua` |
| The tour HUD: buoy rings, the GPS line on the water, the photo gauge, the guide's bubble, the stamps, the AFTER panel, the shift report lines; the rental's timer and toasts; "Unlocks at Empire 2" in the EMPIRE app | `src/client/Controllers/BusinessClient.lua` |
| Two pitched cues: `TourShutter`, `TourHorn` | `src/shared/Config/Sounds.lua` (shared, 3 lines) |
| Offline maths tests | `tools/logic-tests/businesses.sh` |

**Where it is.** On the **water**, just off the end of the first marina pier (z = 1100), where Marina Boat Sales' kiosk stands. Its world box is x 1706..1756, z 1072..1128. A 22-stud gangway joins the pier's end (between the showcase dock and the kiosk) to the dock's front deck. The box was checked against the place file: nothing inside it; the civilian boat pads are 6 studs south; Marina Boat Sales' runtime lot is 6 studs west.

## 2. Studio helpers (Studio only)

Run them in the **server** Command Bar through DebugService's `NCCmd` door, as in M1. Read the answer with `print(workspace:GetAttribute("NCResult"))`. `"$me"` is the first player; use `"Player2"` for the second.

| What | Command |
|---|---|
| Test cash | `workspace:SetAttribute("NCCmd", '["cash","$me",500000]')` |
| **Set your Empire rank** (1-10, exactly) | `workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","rank","",2]')` |
| Own Boat Rentals free (skips the rank gate) | `... "Debug","$me","give","BoatRentals"]` |
| Its level (1-5) | `... "Debug","$me","level","BoatRentals",4]` |
| **Force your next tour's special** | `... "Debug","$me","tour","","Celebrity"]` (or `"Fishing"`, `"Sunset"`; `""` clears it) |
| Force your next tour's route | `... "Debug","$me","route","","Lighthouse"]` (`Marina`, `Boardwalk`, `Ferris`, `Flamingo`, `Lighthouse`, `Grand`, `Fishing`) |
| Set your tourists' mood now (0-1) | `... "Debug","$me","mood","",0.5]` |
| Your jet ski rental's time left (seconds) | `... "Debug","$me","rentleft","",70]` |
| A break-in at the ticket booth | `... "Debug","$me","breakin","BoatRentals",120]` |
| Summary | `... "Debug","$me","state"]` |
| **Time scale** (register, break-ins, and a new rental's 10 minutes) | `workspace:SetAttribute("BusinessTimeScale", 60)` (set it back to 1) |
| Dusk (a Sunset Tour may roll) | `workspace:SetAttribute("NCCmd", '["clock",18]')`; noon: `["clock",12]` |
| Crewmates | `workspace:SetAttribute("BizTestCrew", true)` |
| Phone layout (client bar) | `game.Players.LocalPlayer:SetAttribute("PreviewTouch", true)` |

## 3. One player: the unlock, the dock, the tours

1. **The Empire 2 gate.**
   - `rank 1`, then walk the gangway to the ticket booth's door. The bubble reads "View / Buy $120,000". The buy card's button says **EMPIRE 2 NEEDED** and the note "Needs Empire rank 2 (you're 1)".
   - PHONE > EMPIRE lists it under FOR SALE as "Unlocks at Empire 2 (you're 1) · Boat tours...", meta "EMPIRE 2 NEEDED" in purple.
   - `rank 2`: the card now offers **BUY $120,000** (with the cash). Buy it: the YOU OWN IT stamp, the gold ring on the minimap's teal **Y**.
2. **Map.** The minimap and the big map show a teal **Y** on the water past Marina Boat Sales. PHONE > GPS > PLACES lists "Coastline Boat Rentals · Business · $120k"; GPS leads down the marina pier.
3. **The dock at level 1.** Walk out along the pier, past Marina Boat Sales, over the gangway. Check:
   - the COASTLINE arch over the landing; the white TOURS booth with its window, the plate "FOR SALE · $120,000" on the roof edge, the COASTLINE roof sign;
   - the JET SKI RENTALS stand at the head of the left slip; the main pier with lamps and a flag; a finger each side; a dinghy in the far-left berth; a chalkboard "BOAT TOURS · TICKETS HERE";
   - you walk on the deck, the gangway and the piers, not through the booth's walls; the sea shows through everywhere else (no concrete slab);
   - Output has no "the Coastline Boat Rentals lot overlaps" warning.
4. **Levels.** `level` 2..5 and check each (the props show only on your device):
   - **L2:** a white runabout in the left berth, the striped awning and TICKETS lightbox at the window, brochures, the booth's flag;
   - **L3:** three jet skis on a little dock in the right berth with a JET SKIS flag; aqua LED strips along the main pier's edges after dark;
   - **L4:** the COASTLINE TOURS canopy boat in the right berth;
   - **L5:** the luxury yacht in the left berth (the dinghy and the runabout are gone), gold trim on the roof sign.
5. **START JOB > BOAT TOURS** (at level 1).
   - A Marlin appears in the right-hand slip and you're put at its helm. If not: the strip says **WALK TO THE BOAT** with the distance, and only you see its "Drive" bubble.
   - Two tourists (pedestrian looks, sun hats) wait on the main pier, then hop aboard one by one and sit behind you. The strip says ALL ABOARD...
   - Then: the ship's horn, ALL ABOARD! over the action spot, the guide's first line in a bubble under the strip, and the boat is yours to drive.
   - Gold buoy rings on the water (the next one bright with a light pillar, the one after it dim), a white GPS line on the water, the strip "NEXT: MARINA ROW SLIPS" with the distance, the line under it "HAPPY 100% · STOP 1/4 · PAR 0:28".
6. **The route.** Drive through each ring: it bursts, the guide's line pops up ("Those yachts? Mortgaged. Every one."), and the next ring lights.
   - **Photo stop (pink ring, PHOTO STOP):** "PHOTO STOP: SLOW DOWN!" as you approach. Inside, the PHOTO bar fills while you're under 16 studs/s: green under 8, orange between, red (and back to empty) over 16. Fill it: **PERFECT SHOT!** (1.5 s of it under 8) or **NICE SHOT!**, with three camera flashes on screen and the tourists' heads flashing. Drive out early: **MISSED THE PHOTO!**
   - **Hard turns at speed:** HAPPY drops (orange under 80%, red under 50%), the line shakes, a tourist shouts "Whoa!".
   - **Ram a pier or a boat:** −15%, a crash and "OW!". **Run aground** on the beach: −20% and a splash, "Are we on LAND?!", a toast to back off.
   - After the last ring: "BACK TO THE DOCK", then "STOP IN THE DOCK RING" (aqua, just outside the slip). Stop in it.
7. **The dock.** The boat glides into its berth. The stamp **★★★ TOUR** / **★★ GREAT TOUR** / **★ TOUR DONE** with the tip (and streak), the money counts up, confetti on ★★★. The tourists step off onto the pier, hop and cheer ("Best. Tour. EVER!" or "...thanks, I guess."), then fade. The AFTER panel: "+$X ★★☆" and what was missing ("for ★★★: faster, PERFECT photos, a smoother ride"), **NEXT TOUR | END**.
8. **NEXT TOUR** → new tourists, a new route (levels 1-2: Marina & Sea Dream or Boardwalk Beach). Get out at the dock first, then NEXT TOUR: you're seated again if you're within 40 studs.
9. **The streak.** Two ★★★ tours in a row: "★★★ streak ×2: tips ×1.1!" and STREAK ×2 on the line. A ★★ ends it ("Streak over").
10. **Specials.**
    - `tour Celebrity`: a toast "CELEBRITY TOUR: Lexi Lux is aboard!", a gold "★ LEXI LUX ★" tag over one tourist, CELEBRITY · LEXI LUX on the line. A ★★★ tour tips ×3.
    - `tour Fishing`: the fishing route, two green FISHING STOP rings (stop dead still: "STAY STILL... LINES IN"; FISH bar), fishing rods on the tourists, a bonus at the dock.
    - `clock 18` then `tour Sunset`: SUNSET TOUR, pay ×1.3. At `clock 12` a `tour Sunset` still works (the helper forces it), but natural rolls never give one by day.
11. **The endings** (the boat and the tourists always go). Check each:
    - END JOB (mid-tour and at the dock) → the SHIFT REPORT: tours, ★★★, best streak, photo stops and PERFECTs, tourists, % happy, specials.
    - Get out mid-tour and swim off for 15 s → "Job over: you left the tour boat."
    - Get wanted (`["heat","$me",1]`) → "Job over: you're wanted."
    - Wait 3 minutes at the dock without NEXT TOUR → "Shift over: no tour started for a while."
    - Drive the boat to the Chop Shop, try a race pad or a taxi shift: nothing (it's nobody's boat).
12. **Break-in.** `breakin BoatRentals 120`: 1-2 robbers inside the booth at the till, the Y flashing red. Scare or punch them; they run out of the booth door onto the deck and fade.

## 4. The jet ski rental

1. As any citizen (P2, or you): stand at the JET SKI RENTALS stand. The bubble "Jet ski rental $150". Press it:
   - you pay $150 and appear on a pink Splash Jet Ski in the left-hand slip; a toast "Jet ski rented for 10:00!";
   - the strip shows **RENTAL · JET SKI RENTAL · 9:59**, counting down (whenever no job or alarm has the strip).
2. `rentleft 70`: at 1:00 left the line turns orange and a toast says "1:00 left on your jet ski rental!". At 0: you're put in the water and the jet ski goes ("Time's up").
3. Rent again, get off and swim away for 60 s: it goes back ("You left your jet ski...").
4. Refusals: press it again while one is out (**RentAlready**); from a car seat (**RentOnFoot**, the bubble shouldn't even show); wanted (**RentWanted**); as a cop (**RentCivOnly**); two rentals out and a third (**RentBusy**).
5. The rules: nobody else can sit on it (their "Drive" bubble doesn't show); it can't race, take a taxi fare, go in the garage or be sold.
6. With `BusinessTimeScale` 60 a new rental lasts 10 s (scaled), handy for the warning and the end.

## 5. Two players (Test > Clients and Servers, 2 players)

1. **Featured owner.** P1 owns it at level 4; P2 owns nothing. P2 sees "Player1's Coastline Boats" on the plate and the level 4 props.
2. **Customer split.** P2 rents a jet ski: P2 pays $150, P1 gets "Player2 got a jet ski rental at your Boat Rentals +$105" and +10 Empire XP (twice an hour at most from P2).
3. **Crew tours.** `BizTestCrew` true. P2 at the booth door gets the CREW card with BOAT TOURS. P2 runs a tour on P1's level-4 boat (the Moonstone hull, 5 tourists, the canopy) and is paid; P1 gets "+$... crew cut".
4. **Everyone sees the tourists:** P1 watches P2's tour: the tourists aboard, their shouts, the camera flashes on their heads, the cheering on the pier.

## 6. Fun and feel (check by hand: offline tests can't)

**THE LOOP**
- **One tour** should take 30-60 s at level 1 (the Marina route ~1,490 studs, the Boardwalk ~2,290), longer at higher levels. Time five real tours. If they're much faster than ~90 studs/s on average, the pay per stud is too high: tune `Tour.PerStud` (and see BALANCE).
- **The 5th tour** should still feel good: new tourists, a different route now and then, a special 1 in 8, the streak.

**PHOTO STOPS**
- Is PERFECT reachable but not automatic (about 1 in 2 for a new player)? If never or always, move `Tour.Photo.Perfect` (8) or `PerfectHold` (1.5).
- Can you tell from the PHOTO bar's colours what to do? Green = good, orange = slower, red = too fast.
- The camera flashes and the shutter: satisfying, not blinding. Three blinks on screen, a few lights on the tourists.

**THE MOOD**
- Does HAPPY drop when it should (a hard turn at full speed, a ram, the beach) and not for ordinary driving? If it drains on every turn, raise `Mood.TurnLimit` (60); if it never moves, lower it.
- The shouts are funny, not constant (at most one every 1.6 s).

**THE ROUTE**
- The buoy rings read from far off on the turquoise sea (gold, pink, green, aqua) and don't hide the water you need to see.
- The white GPS line on the water leads the way and redraws when you wander off.
- The guide's lines are short enough to read at speed, and don't cover the HOLD spot or the controls.

**THE DOCK**
- The glide into the berth looks like docking, not a teleport.
- The tourists step onto the pier (not into the water), hop and cheer, then fade.
- The stamp, the count-up and the AFTER panel don't fight each other on a phone.

**PERFORMANCE**
- On a phone: no hitch when the boat appears, when 6 tourists board at level 5, at the camera flashes or the confetti.

## 7. Phone layout (PreviewTouch)

- The strip, the line under it, the PHOTO bar and the guide's bubble stack under each other in the Banner zone without overlapping.
- The AFTER panel (NEXT TOUR | END) sits low and a little right of centre, clear of the thumbstick.
- The SHIFT REPORT is centred and fits.
- The RENTAL timer fits on the strip.

## 8. The numbers (Config.Businesses)

| | Level 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Trickle ($/min online) | 256 | 340 | 423 | 507 | 590 |
| Register size | $9,600 | $16,050 | $22,500 | $28,950 | $35,400 |
| Job pay multiplier | 1.00 | 1.06 | 1.12 | 1.18 | 1.25 |
| Upgrade price (to this level) | — | $48,000 | $72,000 | $96,000 | $120,000 |
| Tour boat | Marlin | Marlin | Marlin (canopy) | Moonstone hull (canopy) | Moonstone (luxury) |
| Tourists | 2 | 3 | 4 | 5 | 6 |
| New routes | Marina, Boardwalk | Ferris Wheel Run | Flamingo Coast | Lighthouse Key | The Grand Tour |

- **The trickle** is the PRD's first $130 → $300 (register $5k → $18k) ×~1.97 at every level: the Nov 4 treatment Coffee and the Print Shop got. It pays the $120,000 back in **~7.8 h** online (was ~15.4 h); price + every upgrade at level 5 in ~12.9 h.
- **Routes** (straight legs, berth → stops → dock ring): Marina & Sea Dream ~1,490 studs (1 photo), Boardwalk Beach ~2,290 (1), Ferris Wheel Run ~2,980 (2), Flamingo Coast ~4,720 (3), Lighthouse Key ~4,890 (2), The Grand Tour ~5,500 (4), the Fishing Party's ~750 (2 fishing stops). Half the time a tour is one of the level's newest routes, else any it offers.
- **Rings:** 32 studs radius (as a race checkpoint), tested along the whole stretch driven since the last check. The dock ring: 22 studs, stop under 10.
- **Photo stops:** under 16 studs/s for 2.5 s; PERFECT with 1.5 s of it under 8. Fishing stops: under 10 for 4.5 s; PERFECT with 3 s under 5.
- **The mood:** turns over 60 studs/s² of sideways pull cost up to 10% a second; a ram 15%; running aground 20% + 5% a second; calm driving gives back 0.5% a second. The ★ needs 80%.
- **The pay** (level 1, × JobMult and RateScale): $240 + 18.5¢ a stud + $95 a photo stop, paid whatever happens; a tip of up to 40% of that, from three equal shares: the time (full inside par, gone at 1.5× par), the photos (PERFECT 1, OK 0.4, MISSED 0), the mood (0 at 20%, full at 100%).
  - Par = 4 s + the route ÷ 85 + 7 s a stop. Marina & Sea Dream: $611 + up to $244, par 0:28.
  - ★ inside par, ★ every photo PERFECT, ★ the tourists 80%+ happy; at least ★.
  - ★★★ in a row: the tip ×1.1, ×1.2, ×1.3.
  - Specials, 1 in 8 (equal odds among those allowed): Celebrity (×3 tip on ★★★), Fishing Party (its own route, par ×1.5, +$250), Sunset Tour (dusk and night only, ×1.3).
- **The calibration** (the seeded simulation in the logic tests): **~$1,401 a minute of work at level 1** for a typical player (~90 studs/s, half the photos PERFECT, the tourists ending 60-100% happy); ~$1,307 careless, ~$1,517 smooth at the same speed, ~$1,192 slow, ~$1,542 fast. About one tour in five is ★★★. The streak and the specials are inside that, worth ~2.5%.
- **Speed check:** every leg against the boat's nitro top speed × 1.15, and VehicleGuard (as a taxi fare).
- **Empire XP:** 10 a tour. Customer XP for a rental: 10, at most twice an hour per buyer.
- **The rental:** $150 for 10 minutes on the Splash Jet Ski (the smallest boat in the game, Class "Jet Ski"); a warning at 1:00; it goes back after 60 s off it; $105 to the featured owner, $45 sink.

## 9. Not verified offline (check these in Studio)

- **The dock has never been seen.** Check the gangway meets the pier's end flush (between the showcase dock and the kiosk), the booth's walls and roof, the signs' faces, and that nothing floats or sinks. Check the left and right berths' display boats sit on the water.
- **The tour boat in its berth.** Its float height (DealershipService's display formula), that its hull misses the main pier and the right finger (the Moonstone has 1.5 studs each side), and that it leaves the slip cleanly.
- **The tourists' seats** (`Tour.Seats`) are estimates from the hull sizes: they may sit in the hull or float. Tune the offsets (x, z from the DriverSeat). The Marlin's seat is at its old default spot; the Moonstone's on its aft deck (SeatY 4.5, SeatZ 7).
- **The canopy fit-out** (level 3+) over the tourists' seats, 6 studs over the seat: check it clears the mesh bodies' windscreens.
- **Boarding and stepping off:** the hop arc from the pier to the seat, the sit pose without a Humanoid (as taxi fares), the weld holding them aboard at speed.
- **Physics hand-over:** the boat is anchored at the berth, let go at "all aboard" (network owner: the driver), anchored again at the dock for the glide. Check the driving feels normal after the hand-over and nothing jerks at the dock.
- **Running aground:** the server's ray down from the hull. Check it says aground on the beach and never on open water (the Surf Sprint's start pad floats at x 1625..1655, z -555..-525: no route passes it).
- **Water everywhere on the routes:** the routes reach Lighthouse Key's north shore and the cargo cranes. Drive each once with `route`.
- **Rams:** the deceleration test (150 studs/s², the speed more than halved) on a boat's softer hits. Tune `Mood.RamDecel`.
- **The rental jet ski** floats while nobody sits on it (it appears with you aboard; get off to check).
- **Saving:** `data.businesses.BoatRentals` only persists with Studio API access or in a private live test.

## 10. Shared files changed

- `src/shared/Config/Sounds.lua`: two cues (`TourShutter`, `TourHorn`) and a comment line, both pitched copies of checked assets (Click and Horn). No new asset IDs.
- Nothing else outside the business files. VehicleService (`EjectAll`), VehicleGuard (`Allow`, `RecentlyFlagged`), CarBuilder (`Build`, `PlayPose`), ImpactService (`BumpedAt`), WorldService (`IsNight`, `Lighting.ClockTime`) and GPSClient (`SetPath` with `Height`) are only called or read.

## 11. Studio test, Nov 5 2026 (one player, PC, scratch copy of the place)

**What worked:**
- START JOB > BOAT TOURS: the tour boat appears in its berth with you at the helm.
- Tourists in sun hats hop aboard.
- The strip reads "HAPPY 100% · STOP 1/4", the guide's first line shows, and the GPS line runs on the water.
- The boat drives at ~85 mph and stays upright through hard turns.
- A hard turn drops the mood (100% → 94%), and smooth driving brings it back.
- No server errors or warnings came from any business code.

**Not seen yet:**
- A whole route: the PASS and PHOTO rings, docking and pay.
- The jet ski rental.
- The phone layout of the tour strip.

**One open question:** on the first tour, the player died a few seconds into a hard turn at full speed. Nothing on the server killed them; the only kill code is combat, which logs. The likely cause is falling out of the world. Two more tours with the same driving were fine. If it happens again, note where.
