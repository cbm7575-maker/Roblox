-- BusinessService (ModuleScript, ServerScriptService.Services.BusinessService)
-- Empire: player-owned businesses (launch/10-BUSINESSES-PRD.md v2; every number and place in
-- Config.Businesses). The server decides everything here; BusinessClient only asks, and draws the cards, the
-- wash mini-game, the level props, the job HUD and the alerts. M1 = the foundation plus the Car Wash. M2 = Palm
-- Grind Coffee: its building and its job (RUSH ORDERS) are in the job module Services.BusinessJobs.Coffee
-- (see JOB MODULES below); the cold brew goes through the same customer path as the shine (CUSTOMERS). M3 = the
-- Backlot Print Shop, the first shady business: its building, its shift (PRINT and LAUNDER, the dirty cash) and
-- its POLICE RAIDS are all in the job module Services.BusinessJobs.PrintShop; this file only hands it the hooks
-- listed under JOB MODULES, saves its dirty cash and keeps it out of NPC break-ins. M4 = Coastline Boat Rentals
-- (Empire rank 2 to buy): its floating dock, its job (BOAT TOURS on water checkpoints) and its customer service
-- (the JET SKI RENTAL) are in the job module Services.BusinessJobs.BoatRentals; the rental is paid through this
-- file's customer path (CUSTOMERS), handed over as Api.serveCustomer. M5 = the Afterglow Nightclub (Empire rank 3 to
-- buy): its building, its job (VIP PICKUPS in the club's limo, with paparazzi), the club's inside (the COVER CHARGE and
-- the VIP BOOTH) and its shady BACK ROOM are in the job module Services.BusinessJobs.Nightclub; the back room's police
-- raids run on the Print Shop's raid code, now shared as Services.BusinessJobs.Raids. Here: its register fills
-- def.NightMult times as fast at night (settle, pushState: isNight), and the customer path takes the booth's own words.
--
-- LAUNCH SWITCH: runs in Studio always, in a live server only when Config.Businesses.Live is true. Off, Init
-- sets ReplicatedStorage attribute BusinessesOn = false and does nothing else (no buildings, no remotes), and
-- the phone hides the EMPIRE app.
--
-- OWNERSHIP AND SAVING
--   * Saved per player as data.businesses[id] = { level (1-5), register ($, may hold cents), lifetime (all the
--     owner ever earned from it: collections, their own job pay, crew cuts, customer money), jobsDone,
--     boughtAt (os.time), dirty (shady businesses only: the dirty cash in stock, M3) }, plus data.empireXP. DataService's default() has businesses = {} and empireXP = 0,
--     so an old save loads with none. Entries for businesses not Enabled in the config are left in the save
--     untouched and simply not used. Many players can own the same business; one of each per player.
--   * Player attributes: "Businesses" = owned ids, comma separated ("CarWash"; nil for none), "Empire" = Empire
--     rank 1-10, "EmpireXP", "EmpireTitle" ("Mogul" at 7, "Kingpin of the Coast" at 10; nil before),
--     "JobKind" = "BizWash" | "BizDetail" | "BizRush" | "BizPrint" | "BizLaunder" | "BizTour" | "BizVip" (any "Biz..." kind is a
--     business job) while on a business job (so missions, races, the Big
--     Score and the HUD treat you as busy, as with a taxi shift), "BizJob" = that business's id, "BizAlarm" =
--     ids of businesses with a break-in you should respond to (yours or a crewmate's; comma separated),
--     "ShineUntil" = server time your car stops sparkling, "ColdBrewUntil" = server time your cold brew wears
--     off (LocomotionClient's sprint drains slower until then), "BizRentalUntil" = server time your rented jet ski
--     goes back (M4), "BizTourHappy" = your boat tour's tourists' mood, 0-100 (M4, while on a tour).
--   * Buying (at the door, the buy card's BUY): Enabled, not owned yet, Empire rank >= the business's Unlock,
--     within Config.Reach of the lot, the cash (EconomyService.Spend, reason "bizbuy:<id>"). +Empire XP Buy,
--     ProgressService "BuyBusiness", saved right away.
--   * Upgrading (the manage card): one level at a time to 5, Businesses.UpgradePrice (40/60/80/100% of the
--     price), reason "bizupgrade:<id>:<level>". +Empire XP UpgradePerLevel x the new level. Saved right away.
--
-- THE REGISTER (trickle). Every Config.TickSeconds, and before every action, each owner in the server is
-- settled: Businesses.Accrue(the time since the last settle, x BusinessTimeScale in Studio), up to the
-- level's cap, +BusyBonus while one of the owner's crewmates is within Reach of the lot, x def.NightMult while it's
-- night (M5, the Nightclub: Workspace IsNight, or in Studio the override BizTestNight; the whole stretch since the
-- last settle counts as what it is at the settle, at most 90 s off at dusk and dawn). A player's clock
-- starts when their save loads and stops when they leave: nothing accrues offline. COLLECT at the business
-- (EconomyService.AddCash, reason "biz:<id>"), or from the phone ("Remote") at Empire rank RemoteCollect+.
-- "Full" toast once per crossing of the cap.
--
-- FEATURED OWNER. Per business, the highest-level owner in the server (ties: more lifetime, then the lower
-- UserId). Published as the building model's attributes FeaturedUserId / FeaturedName / FeaturedLevel and
-- Owners (JSON { [userId] = level } of every owner in the server), and for clients that don't have the
-- building streamed in as ReplicatedStorage attribute "BizOwners" = JSON { [id] = { f = featured UserId,
-- n = featured name, l = featured level, o = { [userId] = level } } }. The sign plate under the roof sign
-- reads "FOR SALE · $25,000" with no owner in the server, else "<Featured>'s Suds & Shine" (BusinessClient
-- re-dresses it on owners' and crewmates' devices).
--
-- EMPIRE XP (Config.Businesses.Empire): buy, upgrade, every finished job (the worker), every player customer
-- served (the featured owner), every break-in stopped (the owner). A rank-up sends BusinessResult RankUp
-- { Rank, Unlock } (the client stamps it) and updates the attributes.
--
-- THE BUILDING (Look 3.0: real materials, neon only after dark via tag "NightNeon", lamps "NightLamp"): one
-- Model per Enabled business in Workspace.Shops, "Business_<Id>", ModelStreamingMode Atomic. Attributes
-- BusinessId, PlaceName, PlaceKind = "Business" (+ the featured-owner ones above). Prompts: "BusinessDoor"
-- at the door (everyone; reach 10; BusinessClient relabels it), "BizShinePrompt" under the shine gantry
-- (InCar = true, so PromptGate shows it from a driver's seat; BusinessClient only shows it while you drive
-- your own car). LEVEL PROPS: child Models with attributes MinLevel / MaxLevel (nil = no limit); every part
-- in them gets tag "BizProp" and attributes BizId, MinLevel, MaxLevel, and never collides (each device shows
-- its own level: BusinessClient hides the props outside it). All solid parts stay inside the lot.
--
-- THE CARD. The door: an owner gets BusinessCard { Id, Mode = "Manage" }; a crewmate of an owner in the
-- server { Id, Mode = "Crew", Owner = UserId, OwnerName, Level }; anyone else (not a prisoner) { Id, Mode =
-- "Buy" }. Every card action is checked again here (at the business, alive, not in prison, owning it).
--
-- JOBS (citizens only, not wanted, not on a mission / race / Big Score / taxi shift; at the business, on foot):
--   For yourself if you own it, else for a crewmate who owns it and is in the server (forId picks which).
--   A crewmate gets the normal pay; the owner gets Config.CrewCut of it on top (paid by the game, reason
--   "bizcrewcut:<id>", BusinessResult CrewCut). Job pay uses the OWNER's level (JobMult) and RateScale. The
--   owner's jobsDone / lifetime count it. The worker gets the job's Empire XP.
--   * WASH: the server picks a free bay (Businesses.BayCount at the owner's level; one worker per bay across
--     every owner and crewmate at that building), rolls the customer (a first name from K.FIRST_NAMES, a special
--     one about 1 in 8: Businesses.RollSpecial) and every spot's dirt (Businesses.RollDirt), and sends
--     BusinessJob "Wash" { Id, Bay, Spots, Dirt (a dense list of "Mud" | "Bugs" | "Bird"), Special, Name,
--     Streak (★★★ washes in a row so far), Level, Owner, OwnerName, Ready (seconds until the car is in), Seed,
--     Count }. The customer car exists only on the worker's device. Steps come back as RequestBusiness("Step",
--     step, arg): "SprayOn" / "SprayOff", "Scrub" (arg = spot 1..Spots), "RinseOn" / "RinseOff". The server:
--     steps in order; nothing before the car is in; SPRAY and RINSE are timing gauges graded on the server's
--     clock (Businesses.WashGrade): EARLY (before the gauge's Min) didn't count, "WashStep" { Stage, Again =
--     true, Early = true } and the hold starts over; else PERFECT or OK, "WashStep" { Stage, Grade, Step } for
--     the spray (the rinse's grade rides on WashPaid); a scrub tap counts at most every ScrubGap seconds,
--     Businesses.WashTaps(its dirt) per spot; the worker within BayRange of the bay for every step. After the
--     rinse: under MinTime from "car in" that car isn't paid (warned; WashPaid with Pay 0 and Refused = true;
--     the job goes on, the streak back to 0), else paid: Businesses.WashPay (pay + the bird-mess spots; the
--     tip from the grades and the quick ★, the special's multipliers and the ★★★ streak), reason
--     "bizjob:<id>:wash", BusinessJob "WashPaid" { Pay, Tip, Stars, Grade (the rinse's), Perfects, Quick,
--     Streak, Mult (the streak's), Special, Name, Took, Count, Earned }. Then NEXT CAR ("Job" Wash again),
--     DELIVER ("Job" Detail) or END ("EndJob"). Walking further than LeaveRange from the bay (or sitting down)
--     for LeaveGrace seconds ends it ("LeftBay").
--   * DETAIL DELIVERY: a real customer car (CarBuilder, a Config.Detail.Cars pick for the owner's level)
--     appears on the PICK-UP box (refused "PickupBlocked" when something's on it) with the worker at the
--     wheel. Car attributes BizCar = true, BizDriverUserId, BizId; no OwnerUserId (so no taxi, race, garage,
--     ride or Chop Shop: the Chop Shop only buys CarBoostService's tracked cars), its DrivePrompt and
--     RidePrompt removed and a "BizDrivePrompt" ("Drive", the way back in; only the worker may sit, anyone
--     else is unseated). One in five (Detail.Sports.Chance) is a sports car from Detail.Sports.Cars instead.
--     The address: JobService.RoadsideSpot, DistMin-DistMax studs away (BusinessJob "Detail" { Id, Pos, Name,
--     Est, Car, Level, Sports, Streak (clean deliveries in a row so far), Owner }). Stop in its ring
--     (StopRadius, under StopSpeed): refused like a taxi fare when reached sooner than the straight line at the
--     car's nitro top speed x FastSlack or after VehicleGuard flagged it ("Invalid"); else Businesses.DetailPay
--     (speed tip less the dents, x1.5 for a sports car, the no-dent streak; dents: see Config.Detail), reason
--     "bizjob:<id>:detail", BusinessJob "DetailPaid" { Pay, Tip, Dents, Stars, Streak, Mult, Sports, Took,
--     Name, Count, Earned }. The worker is put out (VehicleService.EjectAll), the customer takes the car (it
--     goes HandOver seconds later: the worker's device draws them walking out to it), and the SHIFT GOES ON
--     (stage "back"): call your own car, drive back and START the next car or wash; IdleTime seconds without
--     one ends it ("NoNextCar"). Out of the car LeaveGrace seconds ("LeftCar"), the car gone or sunk
--     ("CarGone"), and the rules below end it too. The car always goes with the job (everyone in it put out
--     first: VehicleService.EjectAll).
--   * RUSH ORDERS (Palm Grind, M2): Services.BusinessJobs.Coffee runs it (JobKind "BizRush"); see its header.
--   * PRINT and LAUNDER (the Print Shop, M3): Services.BusinessJobs.PrintShop runs the shift (JobKind "BizPrint"
--     at the shop, "BizLaunder" on a run with the bags); see its header. A launder run is the one job being
--     wanted doesn't end (Module.KeepWanted): getting spotted is its risk, and the run goes on.
--   * Every job ends on: END JOB ("Player"), wanted ("Wanted"), off the Civilian side ("Side"), death or a new
--     character ("Died"), the owner leaving or no longer owning it ("OwnerLeft"), leaving the game. BusinessJob
--     "Ended" { Id, Reason, Jobs, Earned, XP (the shift's Empire XP), Kind (the last job kind: CONTINUE starts
--     it again), Owner (whose business), Report (the shift's numbers: the Car Wash's { Washes, Stars3,
--     Perfects, BestWash, Specials, Deliveries, Dents, Clean, BestDetail }; a job module's own, from its End
--     hook: Palm Grind's, or the Print Shop's Summary) }: BusinessClient's SHIFT REPORT card. "Dent" { Dents }
--     during a delivery. A rush job also ends when another job takes the JobKind attribute (a taxi shift
--     started on the way: "Busy"). Empire XP a worker earns during a shift (this file's, or a job module's
--     through Api.addEmpireXP) is counted on the job (job.xp) for the report.
--   * START JOB only offers (and the server only takes) the kinds in the business's Config Jobs list.
--
-- JOB MODULES (M2+): a business whose Style has a module in Services.BusinessJobs (Coffee, PrintShop) gets its
-- building from Module.Style(model, frame, def, Api) and its job from Module.Start / Step / Tick / Resend
-- (player, job, ..., Api). Api is this file's own helpers, handed over in Init (levelOf, creditOwner,
-- addEmpireXP, progressEvent, endJob, refuse, pushState, fire = BusinessJob to the worker, result =
-- BusinessResult to anyone, service, owned, sameCrew, play (a player's play clock), the Build helpers...).
-- A module that won't load leaves its business unbuilt (a warning in Output), never the others. Optional hooks
-- (M3), every one called in a pcall so a broken module never stops the rest:
--   Module.Kinds = { [job kind] = JobKind attribute } the kinds it runs (Coffee: Rush = "BizRush"; the Print
--     Shop: Print = "BizPrint", Launder = "BizLaunder"). job.mod is the module, job.jobKind the attribute it set.
--   Module.Switch(player, job, kind, A)  START JOB with another of its kinds while on the job (Print <-> Launder)
--   Module.KeepWanted(job) -> true: being wanted doesn't end the job right now (a launder run with the bags)
--   Module.End(player, job, reason, A) -> extra fields for BusinessJob "Ended" (the Print Shop's shift Summary,
--     Palm Grind's Report: the shift report card)
--   Module.Init(A)            once, after every building is up (the Print Shop's raid prompts and remotes)
--   Module.Second(dt, A)      once a second, with the break-ins (the Print Shop's raids, Palm Grind's rush hours)
--   Module.State(player, def, entry) -> extra fields for that business in BusinessState (Dirty, Raid...)
--   Module.Alarms(player) -> business ids to add to the player's BizAlarm (a raid they're part of)
--   Module.PlayerLeft(player, A)  before this file forgets them
--   Module.Debug(player, cmd, id, value, A) -> an answer string for a Studio helper it knows, else nil
--   Module.Service(player, def, A)  its business's customer purchase at the BizServicePrompt (M4: Boat Rentals'
--     jet ski rental; M5: the Nightclub's cover charge; it pays through A.serveCustomer)
--   Module.Request(player, def, arg, arg2, A)  RequestBusiness("Mod", id, arg, arg2): a request of its own (M5: the
--     Nightclub's LEAVE inside the club)
-- (M5 Api: isNight() = night for the businesses, featuredOf(id) = the featured owner and their entry; serveCustomer
-- takes a 5th argument, the words for the owner's toast, when a business sells more than its Service: the VIP booth.)
--
-- CUSTOMERS (PRD section 6). Every player purchase goes through serveCustomer: Spend the price ("biz<kind>:
-- <id>"), then the featured owner (if in the server and not the buyer) gets Businesses.Split's share
-- ("bizcustomer:<id>"), Empire XP Customer (Businesses.CustomerXP: at most CustomerPerBuyerHour times an hour
-- per buyer) and BusinessResult Customer { Buyer, Amount, Service = the Config Service Words }; the rest is a
-- sink. An owner buying at their own business pays and the game keeps it all.
--   * DRIVE-THROUGH SHINE: BizShinePrompt (anyone in the driver's seat of their own land car, within
--     Shine.Reach of the gantry, under Shine.MaxSpeed). Player attribute ShineUntil = now + Shine.Seconds; the
--     buyer gets Shined { Price, Until, Owner }. Refused while more than RebuyLeft is left ("ShineAlready").
--   * COLD BREW (Palm Grind): BizServicePrompt at the counter's ORDER HERE spot (anyone on foot, alive, not a
--     prisoner, within ColdBrew.Reach). ColdBrewUntil = now + ColdBrew.Seconds; the buyer gets ColdBrew
--     { Price, Until, Owner }. Refused seated ("ColdBrewOnFoot") or while more than RebuyLeft is left
--     ("ColdBrewAlready").
--   * JET SKI RENTAL (Boat Rentals, M4): BizServicePrompt at the JET SKI RENTALS stand; the job module's Service
--     runs it (BusinessJobs.BoatRentals: the checks, the jet ski for Rental.Seconds, its timer and its end) and
--     pays through serveCustomer ("bizrental:<id>").
--   * COVER CHARGE and VIP BOOTH (the Nightclub, M5): BizServicePrompt at the velvet rope (the job module's Service:
--     into the club's inside, "bizcover:<id>") and the booth's own prompt inside ("bizbooth:<id>", words "a VIP booth").
--
-- NPC BREAK-INS (Config.BreakIn): per owner, a play clock (seconds in the server, x BusinessTimeScale in
-- Studio). First possible at MinPlay + a random part of Window, then Gap + a random part of Window after the
-- last one. Due, it picks the owner's legit business (Businesses.BreakInEligible: never a shady one, which gets
-- police raids instead) with the fullest register (MinRegister+), only while the
-- owner is a living citizen (else tried again Retry later). 1-2 robbers (PedService's looks, a dark beanie
-- and bandana; Workspace.NPCs, model "BizRobber", attributes NPCKind = "BizRobber", AimTarget, BizId,
-- BizOwner, Pose) appear at the register. The owner and their crewmates get BusinessResult BreakIn { Id,
-- Until (server time), Owner, OwnerName, Robbers } and BizAlarm. A gun pointed at one (BusinessClient asks:
-- RequestBusiness("Scare", nil, model); checked here: the owner or a crewmate, a citizen on foot, a gun in
-- hand, within ScareReach, facing it) puts its hands up and it runs; a punch or a shot (CombatService routes
-- hits on NPCKind "BizRobber" to BusinessService.NPCHit) knocks it down. Either way the one who stopped it gets
-- Reward ("bizbreakin:<id>", RobberStopped { Reward, Left }); all stopped: the owner gets Empire XP BreakIn and
-- everyone involved BreakInStopped. Anyone else's gun or fists do nothing to them. Time runs out: they take
-- Businesses.BreakInLoss of that owner's register and leave (BreakInLost { Amount }). The owner leaving ends it
-- with nothing lost.
--
-- REMOTES
--   RequestBusiness(action, id, arg, arg2) (client -> server, rate-limited): "State"; "Buy" (id); "Collect"
--     (id, arg "Remote" from the phone); "Upgrade" (id); "Job" (id, arg "Wash" | "Detail" | "Rush" | "Print" |
--     "Launder", arg2 = the owner's UserId when working for a crewmate); "EndJob"; "Step" (id = the step name,
--     arg = a spot: the wash's; a module job's own steps: the rush job's "GrabOn" / "GrabOff", the Print Shop's
--     "HoldOn" / "HoldOff"); "Scare" (arg = a robber model); "Mod" (id, arg, arg2: the business's job module's own
--     request, Module.Request: M5, the Nightclub's "Leave").
--   BusinessCard { Id, Mode, Owner, OwnerName, Level }; BusinessState { At (server time), Scale, XP, Rank,
--     List = { [id] = { Level, Register, Cap, Rate ($/min now, busy included), Busy, Lifetime, JobsDone, Next
--     (the next upgrade's price, nil at 5) } } (on join, after every action, every tick);
--   BusinessResult { Kind, Id, ... }: Bought, Upgraded { Level }, Collected { Amount, Remote }, Full, Customer
--     { Buyer, Amount, Service }, Shined { Price, Until, Owner }, ColdBrew { Price, Until, Owner }, CrewCut
--     { Worker, Amount }, BreakIn, RobberStopped, BreakInStopped { OwnerName }, BreakInLost { Amount, OwnerName },
--     RankUp { Rank, Unlock }, No { Reason: TooFar, Owned, Locked, Empty, MaxLevel, NotYours, BaysBusy,
--     JobElsewhere, OnDelivery, OnRush, PickupBlocked, NoAddress, NoCar, RemoteRank, ShineOwnCar, ShineStop,
--     ShineAlready, ColdBrewOnFoot, ColdBrewAlready }.
--   BusinessJob (server -> worker): "Wash", "WashStep", "WashPaid", "Detail", "Dent", "DetailPaid", "Ended";
--     rush orders (Coffee): "Rush", "RushStep", "RushLeg", "RushPaid"; the Print Shop's: see PrintShop's header;
--     boat tours (BoatRentals, M4): "Tour", "TourSeat", "TourGo", "TourStop", "TourPhotoOn", "TourPhoto",
--     "TourMood", "TourPaid" (see its header).
--   BusinessResult also carries the Print Shop's raid news (Raid, RaidBreached, RaidSeized, RaidHeld, RaidOver)
--     and its refusals (No: StockFull, NoStock, NotInBay, BagsAway); Boat Rentals' rental news (Rented, RentalWarn,
--     RentalOver) and refusals (No: NoBoat, BerthBlocked, RentCivOnly, RentWanted, RentOnFoot, RentAlready,
--     RentBusy).
--   Notify keys reused: NotEnoughCash, ActivityCivOnly, ActivityWanted, MissionBusy, GetOutFirst.
--
-- STUDIO ONLY (RunService:IsStudio()):
--   Workspace attribute BusinessTimeScale (number): register and break-in clocks run that many times faster
--     (60 = a minute a second). The break-in's own 2-minute timer is not scaled.
--   Workspace attribute BizTestCrew = true: every two players count as crewmates here and in BusinessClient
--     (false / nil: only real crews). Set it from the server Command Bar, or Debug "crew".
--   BusinessService.Debug(player, cmd, id, value): player = a Player or a player's Name ("$me" through
--     DebugService). Through DebugService's NCCmd, e.g.
--       workspace:SetAttribute("NCCmd", '["call","BusinessService","Debug","$me","level","CarWash",3]')
--     cmd: "state", "give" (own it free), "remove", "level" (value 1-5), "fill" (register to its cap),
--     "register" (value), "xp" (value: add Empire XP), "cash" (value: add cash), "breakin" (now, at id or the
--     fullest business; value = seconds on its timer; tops the register up to MinRegister), "crew" (value
--     true / false), "scale" (value), "shine" (clear your ShineUntil), "coldbrew" (clear your ColdBrewUntil),
--     "vip" (your next rush order ends at a VIP home, whatever the level), "next" (value "Muddy" | "Classic" |
--     "Wedding": your next wash customer is that special one; "Sports": your next delivery is a sports car; kept
--     as your player attribute BizTestNext until used). Palm Grind's own (Coffee.Debug): "rushhour" (a rush
--     hour at your café now; value = seconds, default RushHour.Length). Returns a short answer string.
--     The Print Shop's own (PrintShop.Debug, see its header): "dirty" (value: your stock), "raid" (a warrant at
--     your Print Shop now; value "ai" for the AI raid, or seconds on the warrant), "endraid", "testcop" (value: a
--     player's Name who counts as an on-duty cop for raids, "" for none), "heat" (value 0-1: your launder run's
--     heat meter). M4: "rank" (value 1-10: your Empire rank, set exactly; to test the Empire 2 unlock); Boat
--     Rentals' own (BoatRentals.Debug): "tour" (value "Celebrity" | "Fishing" | "Sunset": your next tour is that
--     special one; "" clears it), "route" (value a route Id), "mood" (value 0-1: your tour's tourists now),
--     "rentleft" (value seconds: your jet ski rental's time left). M5, the Nightclub's own (Nightclub.Debug): "celeb",
--     "papz", "comfort", "night", "pickup", "backroom", "washready", "booth", "club", and "raid" / "endraid" with id
--     "Nightclub" (see its header).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local BusinessService = {}

local W = Businesses.Wash
local D = Businesses.Detail
local B = Businesses.BreakIn
local E = Businesses.Empire
local SH = Businesses.Shine

-- Constants that aren't balance (balance lives in Config.Businesses).
local K = {
	SEAT_UP = 3.4, -- a car's pivot above the lot's ground (0.2 slab + VehicleService's 3.2)
	ROBBER_SPEED = 16, -- studs/s a robber runs out at
	DOWN_TIME = 4, -- seconds a knocked-down robber lies there before fading
	SINK_TIME = 2, -- seconds a customer car may sit in the water
	NAMES = { "Mrs. Alvarez", "Dr. Patel", "Coach Rivera", "Ms. Okafor", "Mr. Delgado", "Captain Shaw", "Aunt Rosa",
		"DJ Marlo", "Señor Vega", "Miss Kim", "Uncle Jimmy", "Professor Lane" },
	-- Wash customers (the tag on the car: "Carla's sedan"; short, so the tag and the strip fit).
	FIRST_NAMES = { "Carla", "Marco", "Tasha", "Luis", "Jenny", "Omar", "Rosa", "Dev", "Kiki", "Andre", "Paula", "Benny",
		"Nina", "Hector", "Yara", "Sam", "Lupe", "Theo", "Gabi", "Rico" },
	BEANIE = Color3.fromRGB(28, 28, 32),
	BANDANA = Color3.fromRGB(36, 40, 52),
}

local R = {} -- remotes: notify, card, state, result, job
local S = {
	on = false,
	sites = {}, -- [id] = { model, def, plate (TextLabel) }
	lastSettle = {}, -- [player] = os.clock() of their last settle (nil until their save loads)
	flags = {}, -- [player] = { [id] = { full } }
	play = {}, -- [player] = seconds of play this session (x BusinessTimeScale)
	breakins = {}, -- [player (owner)] = { nextAt (play seconds), active = rec or nil }
	robbers = {}, -- [model] = { model, root, hum, state, rec, token, sayToken }
	jobs = {}, -- [player (worker)] = job
	bays = {}, -- [id] = { [bay] = player }
	ownersJson = nil,
	rng = Random.new(),
	customerXP = setmetatable({}, { __mode = "k" }), -- [featured owner] = { [buyer UserId] = { since, count } }
	forceVip = setmetatable({}, { __mode = "k" }), -- [player] = true: their next rush order gets a VIP stop (Debug "vip")
}
local Jobs = {} -- the job modules (Services.BusinessJobs.<Style>), loaded in Init: see JOB MODULES
local Api = {} -- what those modules may use of this file (filled in Init)

------------------------------------------------------------------ small helpers

local function service(name)
	local module = ServerScriptService.Services:FindFirstChild(name)
	if not module then
		return nil
	end
	local ok, mod = pcall(require, module)
	return ok and type(mod) == "table" and mod or nil
end

-- A ProgressService event in its own thread (goal listeners can never undo what just happened).
local function progressEvent(player, kind, amount)
	task.spawn(function()
		local progress = service("ProgressService")
		if progress and type(progress.Event) == "function" then
			progress.Event(player, kind, amount)
		end
	end)
end

-- Studio only: Workspace attribute BusinessTimeScale (see the header).
local function timeScale()
	if not RunService:IsStudio() then
		return 1
	end
	local s = Workspace:GetAttribute("BusinessTimeScale")
	if type(s) == "number" and s == s and s > 0 then
		return math.clamp(s, 0.01, 10000)
	end
	return 1
end

local function testCrew()
	return RunService:IsStudio() and Workspace:GetAttribute("BizTestCrew") == true
end

-- Is it night for the businesses (M5: the Nightclub's x2)? Workspace IsNight; in Studio BizTestNight overrides it.
local function isNight()
	local test = nil
	if RunService:IsStudio() then
		test = Workspace:GetAttribute("BizTestNight") -- (false must stay false: day on demand)
	end
	return Businesses.NightNow(Workspace:GetAttribute("IsNight"), test)
end

local function num(v, default)
	if type(v) == "number" and v == v and v > -math.huge and v < math.huge then
		return v
	end
	return default
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function humOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function alive(player)
	local hum = humOf(player)
	return hum ~= nil and hum.Health > 0
end

local function money(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return "$" .. s
end

-- Two different players in the same crew (or, in Studio with BizTestCrew, any two players).
local function sameCrew(a, b)
	if not a or not b or a == b then
		return false
	end
	if testCrew() then
		return true
	end
	local crew = a:GetAttribute("Crew")
	return crew ~= nil and crew == b:GetAttribute("Crew")
end

local function result(player, info)
	if player and player.Parent == Players and R.result then
		R.result:FireClient(player, info)
	end
end

local function refuse(player, id, reason)
	result(player, { Kind = "No", Id = id, Reason = reason })
end

local function notifyKey(player, key)
	if player.Parent == Players and R.notify then
		R.notify:FireClient(player, key)
	end
end

local function npcFolder()
	local folder = Workspace:FindFirstChild("NPCs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "NPCs"
		folder.Parent = Workspace
	end
	return folder
end

------------------------------------------------------------------ saved state

local function fresh()
	return { level = 1, register = 0, lifetime = 0, jobsDone = 0, boughtAt = os.time() }
end

-- Make one saved entry safe to use (a hand-edited save, a level removed from the config...).
local function sanitize(entry)
	entry.level = Businesses.ClampLevel(num(entry.level, 1))
	entry.register = math.max(0, num(entry.register, 0))
	entry.lifetime = math.max(0, num(entry.lifetime, 0))
	entry.jobsDone = math.max(0, math.floor(num(entry.jobsDone, 0)))
	entry.boughtAt = num(entry.boughtAt, 0)
	if entry.dirty ~= nil then
		entry.dirty = math.max(0, num(entry.dirty, 0)) -- (M3: a shady business's dirty cash)
	end
	return entry
end

-- This player's entry for an Enabled business they own (nil otherwise), their data, the def.
local function owned(player, id)
	local def = Businesses.ById[id]
	local data = DataService.Get(player)
	local list = data and data.businesses
	local entry = type(list) == "table" and list[id] or nil
	if def and def.Enabled and type(entry) == "table" then
		return entry, data, def
	end
	return nil, data, def
end

local function levelOf(player, def)
	local entry = player and owned(player, def.Id)
	return entry and entry.level or 1
end

local function empireXP(player)
	local data = DataService.Get(player)
	return data and math.max(0, num(data.empireXP, 0)) or 0
end

local function empireRank(player)
	return Businesses.RankFor(empireXP(player))
end

local function publishOwned(player)
	if player.Parent ~= Players then
		return
	end
	local ids = {}
	for _, def in ipairs(Businesses.List) do
		if owned(player, def.Id) then
			table.insert(ids, def.Id)
		end
	end
	player:SetAttribute("Businesses", #ids > 0 and table.concat(ids, ",") or nil)
	local xp = empireXP(player)
	local rank = Businesses.RankFor(xp)
	player:SetAttribute("EmpireXP", math.floor(xp))
	player:SetAttribute("Empire", rank)
	player:SetAttribute("EmpireTitle", Businesses.TitleFor(rank))
end

-- Is this JobKind attribute one of ours (a business job: "BizWash", "BizRush", "BizPrint"...)?
local function isBizKind(kind)
	return type(kind) == "string" and string.sub(kind, 1, 3) == "Biz"
end

local function flagsFor(player, id)
	S.flags[player] = S.flags[player] or {}
	S.flags[player][id] = S.flags[player][id] or {}
	return S.flags[player][id]
end

------------------------------------------------------------------ the featured owner

local function featuredOf(id)
	local best, bestEntry
	for _, p in ipairs(Players:GetPlayers()) do
		local entry = owned(p, id)
		if entry then
			local better = not best or entry.level > bestEntry.level
				or (entry.level == bestEntry.level and (entry.lifetime > bestEntry.lifetime
					or (entry.lifetime == bestEntry.lifetime and p.UserId < best.UserId)))
			if better then
				best, bestEntry = p, entry
			end
		end
	end
	return best, bestEntry
end

-- The featured owners and every owner's level, on the buildings and in ReplicatedStorage "BizOwners".
local function publishOwners()
	local all = {}
	for _, def in ipairs(Businesses.List) do
		if def.Enabled then
			local f, fe = featuredOf(def.Id)
			local o = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local e = owned(p, def.Id)
				if e then
					o[tostring(p.UserId)] = e.level
				end
			end
			all[def.Id] = { f = f and f.UserId or nil, n = f and f.DisplayName or nil, l = fe and fe.level or nil, o = o }
			local site = S.sites[def.Id]
			if site and site.model.Parent then
				local m = site.model
				m:SetAttribute("FeaturedUserId", f and f.UserId or nil)
				m:SetAttribute("FeaturedName", f and f.DisplayName or nil)
				m:SetAttribute("FeaturedLevel", fe and fe.level or nil)
				local json = HttpService:JSONEncode(o)
				if m:GetAttribute("Owners") ~= json then
					m:SetAttribute("Owners", json)
				end
				if site.plate then
					local text = f and (f.DisplayName .. "'s " .. (def.Brand or def.Name)) or ("FOR SALE · " .. money(def.Price))
					if site.plate.Text ~= text then
						site.plate.Text = text
					end
				end
			end
		end
	end
	local json = HttpService:JSONEncode(all)
	if json ~= S.ownersJson then
		S.ownersJson = json
		ReplicatedStorage:SetAttribute("BizOwners", json)
	end
end

------------------------------------------------------------------ Empire XP

local function addEmpireXP(player, amount)
	local data = DataService.Get(player)
	amount = math.floor(num(amount, 0))
	if not data or amount <= 0 then
		return
	end
	local before = Businesses.RankFor(data.empireXP)
	data.empireXP = math.max(0, num(data.empireXP, 0)) + amount
	local after = Businesses.RankFor(data.empireXP)
	publishOwned(player)
	if after > before then
		for r = before + 1, after do
			result(player, { Kind = "RankUp", Rank = r, Unlock = E.Unlocks[r] })
		end
		Telemetry.Custom(player, "EmpireRank_" .. after, after)
	end
end

------------------------------------------------------------------ the register

local function atLot(player, def)
	local root = rootOf(player)
	if not root then
		return false
	end
	local d = root.Position - def.Position
	return math.abs(d.Y) < 25 and flat(d).Magnitude <= Businesses.Reach
end

-- Is one of this owner's crewmates at this business right now (the busy-shop bonus)?
local function crewmateAt(owner, def)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= owner and sameCrew(owner, p) and alive(p) and atLot(p, def) then
			return true
		end
	end
	return false
end

-- Bring every register this player owns up to now. Returns true if anything changed.
local function settle(player)
	local data = DataService.Get(player)
	local last = S.lastSettle[player]
	if not data or not last then
		return false
	end
	local t = os.clock()
	S.lastSettle[player] = t
	local seconds = math.clamp(t - last, 0, Businesses.TickSeconds * 3) * timeScale()
	local changed = false
	local night = isNight()
	for _, def in ipairs(Businesses.List) do
		local entry = owned(player, def.Id)
		if entry and seconds > 0 then
			local register, earned = Businesses.Accrue(def, entry.register, entry.level, seconds, crewmateAt(player, def), night)
			if earned > 0 then
				entry.register = register
				changed = true
			end
			local f = flagsFor(player, def.Id)
			if entry.register >= Businesses.Cap(def, entry.level) then
				if not f.full then
					f.full = true
					result(player, { Kind = "Full", Id = def.Id })
				end
			else
				f.full = false
			end
		end
	end
	return changed
end

-- What the cards and the EMPIRE app need (see the header).
local function pushState(player)
	if player.Parent ~= Players or not DataService.Get(player) or not R.state then
		return
	end
	local list = {}
	local night = isNight()
	for _, def in ipairs(Businesses.List) do
		local entry = owned(player, def.Id)
		if entry then
			local busy = crewmateAt(player, def)
			list[def.Id] = {
				Level = entry.level,
				Register = math.floor(entry.register * 100) / 100,
				Cap = Businesses.Cap(def, entry.level),
				Rate = Businesses.Trickle(def, entry.level, busy, night),
				Busy = busy,
				Lifetime = math.floor(entry.lifetime),
				JobsDone = entry.jobsDone,
				Next = Businesses.UpgradePrice(def, entry.level),
			}
			-- A job module's own numbers for it (the Print Shop: Dirty, Stock, Carry, the raid on it).
			local mod = Jobs[def.Style or ""]
			if mod and type(mod.State) == "function" then
				local ok, extra = pcall(mod.State, player, def, entry)
				for k, v in pairs(ok and type(extra) == "table" and extra or {}) do
					list[def.Id][k] = v
				end
			end
		end
	end
	local xp = empireXP(player)
	R.state:FireClient(player, {
		At = Workspace:GetServerTimeNow(), Scale = timeScale(), List = list, XP = math.floor(xp), Rank = Businesses.RankFor(xp),
	})
end

------------------------------------------------------------------ owner actions

local function canAct(player, def)
	if player:GetAttribute("Side") == "Prisoner" or not alive(player) then
		return false
	end
	if not atLot(player, def) then
		refuse(player, def.Id, "TooFar")
		return false
	end
	return true
end

local function buy(player, def)
	local data = DataService.Get(player)
	if not data or not def.Enabled or not canAct(player, def) then
		return
	end
	if type(data.businesses) ~= "table" then
		data.businesses = {}
	end
	if owned(player, def.Id) then
		refuse(player, def.Id, "Owned")
		return
	end
	if not Businesses.Unlocked(def, empireRank(player)) then
		refuse(player, def.Id, "Locked")
		return
	end
	if not EconomyService.Spend(player, def.Price, "bizbuy:" .. def.Id) then
		notifyKey(player, "NotEnoughCash")
		return
	end
	settle(player) -- (the others up to now: the new one starts its clock here)
	data.businesses[def.Id] = fresh()
	flagsFor(player, def.Id).full = false
	addEmpireXP(player, E.XP.Buy)
	publishOwned(player)
	result(player, { Kind = "Bought", Id = def.Id })
	Telemetry.Custom(player, "BizBought_" .. def.Id, def.Price)
	progressEvent(player, "BuyBusiness", 1)
	task.spawn(DataService.SaveNow, player) -- a big purchase: save it right away
	pushState(player)
	publishOwners()
end

local function collect(player, def, remote)
	local entry = owned(player, def.Id)
	if not entry then
		return
	end
	if remote then
		if player:GetAttribute("Side") == "Prisoner" then
			return
		end
		if empireRank(player) < E.RemoteCollect then
			refuse(player, def.Id, "RemoteRank")
			return
		end
	elseif not canAct(player, def) then
		return
	end
	settle(player)
	local amount = math.floor(entry.register)
	if amount <= 0 then
		refuse(player, def.Id, "Empty")
		return
	end
	entry.register -= amount
	entry.lifetime += amount
	EconomyService.AddCash(player, amount, "biz:" .. def.Id)
	flagsFor(player, def.Id).full = false
	result(player, { Kind = "Collected", Id = def.Id, Amount = amount, Remote = remote == true })
	Telemetry.Custom(player, "BizCollect_" .. def.Id, amount)
	progressEvent(player, "BusinessCollect", amount)
	pushState(player)
end

local function upgrade(player, def)
	local entry = owned(player, def.Id)
	if not entry or not canAct(player, def) then
		return
	end
	settle(player)
	local price = Businesses.UpgradePrice(def, entry.level)
	if not price then
		refuse(player, def.Id, "MaxLevel")
		return
	end
	if not EconomyService.Spend(player, price, "bizupgrade:" .. def.Id .. ":" .. (entry.level + 1)) then
		notifyKey(player, "NotEnoughCash")
		return
	end
	entry.level += 1
	flagsFor(player, def.Id).full = entry.register >= Businesses.Cap(def, entry.level)
	addEmpireXP(player, E.XP.UpgradePerLevel * entry.level)
	result(player, { Kind = "Upgraded", Id = def.Id, Level = entry.level })
	Telemetry.Custom(player, "BizUpgrade_" .. def.Id, entry.level)
	progressEvent(player, "BusinessUpgrade", entry.level)
	task.spawn(DataService.SaveNow, player)
	pushState(player)
	publishOwners()
end

------------------------------------------------------------------ jobs: shared

local function releaseBay(player)
	for _, bays in pairs(S.bays) do
		for i, p in pairs(bays) do
			if p == player then
				bays[i] = nil
			end
		end
	end
end

-- A free wash bay at this building for this worker (owner's level decides how many are open), or nil.
local function freeBay(def, level, player)
	S.bays[def.Id] = S.bays[def.Id] or {}
	local bays = S.bays[def.Id]
	-- From the owner's highest open bay down: a worker for a level-3 owner who took bay 1 used to lock every
	-- level-1 owner (one bay) out with bays 2 and 3 free. Higher bays go to whoever can use them first.
	for i = Businesses.BayCount(def, level), 1, -1 do
		local p = bays[i]
		local stale = p ~= nil and (p.Parent ~= Players or not S.jobs[p] or S.jobs[p].bay ~= i or S.jobs[p].id ~= def.Id)
		if p == nil or p == player or stale then
			bays[i] = player
			return i
		end
	end
	return nil
end

-- The customer car goes (anyone in it put out beside it first).
local function destroyCar(job)
	local car = job.car
	job.car = nil
	if car and car.Parent then
		local vs = service("VehicleService")
		if vs and type(vs.EjectAll) == "function" then
			pcall(vs.EjectAll, car)
		end
		task.delay(0.15, function()
			if car.Parent then
				car:Destroy()
			end
		end)
	end
end

-- A job module's End hook (JOB MODULES): its last word on the job (the Print Shop's bags, its shift summary).
-- Returns the extra fields it wants in BusinessJob "Ended", or nil.
local function moduleEnd(player, job, reason)
	local mod = job.mod
	if not mod or type(mod.End) ~= "function" then
		return nil
	end
	local ok, extra = pcall(mod.End, player, job, reason, Api)
	if not ok then
		warn("[BusinessService] job module End: " .. tostring(extra))
		return nil
	end
	return type(extra) == "table" and extra or nil
end

local function endJob(player, reason)
	local job = S.jobs[player]
	if not job then
		return
	end
	S.jobs[player] = nil
	releaseBay(player)
	destroyCar(job)
	local extra = moduleEnd(player, job, reason)
	if player.Parent == Players then
		if isBizKind(player:GetAttribute("JobKind")) then
			player:SetAttribute("JobKind", nil)
		end
		player:SetAttribute("BizJob", nil)
		-- The shift report (see the header): the Car Wash's numbers here; a job module's come from its End hook.
		local info = { Id = job.id, Reason = reason, Jobs = job.count, Earned = job.earned, XP = job.xp or 0, Kind = job.kind,
			Owner = job.owner and job.owner.UserId or nil }
		local st = job.stats
		if st and not job.mod then
			info.Report = {
				Washes = st.washes, Stars3 = st.stars3, Perfects = st.perfects, BestWash = st.bestWash, Specials = st.specials,
				Deliveries = st.deliveries, Dents = st.dents, Clean = st.clean, BestDetail = st.bestDetail,
			}
		end
		for k, v in pairs(extra or {}) do
			info[k] = v
		end
		R.job:FireClient(player, "Ended", info)
	end
end

-- Why this player can't start a job right now (a Notify key), or nil.
local function jobBlocked(player)
	if player:GetAttribute("Side") ~= "Civilian" then
		return "ActivityCivOnly"
	elseif (player:GetAttribute("Heat") or 0) > 0 then
		return "ActivityWanted"
	end
	local kind = player:GetAttribute("JobKind")
	if player:GetAttribute("Mission") or player:GetAttribute("RacingId") or player:GetAttribute("BigScore")
		or (kind ~= nil and not isBizKind(kind)) then
		return "MissionBusy" -- one thing at a time (as JobService and MissionService refuse)
	end
	return nil
end

-- Whom a job here would be for: yourself if you own it, else a crewmate in the server who does (forId first,
-- then the highest level).
local function jobOwner(player, def, forId)
	if owned(player, def.Id) then
		return player
	end
	local want = tonumber(forId)
	local best, bestLevel
	for _, p in ipairs(Players:GetPlayers()) do
		local entry = p ~= player and owned(p, def.Id)
		if entry and sameCrew(player, p) then
			if want and p.UserId == want then
				return p
			end
			if not best or entry.level > bestLevel then
				best, bestLevel = p, entry.level
			end
		end
	end
	return best
end

-- A job's pay reaches the owner's books: their jobsDone and lifetime, and a crewmate's job pays them the cut.
local function creditOwner(job, worker, amount)
	local owner = job.owner
	local entry = owner and owner.Parent == Players and owned(owner, job.id)
	if not entry then
		return
	end
	entry.jobsDone += 1
	if owner == worker then
		entry.lifetime += amount
		return
	end
	local cut = Businesses.CrewCutFor(amount)
	if cut > 0 then
		EconomyService.AddCash(owner, cut, "bizcrewcut:" .. job.id)
		entry.lifetime += cut
		result(owner, { Kind = "CrewCut", Id = job.id, Worker = worker.DisplayName, Amount = cut })
		Telemetry.Custom(owner, "BizCrewCut_" .. job.id, cut)
	end
end

-- Empire XP for this player, counted on the shift they're on (job.xp: the shift report). Job modules get it as
-- Api.addEmpireXP.
local function jobXP(player, amount)
	addEmpireXP(player, amount)
	local job = S.jobs[player]
	amount = math.floor(num(amount, 0))
	if job and amount > 0 then
		job.xp = (job.xp or 0) + amount
	end
end

-- The Car Wash shift's numbers for the report (made on first use).
local function statsOf(job)
	job.stats = job.stats or { washes = 0, stars3 = 0, perfects = 0, bestWash = 0, specials = 0, deliveries = 0, dents = 0,
		clean = 0, bestDetail = 0 }
	return job.stats
end

-- Studio only (Debug "next"): the special customer or sports car this player's next car should be, used up here.
local function takeTestNext(player, want)
	if not RunService:IsStudio() then
		return nil
	end
	local v = player:GetAttribute("BizTestNext")
	if type(v) ~= "string" then
		return nil
	end
	local isSports = v == "Sports"
	if (want == "Sports") ~= isSports or (not isSports and not W.Specials[v]) then
		return nil
	end
	player:SetAttribute("BizTestNext", nil)
	return v
end

------------------------------------------------------------------ jobs: the wash bay

local function nextWash(player, job, level)
	local now = os.clock()
	job.kind = "Wash"
	job.stage = "spray"
	job.readyAt = now + W.ArriveTime + (job.washes and job.washes > 0 and W.DepartTime or 0)
	job.holdAt = nil
	job.grades = {}
	-- The customer (rolled here: the money depends on it). A special one has its own spots and dirt odds.
	job.special = takeTestNext(player, "Special") or Businesses.RollSpecial(S.rng:NextNumber(), S.rng:NextNumber())
	local sp = job.special and W.Specials[job.special]
	local range = sp and sp.Spots or W.Spots
	job.spots = S.rng:NextInteger(range[1], range[2])
	job.dirt = {}
	for s = 1, job.spots do
		job.dirt[s] = Businesses.RollDirt(S.rng:NextNumber(), job.special)
	end
	job.customer = K.FIRST_NAMES[S.rng:NextInteger(1, #K.FIRST_NAMES)]
	job.taps = {}
	job.lastTap = 0
	job.awaySince = nil
	R.job:FireClient(player, "Wash", {
		Id = job.id, Bay = job.bay, Spots = job.spots, Dirt = job.dirt, Special = job.special, Name = job.customer,
		Streak = job.washStreak or 0, Level = level, Owner = job.owner.UserId, OwnerName = job.owner.DisplayName,
		Ready = job.readyAt - now, Seed = S.rng:NextInteger(1, 1000000), Count = job.count,
		Departing = job.washes ~= nil and job.washes > 0,
	})
end

local function inBay(player, job)
	local root = rootOf(player)
	local bay = job.bay and Businesses.BayCFrame(job.def, job.bay)
	if not root or not bay then
		return false
	end
	return flat(root.Position - bay.Position).Magnitude <= W.BayRange and math.abs(root.Position.Y - bay.Position.Y) < 20
end

-- The server's stage (and every spot's counted taps, a dense list) back to the worker's device: after a
-- stage change, or "Again" when a step didn't count (a hold let go early, a step out of order), so the
-- mini-game puts itself back where the server is.
local function stepReply(player, job, again, extra)
	local taps = {}
	for s = 1, job.spots or 0 do
		taps[s] = job.taps and job.taps[s] or 0
	end
	local info = { Stage = job.stage, Again = again == true, Taps = taps }
	for k, v in pairs(extra or {}) do
		info[k] = v
	end
	R.job:FireClient(player, "WashStep", info)
end

local function finishWash(player, job)
	local total = os.clock() - job.readyAt
	if total < W.MinTime then
		-- Faster than any human can wash: that car isn't paid, but the job goes on (a quick honest player who
		-- just scraped under the line loses one car, not the shift). The AFTER panel shows NOT PAID.
		warn(string.format("[BusinessService] refused %s's wash: %.1fs (at least %.1fs)", player.Name, total, W.MinTime))
		job.stage = "paid"
		job.washStreak = 0
		R.job:FireClient(player, "WashPaid", {
			Id = job.id, Pay = 0, Tip = 0, Stars = 0, Took = total, Count = job.count, Earned = job.earned, Refused = true,
		})
		return
	end
	local level = levelOf(job.owner, job.def)
	local taps, birds = 0, 0
	for s = 1, job.spots do
		taps += Businesses.WashTaps(job.dirt[s])
		if job.dirt[s] == "Bird" then
			birds += 1
		end
	end
	local g = job.grades or {}
	local quick = total <= Businesses.WashStarTime(taps)
	local hadStreak = job.washStreak or 0
	local pay, tip, stars, streak = Businesses.WashPay(job.def, level, {
		spray = g.spray, rinse = g.rinse, quick = quick, birds = birds, special = job.special, streak = hadStreak,
	})
	job.washStreak = streak
	EconomyService.AddCash(player, pay + tip, "bizjob:" .. job.id .. ":wash")
	job.stage = "paid"
	job.count += 1
	job.washes = (job.washes or 0) + 1
	job.earned += pay + tip
	local perfects = (g.spray == "Perfect" and 1 or 0) + (g.rinse == "Perfect" and 1 or 0)
	local st = statsOf(job)
	st.washes += 1
	st.perfects += perfects
	st.stars3 += stars == 3 and 1 or 0
	st.specials += job.special and 1 or 0
	st.bestWash = math.max(st.bestWash, streak)
	creditOwner(job, player, pay + tip)
	jobXP(player, E.XP.Wash)
	progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizWash_" .. job.id, pay + tip)
	R.job:FireClient(player, "WashPaid", {
		Id = job.id, Pay = pay, Tip = tip, Stars = stars, Grade = g.rinse, Perfects = perfects, Quick = quick,
		Streak = streak, Broke = hadStreak >= 2 and streak == 0 and hadStreak or nil,
		Mult = Businesses.StreakMult(streak, Businesses.Streak), Special = job.special, Name = job.customer, Took = total,
		Count = job.count, Earned = job.earned,
	})
	if job.owner ~= player then
		pushState(job.owner)
	end
end

-- RequestBusiness("Step", step, arg): one step of the wash (see the header).
local function washStep(player, step, arg)
	local job = S.jobs[player]
	if not job or job.kind ~= "Wash" or not RateLimit.Allow(player, "BizWashStep", 12, 12) then
		return
	end
	local now = os.clock()
	if now < job.readyAt - 0.5 or not inBay(player, job) then
		if step == "SprayOff" or step == "RinseOff" then
			stepReply(player, job, true) -- (the client lets go of the hold: do it again from where it counts)
		end
		return
	end
	if step == "SprayOn" or step == "RinseOn" then
		if job.stage == (step == "SprayOn" and "spray" or "rinse") then
			job.holdAt = now
		end
	elseif step == "SprayOff" or step == "RinseOff" then
		local want = step == "SprayOff" and "spray" or "rinse"
		if job.stage ~= want then
			if job.stage == "spray" or job.stage == "scrub" or job.stage == "rinse" then
				stepReply(player, job, true) -- (out of step with the device: put it back)
			end
			return
		end
		local held = job.holdAt and now - job.holdAt or 0
		job.holdAt = nil
		-- The gauge, graded on this clock (Businesses.WashGrade): EARLY didn't count, hold it again.
		local grade = Businesses.WashGrade(want, held)
		if grade == "Early" then
			stepReply(player, job, true, { Early = true })
			return
		end
		job.grades = job.grades or {}
		job.grades[want] = grade
		if want == "spray" then
			job.stage = "scrub"
			stepReply(player, job, false, { Grade = grade, Step = "spray" })
		else
			job.stage = "done"
			finishWash(player, job) -- (WashPaid carries the rinse's grade)
		end
	elseif step == "Scrub" then
		local i = tonumber(arg)
		if job.stage ~= "scrub" or not i or i ~= math.floor(i) or i < 1 or i > job.spots then
			return
		end
		if now - job.lastTap < W.ScrubGap then
			return -- (faster than a hand: an auto-clicker's extra taps simply don't count)
		end
		local taps = job.taps[i] or 0
		if taps >= Businesses.WashTaps(job.dirt and job.dirt[i]) then
			return
		end
		job.lastTap = now
		job.taps[i] = taps + 1
		for s = 1, job.spots do
			if (job.taps[s] or 0) < Businesses.WashTaps(job.dirt and job.dirt[s]) then
				return
			end
		end
		job.stage = "rinse"
		stepReply(player, job)
	end
end

------------------------------------------------------------------ jobs: detail delivery

local function topSpeed(car)
	return (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
end

-- An ordinary civilian car anyone could own (never police, boats, street cars, game-pass or heist-locked ones).
local function customerCarOk(id)
	local v = Vehicles.ById[id]
	return v ~= nil and not v.Police and not v.Boat and not v.Hidden and not v.Pass and not v.UnlockHeists
end

-- A customer car for the owner's level: half the time from that level's own (nicest) list, else any list up to it.
-- sports: one of Detail.Sports.Cars instead (any level). Returns the id and whether it is a sports car.
local function pickCar(level, sports)
	if sports then
		local list = {}
		for _, id in ipairs(D.Sports.Cars) do
			if customerCarOk(id) then
				table.insert(list, id)
			end
		end
		if #list > 0 then
			return list[S.rng:NextInteger(1, #list)], true
		end
	end
	local tiers = {}
	for l = 1, Businesses.ClampLevel(level) do
		local list = {}
		for _, id in ipairs(D.Cars[l] or {}) do
			if customerCarOk(id) then
				table.insert(list, id)
			end
		end
		if #list > 0 then
			table.insert(tiers, list)
		end
	end
	if #tiers == 0 then
		return nil, false
	end
	local tier = S.rng:NextNumber() < 0.5 and tiers[#tiers] or tiers[S.rng:NextInteger(1, #tiers)]
	return tier[S.rng:NextInteger(1, #tier)], false
end

-- Nothing (a car, or anyone but the worker) on the pick-up box?
local function pickupClear(cf, size, worker)
	local list = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p ~= worker then
			table.insert(list, p.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	return #Workspace:GetPartBoundsInBox(cf, size + Vector3.new(2, 4, 3), params) == 0
end

-- Only the worker drives the customer car; their device gets its physics while they sit in it.
local function onCustomerSeat(car, seat)
	local occupant = seat.Occupant
	local chassis = car.PrimaryPart
	local p = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	if occupant and (not p or p.UserId ~= car:GetAttribute("BizDriverUserId")) then
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
		return
	end
	if p and chassis then
		car:SetAttribute("DriverUserId", p.UserId)
		pcall(function()
			chassis:SetNetworkOwner(p)
		end)
	else
		car:SetAttribute("DriverUserId", nil)
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil and chassis and chassis:IsDescendantOf(Workspace) then
				pcall(function()
					chassis:SetNetworkOwner(nil)
				end)
			end
		end)
	end
end

-- The customer car on the pick-up box, the address, the worker at the wheel. Returns true when it started.
local function beginDetail(player, job, level)
	local def = job.def
	local JobService = service("JobService")
	local roadside = JobService and JobService.RoadsideSpot
	if type(roadside) ~= "function" then
		refuse(player, def.Id, "NoAddress")
		return false
	end
	local wantSports = takeTestNext(player, "Sports") ~= nil or S.rng:NextNumber() < D.Sports.Chance
	local id, sports = pickCar(level, wantSports)
	if not id then
		refuse(player, def.Id, "NoCar")
		return false
	end
	local CarBuilder = require(ServerStorage.Tools.CarBuilder)
	local ok, car = pcall(CarBuilder.Build, id)
	if not ok or not car or not car.PrimaryPart then
		warn("[BusinessService] couldn't build a customer " .. tostring(id) .. ": " .. tostring(car))
		refuse(player, def.Id, "NoCar")
		return false
	end
	local seat = car:FindFirstChild("DriverSeat")
	local cf = Businesses.Frame(def) * CFrame.new(def.Layout.Pickup) * CFrame.new(0, K.SEAT_UP, 0) -- nose to the street
	if not seat or not pickupClear(cf, car.PrimaryPart.Size, player) then
		car:Destroy()
		refuse(player, def.Id, seat and "PickupBlocked" or "NoCar")
		return false
	end
	local drop = roadside(def.Position, D.DistMin, D.DistMax)
	if not drop then
		car:Destroy()
		refuse(player, def.Id, "NoAddress")
		return false
	end
	car.Name = "CustomerCar"
	car:SetAttribute("BizCar", true)
	car:SetAttribute("BizDriverUserId", player.UserId)
	car:SetAttribute("BizId", def.Id)
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("ProximityPrompt") and (d.Name == "DrivePrompt" or d.Name == "RidePrompt") then
			d:Destroy()
		end
	end
	-- The way back in after stepping out (BusinessClient shows it to the worker only).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BizDrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Customer car"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	job.car = car -- (set before anything below can fail: endJob -> destroyCar always finds it, nothing leaks)
	car:PivotTo(cf)
	car.Parent = Workspace.Vehicles
	pcall(function()
		car.PrimaryPart:SetNetworkOwner(nil)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onCustomerSeat(car, seat)
	end)
	local pseat = car:FindFirstChild("PassengerSeat")
	if pseat and pseat:IsA("Seat") then
		pseat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occ = pseat.Occupant
			local sw = occ and pseat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy() -- nobody rides along in a customer's car
			end
		end)
	end
	prompt.Triggered:Connect(function(who)
		local h = humOf(who)
		if who == player and S.jobs[player] == job and job.car == car and h and h.Health > 0 and h.SeatPart == nil
			and seat.Occupant == nil then
			seat:Sit(h)
		end
	end)
	-- The route: its road length sets the pay and the estimate.
	local length = 0
	local path = RoadGraph.Path(cf.Position, drop)
	if path then
		for i = 2, #path do
			length += (path[i] - path[i - 1]).Magnitude
		end
	else
		length = flat(drop - cf.Position).Magnitude * 1.4
	end
	job.kind = "Detail"
	job.stage = "drive"
	job.car = car
	job.drop = drop
	job.length = length
	job.est = Businesses.DetailEstimate(length)
	job.pickedAt = os.clock()
	job.from = cf.Position
	job.top = topSpeed(car)
	job.dents = 0
	job.lastSpeed = 0
	job.lastSpeedAt = os.clock()
	job.lastDentAt = -math.huge
	job.bumpedAt = car:GetAttribute("BumpedAt")
	job.outSince = nil
	job.sunkSince = nil
	job.name = K.NAMES[S.rng:NextInteger(1, #K.NAMES)]
	job.carName = car:GetAttribute("DisplayName") or id
	job.sports = sports == true
	job.backSince = nil
	local hum = humOf(player)
	task.defer(function()
		if S.jobs[player] == job and job.car == car and car.Parent and seat.Occupant == nil and hum and hum.Parent
			and hum.Health > 0 and hum.SeatPart == nil then
			seat:Sit(hum)
		end
	end)
	R.job:FireClient(player, "Detail", {
		Id = def.Id, Pos = drop, Name = job.name, Est = job.est, Car = job.carName, Level = level, Sports = job.sports,
		Streak = job.detailStreak or 0, Owner = job.owner.UserId, Earned = job.earned, Count = job.count,
	})
	Telemetry.Custom(player, "BizDetailStart_" .. def.Id, 1)
	return true
end

-- A delivery done: the worker is put out, the customer car stays HandOver seconds (its owner walks out to it on the
-- worker's device), then goes. Nobody gets back in meanwhile (no driver, no prompt).
local function handOver(job)
	local car = job.car
	job.car = nil
	if not car or not car.Parent then
		return
	end
	car:SetAttribute("BizDriverUserId", 0)
	local prompt = car:FindFirstChild("BizDrivePrompt", true)
	if prompt then
		prompt:Destroy()
	end
	local vs = service("VehicleService")
	if vs and type(vs.EjectAll) == "function" then
		pcall(vs.EjectAll, car)
	end
	task.delay(D.HandOver, function()
		if car.Parent then
			car:Destroy()
		end
	end)
end

local function dent(player, job, t)
	job.dents += 1
	job.lastDentAt = t
	R.job:FireClient(player, "Dent", { Dents = job.dents })
end

local function detailTick(player, job, t)
	local car = job.car
	local chassis = car and car.Parent and car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
		endJob(player, "CarGone")
		return
	end
	if chassis.Position.Y < 0.2 then
		job.sunkSince = job.sunkSince or t
		if t - job.sunkSince >= K.SINK_TIME then
			endJob(player, "CarGone")
		end
		return
	end
	job.sunkSince = nil
	local seat = car:FindFirstChild("DriverSeat")
	local hum = humOf(player)
	if not (seat and hum and seat.Occupant == hum) then
		job.outSince = job.outSince or t
		if t - job.outSince > D.LeaveGrace then
			endJob(player, "LeftCar")
		end
		job.lastSpeed = 0
		return
	end
	job.outSince = nil
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	-- Dents (see Config.Detail): a crash-hard stop, or another car shoving this one.
	local dt = math.max(t - job.lastSpeedAt, 0.05)
	-- (and the speed must have more than halved: a phone's position updates can arrive in bursts, and a normal
	-- hard brake or a kerb hop could look like DentDecel between two samples; a real crash kills the speed)
	if job.lastSpeed >= D.DentMinSpeed and (job.lastSpeed - speed) / dt >= D.DentDecel and speed < job.lastSpeed * 0.5
		and t - job.lastDentAt >= D.DentGap then
		dent(player, job, t)
	end
	local bumped = car:GetAttribute("BumpedAt")
	if bumped ~= job.bumpedAt then
		job.bumpedAt = bumped
		if t - job.lastDentAt >= D.DentGap then
			dent(player, job, t)
		end
	end
	job.lastSpeed, job.lastSpeedAt = speed, t
	job.top = math.max(job.top, topSpeed(car))
	-- Arrived: stopped inside the ring.
	if flat(chassis.Position - job.drop).Magnitude >= D.StopRadius or speed >= D.StopSpeed then
		return
	end
	local took = t - job.pickedAt
	local gap = math.max(0, flat(job.drop - job.from).Magnitude - D.StopRadius)
	local fastest = gap / (job.top * D.FastSlack)
	local guard = service("VehicleGuard")
	if took < fastest or (guard and type(guard.RecentlyFlagged) == "function" and guard.RecentlyFlagged(player, took)) then
		warn(string.format("[BusinessService] refused %s's delivery: %.2fs (at least %.2fs)", player.Name, took, fastest))
		endJob(player, "Invalid")
		return
	end
	local level = levelOf(job.owner, job.def)
	local hadStreak = job.detailStreak or 0
	local pay, tip, stars, streak = Businesses.DetailPay(job.def, level, job.length, took, job.est, job.dents, job.sports, hadStreak)
	job.detailStreak = streak
	EconomyService.AddCash(player, pay + tip, "bizjob:" .. job.id .. ":detail")
	job.count += 1
	job.earned += pay + tip
	local st = statsOf(job)
	st.deliveries += 1
	st.dents += job.dents
	st.clean += job.dents == 0 and 1 or 0
	st.bestDetail = math.max(st.bestDetail, streak)
	creditOwner(job, player, pay + tip)
	jobXP(player, E.XP.Detail)
	progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizDetail_" .. job.id, pay + tip)
	R.job:FireClient(player, "DetailPaid", {
		Id = job.id, Pay = pay, Tip = tip, Dents = job.dents, Stars = stars, Streak = streak,
		Broke = hadStreak >= 2 and streak == 0 and hadStreak or nil, Mult = Businesses.StreakMult(streak, Businesses.Streak),
		Sports = job.sports, Took = took, Est = job.est, Name = job.name, Count = job.count, Earned = job.earned,
		Vehicle = car, At = chassis.CFrame, Back = Businesses.DoorPosition(job.def),
	})
	if job.owner ~= player then
		pushState(job.owner)
	end
	-- The customer takes their car; the shift goes on (call your own car and head back for the next one).
	handOver(job)
	job.stage = "back"
	job.backSince = t
	job.drop = nil
end

------------------------------------------------------------------ jobs: starting and the tick

-- The JobKind attribute a job module runs `kind` under (Module.Kinds; Palm Grind's RUSH ORDERS from before
-- Kinds existed: "BizRush"), or nil when the kind isn't the module's.
local function moduleKind(mod, kind)
	if type(mod) ~= "table" then
		return nil
	end
	if type(mod.Kinds) == "table" then
		return mod.Kinds[kind]
	end
	return kind == "Rush" and "BizRush" or nil
end

-- "Job" (Wash | Detail | Rush | Print | Launder): see the header. A wash session goes on from car to car;
-- DELIVER after a wash keeps the session (and its totals) and frees the bay. RUSH ORDERS, PRINT and LAUNDER
-- belong to the business's job module (JOB MODULES).
local function startJob(player, def, kind, forId)
	if not RateLimit.Allow(player, "BizJobStart", 1, 3) then
		return
	end
	local why = jobBlocked(player)
	if why then
		notifyKey(player, why)
		return
	end
	local job = S.jobs[player]
	if job then
		if job.id ~= def.Id then
			refuse(player, def.Id, "JobElsewhere")
			return
		elseif job.mod then
			local mod = job.mod
			if kind == job.kind and type(mod.Resend) == "function" then
				pcall(mod.Resend, player, job, Api) -- (already on it: its HUD again)
			elseif moduleKind(mod, kind) and type(mod.Switch) == "function" then
				local ok, err = pcall(mod.Switch, player, job, kind, Api) -- (the Print Shop: PRINT <-> LAUNDER)
				if not ok then
					warn("[BusinessService] job module Switch: " .. tostring(err))
				end
			elseif kind ~= job.kind then
				refuse(player, def.Id, "OnRush") -- ("Finish them first, or END JOB")
			end
			return
		elseif job.kind == "Detail" and job.stage ~= "back" then
			refuse(player, def.Id, "OnDelivery")
			return
		elseif job.kind == "Wash" and job.stage ~= "paid" then
			return -- (a car is in the bay: finish it or END JOB)
		end
		-- (else: after a wash, or back from a delivery: the shift goes on with the next car)
	end
	if not canAct(player, def) then
		return
	end
	local hum = humOf(player)
	if hum and hum.SeatPart then
		notifyKey(player, "GetOutFirst")
		return
	end
	local owner = job and job.owner or jobOwner(player, def, forId)
	if not owner then
		refuse(player, def.Id, "NotYours")
		return
	end
	local level = levelOf(owner, def)
	local isNew = job == nil
	local mod = Jobs[def.Style or ""]
	local modKind = moduleKind(mod, kind)
	if modKind then
		if not isNew or type(mod.Start) ~= "function" then
			return
		end
		job = { id = def.Id, def = def, owner = owner, count = 0, earned = 0, startedAt = os.clock(), kind = kind,
			char = player.Character, mod = mod, jobKind = modKind }
		S.jobs[player] = job
		player:SetAttribute("JobKind", modKind)
		player:SetAttribute("BizJob", def.Id)
		local ok, err = pcall(mod.Start, player, job, Api)
		if not ok then
			warn("[BusinessService] couldn't start a " .. tostring(kind) .. " job: " .. tostring(err))
			endJob(player, "Player")
			return
		end
		Telemetry.Custom(player, "BizJob_" .. def.Id .. (owner == player and "" or "_crew"), 1)
		return
	end
	job = job or { id = def.Id, def = def, owner = owner, count = 0, earned = 0, startedAt = os.clock() }
	job.char = player.Character
	if kind == "Wash" then
		local bay = (job.bay and S.bays[def.Id] and S.bays[def.Id][job.bay] == player and job.bay) or freeBay(def, level, player)
		if not bay then
			refuse(player, def.Id, "BaysBusy")
			return
		end
		job.bay = bay
		S.jobs[player] = job
		player:SetAttribute("JobKind", "BizWash")
		player:SetAttribute("BizJob", def.Id)
		nextWash(player, job, level)
	else
		S.jobs[player] = job -- (beginDetail's checks may still refuse: a fresh job is dropped again below)
		if not beginDetail(player, job, level) then
			if isNew and S.jobs[player] == job then
				S.jobs[player] = nil
			end
			return
		end
		if S.jobs[player] ~= job then
			destroyCar(job) -- (the job ended while the car was being built: wanted, left... the car goes with it)
			return
		end
		releaseBay(player)
		job.bay = nil
		job.washes = 0 -- (no car left in the bay to pull out before the next wash)
		player:SetAttribute("JobKind", "BizDetail")
		player:SetAttribute("BizJob", def.Id)
	end
	if isNew then
		Telemetry.Custom(player, "BizJob_" .. def.Id .. (owner == player and "" or "_crew"), 1)
	end
end

-- May this job go on while its worker is wanted (Module.KeepWanted: a launder run with the bags in the car)?
local function keepWanted(job)
	local mod = job.mod
	if not mod or type(mod.KeepWanted) ~= "function" then
		return false
	end
	local ok, keep = pcall(mod.KeepWanted, job)
	return ok and keep == true
end

-- Four times a second: deliveries, and jobs that should end.
local function jobsTick()
	local t = os.clock()
	for player, job in pairs(S.jobs) do
		if player.Parent ~= Players then
			S.jobs[player] = nil
			releaseBay(player)
			destroyCar(job)
			moduleEnd(player, job, "Left")
		elseif (player:GetAttribute("Heat") or 0) > 0 and not keepWanted(job) then
			endJob(player, "Wanted")
		elseif player:GetAttribute("Side") ~= "Civilian" then
			endJob(player, "Side")
		elseif player.Character ~= job.char or not alive(player) then
			endJob(player, "Died")
		elseif job.owner.Parent ~= Players or not owned(job.owner, job.id) then
			endJob(player, "OwnerLeft")
		elseif job.mod then
			local mod = job.mod
			if player:GetAttribute("JobKind") ~= job.jobKind then
				endJob(player, "Busy") -- (another job took the attribute: a taxi shift started on the way)
			elseif type(mod.Tick) == "function" then
				local ok, err = pcall(mod.Tick, player, job, t, Api)
				if not ok then
					warn("[BusinessService] " .. tostring(job.kind) .. " job: " .. tostring(err))
					endJob(player, "Player") -- (one broken job never stops everyone else's)
				end
			end
		elseif job.kind == "Detail" and job.stage == "back" then
			-- Between cars, after a delivery: the next one (or a wash) within IdleTime, or the shift ends.
			if t - (job.backSince or t) > D.IdleTime then
				endJob(player, "NoNextCar")
			end
		elseif job.kind == "Detail" then
			detailTick(player, job, t)
		elseif job.kind == "Wash" then
			local root = rootOf(player)
			local hum = humOf(player)
			local bay = Businesses.BayCFrame(job.def, job.bay)
			local away = not root or not bay or (hum and hum.SeatPart ~= nil)
				or flat(root.Position - bay.Position).Magnitude > W.LeaveRange
			if away then
				job.awaySince = job.awaySince or t
				if t - job.awaySince > W.LeaveGrace then
					endJob(player, "LeftBay")
				end
			else
				job.awaySince = nil
			end
		end
	end
end

------------------------------------------------------------------ customers: the shine and the cold brew

-- A player customer pays `price` for this business's service (see CUSTOMERS in the header). Returns false
-- when they can't pay (told so), else true and the featured owner's name when one was paid. words: what the owner's
-- toast calls it (M5: the Nightclub's VIP booth; default the business's Service Words).
local function serveCustomer(player, def, price, reason, words)
	if not EconomyService.Spend(player, price, reason .. ":" .. def.Id) then
		notifyKey(player, "NotEnoughCash")
		return false, nil
	end
	local featured = featuredOf(def.Id)
	if not featured or featured == player then
		return true, nil -- (nobody to pay, or an owner at their own business: the game keeps it all)
	end
	local share = Businesses.Split(price)
	if share <= 0 then
		return true, nil
	end
	EconomyService.AddCash(featured, share, "bizcustomer:" .. def.Id)
	local entry = owned(featured, def.Id)
	if entry then
		entry.lifetime += share
	end
	-- Empire XP: one buyer counts at most CustomerPerBuyerHour times an hour for this owner.
	S.customerXP[featured] = S.customerXP[featured] or {}
	local counts, rec = Businesses.CustomerXP(S.customerXP[featured][player.UserId], os.clock())
	S.customerXP[featured][player.UserId] = rec
	if counts then
		addEmpireXP(featured, E.XP.Customer)
	end
	result(featured, { Kind = "Customer", Id = def.Id, Buyer = player.DisplayName, Amount = share,
		Service = (type(words) == "string" and words) or (def.Service and def.Service.Words) or "a purchase" })
	Telemetry.Custom(featured, "BizCustomer_" .. def.Id, share)
	return true, featured.DisplayName
end

local function onShine(player, def)
	if not RateLimit.Allow(player, "BizShine", 1, 2) then
		return
	end
	local hum = humOf(player)
	local seat = hum and hum.Health > 0 and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	local vs = service("VehicleService")
	if not car or car:GetAttribute("OwnerUserId") ~= player.UserId or car:GetAttribute("Boat") == true
		or (vs and type(vs.GetCar) == "function" and vs.GetCar(player) ~= car) then
		refuse(player, def.Id, "ShineOwnCar")
		return
	end
	if flat(seat.Position - Businesses.At(def, def.Layout.Shine)).Magnitude > SH.Reach then
		refuse(player, def.Id, "TooFar")
		return
	end
	if car.PrimaryPart and car.PrimaryPart.AssemblyLinearVelocity.Magnitude > SH.MaxSpeed then
		refuse(player, def.Id, "ShineStop")
		return
	end
	local now = Workspace:GetServerTimeNow()
	local untilT = player:GetAttribute("ShineUntil")
	if type(untilT) == "number" and untilT - now > SH.RebuyLeft then
		refuse(player, def.Id, "ShineAlready")
		return
	end
	local price = (def.Service and def.Service.Price) or SH.Price
	local paid, paidTo = serveCustomer(player, def, price, "bizshine")
	if not paid then
		return
	end
	player:SetAttribute("ShineUntil", now + SH.Seconds)
	result(player, { Kind = "Shined", Id = def.Id, Price = price, Until = now + SH.Seconds, Owner = paidTo })
	Telemetry.Custom(player, "BizShine_" .. def.Id, price)
end

-- BizServicePrompt at Palm Grind's counter: a cold brew (see CUSTOMERS in the header).
local function onColdBrew(player, def)
	local CB = Businesses.ColdBrew
	local hum = humOf(player)
	local root = rootOf(player)
	if player:GetAttribute("Side") == "Prisoner" or not hum or hum.Health <= 0 or not root then
		return
	end
	if hum.SeatPart then
		refuse(player, def.Id, "ColdBrewOnFoot")
		return
	end
	local spot = Businesses.At(def, def.Layout.Service)
	if flat(root.Position - spot).Magnitude > CB.Reach or math.abs(root.Position.Y - spot.Y) > 12 then
		refuse(player, def.Id, "TooFar")
		return
	end
	local now = Workspace:GetServerTimeNow()
	local untilT = player:GetAttribute("ColdBrewUntil")
	if type(untilT) == "number" and untilT - now > CB.RebuyLeft then
		refuse(player, def.Id, "ColdBrewAlready")
		return
	end
	local price = def.Service.Price
	local paid, paidTo = serveCustomer(player, def, price, "bizcoldbrew")
	if not paid then
		return
	end
	player:SetAttribute("ColdBrewUntil", now + CB.Seconds)
	result(player, { Kind = "ColdBrew", Id = def.Id, Price = price, Until = now + CB.Seconds, Owner = paidTo })
	Telemetry.Custom(player, "BizColdBrew_" .. def.Id, price)
end

-- The service prompt (BizServicePrompt): which purchase it is comes from the Config Service Kind, or the business's
-- job module runs it (Module.Service: Boat Rentals' jet ski rental, M4).
local function onService(player, def)
	if not RateLimit.Allow(player, "BizService", 1, 2) or not DataService.Get(player) then
		return
	end
	if def.Service and def.Service.Kind == "ColdBrew" and def.Layout.Service then
		onColdBrew(player, def)
		return
	end
	local mod = Jobs[def.Style or ""]
	if def.Service and def.Layout.Service and mod and type(mod.Service) == "function" then
		local ok, err = pcall(mod.Service, player, def, Api)
		if not ok then
			warn("[BusinessService] job module Service: " .. tostring(err))
		end
	end
end

------------------------------------------------------------------ NPC break-ins

-- BizAlarm on everyone: the businesses with a break-in they should answer (their own, or a crewmate's).
local function refreshAlarms()
	for _, p in ipairs(Players:GetPlayers()) do
		local ids = {}
		for owner, b in pairs(S.breakins) do
			local rec = b.active
			if rec and owner.Parent == Players and (owner == p or sameCrew(owner, p)) and not table.find(ids, rec.id) then
				table.insert(ids, rec.id)
			end
		end
		-- (and the job modules' own: a Print Shop raid this player is part of)
		for _, mod in pairs(Jobs) do
			if type(mod.Alarms) == "function" then
				local ok, more = pcall(mod.Alarms, p)
				for _, id in ipairs(ok and type(more) == "table" and more or {}) do
					if not table.find(ids, id) then
						table.insert(ids, id)
					end
				end
			end
		end
		local s = #ids > 0 and table.concat(ids, ",") or nil
		if p:GetAttribute("BizAlarm") ~= s then
			p:SetAttribute("BizAlarm", s)
		end
	end
end

-- A speech bubble over a robber's head, for everyone, for `seconds` (as HeistService's clerks).
local function say(r, text, seconds)
	local head = r.model:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("Say")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "Say"
		gui.Size = UDim2.fromOffset(220, 34)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 80
		gui.AlwaysOnTop = true
		gui.Parent = head
		local l = Instance.new("TextLabel")
		l.Name = "Text"
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		l.BackgroundTransparency = 0.05
		l.TextColor3 = Color3.fromRGB(20, 20, 28)
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = l
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = l
	end
	gui.Text.Text = text
	gui.Enabled = true
	r.sayToken = (r.sayToken or 0) + 1
	local token = r.sayToken
	task.delay(seconds, function()
		if r.sayToken == token and gui.Parent then
			gui.Enabled = false
		end
	end)
end

-- Fade a model out and remove it.
local function fadeOut(model, seconds)
	if not model.Parent then
		return
	end
	local info = TweenInfo.new(seconds or 0.6)
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay((seconds or 0.6) + 0.1, function()
		S.robbers[model] = nil
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- A robber runs out of the door to the forecourt and vanishes. scared: arms over the head.
local function runOff(r, scared)
	local model, root = r.model, r.root
	if not model.Parent or not root.Parent then
		S.robbers[model] = nil
		return
	end
	model:SetAttribute("NPCKind", nil) -- (nobody can hit it any more)
	model:SetAttribute("AimTarget", nil)
	model:SetAttribute("Pose", scared and "Brace" or nil)
	local def = r.rec.def
	local y = root.Position.Y
	local door = Businesses.At(def, def.Layout.Door + Vector3.new(0, 0, 2))
	local exit = Businesses.At(def, def.Layout.Exit)
	local legs = { Vector3.new(door.X, y, door.Z), Vector3.new(exit.X, y, exit.Z) }
	root.Anchored = true
	pcall(function()
		require(ServerStorage.Tools.CarBuilder).PlayPose(model, "walk")
	end)
	task.spawn(function()
		local from = root.Position
		for _, to in ipairs(legs) do
			local d = (to - from).Magnitude
			if d > 0.5 and model.Parent then
				local tween = TweenService:Create(root, TweenInfo.new(d / K.ROBBER_SPEED, Enum.EasingStyle.Linear),
					{ CFrame = CFrame.lookAt(to, to + (to - from).Unit) })
				tween:Play()
				tween.Completed:Wait()
			end
			from = to
		end
		fadeOut(model, 0.5)
	end)
end

-- A break-in robber at its spot in front of the register (one of PedService's looks, a dark beanie and a
-- bandana), or nil when no look can be made.
local function spawnRobber(def, rec, i)
	local ok, model = pcall(function()
		local looks = ReplicatedStorage:FindFirstChild("PedTemplates")
		local list = looks and looks:GetChildren() or {}
		local pick = #list > 0 and list[S.rng:NextInteger(1, #list)] or nil
		if pick and pick:IsA("Model") and pick:FindFirstChild("HumanoidRootPart") and pick:FindFirstChildOfClass("Humanoid") then
			return pick:Clone()
		end
		local desc = Instance.new("HumanoidDescription")
		local c = Color3.fromRGB(205, 160, 120)
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = c, c, c
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(40, 44, 52), Color3.fromRGB(40, 44, 52)
		desc.TorsoColor = Color3.fromRGB(30, 32, 38)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not hum or not root then
		model:Destroy()
		return nil
	end
	hum.BreakJointsOnDeath = false
	hum.DisplayName = "Robber"
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 60
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	-- A dark beanie and a bandana over the mouth, welded to the head (looks only).
	if head and head:IsA("BasePart") then
		for _, spec in ipairs({
			{ "Beanie", Vector3.new(1.25, 0.55, 1.25), CFrame.new(0, head.Size.Y * 0.42, 0), K.BEANIE, Enum.Material.Fabric },
			{ "Bandana", Vector3.new(1.22, 0.45, 1.22), CFrame.new(0, -head.Size.Y * 0.22, 0), K.BANDANA, Enum.Material.Fabric },
		}) do
			local p = Instance.new("Part")
			p.Name = spec[1]
			p.Size = spec[2]
			p.Color = spec[4]
			p.Material = spec[5]
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CFrame = head.CFrame * spec[3]
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = head, p
			weld.Parent = p
			p.Parent = model
		end
	end
	local f = Businesses.Frame(def)
	local spot = def.Layout.Robbers[i] or def.Layout.Robbers[1]
	local reg = Businesses.At(def, def.Layout.Register)
	local floor = (f * CFrame.new(spot.X, 0.4, spot.Z)).Position
	local at = floor + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0)
	model:PivotTo(CFrame.lookAt(at, Vector3.new(reg.X, at.Y, reg.Z)))
	root.Anchored = true
	model.Name = "BizRobber"
	model:SetAttribute("NPCKind", "BizRobber")
	model:SetAttribute("AimTarget", true)
	model:SetAttribute("BizId", def.Id)
	model:SetAttribute("BizOwner", rec.owner.UserId)
	model.Parent = npcFolder()
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://507766388" -- (Roblox's stock R15 idle)
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
	local r = { model = model, root = root, hum = hum, state = "Robbing", rec = rec, token = 0 }
	S.robbers[model] = r
	if i == 1 then
		say(r, "Grab the cash, quick!", 3)
	end
	return r
end

-- Everyone who should hear about this owner's break-in: the owner and their crewmates in the server.
local function breakInCrew(owner)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p == owner or sameCrew(owner, p) then
			table.insert(list, p)
		end
	end
	return list
end

local function endBreakIn(owner, how)
	local b = S.breakins[owner]
	local rec = b and b.active
	if not rec or rec.done then
		return
	end
	rec.done = true
	b.active = nil
	b.nextAt = (S.play[owner] or 0) + B.Gap + S.rng:NextNumber() * B.Window
	if how == "Stopped" then
		addEmpireXP(owner, E.XP.BreakIn)
		for _, p in ipairs(breakInCrew(owner)) do
			result(p, { Kind = "BreakInStopped", Id = rec.id, Owner = owner.UserId, OwnerName = owner.DisplayName })
		end
		Telemetry.Custom(owner, "BizBreakInStopped_" .. rec.id, rec.total)
	elseif how == "Escaped" then
		local entry = owned(owner, rec.id)
		local loss = 0
		if entry then
			settle(owner)
			loss = Businesses.BreakInLoss(entry.register)
			entry.register -= loss
			flagsFor(owner, rec.id).full = false
		end
		for _, r in ipairs(rec.robbers) do
			if r.state == "Robbing" then
				r.state = "Leaving"
				r.token += 1
				say(r, "We're out of here!", 2)
				runOff(r, false)
			end
		end
		for _, p in ipairs(breakInCrew(owner)) do
			result(p, { Kind = "BreakInLost", Id = rec.id, Amount = loss, Owner = owner.UserId, OwnerName = owner.DisplayName })
		end
		Telemetry.Custom(owner, "BizBreakInLost_" .. rec.id, loss)
		pushState(owner)
	else
		-- The owner left: the robbers simply go.
		for _, r in ipairs(rec.robbers) do
			r.state = "Gone"
			r.token += 1
			S.robbers[r.model] = nil
			if r.model.Parent then
				r.model:Destroy()
			end
		end
	end
	refreshAlarms()
end

-- One robber was scared off or knocked down by `by` (the owner or a crewmate).
local function robberStopped(r, by)
	local rec = r.rec
	if rec.done then
		return
	end
	rec.stopped += 1
	local reward = math.floor(B.Reward * Businesses.RateScale)
	if by.Parent == Players and reward > 0 then
		EconomyService.AddCash(by, reward, "bizbreakin:" .. rec.id)
		result(by, { Kind = "RobberStopped", Id = rec.id, Reward = reward, Left = rec.total - rec.stopped })
	end
	if rec.stopped >= rec.total then
		endBreakIn(rec.owner, "Stopped")
	end
end

-- Start a break-in at `def` for this owner now. seconds: its timer (B.Time by default).
local function startBreakIn(owner, def, seconds)
	local b = S.breakins[owner]
	if not b or b.active then
		return false
	end
	local rec = { id = def.Id, def = def, owner = owner, robbers = {}, stopped = 0, total = 0,
		untilAt = os.clock() + (seconds or B.Time) }
	for i = 1, S.rng:NextInteger(B.Robbers[1], B.Robbers[2]) do
		local r = spawnRobber(def, rec, i)
		if r then
			table.insert(rec.robbers, r)
		end
	end
	if #rec.robbers == 0 then
		return false
	end
	rec.total = #rec.robbers
	b.active = rec
	local serverUntil = Workspace:GetServerTimeNow() + (rec.untilAt - os.clock())
	for _, p in ipairs(breakInCrew(owner)) do
		result(p, { Kind = "BreakIn", Id = def.Id, Until = serverUntil, Owner = owner.UserId, OwnerName = owner.DisplayName,
			Robbers = rec.total })
	end
	refreshAlarms()
	Telemetry.Custom(owner, "BizBreakIn_" .. def.Id, rec.total)
	return true
end

-- The owner's legit business with the fullest register (MinRegister+), if a break-in may happen now.
local function breakInTarget(owner)
	if owner:GetAttribute("Side") ~= "Civilian" or not alive(owner) then
		return nil
	end
	settle(owner)
	local best, bestEntry
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and Businesses.BreakInEligible(def) and def.Layout and def.Layout.Robbers and S.sites[def.Id] then
			local entry = owned(owner, def.Id)
			if entry and entry.register >= B.MinRegister and (not bestEntry or entry.register > bestEntry.register) then
				best, bestEntry = def, entry
			end
		end
	end
	return best
end

-- Once a second: everyone's play clock, break-ins that are due or over, the alarms.
local function breakInTick(dt)
	local scale = timeScale()
	for _, player in ipairs(Players:GetPlayers()) do
		if S.lastSettle[player] then
			S.play[player] = (S.play[player] or 0) + dt * scale
			local b = S.breakins[player]
			if not b then
				b = { nextAt = B.MinPlay + S.rng:NextNumber() * B.Window }
				S.breakins[player] = b
			end
			if b.active then
				if os.clock() >= b.active.untilAt then
					endBreakIn(player, "Escaped")
				end
			elseif S.play[player] >= b.nextAt then
				local def = breakInTarget(player)
				if not def or not startBreakIn(player, def) then
					b.nextAt = S.play[player] + B.Retry
				end
			end
		end
	end
	refreshAlarms()
end

-- RequestBusiness("Scare", nil, model): a gun pointed at a robber (see the header).
local function onScare(player, model)
	if not RateLimit.Allow(player, "BizScare", 2, 3) then
		return
	end
	local r = typeof(model) == "Instance" and S.robbers[model] or nil
	if not r or r.state ~= "Robbing" or r.rec.done then
		return
	end
	local owner = r.rec.owner
	if (player ~= owner and not sameCrew(owner, player)) or player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root or hum.SeatPart then
		return
	end
	local gun = false
	for _, t in ipairs(char:GetChildren()) do
		gun = gun or (t:IsA("Tool") and t:GetAttribute(Combat.ToolAttribute or "NCCombat") == "Gun")
	end
	local to = flat(r.root.Position - root.Position)
	local look = flat(root.CFrame.LookVector)
	if not gun or to.Magnitude > B.ScareReach or to.Magnitude < 0.5 or look.Magnitude < 0.1 or look.Unit:Dot(to.Unit) < B.ScareCone then
		return
	end
	r.state = "Scared"
	r.token += 1
	local token = r.token
	model:SetAttribute("Pose", "HandsUp")
	say(r, "Whoa! Okay, okay, I'm going!", 2)
	robberStopped(r, player)
	task.delay(1.2, function()
		if r.token == token and model.Parent then
			runOff(r, true)
		end
	end)
end

------------------------------------------------------------------ the building (Look 3.0)

-- Colours (Look 3.0: real materials in believable colours, one accent per place, neon only after dark).
local C = {
	WHITE = Color3.fromRGB(236, 234, 228),
	WALL = Color3.fromRGB(232, 236, 240),
	CONCRETE = Color3.fromRGB(176, 172, 164),
	DARK = Color3.fromRGB(26, 28, 32), -- sign boards
	DARK_METAL = Color3.fromRGB(44, 44, 48),
	STEEL = Color3.fromRGB(120, 124, 130),
	GLASS = Color3.fromRGB(52, 62, 70),
	GOLD = Color3.fromRGB(255, 214, 10),
	SAFETY = Color3.fromRGB(240, 196, 44), -- painted lines
	WARM = Color3.fromRGB(255, 214, 170),
	TRIM_DAY = Color3.fromRGB(58, 60, 66), -- an unlit neon tube by day (SkyClient's day colour)
	LAMP_DAY = Color3.fromRGB(226, 226, 220),
	LEAF = Color3.fromRGB(64, 108, 58),
	BARK = Color3.fromRGB(128, 110, 88),
	SOFT_BLUE = Color3.fromRGB(120, 200, 255),
	CONE = Color3.fromRGB(255, 120, 40),
	PINK = Color3.fromRGB(255, 62, 165),
}
local FONT = Enum.Font.Oswald
local SMALL_FONT = Enum.Font.GothamBold

-- Small details: no collisions, no queries, no shadow. SHADE: looks only, but casts a shadow.
local DETAIL = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
local SHADE = { CanCollide = false, CanQuery = false, CanTouch = false }

local Build = {} -- the building helpers (a table, so the file stays well under Luau's 200 locals)

function Build.part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- One part between two corners (x0..x1, y0..y1, z0..z1) of a frame's local space.
function Build.box(parent, name, frame, x0, x1, y0, y1, z0, z1, color, material, props)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	return Build.part(parent, name, size, frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, props)
end

-- An upright cylinder standing on (x, y0, z), `h` tall.
function Build.post(parent, name, frame, x, z, y0, h, diameter, color, material, props)
	local p = Build.part(parent, name, Vector3.new(h, diameter, diameter),
		frame * CFrame.new(x, y0 + h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Night-only neon (dark metal by day; SkyClient lights it in NeonColor after dark, and any Light in it).
function Build.nightNeon(p, color)
	p.Material = Enum.Material.Metal
	p.Color = C.TRIM_DAY
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end

function Build.neon(parent, frame, x0, x1, y0, y1, z0, z1, color)
	return Build.nightNeon(Build.box(parent, "Neon", frame, x0, x1, y0, y1, z0, z1, C.TRIM_DAY, Enum.Material.Metal, DETAIL), color)
end

-- A lamp (tag "NightLamp"): a pale shade by day, lit in LampColor after dark, with its light.
function Build.lamp(parent, frame, x0, x1, y0, y1, z0, z1, range)
	local p = Build.box(parent, "Lamp", frame, x0, x1, y0, y1, z0, z1, C.LAMP_DAY, Enum.Material.SmoothPlastic, DETAIL)
	p:SetAttribute("LampColor", C.WARM)
	CollectionService:AddTag(p, "NightLamp")
	local l = Instance.new("PointLight")
	l.Color = C.WARM
	l.Range = range or 16
	l.Brightness = 1
	l.Shadows = false
	l.Enabled = false -- SkyClient switches it on after dark
	l.Parent = p
	return p
end

-- A light that's always on (indoors).
function Build.roomLight(parent, frame, x0, x1, y, z0, z1, color, range)
	local p = Build.box(parent, "CeilingLight", frame, x0, x1, y - 0.2, y, z0, z1, color, Enum.Material.Neon, DETAIL)
	local l = Instance.new("SurfaceLight")
	l.Face = Enum.NormalId.Bottom
	l.Range = range or 18
	l.Angle = 120
	l.Brightness = 1.1
	l.Color = color
	l.Shadows = false
	l.Parent = p
	return p
end

function Build.glass(parent, frame, x0, x1, y0, y1, z0, z1)
	return Build.box(parent, "Window", frame, x0, x1, y0, y1, z0, z1, C.GLASS, Enum.Material.Glass, { Reflectance = 0.1, Transparency = 0.35 })
end

-- Sign text on one face of a part: the title in Oswald, an optional sub line in small print. painted = it
-- takes the light like paint (not a lit sign). Returns the gui.
function Build.signGui(part, face, title, sub, titleColor, subColor, painted)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.LightInfluence = painted and 1 or 0
	gui.Brightness = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, sub and 0.06 or 0.1)
	t.Size = UDim2.fromScale(0.92, sub and 0.56 or 0.8)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = titleColor or C.WHITE
	t.Text = title
	t.Parent = gui
	if sub then
		local s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0.08, 0.64)
		s.Size = UDim2.fromScale(0.84, 0.3)
		s.Font = SMALL_FONT
		s.TextScaled = true
		s.TextColor3 = subColor or C.GOLD
		s.Text = sub
		s.Parent = gui
	end
	gui.Parent = part
	return gui
end

-- A palm (the city art's palm mesh when the place has one, else a trunk and fronds), as HousingService's.
function Build.palm(parent, frame, x, z, height, yaw)
	local base = frame * CFrame.new(x, 0.2, z)
	local trunk = Build.part(parent, "PalmTrunk", Vector3.new(height, 1.4, 1.4), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		C.BARK, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	if template and template:IsA("BasePart") then
		trunk.Transparency = 1
		local mesh = template:Clone()
		mesh.Name = "PalmTree"
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Size = template.Size * math.min(height / 22, 12 / math.max(template.Size.X, template.Size.Z))
		mesh.CFrame = base * CFrame.new(0, mesh.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0)
		mesh.Parent = parent
		return
	end
	local top = base * CFrame.new(0, height, 0)
	for i = 0, 5 do
		Build.part(parent, "PalmLeaf", Vector3.new(2.2, 0.3, 8), top * CFrame.Angles(0, yaw + math.rad(i * 60 + 15), 0)
			* CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -3.8), C.LEAF, Enum.Material.Grass, DETAIL)
	end
end

function Build.planterPalm(parent, frame, x, z, height)
	Build.box(parent, "Planter", frame, x - 2.2, x + 2.2, 0.2, 1.6, z - 2.2, z + 2.2, C.CONCRETE, Enum.Material.Concrete)
	Build.palm(parent, frame, x, z, height, math.rad(x * 13 + z * 7))
end

function Build.prompt(parent, name, action, object, reach)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0
	p.MaxActivationDistance = reach or 10
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- An invisible part to hang a prompt on.
function Build.holder(parent, name, frame, pos, size)
	return Build.part(parent, name, size or Vector3.new(1, 1, 1), frame * CFrame.new(pos), C.DARK, nil,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
end

-- Painted lines (a rectangle outline) on the ground, and a stencil word in it.
function Build.bayLines(parent, frame, cx, cz, w, d, label)
	local y0, y1 = 0.2, 0.24
	local B_ = Build.box
	B_(parent, "BayLine", frame, cx - w / 2, cx + w / 2, y0, y1, cz - d / 2, cz - d / 2 + 0.4, C.SAFETY, Enum.Material.SmoothPlastic, DETAIL)
	B_(parent, "BayLine", frame, cx - w / 2, cx + w / 2, y0, y1, cz + d / 2 - 0.4, cz + d / 2, C.SAFETY, Enum.Material.SmoothPlastic, DETAIL)
	B_(parent, "BayLine", frame, cx - w / 2, cx - w / 2 + 0.4, y0, y1, cz - d / 2, cz + d / 2, C.SAFETY, Enum.Material.SmoothPlastic, DETAIL)
	B_(parent, "BayLine", frame, cx + w / 2 - 0.4, cx + w / 2, y0, y1, cz - d / 2, cz + d / 2, C.SAFETY, Enum.Material.SmoothPlastic, DETAIL)
	if label then
		local paint = B_(parent, "BayPaint", frame, cx - w / 2 + 1, cx + w / 2 - 1, y0, y0 + 0.02, cz - 2, cz + 2, C.CONCRETE, Enum.Material.SmoothPlastic,
			{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		Build.signGui(paint, Enum.NormalId.Top, label, nil, C.SAFETY, nil, true)
	end
end

-- A front wall along z = z0..z1 from x0 to x1: a low wall, a glass band and a header, as one shopfront.
function Build.shopfront(parent, frame, x0, x1, z0, z1, H, wall, mat, sill, glassTop)
	Build.box(parent, "FrontWall", frame, x0, x1, 0.2, sill, z0, z1, wall, mat)
	Build.glass(parent, frame, x0 + 0.3, x1 - 0.3, sill, glassTop, z0 + 0.3, z1 - 0.3)
	Build.box(parent, "Header", frame, x0, x1, glassTop, H, z0, z1, wall, mat)
end

-- A parked car to look at (a level prop: a waiting customer, the car on the detailing lift). Its nose
-- points along the lot's -Z turned by `yaw`; (x, y, z) is the middle of its footprint on the ground.
function Build.carProp(parent, frame, x, y, z, yaw, color)
	local cf = frame * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
	local P = Build.part
	P(parent, "CarBody", Vector3.new(6.8, 1.8, 14), cf * CFrame.new(0, 2.1, 0), color, Enum.Material.SmoothPlastic,
		{ Reflectance = 0.15, CanCollide = false, CanQuery = false })
	P(parent, "CarCabin", Vector3.new(6, 1.6, 6.4), cf * CFrame.new(0, 3.8, 0.8), C.GLASS, Enum.Material.Glass,
		{ Transparency = 0.25, CanCollide = false, CanQuery = false, CastShadow = false })
	P(parent, "CarRoof", Vector3.new(5.8, 0.25, 6), cf * CFrame.new(0, 4.7, 0.8), color, Enum.Material.SmoothPlastic, DETAIL)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local w = P(parent, "CarWheel", Vector3.new(1, 2.4, 2.4), cf * CFrame.new(sx * 3.1, 1.2, sz * 4.6), Color3.fromRGB(28, 28, 32),
				Enum.Material.SmoothPlastic, DETAIL)
			w.Shape = Enum.PartType.Cylinder
		end
		P(parent, "Headlight", Vector3.new(1.3, 0.5, 0.2), cf * CFrame.new(sx * 2.3, 2.4, -7.05), Color3.fromRGB(255, 250, 220),
			Enum.Material.SmoothPlastic, DETAIL)
		P(parent, "Taillight", Vector3.new(1.3, 0.5, 0.2), cf * CFrame.new(sx * 2.3, 2.4, 7.05), Color3.fromRGB(150, 24, 34),
			Enum.Material.SmoothPlastic, DETAIL)
	end
end

-- A group of level props: everything built into it shows from minL (and up to maxL, if given) on each
-- device. Tagged by tagProps once the building is done.
function Build.group(m, name, minL, maxL)
	local g = Instance.new("Model")
	g.Name = name
	g:SetAttribute("MinLevel", minL)
	g:SetAttribute("MaxLevel", maxL)
	g.Parent = m
	return g
end

-- Every part in a level group: tag BizProp, BizId / MinLevel / MaxLevel, and never solid (each device shows
-- its own level, so a prop that collided would be a wall one player sees and another drives through).
function Build.tagProps(m, id)
	for _, g in ipairs(m:GetChildren()) do
		if g:IsA("Model") and g:GetAttribute("MinLevel") then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d:SetAttribute("BizId", id)
					d:SetAttribute("MinLevel", g:GetAttribute("MinLevel"))
					d:SetAttribute("MaxLevel", g:GetAttribute("MaxLevel"))
					-- Its own look, kept on the part (BizT): each device hides a prop by making it fully see-through
					-- and shows it again from this, never from a copy it remembered (the Nov 4 Studio test found every
					-- prop stuck see-through after a level change: the remembered copy had gone stale).
					d:SetAttribute("BizT", d.Transparency)
					for _, k in ipairs(d:GetChildren()) do
						if k:IsA("Decal") or k:IsA("Texture") then
							k:SetAttribute("BizT", k.Transparency)
						end
					end
					CollectionService:AddTag(d, "BizProp")
				end
			end
		end
	end
end

local STYLES = {}

-- Suds & Shine (lot space; the street is -Z). A white wash hall with three bay spaces (x -27..3, open to the
-- forecourt at z -3), a detailing room (x 3..15.5) behind a roll-up door, and a glass-front office (x 16.5..27,
-- the door at x 18.5..23.5) with the counter and the register. On the forecourt: the shine lane with its gantry
-- (x 4..14), the PICK-UP box (x 16..25), lane arrows into the bays. Level props (PRD section 5):
--   1  bay 1 only (bays 2-3 closed with cones and a COMING SOON barrier), the painted roof sign
--   2  bay 2 (its partition, brush, boom, board, arrows) and a vacuum station
--   3  bay 3, neon on the roof sign / header / office, the pole sign with its bubbles, a waiting bench and a
--      planter, a customer's car waiting in the queue
--   4  the detailing garage (the roll-up door rolls up: a lift with a car, tool chests, bright lights, a
--      DETAILING sign), a second car waiting
--   5  a full drive-through tunnel over the shine lane: arches with LED strips, roller brushes, a gold sign
-- Returns the plate's title label (the owner's name / FOR SALE).
function STYLES.CarWash(m, f, def)
	local box, post, neon, group = Build.box, Build.post, Build.neon, Build.group
	local accent, glow = def.Accent, def.Neon
	local wall = C.WALL
	local H, OH = 13, 11 -- the hall's height, the office's and detailing room's
	local front = Enum.NormalId.Front -- (a part built in the lot frame faces the street with its Front)

	-- THE WASH HALL ------------------------------------------------------------------------------------------
	box(m, "BayFloor", f, -27, 3, 0.2, 0.3, -3, 23, Color3.fromRGB(120, 124, 128), Enum.Material.Concrete)
	box(m, "BackWall", f, -27, 3, 0.3, H, 22, 23, wall, Enum.Material.Concrete)
	box(m, "SideWall", f, -27, -26, 0.3, H, -3, 22, wall, Enum.Material.Concrete)
	box(m, "SideWall", f, 2, 3, 0.3, H, -3, 22, wall, Enum.Material.Concrete)
	box(m, "BayHeader", f, -27, 3, 10.4, H, -3, -2, accent, Enum.Material.Metal)
	box(m, "Roof", f, -28, 4, H, H + 0.8, -4, 23.5, C.WHITE, Enum.Material.Concrete, { CastShadow = true })
	Build.roomLight(m, f, -25, 1, 10.3, 8, 10, Color3.fromRGB(240, 246, 255), 22)
	-- The roof sign (painted at levels 1-2: it takes the light; level 3 adds neon tubes round it).
	box(m, "SignLeg", f, -20.3, -19.7, H + 0.8, H + 1.6, -2.4, -1.8, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	box(m, "SignLeg", f, -4.3, -3.7, H + 0.8, H + 1.6, -2.4, -1.8, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	local sign = box(m, "Sign", f, -25, 1, H + 1.6, H + 7.6, -2.6, -2, Color3.fromRGB(40, 92, 160), Enum.Material.Wood)
	Build.signGui(sign, front, "SUDS & SHINE", "CAR WASH", C.WHITE, Color3.fromRGB(255, 236, 160), true)
	-- The owner plate on the bay header: FOR SALE, or the featured owner's name (publishOwners).
	local plate = box(m, "OwnerPlate", f, -21, -5, 10.7, 12.7, -3.16, -3.04, C.DARK, Enum.Material.Metal, DETAIL)
	local plateGui = Build.signGui(plate, front, "FOR SALE · " .. money(def.Price), nil, C.GOLD)

	-- The bays: bay 1 always; bay 2 from level 2, bay 3 from level 3 (closed off with cones until then).
	for i, b in ipairs(def.Layout.Bays) do
		local g = i == 1 and m or group(m, "Bay" .. i, i, nil)
		local c = b.X
		box(g, "Drain", f, c - 2, c + 2, 0.3, 0.33, 9, 11, C.DARK_METAL, Enum.Material.DiamondPlate, DETAIL)
		box(g, "WashBoom", f, c - 0.3, c + 0.3, 10.6, 11.1, 1, 21, C.DARK_METAL, Enum.Material.Metal, DETAIL)
		box(g, "Hose", f, c + 3.05, c + 3.35, 5.5, 10.6, 15.85, 16.15, C.STEEL, Enum.Material.Metal, DETAIL)
		box(g, "Nozzle", f, c + 2.9, c + 3.5, 5, 5.5, 15.7, 16.3, C.DARK_METAL, Enum.Material.Metal, DETAIL)
		post(g, "Brush", f, c - 3.4, 19.4, 0.3, 7, 2.2, accent, Enum.Material.Fabric, DETAIL)
		local board = box(g, "BayBoard", f, c - 3.4, c + 3.4, 7, 9.4, 21.8, 22, C.DARK, Enum.Material.Metal, DETAIL)
		Build.signGui(board, front, "BAY " .. i, "SPRAY · SCRUB · RINSE", C.WHITE, C.SOFT_BLUE)
		box(g, "SoapRack", f, c + 2.6, c + 4, 2, 5.5, 20.4, 21.8, Color3.fromRGB(70, 150, 220), Enum.Material.SmoothPlastic, DETAIL)
		box(g, "LaneArrow", f, c - 0.4, c + 0.4, 0.2, 0.24, -14, -7, C.WHITE, Enum.Material.SmoothPlastic, DETAIL)
		box(g, "LaneArrow", f, c - 1.6, c + 1.6, 0.2, 0.24, -7, -6.2, C.WHITE, Enum.Material.SmoothPlastic, DETAIL)
		if i > 1 then
			-- Before its level: a barrier across the bay's mouth and two cones.
			local shut = group(m, "BayClosed" .. i, 1, i - 1)
			box(shut, "Barrier", f, c - 4, c + 4, 2.6, 3.3, -1.3, -1, C.SAFETY, Enum.Material.SmoothPlastic, DETAIL)
			for _, dx in ipairs({ -3.2, 3.2 }) do
				box(shut, "BarrierLeg", f, c + dx - 0.15, c + dx + 0.15, 0.3, 2.6, -1.3, -1, C.DARK_METAL, Enum.Material.Metal, DETAIL)
				post(shut, "Cone", f, c + dx, -3.5, 0.3, 1.8, 1, C.CONE, Enum.Material.SmoothPlastic, DETAIL)
			end
			local closed = box(shut, "ClosedBoard", f, c - 2.4, c + 2.4, 3.3, 4.7, -1.2, -1.05, C.DARK, Enum.Material.SmoothPlastic, DETAIL)
			Build.signGui(closed, front, "COMING SOON", nil, C.SAFETY, nil, true)
		end
	end
	-- Partitions between the bays, with the bays.
	box(group(m, "Partition2", 2, nil), "Partition", f, -17.5, -16.5, 0.3, 10.4, 3, 22, wall, Enum.Material.Concrete)
	box(group(m, "Partition3", 3, nil), "Partition", f, -7.5, -6.5, 0.3, 10.4, 3, 22, wall, Enum.Material.Concrete)

	-- THE DETAILING ROOM (x 3..15.5) -------------------------------------------------------------------------
	box(m, "DetailFloor", f, 3, 15.5, 0.2, 0.4, 1, 23, Color3.fromRGB(150, 156, 164), Enum.Material.SmoothPlastic)
	box(m, "BackWall", f, 3, 15.5, 0.4, OH, 22, 23, wall, Enum.Material.Plaster)
	box(m, "MidWall", f, 15.5, 16.5, 0.4, OH, 1, 22, wall, Enum.Material.Plaster)
	box(m, "Jamb", f, 3, 4, 0.4, 9.5, 1, 2, wall, Enum.Material.Plaster)
	box(m, "Jamb", f, 14.5, 16.5, 0.4, 9.5, 1, 2, wall, Enum.Material.Plaster)
	box(m, "DoorHeader", f, 3, 16.5, 9.5, OH, 1, 2, wall, Enum.Material.Plaster)
	box(m, "Roof", f, 2.5, 27.5, OH, OH + 0.6, 0.5, 23.5, C.WHITE, Enum.Material.Concrete, { CastShadow = true })
	-- Levels 1-3: the roll-up door is down.
	local shutDoor = group(m, "DetailShut", 1, 3)
	box(shutDoor, "RollUpDoor", f, 4, 14.5, 0.4, 9.5, 1.3, 1.6, Color3.fromRGB(150, 152, 150), Enum.Material.Metal)
	for i = 1, 5 do
		local y = 0.4 + i * 1.6
		box(shutDoor, "Slat", f, 4, 14.5, y - 0.08, y + 0.08, 1.15, 1.3, Color3.fromRGB(120, 122, 120), Enum.Material.Metal, DETAIL)
	end
	-- Level 4+: the detailing garage.
	local det = group(m, "Detailing", 4, nil)
	box(det, "RolledDoor", f, 4, 14.5, 8.8, 9.5, 1.3, 2.2, Color3.fromRGB(150, 152, 150), Enum.Material.Metal, DETAIL)
	for _, x in ipairs({ 4.6, 13.9 }) do
		box(det, "LiftPost", f, x - 0.5, x + 0.5, 0.4, 8, 11.5, 12.5, Color3.fromRGB(200, 60, 50), Enum.Material.Metal, DETAIL)
	end
	box(det, "LiftArm", f, 5, 13.5, 3.6, 4, 6, 18, C.DARK_METAL, Enum.Material.DiamondPlate, DETAIL)
	Build.carProp(det, f, 9.25, 4, 12, 0, Color3.fromRGB(20, 20, 24))
	box(det, "ToolChest", f, 3.6, 6.6, 0.4, 4.2, 20.2, 22, Color3.fromRGB(200, 40, 40), Enum.Material.Metal, DETAIL)
	box(det, "ToolChest", f, 12, 15, 0.4, 3.4, 20.2, 22, Color3.fromRGB(200, 40, 40), Enum.Material.Metal, DETAIL)
	post(det, "Polisher", f, 13.6, 5, 0.4, 3.4, 0.6, C.STEEL, Enum.Material.Metal, DETAIL)
	Build.roomLight(det, f, 4.5, 14, OH - 0.1, 6, 8, Color3.fromRGB(236, 244, 255), 20)
	Build.roomLight(det, f, 4.5, 14, OH - 0.1, 15, 17, Color3.fromRGB(236, 244, 255), 20)
	local detSign = box(det, "DetailSign", f, 4.5, 14, 9.6, 10.9, 0.84, 0.98, C.DARK, Enum.Material.Metal, DETAIL)
	Build.signGui(detSign, front, "DETAILING", nil, C.WHITE)
	neon(det, f, 4.5, 14, 9.5, 9.6, 0.84, 0.98, glow)

	-- THE OFFICE (x 16.5..27) ----------------------------------------------------------------------------------
	box(m, "OfficeFloor", f, 16.5, 27, 0.2, 0.4, 1, 23, Color3.fromRGB(214, 214, 208), Enum.Material.Marble)
	box(m, "BackWall", f, 16.5, 27, 0.4, OH, 22, 23, wall, Enum.Material.Plaster)
	box(m, "SideWall", f, 26, 27, 0.4, OH, 1, 22, wall, Enum.Material.Plaster)
	Build.shopfront(m, f, 16.5, 18.5, 1, 2, OH, wall, Enum.Material.Plaster, 2.6, 8.5)
	Build.shopfront(m, f, 23.5, 27, 1, 2, OH, wall, Enum.Material.Plaster, 2.6, 8.5)
	box(m, "Lintel", f, 18.5, 23.5, 9, OH, 1, 2, wall, Enum.Material.Plaster)
	box(m, "DoorFrame", f, 18.2, 18.5, 0.4, 9, 0.9, 2.1, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	box(m, "DoorFrame", f, 23.5, 23.8, 0.4, 9, 0.9, 2.1, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	box(m, "Awning", f, 18, 24, 9.2, 9.6, -2, 1, accent, Enum.Material.Metal, SHADE)
	Build.lamp(m, f, 20.5, 21.5, 8.4, 8.9, -1.2, -0.2, 18)
	-- The counter and the register (where break-in robbers rummage), shelves of soap, PAY HERE.
	box(m, "Counter", f, 17.5, 25.5, 0.4, 3.8, 13, 15, Color3.fromRGB(60, 64, 70), Enum.Material.Metal)
	box(m, "CounterTop", f, 17.3, 25.7, 3.8, 4.2, 12.8, 15.2, C.WHITE, Enum.Material.Marble)
	local reg = def.Layout.Register
	box(m, "Register", f, reg.X - 0.8, reg.X + 0.8, 4.2, 5.3, reg.Z - 0.6, reg.Z + 0.6, C.DARK, Enum.Material.SmoothPlastic, DETAIL)
	box(m, "Shelf", f, 17.5, 25.5, 4, 4.3, 20.6, 22, C.STEEL, Enum.Material.Metal, DETAIL)
	box(m, "Shelf", f, 17.5, 25.5, 6.5, 6.8, 20.6, 22, C.STEEL, Enum.Material.Metal, DETAIL)
	local tints = { Color3.fromRGB(70, 150, 220), Color3.fromRGB(240, 200, 60), Color3.fromRGB(230, 90, 120) }
	for i = 0, 6 do
		local x = 18.3 + i * 1.05
		box(m, "Bottle", f, x - 0.35, x + 0.35, 4.3, 5.5, 21, 21.7, tints[i % 3 + 1], Enum.Material.SmoothPlastic, DETAIL)
		box(m, "Bottle", f, x - 0.35, x + 0.35, 6.8, 8, 21, 21.7, tints[(i + 1) % 3 + 1], Enum.Material.SmoothPlastic, DETAIL)
	end
	local pay = box(m, "PaySign", f, 19, 24.6, 8.2, 9.6, 12.9, 13.1, C.DARK, Enum.Material.SmoothPlastic, DETAIL)
	Build.signGui(pay, front, "PAY HERE", nil, C.WHITE)
	Build.roomLight(m, f, 18, 25, OH - 0.1, 7, 11, Color3.fromRGB(255, 244, 228), 18)

	-- THE FORECOURT -------------------------------------------------------------------------------------------
	-- The shine lane and its gantry (the BizShinePrompt hangs under the beam: see buildBusiness).
	local sh = def.Layout.Shine
	Build.bayLines(m, f, sh.X, -14, 10, 20, "SHINE $100")
	for _, x in ipairs({ sh.X - 5.6, sh.X + 5.6 }) do
		box(m, "GantryPost", f, x - 0.4, x + 0.4, 0.2, 10.5, sh.Z - 0.4, sh.Z + 0.4, C.STEEL, Enum.Material.Metal)
	end
	box(m, "GantryBeam", f, sh.X - 6, sh.X + 6, 9.5, 10.5, sh.Z - 0.6, sh.Z + 0.6, C.STEEL, Enum.Material.Metal, DETAIL)
	box(m, "SprayBar", f, sh.X - 4.5, sh.X + 4.5, 9.1, 9.5, sh.Z - 0.2, sh.Z + 0.2, Color3.fromRGB(70, 150, 220), Enum.Material.Metal, DETAIL)
	local gantrySign = box(m, "GantrySign", f, sh.X - 5, sh.X + 5, 10.5, 12.3, sh.Z - 0.15, sh.Z + 0.05, C.DARK, Enum.Material.Metal, DETAIL)
	Build.signGui(gantrySign, front, "DRIVE-THRU SHINE", "$100 · SPARKLES FOR 30 MIN", C.WHITE, C.SOFT_BLUE)
	-- The PICK-UP box for detail deliveries.
	local pu = def.Layout.Pickup
	Build.bayLines(m, f, pu.X, pu.Z, 10, 18, "PICK-UP")
	-- A palm at the office's front corner.
	Build.planterPalm(m, f, 25.6, -2.9, 16)

	-- Level 2: the vacuum station along the left edge.
	local vac = group(m, "Vacuum", 2, nil)
	for _, z in ipairs({ -20, -12 }) do
		post(vac, "VacuumPost", f, -27.1, z, 0.2, 5, 1.2, C.SAFETY, Enum.Material.Metal, DETAIL)
		box(vac, "VacuumHead", f, -27.6, -26.2, 5.2, 6.2, z - 0.7, z + 0.7, C.DARK_METAL, Enum.Material.Metal, DETAIL)
		box(vac, "VacuumHose", f, -26.4, -26.1, 1.2, 5.2, z + 0.5, z + 0.8, C.DARK, Enum.Material.SmoothPlastic, DETAIL)
	end
	local vacSign = box(vac, "VacuumSign", f, -27.6, -27.3, 6.4, 7.8, -18.5, -13.5, C.DARK, Enum.Material.Metal, DETAIL)
	Build.signGui(vacSign, Enum.NormalId.Right, "VACUUM", nil, C.SAFETY)

	-- Level 3: neon round the roof sign, on the header and the office roof edge, the pole sign with its
	-- bubbles, a waiting bench and a planter by the office, a customer car waiting.
	local lit = group(m, "Neon3", 3, nil)
	neon(lit, f, -25.2, 1.2, H + 7.6, H + 7.9, -2.7, -1.9, glow)
	neon(lit, f, -25.2, 1.2, H + 1.3, H + 1.6, -2.7, -1.9, glow)
	neon(lit, f, -25.5, -25.2, H + 1.3, H + 7.9, -2.7, -1.9, glow)
	neon(lit, f, 1.2, 1.5, H + 1.3, H + 7.9, -2.7, -1.9, glow)
	neon(lit, f, -27, 3, 10.1, 10.4, -3.2, -2.9, glow)
	neon(lit, f, 2.5, 27.5, OH + 0.1, OH + 0.5, 0.2, 0.5, glow)
	post(lit, "SignPole", f, 26.6, -23, 0.2, 13, 0.8, C.STEEL, Enum.Material.Metal)
	local road = box(lit, "RoadSign", f, 26.3, 26.9, 13, 18.6, -24.6, -18, C.DARK, Enum.Material.Metal)
	Build.signGui(road, Enum.NormalId.Left, "SUDS & SHINE", "CAR WASH · OPEN 24/7", C.WHITE, C.SOFT_BLUE)
	Build.signGui(road, Enum.NormalId.Right, "SUDS & SHINE", "CAR WASH · OPEN 24/7", C.WHITE, C.SOFT_BLUE)
	neon(lit, f, 26.3, 26.9, 18.6, 18.9, -24.6, -18, glow)
	for i, o in ipairs({ { 19.9, -23 }, { 20.2, -21.2 }, { 19.8, -19.4 } }) do
		local d = 2.2 - i * 0.3
		Build.part(lit, "Bubble", Vector3.new(d, d, d), f * CFrame.new(26.6, o[1], o[2]), Color3.fromRGB(190, 230, 255), Enum.Material.Glass,
			{ Shape = Enum.PartType.Ball, Transparency = 0.35, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	box(lit, "BenchSeat", f, 16.9, 19.3, 1.5, 1.8, -2.6, -1.4, Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks, DETAIL)
	box(lit, "BenchBack", f, 16.9, 19.3, 1.8, 3.2, -1.5, -1.3, Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks, DETAIL)
	for _, x in ipairs({ 17.1, 19.1 }) do
		box(lit, "BenchLeg", f, x - 0.15, x + 0.15, 0.2, 1.5, -2.5, -1.5, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	end
	Build.carProp(lit, f, -22, 0.2, -17.5, math.pi, Color3.fromRGB(196, 54, 54))

	-- Level 4: a second car waiting.
	Build.carProp(group(m, "Queue4", 4, nil), f, -12, 0.2, -17.5, math.pi, Color3.fromRGB(230, 230, 236))

	-- Level 5: the drive-through tunnel over the shine lane: arches with LED strips, roller brushes, the sign.
	local tun = group(m, "Tunnel5", 5, nil)
	local ledColors = { glow, C.PINK, glow, C.PINK }
	for i, z in ipairs({ -23.5, -18, -6.5, -3.6 }) do
		for _, x in ipairs({ sh.X - 5.6, sh.X + 5.6 }) do
			box(tun, "ArchPost", f, x - 0.35, x + 0.35, 0.2, 10, z - 0.35, z + 0.35, C.WHITE, Enum.Material.Metal, DETAIL)
			neon(tun, f, x - 0.5, x + 0.5, 0.6, 9.6, z - 0.1, z + 0.1, ledColors[i])
		end
		box(tun, "ArchBeam", f, sh.X - 5.95, sh.X + 5.95, 10, 10.7, z - 0.35, z + 0.35, C.WHITE, Enum.Material.Metal, DETAIL)
		neon(tun, f, sh.X - 5.6, sh.X + 5.6, 9.85, 10, z - 0.1, z + 0.1, ledColors[i])
	end
	box(tun, "TunnelRoof", f, sh.X - 6, sh.X + 6, 10.7, 11, -24, -3.4, Color3.fromRGB(220, 232, 244), Enum.Material.Glass,
		{ Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false })
	for _, z in ipairs({ -20.5, -9 }) do
		for _, x in ipairs({ sh.X - 4.4, sh.X + 4.4 }) do
			post(tun, "RollerBrush", f, x, z, 0.4, 7.5, 1.8, (z < -15) and C.PINK or glow, Enum.Material.Fabric, DETAIL)
		end
	end
	local tunSign = box(tun, "TunnelSign", f, sh.X - 5.5, sh.X + 5.5, 11, 13, -23.9, -23.7, C.DARK, Enum.Material.Metal, DETAIL)
	Build.signGui(tunSign, front, "★ TUNNEL WASH ★", "SUDS & SHINE", C.GOLD, C.WHITE)

	return plateGui:FindFirstChild("Title")
end

-- Warn (only) if a lot overlaps something already in the city, so it can be moved (Studio's Output says).
local function checkLot(name, cf, size)
	local list = {}
	for _, n in ipairs({ "City", "Heists", "Spawns", "Activities", "Dealerships", "Homes" }) do
		local folder = Workspace:FindFirstChild(n)
		if folder then
			table.insert(list, folder)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	-- (The box starts a stud above the ground, so the ground tiles, kerbs and road paint never count.)
	local hits = {}
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, size, params)) do
		table.insert(hits, p:GetFullName())
	end
	if #hits > 0 then
		warn(string.format("[BusinessService] the %s lot overlaps %d part(s), e.g. %s", name, #hits, table.concat(hits, ", ", 1, math.min(#hits, 4))))
	end
end

local function buildBusiness(def, shops)
	local f = Businesses.Frame(def)
	local m = Instance.new("Model")
	m.Name = "Business_" .. def.Id
	m:SetAttribute("BusinessId", def.Id)
	m:SetAttribute("PlaceName", def.Name)
	m:SetAttribute("PlaceKind", "Business")
	local lot = Build.box(m, "Lot", f, -28, 28, 0, 0.2, -25, 25, C.CONCRETE, Enum.Material.Concrete)
	m.PrimaryPart = lot
	Build.box(m, "Kerb", f, -28, 28, 0.2, 0.35, -25, -24.6, Color3.fromRGB(196, 192, 184), Enum.Material.Concrete, DETAIL)
	-- Its building: one of STYLES here, or its job module's Style (JOB MODULES in the header); none: not built.
	local mod = Jobs[def.Style or ""]
	local plate
	if STYLES[def.Style or "CarWash"] then
		plate = STYLES[def.Style or "CarWash"](m, f, def)
	elseif mod and type(mod.Style) == "function" then
		plate = mod.Style(m, f, def, Api)
	else
		m:Destroy()
		error("no building for style " .. tostring(def.Style))
	end
	Build.tagProps(m, def.Id)
	-- The door prompt (everyone; BusinessClient relabels it Manage / Work here / Buy).
	local door = Build.holder(m, "DoorPoint", f, def.Layout.Door + Vector3.new(0, 4.5, 0), Vector3.new(4, 8, 1))
	local doorPrompt = Build.prompt(door, "BusinessDoor", "Business · Buy " .. money(def.Price), def.Name, 10)
	doorPrompt:SetAttribute("BusinessId", def.Id)
	doorPrompt.Triggered:Connect(function(player)
		BusinessService._OnDoor(player, def)
	end)
	-- The shine prompt under the gantry (from a driver's seat; BusinessClient shows it to drivers of their own car).
	if def.Layout.Shine then
		local point = Build.holder(m, "ShinePoint", f, def.Layout.Shine + Vector3.new(0, 4, 0), Vector3.new(2, 2, 2))
		local shine = Build.prompt(point, "BizShinePrompt", "Shine " .. money((def.Service and def.Service.Price) or SH.Price),
			def.Brand or def.Name, 14)
		shine:SetAttribute("BusinessId", def.Id)
		shine:SetAttribute("InCar", true) -- (PromptGate: works from a driver's seat)
		shine.Triggered:Connect(function(player)
			onShine(player, def)
		end)
	end
	-- The counter's service prompt (Palm Grind's cold brew; on foot: PromptGate hides it in a seat).
	if def.Layout.Service and def.Service then
		local spot = def.Layout.Service
		local point = Build.holder(m, "ServicePoint", f, Vector3.new(spot.X, 4.6, spot.Z + 1.2), Vector3.new(2, 2, 1))
		local p = Build.prompt(point, "BizServicePrompt", def.Service.Name .. " " .. money(def.Service.Price), def.Brand or def.Name, 8)
		p:SetAttribute("BusinessId", def.Id)
		p.Triggered:Connect(function(player)
			onService(player, def)
		end)
	end
	checkLot(def.Name, f * CFrame.new(0, 10, 0), Vector3.new(54, 18, 48))
	pcall(function()
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole lot streams in at once
	end)
	m.Parent = shops
	S.sites[def.Id] = { model = m, def = def, plate = plate }
end

------------------------------------------------------------------ the door and requests

function BusinessService._OnDoor(player, def)
	if not RateLimit.Allow(player, "BusinessDoor", 2, 3) then
		return
	end
	if not DataService.Get(player) or player:GetAttribute("Side") == "Prisoner" or not alive(player) then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - Businesses.DoorPosition(def)).Magnitude > Businesses.DoorRange then
		return
	end
	settle(player)
	pushState(player)
	if owned(player, def.Id) then
		R.card:FireClient(player, { Id = def.Id, Mode = "Manage" })
		return
	end
	local boss = jobOwner(player, def, nil)
	if boss then
		R.card:FireClient(player, { Id = def.Id, Mode = "Crew", Owner = boss.UserId, OwnerName = boss.DisplayName, Level = levelOf(boss, def) })
		return
	end
	R.card:FireClient(player, { Id = def.Id, Mode = "Buy" })
end

local function onRequest(player, action, id, arg, arg2)
	if type(action) ~= "string" then
		return
	end
	if action == "Step" then
		local job = S.jobs[player]
		if job and job.mod then
			local mod = job.mod
			if type(mod.Step) == "function" and RateLimit.Allow(player, "BizModStep", 4, 6) then
				local ok, err = pcall(mod.Step, player, job, id, Api)
				if not ok then
					warn("[BusinessService] job module Step: " .. tostring(err))
				end
			end
			return
		end
		washStep(player, id, arg) -- (its own rate limit: a wash sends a dozen of these)
		return
	end
	if not RateLimit.Allow(player, "Business", 4, 6) then
		return
	end
	if action == "State" then
		settle(player)
		pushState(player)
		return
	elseif action == "EndJob" then
		endJob(player, "Player")
		return
	elseif action == "Scare" then
		onScare(player, arg)
		return
	end
	local def = type(id) == "string" and Businesses.ById[id] or nil
	if not def or not def.Enabled or not S.sites[def.Id] or not DataService.Get(player) then
		return
	end
	if action == "Buy" then
		buy(player, def)
	elseif action == "Collect" then
		collect(player, def, arg == "Remote")
	elseif action == "Upgrade" then
		upgrade(player, def)
	elseif action == "Job" and type(arg) == "string" and Businesses.HasJob(def, arg) then
		startJob(player, def, arg, arg2)
	elseif action == "Mod" then
		-- (M5) A job module's own request (the Nightclub's LEAVE inside the club).
		local mod = Jobs[def.Style or ""]
		if mod and type(mod.Request) == "function" then
			local ok, err = pcall(mod.Request, player, def, arg, arg2, Api)
			if not ok then
				warn("[BusinessService] job module Request: " .. tostring(err))
			end
		end
	end
end

------------------------------------------------------------------ public

-- Is the feature running in this server?
function BusinessService.On()
	return S.on
end

-- The ids of the businesses this player owns (config order).
function BusinessService.OwnedBy(player)
	local ids = {}
	for _, def in ipairs(Businesses.List) do
		if owned(player, def.Id) then
			table.insert(ids, def.Id)
		end
	end
	return ids
end

-- For MapService (GPS, minimap, big map): every built business's door. { Name, Kind, Pos, Id }.
function BusinessService.Places()
	local list = {}
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and S.sites[def.Id] then
			table.insert(list, {
				Name = def.Name, Id = def.Id, Pos = Businesses.DoorPosition(def),
				Kind = "Business · " .. Businesses.ShortPrice(def.Price),
			})
		end
	end
	return list
end

-- CombatService routes punches and shots on NPCKind "BizRobber" here. Only the robbers' owner and their crew
-- can knock them down (anyone else's hit does nothing: returns false). Returns true if it counted.
function BusinessService.NPCHit(model, attacker, _damage, dir, _kind)
	local r = S.robbers[model]
	if not r or r.state ~= "Robbing" or r.rec.done or typeof(attacker) ~= "Instance" or not attacker:IsA("Player") then
		return false
	end
	local owner = r.rec.owner
	if attacker ~= owner and not sameCrew(owner, attacker) then
		return false
	end
	r.state = "Down"
	r.token += 1
	model:SetAttribute("AimTarget", nil)
	model:SetAttribute("NPCKind", nil)
	model:SetAttribute("Pose", nil)
	local push = typeof(dir) == "Vector3" and flat(dir) or Vector3.zero
	push = push.Magnitude > 0.05 and push.Unit or -r.root.CFrame.LookVector
	r.root.Anchored = false
	pcall(function()
		require(ReplicatedStorage.Shared.Util.Ragdoll).Start(model, push * 12 + Vector3.new(0, 8, 0), { NoCap = true })
	end)
	say(r, "Ow! Okay, I give up!", 2)
	robberStopped(r, attacker)
	task.delay(K.DOWN_TIME, function()
		fadeOut(model, 0.8)
	end)
	return true
end

-- Studio only: test helpers (see the header). Returns a short answer string.
function BusinessService.Debug(player, cmd, id, value)
	if not RunService:IsStudio() then
		return "studio only"
	end
	if cmd == "crew" then
		Workspace:SetAttribute("BizTestCrew", value == true or value == "true" or value == 1)
		return "BizTestCrew = " .. tostring(Workspace:GetAttribute("BizTestCrew"))
	elseif cmd == "scale" then
		Workspace:SetAttribute("BusinessTimeScale", tonumber(value) or 1)
		return "BusinessTimeScale = " .. tostring(Workspace:GetAttribute("BusinessTimeScale"))
	end
	if type(player) == "string" then
		player = Players:FindFirstChild(player)
	end
	local okPlayer, isPlayer = pcall(function()
		return player:IsA("Player")
	end)
	if not okPlayer or not isPlayer then
		return "no player"
	end
	local data = DataService.Get(player)
	if not data then
		return "save not loaded"
	end
	if type(data.businesses) ~= "table" then
		data.businesses = {}
	end
	settle(player)
	if cmd == "state" then
		local parts = { string.format("empire %d (%d xp) play %ds", empireRank(player), math.floor(empireXP(player)), math.floor(S.play[player] or 0)) }
		for _, d in ipairs(Businesses.List) do
			local e = owned(player, d.Id)
			if e then
				table.insert(parts, string.format("%s lv=%d register=%d/%d lifetime=%d jobs=%d%s", d.Id, e.level, math.floor(e.register),
					Businesses.Cap(d, e.level), math.floor(e.lifetime), e.jobsDone,
					e.dirty and string.format(" dirty=%d/%d", math.floor(e.dirty), Businesses.DirtyCap(d, e.level)) or ""))
			end
		end
		local b = S.breakins[player]
		table.insert(parts, b and (b.active and "BREAK-IN ON" or string.format("next break-in at play %ds", math.floor(b.nextAt))) or "")
		return table.concat(parts, " | ")
	elseif cmd == "xp" then
		addEmpireXP(player, tonumber(value) or 0)
		pushState(player)
		return "empire xp " .. math.floor(empireXP(player))
	elseif cmd == "rank" then
		-- (M4) Set your Empire rank (value 1-10): your Empire XP becomes exactly what that rank needs. Going up
		-- stamps every rank on the way, as earning it would; going down just sets it (to test the Empire 2 gate).
		local rank = math.clamp(math.floor(tonumber(value) or 1), 1, E.MaxRank)
		local want = E.XPFor[rank]
		local have = empireXP(player)
		if want > have then
			addEmpireXP(player, want - have)
		else
			data.empireXP = want
			publishOwned(player)
		end
		pushState(player)
		return string.format("empire rank %d (%d xp)", empireRank(player), math.floor(empireXP(player)))
	elseif cmd == "cash" then
		EconomyService.AddCash(player, tonumber(value) or 0, "debug")
		return "cash " .. tostring(player:GetAttribute("Cash"))
	elseif cmd == "shine" then
		player:SetAttribute("ShineUntil", nil)
		return "shine cleared"
	elseif cmd == "coldbrew" then
		player:SetAttribute("ColdBrewUntil", nil)
		return "cold brew cleared"
	elseif cmd == "vip" then
		S.forceVip[player] = true
		return "the next rush order ends at a VIP home"
	elseif cmd == "next" then
		local v = tostring(value or id or "")
		if v ~= "Sports" and not W.Specials[v] then
			return "next: Muddy, Classic, Wedding (a wash customer) or Sports (a delivery)"
		end
		player:SetAttribute("BizTestNext", v) -- (an attribute, not a table keyed by the player: used up by the next car)
		return "your next " .. (v == "Sports" and "delivery is a sports car" or ("wash customer is a " .. W.Specials[v].Name))
	end
	-- The job modules' own helpers (the Print Shop: dirty, raid, endraid, testcop, heat).
	for _, mod in pairs(Jobs) do
		if type(mod.Debug) == "function" then
			local ok, answer = pcall(mod.Debug, player, cmd, id, value, Api)
			if not ok then
				return "error: " .. tostring(answer)
			elseif answer ~= nil then
				return tostring(answer)
			end
		end
	end
	local def = Businesses.ById[id or ""]
	if cmd == "breakin" then
		if S.breakins[player] and S.breakins[player].active then
			return "a break-in is on already"
		end
		if def and not Businesses.BreakInEligible(def) then
			return def.Id .. " is shady: it gets police raids, not break-ins (try raid)"
		end
		def = def or breakInTarget(player)
		if not def then
			for _, d in ipairs(Businesses.List) do
				if owned(player, d.Id) and Businesses.BreakInEligible(d) then
					def = d
					break
				end
			end
		end
		local entry = def and owned(player, def.Id)
		if not entry then
			return "owns no business to break into"
		end
		entry.register = math.max(entry.register, B.MinRegister)
		S.breakins[player] = S.breakins[player] or { nextAt = 0 }
		local ok = startBreakIn(player, def, tonumber(value))
		pushState(player)
		return ok and ("break-in at " .. def.Id) or "couldn't spawn the robbers"
	end
	if not def or not def.Enabled then
		return "unknown or disabled business " .. tostring(id)
	end
	local entry = data.businesses[def.Id]
	if cmd == "give" then
		if not entry then
			data.businesses[def.Id] = fresh()
		end
	elseif cmd == "remove" then
		data.businesses[def.Id] = nil
	elseif type(entry) ~= "table" then
		return "doesn't own " .. def.Id
	elseif cmd == "level" then
		entry.level = Businesses.ClampLevel(tonumber(value) or 1)
	elseif cmd == "fill" then
		entry.register = Businesses.Cap(def, entry.level)
	elseif cmd == "register" then
		entry.register = math.max(0, tonumber(value) or 0)
	else
		return "unknown command " .. tostring(cmd)
	end
	publishOwned(player)
	pushState(player)
	publishOwners()
	return "ok"
end

function BusinessService.Init()
	S.on = RunService:IsStudio() or Businesses.Live == true
	ReplicatedStorage:SetAttribute("BusinessesOn", S.on)
	if not S.on then
		return -- (the launch switch: see the header)
	end
	R.notify = Remotes.Event("Notify")
	R.card = Remotes.Event("BusinessCard")
	R.state = Remotes.Event("BusinessState")
	R.result = Remotes.Event("BusinessResult")
	R.job = Remotes.Event("BusinessJob")
	Remotes.Event("RequestBusiness").OnServerEvent:Connect(onRequest)

	-- The job modules (JOB MODULES in the header) and what they may use here.
	Api.Build, Api.C, Api.DETAIL, Api.SHADE, Api.money = Build, C, DETAIL, SHADE, money
	Api.rng = S.rng
	-- (addEmpireXP: jobXP, which also counts it on the player's shift for the report)
	Api.levelOf, Api.creditOwner, Api.addEmpireXP, Api.progressEvent = levelOf, creditOwner, jobXP, progressEvent
	Api.endJob, Api.refuse, Api.pushState, Api.service = endJob, refuse, pushState, service
	Api.rootOf, Api.humOf, Api.flat = rootOf, humOf, flat
	Api.fire = function(player, kind, info)
		if player.Parent == Players then
			R.job:FireClient(player, kind, info)
		end
	end
	Api.takeVip = function(player) -- (Debug "vip": once)
		local v = S.forceVip[player] == true
		S.forceVip[player] = nil
		return v
	end
	-- (M3: what the Print Shop's shift and raids use)
	Api.owned, Api.sameCrew, Api.alive, Api.atLot, Api.settle = owned, sameCrew, alive, atLot, settle
	Api.result, Api.notifyKey, Api.timeScale, Api.testCrew = result, notifyKey, timeScale, testCrew
	Api.refreshAlarms, Api.say, Api.fadeOut, Api.npcFolder = refreshAlarms, say, fadeOut, npcFolder
	Api.play = function(player) -- seconds of play this session (x BusinessTimeScale), nil before the save loads
		return S.play[player]
	end
	Api.site = function(id) -- the business's building ({ model, def, plate }), or nil
		return S.sites[id]
	end
	Api.jobOf = function(player) -- the business job this player is on, or nil
		return S.jobs[player]
	end
	Api.setJobKind = function(player, job, kind) -- a module job changing its JobKind (the Print Shop: BizPrint <-> BizLaunder)
		job.jobKind = kind
		if player.Parent == Players then
			player:SetAttribute("JobKind", kind)
		end
	end
	-- (M4: a job module's own customer purchase, Boat Rentals' jet ski rental, goes through the same path as the
	-- shine and the cold brew: the price spent, the featured owner's share and capped Empire XP, the rest a sink)
	Api.serveCustomer = serveCustomer
	-- (M5: the Nightclub's night x2 and the club's crowd by the featured owner's level)
	Api.isNight, Api.featuredOf = isNight, featuredOf
	local folder = script.Parent:FindFirstChild("BusinessJobs")
	for _, def in ipairs(Businesses.List) do
		local module = def.Enabled and def.Style and not STYLES[def.Style] and folder and folder:FindFirstChild(def.Style)
		if module and not Jobs[def.Style] then
			local ok, mod = pcall(require, module)
			if ok and type(mod) == "table" then
				Jobs[def.Style] = mod
			else
				warn("[BusinessService] couldn't load the " .. def.Style .. " job module: " .. tostring(mod))
			end
		end
	end

	-- Workspace.Shops is Coast Arms' folder (CombatService); ours sit beside it. A place saved with old copies
	-- of ours gets them replaced (by name: the gun shop is never touched).
	local shops = Workspace:FindFirstChild("Shops") or Instance.new("Folder")
	shops.Name = "Shops"
	shops.Parent = Workspace
	for _, def in ipairs(Businesses.List) do
		local old = shops:FindFirstChild("Business_" .. def.Id)
		if old then
			old:Destroy()
		end
		if def.Enabled and def.Position and def.Layout then
			local ok, err = pcall(buildBusiness, def, shops)
			if not ok then
				warn("[BusinessService] couldn't build " .. def.Id .. ": " .. tostring(err))
			end
		end
	end

	-- The job modules' start-up, now that their buildings are up (the Print Shop: its raid prompts, BizRaids).
	for style, mod in pairs(Jobs) do
		if type(mod.Init) == "function" then
			local ok, err = pcall(mod.Init, Api)
			if not ok then
				warn("[BusinessService] the " .. style .. " job module's Init: " .. tostring(err))
			end
		end
	end

	DataService.OnLoaded(function(player, data)
		if type(data.businesses) ~= "table" then
			data.businesses = {}
		end
		data.empireXP = math.max(0, num(data.empireXP, 0))
		for id, entry in pairs(data.businesses) do
			local def = Businesses.ById[id]
			if type(entry) == "table" and def and def.Enabled then
				sanitize(entry)
				flagsFor(player, id).full = entry.register >= Businesses.Cap(def, entry.level) -- (no "full" toast on joining)
			end
		end
		S.lastSettle[player] = os.clock() -- the clock starts now: nothing earned while offline
		S.play[player] = 0
		publishOwned(player)
		pushState(player)
		publishOwners()
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- Up to the moment they leave. DataService's leave save writes this same profile table, and its
		-- UpdateAsync only reads it after a yield, so this lands in the save whichever handler runs first.
		settle(player)
		endJob(player, "Left")
		endBreakIn(player, "Gone")
		for _, mod in pairs(Jobs) do
			if type(mod.PlayerLeft) == "function" then
				local ok, err = pcall(mod.PlayerLeft, player, Api) -- (a raid on them, before their save goes)
				if not ok then
					warn("[BusinessService] job module PlayerLeft: " .. tostring(err))
				end
			end
		end
		S.lastSettle[player] = nil
		S.flags[player] = nil
		S.play[player] = nil
		S.breakins[player] = nil
		releaseBay(player)
		task.defer(publishOwners) -- (after they've gone from Players)
	end)

	-- The register tick: settle every owner and send them their numbers; refresh the featured owners.
	task.spawn(function()
		while true do
			task.wait(Businesses.TickSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				if S.lastSettle[player] then
					local ok, err = pcall(function()
						settle(player)
						if #BusinessService.OwnedBy(player) > 0 then
							pushState(player)
						end
					end)
					if not ok then
						warn("[BusinessService] tick for " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
			pcall(publishOwners)
		end
	end)
	-- Jobs four times a second (deliveries, and jobs that should end).
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(jobsTick)
			if not ok then
				warn("[BusinessService] jobs: " .. tostring(err))
			end
		end
	end)
	-- Break-ins and the play clocks once a second.
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local dt = now - last
			local ok, err = pcall(breakInTick, dt)
			last = now
			if not ok then
				warn("[BusinessService] break-ins: " .. tostring(err))
			end
			for style, mod in pairs(Jobs) do
				if type(mod.Second) == "function" then
					local okMod, errMod = pcall(mod.Second, dt, Api) -- (the Print Shop's raids)
					if not okMod then
						warn("[BusinessService] " .. style .. ": " .. tostring(errMod))
					end
				end
			end
		end
	end)
end

return BusinessService
