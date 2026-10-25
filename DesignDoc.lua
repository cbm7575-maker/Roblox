-- DesignDoc (ModuleScript) for Neon Coast. Copy into ServerStorage when the place is created.
-- Source of truth for the full plan: the Neon Coast PRD doc
-- https://claude.ai/code/artifact/3a25c83f-e976-40f9-92c0-5ab67a9c205c
-- Once the place exists, the copy in ServerStorage is the live version; this file is the seed.

return {
	Title = "Neon Coast (working title)",
	Pitch = "Open-world free-roam driving game in Port Solana, a neon Florida-style beach city. "
		.. "Everyone starts as a citizen: drive, race, work jobs, buy homes and guns, or pull heists and race "
		.. "away from AI police and players on the optional police job. Everything you earn is saved.",

	Pillars = {
		"The chase is the heart: cars must feel great on a phone before anything else is built",
		"Neon Miami look nobody else on Roblox has (pastel art deco by day, neon by night)",
		"Fair fun: guns with PASSIVE mode (opt out of being shot), police guns only hurt wanted players, "
			.. "pedestrians are never hurt, no blood, rotating heists, server-authoritative money",
		"Original IP only: never GTA, Grand Theft Auto, Vice City, Leonida, Rockstar or real car brands",
	},

	Targets = {
		Launch = "Early 16+ version Sat Oct 10 2026; full launch Thu Nov 12 2026 (GTA 6 preload day)",
		Rating = "Mild 9+",
		MaxPlayers = 30,
		D1 = "12-20%", Session = "15+ min", Payers = "1-3%",
	},

	-- Hours are focused session hours from the PRD build plan.
	BuildPlan = {
		{ Phase = 1, Name = "Driving foundation", Hours = 13, Gate = "Car feels fun on keyboard and on the user's phone", Steps = {
			"1.1 New place, folders, DesignDoc, settings (streaming, 30 players) - 1h",
			"1.2 Rough city: road grid, highway loop, district blocks - 3h",
			"1.3 Raycast car v1: gas, brake, steering, suspension, drift, chase camera - 4h",
			"1.4 Phone driving controls (Input Action System), tested on phone - 2h",
			"1.5 Car spawning: pads, one car per player, cleanup - 2h",
			"1.6 VehicleGuard anti-cheat: speed + teleport checks - 1h",
		}},
		{ Phase = 2, Name = "Cops and robbers core", Hours = 29.5, Gate = "Full heist, chase, arrest, jailbreak with 2+ players", Steps = {
			"2.1 Teams + picker + cop cap - 2h",
			"2.2 Heist system + 3 quick heists (Glow Mart, Fuel Stop, ATMs) - 4h",
			"2.3 Crew heists: Sparkle & Co, Club Nova, Coastal Bank, Sea Dream yacht - 5h",
			"2.4 Heat stars, bounty, map markers, Coast Feed - 3h",
			"2.5 Cop tools: taser, cuffs/arrest, spike strips - 4h",
			"2.6 Robber tools: nitro, smoke - 1.5h",
			"2.7 Saltmarsh Prison, breakout, timer - 2.5h",
			"2.8 Hideout banking + money - 1h",
			"2.9 AI patrol cars at high heat + tutorial chaser - 3h",
			"2.10 Car Boost job: hot parked cars, lockpick minigame, chop shop, trackers - 2h",
			"2.11 Suspect Card (outfit + car), hollow/solid stars, search circle, hideout wardrobe disguises - 1.5h",
		}},
		{ Phase = 3, Name = "The city and cars", Hours = 25.5, Gate = "Whole map built, lit, driveable with 12 vehicles", Steps = {
			"3.1 Full city: 7 districts + Lighthouse Key - 8h (parallel builder agents)",
			"3.2 10 cars + 2 police cars: bodies, tuning, sounds - 5h",
			"3.3 Speedboat, jet ski, police boat - 2h",
			"3.4 Ambient traffic (client-side) - 3h",
			"3.5 Neon nights: lighting, day/night, signs - 2h",
			"3.6 Sound + radio: engines, sirens, alarms, 3 stations w/ TTS DJ lines, Streamer Mode - 3h",
			"3.7 Rain storms: slick roads, reflections, thunder - 1h",
			"3.8 Florida moments: random events (gator in Glow Mart), wildlife, easter eggs, mugshot card - 1.5h",
		}},
		{ Phase = 4, Name = "Progression and shop", Hours = 18.5, Gate = "Money saves, cars buy + customize, shop works", Steps = {
			"4.1 DataService saving - 2h",
			"4.2 Car dealer + customizing (paint, rims, underglow) - 4h",
			"4.3 Phone menu (Map, Garage, Feed, Crew, Shop, Settings) - 4h",
			"4.4 Tutorial (first 10 minutes) - 2h",
			"4.5 Passes + products + idempotent ProcessReceipt - 2h",
			"4.6 Daily streak, challenges, crew/friend bonus - 1.5h",
			"4.7 Analytics events - 1h",
			"4.8 Minimap (pre-rendered map image) + GPS routing over road nodes - 2h",
		}},
		{ Phase = 5, Name = "Test and launch", Hours = 14.5, Gate = "Friends test passes, phone smooth, store page ready", Steps = {
			"5.1 Phone performance pass - 2h",
			"5.2 Multiplayer test with 3-5 friends - 3h",
			"5.3 Bug-fix round - 4h",
			"5.4 Multi-agent code review + fixes - 2h",
			"5.5 Store page: icon, thumbnails, description, video - 2.5h",
			"5.6 Maturity questionnaire + publish (user) - 1h",
		}},
	},

	UserOnly = {
		"Create the place (File > New > Baseplate) and Save As NeonCoast.rbxl in the project folder",
		"Game Settings > Avatar > R15 only; Lighting style Realistic (not scriptable)",
		"Workspace properties > Streaming: StreamingIntegrityMode = PauseOutsideLoadedArea, StreamingMinRadius = 256 (not scriptable from the MCP)",
		"Max players 30: Game Settings after publishing (Players.MaxPlayers is read-only in scripts)",
		"Publish (private first, for phone tests), Creator Hub passes/products, maturity questionnaire, ads",
	},

	Changelog = {
		{ Date = "2026-09-27", Notes = "Seed created from the PRD. Nothing built yet." },
		{ Date = "2026-09-27", Notes = "PRD expanded (GTA 6 Deep Dive, Game Design Spec, Tech Spec tabs). Added car boost, Suspect Card/disguises, rain, Florida moments, radio, minimap. Neon Coast total 101h." },
		{ Date = "2026-09-28", Notes = "Step 1.1: NeonCoast.rbxl created by user. Folders: Workspace.City/Heists/Spawns/Vehicles, ReplicatedStorage.Shared.Config/Util + Remotes, ServerScriptService.Services, ServerStorage.VehicleTemplates/Tools, StarterPlayerScripts.Controllers. StreamingEnabled on, walk speed 18. Config.Vehicles added (12 land vehicles)." },
		{ Date = "2026-09-28", Notes = "Dev workflow: local files are the source; python http.server on 127.0.0.1:34999 + ServerStorage.Tools.DevSync pulls them into Studio (HttpService.HttpEnabled turned on for this). tools/manifest.py maps files to scripts." },
		{ Date = "2026-09-28", Notes = "Step 1.2: ServerStorage.Tools.CityGen builds the greybox (7 districts, Highway 1 loop, avenues + grid, ocean + prison moat terrain water, ~190 placeholder buildings with neon bands, heist/spawn/service markers, car pads, edge walls, golden-hour lighting). Buildings touching roads or markers are removed automatically." },
		{ Date = "2026-09-28", Notes = "Step 1.3: raycast car. CarBuilder (greybox cars from Config), VehicleService (spawn in front of player, one car per player, owner-only driving, network owner = driver, exit remote, idle despawn 10 min), DriveController (springs along ground normal, grip as per-second rate, handbrake drift, nitro, chase camera with wall check, F exit, R flip), VehicleVisuals (wheels for other cars). Tested: Palmetto 0-100 in ~3.2s, top 116/120; Vortex 194 straight with zero pull; drift slides ~42 studs/s and recovers in 0.3s; parked creep 0; enter/exit/flip OK. Studio test: number keys spawn cars (CoreGui blocks them for MCP input; use the remote)." },
		{ Date = "2026-09-28", Notes = "Step 1.4: DriveUI (speed gauge in MPH + nitro bar for everyone; phone: GAS/BRAKE pedals override throttle so the thumbstick only steers, NITRO, DRIFT, EXIT, FLIP when upside down; hides Roblox's jump button while driving). Studio preview: set LocalPlayer attribute PreviewTouch = true. Camera moved closer (13.5 + 5*speed). PHONE TEST PENDING (needs a private publish)." },
		{ Date = "2026-09-28", Notes = "Step 1.5: starter car waits on a free car pad for your side (robber pads face north, cop pads face south), space check against cars/buildings/players, cars in water (chassis y < 0.2 for 2s) or below -60 are removed with a 'Your car sank!' toast (NotifyController, server sends keys only)." },
		{ Date = "2026-09-28", Notes = "Step 1.6: VehicleGuard checks driven cars every 0.5s: teleport > 300 studs or speed > nitro top x 1.25 + 15 (2 samples) -> snap back + flag; 5 flags in 5 min -> car removed. Studio only logs unless Workspace attribute GuardEnforceInStudio = true. Tested: fake teleport and a 250 studs/s speed hack both caught. RULE: any future server-side car teleport must call VehicleGuard.Allow(car) first." },
		{ Date = "2026-09-28", Notes = "Steps 2.1/2.2/2.8: TeamService + TeamUI picker, HeistService (rotation of 4 open types, bank event every 15 min, server-timed hold-to-rob, bags, alarm after 10s head start), EconomyService (Cash/Carried attributes + leaderstats), HideoutService (bank when unspotted, clears heat), HUDController (cash/bag/heat stars/stamps), HeistClient (site signs, prompt visibility), FeedController (Coast Feed toasts). Full loop tested: rob Glow Mart -> bag $1,200 -> bank -> CLEAN GETAWAY." },
		{ Date = "2026-09-28", Notes = "DIRECTION CHANGE (user approved): open world, GTA-style. Roles: Civilian (default, free roam, can commit crimes -> Wanted via heat), Cop (job), Prisoner. 'Robber' renamed to 'Civilian' everywhere. 3 civilian spawns (downtown, beach, Palm Hills) + hideout, 14 civilian pads, 5 cop pads. Planned activities: street races, stunt jumps, drift zone, jet ski course, taxi/delivery job, car meet lot, phone missions (+~27h)." },
		{ Date = "2026-09-28", Notes = "Review fixes (11 bugs): VehicleGuard rewritten (pcall per car, reference = last good sample, tracks every client-owned car, rise/spin checks, snap back via server ownership, removal via VehicleService.Despawn + CarRemoved); spawn requests rate-limited, refused while Wanted, ground-only raycast, no car for departed players, weak tables; Drive prompt only on your own empty car; touch pedals track each finger's InputObject; jumping disabled while seated (no more jump-button hiding); wheels use Motor6D.Transform; HUD CAR button." },
		{ Date = "2026-09-28", Notes = "Steps 2.4/2.5/2.7: HeatService (250-stud sight with walls blocking, hollow after 8s, escape after 30+10*heat s, hot zones, 4+ star pings, bounty 500/star + 25% bag), ArrestService (taser T, spikes G with 2 charges, cuff prompts only on wanted players, AI/cop arrests, patrol pay $80/min), PrisonService (45+15*heat s timer, vent breakout -> wanted 2 stars; breakout only counts after being seen on the island), LawClient (cop markers, search circles, stamps, mugshot headlines), RateLimit, DebugService (Studio: NCDebug bindable)." },
		{ Date = "2026-09-28", Notes = "Step 2.9: CarPhysics shared module (client driver + server AI), RoadGraph (nodes/edges from road parts, A*, published as JSON), AIPoliceService (spawns when < 2 player cops, follows roads, direct pursuit near/in sight, capped at 95% of target speed, parks a car length away, arrests after ~3s stopped). FIX: roads/walls longer than 2048 studs were silently truncated (gaps in the highway) -> CityGen now builds long roads/walls from pieces." },
		{ Date = "2026-09-28", Notes = "Step 2.11: Suspect Card (SuspectOutfit / SuspectCar attributes noted by cameras and cop sightings, shown on cop markers), DisguiseService (hideout wardrobe hats/masks from parts, -1 star when unseen; Spray & Go $500 respray, -1 star, 30s cooldown), WardrobeUI, car swap allowed while hollow. Tested: disguise 2->1 star, respray 2->1 star." },
		{ Date = "2026-09-28", Notes = "Step 2.10: CarBoostService (3 hot cars on roadsides, 4s server-timed lock pick, +1 heat, 40% GPS tracker ping after 20s, Chop Shop delivery -> value into bag). Step 2.6: RobberToolsService smoke (6 invisible sight-blocking clouds + particles, 1 charge / 30s; CarPhysics/camera/wheel rays ignore Workspace.Smoke). Step 4.1 (pulled forward): DataService (session lock, retries, autosave 60s, BindToClose, Studio memory fallback; saves cash, look, stats)." },
		{ Date = "2026-09-28", Notes = "Phase 6 activities: RaceService (3 street races, countdown, checkpoints, par bonus, PBs, board), StuntService (8 stunt jumps, slow-mo), DriftService (Lighthouse Key drift zone, combo scoring, paid per chain), JobService (taxi shifts with roadside passengers, distance pay + speed tip). ActivityClient UI." },
		{ Date = "2026-09-28", Notes = "Phase 3 art: ArtKit + ArtGen (styled buildings per district, 375 street lights, centre lines), generated meshes (palm, flamingo statue, gator, lighthouse, Ferris wheel, yacht, cypress, tropical bush), art modules HeistFronts / Beach / PalmHillsDowntown (parallel agents, reviewed with screenshots; DocksMarina + GladesPrison pending). WorldService: 12-min day/night, storms (wet grip x0.75), night heists +25%. SkyClient rain/lightning/night windows." },
		{ Date = "2026-09-28", Notes = "Steps 4.2/4.3/4.8: GarageService (owned cars saved, paint $500 / rims $1,500 / underglow $3,000 once per car), phone (Garage, AutoNeon dealer, GPS with road routes + light pillar, Jobs, Shop; design-size UI scaled to any screen), MapService (places, open heists, map shapes), MinimapClient (ViewportFrame top-down map, GPS line, rim-pinned blips, wanted flash)." },
		{ Date = "2026-09-28", Notes = "Step 3.4: TrafficClient (client-side ambient traffic on the RoadGraph, lanes by road width, slows for corners and cars ahead, stops for players, knocked flying when rammed; collision groups Vehicles/Traffic). Step 3.2: mesh bodies for all 12 cars (generate_mesh segmented body/wheels/windows/lights/bumpers, BodyPrep tool, IDs in tools/CAR_BODIES.md), visual wheels moved into the arches; 3 textured traffic models." },
		{ Date = "2026-09-28", Notes = "Steps 4.4-4.7: TutorialService/Client (4 steps, SHOW ME routes the GPS, $500 bonus), ShopService (5 passes + 5 cash packs, idempotent ProcessReceipt saved with the cash, live prices, VIP chat tag, pass paints/glows; IDs = 0 until the Creator Hub items exist), DailyService (login streak $1k..$7k, streak paint), Telemetry (economy, onboarding funnel, custom events)." },
		{ Date = "2026-09-28", Notes = "Step 3.6: SoundClient + Config.Sounds (all ProSoundEffects / APM / Roblox Resources): engines, sirens (H toggles for cops), horn (H), skids, nitro, doors, splash, alarms, rain/thunder, surf/gulls, city hum, UI, 3-station radio (V). LESSON: never start Play while generate_mesh jobs run (they fail)." },
		{ Date = "2026-09-28", Notes = "Progression (ranks 1-20 per side, unlocks, 3 daily challenges, GOALS app), boats (jet ski rental, Marlin, Harbor Patrol; CarPhysics boat mode; marina/beach boat pads; Surf Sprint boat race), crews (CrewService, CREW app, +20% crew / +10% friend bonus, passenger seat), Florida moments (EventService: gator, beach treasure, UFO), phone missions (5), pedestrians (PedClient), SETTINGS app (volumes, Performance mode), multi-step heists (bank fuse box, yacht alarm panel). All 5 art modules integrated (8,169 art parts). Spawns face their pads." },
		{ Date = "2026-09-28", Notes = "Code review round 2 (3 reviewers, ~31 findings fixed): passenger exploits (drift/stunt pay, ride from prison), Ride prompt server-enabled, boat rays from above water, AI ignores boats, wheel radius, DataService.OnLoaded (no more 15 s polling), honest save result, verified pass purchases, crew invite race, clock-skew day checks, Remotes.OnClient (non-blocking), minimap culling, traffic non-colliding, UI overlaps on phones, stamp queue." },
		{ Date = "2026-10-19", Notes = "Recovery: the local src/ folder was lost; all 85 scripts extracted byte for byte from NeonCoast.rbxl (Sep 28 save) into git (tools/extract_rbxl.py), tools/manifest.py rewritten, tools/CAR_BODIES.md rebuilt from the place. Luau type check of every script (luau-lsp + Roblox definitions): no real errors. Fixes: a repeat ProcessReceipt for an already-recorded purchase now answers PurchaseGranted only after a successful save; the dealer's GAME PASS button opens the SHOP instead of saying 'shop coming soon'." },
		{ Date = "2026-10-19", Notes = "Launch kit in launch/: private publish + phone test checklist, Creator Hub setup for the 5 passes and 5 cash packs (PRD prices, descriptions checked against the code; Neon Garage has no animated patterns, Coast Club isn't built), 11 icons (5 pass, 5 cash pack, game icon), 3-hour friends test plan, store description, maturity answers from a content audit of all scripts (expected: Mild). Shop IDs still 0 until the Creator Hub items exist." },
		{ Date = "2026-10-19", Notes = "Full review + GTA-feel pass (not yet run in Studio; type-checked, logic-tested, five code reviews; test list in launch/6-PLAYTEST-THIS-UPDATE.md). Audit of every system by five reviewers found ~30 bugs, all fixed: reset-to-escape arrest dodge, nitro refill on re-entry, spikes missing fast cars and wanted passengers, idle cops switching the AI off, AI not braking for corners and arresting through walls, pedestrians knocked flying and walking in lanes, traffic popping in and driving through ramps/parked cars, a tutorial players could get stuck in, unreadable tutorial text, button overlaps on phones, economy exploits (race/drift/stunt/car meet/patrol farms)." },
		{ Date = "2026-10-19", Notes = "Police: Config.Police; units by stars (1,1,2,3,4) minus engaged cops; street patrols that answer crimes; AI chases only while it sees you, else last-seen + search circle (escape faster outside it); roadblocks with spikes at 4+ stars; new crimes: ramming a cop, evading (+1 star/min, max 4); dying while wanted = arrest; gentle tutorial chaser. Vehicles: VehicleDamageService (crashes, cops ram robbers into smoke/stall/limp; innocents never damaged by other players), Spray & Go repairs ($250 no heat, $500 respray), crash sound/shake, health bar, flashing light bars, brake lights." },
		{ Date = "2026-10-19", Notes = "World: pedestrians dodge (never fall), panic from wanted players/sirens, talk (Config.PedLines), hang out at benches/bus stops; traffic sees everything, pulls over for sirens, honks; 4 new Florida moments (performer, beach party, flamingo, lost tourist); district title banners. Money: crime pays ~2x safe grinding (daily full-pay caps on drift/races/stunts), 4 safehouses (PropertyService: respawn, bank at zero heat, rent), Escape/Fragile missions + 4 cop missions, 40 hidden Gus figurines (CollectibleService, Gator Green paint for all 40). UI: tutorial v2 (car, rob, escape, bank, phone), two-line top bar, objective line, escape bar, HOMES and FEED apps." },
		{ Date = "2026-10-25", Notes = "Playtest fixes (not yet run in Studio; type-checked, four code reviews, houses and gun store built offline in a mock and rendered). Free roam: no role picker, everyone joins as a citizen (spawns inside their home if they own one), police is an optional job in PHONE > JOBS. Paint and rims are bought once per car and stay owned (price shown on every swatch, tap twice to buy). Shop filled with the 5 passes and 5 cash packs (FREE buttons in Studio and for the game's owner). Jet ski prompt reach (60 studs), nitro sound (one whoosh, one click when empty), F exit hardened (ContextActionService + raw fallback + retry), tap outside the phone to close it, seats refit so heads clear every roof, taxi fares sit visibly in the car, friends and crew can ride in each other's cars (rear seats on 4-seaters)." },
		{ Date = "2026-10-25", Notes = "Houses: 8 distinct builds (HouseBuilder kit + Houses/<Style>): stilt cabin, brick loft, bungalow, townhouse, family home with pool, villa, beach house, $1.2M mansion (rank 15, 6-car garage, gated motor court, pool). Owner-only doors (HouseClient), garage showroom with Drive prompts, STASH pad in the garage, spawn in the living room. No hiding at home while wanted (moved out to the sale sign). Daily streak now waits for the client (DailyReady) so its stamp shows." },
		{ Date = "2026-10-25", Notes = "Guns (owner's call: full guns + PASSIVE): Shoreline Arms gun store by the downtown spawn; Coral 9 pistol $750, Riptide SMG $6,500 (rank 3), Breaker shotgun $9,500 (rank 5), Longshore rifle $16,000 (rank 8); police on duty carry a Duty Pistol that only hurts wanted citizens. Owned guns saved; infinite ammo with magazines and reloads; client-side hits checked by the server (rate, range, line of sight, who may hurt whom); hitting players = +1 star, a takedown +1 more; PASSIVE toggle next to PHONE (saved; not while wanted or within 15 s of a fight); 6 s spawn shield; health regen; kill feed; tutorial step 'Buy your first gun'. Sounds: ProSoundEffects 9mm pistol, Mini Uzi and AK-47 single shots (the shotgun is the AK slowed down) and a magazine reload, picked from Creator Store listings; every character's RightGripAttachment is reset to the standard -90 X turn so guns point forward on any avatar (Studio prints a held-right check); mobile layout checked at 5 screen sizes, FIRE stops when the thumb slides off." },
	},
}
