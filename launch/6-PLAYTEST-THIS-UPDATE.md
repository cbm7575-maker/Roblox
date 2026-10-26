# 6. Playtest this update (Oct 26: your Theft Miami Coast fixes)

This update is built on your own Studio save of THEFT MIAMI COAST (Oct 25, 126 scripts). None of it
has been run in Roblox yet. It was checked outside Studio: type checks, offline tests of the paint,
shop, nitro and seat-fit logic, two independent code reviews, and the houses built in a stand-in for
Roblox and rendered. Studio is where it gets proven. Go in order: section A tells you in two minutes
whether everything loaded.

## Load it into Studio

0. **Back up first.** In Studio, File > Save to File As... `TheftMiamiCoast-backup.rbxl`. The sync
   replaces every script that differs from these files.
1. Unzip over your project folder (the zip leaves out NeonCoast.rbxl, so your own place file is never
   overwritten), then run `python tools/manifest.py`. It should say
   **133 scripts**. Don't skip this: without a fresh manifest, DevSync skips scripts it thinks
   are up to date.
2. `python -m http.server 34999 --bind 127.0.0.1` in that folder.
3. Studio command bar: `require(game.ServerStorage.Tools.DevSync).Run()`.
   - Expect 7 NEW lines: HouseBuilder and the 6 house styles (Loft, Bungalow, Ranch, Penthouse,
     Villa, Mansion) in a new Services.Houses folder.
   - Many UPD lines are normal.
   - Then save (Ctrl+S).

## A. Smoke test (2 minutes)

Press Play. In Output (View > Output), check:
- `[Main] server ready`, with **no** `[Main] ... failed to start` lines.
- No red errors. Send me the exact text of any red error or `[...]` warning.

Then type `/console` in chat and check the client side for red errors too.

## B. Free roam start

1. The title screen has one **PLAY** button. No FREE ROAM / POLICE choice any more.
2. Press PLAY: you're in free roam as a citizen.
3. Police is an optional job: PHONE > JOBS has the card "POLICE: AN OPTIONAL JOB" with GO ON DUTY.
   GO OFF DUTY switches back. It refuses while you have stars ("Lose your heat before going on or off
   duty."), in prison, and for a few seconds after switching.
4. Road to the Coast: the goal after "Paint your ride" is **"Gear up: buy your first gun at Coast
   Arms"**. SHOW ME routes you to Coast Arms. Buy the pistol ($2,500): the goal ticks and pays $1,000.
   - Only players who haven't got past "Paint your ride" yet get it. Anyone further along skips it
     (that's how the game already treats new goals). If your own save is past it, start your goals
     over in the **server** command bar:
     `require(game.ServerScriptService.Services.JourneyService).Reset(game.Players:GetPlayers()[1])`.

## C. Your fixes, one by one

1. **Paint you keep:** PHONE > GARAGE > a car > STYLE.
   - Each swatch has its price under it. Tap one: the line says "TAP AGAIN TO BUY" with the name and
     price. Tap again: the money goes.
   - Pick another colour, then go back to the first: it says OWNED and costs nothing. Rims work the
     same way. Stock paint and stock rims are always free.
   - VIP and Neon Garage pass paints are free for pass owners (they used to cost $500). Tell me if you
     want that changed back.
2. **Shop:** PHONE > SHOP lists the 5 passes (VIP, Big Duffel Bag, SWAT Unit, Neon Garage, Hypercar)
   and the 5 cash packs. In Studio and for you as the owner in the live game they're free: tap one and
   it's yours. Other players see the Robux price; until the real IDs are in (launch/2) the buttons say
   it's coming soon.
3. **Jet ski:** at a marina, walk to the end of the dock next to your moored boat.
   - The Drive bubble shows from the dock (boat bubbles now reach 60 studs). Use it: you're on.
   - Launching a boat from the phone while you stand on the dock near its pad sits you straight in it.
4. **Empty nitro:** hold nitro until the tank runs dry. You hear one whoosh that fades, then one
   click. Keep holding: silence, no flicker. Let go and it recharges as before.
5. **F to exit:** play for 20+ minutes, getting in and out with F the whole time. Include a reset
   (Esc > Reset) while sitting in a car, then get back in and press F.
   - The likely cause, found by reading the code: this place keeps a body's joints when it dies
     (CharacterBreakJointsOnDeath is off), so a reset in a seat left the dead body's seat weld behind,
     and the old F only removed the first weld it found in the seat. That is a strong guess, not
     proven: I couldn't reproduce it without Studio. Now every weld holding you goes, leftovers are
     cleaned up, and your device asks again and stands you up if nothing happened.
   - If F ever fails, a `[DriveController] still held by ...` line says why. In Studio it's in Output;
     in the live game type `/console` in chat (Client log). Send me that line.
6. **Phone:** open it, then tap anywhere outside it: it closes. Tapping a HUD button outside the phone
   presses that button and leaves the phone open.
7. **Heads in cars.** Two ways to check:
   - Spawn each car and sit in it: your head stays under the roof. Tall avatars and big hats sink into
     the seat and lean back a little. The Riot Truck, Armored Van and Gatorback get this too.
   - Or, in Play mode, run this in the **server** command bar:
     `require(game.ServerStorage.Tools.CarBuilder).Showroom(Vector3.new(2110, 0.35, -1350))`.
     It builds every car and boat in a row in the Lighthouse Key drift zone, with a dummy in each seat.
     Add `, 1.3` after the position for tall dummies. `Showroom(nil)` removes them.
   - The boat seats (Harbor Patrol, Moonstone) are my estimates, not measured. Screenshot those.
8. **Taxi:** start a taxi shift and stop next to a fare. They sit in the passenger seat where everyone
   can see them. At their stop they get out and walk off.
9. **Riding with friends:** Studio Test tab > Clients and Servers, 2 players > Start.
   - Player 1 spawns a car. Player 2 walks up to its passenger side: a RIDE button shows (or press F).
     They're in. F gets them out.
   - Crewmates can ride, and so can Roblox friends without a crew. Studio's test players count as
     friends, so you can test that here too.
   - It's one passenger per car (the passenger seat). There are no back seats yet.
   - Not into a cop's car as a citizen, and not out of prison.
10. **Houses:** every home now has its own build. Give yourself cash first: SHOP's free cash
    packs, or the **server** command bar: `game.Players:GetPlayers()[1]:SetAttribute("Cash", 2000000)`.
    - PHONE > HOME lists the 6 homes. GPS takes you to a front door: "View / Buy", then TOUR to walk
      round inside first.
    - What to look for: the Rustwater Loft is a brick warehouse with a mezzanine bedroom; the Palm Hills
      Bungalow a tin-roof cottage with a screened porch; the Palm Hills Ranch an L-shape with a 3-door
      garage and a hot tub; the Solana Heights Penthouse has a terrace pool and a sky garage; the Marina
      Row Villa has two floors, a tower, a pool and spa, and a 6-car garage; the Flamingo Beach Mansion
      ($1.2M) has three levels, an 8-car showroom, an infinity pool and a roof spa.
    - Walk every floor of every home. Check: the pools hold water, "Drive this" works from every garage
      bay, the wardrobe works, the EXIT gets you out, and the FOR SALE stand works on a tour. Look at the
      lots at night too.
    - I could only build and render these outside Roblox, with plain colours and no real lighting.
      Send me screenshots of anything that looks wrong (gaps, floating parts, things you can walk
      through, a room you can't get out of).
11. **Spawning at home** (needs saves: in Studio, Game Settings > Security > "Enable Studio Access to
    API Services"; or use your private live game):
    - Buy a home, leave, rejoin. The title screen shows from your front door; press PLAY and you fade
      inside your home, with your cars in the garage.
    - Reset (Esc > Reset): you come back inside.
    - Get a star while inside: you're put out of the front door ("Lose the cops first!...").
    - Go on police duty and respawn: you don't go home. Off duty again: you do.
    - Your cash, cars, paint and guns are still there after rejoining.
    - Several players at home at once (Clients and Servers, 3 players), especially in the Penthouse and
      Mansion: note any lag. Each home copy is big (640 to 1,010 parts).

## D. Guns in the hand

Equip each gun on a few different avatars (your own, a tall one, a blocky one). The gun points
forward out of the right hand. Send a screenshot of any that doesn't.

## E. Phone layout

In Studio's device emulator (and on your phone if you can), check the goal bar and banners don't run
under the cash and stars, and that the AIM button doesn't cover the subtitles or the action button.

## What to send me

For anything that fails, send:
- the step (e.g. C5 or C10),
- what you saw,
- any red Output or `/console` text,
- a screenshot for anything visual: heads through roofs, house interiors, a gun that doesn't sit
  right.
