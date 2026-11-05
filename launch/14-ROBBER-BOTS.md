# 14 · Robber bots (NPC robbers for cops to chase)

Owner, Nov 4 2026: "if no one's stealing anything and the game's kind of dead, could there be like a bot
playing the game, stealing something? … I think like 2 bots makes the most sense. What do you think?"

## The short answer

**Yes, 2 is right.**
- With 1 or 2 cops online, 2 bots keep at least one target busy at all times.
- More bots would mean robberies everywhere on a small server, and the cops' job would stop feeling special.
- The 2 bots never start a crime at the same moment.
- Only **one bot is wanted per cop on duty**. A lone cop gets one chase at a time, never two at once.

### When the bots are on

- **Only while a player cop is on duty and actually patrolling.** The rule is ArrestService's "really
  patrolling" check, so an AFK cop doesn't count. With no cop to chase them, a bot robbing a store is pointless.
- **They step aside for real robbers.** Bots on the server = 2 minus the number of real players who are
  wanted right now:
  - 0 wanted players: 2 bots.
  - 1 wanted player: 1 bot.
  - 2 or more: 0 bots.
- A bot in the middle of a chase is never pulled out, so the cop keeps their catch. An idle bot that isn't
  needed drives off and disappears somewhere no player can see it.
- They also appear only where nobody is looking: on a road at least 300 studs from every player.

### What they do (like a real robber)

1. They cruise the city in a plain street car (sedan, hatchback or pickup), with **"NAME · NPC"** on a small
   tag. Nobody mistakes them for a real player.
2. After a minute or so they pick a crime and drive there:
   - **ATM**: 1 star, about $900 in the bag.
   - **Glow Mart or Fuel Stop till**: 1 star, $1,200 to $1,500. The clerk puts their hands up.
   - **Sparkle & Co.**: 2 stars, $4,000 to $6,000. Rarer.
   - **Carjack**: 1 star. They break into a parked street car (the car alarm rings) and drive off in it,
     leaving their old car behind.
3. They park, get out, walk in and do the crime. They take as long as a player's hold, 8 to 14 seconds.
4. **Bots trip the silent alarm the moment they start.** Every cop gets the red DISPATCH post while the bot
   is still inside: "alarm at Glow Mart! Respond now." A carjack sends "car theft reported!" instead.
5. Then they run, the way a wanted player does.

### How cops catch them (everything already in the game)

- **Finding them.** Cops see the same WANTED / LAST SEEN marker with the stars and the Suspect Card
  ("Sedan (blue) · black beanie, red bandana"). While the stars are hollow they see the red search circle.
  Like wanted players, bots are not dots on a cop's map: cops hunt them with the marker.
- **Seen vs. lost.** A cop within 250 studs with a clear view "sees" the bot, and the stars go solid.
  If no cop sees it for 30 + 10 × stars seconds, the bot **gets away** ("… gave the cops the slip!") and
  lies low before its next crime.
- **Spike strips** (G) flatten their tyres, just like a player's.
- **Ram them and box them in.** The bumps already push server cars. A boxed-in or flat-tyred bot often bails
  out and runs on foot, a little slower than a player walks, so a cop on foot catches it.
- **Taser** (T) on a bot on foot: down for 3 seconds.
- **Cuffs** (hold Q): on a stopped car's driver, a tasered or slow bot on foot, or a bot that gave up.
  Sometimes a bot puts its hands up when a cop runs it down on foot.
- **Guns and fists don't touch bots.** That keeps it kid-friendly, and nobody can "steal" a cop's catch by
  shooting it. AI patrol cars leave bots alone too: the bounty is the player cop's.

### What a cop earns

The same rule as arresting a player: **$500 per star + 25% of the bot's bag**. The VIP bonus applies.
It also gives arrest XP and +1 Arrests, just like a player arrest. Typical arrests:

| Crime | Bounty |
|---|---|
| ATM | $725 |
| Glow Mart | $800 |
| Fuel Stop | $875 |
| Carjack | $500 |
| Sparkle & Co. | about $2,000–2,500 |

Bots pace their crimes (about one per 1–2 minutes per bot, after a 1–2 minute break when one is caught).
That makes a busy cop about $10–15k an hour on bots, on top of $80/min patrol pay. That's the same ballpark
as robbing stores, so being a cop is finally worth it on a quiet server.

### No griefing

Bots never:
- Use up a real robber's store. They don't touch the store's cooldown, and they skip any store with a real
  player within 120 studs.
- Shoot anyone or knock anyone down.
- Steal or drive a player's car. Their own cars can't be entered either.
- Go into homes or businesses.
- Make anybody's stars or a real chase harder.

### Citizens

Citizens see bots driving, robbing and being chased. They hear the alarms and see the Coast Feed posts.
They can't rob, hurt or arrest a bot, and bots never target them. Those are calls for the owner later:
for example, citizens could get a small tip for "reporting" a bot.

## How it's built

- **`src/server/Services/RobberBotService.lua`** (new, in Main's ORDER after CarjackService). It decides when
  bots exist, runs each bot's brain (cruise, crime, flee, on foot, give up, caught), and keeps its own heat
  the way HeatService does. It also pays the cop.
  - Bodies are built like PoliceOfficerService's officers: a posed rider in the seat, a walking Humanoid out
    of the car.
  - Cars are driven by RaceAIService, the same NPC driver as the street races.
- **`src/shared/Util/RobberBots.lua`** (new). It's what clients read.
  - `ReplicatedStorage.RobberBots` holds one Configuration per bot, with Heat, HeatSpotted, LastSeen,
    SuspectCar, SuspectOutfit and DisplayName, the same attributes a wanted player carries.
  - The bot's car (Workspace.Vehicles) and body (Workspace.RobberBots) carry the attribute `RobberBot = <id>`.
- **ArrestService**:
  - The taser, spikes and the car's Cuff prompt also work on bots.
  - `ArrestService.BotCuffPrompt` and `ArrestService.RewardCop` (the bounty, XP and stamp) are shared with
    player arrests.
- **RaceAIService**:
  - `Spawn` takes `Car` and `Paint`.
  - New `Route(bot, legs)` (drive somewhere new, or drive on after `Done`) and `SetTop(bot, top)`.
- **LawClient**: the WANTED / LAST SEEN marker, the Cuff prompts, taser aiming, the zap wire, and a bot's
  hands-up pose.
- **SoundClient**: the zap sound on a bot.
- **FeedController**: "car theft reported!" for cops (`BotCarjack`).

## Test status (Nov 4 2026)

**Offline:**
- Every changed file compiles, and luau-analyze shows no new warnings.
- `tools/logic-tests/robberbots.sh` runs the real RobberBotService and RobberBots code in a stand-in world.
  It has 16 scenarios and **93 PASS**. It covers:
  - Who's on and when: no cop means no bots; a cop brings 2; real robbers take priority; bots leave when no
    cop is on duty.
  - Crimes: one crime per cop at a time; the store's alarm, its untouched cooldown and the clerk; stores
    with players near are skipped; carjack.
  - Catching them: taser then cuff; a runner too fast to cuff; spikes, then a bail-out or cuffing the
    driver; boxed in, it bails.
  - Escaping: it gets away when unseen, with witness pings; stars stay solid while a cop watches.
  - Giving up, then cuffed, or hands down once nobody comes.

  Run it with:

  ```bash
  LUAU=<path to luau.exe> bash tools/logic-tests/robberbots.sh
  ```

**Studio (Nov 5 2026, scratch copy of the place, saves off): 32 of 33 PASS, 0 script errors.** The self-driving
test BotTest / BotTestClient used the real remotes and the real Cuff prompts.

Results:
- **Who's on and when:** no cop means no bots; a cop on duty brings 2, each 2,000+ studs away and posed in
  its car.
- **Crimes:** each one trips the alarm, the cop gets DISPATCH, and the store's cooldown is untouched.
- **On foot:** taser from 10 studs with a clear line, then the Cuff hold. The cop got BOUNTY $630 (VIP), the
  Coast Feed posted "Flip-Flop Frank was just cuffed", Arrests went +1, and the bot was taken away. Its slot
  comes back.
- **Car:** CuffDriver on a boxed-in bot paid BOUNTY $1,093 (Glow Mart bag at night, VIP).
- **Escapes:** an unseen bot escapes ("gave the cops the slip").
- **Citizens:** a citizen sees no Cuff prompts and no markers.
- **Leaving:** with no cop, the bots leave.

The one miss was a spike strip dropped where the cop stood in the bot's path: the bot re-routed away from
the cop (by design). A separate check, with the cop stepping away after dropping the strip, flattened a
fleeing bot's tyres.

Fixes from the run:
- A bot gets in from anywhere beside its car (BOARD_REACH 9 studs). It used to hop onto its own roof when it
  came from the far side.
- No hops right next to its goal.

**Live: published as v11 on Nov 5 2026, about 11:45.**
- It's commit 6a46f42, synced onto live v10. The 5 shared scripts and Main were checked byte for byte against
  v8/v10 first.
- Main = v8 Main plus the RobberBotService line, SyncSha 9df1792f.
- The live place started cleanly before the publish ("[Main] server ready", no warnings).
- Servers were not restarted: new servers pick it up.

## Studio test checklist

Run with a cop (player 1) and a citizen (player 2).

1. **Bots appear and stand down.**
   - With no cop: no bots.
   - Switch to cop: within about 10 s, 2 bots appear on roads out of sight.
   - Switch back to citizen: the idle bots leave within a minute.
2. **Crimes.** Each bot cruises, then robs: an ATM, a store (the clerk's hands go up), or a carjack (the car
   alarm rings).
   - The cop gets DISPATCH.
   - The marker shows WANTED or LAST SEEN with the stars and the clues.
3. **Chase and arrest by car.** Follow a bot until it's seen (solid stars), spike it, then box it in.
   - Cuff the driver (hold Q).
   - BOUNTY stamp with the right amount, cash added, Coast Feed "… was just cuffed by …".
   - The bot is gone, and its slot comes back about 1–2 minutes later.
4. **On foot.** A bot that bails runs. Taser it (T), then cuff it.
5. **Escape.** Stay away for 40+ s: "gave the cops the slip", and the marker goes.
6. **Real robbers win.** Give the citizen heat:
   - 1 wanted player: at most 1 bot.
   - 2 wanted players: no new bot crimes.
7. **Citizens untouched.**
   - The citizen can't see the Cuff prompt and can't shoot a bot.
   - The store the bot robbed still opens for the citizen.
   - Nothing errors in the logs: `[RobberBotService]`, `[LawClient]`, `[ArrestService]`.
