# 6. Playtest the big update (Oct 19 pass)

None of this has been run in Roblox yet: it was written and checked outside Studio (type checks,
logic tests, five code reviews). Studio is where it gets proven. Go in order; the first section
tells you in two minutes whether everything loaded.

## Load it into Studio

1. Unzip over your project folder, then `python tools/manifest.py` (it should say 95 scripts).
2. `python -m http.server 34999 --bind 127.0.0.1` in that folder.
3. Studio command bar: `require(game.ServerStorage.Tools.DevSync).Run()`. Expect 10 NEW lines
   (CollectibleService, CollectibleClient, PropertyService, VehicleDamageService, ObjectiveClient,
   DistrictClient, Police, Properties, Collectibles, PedLines) and many UPD lines. Save (Ctrl+S).

## A. Smoke test (2 minutes)

Press Play. In Output (View > Output), check:
- `[Main] server ready` and **no** `[Main] ... failed to start` lines.
- `[CollectibleService] 40/40 Gus figurines placed` (a few "nudged" is fine; "no clear ground" means a
  spot needs moving: send me the line).
- No red errors from any script. Any warning starting with `[PropertyService]`, `[AIPolice]`,
  `[VehicleDamage]`, `[HeatService]`, `[EventService]`: send me the exact text.

Then type `/console` in chat and check the client side for red errors too.

## B. First five minutes (new player)

In Studio every Play starts with a fresh save, unless Game Settings > Security > "Enable Studio Access
to API Services" is on (then your real save carries over; turn it off for this test).
1. Pick CITIZEN. The top bar says "1/5 Get in your car" in readable text; the GPS routes to your car.
2. Get in: it moves to "Rob a store" and routes to Glow Mart, Fuel Stop or an ATM (never the bank).
3. Rob it: "WANTED!" stamp, 1 star. A police car comes from out of sight. Standing still in the
   first 25 s it can't arrest you.
4. Break line of sight: stars go hollow, the bar shows "LOSING THEM", a red ring on the minimap.
5. Bank at the Hideout: CLEAN GETAWAY; then "open your phone"; +$500 once.
6. Tap the ✕ once: it asks you to tap again (nothing skipped).

## C. Police chases

1. 1 star: one AI car; it brakes for corners (no crashing into buildings on every turn).
2. Hide: it drives to where it last saw you, then searches; you escape in under a minute.
3. 3 stars: two or three cars, not single file.
4. 4+ stars while seen: a roadblock (two flashing cars, spike strip in the gap) appears ahead within
   ~25 s; an X shows on the minimap.
5. Ram a police car on purpose: +1 star, "You rammed a police car!".
6. Press Reset while wanted: the button is disabled. Fall off the world while wanted: you're arrested.
7. With no heat: about 3 patrol cars cruise near you with no siren.
8. As a cop: TASER and SPIKES sit under the minimap on foot, SPIKES under EXIT in a car; none overlap.

## D. Cars

1. Hit a wall hard: crash sound, camera shake, a health bar above the speed gauge.
2. Keep crashing: smoke below 35, then STALLED (no gas for 4 s), then LIMP (~19 MPH).
3. Spray & Go with no heat: $250 repair. With heat: $500 respray + repair + one star off.
4. Burn nitro, hop out and back in: the bar stays low (no free refill).
5. Exit with your door against a wall: you come out the other side, never inside the wall.
6. Siren on, exit: the siren stops.
7. Another player rams you while you're innocent: you take no damage.

## E. Living city

1. Drive at pedestrians: they dodge or fade out. Nobody ever falls over or flies.
2. Get heat near pedestrians: they run and shout. Speech bubbles at most every few seconds.
3. Benches, bus stops, loungers have people sitting (check they don't float or sink).
4. Traffic: no cars popping in front of you; they stop for parked cars, honk if you block them,
   pull over for a siren behind them, and never drive through stunt ramps.
5. Drive between districts: a small title ("SOLANA HEIGHTS") for a couple of seconds.
6. Command bar (switched to Server): `require(game.ServerScriptService.Services.EventService).RunRandom("Flamingo")`
   (also "Performer", "BeachParty", "LostTourist", "BeachTreasure"): a toast for everyone, the event
   works, pays once.

## F. Money, missions, homes, Gus

1. Phone > JOBS: new missions (Hot Package, Glass Cargo...). Hot Package: 2 stars mid-mission,
   lose them, deliver, paid.
2. As a cop: only cop missions show; Beat Patrol pays cash and cop XP.
3. Race the same race twice: first pays full, the repeat 30% ("repeat" note).
4. Give yourself $30k (command bar switched to Server: `game.Players:GetPlayers()[1]:SetAttribute("Cash", 30000)`), go to the
   Rustwater Loft door (Phone > HOMES > SHOW ME): BUY, sign shows your name; reset: you respawn there.
5. Phone > GOALS: "Gus figurines 0/40" with a clue. Find one (green gator on a neon base): +$250,
   it disappears for you only.
6. Phone > FEED shows the Coast Feed history with an unread badge.

## G. Phone performance

On your phone (private publish): drive around downtown at night in rain for 5 minutes. Note the
frame rate and anything that stutters. Turn on SETTINGS > Performance mode and compare.

## What to send me

For anything that fails: the step letter/number, what you saw, and any red Output / `/console` text.
A screenshot helps for anything visual (overlaps, floating peds, placement of homes and figurines).
