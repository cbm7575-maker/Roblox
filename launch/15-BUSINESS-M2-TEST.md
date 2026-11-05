# Empire M2: Palm Grind Coffee — Studio test guide

**Status (Nov 4, 2026):** built locally, not committed, not published. Nothing here is live: the whole feature stays off in live servers until `Config.Businesses.Live = true` (owner's go-ahead only). In Studio it always runs.
**Source of truth:** `launch/10-BUSINESSES-PRD.md` (v2, sections 5, 6, 9 and 17). M1 (the Car Wash and the framework) is in `launch/12-BUSINESS-M1-TEST.md`.

---

## 1. What M2 contains

| Piece | Where |
|---|---|
| Every number: the café entry, `Rush`, `ColdBrew`, the pay maths | `src/shared/Config/Businesses.lua` |
| The café building (levels 1-5) and the RUSH ORDERS job | `src/server/Services/BusinessJobs/Coffee.lua` (new) |
| Job modules, the shared customer path (shine + cold brew), the cold brew, Studio helpers | `src/server/Services/BusinessService.lua` |
| Cards (jobs from the config), the GRAB hold, the rush HUD, cold brew toasts | `src/client/Controllers/BusinessClient.lua` |
| +25% sprint stamina while `ColdBrewUntil` is ahead | `src/client/Controllers/LocomotionClient.lua` (a few lines) |
| Offline maths tests | `tools/logic-tests/businesses.sh` |

The Car Wash still works the same way; only its owner toast for a shine now comes from the shared customer path.

## 2. Studio helpers (Studio only)

Run them in the **server** Command Bar through DebugService's `NCCmd` door, as in M1. Read the answer with `print(workspace:GetAttribute("NCResult"))`. `"$me"` is the first player; use `"Player2"` for the second.

| What | Command |
|---|---|
| Test cash | `workspace:SetAttribute("NCCmd", '["cash","$me",200000]')` |
| Own the café free | `workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","give","PalmGrind"]')` |
| Remove it | `... "Debug","$me","remove","PalmGrind"]` |
| Set its level (1-5) | `... "Debug","$me","level","PalmGrind",4]` |
| Fill the register | `... "Debug","$me","fill","PalmGrind"]` |
| Your next rush order ends at a VIP home (any level) | `... "Debug","$me","vip"]` |
| Clear your cold brew | `... "Debug","$me","coldbrew"]` |
| Break-in at the café now (timer in seconds) | `... "Debug","$me","breakin","PalmGrind",120]` |
| Summary | `... "Debug","$me","state"]` |
| Crewmates / time scale / night / phone layout | as in M1: `BizTestCrew`, `BusinessTimeScale`, `["clock",22]`, `PreviewTouch` |

## 3. One player

1. **Map.**
   - PHONE > GPS > PLACES lists "Palm Grind Coffee · Business · $45k".
   - The minimap shows a brown **C** disc on Marina Row, by Marina Link, south-west of the Car Meet.
   - The big map (M) shows the **C** with its name. Tapping it sets the GPS.
   - EMPIRE lists it under **FOR SALE** with "Rush orders: deliver coffee across town against the clock", and only three businesses under COMING SOON.
2. **The lot at level 1.** Drive there and check:
   - A cream café with a glass front, the door in the middle, a green awning with a lamp over it.
   - The plate on the header reads "FOR SALE · $45,000"; beside it a green "COLD BREW $60" sign; the "PALM GRIND" roof sign; a chalkboard by the door.
   - Inside: the counter with the register, **ORDER HERE** on its left, **RUSH ORDERS · PICK-UP** on its right (paper bags on a shelf, a yellow mat on the floor), the back bar with the espresso machine and the MENU, two tables by the window.
   - Three parking bays on the forecourt ("PARKING" in the middle one), palms at the right-hand corners, a dumpster in the back corner.
   - None of these yet: terrace, drive-through paint, queue, roaster, rooftop.
   - Nothing blocks Marina Link. You can't walk through the walls. Output has no "lot overlaps" warning.
3. **Buy.** Give yourself cash.
   - The door bubble reads "View / Buy $45,000". The card shows the price, the job, the register line, the blurb and "Level 5: a rooftop café · more VIP orders."
   - **BUY**: the YOU OWN IT stamp, the toast about START JOB and the RUSH ORDERS shelf, the plate reads "★ YOUR PALM GRIND ★", the bubble reads "Manage", the minimap C gets a gold ring, EMPIRE moves it to YOUR BUSINESSES.
4. **Levels and props.** **UPGRADE $18,000** stamps LEVEL 2. Then set 3, 4 and 5 with Debug and check:
   - **L2:** wooden decks either side of the door path, three tables with umbrellas (cream, green, cream), planters along the front.
   - **L3:** the drive-through loop painted round the café: in on the right, behind the café, out on the left, with arrows and "DRIVE-THRU" / "EXIT" on the ground. The side window gets an awning, a ledge and a "DRIVE-THRU · PICK UP HERE" sign. A menu board and a speaker on the right. A "DRIVE-THRU" pole sign at the mouth. At night (`["clock",22]`): amber neon round the roof sign, along the roof's front edge, over the window and under the pole sign.
   - **L4:** a copper roaster in the back-left corner (hopper, cooling tray, a chimney through the roof), burlap sacks, the ROASTERY sign; four customers queued outside the door.
   - **L5:** on the roof: glass balustrades with string lights (lit at night), three tables (two with umbrellas), a potted palm, the stair house and a "ROOFTOP CAFÉ" sign.
   - Check the umbrellas don't clip the roof sign, the chimney or the stair house, and the words painted on the ground read the right way up from the lane.
5. **Rush orders (level 1).** Press **Manage > START JOB**.
   - The card closes. A toast explains the job. The strip reads "RUSH ORDER  GRAB AN ORDER AT THE RUSH ORDERS SHELF". END JOB shows.
   - Stand on the yellow mat: **HOLD TO GRAB THE ORDER** appears (F, RT, the mouse or a finger). Let go early: "Hold it until the bar is full...", and nothing happens.
   - Hold it for 2 s. You get:
     - the toast "Order up! Take it to <name>. Get in your car: the clock is running (0:3x).";
     - a gold ring and beam at the address, and the GPS route;
     - the strip "GET IN YOUR CAR · DELIVER TO <NAME>" with "$200  0:3x" on the right (a PC; a phone shows the clock only).
   - Call your car (CAR) and get in: the strip drops "GET IN YOUR CAR". Watch the tip stay at $200 until about a third of the clock is left, then fall.
   - Stop in the ring. You get "Delivered to <name>: +$X (tip $Y)" (about $900-1,600 at level 1) and the ORDER DELIVERED stamp. The ring goes, the GPS routes back to the café, and the strip reads "BACK TO PALM GRIND FOR THE NEXT ORDER" with the distance.
   - Drive back: the GPS clears near the café, and the strip asks for the next grab.
   - **Late:** take the next order and let the clock run out. The right side reads LATE in orange, and the toast says "(late: no tip)". The base is still paid.
   - **END JOB:** "Job over. N jobs, $X."
6. **Rush orders: the endings.** Check each one:
   - After a grab, don't get in a car for 45 s: "Job over: get in your own car after you grab an order".
   - Get out of your car for 10 s mid-order: "Job over: you left your car with the order."
   - Get wanted (`["heat","$me",1]`): the job ends.
   - Stand around without grabbing for 5 minutes: "Job over: no order picked up for a while."
   - Start a taxi shift on the way: the rush job ends ("Job over.").
   - A boat or someone else's car doesn't count as your car.
7. **Multi-stop and VIP.**
   - At level 2 an order has 2 stops. The strip shows "(1/2)" then "(2/2)". The second clock starts when the first stop is paid. The last stop pays the most: it includes the drive back.
   - At level 4 set `vip` first. The order has 3 stops. The last reads "VIP ORDER · <PENTHOUSE / VILLA / MANSION> (3/3)", with the toast "Last stop: a VIP order for <who> at <home>. VIPs tip big!". The ring sits on the verge in front of that home. It pays about 1.5× a normal stop.
8. **Cold brew** (anyone, on foot).
   - At ORDER HERE the bubble reads "Cold brew $60" (E). It doesn't show from a car seat.
   - Buy it: you pay $60 and get the toast "Cold brew! +25% sprint stamina for 5 minutes."
   - From full stamina, a sprint lasts about **15.6 s instead of 12.5 s** (time both: clear it with `coldbrew` for the normal one).
   - Buy again straight away: "You've still got a cold brew going!" After the 5 minutes: "Your cold brew wore off."
   - As the café's only owner, you pay and nobody gets a share.
9. **Break-in at the café.** Buy a pistol first, then run `breakin PalmGrind 120`.
   - The red toast, the GPS route, the C flashing red, the BREAK-IN strip.
   - 1-2 robbers stand in front of the counter, facing the register. Scare one: it runs out of the door into the parking area and fades. Punch the other.
   - Check the robbers stand on the café floor (not sunk in it or floating).
   - On a rush job at the shelf, the GRAB hold hides while the break-in is on, so your gun can come up.
10. **Panels.** With a pistol out, stand on the yellow mat while waiting for an order: the gun lowers while the HOLD button shows, and F grabs the order (never GET IN).

## 4. Two players (Test > Clients and Servers, 2 players)

1. **Featured owner.** P1 owns the café at level 3, P2 owns nothing: P2 sees "Player1's Palm Grind" and the level 3 props. Give P2 the café: P2 sees "★ YOUR…" and level 1, P1 still sees level 3.
2. **A cold brew pays the owner.** P2 buys a cold brew. P1 gets "Player2 got a cold brew at your Coffee Shop +$42" and +10 Empire XP; P2 pays $60.
   - The XP cap: clear P2's cold brew (`"Player2","coldbrew"`) and buy twice more. The third buy in the hour still pays P1 $42 but gives no XP (check P1's EmpireXP).
   - The shine still reads "Player2 got a shine at your Car Wash +$70".
3. **The crew.** Turn on `BizTestCrew`.
   - P2 at the café's door gets the CREW card with **RUSH ORDERS**, BUY YOUR OWN and CLOSE.
   - P2 runs an order: P2 is paid in full, and P1 gets "Player2 worked your Coffee Shop: +$xxx crew cut" for each stop.
   - While P2 is on the lot, P1's manage card reads "(+25% busy: crew here)". P2 sees P1's props.
   - P2's order sizes and pay follow P1's level.
4. **Both businesses at once.** P1 owns both. With P1 on rush orders, START JOB at the Car Wash says "You're working at another business. END JOB first." Break-ins pick whichever register is fuller.

## 5. Phone layout (PreviewTouch)

- The GRAB hold uses the M1 HOLD button: right of centre, above the jump area, the bar filling coffee-brown.
- The strip shows the clock only (no tip) and fits "DELIVER TO … (2/3)"; long names are cut with "…".
- END JOB in the side column; the order toasts don't cover the strip.
- The Manage card's START JOB starts rush orders straight away (no sub-menu: the café has one job).

## 6. The numbers (Config.Businesses)

| | Level 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Trickle ($/min online) | 96 | 132 | 168 | 204 | 240 |
| Register size | $3,600 | $6,300 | $9,000 | $11,700 | $14,400 |
| Job pay multiplier | 1.00 | 1.06 | 1.12 | 1.18 | 1.25 |
| Upgrade price (to this level) | — | $18,000 | $27,000 | $36,000 | $45,000 |
| Stops an order | 1 | 2 | 2 | 3 | 3 |
| VIP chance (the last stop) | — | — | — | 35% | 50% |

**Rush orders (level 1; × the level's multiplier)**
- **GRAB:** a 2 s hold on the RUSH ORDERS shelf, timed by the server.
- **Stops:** the first is 400-1,000 studs (straight line) from the café; each next one 300-700 from the last, on a kerb. A VIP stop is a big home's verge spot, up to 2,600 studs away.
- **The clock per stop:** road ÷ 45 + 18 s for the first (it includes walking to your car), + 8 s for the others.
- **Pay per stop:**
  - $60 + 40¢ a stud of road;
  - the first stop also carries the order's $320;
  - the last stop also pays 40¢ a stud of the road back to the café.
- **Tip per stop:** up to $150. It's full (GOLD) while at least 22% of the clock is left, falls to $0 at 0:00, and late pays no tip (the base is still paid). A perfect run (every stop GOLD) adds $150. (Changed by the fun pass, launch/18.)
- **VIP:** ×1.5 on that stop's pay and tip (not on the drive back).
- **Per minute of work**, counting ~17 s at the café an order, ~45 studs/s on the road and the drive back:
  - one stop: **~$1,252/min** (GOLD on ~57% of stops);
  - two stops: about +7.5%;
  - three stops: about +9% (fewer trips back).
- **Rules:** speed check per leg (FastSlack 1.15) and VehicleGuard, the ring is 32 studs (stop under 6 studs/s), 45 s to get in your car after a grab, 10 s out of it once driving, 5 minutes idle.
- **Empire XP:** 6 per stop (the worker).

**Cold brew:** $60 for 5 minutes, +25% sprint stamina (the sprint drains at 0.8×: 12.5 s becomes 15.6 s). The featured owner gets $42 (70%) and $18 is a sink. Customer XP is 10, at most twice an hour per buyer. Buying again is refused while more than 4 minutes are left.

**Payback:** the trickle alone pays back the $45,000 in ~7.8 h online ($96/min, raised by the fun pass to sit inside the 6-8 h target). Working the job 40% of the time adds ~$140/min over normal work (40% × ($1,250 − $900)): about 3.2 h in all.

## 7. Not verified offline (check these in Studio)

- **The building's look.** It has never been seen:
  - the lot faces west onto Marina Link;
  - the words painted on the ground (the M1 shine lane uses the same trick);
  - the queue's part figures;
  - the rooftop props sitting on the roof;
  - the chimney through the roof;
  - prop clipping in general.
- **Addresses near the marina.** `JobService.RoadsideSpot` has to find kerb spots 400-1,000 studs from the café. If "No customer is home right now" shows often, widen `Rush.FirstMin/FirstMax`.
- **The VIP verge spots.** Check the ring in front of the penthouse, villa and mansion is reachable and not on the road.
- **The clock and the tip.** The timing model is an estimate (~45 studs/s). Time real orders and tune `EstSpeed`, `FirstExtra` and `TipFull`.
- **Prompts at the counter.** The door bubble and ORDER HERE are a few studs apart. Check the right one shows from the counter (Roblox shows the nearest per key).
- **The stamina hook.** Check the sprint really lasts longer and the bar drains slower. Check nothing changes once it wears off.
- **Saving.** `data.businesses.PalmGrind` only persists with Studio API access or in a private live test.

## 8. Left for M3+

- **M3:** Backlot Print Shop (presses, laundering runs, dirty cash, police raids with the AI fallback).
- **M4:** Coastline Boat Rentals (Empire 2).
- **M5:** Afterglow Nightclub (Empire 3).
- **Each of these** now plugs in as a job module (`Services/BusinessJobs/<Style>.lua`: `Style`, `Start`, `Step`, `Tick`, `Resend`) plus a config entry with `Jobs`, `Service` and `Layout`.
