# Empire M5: the Afterglow Nightclub — Studio test guide

**Status (Nov 5, 2026):** built locally, not committed, not published. Nothing here is live: the whole feature stays off in live servers until `Config.Businesses.Live = true` (owner's go-ahead only). In Studio it always runs.
**Source of truth:** `launch/10-BUSINESSES-PRD.md` (v2, sections 4-6, 9, 11, 14 and 20). The fun rules are in `launch/18-BUSINESS-FUN-PASS.md`. The M1-M4 guides are `launch/12-`, `15-`, `17-` and `19-BUSINESS-M*-TEST.md`.

---

## 1. What M5 contains

| Piece | Where |
|---|---|
| Every number and place: the Nightclub entry, `NightShare`, `Vip` (the limo, pickups, comfort, pay, paparazzi, specials), `Club`, `BackRoom`, and the maths (`VipPay`, `VipComfort`, `VipStop`, `PapStep`, `BackRoomAccrue`, `AvgTrickle`, `NightNow`...) | `src/shared/Config/Businesses.lua` |
| The club on the boardwalk (levels 1-5), VIP PICKUPS (the limo, the VIP, paparazzi, the red carpet), the club's inside (cover charge, VIP booth), the back room (WASH, raids) | `src/server/Services/BusinessJobs/Nightclub.lua` (new) |
| The police raid code, moved out of the Print Shop unchanged so the back room can use it too | `src/server/Services/BusinessJobs/Raids.lua` (new); `PrintShop.lua` now calls it |
| Night ×2 on the register, `Api.isNight` / `featuredOf`, the booth's words in the customer path, RequestBusiness "Mod" (LEAVE) | `src/server/Services/BusinessService.lua` |
| The VIP HUD (strip, comfort, the VIP mark, PAPARAZZI / LOST THEM, the red-carpet stamp, NEXT VIP), the club (LEAVE, the dance floor lights, no rain indoors), the back room on the card and the phone, the raid words for the club | `src/client/Controllers/BusinessClient.lua` |
| The club's inside is a safe zone (3 lines in `isSafe`) | `src/server/Services/CombatService.lua` (shared) |
| Offline maths tests (9 new scenarios) | `tools/logic-tests/businesses.sh` |

**Where it is.** On the beach side of the boardwalk, across Highway 1 from downtown, facing west. World box x 1125..1175, z 327..383 (checked against the place file: nothing inside; the boardwalk's palm row is 9 studs in front, non-colliding; Club Nova, the heist, is 426 studs south). The highway is 95 studs away: the limo drives across the sand and the boardwalk.

## 2. Studio helpers (Studio only)

Run them in the **server** Command Bar through DebugService's `NCCmd` door, as before. Read the answer with `print(workspace:GetAttribute("NCResult"))`. `"$me"` is the first player; use `"Player2"` for the second.

| What | Command |
|---|---|
| Test cash | `workspace:SetAttribute("NCCmd", '["cash","$me",900000]')` |
| **Set your Empire rank** (1-10) | `workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","rank","",3]')` |
| Own the Nightclub free (skips the rank gate) | `... "Debug","$me","give","Nightclub"]` |
| Its level (1-5) | `... "Debug","$me","level","Nightclub",3]` |
| **Night on / off** for the businesses (or `""` to follow the clock) | `... "Debug","$me","night","","on"]` |
| **Force your next VIP's special** | `... "Debug","$me","celeb","","Superstar"]` (or `"Tabloid"`, `"Late"`; `""` clears it) |
| **Paparazzi** on your next ride (on a ride now: at once) | `... "Debug","$me","papz"]` |
| Your next pickup's place | `... "Debug","$me","pickup","","VILLA"]` (`MANSION`, `PENTHOUSE`, `TOWER`, `HOTEL`) |
| The VIP's comfort now (0-1) | `... "Debug","$me","comfort","",0.5]` |
| **Fill the back room** (or a value) | `... "Debug","$me","backroom","Nightclub"]` / `... "backroom","Nightclub",5000]` |
| WASH again now (skip the 5 minutes) | `... "Debug","$me","washready"]` |
| **A raid on the back room** (`"ai"` for the AI raid, or seconds) | `... "Debug","$me","raid","Nightclub","ai"]`; end it: `... "endraid","Nightclub"]` |
| Into / out of the club free | `... "Debug","$me","club","","in"]` / `... "club","","out"]` |
| The VIP booth's time left (seconds) | `... "Debug","$me","booth","",70]` |
| A break-in at the club's till | `... "Debug","$me","breakin","Nightclub",120]` |
| Summary | `... "Debug","$me","state"]` |
| Time scale (register, back room, break-ins, a new booth) | `workspace:SetAttribute("BusinessTimeScale", 60)` (set it back to 1) |
| A player cop for raids | `... "Debug","$me","testcop","","Player2"]` |
| Crewmates | `workspace:SetAttribute("BizTestCrew", true)` |
| Phone layout (client bar) | `game.Players.LocalPlayer:SetAttribute("PreviewTouch", true)` |

## 3. One player: the unlock, the building, the levels

1. **The Empire 3 gate.**
   - `rank 2`, walk to the club's doors. The bubble reads "View / Buy $250,000". The buy card's button says **EMPIRE 3 NEEDED**, the note "Needs Empire rank 3 (you're 2)". The blurb says the register is "×2 at night".
   - PHONE > EMPIRE lists it under FOR SALE as "Unlocks at Empire 3 (you're 2)".
   - `rank 3` and the cash: **BUY $250,000**. The YOU OWN IT stamp, the gold ring on the minimap's pink **V**.
2. **Map.** A pink **V** on the beach by the boardwalk, north of Club Nova, on the minimap and the big map. GPS leads there.
3. **The club at level 1** (check by day and at night: `night on`):
   - the charcoal club with black glass, the AFTERGLOW sign on the roof, the marquee with the plate "FOR SALE · $250,000" (or yours), brass door frames;
   - after dark: a pink neon line along the roof and round the doors, the VIP mark's centre line;
   - the red carpet from the doors to the lot's edge with velvet ropes; the pink **VIP** box beside it, the white **LIMO** box and its sign on the other side;
   - the bouncer and his rope, the COVER $50 sign; three photographers behind a rope; palms at the corners;
   - inside: the lobby (ticket counter with the till, a small bar with stools and bottles, the DANCE FLOOR doors), the back room through the door marked PRIVATE (card table, chips, the safe with THE TILLS sign);
   - Output has no "the Afterglow Nightclub lot overlaps" warning.
4. **Levels.** `level` 2..5 (the props show only on your device):
   - **L2:** pink, cyan and violet panels glowing behind the front glass, uplights on the facade (after dark);
   - **L3:** the DJ booth with speakers on the marquee, two searchlight beams on the roof, neon round the AFTERGLOW sign;
   - **L4:** the VIP balcony wings with glass rails, lounge chairs and a VIP sign;
   - **L5:** the rooftop pool, loungers, palms, string lights, three party people, ROOFTOP POOL PARTY.

## 4. VIP pickups

1. **START JOB > VIP PICKUPS** (level 1).
   - The limo appears in the LIMO box and you're put at the wheel. If not: **GET IN THE LIMO** with the distance; only you see its "Drive" bubble.
   - A toast explains the job. The strip: **PICK UP STELLA STARR · THE VILLA** (or another) with the distance; a gold ring and beam at the pickup; the GPS.
2. **The pickup.** Drive there (across the sand and the boardwalk to the highway). The VIP waits there with sunglasses and a gold ★ name ★ tag. Stop in the ring: they walk to the passenger door and get in (everyone sees them sitting there).
   - **VIP ABOARD!**, a door and a honk, what they said ("Drive smooth. I just did my hair."). The strip: **TO THE RED CARPET** with the distance, the GPS back, and at the club a pink ring with a gold dot (the VIP mark).
   - The line under the strip: **COMFORT 100%**, PAR 0:38, NIGHT ×1.25 at night, the streak.
3. **Comfort.** Throw it round a corner at speed: COMFORT drops (orange under 80%, red under 50%), the line shakes, the VIP complains in a bubble ("Easy on the turns!"). Crash into something: a crash sound and "OW! My tiara!". A jump: "Did we just FLY?!". Calm driving brings it back slowly.
4. **Paparazzi** (`papz`, then a pickup; or about 3 rides in 10):
   - 3 s after the VIP gets in: a toast **PAPARAZZI!** and a beep; one (level 3+: two) dark SUVs with PAPARAZZI over the roof appear behind you and chase you.
   - The strip: **LOSE THE PAPARAZZI!** with the nearest one's distance; the sub line PAPARAZZI!
   - Close by, their headlight-height flash blinks (camera flashes) and the comfort drains; the VIP shouts "No photos!".
   - Get 230+ studs from all of them for 3 s: the **LOST THEM!** stamp and the "everything works out" sting. They brake and vanish a few seconds later.
   - Still on your tail at the club: no bonus, a toast "The paparazzi got their shots at the door".
5. **The red carpet.** Near the club the strip says **STOP ON THE VIP MARK**. Stop in the pink ring (16 studs): the stamp **★★★ RED CARPET** / ★★ / ★ with PERFECT / GOOD / OK STOP, the tip, "lost them +$250", "night ×1.25", the streak; the screen flashes 4 times, the press's flashes go off at the carpet (everyone sees), the pay counts up, confetti on ★★★. The VIP steps out, walks the carpet ("Fabulous ride!") and fades at the doors.
   - Then the AFTER panel: "+$X ★★☆" and what was missing ("for ★★★: faster, a smoother ride, stop on the gold dot"), **NEXT VIP | END**.
6. **NEXT VIP** → a new VIP somewhere else; you stay at the wheel. Get out first and NEXT VIP: you're seated again if you're within 40 studs.
7. **The streak.** Two ★★★ in a row: "★★★ streak ×2: tips ×1.1!", STREAK ×2 on the line. A ★★ ends it.
8. **Specials** (`celeb`):
   - `Superstar`: a gold toast "A SUPERSTAR tonight", a sparkle on the VIP, SUPERSTAR on the line; ★★★ tips ×3.
   - `Tabloid`: paparazzi always come; losing them pays ×2.
   - `Late`: a tighter par; the tip ×2.
9. **Night** (`night on` / `night off`): NIGHT ×1.25 on the line and the stamp; the pay is 25% higher.
10. **The endings** (the limo, the VIP and the paparazzi always go). Check each:
    - END JOB (on the way and at the club) → the SHIFT REPORT: VIPs, ★★★, best streak, PERFECT stops, % comfort, paparazzi lost x / y, night pickups, specials.
    - Get out on a ride and walk away for 15 s → "Job over: you left the club's limo."
    - Get wanted (`["heat","$me",1]`) → "Job over: you're wanted."
    - Wait 3 minutes at the club without NEXT VIP → "Shift over: no VIP picked up for a while."
    - The limo can't be taken to the Chop Shop, raced, used for a taxi fare or kept.
11. **Break-in.** `breakin Nightclub 120`: 1-2 robbers at the ticket counter's till in the lobby; scare or punch them; they run out of the doors onto the forecourt.

## 5. The club (cover charge, the inside, the VIP booth)

1. **Cover charge** (as P2, or as yourself with `remove` first): at the velvet rope the bubble reads **Cover charge $50**. Press it: you pay $50, the screen fades and you're in the club's entrance, facing the dance floor. A toast "Welcome to Afterglow! ... back in free for 30 minutes".
   - As the owner (or a crewmate of one): the bubble reads **Enter the club (free)**; no charge.
   - With a pass: **Enter the club (paid)**; no charge.
2. **Inside.** Check:
   - the hall (dark walls, pink/violet/cyan washes and strips), the music (Neon FM) playing, a few dancers;
   - level 1: a plain wood dance floor; level 2+: the floor's 30 tiles flashing pink/cyan/violet/gold in time on your device;
   - the GLOW BAR with the bartender and the bottle wall; the sound system; level 3: the DJ stage with DJ MARLO and the lasers; level 4: the VIP balcony over the entrance; level 5: the pool corner with the flamingo;
   - the strip says **AFTERGLOW · DANCE FLOOR**; the END JOB tile reads **LEAVE**;
   - no rain inside during a storm (`workspace:SetAttribute("NCCmd", '["rain",true]')`; `'["rain",null]'` puts the weather back);
   - no fighting: the SAFE pill shows, punches do nothing.
3. **Leaving:** the EXIT door's "Leave the club" bubble, or LEAVE: fade, and you're back on the carpet outside the doors.
4. **Wanted inside** (`["heat","$me",1]`): the bouncers put you out ("you're wanted").
5. **Respawn inside** (reset): you spawn normally; the club forgets you (the strip line goes).
6. **The club goes away**: leave, wait 60 s, check Workspace: `BizClubInterior` is gone. Come back in: it's built again.
7. **VIP booth** (at the booth's rope inside, west side): the bubble **VIP booth $250**. Press it: -$250 ("On the house" for the owner), a toast, the booth's sign reads **RESERVED · YOUR NAME'S CREW**, the champagne bucket sparkles, the strip shows **YOUR VIP BOOTH 14:59**.
   - P2 (not your crew) walks into the booth: shown out to the dance floor, "That booth is reserved. VIPs only!". P2 sits on a booth seat: stood up.
   - P2 presses the booth bubble: "Another party has the VIP booth right now."
   - `booth 70`: at 1:00 a toast; at 0 "Your VIP booth time is up"; the sign goes back to VIP BOOTH.

## 6. The back room and its raids

1. **The card game.** Own it, `night on`, `BusinessTimeScale 60`: the manage card's second line "Back room $x / $8,000 · WASH up to $2,500 at the safe" grows; by day (`night off`) it doesn't.
2. **WASH.** `backroom Nightclub 5000`, walk through PRIVATE to the safe: the bubble **Wash the take** (hold 4 s). Only the owner sees it. You get $2,500, the WASHED stamp and the count-up, "$2,500 still in the safe". Hold it again at once: "The tills can only hide so much at once: WASH again in 4:59." (`washready` skips that.)
3. **An AI raid** (`raid Nightclub ai`): the toast "Police are on their way to your Afterglow back room! Hold the door ..., or WASH the cash out at the safe.", the siren, the V flashing red, the strip **RAID! GET TO YOUR CLUB** and the clock.
   - A police car pulls up on the forecourt (right side); two officers walk in through the front doors to the back-room door.
   - Stay inside the club building (lobby or back room): HOLD THE DOOR!; they wait and shout "Open the door! Police!".
   - Walk out: COPS BREAKING IN 40%...; after the breach they walk through the back door to the safe ("We're in! Check the safe!"); the search takes half the back room's cash: the RAIDED stamp. The register is untouched.
   - Hold the door for a minute until the warrant runs out: RAID FAILED, $1,000 and Empire XP.
4. **A player-cop raid** (2 players, `testcop Player2`, then `raid Nightclub`): P2 gets the dispatch; P2's BREACH bubble is at the back-room door inside the lobby, then SEARCH at the safe; P2 gets SEIZED $X with the reward.
5. **The Print Shop still raids as before** (`raid` with no id, `raid PrintShop ai`): the same words as M3 (the presses, the Print Shop). Its logic tests pass unchanged.

## 7. Two players (Test > Clients and Servers, 2 players)

1. **Featured owner.** P1 owns it at level 4; P2 sees "Player1's Afterglow" on the plate and the level 4 props.
2. **Customer split.** P2 pays the cover: P1 gets "Player2 got a cover charge at your Nightclub +$35". P2 books the booth: "Player2 got a VIP booth at your Nightclub +$175". Empire XP twice an hour at most from P2.
3. **Crew.** `BizTestCrew` true: P2 walks into the club free, may use P1's booth, gets the BoothCrew toast, runs VIP PICKUPS for P1 (P1 gets the crew cut), and holds the door with P1 in a raid.
4. **Everyone sees:** the VIP waiting and riding in the limo, the paparazzi SUVs, the press's flashes at the carpet, the VIP walking in.

## 8. Fun and feel (check by hand: offline tests can't)

**THE LOOP**
- One VIP should take ~70-90 s. Time five. If much faster than ~45 studs/s on average, the pay per stud is too high: tune `Vip.PerStud` (and see the numbers).
- The 5th VIP still feels good: new names, new places, paparazzi now and then, a special 1 in 8, the streak.

**COMFORT**
- Ordinary city driving (corners at 30-40 studs/s) shouldn't drain it; a handbrake turn at 100 should. If it drains on every corner, raise `Comfort.TurnLimit` (70); if it never moves, lower it.
- Kerb hops shouldn't count as jumps. If they do, raise `Comfort.AirSpeed` (28).

**PAPARAZZI**
- They should keep up with a careful driver and lose to a fast one. If they're never lost, lower `Pap.Top` (115) or `LoseDist` (230); if they're never a threat, raise `Top`.
- They must not ram you. If they do, raise `Pap.Near` (40).
- They appear behind you, on a road, not in a wall.

**THE RED CARPET**
- Is PERFECT (within 3 studs of the mark's middle) reachable about 1 time in 2 with a little care? If never, widen `Vip.Stop.Perfect`.
- The flashes and the stamp are satisfying, not blinding, and don't hide the AFTER panel on a phone.

**PERFORMANCE**
- On a phone: no hitch when the limo appears, when the paparazzi spawn, when you enter the club (it's ~300 parts and 6 dancers), or at the carpet flashes.

## 9. Phone layout (PreviewTouch)

- The strip, the line under it (COMFORT, PAR, PAPARAZZI) stack in the Banner zone without overlapping.
- The AFTER panel (NEXT VIP | END) sits low and a little right of centre, clear of the thumbstick.
- LEAVE (in the club) sits in the side column like END JOB.
- The SHIFT REPORT is centred and fits (3 lines).

## 10. The numbers (Config.Businesses)

| | Level 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Trickle by day ($/min online) | 375 | 500 | 625 | 750 | 875 |
| Trickle at night (×2) | 750 | 1,000 | 1,250 | 1,500 | 1,750 |
| Register size | $20,000 | $33,750 | $47,500 | $61,250 | $75,000 |
| Fills (average / by day / at night) | 37 / 53 / 27 min | 47 / 68 / 34 | 53 / 76 / 38 | 57 / 82 / 41 | 60 / 86 / 43 |
| Job pay multiplier | 1.00 | 1.06 | 1.12 | 1.18 | 1.25 |
| Upgrade price (to this level) | — | $100,000 | $150,000 | $200,000 | $250,000 |
| Paparazzi cars | 1 | 1 | 2 | 2 | 2 |
| Back room: night rate / safe / one WASH | $80 / $8,000 / $2,500 | $95 / $9,500 / $2,800 | $110 / $11,000 / $3,100 | $125 / $12,500 / $3,400 | $140 / $14,000 / $3,700 |

- **Night:** 42.4% of the game's 14-minute day (from WorldService: night from 18:24 to 5:36). The trickle averaged over day and night is ~$534 a minute at level 1: the $250,000 back in **~7.8 h** online (it was ~16.3 h on the PRD's first $180 → $420). Price + every upgrade at level 5 in ~12.7 h.
- **VIP pay** (level 1, × JobMult and RateScale): $345 + 38.5¢ a stud of road both ways, paid whatever happens; a tip of up to 30% of that from three equal shares: the time (full inside par, gone at 1.5× par), the comfort (0 at 20%, full at 100%), the stop (PERFECT 1, GOOD 0.6, OK 0.25). Par = 6 s + the road back ÷ 42. ★★★ in a row ×1.1 → ×1.3; night ×1.25 on pay and tip; losing the paparazzi $250 (Tabloid ×2); Superstar ×3 tip on ★★★, Late tip ×2 with par ×0.8.
- **The calibration** (the seeded simulation in the logic tests): **~$1,500 a minute of work at level 1** for a typical player (~45 studs/s, 45% PERFECT stops, comfort ending 55-100%, the paparazzi lost half the time, night as often as the game has it). ~$1,407 careless, ~$1,607 smooth at the same speed; ~$1,190 slow, ~$1,754 fast. ~13% of arrivals are ★★★. The streak, the specials and the paparazzi bonus are inside the average (~2%); night pay lifts it ~10% over a day-only average.
- **Speed check:** every leg against the limo's nitro top speed × 1.15, and VehicleGuard (as a taxi fare).
- **Empire XP:** 12 a VIP (~9 a minute of work); 10 a WASH; the cover and the booth give the owner customer XP (twice an hour per buyer).
- **Services:** cover $50 → $35 to the featured owner, $15 sink; booth $250 → $175 and $75; a booth lasts 15 minutes, a cover pass 30.
- **Rank 3** is 900 Empire XP: the Car Wash to level 3, the café and ~45 minutes of business jobs get there (~1-1.5 h of business play), or ~80 minutes of jobs with only the Car Wash.

## 11. Not verified offline (check these in Studio)

- **The club has never been seen.** Its walls, glass, signs' faces (they should face the boardwalk), the marquee, the ropes, the people figures (facing the street), the VIP and LIMO boxes on the concrete.
- **The drive to the highway:** across the sand, the boardwalk planks and between the palms. Check nothing blocks the limo (the billboard legs and street lights near x 1033-1054 are solid; the lot was picked where the way out is open at z ~340-365).
- **The limo:** the Silver Egret body painted black, its seats (the VIP in the passenger seat, heads under the roof), the pink underglow and the AFTERGLOW roof light (level 3+), gold trim (level 5).
- **The VIP's walk** to the passenger door (CarBuilder's PassengerDoor attachment) and out onto the carpet, then up it and fading at the doors.
- **The pickup rings** at the three homes' verge spots and the apartment towers' kerbs (a tower too far from a road is skipped). Try `pickup` with each.
- **Paparazzi** spawn on a road behind you (RaceAIService with `Car`/`Paint`/`Route`, the robber bots' additions). If RaceAIService ever loses `Route`, paparazzi simply never come.
- **The comfort's turn and jump limits** on real driving (see FUN AND FEEL).
- **The club's inside:** its light level (it's lit only by its own lights), the music's volume (`Club.MusicVolume`), the dancers' stock dance animations, the booth seats facing the room.
- **The minimap and big map** while you're inside the club (far off the map): your arrow and a crewmate's dot may sit at the edge.
- **Lightning flashes and thunder** may still show inside the club during a storm (SkyClient and SoundClient only skip them in homes). Rain is switched off.
- **Saving:** `data.businesses.Nightclub` (level, register, the back room's `dirty`) only persists with Studio API access or in a private live test.

## 12. Shared files changed

- `src/server/Services/CombatService.lua`: 3 lines in `isSafe` (after the InHome / Prisoner check): a player with attribute `BizClub` (inside the club) is safe.
- Nothing else outside the business files. `PrintShop.lua`'s raid code moved into `BusinessJobs/Raids.lua` (a business file), unchanged; the Print Shop's logic tests pass. VehicleService (`SeatNPC`, `ReleaseNPC`, `EjectAll`), VehicleGuard (`Allow`, `RecentlyFlagged`), RaceAIService (`Spawn`, `Plan`, `Route`, `Release`, `Done`, `Position`, `Remove`), CarBuilder (`Build`, `PlayPose`), JobService (`RoadsideSpot`), ApartmentService (`Towers`), RoadGraph, HouseClient's `HouseFade` remote and Config.Sounds' radio tracks are only called or read.

## 13. Studio test, Nov 5 2026 (one player, PC and the iPhone 7 simulator, scratch copy of the place)

**What worked:**
- **The building** at night: pink and blue neon, the limo bay and the red carpet.
- **VIP PICKUPS:**
  - The limo spawns in its bay with you at the wheel. The strip reads "NIGHT ×1.25 · PICK UP <VIP>" with the distance.
  - At the VIP the celebrity gets in and says their line ("Drive smooth. I just did my hair.").
  - Then the strip reads "COMFORT 100% · PAR 0:40 · TO THE RED CARPET".
- **Comfort:** a crash into a wall dropped it to 85% and the VIP shouted ("OW! My tiara!").
- **The red carpet:** a stop on the carpet paid **+$2,365 ★★** with "for ★★★: faster" and the NEXT VIP | END panel.
- **The shift report** after END: VIPs, PERFECT stops, comfort, night pickups and +12 Empire XP.
- **The anti-cheat:** jumping the limo to the VIP in 4 s was refused ("at least 6.56 s"), which ended the run as designed.
- **The club inside:**
  - THE GLOW BAR, the lit dance floor, the "BACK TO THE BOARDWALK" exit, the LEAVE tile and SAFE ZONE.
  - Leaving puts you back at the club door.
- **No server errors** came from any business code.

**Found and fixed:**
- The GPS readout (for example "ATM #2 760 m", or "4.8 km" inside the club) showed faintly through the job strip in every business job.
- GPSClient now gives way to the strip (`BANNER_OWNERS` gets `{ "Business", "Strip" }`), as it already does for missions and taxi shifts.

**Still to see:**
- **Paparazzi.** They were set to come but the ride was cut short.
- **The cover charge and VIP booth bought by a second player.**
- **Back-room raids.**
- **The exit route:** a street-light pole sits in the lane west of the club, and a limo driven straight out of the bay hits it. Steering around it works. Moving the bay or the pole would make the exit cleaner.

## 14. Two-player Studio test, Nov 5 2026 (afternoon)

**Cover charge:** Player2 paid $50 at the bouncer and walked into the club. Player1, the featured owner, got $35 (70%). The club strip showed with no GPS readout behind it, so the GPSClient fix works.

**VIP booth:**
- The rope's prompt read "VIP booth $250 · 15 minutes · you and your crew".
- Booking it showed "The VIP booth is yours and your crew's for 14:59! (-$250)" and a "YOUR VIP BOOTH" timer.
- Player1 got $175 (70%).

**Paparazzi (scripted ride with legal waits):**
- One paparazzi SUV appeared 3 s after the VIP (DJ Marlo) got in and closed to ~30 studs.
- The strip read "PAPARAZZI · LOSE THE PAPARAZZI!!", and the camera flashes drained comfort (100% → ~37% while standing still next to them).
- After the limo got 1,100+ studs away, the SUV drove off after the hold.
- The red carpet showed the "★ RED CARPET" stamp and paid $2,397 ★★ ("for ★★★: faster, a smoother ride"), with NIGHT ×1.25.

**Test-only note:** jumping the limo next to a VIP standing by a wall destroyed it ("Job over: the limo is gone"). That was the shortcut's placement, not the game; with a clear spot it worked.
