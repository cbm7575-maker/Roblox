# 7. Playtest the gameplay update (Oct 30)

What changed: the F-key exit fix, Z / X fight keys, an always-on health bar, car-hit damage, police
officers on foot, HANDS UP, drivers and pedestrians reacting to a gun, store clerks, the Club Nova
drill, and the race update (lobbies, AI racers, positions, race challenges). Nothing was removed.

**None of this has been run in Roblox yet.** It was written and then read through by independent
reviewers, and their findings were fixed. Studio is where it gets proven. Do section A first: it
tells you in two minutes whether everything loaded.

## Load it into Studio

0. **Back up first.** In Studio, File > Save to File As... `TheftMiamiCoast-backup-oct30.rbxl`.
1. In the project folder, run `python tools/manifest.py`. It should say **138 scripts** (135 before).
   Don't skip this: without a fresh manifest, DevSync skips scripts it thinks are up to date.
2. `python -m http.server 34999 --bind 127.0.0.1` in that folder (skip if it's already running).
3. Studio command bar: `print(require(game.ServerStorage.Tools.DevSync).Run())`.
   - Expect 3 NEW lines: RobloxMenu (Shared.Util), PoliceOfficerService and RaceAIService
     (Services).
   - Many UPD lines are normal. Then save (Ctrl+S).

## A. Smoke test (2 minutes)

Press Play. In Output (View > Output):
- `[Main] server ready`, and **no** `failed to start` lines (look for PoliceOfficerService,
  AIPoliceService, HeistService, CombatService, ImpactService, RaceService).
- No red errors. Send me the exact text of any red error or `[...]` warning.

## B. Getting out of cars (the F bug)

1. Get in a car, drive, press **F**: you get out. Repeat with a jacked street car.
2. Play normally for 10-15 minutes (die once, use the phone, open the weapon wheel with Tab, press
   the **`** key and the **.** key once each, which open Roblox's own backpack and emote menus).
3. F still gets you out every time. If a press ever does nothing, **press F again**: the second
   press within 1.5 s always works. Then open the Developer Console (F9) and send me any line that
   starts with `[DriveController] the get-out key did nothing`.
4. Note: in Studio, clicking the Output or Explorer panel takes the keyboard away from the game.
   Click the game view before testing keys.

## C. Fight keys (no mouse needed)

With empty hands:
1. Walk up to a pedestrian and press **X**: you punch (the Fists come out by themselves). Click the
   left mouse button with empty hands: also a punch.
2. Press **Z** with no gun: "No gun to aim yet" toast.

With a gun (buy the pistol at Coast Arms, PHONE > GPS):
3. Put it away, then hold **Z**: the gun comes out and aims.
4. Hold Z near a pedestrian: the view swings onto them and stays on them as they move. Press **X**
   to shoot. Don't touch the mouse.
5. Tap Z quickly: aim stays on. Tap again: off.
6. While locked on, move the mouse or press the left / right arrow keys: the lock lets go.
7. Right mouse and left mouse still aim and fire as before. Gamepad L2 / R2 and the phone's
   AIM / FIRE buttons still work.

## D. Health and car damage

1. The HEALTH bar (under the minimap) is always on screen, even at full health with empty hands.
2. Stand in a street and let a traffic car hit you: a small loss (about 10-25).
3. Two players (Test tab > Clients and Servers, 2 players). Player1 drives into Player2:
   - slowly (under about 12 mph on the gauge): no damage (a bump at a crawl doesn't even knock them
     over);
   - at 25-40 mph: a moderate hit (about 25-40);
   - at 75+ mph: a big chunk (up to 85, never a kill from full health in one hit);
   - drive over Player2 again while they're down: more damage. Two hard hits kill: YOU DIED,
     "Run over by Player1".
4. In a safe zone (spawn, shop) or with PASSIVE on: knock-down only, no damage.

## E. Police on foot

Get 1 star (punch two pedestrians, or rob a store) and wait for the patrol car (20 s at 1 star).
1. **Stand still, unarmed.** The patrol pulls up, an officer in a navy uniform with POLICE on his
   back gets out, runs up ("POLICE! HANDS UP!") and cuffs you after about 2 seconds: prison.
2. **Hands up.** Get a star again. When the patrol is near, the **HANDS UP** tile appears (side
   column). Press **H** (or tap it). Your hands go up and you can't walk. The officer walks up and
   cuffs you in about a second. CUFFED says "You came quietly: a shorter sentence".
3. **Run.** Sprint away on foot: the officer chases, a little slower than your sprint. Get far
   enough and he goes back to his car, and the car chases you.
4. **Drive off.** Get in a car while he's out: he runs back, gets in, and the chase continues.
5. **Shootout.** Get 2 stars, take a gun out near the officer: "DROP THE WEAPON!" At 2+ stars with a
   gun out (or right after you fire), he draws and shoots (tracers, damage). Shoot him: he goes down.
   That adds stars. If they kill you with police right there, you are arrested on the spot.
6. **Hands up after shooting.** Fire at him, then press H: he still shoots (hands up is no shield
   right after an attack). Press H, then pull a gun out: your hands come down.
7. **3+ stars**: two officers per car.
8. **Punch an officer** 3 times: he falls, gets up after 5 seconds.

With two players (one goes on duty in PHONE > JOBS): the cop's Service Pistol works on a 1-star
suspect who has a gun out. The cop can cuff (Q) a suspect who has their hands up.

## F. Guns and NPCs

1. Aim a gun at a traffic car stopped at a light (or stand in front of one so it stops). After about a
   second the driver gets out with their hands up ("DON'T SHOOT!") and runs. Walk to the car and press
   **F**: it's yours (1 star, as for any carjack).
2. Aim at pedestrians: most put their hands up, some crouch and cover their heads, others run.

## G. Store robberies

1. Go to Glow Mart or Fuel Stop (GPS > HEISTS shows which are open). A **clerk** stands behind the
   counter. With a gun you'll see a toast: "Point your gun at the clerk to rob the store".
2. Aim at the clerk (Z or right mouse). They put their hands up, "Okay, okay! Don't shoot!", and the
   rob bar fills for 6 seconds. Stay in the store. ROBBERY COMPLETE, with 25% more than the till.
3. Walk out halfway: "You walked out: the clerk ducked behind the counter." No money.
4. Shoot or punch the clerk: they go down (a star). A new clerk is there 20 seconds later.
5. Without a gun (sell or never buy one, e.g. a new player): the till's Rob prompt still works.
6. **Club Nova**: hold "Set the drill" (3 s), the alarm goes off, stay in the room for 25 s
   ("Drilling 0:18" on the prompt), then hold "Grab the cash" (3 s). Leave the room for 5+ s while it
   drills: it jams.

## H. Racing

One player:
1. Stop your car on the Ocean Drive Sprint pad and press **E** (Race). A banner counts down from 6
   (12 when other players are near), then you line up with 3 named AI racers, 3-2-1, GO. **POS x/4**
   shows during the race.
2. Finish. The card says your place; the pay goes by place (1st full, 2nd 60%, 3rd 35%, else 15%);
   RESULTS lists everyone, AI racers too.
3. Highway 1 Loop is now 2 laps: LAP 1/2, "Final lap!", checkpoints start over each lap. (It pays
   more now, $2,000 + $1,600 under par, and its best times are kept apart from the old 1-lap ones.)
4. Surf Sprint (boats): no AI racers, no POS: the same time trial as before.
5. Race a few times: about one race in three, "the cops spotted the race" and every racer gets a
   star. The race carries on; lose the cops after.
6. Get out of the car mid-race: cancelled with a toast; the AI cars are gone within about 20 s.

Two players (Test tab > Clients and Servers, 2 players):
7. Player1 presses Race on a pad. Player2, within 150 studs, sees "press Race to join", drives onto
   the pad and presses E. They start side by side with 2 AI racers; positions update live for both.
8. Drive side by side anywhere: a **CHALLENGE** button appears (key **K**, gamepad R3). Press it.
   Player2 gets a card: ACCEPT / DECLINE.
   - Decline (or no answer in 15 s): Player1 is told; challenging Player2 again within 60 s is refused.
   - Line up side by side first: if one car is more than about 30 studs ahead, accepting says "Line
     up side by side first".
   - Accept: both cars freeze where they are, a route of 1,000-1,600 studs is drawn, 3-2-1, GO. The
     first to the finish gets YOU WIN; when the other finishes, both see the times, the gap and
     REMATCH. No money, no police for these.
9. In a challenge, get out of the car (or get a star): it's off for both.
10. Leave the game in the lobby and mid-race: no car is left frozen.

## What to send me

For anything that fails: the section and step (e.g. E2), what you saw, any red Output or F9 console
text, and a screenshot for anything visual (an officer stuck in a car door, a clerk floating or inside
the counter, a gun sitting wrong in an officer's hand).
