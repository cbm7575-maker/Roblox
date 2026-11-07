-- Businesses (ModuleScript, ReplicatedStorage.Shared.Config.Businesses)
-- Empire: player-owned businesses (launch/10-BUSINESSES-PRD.md, version 2, approved Nov 4 2026). The one
-- place for every number, place and rule. BusinessService (server) decides everything from it; BusinessClient
-- and the phone's EMPIRE app draw from it; tools/logic-tests/businesses.sh checks its maths offline.
--
-- THE IDEA: a business is a place you PLAY, not a bank account you defend. Owning one gives you:
--   * its own job (Car Wash: the wash-bay mini-game and detail deliveries), paying about 1.3x a normal job;
--   * a small register "trickle" while you are in the server (never while you are offline);
--   * customers: other players buy a service there (Car Wash: the drive-through shine) and the featured owner
--     gets CustomerShare of it, the rest is a money sink;
--   * a building that grows: 5 levels, each with its own props, drawn per device (see "Levels" below);
--   * a risk that fits it: legit businesses only get NPC break-ins (BreakIn below). Players never rob players.
--
-- MANY OWNERS, ONE BUILDING (PRD section 7). Like homes, many players can own the same business. Each owner
-- has their own level, register and job counts (saved as data.businesses[id]). The building in the street
-- shows, on each device: your own level if you own it; else your crewmate's (the highest crewmate owner in
-- the server); else the FEATURED owner's (the highest-level owner in the server, ties: the most lifetime
-- earnings, then the lower UserId); else level 1. The featured owner's name is on the sign and they get the
-- customer money.
--
-- M1: the foundation and the Car Wash. M2: Palm Grind Coffee (RUSH ORDERS and the cold brew; its building and
-- job live in ServerScriptService.Services.BusinessJobs.Coffee). M3: the Backlot Print Shop, the first SHADY
-- business (PRINT and LAUNDER, dirty cash, police raids with the AI fallback; its building, job and raids live in
-- ServerScriptService.Services.BusinessJobs.PrintShop; numbers in Print, Launder and Raid below). M4: Coastline
-- Boat Rentals, unlocked at Empire rank 2 (BOAT TOURS on water checkpoints and the jet ski rental; its building,
-- tours and rentals live in ServerScriptService.Services.BusinessJobs.BoatRentals; numbers in Tour and Rental
-- below). M5: the Afterglow Nightclub, unlocked at Empire rank 3 (VIP PICKUPS in the club's limo with paparazzi,
-- the register doubling at night, the club inside with the cover charge and the VIP booth, and the shady BACK ROOM
-- with its police raids; its building, job, club and back room live in ServerScriptService.Services.BusinessJobs.
-- Nightclub, the raids in the shared BusinessJobs.Raids; numbers in Vip, Club, BackRoom and NightShare below). Only
-- entries with Enabled = true are built, listed, buyable or saved-to.
--
-- SHADY BUSINESSES (Kind = "Shady", PRD section 5, pillar 3). No player customers, never an NPC break-in
-- (Businesses.BreakInEligible: legit only), and no star for collecting the register (the PRD's M3 notes: raids,
-- not collect stars). Their job makes DIRTY CASH (saved per owner as data.businesses[id].dirty, never spendable,
-- capped by Print.Stock at the owner's level), which only becomes money by laundering it, and which police raids
-- can seize while it sits in the shop. Clean money, the register and the upgrades are never touched by a raid.
--
-- LAUNCH SWITCH: Businesses.Live. In Studio the feature always runs (so it can be tested). In a live server it
-- only runs when Live = true: BusinessService does nothing (no buildings, no remotes) and the phone hides
-- the EMPIRE app. So the code can ship with an unrelated update without the feature going live early. Turn it
-- on only with the owner's explicit go-ahead.
--
-- BALANCE (worked out Nov 4 2026 from the live configs; the PRD's section 9 targets):
--   Baseline: active play for a mid-game player is about $900 a minute. Taxi / courier fares (JobService) pay
--   $150 + 35c a stud + a $100 tip: about $670 a fare, one every 40-50 s, so $800-1,000/min. Store robberies
--   ~$600/min, tier-2 heists ~$1,000/min, winning Downtown Dash ~$1,000/min.
--   Car Wash job target: about $1,150 a minute of WORK at level 1, counting the downtime between jobs. (Re-tuned
--   Nov 4 2026 for the fun pass, launch/18-BUSINESS-FUN-PASS.md: the timing gauges, the ratings, the streaks and
--   the special customers. Every bonus is INSIDE these averages, never on top: the logic tests simulate them.)
--     * WASH: one car is about a 31.6 s cycle for a typical player: 6 s pull-in + 4 s pull-out of the last car
--       + ~2 s to pick NEXT CAR, the SPRAY and RINSE gauges let go in their green bands (~5.0 + 4.4 s, ~1 s to
--       start them), scrubbing 4-6 spots (~14.5 taps: 0.35 s a tap + 0.5 s from spot to spot, ~7 s) and ~2 s
--       of looking around. Pay $430 + $30 a bird-mess spot (~1 a car) + the tip: $165 x (spray + rinse + quick)
--       / 3, where a PERFECT counts 1, an OK 0.4 (Wash.OkShare), the quick wash (StarTime) 1. A typical player
--       (half the holds PERFECT, mostly quick: ~20% of washes ★★★) averages ~$133 of tip a car, the ★★★ streak
--       (x1.1-1.3) and the specials (1 in 8: x1.5, x2, a ★★★ x3) included. The seeded simulation in the logic
--       tests: ~$1,148/min typical, ~$1,074 for an all-OK player, ~$1,288 for an all-PERFECT one; without the
--       bird mess, the specials and the streak the same player would make ~$1,050, so those ~9% are inside the
--       average. (The old rules, $420 + $140 for the ~85% of clean finishes, made ~$1,080 on the old 30 s model
--       but only ~$1,023 on this one, which counts ~3 s of reacting and looking around: both under the target.)
--       Nobody beats MinTime (the gauges' Min and the tap gap enforce it already). Time real washes in Studio.
--     * DETAIL DELIVERY: straight line 600-1500 studs (average ~1,050), ~1.3x that by road (~1,365 studs);
--       ~15 s to start and get in, ~30 s each way, ~10 s to call your own car back (CAR) -> ~85 s a delivery.
--       $500 + 65c x 1,365 + the speed tip less dents. The simulation: the trip takes 0.85-1.35x the estimate,
--       0.5 dents a trip on average (61% clean). On the old rules that is ~$1,118/min; one customer car in five
--       is a sports car (x1.5 tip, $100 a dent) and clean deliveries in a row build the streak (x1.1-1.3 tip),
--       which together land it on ~$1,144/min, the target, so the base pay is unchanged (a careful driver
--       ~$1,189, one who crashes a lot ~$1,088).
--     So either job, or any mix, averages about $1,150 a minute of work at level 1 (x the level's JobMult).
--   Coffee job target (M2, worked out Nov 4 2026; re-tuned the same day for the fun pass): about $1,250 a
--   minute of WORK at level 1, counting the downtime between orders (parking at the café, walking in, the GRAB
--   hold and walking back out, the drive back from the last address). The same driving model as the detail
--   delivery (~45 studs/s on the road, the road ~1.3x the straight line):
--     * ONE ADDRESS (levels 1): ~17 s at the café (park, walk to the shelf, 2 s GRAB, back to the car), the
--       first leg (400-1,000 studs straight, ~700 -> ~910 of road: ~20 s + ~3 s to stop in the ring) and the
--       drive back (~910 of road, ~20 s): ~60 s an order. The simulation spreads the drive over 0.8-1.2x the
--       typical time: a GOLD (22%+ of the clock left: the full tip) about 57% of the time, else mostly SILVER.
--       $320 order + $60 drop + 40c x (910 + 910) + the tip ($150 at most) = ~$1,252/min with the gold streak
--       (x1.1-1.3) and RUSH HOUR (+25% tips ~2 minutes in 10) inside it (~$1,235 without them; a fast driver
--       ~$1,396, a slow one ~$1,116). (The old rules, $330 + a $200 tip that was full only with 35% of the
--       clock left, made ~$1,243 on the same model: medals were made reachable, so the tip shrank to keep the
--       average.)
--     * TWO / THREE ADDRESSES (levels 2-3 / 4-5): each extra leg is 300-700 studs (~650 of road, ~17 s with
--       the stop), and the way back is longer (the last address is ~860 / ~990 studs out). Fewer trips back
--       per address make them pay a little more a minute: ~$1,346 (+7.5%, 2 addresses) and ~$1,364 (+9%, 3),
--       PERFECT RUN bonus included (Rush.PerfectRun: every stop a GOLD), on top of the level's JobMult. A VIP
--       drop (levels 4-5) pays x1.5 (its pay and tip).
--     The drive back is paid (PerStud on the road from the last address back to the café, with the last
--     drop), so a far order pays for its trip home and every order pays about the same a minute.
--   Trickle (PRD: Car Wash $60 -> $150 a minute, register $2k -> $9k): the price pays back in ~7 h online on
--   the trickle alone (25,000 / 60 = 417 min); working the job 40% of the time adds its premium over normal
--   work (40% x ($1,150 - $900) = $100/min), so ~2.6 h. Upgrades (40 / 60 / 80 / 100% of the price) pay back at
--   about the same rate (level 2: +$23/min trickle and +6% job pay; ~3 h). Coffee: $96 -> $240 a minute,
--   register $3.6k -> $14.4k (raised Nov 4 from the PRD's first $80 -> $200, $3k -> $12k, which paid back in
--   ~9.4 h: the owner wants businesses to really make money). Its $45,000 now pays back in ~7.8 h on the
--   trickle alone (45,000 / 96 = 469 min), ~3.2 h working the job 40% of the time (+$140/min); the registers
--   were raised with the trickle, so they still take ~37-60 minutes to fill.
--   Print Shop job target (M3, worked out Nov 4 2026; re-tuned the same day for the timing game, the streak and
--   the clean-run bonus): about $1,600 a minute of WORK at level 1 WITH the risk (PRD section 9: the most
--   profitable business, and the most dangerous). The loop is print, print, print, print, launder:
--     * PRINT: three timing holds in order (Print.Stations: their green bands' middles are 5.0, 4.4 and 6.2 s)
--       about 12 studs apart: ~15.6 s of holding + ~10 s walking + ~4 s finding the spot = a ~30 s press run.
--       An all-OK run prints Print.Batch ($1,250 at level 1, x JobMult) of dirty cash; PERFECTs and the streak
--       print more. A typical player hits about half of the bands: x~1.13, ~$1,412 a run (the logic tests work
--       it out). ~4 of those (~119 s) fill one launder load (Launder.Carry, $5,600).
--     * LAUNDER: walk out to the cash cart and park in the loading bay (~10 s), hold LOAD (3 s), get in (~3 s),
--       drive to a drop 800-1,600 studs away (straight ~1,200 -> ~1,560 of road at ~45 studs/s: ~35 s + 3 s to
--       stop) and back (~35 s): ~89 s. The dirty cash turns into clean cash 1:1 (Launder.Rate), +10% for a
--       clean run (Launder.CleanBonus: no stars on the way).
--     THE RISK: ~38 s of each run is a drive with the bags: ~3 tip-off rolls at 5% (~14% of runs) plus the heat
--     meter filling near the police (~6% more on a server with cops about): ~20% of runs spotted (1 star; 2 with
--     the police close by). Say a quarter of those end in an arrest (the bags are gone) and the rest cost ~50 s
--     escaping. A load then pays 5,600 x (0.8 x 1.10 + 0.2 x 0.75 x 1.00) = ~5,768 in 119 + 89 + 7.5 = ~215.5 s:
--     ~$1,606/min; the odd raid on a stock left waiting trims it to ~$1,600. The streak and the clean-run bonus
--     are part of that average, never on top of it: an all-OK printer makes ~$1,500/min, a perfect one ~$1,850,
--     and with no risk at all (every run clean) it would be ~$1,780. Higher levels carry ~4.2 typical runs a
--     load instead of 4 (fewer trips), so level 5 pays ~1.28x level 1, like the café's bigger orders.
--     The register trickle: $192 -> $450 a minute, register $7k -> $26k (raised Nov 4 from the PRD's first $110
--     -> $260, $4k -> $15k, which paid back in ~13.6 h: the owner wants businesses to really make money; the
--     registers grew with it, so they still take ~36-58 minutes to fill). It pays the $90,000 back in ~7.8 h
--     online on its own (90,000 / 192 = 469 min); working the job 40% of the time adds ~$280/min over normal
--     work (40% x ($1,600 - $900)), so ~3.2 h. Every level grows in the same proportion as before (x1.75), so
--     each business's whole investment (price + upgrades) at level 5 pays back in about the same 11-13 h of trickle.
--   Boat Rentals job target (M4, worked out Nov 4 2026): about $1,400 a minute of WORK at level 1, every bonus
--   inside (the ★★★ streak, PERFECT photo stops, the special tours). One BOAT TOUR is the unit of work:
--     * THE CYCLE: the tourists hop aboard (0.45 s each + 1.2 s), the tour itself (from "go" to stopped in the
--       dock ring: the route's straight legs at ~90 studs/s for a typical driver, the Marlin's 140 top speed less
--       the turns and the slowing down the tourists like, + every PHOTO STOP's 2.5 s hold and ~3 s slowing down
--       and speeding up again, + ~3 s to stop in the dock ring), the glide into the berth (1.2 s), the tourists
--       stepping off and cheering (2.5 s, the stamp on screen meanwhile), ~2 s to press NEXT TOUR and ~2 s a tour
--       of the first walk from the door to the boat. Level 1's two routes are ~1,500 and ~2,300 studs with one
--       photo stop each: a ~32 s tour on average, a ~44 s cycle.
--     * THE PAY (Businesses.TourPay): Tour.Base + PerStud a stud of the route + StopPay a photo stop (paid
--       whatever happens), and a tip of up to TipRate of that, from three shares (the time against par, the
--       photo stops: PERFECT 1, OK 0.4, missed 0, and how happy the tourists ended up). ★★★ tours in a row raise
--       the tip (Businesses.Streak), and about one tour in eight is special (a celebrity: ×3 tip on ★★★; a
--       fishing party: its own slow route with two fishing stops and a bonus; a sunset tour at dusk and at night:
--       ×1.3 on the whole tour). Pay per stud and per stop is worked out from the same ~$17 a second of base pay
--       for every part of the cycle (Base $240 for ~13 s, 18.5c a stud at ~90 studs/s, $95 a ~5.5 s photo stop),
--       so a long route pays about the same a minute as a short one; the tip adds ~30% on average.
--     The seeded simulation in the logic tests: ~$1,400/min for a typical player (half the photo stops PERFECT,
--     the tourists ending 60-100% happy, ~90 studs/s), ~$1,310 for a careless one and ~$1,520 for a smooth one at the
--     same speed (~$1,660 smooth and fast); about one tour in five is ★★★. The streak and the specials are inside
--     that average, not on top (they're worth ~2.5%: the tip is a smaller share of a tour than of a wash). Higher
--     levels' longer routes and more tourists pay about the same a minute before JobMult (within ~5%).
--     The register trickle: $256 -> $590 a minute, register $9.6k -> $35.4k (the PRD's first $130 -> $300,
--     $5k -> $18k, which paid back in ~15.4 h, x~1.97 at every level: the Nov 4 treatment Coffee and the Print
--     Shop got, as the PRD says). It pays the $120,000 back in ~7.8 h online on its own (120,000 / 256 = 469
--     min); working the job 40% of the time adds ~$200/min over normal work, so ~3.3 h. The registers still take
--     ~37-60 minutes to fill, and price + upgrades at level 5 pay back in ~12.9 h of trickle (the others: 10.6-12.7).
--   Nightclub job target (M5, worked out Nov 5 2026): about $1,500 a minute of WORK at level 1, every bonus inside
--   (the ★★★ streak, PERFECT stops, losing the paparazzi, the special VIPs and the night pay). One VIP is the unit:
--     * THE CYCLE: the drive out to the pickup (straight 600-1,700 studs, ~1.3x that by road, ~45 studs/s for a
--       typical driver, + ~3 s to stop in the ring), the VIP getting in (~3 s), the drive back (the same road + ~4 s
--       to stop on the VIP mark), the red carpet and NEXT VIP (~5 s) and the first walk to the limo: ~75-80 s.
--     * THE PAY (Businesses.VipPay): Vip.Base + PerStud a stud of road both ways, paid whatever happens; a tip of up
--       to TipRate of that from three shares (the time against par, the VIP's comfort, the stop on the mark); x
--       NightMult at night (the Nightclub's night is Businesses.NightShare of the time, 42.4%); Pap.Bonus for losing
--       the paparazzi (a ride in Pap.Chance); specials about 1 in 8. ★★★ arrivals in a row raise the tip.
--     The seeded simulation in the logic tests: ~$1,500/min for a typical player, less careless, more smooth and
--     fast; the streak, the specials and the paparazzi bonus are inside it, worth a few %; night pickups pay ~1.25x day
--     ones, so the average is ~10% over a day-only one.
--     The register trickle: $375 -> $875 a minute by day, x2 at night (Nightclub.NightMult), register $20k -> $75k.
--     That is the PRD's first $180 -> $420 (x2 at night: ~$256 a minute on average, ~16.3 h payback) given the Nov 4
--     treatment: x~2.08, so the average over a day and night ($534 a minute at level 1) pays the $250,000 back in
--     ~7.8 h online. The registers were sized on the same average: ~37 minutes to fill at level 1 and ~60 at level 5
--     (by day ~53 -> ~86, at night ~27 -> ~43). Price + upgrades at level 5 pay back in ~12.7 h of trickle.
--     THE BACK ROOM (Businesses.BackRoom) adds a little dirty cash at night (~$34 a minute on average at level 1),
--     with the raid risk; it isn't counted in the payback.
--   STACKING: owning all five at level 5 trickles about $2,305/min by day (150 + 240 + 450 + 590 + 875) and $3,180
--   when the club doubles at night (it was $1,330 before the Nov 4 raise, $1,560 before M4 and $1,850 with the
--   Nightclub's placeholder numbers). RateScale turns EVERY income (trickle and job pay, the dirty cash printed and
--   the back room's, the raid rewards; never prices) up or down at once if the economy runs hot.
--
-- PLACES. Position = the lot centre on the ground (y = 0); Facing = the direction from the building to the
-- street it faces. Every lot uses the same frame ("lot space"): origin at the lot centre, -Z toward the street,
-- +X to the right as you look at the street from the building. Lots are 56 wide (x -28..28) and 50 deep
-- (z -25..25). The Car Wash lot (and the Coffee and Print Shop lots, for M2/M3) were picked from the place
-- file's own parts on Nov 4 2026: clear of every building, road (12+ studs from the road's edge), home lot,
-- runtime lot, heist / spawn / activity pad and apartment tower entrance. (The Coffee lot was checked again for
-- M2 against the current place file: its 50 x 56 world box, x 480..530, z 877..933, holds nothing; its street
-- edge is 14 studs from Marina Link's (x 434..466); the Car Meet's and the Courier Depot's runtime lots are
-- 40+ studs to the north.) (The Print Shop lot was picked again for M3: the first draft's spot, x 807 z -895,
-- turned out to be on Palm Hills ground, not the Docks. The new one is in Rustwater Docks' back streets, on the
-- north side of the z = 1650 street between the x = -650 and x = -300 streets, beside the container lot: its
-- world box x -424..-368, z 1562..1612 holds nothing in the place file (the nearest parts: street palms on the
-- verge 3.5 studs in front, the container stacks 9 studs behind, crates and a forklift 15+ studs to the east);
-- its street edge is 22 studs from the road's (z 1634); the Chop Shop pad, the Hideout pad, the Big Score
-- depot, ATM3, both stunt ramps, every home and the other two businesses are 200+ studs away.) (The Boat Rentals
-- lot, M4, is on the WATER: a floating dock just off the end of the first marina pier (z = 1100), where Marina
-- Boat Sales' kiosk stands. Its world box x 1706..1756, z 1072..1128 holds nothing in the place file (checked
-- Nov 4 against NeonCoast.rbxl: the pier ends at x 1684; the nearest parts are the civilian boat pads at z 1134+,
-- 6 studs south, invisible and never queried). Marina Boat Sales' runtime lot (its kiosk and the showcase dock
-- with the boats for sale, x 1668..1700, z 975..1110) is 6 studs west, and a 22-stud gangway joins the two: from
-- the pier's end between the showcase dock and the kiosk (z 1093.5..1099.5) to the dock's front deck. Every tour
-- leg was checked the same way: nothing of the place within 28 studs of any leg, nothing above the sea bed in
-- any ring; the legs past the Ferris pier keep 47+ studs off its end.) (The Nightclub lot, M5, is on the BEACH side
-- of the boardwalk across Highway 1 from downtown, facing west over the boardwalk to the highway: its world box x
-- 1125..1175, z 327..383 holds nothing in the place file (checked Nov 5 against NeonCoast.rbxl: the nearest parts
-- are the fronds of the boardwalk's palm row, up to x 1116, 9 studs in front, non-colliding meshes; the boardwalk's
-- planks are at x 1065..1076). Club Nova, the heist, is 426 studs south (its building x 1031..1147, z -201..-99),
-- the beach snack shack 57 studs south; the highway's east edge (x 1030) is 95 studs in front, and the limo drives
-- out across the sand and the boardwalk to it (the palms let cars through). No home, runtime lot, pad or business
-- is near it.) The buildings go in Workspace.Shops
-- (beside Coast Arms), which the car-spawn check, CarjackService, Look4's palms and billboards and
-- ApartmentService already keep clear of.
-- Layout (lot space, on the ground):
--   Door      the bottom middle of the doorway: the Buy / Manage prompt
--   Register  the till on the counter: where break-in robbers rummage
--   Robbers   where the 1-2 robbers stand (in front of the counter, facing it)
--   Exit      where scared robbers run to before they vanish (out on the forecourt)
--   Bays      wash bay centres (a customer car's middle), bay 1 first; Bays[level] of them are open
--   BayMouth  z of a customer car's middle where it starts its pull-in (at the bays' open front)
--   Shine     the drive-through shine lane's gantry (the "Shine $100" prompt hangs here)
--   Pickup    where a detail-delivery customer car waits (facing the street)
--   Service   (Coffee) the ORDER HERE spot in front of the counter, where a customer stands: the cold brew prompt
--   Orders    (Coffee) the RUSH ORDERS pick-up shelf's spot in front of the counter: where a worker holds GRAB
--   Stations  (Print Shop) where a worker stands for the three PRINT holds, in order: the paper pallet, the plate
--             bench, the press
--   Search    (Print Shop) the spot by the presses where cops hold SEARCH in a raid
--   Bay       (Print Shop) the loading bay's middle: your own car must be parked here to load the bags
--   Load      (Print Shop) the cash cart by the roll-up door: where a worker holds LOAD (on foot)
--   RaidCar   (Print Shop) where an AI raid's police car parks; RaidStand: where its officers stand to breach
--   Inside    (Print Shop) the building's floor { x0, x1, z0, z1 }: an owner or crewmate in here holds the door
--   Tray, Cash (Print Shop) the press's out tray and the counting table (looks only: BusinessClient's effects)
--   Berth     (Boat Rentals) the tour boat's middle in its slip (nose to +Z, out to sea): it appears and docks here
--   Queue     (Boat Rentals) where the tourists wait on the main pier, beside the berth, before they hop aboard
--   SlipMouth (Boat Rentals) the slip's open end: the tour's GPS line leaves and comes back through here
--   Dock      (Boat Rentals) the middle of the ring a tour ends in (just outside the slip): stop in it to dock
--   Rentals   (Boat Rentals) where a rented jet ski appears (its middle, nose to +Z), one per slot
--   Service   (Boat Rentals) the JET SKI RENTALS stand at the head of the rental slip: the rental prompt
--   Service   (Nightclub) the velvet rope by the door: the COVER CHARGE prompt (the club's way in)
--   LimoBay   (Nightclub) the limo's middle in its bay on the forecourt (nose to the street): it appears here
--   Carpet    (Nightclub) the VIP mark beside the red carpet: the limo's middle when it stops right (the red-carpet ring)
--   Flashes   (Nightclub) where the press's camera flashes go off as a VIP walks the carpet
--   Safe      (Nightclub) the back room's safe: the owner holds WASH here
--   BackDoor  (Nightclub) the back room's door, where the cops breach in a raid; Search: where they search the safe
--   RaidWayIn, RaidPathIn (Nightclub) the AI officers' way in through the front door, and on through the back door
-- Jobs: what START JOB offers there ({ Kind, Label }; BusinessService checks the kind against this list).
-- Service: the customer purchase ({ Name, Price, Kind = "Shine" | "ColdBrew" | "Rental", Words = in the owner's
-- toast }).

local Businesses = {}

------------------------------------------------------------------ switches and the economy

-- Live servers only run the feature when this is true (Studio always does; see LAUNCH SWITCH above).
-- Turned on Nov 6 2026 with the owner's go-ahead ("do the test and push to live").
Businesses.Live = true

Businesses.RateScale = 1 -- x every business income (trickle and job pay). 1 = the numbers below.
Businesses.TickSeconds = 30 -- the server settles every register this often (and before every action)
Businesses.MaxLevel = 5
Businesses.Reach = 34 -- studs (flat) from the lot centre where the cards' buttons work and a crewmate counts as "at" the business
Businesses.DoorRange = 16 -- studs from the doorway the door prompt is accepted from (its reach is 10)

-- Upgrade prices: level N costs this share of the business's price (PRD: 40 / 60 / 80 / 100%).
Businesses.UpgradeShare = { [2] = 0.4, [3] = 0.6, [4] = 0.8, [5] = 1.0 }

Businesses.CustomerShare = 0.7 -- the featured owner's share of what a player customer pays (the rest is a sink)
Businesses.CrewCut = 0.2 -- a crewmate works your business: they get their normal pay, you get this much on top (the game pays it)
Businesses.BusyBonus = 0.25 -- +25% trickle while one or more of the owner's crewmates is at the business (within Reach)

------------------------------------------------------------------ Empire rank (1-10)

Businesses.Empire = {
	MaxRank = 10,
	-- Total Empire XP needed for each rank. Rank 2 comes after buying the Car Wash, its first upgrade and
	-- ~20 washes (~15 minutes of work); rank 3 after about an hour; rank 5 (remote collect) after ~5 hours;
	-- rank 10 after ~30-40 hours of business play (all five businesses, every upgrade, lots of jobs).
	XPFor = { 0, 300, 900, 2000, 3500, 5500, 8000, 11000, 15000, 20000 },
	XP = {
		Buy = 100, -- buying a business
		UpgradePerLevel = 50, -- an upgrade: this x the new level (level 2 = 100 ... level 5 = 250; 700 per business)
		Wash = 5, -- a finished wash (the worker: owner or crewmate)
		Detail = 10, -- a finished detail delivery (the worker)
		Rush = 6, -- every rush-order address delivered to (the worker): ~6-7 a minute of work, like the wash
		Customer = 10, -- the featured owner, for every player customer served
		-- ...but one buyer counts at most this many times an hour per owner (a second account buying shine after
		-- shine can't farm the owner's rank; the money still goes to the owner every time)
		CustomerPerBuyerHour = 2,
		BreakIn = 50, -- the owner, for a break-in stopped (all robbers scared off or knocked down)
		Print = 5, -- a finished press run (the worker): ~2 a minute of printing
		Launder = 15, -- a laundering run delivered (the worker): with its 4 prints, 35 XP a ~3.5-minute loop (~10 a minute, as washing)
		RaidHeld = 75, -- the owner, for a raid held off (the warrant ran out with the door held: PRD "surviving raids")
		Tour = 10, -- a finished boat tour (the worker): one every ~45-90 s, ~10 a minute of work like the other jobs
		Vip = 12, -- a VIP brought to the red carpet (the worker, M5): one every ~80 s, ~9 a minute of work
		BackRoom = 10, -- the owner, for a WASH at the Nightclub's back-room safe (M5)
	},
	RemoteCollect = 5, -- from this rank COLLECT works from the phone (EMPIRE app), anywhere
	Unlocks = {
		[2] = "Coastline Boat Rentals",
		[3] = "Afterglow Nightclub",
		[5] = "Collect your registers from the phone",
		[7] = "Title: Mogul",
		[10] = "Gold business sign · Title: Kingpin of the Coast",
	},
	Titles = { [7] = "Mogul", [10] = "Kingpin of the Coast" }, -- player attribute EmpireTitle (the highest reached)
}

------------------------------------------------------------------ every job: the streak and the shift report

-- THE STREAK (the fun pass): good results in a row raise the TIP of the next ones (Businesses.StreakMult with this
-- rule): the first good result starts it (x1.0), the 2nd pays x1.1, the 3rd x1.2, the 4th and on x1.3; a bad one
-- puts it back to 0. Good = a ★★★ wash, a delivery with no dents, a GOLD rush stop. (The Print Shop's PERFECT
-- streak has its own rule in Businesses.Print.) Part of each job's calibrated average (BALANCE), never on top.
Businesses.Streak = { Step = 0.1, Max = 1.3, From = 1 }
-- THE SHIFT REPORT: any job's end (END JOB, or any other reason) sends BusinessJob "Ended" with the shift's numbers
-- (Report, or the Print Shop's Summary) and its Empire XP; BusinessClient shows the card with CONTINUE / DONE.

------------------------------------------------------------------ the Car Wash's jobs

-- WASH (START JOB > WASH): a customer car (local to the worker's device, so several workers never clash) pulls
-- into a free bay. SPRAY (a timing gauge), SCRUB (tap each dirty spot: its dirt says how many times), RINSE (a
-- timing gauge). The server times every hold and tap, grades the gauges, rolls the customer and pays; see
-- BusinessService. THE FUN PASS (launch/18-BUSINESS-FUN-PASS.md, Nov 4 2026):
--   * SPRAY and RINSE are gauges like the Print Shop's stations (Businesses.GaugeGrade): hold, the gauge fills
--     over Full seconds, let go in the green band (Sweet, widened by Slack each side for lag) for PERFECT, after
--     Min for OK; before Min it didn't count (hold it again); at Full it lets go by itself (OK).
--   * The rating (Businesses.WashStars): a star for each PERFECT hold and one for a quick wash (car ready to the
--     end of the rinse inside StarTime), at least one: ★ / ★★ / ★★★.
--   * The tip (Businesses.WashPay): Tip x (spray + rinse + quick) / 3, a PERFECT 1, an OK OkShare, quick 1.
--     ★★★ washes in a row build the streak (Businesses.Streak: x1.1 from the 2nd, up to x1.3); anything less
--     puts it back to 0. A bad wash still pays Pay: only the tip and the streak are at stake.
--   * Customers: a name, a random model and paint (the worker's device); about one in eight is special
--     (Specials: rolled on the server). Every dirty spot is a Dirt type (also rolled on the server).
-- The pay maths is in BALANCE at the top: ~$1,150 a minute of work at level 1, every bonus inside it.
Businesses.Wash = {
	ArriveTime = 6, -- seconds the car takes to pull in (the first one)
	DepartTime = 4, -- extra seconds for the last car to pull out before the next pulls in
	-- The two gauges: Min = seconds before letting go counts at all, Sweet = the green band { from, to } (PERFECT),
	-- Full = seconds for the gauge to fill (it lets go by itself there). Each band is 0.8 s wide (1.1 s with the
	-- slack): a new player who doesn't know where to let go yet, landing anywhere from Min to Full, hits it ~44%
	-- of the time; aiming at the green, most of the time (the logic tests check both).
	Gauge = {
		spray = { Name = "SPRAY", Min = 3.5, Sweet = { 4.6, 5.4 }, Full = 6 }, -- 77-90% of its gauge
		rinse = { Name = "RINSE", Min = 3, Sweet = { 4.0, 4.8 }, Full = 5.5 }, -- 73-87%: a quicker one (a rhythm to learn)
	},
	Slack = 0.15, -- seconds the server widens each green band by at both ends (a phone's release arrives late)
	OkShare = 0.4, -- an OK hold's share of its third of the tip (a PERFECT gets all of it)
	Spots = { 4, 6 }, -- dirty spots on a normal car (random, both included)
	-- Each dirty spot's dirt: Taps to scrub it off, Odds on a normal car (they add up to 1), Pay = $ more for that
	-- wash at level 1 (x JobMult). ~2.9 taps a spot on average, about what the old 3 taps a spot was.
	Dirt = {
		Mud = { Taps = 3, Odds = 0.5 },
		Bugs = { Taps = 2, Odds = 0.3 },
		Bird = { Taps = 4, Odds = 0.2, Pay = 30 }, -- bird mess: the worst to scrub, worth more
	},
	DirtOrder = { "Mud", "Bugs", "Bird" }, -- (the roll's order)
	ScrubGap = 0.15, -- a tap sooner than this after the last counted one doesn't count (caps auto-clickers at ~6/s)
	-- The ★ for a quick wash: from "car ready" to the end of the rinse in at most Base + PerTap x the car's taps
	-- seconds (4 spots of bugs: ~17 s; 6 of mud: ~23 s; a muddy truck's 7: ~28 s). A typical player makes it ~80%
	-- of the time; only standing about loses it.
	StarTime = { Base = 12, PerTap = 0.6 },
	MinTime = 6.5, -- seconds from "car ready" to the end of the rinse below which that car isn't paid. The gauges'
	-- Min (3.5 + 3 s, less the slack) and the tap gap (the quickest car: 8 taps) already make ~6.8 s the least the
	-- server takes, and a human needs ~9 s+, so no honest wash ever hits it: it only catches a broken clock. The job
	-- goes on: only that car is refused.
	Pay = 430, -- $ a wash at level 1 (x the level's JobMult and RateScale): paid whatever the grades
	Tip = 165, -- $ the whole tip at level 1 (three PERFECT thirds; same multipliers)
	-- SPECIAL CUSTOMERS: about one in SpecialChance is one of these (equal odds, in SpecialOrder). Name = the tag
	-- on the car, Words = what it means (the job strip). PayMult = x the whole wash (pay and tip), Spots / Dirt =
	-- its own spots and dirt odds, TipMult = x the tip, PerfectTip = x the tip but only on a ★★★ wash.
	SpecialChance = 1 / 8,
	Specials = {
		Muddy = { Name = "MUDDY TRUCK", Words = "PAY ×1.5", PayMult = 1.5, Spots = { 6, 7 }, Dirt = { Mud = 0.7, Bugs = 0, Bird = 0.3 } },
		Classic = { Name = "CLASSIC CAR", Words = "★★★ FOR TIP ×3", PerfectTip = 3 }, -- a picky owner: only a perfect wash impresses
		Wedding = { Name = "WEDDING CAR", Words = "TIP ×2", TipMult = 2 }, -- white, with a JUST MARRIED sign
	},
	SpecialOrder = { "Muddy", "Classic", "Wedding" },
	BayRange = 26, -- studs (flat) from the bay centre the worker must be within for a hold or a tap to count
	-- studs from the bay: further than this for LeaveGrace seconds ends the job. (Was 45 / 10: bay 1 is ~46 studs
	-- from the door where START JOB is pressed, so a wash started at the door ended by itself in the Nov 4 Studio
	-- test before the player had found the bay. The client now says WALK TO BAY n while out of BayRange.)
	LeaveRange = 70,
	LeaveGrace = 15,
}

-- DETAIL DELIVERY (START JOB > DELIVER, or DELIVER after a wash): a real customer car (Config.Vehicles, nicer at
-- higher levels) waits on the pick-up box; drive it to the customer's address on a kerb DistMin-DistMax studs
-- away (JobService.RoadsideSpot), stop in the ring. Full pay + a speed tip that dents eat into. Same rules as a
-- taxi fare: the speed check (FastSlack), VehicleGuard, END JOB, and it ends if you're wanted, leave the car
-- for LeaveGrace seconds, change sides or leave the game. The car despawns at the end, whatever happens.
-- THE FUN PASS (Nov 4 2026): about one customer car in five is a sports car (Sports: a bigger tip, dearer dents);
-- the strip counts the dents; at the address the customer walks out to meet you and takes the car (HandOver);
-- the delivery gets a rating (Businesses.DetailStars: on time, no dents = ★★★) and clean deliveries in a row
-- build the streak (Businesses.Streak, x1.1-1.3 on the tip). The shift goes on after a delivery: call your car,
-- drive back and START the next car or wash (within IdleTime), or END JOB for the shift report.
Businesses.Detail = {
	DistMin = 600, -- studs (straight line) from the business to the address...
	DistMax = 1500,
	Base = 500, -- $ a delivery at level 1...
	PerStud = 0.65, -- ...plus this per stud of the road route (GPS length), x JobMult and RateScale
	TipMax = 300, -- $ speed tip at level 1: all of it at or under the estimate...
	TipFade = 0.5, -- ...falling to nothing at estimate x (1 + TipFade)
	EstSpeed = 75, -- the estimate: road length / EstSpeed + EstExtra seconds (a taxi's is /80 + 10)
	EstExtra = 12,
	DentCost = 60, -- $ off the tip for every dent (never below 0)
	-- A dent (the server samples the car's speed 4 times a second; nothing else tracks car damage): the speed
	-- falls faster than DentDecel studs/s^2 (1.5x the hardest brake, Config.Vehicles Brake = 120: a crash, not a
	-- stop) from at least DentMinSpeed, at most one per DentGap seconds. Another car shoving it (ImpactService
	-- stamps the car's BumpedAt) is a dent too.
	DentDecel = 180,
	DentMinSpeed = 25,
	DentGap = 1,
	StopRadius = 32, -- the drop ring (as a taxi's: ActivityClient's ring is 64 across)
	StopSpeed = 6, -- studs/s: stopped
	FastSlack = 1.15, -- as JobService: reached sooner than the straight line at the car's nitro top speed x this = refused
	LeaveGrace = 10, -- seconds out of the car before the job ends
	-- The customer cars, by the business level of the owner the job is for (each level adds to the last).
	-- Never police cars, boats, game-pass or heist-locked cars, or Hidden street cars.
	Cars = {
		{ "Palmetto", "Gatorback", "Mangrove" },
		{ "Sandpiper", "Flamingo" },
		{ "NightHeron", "Voltline" },
		{ "SolanaGT", "SilverEgret" },
		{ "AlbatrossGT" },
	},
	-- A sports car instead, at any level, this often ("Handle with care: Solana GT"): its tip x TipMult and every
	-- dent costs DentCost instead (the same rules for Cars apply).
	Sports = { Chance = 0.2, TipMult = 1.5, DentCost = 100, Cars = { "Voltline", "SolanaGT", "AlbatrossGT" } },
	HandOver = 3, -- seconds the customer car stays at the address after the drop (its owner walks out to it)
	IdleTime = 240, -- seconds after a delivery to start the next car or wash at the business before the shift ends
}

-- DRIVE-THROUGH SHINE (player customers, PRD section 6): drive your own car under the gantry in the shine lane
-- and press "Shine $100": your car sparkles for Seconds (player attribute ShineUntil, server time; every device
-- draws the sparkle on that player's cars near its camera). CustomerShare of the price goes to the featured
-- owner if one is in the server (never to the buyer themselves: an owner shining their own car pays and the
-- game keeps it); the rest is a sink.
Businesses.Shine = {
	Price = 100,
	Seconds = 30 * 60,
	Reach = 18, -- studs from the gantry to the car's driver seat (the prompt reaches 14)
	MaxSpeed = 8, -- studs/s: you have to stop under it
	RebuyLeft = 25 * 60, -- refused while more than this is left on your shine (no double-buying by mistake)
}

------------------------------------------------------------------ Palm Grind Coffee's job and service (M2)

-- RUSH ORDERS (START JOB at Palm Grind): hold GRAB at the RUSH ORDERS shelf (the server times it), get in your
-- own car (CAR calls it) and drive the order to Drops[level] addresses in a row, each on a kerb
-- (JobService.RoadsideSpot); from VIPLevel the last one may be a VIP order at a big home (VIPHomes in
-- Config.Housing: its verge parking spot), paying VIPMult. Every address has its own clock (Businesses.RushTimer,
-- shown on the job strip): stop in its ring and you're paid the base whatever the clock says; the tip is full
-- while at least TipFull of the clock is left, then shrinks to $0 at 0:00 (late pays the base only). After
-- the last address, drive back to the café for the next order. The same rules as a taxi fare: the speed
-- check on every leg (FastSlack, VehicleGuard), END JOB, and the job ends if you're wanted, change sides, die,
-- leave the game, stay out of your car too long (CarGrace after grabbing, LeaveGrace once you've driven
-- off), or don't grab another order within IdleTime. The pay maths is in BALANCE at the top.
-- THE FUN PASS (Nov 4 2026; all decided here on the server, the strip only shows it):
--   * A MEDAL for every address (Businesses.RushMedal): GOLD with TipFull of the clock still left (the full
--     tip), SILVER before 0:00 (the tip fading), BRONZE late (the base only).
--   * GOLDS in a row (across stops and orders) build the streak (Businesses.Streak: x1.1-1.3 on the tip).
--   * A multi-stop order with a GOLD at every stop pays PerfectRun on top (a PERFECT RUN).
--   * RUSH HOUR: about every 10 minutes of the owner's play (RushHour.Gap after the last one ends), the owner's
--     café gets RushHour.Length seconds of +TipBoost on every rush-order tip (theirs and their crew's), announced
--     to the owner (player attribute BizRushHour = the server time it ends).
Businesses.Rush = {
	GrabHold = 2, -- seconds holding GRAB at the shelf
	HoldSlack = 0.4, -- a hold may end this much early (lag) and still count
	GrabRange = 10, -- studs (flat) from the shelf spot (Layout.Orders) a grab counts from (BusinessClient shows HOLD within 7)
	Drops = { 1, 2, 2, 3, 3 }, -- addresses an order has, by the owner's level
	FirstMin = 400, -- studs (straight line) from the café to the first address...
	FirstMax = 1000,
	NextMin = 300, -- ...and from one address to the next
	NextMax = 700,
	VIPLevel = 4, -- from this level an order's last address may be a VIP order...
	VIPChance = { [4] = 0.35, [5] = 0.5 }, -- ...this often (by level)
	VIPMax = 2600, -- studs (straight line) from the stop before: a VIP home further away isn't picked
	VIPMult = 1.5, -- x a VIP drop's pay and tip
	VIPHomes = { "SolanaHeightsPenthouse", "MarinaRowVilla", "FlamingoBeachMansion" }, -- Config.Housing ids: the penthouse, the villa, the mansion
	OrderPay = 320, -- $ an order at level 1 (paid with its first drop: the time at the café; was 330 before the fun pass)
	DropPay = 60, -- $ every address at level 1...
	PerStud = 0.40, -- ...plus this a stud of the road route: every leg, and the way back to the café (with the last drop)
	TipMax = 150, -- $ an address's speed tip at level 1 (was 200 with TipFull 0.35: GOLD is reachable now, so it's smaller)
	TipFull = 0.22, -- the tip is full (a GOLD) while at least this share of the clock is left, then falls to $0 at 0:00
	-- (a typical driver gets ~22% left: a GOLD about half the time; was 0.35 before the medals)
	PerfectRun = 150, -- $ at level 1 (x JobMult) on top of an order of 2+ stops with a GOLD at every one
	RushHour = {
		Gap = { 420, 540 }, -- seconds of the owner's play from one rush hour's end to the next one's start (random)
		Length = 120, -- seconds a rush hour lasts (real seconds: about 2 minutes in every 10 of play)
		TipBoost = 0.25, -- +25% on every rush-order tip at that owner's café while it's on
	},
	EstSpeed = 45, -- the clock: road length / EstSpeed + FirstExtra (the first address: walking out to your car) or NextExtra
	FirstExtra = 18,
	NextExtra = 8,
	StopRadius = 32, -- the drop ring (as a taxi's; BusinessClient's ring is 64 across)
	StopSpeed = 6, -- studs/s: stopped
	FastSlack = 1.15, -- as JobService: a leg done sooner than the straight line at the car's nitro top speed x this = refused
	CarGrace = 45, -- seconds after grabbing an order to get into your own car
	LeaveGrace = 10, -- seconds out of your car once you've driven off with the order
	IdleTime = 300, -- seconds without grabbing an order (at the café, or on the way back) before the job ends
}

-- COLD BREW (player customers at Palm Grind, PRD section 6): walk up to the ORDER HERE spot at the counter and
-- press "Cold brew $60": +Stamina sprint stamina for Seconds (player attribute ColdBrewUntil, server time;
-- LocomotionClient drains the sprint 1 / (1 + Stamina) as fast while it's ahead). Paid exactly like the shine:
-- CustomerShare to the featured owner (never the buyer), the rest a sink, Empire XP capped per buyer per hour.
Businesses.ColdBrew = {
	Seconds = 5 * 60, -- how long it lasts
	Stamina = 0.25, -- +25% sprint stamina (the sprint lasts 1.25x as long)
	Reach = 12, -- studs (flat) from the ORDER HERE spot to the buyer (the prompt reaches 8)
	RebuyLeft = 4 * 60, -- refused while more than this is left on yours (no double-buying by mistake)
}

------------------------------------------------------------------ the Backlot Print Shop's job and raids (M3)

-- PRINT (START JOB > PRINT at the Print Shop; one shift with LAUNDER below: either button starts it, and both
-- work during it). A timing game at three stations, in order (Layout.Stations: the paper, the plate bench, the
-- press). At each one, hold the HOLD button (F / RT / the mouse / a finger): its gauge fills over Full seconds and
-- has a green band (Sweet). Let go IN the band: PERFECT. Anywhere after Min: OK (it still counts). Before Min: it
-- didn't count, hold it again. At Full it lets go by itself (OK). The server times every hold (from its own
-- clock: the device only draws the gauge) and grades it with Businesses.PrintGrade, widening the band by Slack
-- each side for lag. After the third station the press run prints Businesses.PrintBatch of dirty cash into the
-- owner's stock (up to Stock at their level; a crewmate printing fills the OWNER's stock and earns when they
-- launder it):
--   * every PERFECT station in that run prints PerfectBonus more (up to +15%);
--   * THE STREAK: PERFECT stations in a row (across press runs) raise a multiplier StreakStep at a time, up to
--     StreakMax (6 in a row); an OK or a hold that didn't count puts it back to x1.0. Shown on the job strip.
-- So an all-OK press run prints $1,250 at level 1 and a perfect one, deep in a streak, ~$1,870. Calibrated on a
-- typical player who hits about half of the bands: ~x1.13, ~$1,410 a run (BALANCE at the top). The streak is
-- part of that average, not on top of it.
Businesses.Print = {
	-- Each station: Min = seconds before letting go counts at all, Sweet = the green band { from, to } (PERFECT),
	-- Full = seconds for the gauge to fill (it lets go by itself there). The bands sit at different places on
	-- each gauge (a rhythm to learn). Holding to the middle of the bands: ~15.6 s of a ~30 s press run.
	Stations = {
		{ Name = "LOAD PAPER", Where = "PAPER", Min = 2.5, Sweet = { 4.6, 5.4 }, Full = 7 },
		{ Name = "SET THE PLATES", Where = "PLATE BENCH", Min = 2.5, Sweet = { 4.0, 4.8 }, Full = 6.5 },
		{ Name = "RUN THE PRESS", Where = "PRESS", Min = 3, Sweet = { 5.8, 6.6 }, Full = 8 },
	},
	Slack = 0.15, -- seconds the server widens each green band by at both ends (network lag: a phone's release arrives late)
	Range = 8, -- studs (flat) from a station's spot a hold counts from (BusinessClient shows HOLD within 6)
	Batch = 1250, -- $ of dirty cash an all-OK press run prints at level 1 (x the owner's JobMult and RateScale)
	PerfectBonus = 0.05, -- each PERFECT station in a press run prints this much more (3 = +15%)
	StreakStep = 0.05, -- every PERFECT in a row raises the streak multiplier by this...
	StreakMax = 1.3, -- ...up to this (6 PERFECTs in a row); an OK puts it back to x1.0
	Stock = { 14000, 17500, 21000, 26000, 31000 }, -- $ of dirty cash the back room holds, by the owner's level (~2.5-4 loads)
	IdleTime = 300, -- seconds at the shop without a hold that counts (a station or a load) before the shift ends
}

-- LAUNDER (the same shift). With dirty cash in stock: park your own car (not a boat) in the loading bay
-- (Layout.Bay, within BayRange, stopped), walk to the cash cart (Layout.Load) and hold LOAD on foot. Carry(level)
-- of the stock goes into that car (out of the shop's stock: a raid can't seize it any more, but it's gone if the
-- run fails). Drive it to a drop point DistMin-DistMax studs away (JobService.RoadsideSpot: the GPS route and a
-- gold ring) and stop in the ring: the bags turn into clean cash x Rate (EconomyService, reason
-- "bizjob:<id>:launder"), and a CLEAN RUN (you were never wanted on the way) pays CleanBonus more. A crewmate
-- running it for the owner gets the pay and the owner the crew cut, as M1.
-- THE HEAT METER (Businesses.HeatStep, the job strip shows it): while you drive with the bags and aren't wanted,
-- police within HeatRange (a player cop or their car, an AI patrol car, an officer on foot, the police HQ) fill
-- it, faster the closer they are, HeatHidden as fast with a wall between you, and it drains at HeatFall a second
-- with none in range. Full: SPOTTED (PatrolStars with the police within PatrolNear, else Stars) through
-- HeatService. Driving round the police keeps it down. On top of that, every SpotEvery seconds a small chance of
-- a tip-off (SpotChance[level], Stars). Spotted, the run goes on under pressure (being wanted doesn't end a run
-- with bags in the car), but it's no longer clean.
-- THE BAGS ARE LOST (that dirty cash is gone) when you're arrested, die, leave the car for LeaveGrace seconds,
-- the car is gone, the delivery fails the speed check (as a taxi: FastSlack, VehicleGuard), the owner leaves,
-- or you END JOB away from the shop (at the shop, END JOB puts them back in the stock).
-- (Calibrated on ~20% of runs spotted (~14% tip-offs, ~6% the meter), a quarter of those arrested: BALANCE.)
Businesses.Launder = {
	Carry = { 5600, 6100, 6500, 7000, 7400 }, -- $ of dirty cash one run carries, by the owner's level (~4 typical press runs)
	LoadHold = 3, -- seconds holding LOAD at the cash cart
	LoadRange = 9, -- studs (flat) from the cash cart the LOAD hold counts from (BusinessClient shows HOLD within 7)
	BayRange = 14, -- studs (flat) from the bay's middle to your car's chassis: parked in the bay
	BaySpeed = 4, -- studs/s: the car must be standing still in the bay
	DistMin = 800, -- studs (straight line) from the shop to the drop point...
	DistMax = 1600,
	Rate = 1, -- clean $ per dirty $ delivered (the level's job pay was already in the press run)
	CleanBonus = 0.10, -- a run with no stars on the way pays this much more (part of the ~$1,600/min, not on top)
	StopRadius = 32, -- the drop ring (as a taxi's; BusinessClient's ring is 64 across)
	StopSpeed = 6, -- studs/s: stopped
	FastSlack = 1.15, -- as JobService: a run done sooner than the straight line at the car's nitro top speed x this = refused
	LeaveGrace = 20, -- seconds out of the loaded car (getting in after LOAD included) before the bags are lost
	HeatRange = 260, -- studs: police closer than this fill the heat meter (a cop's eyes reach 250: HeatService)
	HeatRise = 0.25, -- meter a second with the police right beside you and a clear line (x how close: 0 at HeatRange; ~6.5 s at 100 studs)
	HeatHidden = 0.4, -- x the rise when a wall is between you and them
	HeatFall = 0.08, -- meter a second it drains with no police in range (full to empty in 12.5 s)
	PatrolNear = 120, -- studs: the police this close when the meter fills = PatrolStars
	SpotEvery = { 10, 15 }, -- seconds between two tip-off rolls while you drive with the bags (random in this range)
	SpotChance = { 0.05, 0.05, 0.04, 0.04, 0.035 }, -- chance a roll is a tip-off, by the owner's level (lower from 3: the hidden back door)
	Stars = 1, -- stars for a tip-off, or a full meter with the police further than PatrolNear...
	PatrolStars = 2, -- ...or with them close by
	MinSpeed = 8, -- studs/s: a car slower than this isn't "on a run" for the tip-off rolls (parked, waiting)
}

-- POLICE RAIDS (PRD section 5, pillar 3; shady businesses only). Per owner, a play clock (BusinessService's,
-- x BusinessTimeScale in Studio). Every Check seconds of play, once the owner has played MinPlay this session
-- and Gap has passed since their last raid, with MinDirty+ of dirty cash in their stock, the owner a living
-- citizen in the server and no raid at that building (and SiteGap since its last one): a roll at
-- Businesses.WarrantChance. A hit issues a RAID WARRANT for Warrant seconds:
--   * PLAYER COPS on duty (Side "Cop", really patrolling, not the owner's crewmates) get the dispatch: a toast,
--     the GPS, the map flashing. They hold BREACH at the door (BreachHold; ArmoredHold from ArmoredLevel: the
--     armored door), then SEARCH at the presses (SearchHold) to SEIZE all the dirty cash in that owner's stock.
--     Every cop at the shop then gets RewardBase + an even split of SeizeShare of it (at most RewardMax in all),
--     clean money. After a breach the warrant has at least SearchMin seconds left.
--   * NO PLAYER COP on duty (or none left before the breach): the AI raid. A police car pulls up AIArrive seconds
--     in, two officers walk to the door and breach in AIBreach seconds, then search for AISearch seconds and take
--     AISeize of the stock. Slower and weaker: their clocks only run while nobody holds the door.
--   * THE OWNER AND THEIR CREW get the warning (a toast, the GPS, the map flashing red, the strip's clock). They
--     can launder stock out first, fight the cops (the game's normal combat rules), or HOLD THE DOOR: stay inside
--     (Layout.Inside). An AI raid can't breach while they're in there. When the warrant runs out with no breach
--     and they were inside for HeldMin seconds of it, the raid is held off (a RAID FAILED stamp): the owner gets
--     HeldBonus (clean) and Empire XP RaidHeld, and every crewmate who was inside HeldMin seconds too CrewHeldBonus
--     and the same XP. A warrant that runs out with nobody inside is just over: the stock is safe, no bonus.
--   * The cops' SEIZED $X stamp, the siren at the shop, the countdown banner and the red map icon: BusinessClient.
-- Only the dirty cash is ever taken: never clean money, the register or upgrades. Everything here is decided by
-- the server (BusinessJobs.PrintShop); the clients only see it (ReplicatedStorage attribute BizRaids) and hold
-- the two prompts, which the server times again.
Businesses.Raid = {
	MinPlay = 600, -- seconds of the owner's play this session before the first warrant (PRD: never in the first 10 minutes)
	Check = 60, -- seconds of play between two warrant rolls per owner
	Gap = 900, -- seconds of play after a raid (whatever the outcome) before that owner can get another warrant
	SiteGap = 300, -- seconds after a raid at a building before another warrant there (any owner)
	MinDirty = 5500, -- $ of dirty cash in the owner's stock before a warrant can be issued (about one launder load)
	Chance = { 0.10, 0.40 }, -- chance per roll: at MinDirty ... at a full stock (a straight line between)
	Warrant = 180, -- seconds a warrant runs (PRD: 3 minutes)
	BreachHold = 6, -- seconds a cop holds BREACH at the door...
	ArmoredHold = 9, -- ...from ArmoredLevel (the armored door, level 4)
	ArmoredLevel = 4,
	SearchHold = 8, -- seconds a cop holds SEARCH at the presses
	SearchMin = 60, -- after a breach the warrant is stretched to at least this many seconds from then
	HoldSlack = 0.4, -- a prompt hold may end this much early (lag) and still count
	CopRange = 14, -- studs a cop may be from the door / the presses when the hold ends (the prompts reach 10)
	SeizeShare = 0.25, -- the cops' share of the dirty cash seized, as clean money (x RateScale)...
	RewardMax = 6000, -- ...at most this much in all...
	RewardBase = 300, -- ...plus this to every cop at the shop for serving the warrant (even if the stock was moved out)
	HeldMin = 60, -- seconds the owner or a crewmate must spend inside during the warrant to have held the door
	HeldBonus = 1000, -- $ (clean) to the owner for a raid held off (x RateScale)
	CrewHeldBonus = 500, -- $ (clean) to each crewmate who held the door with them for HeldMin seconds (x RateScale)
	AIArrive = 30, -- seconds after the warrant the AI police car pulls up
	AIBreach = 40, -- seconds of nobody holding the door the AI officers need to breach...
	AISearch = 15, -- ...and to search the presses once inside
	AISeize = 0.5, -- share of the stock an AI raid takes
	AIOfficers = 2, -- officers in the AI raid
}

------------------------------------------------------------------ Coastline Boat Rentals' job and service (M4)

-- BOAT TOURS (START JOB > BOAT TOURS at Coastline Boat Rentals; JobKind "BizTour"). The business's own boat
-- (Boats[level], a Config.Vehicles boat with the business's fit-out: nobody owns it, it can't be kept, sold, raced
-- or used for a taxi fare, and it goes when the shift ends) appears in its berth with you at the helm. Tourists
-- (the pedestrians' looks: Tourists[level] of them) hop aboard from the pier, then you drive a sightseeing ROUTE
-- (Routes: picked at random, longer ones from higher levels) of floating buoy rings past the coast's landmarks
-- and back to the dock ring. Everything below is decided on the server (BusinessJobs.BoatRentals):
--   * PASS rings: drive through them in order (Radius, tested along the whole stretch driven since the last check
--     so a fast boat can't skip one: Businesses.TourReached). The tour guide's line for that landmark pops up.
--   * PHOTO STOPS (Kind "Photo"): inside the ring, slow down under Photo.Speed and stay under it for Photo.Hold
--     seconds: the tourists take their photos (the camera flashes). PERFECT when Photo.PerfectHold of those
--     seconds were under Photo.Perfect (gliding nearly still), else OK; leave the ring before it's done: MISSED
--     (Businesses.PhotoStep). Going over Photo.Speed inside starts the hold again.
--   * THE TOURISTS' MOOD (a 0-100% meter: Businesses.TourMood): hard turns at speed (lateral acceleration over
--     Mood.TurnLimit), ramming something (the speed more than halved at Mood.RamDecel+) and running aground (the
--     water no longer under the hull) lower it; calm driving slowly lifts it back.
--   * THE RATING (Businesses.TourStars): ★ back inside par (Businesses.TourPar), ★ every photo stop PERFECT,
--     ★ the tourists at least Mood.StarAt happy; never less than ★. The pay (Businesses.TourPay): see BALANCE.
--   * SPECIAL TOURS (about one in SpecialChance, rolled on the server; equal odds among those allowed now).
--   * The speed check on every leg (as a taxi fare: FastSlack x the boat's nitro top speed, VehicleGuard).
--   * It ends on END JOB, wanted, a change of side (arrested), death, out of the boat for LeaveGrace seconds,
--     the boat gone, or IdleTime at the dock without a NEXT TOUR. The boat and the tourists go with it.
-- Every number here is at level 1 (x the owner's JobMult and RateScale where it's money).
local function stop(name, x, z, line)
	return { Name = name, Pos = Vector3.new(x, 0, z), Line = line }
end
Businesses.Tour = {
	-- The boat by the owner's level (Config.Vehicles ids: the 8 x 20 Marlin speedboat, the 10 x 26 Moonstone yacht
	-- hull) and its fit-out (BoatRentals' looks on it: "Plain", "Canopy" a striped sun canopy, "Luxury" gold trim).
	Boats = { "Marlin", "Marlin", "Marlin", "Moonstone", "Moonstone" },
	Fitout = { "Plain", "Plain", "Canopy", "Canopy", "Luxury" },
	Tourists = { 2, 3, 4, 5, 6 }, -- tourists aboard, by the owner's level
	-- Where the tourists sit on each boat: { x, z } studs from its DriverSeat (x right, z toward the stern), at
	-- the seat's height. (Estimated from the hulls' sizes: check them in Studio.)
	Seats = {
		Marlin = { { -1.7, 2.4 }, { 1.7, 2.4 }, { -1.7, 4.8 }, { 1.7, 4.8 }, { -1.7, 7.2 }, { 1.7, 7.2 } },
		Moonstone = { { -2.2, -3 }, { 2.2, -3 }, { -2.2, -6 }, { 2.2, -6 }, { -2.2, -9 }, { 2.2, -9 } },
	},
	BoardEach = 0.45, -- seconds between two tourists hopping aboard...
	BoardExtra = 1.2, -- ...and after the last one, before "all aboard" (the tour's clock starts then)
	BoardGrace = 40, -- seconds after START JOB to get to the helm (the server seats you; else walk to the boat)
	Radius = 32, -- studs: a ring's radius (as a race checkpoint's: ActivityClient's ring is 64 across)
	MaxStep = 120, -- studs: a jump longer than this between two checks (a quarter second) isn't driving: it passes nothing
	DockRadius = 22, -- studs: the dock ring at the end (Layout.Dock)...
	DockSpeed = 10, -- ...stop in it under this (studs/s) and the boat glides into its berth
	GlideTime = 1.2, -- seconds the boat takes to glide into the berth
	UnboardTime = 2.5, -- seconds the tourists take to step off and cheer (the pay comes at once)
	FastSlack = 1.15, -- as JobService: a leg done sooner than the straight line at the boat's nitro top speed x this = refused
	LeaveGrace = 15, -- seconds out of the boat during a tour before the shift ends
	LeaveRange = 150, -- studs from the boat you may wander at the dock between tours (further for LeaveGrace: it ends)
	IdleTime = 180, -- seconds at the dock without starting the next tour before the shift ends
	-- PHOTO STOPS (Businesses.PhotoStep). Speed / Perfect in studs/s, Hold / PerfectHold in seconds, Slack = studs
	-- past the ring's edge before you've "left" it. A new player who slows to anywhere between 2 and 15 studs/s,
	-- wobbling a little, lands a PERFECT ~45% of the time, about as often as on the wash's gauges (the logic tests);
	-- one who knows to glide nearly still, most of the time.
	Photo = { Speed = 16, Hold = 2.5, Perfect = 8, PerfectHold = 1.5, Slack = 6 },
	-- FISHING STOPS (the Fishing Party's): longer and stiller.
	Fish = { Speed = 10, Hold = 4.5, Perfect = 5, PerfectHold = 3, Slack = 6 },
	-- THE TOURISTS' MOOD (Businesses.TourMood; 0-1, starts at 1): lateral acceleration = speed x turn rate
	-- (studs/s^2; a Marlin flat out on full lock pulls ~130, a gentle curve ~30).
	Mood = {
		TurnLimit = 60, -- studs/s^2 of turn the tourists don't mind
		TurnDrain = 0.05, -- mood lost a second for every TurnLimit over it...
		TurnCap = 2, -- ...counting at most this many (0.1 a second at worst)
		RamDecel = 150, -- studs/s^2: the speed falling this fast (and more than halving) from RamMinSpeed is a ram...
		RamMinSpeed = 25,
		RamHit = 0.15, -- ...which costs this much mood...
		RamGap = 1, -- ...at most once a second (another car or boat shoving yours counts too: ImpactService's BumpedAt)
		BeachHit = 0.2, -- running aground (the hull's not over water): this at once...
		BeachDrain = 0.05, -- ...and this a second while aground
		Recover = 0.005, -- a second, while nothing above happens (+30% a minute of calm driving)
		StarAt = 0.8, -- the ★ for a smooth ride: at least this happy at the dock
		Zero = 0.2, -- the mood's share of the tip: 0 at this mood, all of it at 100%
		Say = 0.04, -- a drop this big in one check (or a ram, or running aground) makes a tourist shout
	},
	-- THE PAY (Businesses.TourPay; BALANCE at the top): Base + PerStud x the route's length + StopPay x its photo
	-- (or fishing) stops, paid whatever happens; the tip is up to TipRate of that, from the three shares.
	Base = 240, -- $ a tour at level 1 (the boarding, docking, cheering and NEXT TOUR: ~13 s of the cycle)
	PerStud = 0.185, -- $ a stud of the route (straight legs, berth to dock: ~90 studs/s for a typical driver)
	StopPay = 95, -- $ a photo or fishing stop (~5.5 s of slowing, holding and speeding up again)
	TipRate = 0.4, -- the whole tip, as a share of the tour's pay
	OkShare = 0.4, -- an OK photo's share of its part of the tip (PERFECT 1, MISSED 0)
	TimeFade = 0.5, -- the time share: all of it inside par, down to 0 at par x (1 + TimeFade)
	ParSpeed = 85, -- par: the route / ParSpeed + ParStop a stop + ParExtra (a typical driver's ~90 makes it)
	ParStop = 7,
	ParExtra = 4,
	-- SPECIAL TOURS: about one in SpecialChance is one of these (equal odds among the ones allowed right now, in
	-- SpecialOrder). Name = the strip's words, Words = what it means. PerfectTip = x the tip, only on a ★★★ tour;
	-- Route = its own route; Bonus = $ on top (x JobMult); ParMult = x par; PayMult = x the whole tour (pay and
	-- tip); Night = only at dusk and at night (Businesses.SunsetTime).
	SpecialChance = 1 / 8,
	Specials = {
		Celebrity = { Name = "CELEBRITY TOUR", Words = "★★★ FOR TIP ×3", PerfectTip = 3 }, -- a star aboard: only a perfect tour impresses
		Fishing = { Name = "FISHING PARTY", Words = "TAKE IT SLOW · BONUS", Route = "Fishing", Bonus = 250, ParMult = 1.5 },
		Sunset = { Name = "SUNSET TOUR", Words = "PAY ×1.3", PayMult = 1.3, Night = true },
	},
	SpecialOrder = { "Celebrity", "Fishing", "Sunset" },
	-- Dusk: Lighting.ClockTime from SunsetFrom through midnight to SunsetTo (WorldService's golden hour on), or
	-- Workspace attribute IsNight.
	SunsetFrom = 17.2,
	SunsetTo = 5.5,
	-- THE LANDMARKS (world positions on the water; Line = the tour guide's line as you pass, short and silly).
	Stops = {
		Marina = stop("MARINA ROW SLIPS", 1800, 1215, "Those yachts? Mortgaged. Every one."),
		SeaDream = stop("THE SEA DREAM", 1810, 1352, "The Sea Dream! Smile, it's insured."),
		Cranes = stop("THE CARGO CRANES", 1730, 1790, "Cranes: giraffes, but for boxes."),
		Dolphins = stop("DOLPHIN WATCH", 1900, 1500, "A dolphin! ...no, a pool float."),
		MarinaRow = stop("MARINA ROW", 1800, 900, "Marina Row: boats, shrimp, sunsets."),
		Beach = stop("THE BEACH", 1660, 420, "Sunscreen check! Too late, Gary."),
		Lifeguards = stop("LIFEGUARD TOWERS", 1650, -20, "Wave at the lifeguards! Not too much."),
		OpenSouth = stop("OPEN WATER", 1850, 600, "Hold on to your hats! Really."),
		Ferris = stop("THE FERRIS WHEEL", 1720, -260, "The Ferris wheel: 113 studs of fun."),
		PierEnd = stop("THE PIER END", 1880, -330, "Wave at the fishermen. Gently."),
		BackNorth = stop("SURF WATERS", 1950, 300, "Surf Sprint waters. No racing, Kevin."),
		Flamingo = stop("FLAMINGO BEACH", 1680, -880, "A 66-stud flamingo. As one does."),
		Surf = stop("SURF WATERS", 2000, -200, "Surf Sprint waters. No racing, Kevin."),
		OpenEast = stop("OPEN WATER", 1950, 600, "Feel that breeze? That's freedom."),
		Lighthouse = stop("LIGHTHOUSE KEY", 2250, -1060, "Lighthouse Key: lights on, nobody home."),
		FarSea = stop("THE OPEN SEA", 2250, -150, "Next stop: nowhere. Turning back!"),
		Fish1 = stop("FISHING SPOT", 1900, 1250, "Lines in! Shh, the fish are listening."),
		Fish2 = stop("THE DEEP SPOT", 2000, 1000, "Big ones down here. Allegedly."),
	},
	-- THE ROUTES: Id, Name (the strip and the toasts), MinLevel (the owner's level it's offered from; 99 = only
	-- as a special), Stops = { { landmark id, Kind = "Pass" | "Photo" | "Fish" } } in order (the berth before the
	-- first, the dock ring after the last). Every leg checked clear of the place (see PLACES at the top).
	Routes = {
		{ Id = "Marina", Name = "MARINA & SEA DREAM", MinLevel = 1, -- ~1,490 studs
			Stops = { { "Marina", "Pass" }, { "SeaDream", "Photo" }, { "Cranes", "Pass" }, { "Dolphins", "Pass" } } },
		{ Id = "Boardwalk", Name = "BOARDWALK BEACH", MinLevel = 1, -- ~2,290 studs
			Stops = { { "MarinaRow", "Pass" }, { "Beach", "Photo" }, { "Lifeguards", "Pass" }, { "OpenSouth", "Pass" } } },
		{ Id = "Ferris", Name = "FERRIS WHEEL RUN", MinLevel = 2, -- ~2,980 studs
			Stops = { { "Beach", "Photo" }, { "Lifeguards", "Pass" }, { "Ferris", "Photo" }, { "PierEnd", "Pass" }, { "BackNorth", "Pass" } } },
		{ Id = "Flamingo", Name = "FLAMINGO COAST", MinLevel = 3, -- ~4,720 studs
			Stops = { { "SeaDream", "Photo" }, { "Beach", "Pass" }, { "Ferris", "Photo" }, { "PierEnd", "Pass" }, { "Flamingo", "Photo" },
				{ "Surf", "Pass" } } },
		{ Id = "Lighthouse", Name = "LIGHTHOUSE KEY", MinLevel = 4, -- ~4,890 studs
			Stops = { { "OpenEast", "Pass" }, { "PierEnd", "Photo" }, { "Flamingo", "Pass" }, { "Lighthouse", "Photo" }, { "FarSea", "Pass" } } },
		{ Id = "Grand", Name = "THE GRAND TOUR", MinLevel = 5, -- ~5,500 studs
			Stops = { { "SeaDream", "Photo" }, { "Beach", "Pass" }, { "Ferris", "Photo" }, { "PierEnd", "Pass" }, { "Flamingo", "Photo" },
				{ "Lighthouse", "Photo" }, { "FarSea", "Pass" } } },
		{ Id = "Fishing", Name = "FISHING PARTY", MinLevel = 99, -- ~750 studs: the Fishing Party's own
			Stops = { { "Fish1", "Fish" }, { "Fish2", "Fish" } } },
	},
	OwnShare = 0.5, -- a new tour is one of the newest routes the owner's level offers this often, else any it offers
}

-- JET SKI RENTAL (player customers at Coastline Boat Rentals, PRD section 6): walk up to the JET SKI RENTALS stand
-- (Layout.Service) and press "Jet ski rental $150": a jet ski (Vehicle: Config.Vehicles' Splash Jet Ski, the
-- smallest and quickest-turning boat in the game) appears in a free rental slot (Layout.Rentals) with you aboard,
-- yours to ride for Seconds. Nobody owns it (no OwnerUserId: no garage, no selling, no races, no taxi fares, no
-- passengers; only you can sit on it, as M1's customer cars). A warning Warn seconds before the end; then you're
-- put off and it goes. It also goes if you leave it for LeaveGrace seconds, leave the game or are arrested.
-- Paid exactly like the shine and the cold brew: CustomerShare to the featured owner (never the buyer), the rest a
-- sink, Empire XP capped per buyer per hour. Citizens only, not while wanted, one at a time.
Businesses.Rental = {
	Vehicle = "Splash", -- Config.Vehicles id (the label on the stand and the toasts says what it is: Label)
	Label = "Jet ski",
	Seconds = 10 * 60, -- how long a rental lasts (real time; x BusinessTimeScale in Studio)
	Warn = 60, -- seconds left when the "1 minute left" warning comes
	LeaveGrace = 60, -- seconds off the jet ski before it's taken back early
	Reach = 12, -- studs (flat) from the stand's spot to the buyer (the prompt reaches 8)
}

------------------------------------------------------------------ the Afterglow Nightclub's job, club and back room (M5)

-- NIGHT. The game's day is 14 minutes (WorldService's ACTS: 6:00-9:30 in 110 s, 9:30-14:00 in 70 s, 14:00-16:00 in
-- 120 s, 16:00-18:48 in 200 s, 18:48-6:00 in 340 s; 840 s in all). Workspace IsNight is on while its "nightness" is
-- over a half: from 18:24 (28.6 s before the end of the 16:00 act) to 5:36 (327.9 s into the last), so 356.4 s of every
-- 840 s: 42.4% of the time. The logic tests work this share out again from WorldService's own ACTS and nightness lines.
-- At night the Nightclub's register fills NightMult times as fast (its entry), and VIP pickups pay Vip.NightMult.
-- Studio: Workspace attribute BizTestNight (true / false) overrides IsNight for the businesses (Debug "night").
Businesses.NightShare = 0.4243

-- VIP PICKUPS (START JOB > VIP PICKUPS at the Afterglow Nightclub; JobKind "BizVip"). The club's own LIMO (Limo, a
-- Config.Vehicles car in the club's paint and fit-out by the owner's level: nobody owns it, it can't be kept, sold,
-- raced or used for a taxi fare, and it goes when the shift ends) waits in its bay with you at the wheel. Every VIP:
--   1. THE PICKUP: a celebrity waits at a mansion, a villa, a penthouse, a hotel tower or a hotel's kerb DistMin-
--      DistMax studs from the club (Homes from Config.Housing, the apartment towers, or a kerb spot from
--      JobService.RoadsideSpot). Drive there and stop in the gold ring (PickupRadius, under StopSpeed): the VIP walks
--      to the limo and gets in (the passenger seat, for everyone to see).
--   2. THE RIDE BACK: the VIP's COMFORT meter (Businesses.VipComfort, 0-100%): hard turns at speed, crashes, jumps and
--      paparazzi flashing at the window lower it; calm driving lifts it back. The clock: par (Businesses.VipPar).
--   3. PAPARAZZI: about one ride in Pap.Chance (a Tabloid Star: always), Pap.Cars[level] paparazzi cars (NPC drivers:
--      RaceAIService) come after you a few seconds after the VIP gets in. Get Pap.LoseDist away from all of them for
--      Pap.LoseHold seconds: LOST THEM! and Pap.Bonus at the red carpet. Still on your tail at the club: no bonus
--      (never a penalty). Close by they flash their cameras (the VIP hates that: FlashDrain).
--   4. THE RED CARPET: stop in the red-carpet ring (CarpetRadius) at the club, under StopSpeed. How close the limo
--      stops to the VIP mark grades the arrival (Businesses.VipStop): PERFECT within Stop.Perfect, GOOD within
--      Stop.Good, else OK. The VIP steps out and walks the carpet through the camera flashes; the pay counts up.
--   * THE RATING (Businesses.VipStars): ★ back inside par, ★ the VIP at least Comfort.StarAt comfortable, ★ a PERFECT
--     stop. The tip (Businesses.VipPay) is up to TipRate of the pay from three equal shares (time, comfort, the stop);
--     ★★★ in a row raise it (Businesses.Streak). Special VIPs about one in SpecialChance.
--   * NIGHT: VIP pickups pay NightMult (pay and tip) at night.
--   * The speed check on both legs (as a taxi fare: FastSlack x the limo's nitro top speed, VehicleGuard).
--   * It ends on END JOB, wanted, a change of side, death, out of the limo for LeaveGrace seconds on a pickup or a
--     ride (or LeaveRange away from it at the club), the limo gone, or IdleTime at the club without a NEXT VIP.
-- THE PAY MATHS (BALANCE at the top): ~$1,500 a minute of work at level 1, every bonus inside (night included).
Businesses.Vip = {
	Limo = "SilverEgret", -- Config.Vehicles id: the long luxury saloon, in the club's paint
	-- Its paint and the club's looks on it by the owner's level: "Plain" (black), "Neon" (pink underglow and an
	-- AFTERGLOW roof light), "Gold" (gold trim on a pearl-white paint).
	Paint = { Color3.fromRGB(18, 18, 22), Color3.fromRGB(18, 18, 22), Color3.fromRGB(26, 20, 34), Color3.fromRGB(26, 20, 34),
		Color3.fromRGB(236, 232, 226) },
	Fitout = { "Plain", "Plain", "Neon", "Neon", "Gold" },
	DistMin = 600, -- studs (straight line) from the club to a pickup...
	DistMax = 1700,
	HotelMin = 700, -- ...and for a hotel kerb (JobService.RoadsideSpot)
	HotelMax = 1500,
	NamedShare = 0.55, -- a pickup is at a named home or tower this often when one is in range (else a hotel kerb)
	-- The homes VIPs live in (Config.Housing ids; the VIP waits by their verge parking spot) and their word on the strip.
	Homes = { { Id = "FlamingoBeachMansion", Kind = "MANSION" }, { Id = "MarinaRowVilla", Kind = "VILLA" },
		{ Id = "SolanaHeightsPenthouse", Kind = "PENTHOUSE" } },
	TowerReach = 60, -- studs: an apartment tower's door this close to a road is a pickup (at its kerb)
	Hotels = { "Ocean Grand Hotel", "Coral Palms Hotel", "Hotel Valencia", "The Solana Royale", "Seabreeze Suites", "The Neon Palms",
		"Hotel Flamingo", "The Palmetto Inn" },
	Names = { "Stella Starr", "DJ Marlo", "Rico Diamante", "Lexi Lux", "Captain Neon", "Kai Sterling", "Bianca Bling", "Jaxon Jett",
		"Coco Velvet", "Valentina Vibe", "Tony Topaz", "Sasha Sparkle", "Duchess Delray", "Miami Mike" },
	PickupRadius = 24, -- studs: the pickup ring
	StopSpeed = 6, -- studs/s: stopped
	BoardTime = 2.2, -- seconds the VIP takes to walk to the limo and get in
	CarpetRadius = 16, -- studs from the VIP mark: the red-carpet ring
	Stop = { Perfect = 3, Good = 7 }, -- studs from the VIP mark (the limo's middle): PERFECT, GOOD, else OK
	StopShare = { Perfect = 1, Good = 0.6, Ok = 0.25 }, -- the stop's share of its third of the tip
	CarpetTime = 3.5, -- seconds the VIP takes up the carpet (the pay comes at once)
	FastSlack = 1.15, -- as JobService: a leg done sooner than the straight line at the limo's nitro top speed x this = refused
	SeatGrace = 40, -- seconds after START JOB to get into the limo
	LeaveGrace = 15, -- seconds out of the limo on a pickup or a ride before the shift ends
	LeaveRange = 120, -- studs you may wander from the limo at the club between VIPs
	IdleTime = 180, -- seconds at the club without a NEXT VIP before the shift ends
	-- THE VIP'S COMFORT (Businesses.VipComfort; 0-1, starts at 1). lat = the limo's lateral acceleration (speed x turn
	-- rate, studs/s^2; a street corner at 40 studs/s pulls ~50, flat out round a long bend ~110).
	Comfort = {
		TurnLimit = 70, -- studs/s^2 of turn the VIP doesn't mind
		TurnDrain = 0.05, -- comfort lost a second for every TurnLimit over it...
		TurnCap = 2, -- ...counting at most this many (0.1 a second at worst)
		RamDecel = 150, -- studs/s^2: the speed falling this fast (and more than halving) from RamMinSpeed is a crash...
		RamMinSpeed = 25,
		RamHit = 0.15, -- ...which costs this much...
		RamGap = 1, -- ...at most once a second (another car shoving the limo counts too: ImpactService's BumpedAt)
		AirSpeed = 28, -- studs/s up or down: the limo is off the ground (a jump, a kerb taken far too fast)...
		AirHit = 0.12, -- ...which costs this...
		AirGap = 1.5, -- ...at most this often
		FlashDrain = 0.02, -- a second, while a paparazzi car is within Pap.FlashRange flashing its cameras
		Recover = 0.005, -- a second, while nothing above happens (+30% a minute of calm driving)
		StarAt = 0.8, -- the ★ for a smooth ride
		Zero = 0.2, -- the comfort's share of the tip: 0 at this, all of it at 100%
		Say = 0.04, -- a drop this big lately (or a crash, a jump) makes the VIP complain
	},
	-- THE PAY (Businesses.VipPay; BALANCE at the top): Base + PerStud x the road both ways (out to the pickup and back),
	-- paid whatever happens; the tip is up to TipRate of that from the three shares.
	Base = 345, -- $ a VIP at level 1 (the boarding, the carpet, NEXT VIP and the two stops: ~14 s of the cycle)
	PerStud = 0.385, -- $ a stud of road, both legs (~45 studs/s for a typical driver)
	TipRate = 0.3, -- the whole tip, as a share of the pay
	TimeFade = 0.5, -- the time share: all of it inside par, down to 0 at par x (1 + TimeFade)
	ParSpeed = 42, -- par for the ride back: the road / ParSpeed + ParExtra (a typical driver's ~45 makes it)
	ParExtra = 6,
	NightMult = 1.25, -- x a VIP's pay and tip at night (PRD: "at night VIP pickups pay more")
	-- PAPARAZZI (BusinessJobs.Nightclub, with RaceAIService's NPC drivers).
	Pap = {
		Chance = 0.3, -- a ride with paparazzi on it (a Tabloid Star: always)
		Cars = { 1, 1, 2, 2, 2 }, -- paparazzi cars by the owner's level
		Delay = 3, -- seconds after the VIP gets in before they appear
		SpawnMin = 70, -- studs from the limo they appear (a road point, behind it when there is one)...
		SpawnMax = 220,
		Top = 115, -- studs/s: their top speed (the limo's is 185: a driver who goes for it loses them)
		Near = 40, -- studs: closer than this they ease off (no ramming)
		FlashRange = 60, -- studs: closer than this their cameras flash (the VIP's comfort drains)
		LoseDist = 230, -- studs from every one of them...
		LoseHold = 3, -- ...for this long: LOST THEM!
		Replan = 1.5, -- seconds between two new routes to the limo
		Bonus = 250, -- $ at level 1 (x JobMult) for losing them, paid at the red carpet
		Car = "Mangrove", -- Config.Vehicles id (a dark SUV), when RaceAIService can take a model
		Paint = Color3.fromRGB(44, 46, 52),
	},
	-- SPECIAL VIPs: about one in SpecialChance (equal odds, in SpecialOrder). Name = the strip's words, Words = what it
	-- means. PerfectTip = x the tip on a ★★★ arrival; Paparazzi = they always come (PapMult x the bonus); ParMult = x
	-- par; TipMult = x the tip; PayMult = x the whole pay.
	SpecialChance = 1 / 8,
	Specials = {
		Superstar = { Name = "SUPERSTAR", Words = "★★★ FOR TIP ×3", PerfectTip = 3 },
		Tabloid = { Name = "TABLOID STAR", Words = "PAPARAZZI · LOSE THEM ×2", Paparazzi = true, PapMult = 2 },
		Late = { Name = "LATE FOR THE SHOW", Words = "BEAT THE CLOCK · TIP ×2", ParMult = 0.8, TipMult = 2 },
	},
	SpecialOrder = { "Superstar", "Tabloid", "Late" },
}

-- THE CLUB (player customers, PRD section 6). The club's inside is built far off the map (Origin: further from the city
-- and from the homes' insides than any streaming radius, so it never loads for anyone outside), once, when the first
-- guest walks in, and taken down EmptyFor seconds after the last one leaves (HousingService's per-visit idea).
--   * COVER CHARGE ($50, the Nightclub's Service, at the velvet rope by the door): any citizen on foot, not wanted,
--     pays and walks in (a fade, then the club's entrance). The pass lets them back in free for CoverValid seconds.
--     Owners of the club and their crewmates walk in free. Inside: the dance floor, the bar, the DJ, the music, the
--     lights (a social hangout; a safe zone: no fights). Leaving (the EXIT door, or LEAVE on the screen) puts them
--     back outside the door. Wanted inside: the bouncers put them out.
--   * VIP BOOTH ($250, Booth on the Nightclub's entry, at the booth's rope inside): a private booth for you and your
--     crew for BoothSeconds. Anyone else who walks in is shown out to the dance floor. Owners of the club book free.
-- Positions here are the club's own space: Origin + (x, y, z), the entrance to the south (+Z), the DJ to the north.
Businesses.Club = {
	Origin = Vector3.new(-12000, 120, -12000), -- the middle of the club's floor (off the map: x < -2000, far from the homes' insides)
	Arrive = Vector3.new(0, 0, 20), -- where a guest appears (facing north, the dance floor ahead)
	Exit = Vector3.new(0, 0, 26.5), -- the EXIT door's prompt
	Booth = { X0 = -35, X1 = -22, Z0 = -14, Z1 = 6 }, -- the VIP booth's floor
	BoothRope = Vector3.new(-21, 0, -4), -- its BOOK prompt, at the rope's gap
	BoothOut = Vector3.new(-16, 0, -4), -- where someone without the booth is shown out to
	KeepIn = 150, -- studs from Origin: further away, a guest has left by some other way
	CoverValid = 30 * 60, -- seconds a paid cover lets you back in free
	Reach = 12, -- studs from the rope (or the booth's rope) the prompts count from
	FadeTime = 0.35, -- seconds of black screen before the move (HouseClient's HouseFade)
	EmptyFor = 60, -- seconds after the last guest leaves before the club's inside is taken down
	BoothSeconds = 15 * 60, -- a VIP booth booking
	BoothWarn = 60, -- seconds left when its "1 minute left" toast comes
	Dancers = { 2, 3, 4, 5, 6 }, -- dancing NPCs on the floor, by the featured owner's level
	MusicVolume = 0.4,
}

-- THE BACK ROOM (the Nightclub's shady side; PRD: "Legit, with a shady back room"). After dark a card game runs in the
-- back room and the house's cut piles up in its safe as DIRTY cash (saved per owner as data.businesses.Nightclub.dirty):
-- Rate[level] a minute at night while the owner is online, up to Stock[level]. It isn't money yet: hold WASH at the
-- safe (WashHold seconds; the owner only) and up to Wash[level] of it goes through the club's tills into your pocket,
-- clean, once every WashGap seconds. While it holds MinDirty or more, POLICE RAIDS can come for it (Config.Raid's
-- rules, the Print Shop's raid code: BusinessJobs.Raids): the cops breach the back-room door and search the safe; hold
-- the door from inside the club building, or wash it out first. A raid only ever takes the back-room stock: never the
-- register, clean money or upgrades. NPC break-ins still come for the club's legit register.
Businesses.BackRoom = {
	Rate = { 80, 95, 110, 125, 140 }, -- $ of dirty cash a minute at night (x RateScale), by the owner's level
	Stock = { 8000, 9500, 11000, 12500, 14000 }, -- $ the safe holds, by the owner's level
	Wash = { 2500, 2800, 3100, 3400, 3700 }, -- $ one WASH moves through the tills, by the owner's level
	WashHold = 4, -- seconds holding WASH at the safe
	WashGap = 300, -- seconds between two washes ("the tills can only hide so much at once")
	Reach = 9, -- studs (flat) from the safe the WASH counts from
	MinDirty = 4000, -- $ in the safe before a raid warrant can come
}

-- NPC BREAK-INS (PvE, legit businesses; PRD section 5, pillar 3). Only while the owner is in the server, on
-- the Civilian side, has played MinPlay seconds this session, and one of their registers holds MinRegister+.
-- At most one every Gap seconds of play, at a random moment inside the Window after that. 1-2 robbers appear
-- at that business's register; the owner and their crewmates in the server get the alert (toast, a GPS route,
-- a flashing red icon on both maps) and Time seconds. Scare them off by pointing a gun at them, or knock them
-- down (punch or shoot): Reward per robber to whoever stopped it, and the owner gets Empire XP when all are
-- stopped. Time runs out: they take Loss of that owner's register and leave. Anyone can SEE them; only the
-- owner and crew can scare or hit them (nobody else can trigger, farm or spoil one).
Businesses.BreakIn = {
	MinPlay = 600, -- seconds of play this session before the first one can happen
	Gap = 1200, -- seconds of play between two (per owner, across all their businesses)
	Window = 900, -- ...then a random moment within this many more seconds
	Retry = 60, -- seconds of play before trying again when one was due but couldn't happen (not a citizen, registers low)
	MinRegister = 800, -- $ the register must hold
	Time = 120, -- seconds to stop it
	Robbers = { 1, 2 },
	Loss = 0.10, -- share of that owner's register taken when the time runs out
	Reward = 250, -- $ per robber stopped, to whoever stopped it (the owner or a crewmate)
	ScareReach = 26, -- studs: the server's limit for a gun pointed at a robber (the client asks within 22)
	ScareCone = 0.6, -- cosine: how squarely the scarer must face the robber (as a clerk robbery)
}

------------------------------------------------------------------ the businesses

-- Levels[n] = { Trickle ($/min while the owner is online, x RateScale), Cap (the register's size), JobMult
-- (x every job's pay), Adds (what that level brings, for the cards) }. Bays = wash bays open at each level.
-- MapLetter / MapColor: the business's blip on the minimap and the big map (yours get a gold ring).

-- Even steps from a to b over the five levels (rounded to whole dollars): the PRD's "Lv 1 -> Lv 5" ranges.
local function steps(a, b)
	local out = {}
	for i = 0, 4 do
		out[i + 1] = math.floor(a + (b - a) * i / 4 + 0.5)
	end
	return out
end

local JOB_MULT = { 1.0, 1.06, 1.12, 1.18, 1.25 } -- every business: +6% job pay a level, +25% at level 5

local function levels(trickle, cap, adds)
	local t, c = steps(trickle[1], trickle[2]), steps(cap[1], cap[2])
	local out = {}
	for i = 1, 5 do
		out[i] = { Trickle = t[i], Cap = c[i], JobMult = JOB_MULT[i], Adds = adds and adds[i] or nil }
	end
	return out
end

Businesses.List = {
	{
		Id = "CarWash",
		Name = "Suds & Shine Car Wash",
		Short = "Car Wash", -- in toasts ("Your Car Wash register is full")
		Brand = "Suds & Shine", -- on signs ("Player1's Suds & Shine")
		Kind = "Legit",
		Enabled = true,
		Price = 25000,
		Unlock = 1, -- Empire rank needed to buy it (1 = none)
		Style = "CarWash", -- BusinessService's building
		Blurb = "A hand-wash bay on Solana Avenue. Wash cars, deliver them across town, and grow it into a full tunnel wash.",
		JobLine = "Wash cars in the bay, and drive detailed cars to their owners",
		JobPay = "about $1,150 a minute of work",
		Hint = "Press Manage at the door: START JOB to wash and deliver cars. The register fills while you play.",
		Jobs = { { Kind = "Wash", Label = "WASH A CAR" }, { Kind = "Detail", Label = "DELIVER A CAR" } },
		Service = { Name = "Drive-through shine", Price = 100, Kind = "Shine", Words = "a shine" },
		-- Palm Hills' south edge, on the east side of Solana Avenue (x = 50), facing it; downtown's first block
		-- starts 12 studs south of the lot.
		Position = Vector3.new(112, 0, -860),
		Facing = Vector3.new(-1, 0, 0),
		Layout = {
			Door = Vector3.new(21, 0, 1),
			Register = Vector3.new(21.8, 0, 14),
			Robbers = { Vector3.new(19.6, 0, 10.4), Vector3.new(24, 0, 10.4) },
			Exit = Vector3.new(21, 0, -12),
			Bays = { Vector3.new(-22, 0, 9.5), Vector3.new(-12, 0, 9.5), Vector3.new(-2, 0, 9.5) },
			BayMouth = -3,
			Shine = Vector3.new(9, 0, -12),
			Pickup = Vector3.new(20.5, 0, -14),
		},
		Bays = { 1, 2, 3, 3, 3 },
		Levels = levels({ 60, 150 }, { 2000, 9000 }, {
			"One hand-wash bay and a painted sign",
			"A second wash bay and a vacuum station",
			"A third bay, the neon sign, a waiting bench: more customers",
			"The detailing garage opens",
			"A full drive-through tunnel with lights",
		}),
		Accent = Color3.fromRGB(40, 132, 214), -- wash-bay blue
		Neon = Color3.fromRGB(34, 225, 255),
		MapLetter = "W",
		MapColor = Color3.fromRGB(64, 156, 230),
	},
	{
		Id = "PalmGrind",
		Name = "Palm Grind Coffee",
		Short = "Coffee Shop",
		Brand = "Palm Grind",
		Kind = "Legit",
		Enabled = true, -- M2
		Price = 45000,
		Unlock = 1, -- no Empire rank needed
		Style = "Coffee", -- its building: ServerScriptService.Services.BusinessJobs.Coffee
		Blurb = "A corner café on Marina Row, by the Car Meet. Rush coffee orders across town against the clock, and grow it into a rooftop café.",
		JobLine = "Rush orders: deliver coffee across town against the clock",
		JobPay = "about $1,250 a minute of work",
		Hint = "Press Manage at the door: START JOB for rush orders. Grab one at the RUSH ORDERS shelf and drive it over.",
		Jobs = { { Kind = "Rush", Label = "RUSH ORDERS" } },
		Service = { Name = "Cold brew", Price = 60, Kind = "ColdBrew", Words = "a cold brew" },
		-- Marina Row, on the east side of Marina Link (x = 450), facing it; the Car Meet is ~170 studs to the
		-- north-east. (Lot re-checked for M2: see PLACES above.)
		Position = Vector3.new(505, 0, 905),
		Facing = Vector3.new(-1, 0, 0),
		-- The café (x -17..10, z 2..14; the door in the middle of its glass front), the counter at z 9..10.8
		-- with the register, ORDER HERE (cold brew) on its left and the RUSH ORDERS shelf on its right; the
		-- terrace and the parking bays on the forecourt; the drive-through loop (level 3) round the café.
		Layout = {
			Door = Vector3.new(0, 0, 2),
			Register = Vector3.new(2, 0, 9.8),
			Robbers = { Vector3.new(0.4, 0, 7.4), Vector3.new(3.6, 0, 7.4) },
			Exit = Vector3.new(0, 0, -16),
			Service = Vector3.new(-2.5, 0, 7.6),
			Orders = Vector3.new(6.5, 0, 7.6),
		},
		-- Trickle $96 -> $240 a minute, register $3.6k -> $14.4k: the PRD's first numbers x1.2 (Nov 4: trickle-only
		-- payback ~7.8 h instead of ~9.4; see BALANCE).
		Levels = levels({ 96, 240 }, { 3600, 14400 }, {
			"A counter, two tables and the RUSH ORDERS shelf",
			"A terrace with umbrellas · orders with 2 stops",
			"The drive-through window and the neon signs",
			"A roastery corner and a queue outside · 3 stops, VIP orders",
			"A rooftop café · more VIP orders",
		}),
		Accent = Color3.fromRGB(38, 128, 102), -- palm green
		Neon = Color3.fromRGB(255, 160, 64), -- warm amber
		MapLetter = "E",
		MapColor = Color3.fromRGB(196, 128, 70), -- coffee brown
	},
	{
		Id = "PrintShop",
		Name = "Backlot Print Shop",
		Short = "Print Shop",
		Brand = "Backlot Print",
		Kind = "Shady", -- no customers, no break-ins, police raids instead (SHADY BUSINESSES at the top)
		Enabled = true, -- M3
		Price = 90000,
		Unlock = 1, -- no Empire rank needed
		Style = "PrintShop", -- its building, job and raids: ServerScriptService.Services.BusinessJobs.PrintShop
		Blurb = "Flyers out front, something else in the back. Print fake cash, launder it across town, and watch for police raids.",
		JobLine = "Print and launder fake cash (cops can spot you)",
		JobPay = "about $1,600 a minute of work, with the risk",
		Hint = "Press Manage at the door: START JOB to print. Load the cash into your car at the bay and launder it. Raids take the dirty cash only.",
		Jobs = { { Kind = "Print", Label = "PRINT" }, { Kind = "Launder", Label = "LAUNDER" } },
		-- Rustwater Docks' back streets: the north side of the z = 1650 street, by the container lot (see PLACES).
		Position = Vector3.new(-396, 0, 1587),
		Facing = Vector3.new(0, 0, 1),
		-- A brick print shop (x -26..16, z -2..22): the PRINT & COPY front office on the left (its door at x -21..-17
		-- and the till), the workshop behind it with the three print stations along the back, the roll-up loading
		-- door at x 0..8 with the cash cart beside it, the loading bay painted on the forecourt in front of it.
		Layout = {
			Door = Vector3.new(-19, 0, -2),
			Register = Vector3.new(-23.8, 0, 2.5),
			Stations = { Vector3.new(-21, 0, 13), Vector3.new(-10, 0, 14), Vector3.new(4, 0, 10) },
			Search = Vector3.new(-3, 0, 11.5),
			Tray = Vector3.new(4, 0, 12.4), -- the press's out tray: where the printed sheets flutter out (BusinessClient)
			Cash = Vector3.new(-3.3, 0, 19.8), -- the counting table by the back wall: the stack of fake bills grows here (per device)
			Bay = Vector3.new(4, 0, -14),
			Load = Vector3.new(-1.5, 0, -4),
			RaidCar = Vector3.new(-14, 0, -17),
			RaidStand = { Vector3.new(-20.5, 0, -5), Vector3.new(-17.5, 0, -5) },
			Inside = { -25, 15, -1, 21 }, -- x0, x1, z0, z1: the floor inside the walls
		},
		-- Trickle $192 -> $450 a minute, register $7k -> $26k: the PRD's first numbers x~1.75 (Nov 4: trickle-only
		-- payback ~7.8 h instead of ~13.6; see BALANCE).
		Levels = levels({ 192, 450 }, { 7000, 26000 }, {
			"One old press in a back room",
			"A second press and a paper store · bigger loads",
			"Drying racks and a hidden back door · harder to spot",
			"A counting room and an armored door · slower breaches",
			"A full counterfeit floor · the biggest loads",
		}),
		Accent = Color3.fromRGB(150, 120, 235), -- (the map's violet; the building itself is brick and steel)
		MapLetter = "X",
		MapColor = Color3.fromRGB(150, 120, 235),
	},
	{
		Id = "BoatRentals",
		Name = "Coastline Boat Rentals",
		Short = "Boat Rentals",
		Brand = "Coastline Boats",
		Kind = "Legit",
		Enabled = true, -- M4
		Price = 120000,
		Unlock = 2, -- Empire rank needed to buy it (PRD: Empire 2 unlocks Boat Rentals)
		Style = "BoatRentals", -- its building, tours and rentals: ServerScriptService.Services.BusinessJobs.BoatRentals
		Blurb = "A floating dock beside Marina Boat Sales. Take tourists on sightseeing tours of the coast, rent out jet skis, and grow it into luxury yacht tours.",
		JobLine = "Boat tours: take tourists round the coast's landmarks",
		JobPay = "about $1,400 a minute of work",
		Hint = "Press Manage at the ticket booth: START JOB for boat tours. Drive through the buoys, slow right down for PHOTO STOPS, and keep the ride smooth.",
		Jobs = { { Kind = "Tour", Label = "BOAT TOURS" } },
		Service = { Name = "Jet ski rental", Price = 150, Kind = "Rental", Words = "a jet ski rental" },
		-- On the water off the end of the first marina pier, beside Marina Boat Sales (see PLACES), facing the pier
		-- (west): lot-space -Z is the gangway to the pier, +Z the open sea.
		Position = Vector3.new(1731, 0, 1100),
		Facing = Vector3.new(-1, 0, 0),
		-- A floating timber dock (BusinessJobs.BoatRentals): the front deck (z -25..-13) with the TOURS ticket booth
		-- (x 8..19, z -22..-15: the door at its front, the till on the counter at its back) and the JET SKI RENTALS
		-- stand at the head of the rental slip; the main pier (x -3..3) out to sea between the rental slip (x -17.5
		-- ..-3) and the tour boat's slip (x 3..16); a finger on each side and a berth for the fleet's display boats
		-- beyond each finger. The gangway to the marina pier lands at x 0.5..6.5.
		Layout = {
			Door = Vector3.new(13.5, 0, -22),
			Register = Vector3.new(13.5, 0, -16.4),
			Robbers = { Vector3.new(12, 0, -18.8), Vector3.new(15, 0, -18.8) },
			Exit = Vector3.new(13.5, 0, -24.3), -- straight out of the booth door to the front deck's edge (they fade there)
			Service = Vector3.new(-10, 0, -15.5),
			Berth = Vector3.new(9.5, 0, 1),
			Queue = { Vector3.new(0, 0, -9), Vector3.new(0, 0, -6), Vector3.new(0, 0, -3), Vector3.new(0, 0, 0), Vector3.new(0, 0, 3),
				Vector3.new(0, 0, 6) },
			SlipMouth = Vector3.new(9.5, 0, 28),
			Dock = Vector3.new(9.5, 0, 38),
			Rentals = { Vector3.new(-7.5, 0, -1), Vector3.new(-13.5, 0, -1) },
		},
		-- Trickle $256 -> $590 a minute, register $9.6k -> $35.4k: the PRD's first numbers ($130 -> $300, $5k -> $18k)
		-- x~1.97, the Nov 4 treatment (trickle-only payback ~7.8 h instead of ~15.4; see BALANCE).
		Levels = levels({ 256, 590 }, { 9600, 35400 }, {
			"A dock, a ticket hut and one small boat",
			"A second boat and a proper ticket booth · longer tours",
			"Jet skis for the fleet · a canopy tour boat",
			"The tour boat: a bigger hull, more tourists, longer tours",
			"Luxury yacht tours · the grand tour",
		}),
		Accent = Color3.fromRGB(28, 120, 150), -- sea blue (with marina teal and white timber)
		Neon = Color3.fromRGB(70, 220, 210), -- aqua
		MapLetter = "Y",
		MapColor = Color3.fromRGB(40, 180, 170),
	},
	{
		Id = "Nightclub",
		Name = "Afterglow Nightclub",
		Short = "Nightclub",
		Brand = "Afterglow",
		-- The club itself is legit (NPC break-ins come for its till); its BACK ROOM is shady (BackRoom: dirty cash, and
		-- police raids that only ever touch that stock).
		Kind = "Legit",
		Enabled = true, -- M5
		Price = 250000,
		Unlock = 3, -- Empire rank needed to buy it (PRD: Empire 3 unlocks the Nightclub)
		Style = "Nightclub", -- its building, VIP pickups, the club inside, the back room: ServerScriptService.Services.BusinessJobs.Nightclub
		Blurb = "The boardwalk's hottest club. Chauffeur celebrities to the red carpet in the club's limo, sell entry and VIP booths, and take double at night. After dark, the back room runs a card game.",
		JobLine = "VIP pickups: chauffeur celebrities to the red carpet in the club's limo",
		JobPay = "about $1,500 a minute of work, more at night",
		Hint = "Press Manage at the door: START JOB for VIP pickups. Drive smooth, lose the paparazzi and stop right on the VIP mark. After dark, wash the back room's cash at the safe.",
		Jobs = { { Kind = "Vip", Label = "VIP PICKUPS" } },
		Service = { Name = "Cover charge", Price = 50, Kind = "Cover", Words = "a cover charge" },
		Booth = { Name = "VIP booth", Price = 250, Words = "a VIP booth" }, -- (inside the club: Businesses.Club)
		NightMult = 2, -- the register fills this many times as fast at night (Businesses.NightShare of the time)
		BackRoom = true, -- a shady back room: dirty cash and police raids (Businesses.BackRoom)
		-- The beach side of the boardwalk, across Highway 1 from downtown, facing west to it (see PLACES).
		Position = Vector3.new(1150, 0, 355),
		Facing = Vector3.new(-1, 0, 0),
		-- The club (x -22..22, z -4..24, 18 tall): the front doors in the middle of its glass front (Layout.Door), the
		-- lobby inside with the ticket counter and its till (Register) and a small bar, the back room behind it (x
		-- 5..21, z 11..23: its door BackDoor, the safe, a card table). The forecourt: the red carpet from the door to the
		-- lot's front edge (x -2..2), the VIP mark beside it (Carpet: a pink box), the limo's bay on the other side
		-- (LimoBay), the velvet rope and the bouncer by the door (Service).
		Layout = {
			Door = Vector3.new(0, 0, -4),
			Register = Vector3.new(-16, 0, 5),
			Robbers = { Vector3.new(-17.5, 0, 2.6), Vector3.new(-14.5, 0, 2.6) },
			Exit = Vector3.new(-10, 0, -18),
			Service = Vector3.new(-5.5, 0, -7),
			LimoBay = Vector3.new(-12, 0, -15),
			Carpet = Vector3.new(6.5, 0, -16),
			Flashes = { Vector3.new(3.6, 0, -6.6), Vector3.new(6.4, 0, -6.4), Vector3.new(9.2, 0, -6.6), Vector3.new(-3.6, 0, -11),
				Vector3.new(-3.6, 0, -16) },
			Safe = Vector3.new(18.5, 0, 21),
			Search = Vector3.new(16, 0, 19.5),
			BackDoor = Vector3.new(9.5, 0, 10),
			RaidCar = Vector3.new(19, 0, -16),
			RaidStand = { Vector3.new(8, 0, 7.5), Vector3.new(11, 0, 7.5) },
			RaidWayIn = { Vector3.new(2, 0, -10), Vector3.new(1.5, 0, 0) },
			RaidPathIn = { Vector3.new(9.5, 0, 12.5), Vector3.new(13, 0, 17) },
			Inside = { -21, 21, -3, 23 }, -- x0, x1, z0, z1: the lobby and the back room (an owner or crewmate in here holds the door)
		},
		-- Trickle $375 -> $875 a minute by day, x2 at night; register $20k -> $75k: the PRD's first $180 -> $420 and
		-- $8k -> $25k given the Nov 4 treatment over a day and night (trickle-only payback ~7.8 h; see BALANCE).
		Levels = levels({ 375, 875 }, { 20000, 75000 }, {
			"A small bar and house music · the red carpet and the limo",
			"Dance floor lights · more dancers inside",
			"The DJ booth and a light show",
			"The VIP balcony",
			"A rooftop pool party",
		}),
		Accent = Color3.fromRGB(120, 36, 96), -- deep plum (with charcoal stucco and black glass)
		Neon = Color3.fromRGB(255, 62, 165), -- hot pink
		MapLetter = "V", -- (not N: the minimap's north marker is a round N on its edge too, as an owned blip would be)
		MapColor = Color3.fromRGB(255, 62, 165),
	},
}

Businesses.ById = {}
for _, def in ipairs(Businesses.List) do
	Businesses.ById[def.Id] = def
end

------------------------------------------------------------------ places

-- A lot's frame: origin at the lot centre on the ground, -Z toward the street.
function Businesses.Frame(def)
	return CFrame.lookAt(def.Position, def.Position + def.Facing)
end

-- A lot-space point (Vector3) in the world.
function Businesses.At(def, v)
	return (Businesses.Frame(def) * CFrame.new(v)).Position
end

function Businesses.DoorPosition(def)
	return Businesses.At(def, def.Layout.Door)
end

-- Bay i's centre on the ground, facing into the bay (+Z of the lot: nose toward the back wall).
function Businesses.BayCFrame(def, i)
	local bay = def.Layout.Bays[i]
	if not bay then
		return nil
	end
	return Businesses.Frame(def) * CFrame.new(bay) * CFrame.Angles(0, math.pi, 0)
end

------------------------------------------------------------------ maths (pure: the server, the cards and the logic tests use these)

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

-- A level clamped to 1..MaxLevel.
function Businesses.ClampLevel(n)
	return math.clamp(math.floor(num(n)), 1, Businesses.MaxLevel)
end

function Businesses.LevelInfo(def, level)
	return def.Levels[Businesses.ClampLevel(level)]
end

-- $ a minute the register fills at this level (busy: a crewmate is at the business; night: it's night, and the
-- business has a NightMult: the Nightclub's x2).
function Businesses.Trickle(def, level, busy, night)
	local base = Businesses.LevelInfo(def, level).Trickle * Businesses.RateScale
	if busy then
		base *= 1 + Businesses.BusyBonus
	end
	if night == true and def.NightMult then
		base *= def.NightMult
	end
	return base
end

-- The trickle at this level averaged over the game's day and night (Businesses.NightShare of it at night).
function Businesses.AvgTrickle(def, level)
	return Businesses.Trickle(def, level, false) * (1 + ((def.NightMult or 1) - 1) * Businesses.NightShare)
end

-- Is it night for the businesses? isNight = Workspace attribute IsNight; testNight = the Studio override BizTestNight
-- (callers pass it only in Studio): a boolean there wins.
function Businesses.NightNow(isNight, testNight)
	if type(testNight) == "boolean" then
		return testNight
	end
	return isNight == true
end

-- The register's size at this level.
function Businesses.Cap(def, level)
	return Businesses.LevelInfo(def, level).Cap
end

-- `seconds` of trickle (the owner was in the server): up to the cap. Returns the new register and what was
-- earned. A register already over its cap (a cap lowered in this config) keeps its money and earns nothing.
function Businesses.Accrue(def, register, level, seconds, busy, night)
	register = math.max(0, num(register))
	seconds = math.max(0, num(seconds))
	local cap = Businesses.Cap(def, level)
	local perSecond = Businesses.Trickle(def, level, busy, night) / 60
	if seconds <= 0 or register >= cap or perSecond <= 0 then
		return register, 0
	end
	local earned = math.min(perSecond * seconds, cap - register)
	return register + earned, earned
end

-- The price of the next level from `level` (nil at the top).
function Businesses.UpgradePrice(def, level)
	level = Businesses.ClampLevel(level)
	local share = Businesses.UpgradeShare[level + 1]
	if level >= Businesses.MaxLevel or not share then
		return nil
	end
	return math.floor(def.Price * share + 0.5)
end

-- x every job's pay at this level (and RateScale).
function Businesses.JobMult(def, level)
	return Businesses.LevelInfo(def, level).JobMult * Businesses.RateScale
end

-- Open wash bays at this level.
function Businesses.BayCount(def, level)
	local bays = def.Bays or { 1 }
	return math.min(bays[Businesses.ClampLevel(level)] or 1, #(def.Layout and def.Layout.Bays or { 1 }))
end

-- The streak multiplier for this many good results in a row (x1.0 up to the rule's Max). rule: Businesses.Streak
-- (the jobs: the first good result is x1.0, then +Step each) or, by default, Businesses.Print (the Print Shop's
-- PERFECT streak: +StreakStep from the first). Both rules: { Step / StreakStep, Max / StreakMax, From / StreakFrom }.
function Businesses.StreakMult(streak, rule)
	rule = type(rule) == "table" and rule or Businesses.Print
	local step = rule.Step or rule.StreakStep or 0
	local max = rule.Max or rule.StreakMax or 1
	local from = rule.From or rule.StreakFrom or 0
	return math.min(max, 1 + step * math.max(0, math.floor(num(streak)) - from))
end

-- A timing gauge's grade (the wash's SPRAY / RINSE, the Print Shop's stations): "Perfect" (let go inside the green
-- band, widened by slack each side), "Ok" (after Min; a hold that reached Full let go by itself) or "Early" (before
-- Min: it didn't count). gauge = { Min, Sweet = { from, to }, Full }; held = seconds by the server's clock.
function Businesses.GaugeGrade(gauge, held, slack)
	held, slack = num(held), num(slack)
	if held < gauge.Min - slack then
		return "Early"
	end
	if held >= gauge.Sweet[1] - slack and held <= gauge.Sweet[2] + slack then
		return "Perfect"
	end
	return "Ok"
end

-- How a wash gauge's hold went ("spray" | "rinse"): Businesses.GaugeGrade with the wash's slack.
function Businesses.WashGrade(step, held)
	local W = Businesses.Wash
	return Businesses.GaugeGrade(W.Gauge[step] or W.Gauge.spray, held, W.Slack)
end

-- Taps to scrub off one dirty spot of this dirt ("Mud" | "Bugs" | "Bird"; anything else counts as mud).
function Businesses.WashTaps(dirt)
	local d = Businesses.Wash.Dirt
	return (d[dirt] or d.Mud).Taps
end

-- One spot's dirt from a random number 0..1 (r), for a normal car or a special one (its own odds).
function Businesses.RollDirt(r, special)
	local W = Businesses.Wash
	local sp = special and W.Specials[special]
	local odds = sp and sp.Dirt
	r = num(r)
	local acc = 0
	for _, id in ipairs(W.DirtOrder) do
		acc += odds and (odds[id] or 0) or W.Dirt[id].Odds
		if r < acc then
			return id
		end
	end
	return W.DirtOrder[1]
end

-- The customer: a special one (an id in Wash.SpecialOrder) or nil, from two random numbers 0..1.
function Businesses.RollSpecial(r1, r2)
	local W = Businesses.Wash
	if num(r1) >= W.SpecialChance then
		return nil
	end
	local list = W.SpecialOrder
	return list[math.clamp(math.floor(num(r2) * #list) + 1, 1, #list)]
end

-- Seconds a wash with this many taps may take (car ready to the end of the rinse) for its ★ for time.
function Businesses.WashStarTime(taps)
	local st = Businesses.Wash.StarTime
	return st.Base + st.PerTap * math.max(0, num(taps))
end

-- A wash's rating, 1-3 stars: one for each PERFECT hold (0-2) and one for a quick wash, at least one.
function Businesses.WashStars(perfects, quick)
	return math.max(1, math.clamp(math.floor(num(perfects)), 0, 2) + (quick and 1 or 0))
end

-- A gauge grade's share of its third of the tip.
function Businesses.WashShare(grade)
	return grade == "Perfect" and 1 or (grade == "Ok" and Businesses.Wash.OkShare or 0)
end

-- A finished wash (whole dollars): pay, tip, stars, the ★★★ streak after it. w = { spray, rinse (grades),
-- quick (the ★ for time), birds (bird-mess spots), special (a Wash.Specials id or nil), streak (★★★ washes in a
-- row BEFORE this one) }. The streak raises the tip of a ★★★ wash only (Businesses.Streak); a special's PayMult
-- is on the whole wash, TipMult on the tip, PerfectTip on a ★★★ wash's tip.
function Businesses.WashPay(def, level, w)
	local W = Businesses.Wash
	w = type(w) == "table" and w or {}
	local mult = Businesses.JobMult(def, level)
	local sp = w.special and W.Specials[w.special] or nil
	local perfects = (w.spray == "Perfect" and 1 or 0) + (w.rinse == "Perfect" and 1 or 0)
	local stars = Businesses.WashStars(perfects, w.quick == true)
	local streak = stars == 3 and math.max(0, math.floor(num(w.streak))) + 1 or 0
	local whole = sp and sp.PayMult or 1
	local tipMult = (sp and sp.TipMult or 1) * ((sp and sp.PerfectTip and stars == 3) and sp.PerfectTip or 1)
	local share = (Businesses.WashShare(w.spray) + Businesses.WashShare(w.rinse) + (w.quick == true and 1 or 0)) / 3
	local birds = math.max(0, math.floor(num(w.birds)))
	local pay = math.floor((W.Pay + (W.Dirt.Bird.Pay or 0) * birds) * whole * mult + 0.5)
	local tip = math.floor(W.Tip * share * tipMult * whole * Businesses.StreakMult(streak, Businesses.Streak) * mult + 0.5)
	return pay, tip, stars, streak
end

-- The estimate (seconds) for a delivery of `length` studs of road.
function Businesses.DetailEstimate(length)
	local D = Businesses.Detail
	return math.max(0, num(length)) / D.EstSpeed + D.EstExtra
end

-- A delivery's rating, 1-3 stars: one for arriving inside the estimate, two for no dents (one for a single dent).
function Businesses.DetailStars(took, est, dents)
	dents = math.max(0, math.floor(num(dents)))
	local pts = (num(took) <= math.max(1, num(est)) and 1 or 0) + (dents == 0 and 2 or (dents == 1 and 1 or 0))
	return math.clamp(pts, 1, 3)
end

-- A finished delivery (whole dollars): pay, tip, stars, the no-dent streak after it. took / est in seconds; dents
-- counted; sports = a sports car (Detail.Sports: tip x TipMult, DentCost a dent); streak = clean deliveries in a
-- row BEFORE this one (a clean one adds to it and raises its own tip: Businesses.Streak).
function Businesses.DetailPay(def, level, length, took, est, dents, sports, streak)
	local D = Businesses.Detail
	local mult = Businesses.JobMult(def, level)
	length, took, est = math.max(0, num(length)), math.max(0, num(took)), math.max(1, num(est))
	dents = math.max(0, math.floor(num(dents)))
	local pay = math.floor((D.Base + D.PerStud * length) * mult + 0.5)
	local share = 1
	if took > est then
		share = math.clamp(1 - (took - est) / (est * D.TipFade), 0, 1)
	end
	local sp = sports == true and D.Sports or nil
	local tip = math.max(0, math.floor(D.TipMax * share * (sp and sp.TipMult or 1) + 0.5) - (sp and sp.DentCost or D.DentCost) * dents)
	local newStreak = dents == 0 and math.max(0, math.floor(num(streak))) + 1 or 0
	tip *= Businesses.StreakMult(newStreak, Businesses.Streak)
	return pay, math.floor(tip * mult + 0.5), Businesses.DetailStars(took, est, dents), newStreak
end

-- How many addresses a rush order has at this level.
function Businesses.RushDrops(level)
	return Businesses.Rush.Drops[Businesses.ClampLevel(level)] or 1
end

-- The clock (seconds) for one rush-order address `road` studs of road away. first: the order's first
-- address (the clock also covers walking out to your car).
function Businesses.RushTimer(road, first)
	local Ru = Businesses.Rush
	return math.max(0, num(road)) / Ru.EstSpeed + (first and Ru.FirstExtra or Ru.NextExtra)
end

-- The share (0-1) of the speed tip for an address reached `took` seconds into its `timer`-second clock:
-- full while TipFull of the clock is left, then down to 0 at 0:00; nothing late.
function Businesses.RushTipShare(took, timer)
	took, timer = math.max(0, num(took)), math.max(1, num(timer))
	local left = timer - took
	if left <= 0 then
		return 0
	end
	return math.clamp(left / (timer * Businesses.Rush.TipFull), 0, 1)
end

-- An address's medal, reached `took` seconds into its `timer`-second clock: "Gold" (TipFull of the clock or more
-- still left: the full tip), "Silver" (before 0:00: the tip fading) or "Bronze" (late: the base only).
function Businesses.RushMedal(took, timer)
	took, timer = math.max(0, num(took)), math.max(1, num(timer))
	local left = timer - took
	if left >= timer * Businesses.Rush.TipFull then
		return "Gold"
	elseif left > 0 then
		return "Silver"
	end
	return "Bronze"
end

-- Is a rush hour on? untilT = the owner's BizRushHour attribute (server time it ends), now = server time.
function Businesses.RushHourOn(untilT, now)
	return type(untilT) == "number" and type(now) == "number" and untilT > now
end

-- One rush-order address delivered (whole dollars): pay, tip, medal, the gold streak after it. road = this leg's
-- road length; back = the road from this address back to the café when it's the order's last (else 0); first =
-- the order's first address (it carries the order's own pay); took / timer in seconds; vip = a VIP order; streak =
-- GOLDs in a row BEFORE this one (a GOLD adds to it and raises its own tip: Businesses.Streak); rushHour = the
-- owner's rush hour is on (+RushHour.TipBoost on the tip).
function Businesses.RushPay(def, level, road, back, first, took, timer, vip, streak, rushHour)
	local Ru = Businesses.Rush
	local mult = Businesses.JobMult(def, level)
	local vipMult = vip and Ru.VIPMult or 1
	local pay = (Ru.DropPay + Ru.PerStud * math.max(0, num(road))) * vipMult + Ru.PerStud * math.max(0, num(back))
		+ (first and Ru.OrderPay or 0)
	local medal = Businesses.RushMedal(took, timer)
	local newStreak = medal == "Gold" and math.max(0, math.floor(num(streak))) + 1 or 0
	local tip = Ru.TipMax * Businesses.RushTipShare(took, timer) * vipMult * Businesses.StreakMult(newStreak, Businesses.Streak)
		* (rushHour == true and (1 + Ru.RushHour.TipBoost) or 1)
	return math.floor(pay * mult + 0.5), math.floor(tip * mult + 0.5), medal, newStreak
end

-- The tip an address would pay if reached now (the job strip's live number: the same maths as the server's).
function Businesses.RushTip(def, level, took, timer, vip, streak, rushHour)
	local _, tip = Businesses.RushPay(def, level, 0, 0, false, took, timer, vip, streak, rushHour)
	return tip
end

-- The PERFECT RUN bonus (whole dollars) for an order of `drops` stops with `golds` GOLDs: Rush.PerfectRun x
-- JobMult when it had 2+ stops and every one was a GOLD, else 0.
function Businesses.PerfectRunBonus(def, level, drops, golds)
	drops, golds = math.floor(num(drops)), math.floor(num(golds))
	if drops < 2 or golds < drops then
		return 0
	end
	return math.floor(Businesses.Rush.PerfectRun * Businesses.JobMult(def, level) + 0.5)
end

-- LocomotionClient's sprint drain multiplier while a cold brew is on (untilT, now: server time).
function Businesses.ColdBrewDrain(untilT, now)
	if type(untilT) == "number" and type(now) == "number" and untilT > now then
		return 1 / (1 + Businesses.ColdBrew.Stamina)
	end
	return 1
end

-- Does this purchase still earn the featured owner Empire XP? rec = the owner's record for this buyer
-- ({ since, count } or nil), now = os.clock(). One buyer counts at most Empire.XP.CustomerPerBuyerHour times
-- an hour (a second account buying again and again can't farm a rank; the money still goes to the owner).
-- Returns yes / no and the record to keep.
function Businesses.CustomerXP(rec, now)
	now = num(now)
	if type(rec) ~= "table" or type(rec.since) ~= "number" or type(rec.count) ~= "number" or now - rec.since >= 3600 then
		rec = { since = now, count = 0 }
	end
	if rec.count < (Businesses.Empire.XP.CustomerPerBuyerHour or 2) then
		rec.count += 1
		return true, rec
	end
	return false, rec
end

-- The kinds of job START JOB offers at this business (its Jobs list).
function Businesses.HasJob(def, kind)
	for _, j in ipairs(def and def.Jobs or {}) do
		if j.Kind == kind then
			return true
		end
	end
	return false
end

-- Empire rank for this much Empire XP.
function Businesses.RankFor(xp)
	xp = num(xp)
	local E = Businesses.Empire
	local rank = 1
	while rank < E.MaxRank and xp >= E.XPFor[rank + 1] do
		rank += 1
	end
	return rank
end

-- rank, share of the way to the next rank (0-1), XP into this rank, XP this rank needs (0 at the top).
function Businesses.RankProgress(xp)
	xp = math.max(0, num(xp))
	local E = Businesses.Empire
	local rank = Businesses.RankFor(xp)
	if rank >= E.MaxRank then
		return rank, 1, xp - E.XPFor[rank], 0
	end
	local from, to = E.XPFor[rank], E.XPFor[rank + 1]
	return rank, (xp - from) / (to - from), xp - from, to - from
end

-- The highest title reached at this rank (nil below the first).
function Businesses.TitleFor(rank)
	local best
	for r, title in pairs(Businesses.Empire.Titles) do
		if rank >= r and (not best or r > best) then
			best = r
		end
	end
	return best and Businesses.Empire.Titles[best] or nil
end

-- May someone of this Empire rank buy this business?
function Businesses.Unlocked(def, rank)
	return num(rank) >= (def.Unlock or 1)
end

-- A player customer's payment: the featured owner's share and the sink (whole dollars, adding up to price).
function Businesses.Split(price)
	price = math.max(0, math.floor(num(price)))
	local owner = math.floor(price * Businesses.CustomerShare)
	return owner, price - owner
end

-- The owner's cut of a crewmate's job pay (paid by the game on top).
function Businesses.CrewCutFor(pay)
	return math.floor(math.max(0, num(pay)) * Businesses.CrewCut)
end

-- What break-in robbers take when the time runs out (whole dollars, never more than the register).
function Businesses.BreakInLoss(register)
	register = math.max(0, num(register))
	return math.min(math.floor(register), math.floor(register * Businesses.BreakIn.Loss))
end

------------------------------------------------------------------ maths: the Print Shop (M3)

-- May NPC robbers break into this business? Legit ones only (PRD pillar 3: shady ones get police raids instead).
function Businesses.BreakInEligible(def)
	return type(def) == "table" and def.Kind == "Legit"
end

-- How a print station's hold went: "Perfect" (let go inside the green band, widened by Slack each side), "Ok"
-- (after Min; a hold that reached Full let go by itself) or "Early" (before Min: it didn't count). held = seconds
-- by the server's clock. (Businesses.GaugeGrade, shared with the wash's SPRAY and RINSE.)
function Businesses.PrintGrade(station, held)
	local P = Businesses.Print
	local st = P.Stations[math.clamp(math.floor(num(station)), 1, #P.Stations)]
	return Businesses.GaugeGrade(st, held, P.Slack)
end

-- (The streak multiplier, Businesses.StreakMult(streak), is with the job maths above: called with one argument it
-- is the Print Shop's PERFECT streak, x1.0 + StreakStep a PERFECT up to StreakMax.)

-- The dirty cash one finished press run prints (whole dollars): perfects = PERFECT stations in this run (0-3),
-- streak = PERFECTs in a row at its end.
function Businesses.PrintBatch(def, level, perfects, streak)
	local P = Businesses.Print
	local k = math.clamp(math.floor(num(perfects)), 0, #P.Stations)
	return math.floor(P.Batch * Businesses.JobMult(def, level) * (1 + P.PerfectBonus * k) * Businesses.StreakMult(streak) + 0.5)
end

-- The dirty cash the back room holds at this level, and what one launder run carries.
function Businesses.Stock(level)
	return Businesses.Print.Stock[Businesses.ClampLevel(level)]
end

function Businesses.Carry(level)
	return Businesses.Launder.Carry[Businesses.ClampLevel(level)]
end

-- Dirty cash into the stock, up to its cap. Returns the new stock and what went in (a stock already over its cap
-- from an older config keeps its cash and takes nothing).
function Businesses.AddDirty(dirty, amount, cap)
	dirty, amount, cap = math.max(0, num(dirty)), math.max(0, math.floor(num(amount))), math.max(0, num(cap))
	local added = math.max(0, math.min(amount, math.floor(cap - dirty)))
	return dirty + added, added
end

-- A delivered launder run: the clean pay and the clean-run bonus (whole dollars).
function Businesses.LaunderPay(bags, clean)
	local L = Businesses.Launder
	bags = math.max(0, math.floor(num(bags)))
	local pay = math.floor(bags * L.Rate + 0.5)
	return pay, clean and math.floor(bags * L.CleanBonus + 0.5) or 0
end

-- The tip-off chance of one roll at this level.
function Businesses.SpotChance(level)
	return Businesses.Launder.SpotChance[Businesses.ClampLevel(level)] or 0
end

-- The heat meter after dt seconds: dist = studs to the nearest police (nil or beyond HeatRange: none in range),
-- seen = a clear line between you. Returns 0..1 (1 = spotted).
function Businesses.HeatStep(heat, dt, dist, seen)
	local L = Businesses.Launder
	heat, dt = math.clamp(num(heat), 0, 1), math.max(0, num(dt))
	local d = dist ~= nil and num(dist) or math.huge
	if d >= L.HeatRange then
		return math.max(0, heat - L.HeatFall * dt)
	end
	local close = 1 - math.max(0, d) / L.HeatRange
	return math.min(1, heat + L.HeatRise * close * (seen and 1 or L.HeatHidden) * dt)
end

-- The chance a warrant roll hits for this stock at this level (0 below MinDirty). cap / minDirty: another building's
-- (the Nightclub's back room: Businesses.BackRoomStock, BackRoom.MinDirty); nil = the Print Shop's.
function Businesses.WarrantChance(dirty, level, cap, minDirty)
	local R = Businesses.Raid
	dirty = num(dirty)
	cap = cap ~= nil and num(cap) or Businesses.Stock(level)
	local minD = minDirty ~= nil and num(minDirty) or R.MinDirty
	if dirty < minD or cap <= minD then
		return dirty >= minD and R.Chance[2] or 0
	end
	local share = math.clamp((dirty - minD) / (cap - minD), 0, 1)
	return R.Chance[1] + (R.Chance[2] - R.Chance[1]) * share
end

-- Seconds a cop holds BREACH at this owner level's door (the armored door is slower).
function Businesses.BreachHold(level)
	local R = Businesses.Raid
	return Businesses.ClampLevel(level) >= R.ArmoredLevel and R.ArmoredHold or R.BreachHold
end

-- A player-cop raid's reward for each of `cops` cops (whole dollars): RewardBase + an even split of SeizeShare
-- of what was seized (x RateScale, at most RewardMax in all). Returns each one's and the total.
function Businesses.RaidReward(seized, cops)
	local R = Businesses.Raid
	cops = math.max(1, math.floor(num(cops)))
	local share = math.min(R.RewardMax, math.floor(math.max(0, num(seized)) * R.SeizeShare * Businesses.RateScale))
	local each = math.floor(R.RewardBase * Businesses.RateScale) + math.floor(share / cops)
	return each, each * cops
end

-- What an AI raid takes from this stock (whole dollars).
function Businesses.AISeizeAmount(dirty)
	dirty = math.max(0, num(dirty))
	return math.min(math.floor(dirty), math.floor(dirty * Businesses.Raid.AISeize))
end

-- Is this world point inside the business's building (Layout.Inside: the floor, up to 16 studs up)?
function Businesses.Inside(def, pos)
	local box = def and def.Layout and def.Layout.Inside
	if not box or not pos then
		return false
	end
	local d = pos - def.Position
	if d.Y < -4 or d.Y > 16 then
		return false
	end
	local look = def.Facing
	-- (lot space: +X = look x up, -Z = look)
	local x = -d.X * look.Z + d.Z * look.X
	local z = -(d.X * look.X + d.Z * look.Z)
	return x >= box[1] and x <= box[2] and z >= box[3] and z <= box[4]
end

------------------------------------------------------------------ maths: Coastline Boat Rentals (M4)

-- The tour boat (a Config.Vehicles id), its fit-out and how many tourists come aboard, at the owner's level.
function Businesses.TourBoat(level)
	local T = Businesses.Tour
	return T.Boats[Businesses.ClampLevel(level)] or T.Boats[1]
end

function Businesses.TourFitout(level)
	return Businesses.Tour.Fitout[Businesses.ClampLevel(level)] or "Plain"
end

function Businesses.TourTourists(level)
	return Businesses.Tour.Tourists[Businesses.ClampLevel(level)] or 2
end

-- A route by its Id (nil when there's none).
function Businesses.TourRoute(id)
	for _, r in ipairs(Businesses.Tour.Routes) do
		if r.Id == id then
			return r
		end
	end
	return nil
end

-- The routes the owner's level offers (MinLevel at most the level), and the newest MinLevel among them.
function Businesses.TourRoutes(level)
	level = Businesses.ClampLevel(level)
	local list, newest = {}, 0
	for _, r in ipairs(Businesses.Tour.Routes) do
		if r.MinLevel <= level then
			table.insert(list, r)
			newest = math.max(newest, r.MinLevel)
		end
	end
	return list, newest
end

-- A new tour's route from two random numbers 0..1: OwnShare of the time one of the newest routes the level offers
-- (its "own" tours), else any it offers.
function Businesses.PickRoute(level, r1, r2)
	local list, newest = Businesses.TourRoutes(level)
	local pool = list
	if num(r1) < Businesses.Tour.OwnShare then
		pool = {}
		for _, r in ipairs(list) do
			if r.MinLevel == newest then
				table.insert(pool, r)
			end
		end
	end
	if #pool == 0 then
		return Businesses.Tour.Routes[1]
	end
	return pool[math.clamp(math.floor(num(r2) * #pool) + 1, 1, #pool)]
end

-- A route's stops in order: { Id, Name, Pos (world, y 0), Line, Kind = "Pass" | "Photo" | "Fish" }.
function Businesses.TourStops(route)
	local out = {}
	for _, s in ipairs(route and route.Stops or {}) do
		local l = Businesses.Tour.Stops[s[1]]
		if l then
			table.insert(out, { Id = s[1], Name = l.Name, Pos = l.Pos, Line = l.Line, Kind = s[2] or "Pass" })
		end
	end
	return out
end

-- How many photo or fishing stops a route has.
function Businesses.TourStopCount(route)
	local n = 0
	for _, s in ipairs(Businesses.TourStops(route)) do
		if s.Kind ~= "Pass" then
			n += 1
		end
	end
	return n
end

-- A route's length (studs, flat): from the berth through every stop to the dock ring, in straight lines.
function Businesses.TourLength(def, route)
	local function flatAt(v)
		return Vector3.new(v.X, 0, v.Z)
	end
	local prev = flatAt(Businesses.At(def, def.Layout.Berth))
	local len = 0
	for _, s in ipairs(Businesses.TourStops(route)) do
		len += (flatAt(s.Pos) - prev).Magnitude
		prev = flatAt(s.Pos)
	end
	return len + (flatAt(Businesses.At(def, def.Layout.Dock)) - prev).Magnitude
end

-- Par (seconds, from "all aboard" to stopped in the dock ring) for a route of `length` studs with `stops` photo or
-- fishing stops (parMult: a special's, e.g. the Fishing Party's x1.5).
function Businesses.TourPar(length, stops, parMult)
	local T = Businesses.Tour
	return (T.ParExtra + math.max(0, num(length)) / T.ParSpeed + T.ParStop * math.max(0, math.floor(num(stops)))) * (parMult or 1)
end

-- Did the boat pass within `radius` of the ring on its way from `from` to `to` (flat positions)? `from` = nil on
-- the first check, ignored after a jump longer than Tour.MaxStep (not driving). As RaceService's checkpoints:
-- the whole stretch counts, so a fast boat can't skip a ring between two checks.
function Businesses.TourReached(from, to, cp, radius)
	radius = num(radius)
	if from then
		local step = to - from
		local len2 = step.X * step.X + step.Z * step.Z
		local maxStep = Businesses.Tour.MaxStep
		if len2 >= 1e-4 and len2 <= maxStep * maxStep then
			local t = math.clamp(((cp.X - from.X) * step.X + (cp.Z - from.Z) * step.Z) / len2, 0, 1)
			local px, pz = from.X + step.X * t - cp.X, from.Z + step.Z * t - cp.Z
			if px * px + pz * pz <= radius * radius then
				return true
			end
		end
	end
	local dx, dz = to.X - cp.X, to.Z - cp.Z
	return dx * dx + dz * dz <= radius * radius
end

-- One check of a PHOTO (kind "Photo") or FISHING ("Fish") stop. st = this stop's state ({ hold, steady, entered };
-- nil = fresh), dt = seconds since the last check, inside = the boat within the ring (plus Slack), speed = its
-- flat speed (studs/s). Returns the state and nil (going on), "Perfect", "Ok" or "Missed" (left the ring before
-- the hold was done). Over the rule's Speed inside the ring starts the hold again; under its Perfect counts as
-- steady, and Perfect needs PerfectHold seconds of steady in the hold.
function Businesses.PhotoStep(st, dt, inside, speed, kind)
	local rule = kind == "Fish" and Businesses.Tour.Fish or Businesses.Tour.Photo
	if type(st) ~= "table" then
		st = { hold = 0, steady = 0, entered = false }
	end
	if not inside then
		if st.entered then
			return st, "Missed"
		end
		return st, nil
	end
	st.entered = true
	speed, dt = math.max(0, num(speed)), math.max(0, num(dt))
	if speed > rule.Speed then
		st.hold, st.steady = 0, 0
		return st, nil
	end
	st.hold += dt
	if speed <= rule.Perfect then
		st.steady += dt
	end
	if st.hold >= rule.Hold - 1e-9 then
		return st, (st.steady >= rule.PerfectHold - 1e-9) and "Perfect" or "Ok"
	end
	return st, nil
end

-- A photo (or fishing) stop's share of its part of the tip.
function Businesses.PhotoShare(grade)
	return grade == "Perfect" and 1 or (grade == "Ok" and Businesses.Tour.OkShare or 0)
end

-- The tourists' mood after dt seconds: lat = the boat's lateral acceleration (speed x turn rate, studs/s^2), ram =
-- it rammed something this check, aground = it's out of the water now, newlyAground = it just ran aground.
-- Returns the new mood (0-1) and how much it dropped.
function Businesses.TourMood(mood, dt, lat, ram, aground, newlyAground)
	local M = Businesses.Tour.Mood
	dt, lat = math.max(0, num(dt)), math.max(0, num(lat))
	local drop = 0
	if lat > M.TurnLimit then
		drop += M.TurnDrain * math.min(M.TurnCap, (lat - M.TurnLimit) / M.TurnLimit) * dt
	end
	if ram then
		drop += M.RamHit
	end
	if newlyAground then
		drop += M.BeachHit
	end
	if aground then
		drop += M.BeachDrain * dt
	end
	local m = math.clamp(num(mood), 0, 1)
	if drop > 0 then
		return math.max(0, m - drop), drop
	end
	return math.min(1, m + M.Recover * dt), 0
end

-- A tour's rating, 1-3 stars: one inside par, one with every photo stop PERFECT, one with the tourists at least
-- Mood.StarAt happy; at least one.
function Businesses.TourStars(onTime, allPerfect, mood)
	local pts = (onTime and 1 or 0) + (allPerfect and 1 or 0) + (num(mood) >= Businesses.Tour.Mood.StarAt - 1e-9 and 1 or 0)
	return math.max(1, pts)
end

-- A finished tour (whole dollars): pay, tip, stars, the ★★★ streak after it, the special's bonus, the tip's share
-- (0-1). t = { length (studs), grades (every photo / fishing stop's: "Perfect" | "Ok" | "Missed"), took, par
-- (seconds), mood (0-1), special (a Tour.Specials id or nil), streak (★★★ tours in a row BEFORE this one) }.
-- The pay is paid whatever happened; the tip is TipRate of it x the three shares' average (time, photos, mood);
-- a special's PayMult is on both, its PerfectTip on a ★★★ tour's tip, its Bonus on top; ★★★ tours in a row raise
-- the tip (Businesses.Streak).
function Businesses.TourPay(def, level, t)
	local T = Businesses.Tour
	t = type(t) == "table" and t or {}
	local mult = Businesses.JobMult(def, level)
	local sp = t.special and T.Specials[t.special] or nil
	local grades = type(t.grades) == "table" and t.grades or {}
	local n = #grades
	local took, par = math.max(0, num(t.took)), math.max(1, num(t.par))
	local base = (T.Base + T.PerStud * math.max(0, num(t.length)) + T.StopPay * n) * (sp and sp.PayMult or 1)
	local timeShare = took <= par and 1 or math.clamp(1 - (took - par) / (par * T.TimeFade), 0, 1)
	local photoShare, allPerfect = 1, true
	if n > 0 then
		local sum = 0
		for _, g in ipairs(grades) do
			sum += Businesses.PhotoShare(g)
			allPerfect = allPerfect and g == "Perfect"
		end
		photoShare = sum / n
	end
	local mood = math.clamp(num(t.mood), 0, 1)
	local moodShare = math.clamp((mood - T.Mood.Zero) / (1 - T.Mood.Zero), 0, 1)
	local stars = Businesses.TourStars(took <= par, allPerfect, mood)
	local streak = stars == 3 and math.max(0, math.floor(num(t.streak))) + 1 or 0
	local share = (timeShare + photoShare + moodShare) / 3
	local tipMult = (sp and sp.PerfectTip and stars == 3) and sp.PerfectTip or 1
	local tip = base * T.TipRate * share * tipMult * Businesses.StreakMult(streak, Businesses.Streak)
	local bonus = sp and sp.Bonus or 0
	return math.floor(base * mult + 0.5), math.floor(tip * mult + 0.5), stars, streak, math.floor(bonus * mult + 0.5), share
end

-- Is it dusk or night (a Sunset Tour may roll)? clock = Lighting.ClockTime, isNight = Workspace attribute IsNight.
function Businesses.SunsetTime(clock, isNight)
	if isNight == true then
		return true
	end
	local T = Businesses.Tour
	local c = num(clock)
	return c >= T.SunsetFrom or c < T.SunsetTo
end

-- The tour: a special one (an id in Tour.SpecialOrder) or nil, from two random numbers 0..1; night = dusk or night
-- (Businesses.SunsetTime: only then may it be a Sunset Tour).
function Businesses.RollTourSpecial(r1, r2, night)
	local T = Businesses.Tour
	if num(r1) >= T.SpecialChance then
		return nil
	end
	local list = {}
	for _, id in ipairs(T.SpecialOrder) do
		local sp = T.Specials[id]
		if sp and (not sp.Night or night == true) then
			table.insert(list, id)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(num(r2) * #list) + 1, 1, #list)]
end

-- Seconds left on a jet ski rental (untilT, now: server time; 0 when it's over or not a number).
function Businesses.RentalLeft(untilT, now)
	if type(untilT) ~= "number" or type(now) ~= "number" or untilT ~= untilT then
		return 0
	end
	return math.max(0, untilT - now)
end

------------------------------------------------------------------ maths: the Afterglow Nightclub (M5)

-- Can this business be raided (a shady one, or one with a shady back room)?
function Businesses.HasRaids(def)
	return type(def) == "table" and (def.Kind == "Shady" or def.BackRoom ~= nil)
end

-- The back room: its stock's cap, its night rate ($ a minute, x RateScale) and one WASH, at the owner's level.
function Businesses.BackRoomStock(level)
	return Businesses.BackRoom.Stock[Businesses.ClampLevel(level)]
end

function Businesses.BackRoomRate(level)
	return Businesses.BackRoom.Rate[Businesses.ClampLevel(level)] * Businesses.RateScale
end

function Businesses.BackRoomWash(level)
	return Businesses.BackRoom.Wash[Businesses.ClampLevel(level)]
end

-- The dirty stock's cap for this business at this level (the Print Shop's presses or the Nightclub's back room).
function Businesses.DirtyCap(def, level)
	if type(def) == "table" and def.BackRoom then
		return Businesses.BackRoomStock(level)
	end
	return Businesses.Stock(level)
end

-- `seconds` of the back room's card game (only at night): the new stock (may hold cents) and what went in, up to the cap.
function Businesses.BackRoomAccrue(dirty, level, seconds, night)
	dirty = math.max(0, num(dirty))
	seconds = math.max(0, num(seconds))
	local cap = Businesses.BackRoomStock(level)
	if night ~= true or seconds <= 0 or dirty >= cap then
		return dirty, 0
	end
	local add = math.min(Businesses.BackRoomRate(level) / 60 * seconds, cap - dirty)
	return dirty + add, add
end

-- One WASH at the safe (whole dollars): what moves into clean cash, and the stock left.
function Businesses.BackRoomWashAmount(dirty, level)
	dirty = math.max(0, num(dirty))
	local amount = math.min(math.floor(dirty), Businesses.BackRoomWash(level))
	return amount, dirty - amount
end

-- The limo's paint and fit-out at the owner's level.
function Businesses.VipPaint(level)
	return Businesses.Vip.Paint[Businesses.ClampLevel(level)]
end

function Businesses.VipFitout(level)
	return Businesses.Vip.Fitout[Businesses.ClampLevel(level)] or "Plain"
end

-- Par (seconds, from the VIP aboard to stopped on the mark) for `road` studs of road back (parMult: a special's).
function Businesses.VipPar(road, parMult)
	local V = Businesses.Vip
	return (V.ParExtra + math.max(0, num(road)) / V.ParSpeed) * (parMult or 1)
end

-- How well the limo stopped: dist = studs (flat) from its middle to the VIP mark. "Perfect" | "Good" | "Ok".
function Businesses.VipStop(dist)
	local st = Businesses.Vip.Stop
	if type(dist) ~= "number" or dist ~= dist then
		return "Ok" -- (a broken reading is never a PERFECT)
	end
	dist = math.abs(dist)
	if dist <= st.Perfect then
		return "Perfect"
	elseif dist <= st.Good then
		return "Good"
	end
	return "Ok"
end

function Businesses.VipStopShare(grade)
	return Businesses.Vip.StopShare[grade or "Ok"] or Businesses.Vip.StopShare.Ok
end

-- An arrival's rating, 1-3 stars: one inside par, one with the VIP at least Comfort.StarAt comfortable, one for a
-- PERFECT stop on the mark; at least one.
function Businesses.VipStars(onTime, comfort, stop)
	local pts = (onTime and 1 or 0) + (num(comfort) >= Businesses.Vip.Comfort.StarAt - 1e-9 and 1 or 0) + (stop == "Perfect" and 1 or 0)
	return math.max(1, pts)
end

-- The VIP's comfort after dt seconds: lat = the limo's lateral acceleration (studs/s^2), ram = it crashed this check,
-- air = it left the ground this check, flash = a paparazzi car is flashing its cameras close by. Returns the new
-- comfort (0-1) and how much it dropped.
function Businesses.VipComfort(comfort, dt, lat, ram, air, flash)
	local M = Businesses.Vip.Comfort
	dt, lat = math.max(0, num(dt)), math.max(0, num(lat))
	local drop = 0
	if lat > M.TurnLimit then
		drop += M.TurnDrain * math.min(M.TurnCap, (lat - M.TurnLimit) / M.TurnLimit) * dt
	end
	if ram then
		drop += M.RamHit
	end
	if air then
		drop += M.AirHit
	end
	if flash then
		drop += M.FlashDrain * dt
	end
	local c = math.clamp(num(comfort), 0, 1)
	if drop > 0 then
		return math.max(0, c - drop), drop
	end
	return math.min(1, c + M.Recover * dt), 0
end

-- A VIP brought to the red carpet (whole dollars): pay, tip, stars, the ★★★ streak after it, the paparazzi bonus, the
-- tip's share (0-1). v = { road (studs of road, both legs), took, par (seconds, the ride back), comfort (0-1), stop
-- ("Perfect" | "Good" | "Ok"), lost (the paparazzi were lost), special (a Vip.Specials id or nil), streak (★★★ in a row
-- BEFORE this one), night (it's night: NightMult on pay and tip) }. The pay is paid whatever happened; the tip is
-- TipRate of it x the three shares' average (time, comfort, the stop); a special's PayMult is on both, TipMult on the
-- tip, PerfectTip on a ★★★ tip, PapMult on the bonus; ★★★ in a row raise the tip (Businesses.Streak).
function Businesses.VipPay(def, level, v)
	local V = Businesses.Vip
	v = type(v) == "table" and v or {}
	local mult = Businesses.JobMult(def, level)
	local sp = v.special and V.Specials[v.special] or nil
	local nightMult = v.night == true and V.NightMult or 1
	local took, par = math.max(0, num(v.took)), math.max(1, num(v.par))
	local base = (V.Base + V.PerStud * math.max(0, num(v.road))) * (sp and sp.PayMult or 1) * nightMult
	local timeShare = took <= par and 1 or math.clamp(1 - (took - par) / (par * V.TimeFade), 0, 1)
	local comfort = math.clamp(num(v.comfort), 0, 1)
	local comfortShare = math.clamp((comfort - V.Comfort.Zero) / (1 - V.Comfort.Zero), 0, 1)
	local stop = (v.stop == "Perfect" or v.stop == "Good") and v.stop or "Ok"
	local stars = Businesses.VipStars(took <= par, comfort, stop)
	local streak = stars == 3 and math.max(0, math.floor(num(v.streak))) + 1 or 0
	local share = (timeShare + comfortShare + Businesses.VipStopShare(stop)) / 3
	local tipMult = (sp and sp.TipMult or 1) * ((sp and sp.PerfectTip and stars == 3) and sp.PerfectTip or 1)
	local tip = base * V.TipRate * share * tipMult * Businesses.StreakMult(streak, Businesses.Streak)
	local bonus = v.lost == true and V.Pap.Bonus * (sp and sp.PapMult or 1) or 0
	return math.floor(base * mult + 0.5), math.floor(tip * mult + 0.5), stars, streak, math.floor(bonus * mult + 0.5), share
end

-- The VIP: a special one (an id in Vip.SpecialOrder) or nil, from two random numbers 0..1.
function Businesses.RollVipSpecial(r1, r2)
	local V = Businesses.Vip
	if num(r1) >= V.SpecialChance then
		return nil
	end
	local list = V.SpecialOrder
	return list[math.clamp(math.floor(num(r2) * #list) + 1, 1, #list)]
end

-- Do paparazzi follow this ride (r: a random number 0..1)? A special with Paparazzi always.
function Businesses.PapRoll(r, special)
	local sp = special and Businesses.Vip.Specials[special]
	if sp and sp.Paparazzi then
		return true
	end
	return num(r) < Businesses.Vip.Pap.Chance
end

-- How many paparazzi cars come at the owner's level.
function Businesses.PapCars(level)
	return Businesses.Vip.Pap.Cars[Businesses.ClampLevel(level)] or 1
end

-- One check of a paparazzi chase: nearest = studs from the limo to the nearest paparazzi car (nil: none left), held =
-- seconds they've all been further than Pap.LoseDist so far. Returns the new held and whether they're lost now.
function Businesses.PapStep(nearest, held, dt)
	local P = Businesses.Vip.Pap
	if nearest == nil or num(nearest) > P.LoseDist then
		held = math.max(0, num(held)) + math.max(0, num(dt))
		return held, held >= P.LoseHold - 1e-9
	end
	return 0, false
end

-- Seconds left on a VIP booth or a cover pass (untilT, now: server time; 0 when over or not a number).
function Businesses.TimeLeft(untilT, now)
	if type(untilT) ~= "number" or type(now) ~= "number" or untilT ~= untilT then
		return 0
	end
	return math.max(0, untilT - now)
end

-- Is this world point inside the club's VIP booth (Club.Booth, from the club's Origin; up to 14 studs up)?
function Businesses.InBooth(pos)
	local CL = Businesses.Club
	if not pos then
		return false
	end
	local d = pos - CL.Origin
	return d.X >= CL.Booth.X0 and d.X <= CL.Booth.X1 and d.Z >= CL.Booth.Z0 and d.Z <= CL.Booth.Z1 and d.Y > -4 and d.Y < 14
end

-- Hours online to earn the price back on the trickle alone, at level 1 (averaged over day and night: the Nightclub's
-- night x2 counts for Businesses.NightShare of the time).
function Businesses.PaybackHours(def)
	return def.Price / Businesses.AvgTrickle(def, 1) / 60
end

-- A short price for tight labels: "$25k", "$1.2M".
function Businesses.ShortPrice(price)
	if price >= 1000000 then
		return string.format("$%gM", math.floor(price / 100000) / 10)
	end
	return string.format("$%dk", math.floor(price / 1000))
end

return Businesses
