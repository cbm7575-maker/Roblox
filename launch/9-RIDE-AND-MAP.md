# 9. Riding together and the big map (Nov 4)

What's new:
- **HOP IN for any player's car**, with the driver saying yes first for strangers.
- **INVITE** from the driver's seat.
- **Other players as dots** on the minimap.
- **Big map:** tap the minimap or press M to see the whole city, then tap a spot to set a GPS waypoint.

Nothing was removed. Crewmates and Roblox friends still hop in straight away, as before.

## Riding together

**HOP IN** (the button that used to say RIDE):
1. Walk to the passenger door of another player's car.
2. If they're a crewmate, a Roblox friend, or someone who has let you in before, the button says **HOP IN** and puts you straight in the seat. It's F on a keyboard, X on a gamepad, or a tap.
3. If they're a stranger, it says **HOP IN · ASK DRIVER**, and pressing it sends the driver a card: "**<name> wants to hop in your car**", with **LET IN** / **NO**.
4. LET IN puts the rider straight into the seat (if they're still within about 45 studs). It also remembers them for the rest of the session, so next time they hop in without asking.
5. The car's own bubble says "Hop in" or "Ask to hop in" and does the same thing with E.
6. A stranger's car only offers this while its owner is driving it or standing near it. A parked car with nobody around shows nothing.

**INVITE** (driver's side):
1. Sit at the wheel of your own car, stopped or crawling (under about 10 mph), with the passenger seat free.
2. When another player is on foot within about 35 studs, an **INVITE** button appears. On a PC it's in the right-hand column, key **B**. On a phone it's a "+ INVITE" tile.
3. Press it. They get a card: "**<name> invites you to hop in**", with **HOP IN** / **NO THANKS**.
4. HOP IN puts them in your passenger seat right away (within about 45 studs, nothing in the way). If they're too far, they're told to walk over and press HOP IN.

**Limits:**
- Cops ride with cops, citizens with citizens, and prisoners never ride.
- A card waits 15 seconds.
- After a NO, or no answer, the same person can't be asked again for a minute.
- Gamepad players have no INVITE key, because every button is already used while driving. The walker can still ask with HOP IN.

## Other players on the map

- Other players show as small white dots on the minimap. Player cops are blue, and crewmates stay purple with their initial, as before.
- Hidden from the map:
  - Prisoners, and players inside a home.
  - If you're a cop: wanted players.
  - If you're wanted: player cops. The chase radar still decides which police you see.

## The big map

- **Open:** tap or click the minimap, or press **M** on a keyboard.
- **Close:** the X button, or M again.
- It shows the whole city: every place with its name, you, the other players (same rules as above), and your GPS route.
- **Zoom and pan:** the mouse wheel or the + / − buttons, and drag to move around.
- **Tap a place** to get a GPS route to it.
- **Tap anywhere else** to drop a waypoint there, with the route on the roads, the gold line and the pillar.
- **CLEAR** removes the waypoint.
- It's a waypoint, not a teleport, so the police chase still works.

## Tested before going live (version 7, Nov 4, 11:05 AM)

Checked in Studio with two players, on both the PC layout and the phone layout (PreviewTouch, below):
- **INVITE:** the button and the B key, the card, HOP IN seating the rider.
- **HOP IN:** a stranger's "HOP IN · ASK DRIVER", then LET IN seating the rider; afterwards HOP IN works straight away with no asking.
- **Big map:**
  - opening it by clicking the minimap and with M;
  - zooming with the wheel and +, and dragging;
  - clicking a place (route by name) and empty ground (Waypoint), on both layouts;
  - the route showing on the minimap and the road.
- **Player dots** on the minimap.

There were no script errors.

Two things Studio couldn't show:
- **Top-right buttons:** Studio's test window ignores clicks in the top-right corner of the game view. That's where the phone INVITE tile and the map's X and CLEAR ROUTE sit. They're the same kind of button as the ones that worked, and nothing in the game covers them (the Roblox player list is turned off), but tap them once on a real phone.
- **Pinch zoom** needs a real touch screen.

## Testing it in Studio (two players)

1. Test tab > Clients and Servers, 2 players.
2. In the **server** window's command bar run `workspace:SetAttribute("RideAsStrangers", true)`. Studio's test players count as friends unless you turn this on, which treats them as strangers.
3. To check the phone layout on a PC, run this in a client window's command bar:
   `game.Players.LocalPlayer:SetAttribute("PreviewTouch", true)`
   This works in Studio only, and switches the whole HUD to the phone layout.
