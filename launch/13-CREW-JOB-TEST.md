# Crew Heist: saved crews, ride-to-crew, crew preps and the Big Score

**Status (Nov 5, 2026):** **live as v9**, published Nov 5 at 16:57 UTC. Committed as 06d216a and **play-tested in Studio with two players** on Nov 4. Offline checks pass too: compile, a lint diff, and `tools/logic-tests/crew.sh` (89 checks).

The publish added only the 10 crew game files on top of live v8. Servers weren't restarted, so new servers get v9.

### Studio test results (Nov 4, about 7:10–7:35 PM, Server & Clients with 2 players)

| What | Result |
|---|---|
| Ride: Player2 in Player1's passenger seat for 12 s | CREW UP? card on Player1: "Add Player2 to your crew?" INVITE / NOT NOW |
| Card timing | My INVITE tap landed just as the 15 s card ran out, so no invite went. **Fixed:** the card now waits 30 s. |
| PHONE > CREW > INVITE | "Invite sent!", then Player2 got CREW INVITE (JOIN / NO THANKS) |
| JOIN | CREW UP! stamp ("NEW CREW HEIST ... $48,000+ each (more with a bigger crew)"), the heist plan on both screens, crewmate name tags |
| PAUSE HEIST (Player2) | The plan left both screens, with "Heist paused. Your progress is saved..." |
| Phone while paused | "CREW HEIST: THE BIG SCORE 0/3 PREPS (PAUSED)" with RESUME HEIST and the 3 preps |
| RESUME HEIST (Player1) | The phone closed, the plan came back, and "Player1 is back on the heist" showed |
| START (plan) | GEAR UP intro, the CREW PREP banner with its clock and QUIT, "Grab the drill parts: 3 stops 0/3", markers |
| Places | Coast Arms, Chop Shop, Spray & Go, Hideout and Police HQ resolved to the real map spots |
| Only Player1 at a stop | It didn't count, and "Stick together: it counts once your crew is there with you." showed |
| All 3 preps | $1,500 + XP each per prep, the plan ticking them off, and both reached rank 3 |
| Getaway Run | At the Reserve gate the clock dropped to 1:15: "Race to the Hideout before the cops show!" |
| All preps done | The plan showed THE BIG SCORE with START HEIST, which started the Big Score for the crew of 2 |
| Big Score pass (4 bars, daytime, crew of 2) | $16,000 each ($32,000 pot split in two), heat cleared, preps reset for the next score |
| Phone layout (PreviewTouch) | The plan is one slim row: "THE BIG SCORE 0/4 / Next: Gear Up · $48K+ each", START, PAUSE HEIST |
| Phone open | The plan steps aside |
| LEAVE CREW | The first tap shows "TAP AGAIN TO LEAVE"; the second leaves. Both players have no crew, and the plan is gone. |
| Errors | 0 in the server and both player logs |

Not covered in Studio: rejoining in a new session to see the saved crew come back. The logic tests cover it.

## What players get

1. **Ride, then crew up.** Someone rides in your passenger seat for about 12 seconds while you drive your own car. You get a **CREW UP?** card: "Add <name> to your crew?" with INVITE / NOT NOW.
   - INVITE sends them the normal crew invite card (JOIN / NO THANKS).
   - The card comes up once per rider per session. The phone's CREW > INVITE still works too.
2. **Crews are saved.** A crew is 2 to 4 players, and any two of them can work the heist. Your crew and its heist progress are still there the next time you play, in any server, until you press LEAVE CREW. LEAVE CREW now takes two taps.
3. **A crew gets a heist.** When the crew forms, both players see a gold **CREW UP!** stamp: "NEW CREW HEIST, The Big Score: rob the Gold Reserve for up to $96,000". Then the **heist plan** comes up on screen:
   - **What it shows:** the 4 steps (Gear Up, Case the Joint, Getaway Run, The Big Score). Done steps are ticked and the next one is boxed in gold.
   - **START** plays the next step. **PAUSE HEIST** puts the crew's heist on hold: the plan leaves every crewmate's screen, the progress is kept, and it stays paused next session.
   - **Where it sits:** on a PC, a panel at the left edge, half way down. On a phone, one slim row in the upper middle ("THE BIG SCORE 1/4", "Next: ...", START, PAUSE HEIST).
   - **When it hides:** while you're on a mission, prep, race or job shift, the Big Score, wanted, a cop or in prison. It also steps aside for stamps, the invite cards, pass offers and the open phone.
   - **Getting it back:** PHONE > CREW > **RESUME HEIST**. Starting a prep, or a new member joining, also brings it back.
4. **Crew preps.** These are driving chores the crew does together, started from the plan's START or PHONE > CREW > CREW HEIST:

   | Prep | What you do | Pay |
   |---|---|---|
   | Gear Up | Drive to Coast Arms, the Chop Shop and Spray & Go (any order), then the Hideout | $1,500 + 120 XP each |
   | Case the Joint | Stop 3 s at the Ironclad depot gate, stop 3 s at the Gold Reserve gate, drive past Police HQ | $1,500 + 120 XP each |
   | Getaway Run | Line up at the Gold Reserve gate, then reach the Hideout before a clock runs out (about 2 min, worked out from the distance) | $1,500 + 120 XP each |

   - A goal only counts when **two crew members are there together**: one car, or a convoy. Arriving alone gives "Stick together".
   - Being wanted doesn't fail a prep. It just doesn't count until you lose the cops.
   - A prep fails for everyone if anyone on it presses QUIT, leaves the game, leaves the crew or goes to the police or to prison.
5. **The Big Score unlocks** once all 3 preps are done (a **BIG SCORE UNLOCKED** stamp). Its pay is unchanged: up to $96k+ split across the crew.
   - A passed Big Score resets the preps for the next score. A failed one keeps them.
6. **If someone leaves** a 2-player crew, it breaks up and the job and its preps go with it. A crew of 3 or 4 keeps going.

## Studio test (two players)

Test > Clients and Servers > **2 players**. See the memory note on the Studio harness for the window quirks.

Before syncing scripts, run `python tools/manifest.py`. Note that another session's Empire work is also in the folder.

1. **Ride offer.**
   - Player1 spawns a car and drives. Player2 hops in through HOP IN, or Player1's INVITE.
   - Expected: after about 12 s Player1 gets CREW UP?. Press INVITE.
   - Expected: Player2 gets the crew invite. Press JOIN.
   - Expected: CREW UP! stamp on both screens, then the heist plan on both (PC: left edge; phone: a slim row).
2. **Heist plan.**
   - Press PAUSE HEIST on Player2. Expected: the plan leaves both screens, and both see "paused the heist... PHONE > CREW".
   - On Player1, PHONE > CREW > RESUME HEIST. Expected: the plan is back on both screens.
3. **Phone.** On both players, PHONE > CREW.
   - Expected: "CREW HEIST: THE BIG SCORE 0/3 PREPS", a PAUSE HEIST button, and 3 START rows.
   - Expected: THE BIG SCORE line reads "Do your crew preps first: 0/3". This shows only at rank 3+; at lower ranks it shows the rank line first.
   - Expected: YOUR CREW lists both with "Here now", plus the "saved" note.
4. **Gear Up.**
   - Press START on the plan. Expected: the plan hides, and both get the CREW PREP banner and the GPS.
   - Drive to one stop with only one player. Expected: "Stick together", and the stop doesn't count.
   - Bring both. Expected: the stop counts.
   - Finish the prep. Expected: PREP DONE stamp, $1,500 each, the plan back with Gear Up ticked, and the phone shows 1/3.
5. **Getaway Run.** Check the clock jumps down at the Gold Reserve gate, and that being too slow fails it with "Too slow".
6. **Shortcut.** Run `["call","CrewService","Debug","$me","preps"]` (DebugService NCCmd). Expected: the plan's last row is boxed with START HEIST, and it starts the Big Score for the crew.
7. **Leave.** Player2 presses LEAVE CREW twice. Expected: both get "your crew broke up", the plan goes, and the CREW HEIST section goes back to the "Crew up..." note.
8. **Saving.** API access is on now, so a Studio test writes to the real save. Form a crew, do a prep, pause, leave the game, then rejoin. Expected: "Your crew: <name>. Crew preps 1/3", and the heist still paused.
9. **Phone layout.** Repeat steps 1 to 4 in phone layout (`PreviewTouch`). Check the CREW UP? card and the plan row fit a 667 x 375 screen.

**Solo in Studio:** `["call","CrewService","Debug","$me","solo"]` makes a crew of one, so the preps can be driven alone. It only works in Studio.

## Crew tip: "WAY MORE MONEY" (Nov 5, live as v13)

The owner asked (Nov 5) for something that tells players they can make a lot more money with a crew, and that they can join up with anyone in the server.

**Status:**
- **Live as v13**, published Nov 5 at 19:20 UTC on top of v12. Servers weren't restarted.
- **What the publish added:** exactly 3 client scripts on top of v12.
  - Shared.Util.CrewTip (new).
  - CrewClient.
  - PhoneUI: the live 06d216a version plus only the two tip hunks. The Empire hunks in the repo's PhoneUI are not live.
- **Checks:** the offline checks pass (compile, a lint diff, and `tools/logic-tests/crewtip.sh` with 30 checks), and the two-player Studio test passed (results below).
- **Not committed yet.**

**Studio test results (Nov 5, ~12:07–12:20 PM, a copy of live v12 plus the 3 scripts, Server and 2 clients):**

| What | Result |
|---|---|
| The Big Score refusing for want of a crew (Player1) | The tip came up within a second: "WAY MORE MONEY / Crews unlock The Big Score: $48,000+ each. You can team up with anyone in this server!" All three lines show on PC, with FIND A CREW and LATER. |
| A $2,500 payout (Player2, no crew) | The tip came up straight away. The $1,000 daily-streak bonus at login didn't trigger it (first 60 s). |
| The tutorial still running | No tip until the tutorial was finished (by design). |
| FIND A CREW | The phone opened on CREW, showing the new note ("Crews make way more money... team up with anyone in this server...") and "Anyone here can join your crew: tap INVITE to ask them." above Player2's INVITE button. The first try fell exactly on the card's 20 s timeout. |
| LATER | The card went. |
| An invite while the tip is up | Player1's INVITE replaced Player2's tip with the CREW INVITE card. JOIN formed the crew (the CREW HEIST section with PAUSE HEIST), and the tip didn't come back. |
| Phone layout (PreviewTouch) | One row. **Fixed in the test:** on the narrowest cards (330 px, a 667 px-wide phone) the second line was cut off, so the phone words now shrink to fit (13 px down to 9). Retested at a ~490 px view: "Crews earn $48K+ each. Team up with anyone here!" shows in full. |
| Crew saved between sessions | The crew from the first session was still there in the second, and the heist plan was on screen. |
| Errors | 0 in the server and client logs, in both sessions. |

**What players see:**
- **The crew tip card**, for players with no crew. It appears in the crew invite's spot:
  - A green **WAY MORE MONEY** tag.
  - PC: "Crews unlock The Big Score: $48,000+ each. You can team up with anyone in this server!"
  - Phones: "Crews earn $48K+ each. Team up with anyone here!"
  - **FIND A CREW** opens PHONE > CREW. **LATER** closes the card, which also goes after 20 s.
- **When the card comes up:**
  - About 3 minutes into a session.
  - Right after a solo payout of $1,000 or more.
  - Straight away when The Big Score refuses to start because there's no crew.
- **Limits:**
  - The card only appears in free roam, past the tutorial, and when nothing else is on screen in that spot: no mission, race, job, wanted level or open phone.
  - It needs another free-roam player in the server.
  - At most 3 timed or payout tips a session, at most one every 8 minutes, and none after LATER is pressed twice. The Big Score refusal still brings it up.
- **PHONE > CREW (no crew):**
  - The CREW HEIST note now reads: "Crews make way more money: The Big Score pays $48,000+ each. You can team up with anyone in this server: tap INVITE by a name under PLAYERS HERE, or give someone a ride..."
  - PLAYERS HERE starts with "Anyone here can join your crew: tap INVITE to ask them."

**Where it lives:**
- Timing rules: `src/shared/Util/CrewTip.lua`.
- The card: `CrewClient` (frame "CrewInvite" with attribute Kind = "Tip", so the HUD pieces that keep clear of the invite keep clear of it too).
- The phone text: `PhoneUI`.
- There are no server changes.

**Studio test (two players, Server & Clients):**
1. **Big Score refusal.** On Player1 (no crew), press START on THE BIG SCORE in PHONE > CREW, then close the phone. Or fire Notify "BigScoreNeedCrew" to Player1 from the server bar.
   - Expected: the tip card, with the words not cut off.
2. **FIND A CREW.** Expected: PHONE > CREW opens, showing the new note, "Anyone here can join your crew", and Player2 with INVITE.
3. **Payout.** 60 s or more into the session, add $2,500 to Player2 (no crew).
   - Expected: the tip comes up within a second or two.
   - Press LATER. Expected: it goes.
4. **Joining.** With the tip up, Player2 joins a crew. Expected: the tip goes.
5. **Phone layout.** Repeat step 1 with `PreviewTouch`. Expected: one 60 px row with FIND A CREW and LATER, and the words fit.
6. **Errors:** none in the server log or either client log.

## Owner decisions (defaults chosen; easy to change in Config/Missions.lua)

- **Prep pay:** $1,500 + 120 XP per member.
- **Big Score pay grows with the crew** (owner, Nov 4: a group heist should pay more). A full van pays $48,000 each for 2, $55,200 each for 3 and $62,400 each for 4. Night (x1.25) and VIP bonuses still apply. It's `MemberBonus` and `Heists.BigScorePot` in Config/Heists.lua.
- **Gating:** the Big Score now **needs** the 3 preps. A crew could start it right away before.
- **Ride time:** 12 s of riding before CREW UP? (`CREW_OFFER_AFTER` in RideService). The card then waits 30 s (`OFFER_EXPIRE`).
