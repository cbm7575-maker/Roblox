# 6. Playtest this update (Oct 25: free roam, houses, guns, your fixes)

None of this has been run in Roblox yet. It was written and checked outside Studio: type checks, four
code reviews, and the houses and gun store built in a stand-in for Roblox and rendered. Studio is
where it gets proven. Go in order: section A tells you in two minutes whether everything loaded.

## Load it into Studio

0. **Back up first.** In Studio, File > Save to File As... `NeonCoast-backup.rbxl`. The sync replaces
   every script that differs from these files.
1. Unzip over your project folder, then run `python tools/manifest.py`. It should say **108
   scripts**. Don't skip this: without a fresh manifest, DevSync skips scripts it thinks are up to date.
2. `python -m http.server 34999 --bind 127.0.0.1` in that folder.
3. Studio command bar: `require(game.ServerStorage.Tools.DevSync).Run()`.
   - Expect 13 NEW lines: HouseBuilder, the 8 house styles (in a new Houses folder), HouseClient,
     WeaponService, WeaponClient, Weapons.
   - Many UPD lines are normal.
   - Then save (Ctrl+S).

## A. Smoke test (2 minutes)

Press Play. In Output (View > Output), check:
- `[Main] server ready`, with **no** `[Main] ... failed to start` lines.
- No `[WeaponService] gun store not built` and no `[PropertyService] couldn't build` lines.
- No red errors. Send me the exact text of any red error or `[...]` warning.

Then type `/console` in chat and check the client side for red errors too.

## B. Free roam (no role picker)

1. Press Play: no "How do you want to play?" screen. You're a CITIZEN.
2. Tap the CITIZEN badge (top left). The phone opens on JOBS, which has the police card. GO ON DUTY
   makes you police; GO OFF DUTY switches back.
3. The tutorial bar has 6 steps: car, rob, escape, bank, **buy your first gun**, phone. SHOW ME on the
   gun step routes to Shoreline Arms (the pink-signed shop on the plaza east of the spawn).
4. Stay a minute: the DAY 1 STREAK stamp shows (it used to be lost).

## C. Your fixes, one by one

1. **Paint:** phone > GARAGE > a car > a colour.
   - The swatch shows $500. Tap it: the line above says "TAP AGAIN: $500". Tap again: $500 spent.
   - Pick another colour, then go back to the first: OWNED, $0. Rims work the same way.
2. **Shop:** phone > SHOP lists 5 passes and 5 cash packs, all with FREE (Studio) buttons. Tap a cash
   pack: the money arrives. In your live game you get them free as the owner. Players see the prices,
   with "Coming soon" until you send me the IDs (launch/2).
3. **Jet ski:** at the marina, walk up to a moored Splash: the prompt shows from the dock. Get on.
4. **Nitro:** hold nitro until the tank runs dry. You hear one whoosh that fades, then one click. Keep
   holding: silence, no flicker.
5. **F to exit:** drive around for 15 minutes, getting in and out with F the whole time. If F ever
   fails, Output has a `[DriveController]` line saying why: send it to me.
6. **Phone:** open it, then tap anywhere outside it: it closes.
7. **Heads in cars.** Two ways to check:
   - In Studio, hold **Shift** and press 1-9, 0, -, = to spawn each car (plain number keys now pick
     guns). Sit in each one: your head stays under the roof.
   - Or use the Server command bar:
     `require(game.ServerStorage.Tools.CarBuilder).Showroom(Vector3.new(2150, 0, -1450))` builds every
     car with a dummy in each seat in the drift zone.
     `Showroom(nil)` removes them.
8. **Taxi:** start the taxi job and stop next to a fare: they hop in and you can see them sitting in
   the passenger seat. At their stop they get out and walk away.
9. **Riding with friends:** Studio Test tab > Clients and Servers, 2 players > Start.
   - Player 1 spawns a 4-seat car (the Gatorback or Mangrove).
   - Player 1 invites player 2 (phone > CREW > Invite), and player 2 joins.
   - Player 2 walks up to the car and uses Ride. F gets them out.
   - Roblox friends can ride without a crew. Two Studio test players aren't friends, so that part
     needs a live test.
10. **Houses.** Give yourself cash: Server command bar,
    `game.Players:GetPlayers()[1]:SetAttribute("Cash", 2000000)`.
    - Phone > HOMES > SHOW ME on each house. Each one looks different, and the bigger ones have two
      floors and pools.
    - The Coastal Mansion needs rank 15. To test it, set `CivRank` the same way:
      `game.Players:GetPlayers()[1]:SetAttribute("CivRank", 15)`.
    - Buy one, then press Reset: you respawn inside it.
    - Your cars stand in the garage. DRIVE on one puts you in it.
    - Walk onto the STASH pad with a bag and no stars: it banks.
11. **Saved when you come back:**
    - In Studio, saves only persist with Game Settings > Security > "Enable Studio Access to API
      Services" turned on.
    - Better: in your private live game, buy a house, leave, rejoin. You spawn inside it, and your
      cash, cars, paint and guns are all still there.
12. **No hiding at home:** get a star, then walk into your house.
    - The doors stay shut, and if you're inside you're moved out to the FOR SALE sign: "No hiding at
      home while you're wanted!"
    - DRIVE in the garage is refused while you have any stars.

## D. Guns (new)

1. **Store:** walk into Shoreline Arms and press E at the counter. The store screen lists 4 guns.
   - BUY $750 on the Coral 9 asks TAP TO CONFIRM; tap again.
   - It lands in your backpack (bottom of the screen), and the tutorial gun step ticks.
   - The others show their rank locks.
2. **Shooting, PC:** press 1 to take the gun out.
   - A crosshair follows your mouse, and your character turns to face where you aim.
   - Click fires: a pink tracer, a flash and a sound.
   - The ammo counter (bottom right) counts down, R reloads, and an empty mag reloads by itself.
3. **Shooting, phone:**
   - FIRE and RELOAD buttons appear on the right, and you aim with the crosshair in the middle of the
     screen.
   - As police, FIRE moves left of TASER and SPIKES. Check nothing overlaps.
4. **Two players** (Clients and Servers, 2 players):
   - Player 1 shoots player 2: player 2's health bar (bottom centre) drops and the screen flashes
     red. Player 1 sees a ✕ hit marker and gets 1 star.
   - Keep shooting: player 2 falls apart, respawns at home or the spawn after about 5 s, and the feed
     says "took down".
5. **PASSIVE:** tap PASSIVE (next to CAR).
   - Nobody can hurt you, you can't shoot, and others see a 🛡 over your head.
   - It can't be turned on with stars or within 15 s of a fight. Getting a star turns it off.
6. **Police:** go on duty: you carry a Duty Pistol only.
   - It does nothing to innocent players.
   - Shooting a wanted player down sends them to prison, and you get the bounty.
7. **No-hit rules:**
   - Nobody can hurt you in your first 6 s after spawning.
   - Pedestrians: bullets pass through them.
   - In a car, guns go away and you can't fire.
8. **Cars:** shooting a police car gives a star and damages it, and enough shots make it smoke.
   Shooting a passive player's car does nothing.

## E. Gun sounds (placeholders)

I couldn't check gun sound IDs from here, so the guns play sped-up stand-ins (the crash and stamp
sounds). To use real ones:
1. Studio > Toolbox > Audio. Search "pistol shot", "smg", "shotgun", "rifle shot" and "reload".
2. Pick sounds made by Roblox or ProSoundEffects, right-click > Copy Asset ID.
3. Paste each one into `src/shared/Config/Sounds.lua` (PistolShot, SMGShot, ShotgunShot, RifleShot,
   GunReload, GunEmpty: replace the `0`), or send me the numbers.

## F. Phone performance

On your phone (private publish), drive downtown at night in rain for 5 minutes. Then have a friend
shoot an SMG near you. Note the frame rate and anything that stutters.

## What to send me

For anything that fails, send:
- the step (e.g. C7 or D3),
- what you saw,
- any red Output or `/console` text,
- a screenshot for anything visual: overlaps, heads through roofs, house interiors, the gun in your
  hand (if it points the wrong way, tell me which way it points).
