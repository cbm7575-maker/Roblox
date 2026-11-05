# 11. Coast Guard (Nov 4)

What's new:
- **The sea is no longer a free escape.** If you're wanted and you get in a boat, or swim out where the water is deep, **Coast Guard boats** come after you and can arrest you.
- **Before:** the moment you sat in a boat, every police car disappeared and nothing replaced it.
- **Also fixed:** driving a boat up onto the sand and sitting in it used to keep every patrol away too. Now patrol cars come for it, and their officers cuff you.

Nothing was removed. Patrol cars on land work as before, and player cops still have the Harbor Patrol boat.

## How it works

- **Who:** a wanted citizen sitting in a boat that's floating, or swimming in the sea where it's at least 8 studs deep.
  - The prison moat is too shallow, so a swimmer there still gets patrol cars, as before.
- **How many:** the same number as patrol cars would be, after the same head start:
  - 1 boat at 1-2 stars (only when no player cops are on).
  - At 3+ stars, one fewer boat than your stars (3 at most).
  - No AI boats while 2+ player cops are patrolling.
- **What they look like:** the white Harbor Patrol police boat, with a siren, flashing lights and an officer aboard (two from 3 stars). They show on the minimap like patrol cars.
- **Where they come from:** open, deep water 350-600 studs away, never under a pier.
- **Speed:** they're capped at 95% of your boat's top speed, the same rule as the cars. A boat at full throttle can't be caught, but it can't get out of sight easily on open water either.
- **Getting arrested:**
  - In a boat: stop, or go under about 12 studs/s, within 36 studs of a Coast Guard boat for 3 seconds. You see the BEING CUFFED bar with "DRIVE to break free".
  - Swimming: being within 36 studs of one for 3 seconds is enough. A toast says "The Coast Guard is pulling you out of the water!"
- **Escaping:** head for land. Once you're ashore, they wait offshore for 10 seconds, still watching, then leave. Patrol cars take over on land.
- **Toast** (once per chase): "Coast Guard on the way! Their boats chase you on the water: head for land to lose them."

## Tested

Offline: compile, lint, and `tools/logic-tests/coastguard.sh` (34 checks, all PASS).

**Studio, Nov 4 evening**, in a scratch copy of the v8 place:
- Only the Coast Guard scripts were loaded, and saving was off (memory only).
- A test script played the scenarios itself, and the results come from the server log.
- The jet ski was driven by the server, not by keys.

| Check | Result |
|---|---|
| Boat at sea, 2 stars | The head-start countdown showed. Then one Coast Guard boat appeared 513-576 studs off on deep, open water, with an officer aboard and its red blip on the minimap. |
| Circling at full speed (107 studs/s) for 35 s | It held about 111 studs behind at 101 studs/s and never arrested. The cuff bar never showed. The HUD said "SEEN – BREAK LINE OF SIGHT". |
| Stopping at sea | It pulled up 15 studs away within 2 s. The BEING CUFFED bar filled (0.2 → 0.55 → 0.9) and then came the arrest. The boat left after it. |
| Swimming far out | It came right alongside (about 7 studs) and arrested the swimmer. No cuff bar, as intended. |
| Going ashore | The boat stopped, waited 10.8 s offshore, then left. A patrol car came 2 s after the player reached land. |
| Boat run up on the sand | A patrol car came after the head start, an officer got out, and the driver was arrested. No Coast Guard boat came. |
| 4 stars at sea | Three boats, two officers each, held a column about 100 studs behind a 108 studs/s jet ski for 35 s. None rammed or flipped. Average frame 17-23 ms. |
| Errors | None in any run. |

Not checked in Studio yet:
- Weaving in and out of the marina piers with a boat chasing. It should back off and turn if it gets stuck, and go if it stays stuck.
- Two player cops on duty: no AI boats should come. The logic test covers this.
- The officer's seat on the boat up close. It looked fine from the chase camera.

**Not live.** It goes live only when the owner says so: play test, then File > Publish (see 9-RIDE-AND-MAP.md for the steps).
