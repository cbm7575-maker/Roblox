-- Businesses (ModuleScript, ReplicatedStorage.Shared.Config.Businesses)
-- Empire: player-owned businesses (launch/10-BUSINESSES-PRD.md, version 2, approved Nov 4 2026). The one
-- place for every number, place and rule. BusinessService (server) decides everything from it; BusinessClient
-- and the phone's EMPIRE app draw from it; tools/logic-tests/businesses.sh checks its maths offline.
--
-- THE IDEA: a business is a place you PLAY, not a bank account you defend. Owning one gives you:
--   * its own job (Car Wash: the wash-bay mini-game and detail deliveries), paying about 1.3x a normal job;
--   * a small register "trickle" while you are in the server (never while you are offline);
--   * customers: other players buy a service there (Car Wash: the drive-through shine) and the featured owner
--     gets CustomerShare of it, the rest is a money sink;
--   * a building that grows: 5 levels, each with its own props, drawn per device (see "Levels" below);
--   * a risk that fits it: legit businesses only get NPC break-ins (BreakIn below). Players never rob players.
--
-- MANY OWNERS, ONE BUILDING (PRD section 7). Like homes, many players can own the same business. Each owner
-- has their own level, register and job counts (saved as data.businesses[id]). The building in the street
-- shows, on each device: your own level if you own it; else your crewmate's (the highest crewmate owner in
-- the server); else the FEATURED owner's (the highest-level owner in the server, ties: the most lifetime
-- earnings, then the lower UserId); else level 1. The featured owner's name is on the sign and they get the
-- customer money.
--
-- M1: the foundation and the Car Wash. M2: Palm Grind Coffee (RUSH ORDERS and the cold brew; its building and
-- job live in ServerScriptService.Services.BusinessJobs.Coffee). Only entries with Enabled = true are built,
-- listed, buyable or saved-to. The other three are placeholders (name, kind, price, unlock, PRD money targets)
-- so the EMPIRE app can show them as "Coming soon"; they get their lots, layouts and job modules in M3-M5.
--
-- LAUNCH SWITCH: Businesses.Live. In Studio the feature always runs (so it can be tested). In a live server it
-- only runs when Live = true: BusinessService does nothing (no buildings, no remotes) and the phone hides
-- the EMPIRE app. So the code can ship with an unrelated update without the feature going live early. Turn it
-- on only with the owner's explicit go-ahead.
--
-- BALANCE (worked out Nov 4 2026 from the live configs; the PRD's section 9 targets):
--   Baseline: active play for a mid-game player is about $900 a minute. Taxi / courier fares (JobService) pay
--   $150 + 35c a stud + a $100 tip: about $670 a fare, one every 40-50 s, so $800-1,000/min. Store robberies
--   ~$600/min, tier-2 heists ~$1,000/min, winning Downtown Dash ~$1,000/min.
--   Car Wash job target: about $1,150 a minute of WORK at level 1, counting the downtime between jobs:
--     * WASH: one car is about a 30 s cycle for a typical player: 6 s pull-in + 4 s pull-out of the last car,
--       5 s spray hold, ~6-9 s scrubbing 4-6 spots x 3 taps, 5 s rinse hold, ~2 s to pick NEXT CAR. A fast
--       player does it in ~24 s, and nobody beats ~21.5 s (MinTime + the 10 s of pulling in and out). A clean
--       finish (both holds in one go, inside TipTime) adds the tip; assume 85% of washes are clean.
--       $420 + 0.85 x $140 = $539 a wash: x 60 / 30 = ~$1,080/min typical, ~$1,350/min fast.
--       (Re-tuned Nov 4 after the code review: the first numbers, $475 + $160 with 4 + 3 s of pulling in and
--       out, assumed a 32 s cycle that is really ~22 s, so they paid ~$1,600/min.) Time real washes in Studio.
--     * DETAIL DELIVERY: straight line 600-1500 studs (average ~1,050), ~1.3x that by road (~1,365 studs);
--       ~15 s to start and get in, ~30 s each way, ~10 s to call your own car back (CAR) -> ~85 s a delivery.
--       $500 + 65c x 1,365 + an average tip of ~$220 (speed tip less dents) = ~$1,607, x 60 / 85 = ~$1,134/min.
--     So either job, or any mix, averages about $1,150 a minute of work at level 1 (x the level's JobMult).
--   Coffee job target (M2, worked out Nov 4 2026): about $1,250 a minute of WORK at level 1, counting the
--   downtime between orders (parking at the café, walking in, the GRAB hold and walking back out, the drive
--   back from the last address). The same driving model as the detail delivery (~45 studs/s on the road, the
--   road ~1.3x the straight line):
--     * ONE ADDRESS (levels 1): ~17 s at the café (park, walk to the shelf, 2 s GRAB, back to the car), the
--       first leg (400-1,000 studs straight, ~700 -> ~910 of road: ~20 s + ~3 s to stop in the ring) and the
--       drive back (~910 of road, ~20 s): ~60 s an order. A typical driver reaches the address with ~9 s of
--       its ~38 s clock left (910 / 45 + 18): ~2/3 of the $200 tip.
--       $330 order + $60 drop + 40c x (910 + 910) + ~$134 tip = ~$1,252, x 60 / 60.4 = ~$1,244/min.
--     * TWO / THREE ADDRESSES (levels 2-3 / 4-5): each extra leg is 300-700 studs (~650 of road, ~17 s with
--       the stop), and the way back is longer (the last address is ~860 / ~990 studs out). Fewer trips back
--       per address make them pay a little more a minute: ~$1,296 (2 addresses, 82 s) and ~$1,328 (3, 104 s),
--       +4% / +7%, on top of the level's JobMult. A VIP drop (levels 4-5) pays x1.5 (its pay and tip).
--     The drive back is paid (PerStud on the road from the last address back to the café, with the last
--     drop), so a far order pays for its trip home and every order pays about the same a minute.
--   Trickle (PRD: Car Wash $60 -> $150 a minute, register $2k -> $9k): the price pays back in ~7 h online on
--   the trickle alone (25,000 / 60 = 417 min); working the job 40% of the time adds its premium over normal
--   work (40% x ($1,150 - $900) = $100/min), so ~2.6 h. Upgrades (40 / 60 / 80 / 100% of the price) pay back at
--   about the same rate (level 2: +$23/min trickle and +6% job pay; ~3 h). Coffee (PRD: $80 -> $200, register
--   $3k -> $12k) pays its $45,000 back in ~9.4 h on the trickle alone (45,000 / 80 = 563 min; the PRD's own
--   numbers, a little slower than the 6-8 h target), ~3.4 h working the job 40% of the time (+$140/min).
--   STACKING: owning all five at level 5 trickles about $1,330/min. RateScale turns EVERY income (trickle and
--   job pay; never prices) up or down at once if the economy runs hot.
--
-- PLACES. Position = the lot centre on the ground (y = 0); Facing = the direction from the building to the
-- street it faces. Every lot uses the same frame ("lot space"): origin at the lot centre, -Z toward the street,
-- +X to the right as you look at the street from the building. Lots are 56 wide (x -28..28) and 50 deep
-- (z -25..25). The Car Wash lot (and the Coffee and Print Shop lots, for M2/M3) were picked from the place
-- file's own parts on Nov 4 2026: clear of every building, road (12+ studs from the road's edge), home lot,
-- runtime lot, heist / spawn / activity pad and apartment tower entrance. (The Coffee lot was checked again for
-- M2 against the current place file: its 50 x 56 world box, x 480..530, z 877..933, holds nothing; its street
-- edge is 14 studs from Marina Link's (x 434..466); the Car Meet's and the Courier Depot's runtime lots are
-- 40+ studs to the north.) The buildings go in Workspace.Shops
-- (beside Coast Arms), which the car-spawn check, CarjackService, Look4's palms and billboards and
-- ApartmentService already keep clear of.
-- Layout (lot space, on the ground):
--   Door      the bottom middle of the doorway: the Buy / Manage prompt
--   Register  the till on the counter: where break-in robbers rummage
--   Robbers   where the 1-2 robbers stand (in front of the counter, facing it)
--   Exit      where scared robbers run to before they vanish (out on the forecourt)
--   Bays      wash bay centres (a customer car's middle), bay 1 first; Bays[level] of them are open
--   BayMouth  z of a customer car's middle where it starts its pull-in (at the bays' open front)
--   Shine     the drive-through shine lane's gantry (the "Shine $100" prompt hangs here)
--   Pickup    where a detail-delivery customer car waits (facing the street)
--   Service   (Coffee) the ORDER HERE spot in front of the counter, where a customer stands: the cold brew prompt
--   Orders    (Coffee) the RUSH ORDERS pick-up shelf's spot in front of the counter: where a worker holds GRAB
-- Jobs: what START JOB offers there ({ Kind, Label }; BusinessService checks the kind against this list).
-- Service: the customer purchase ({ Name, Price, Kind = "Shine" | "ColdBrew", Words = in the owner's toast }).

local Businesses = {}

------------------------------------------------------------------ switches and the economy

-- Live servers only run the feature when this is true (Studio always does; see LAUNCH SWITCH above).
Businesses.Live = false

Businesses.RateScale = 1 -- x every business income (trickle and job pay). 1 = the numbers below.
Businesses.TickSeconds = 30 -- the server settles every register this often (and before every action)
Businesses.MaxLevel = 5
Businesses.Reach = 34 -- studs (flat) from the lot centre where the cards' buttons work and a crewmate counts as "at" the business
Businesses.DoorRange = 16 -- studs from the doorway the door prompt is accepted from (its reach is 10)

-- Upgrade prices: level N costs this share of the business's price (PRD: 40 / 60 / 80 / 100%).
Businesses.UpgradeShare = { [2] = 0.4, [3] = 0.6, [4] = 0.8, [5] = 1.0 }

Businesses.CustomerShare = 0.7 -- the featured owner's share of what a player customer pays (the rest is a sink)
Businesses.CrewCut = 0.2 -- a crewmate works your business: they get their normal pay, you get this much on top (the game pays it)
Businesses.BusyBonus = 0.25 -- +25% trickle while one or more of the owner's crewmates is at the business (within Reach)

------------------------------------------------------------------ Empire rank (1-10)

Businesses.Empire = {
	MaxRank = 10,
	-- Total Empire XP needed for each rank. Rank 2 comes after buying the Car Wash, its first upgrade and
	-- ~20 washes (~15 minutes of work); rank 3 after about an hour; rank 5 (remote collect) after ~5 hours;
	-- rank 10 after ~30-40 hours of business play (all five businesses, every upgrade, lots of jobs).
	XPFor = { 0, 300, 900, 2000, 3500, 5500, 8000, 11000, 15000, 20000 },
	XP = {
		Buy = 100, -- buying a business
		UpgradePerLevel = 50, -- an upgrade: this x the new level (level 2 = 100 ... level 5 = 250; 700 per business)
		Wash = 5, -- a finished wash (the worker: owner or crewmate)
		Detail = 10, -- a finished detail delivery (the worker)
		Rush = 6, -- every rush-order address delivered to (the worker): ~6-7 a minute of work, like the wash
		Customer = 10, -- the featured owner, for every player customer served
		-- ...but one buyer counts at most this many times an hour per owner (a second account buying shine after
		-- shine can't farm the owner's rank; the money still goes to the owner every time)
		CustomerPerBuyerHour = 2,
		BreakIn = 50, -- the owner, for a break-in stopped (all robbers scared off or knocked down)
	},
	RemoteCollect = 5, -- from this rank COLLECT works from the phone (EMPIRE app), anywhere
	Unlocks = {
		[2] = "Coastline Boat Rentals",
		[3] = "Afterglow Nightclub",
		[5] = "Collect your registers from the phone",
		[7] = "Title: Mogul",
		[10] = "Gold business sign · Title: Kingpin of the Coast",
	},
	Titles = { [7] = "Mogul", [10] = "Kingpin of the Coast" }, -- player attribute EmpireTitle (the highest reached)
}

------------------------------------------------------------------ the Car Wash's jobs

-- WASH (START JOB > WASH): a customer car (local to the worker's device, so several workers never clash) pulls
-- into a free bay. SPRAY (hold), SCRUB (tap each dirty spot ScrubTaps times), RINSE (hold). The server times
-- every hold and tap; see BusinessService.
Businesses.Wash = {
	ArriveTime = 6, -- seconds the car takes to pull in (the first one)
	DepartTime = 4, -- extra seconds for the last car to pull out before the next pulls in
	SprayHold = 5, -- seconds of holding SPRAY
	RinseHold = 5, -- seconds of holding RINSE
	HoldSlack = 0.4, -- a hold may end this much early (lag) and still count
	Spots = { 4, 6 }, -- dirty spots on a car (random, both included)
	ScrubTaps = 3, -- taps per spot
	ScrubGap = 0.15, -- a tap sooner than this after the last counted one doesn't count (caps auto-clickers at ~6/s)
	MinTime = 11.5, -- seconds from "car ready" to the end of the rinse below which that car isn't paid (the holds
	-- and the tap gap alone take ~10.9 s with 4 spots; a quick player needs ~13.5 s). The job goes on: only that car is refused.
	TipTime = 40, -- a clean finish (both holds in one go) inside this many seconds pays the tip
	Pay = 420, -- $ a wash at level 1 (x the level's JobMult and RateScale)
	Tip = 140, -- $ the clean-finish tip at level 1 (same multipliers)
	BayRange = 26, -- studs (flat) from the bay centre the worker must be within for a hold or a tap to count
	-- studs from the bay: further than this for LeaveGrace seconds ends the job. (Was 45 / 10: bay 1 is ~46 studs
	-- from the door where START JOB is pressed, so a wash started at the door ended by itself in the Nov 4 Studio
	-- test before the player had found the bay. The client now says WALK TO BAY n while out of BayRange.)
	LeaveRange = 70,
	LeaveGrace = 15,
}

-- DETAIL DELIVERY (START JOB > DELIVER, or DELIVER after a wash): a real customer car (Config.Vehicles, nicer at
-- higher levels) waits on the pick-up box; drive it to the customer's address on a kerb DistMin-DistMax studs
-- away (JobService.RoadsideSpot), stop in the ring. Full pay + a speed tip that dents eat into. Same rules as a
-- taxi fare: the speed check (FastSlack), VehicleGuard, END JOB, and it ends if you're wanted, leave the car
-- for LeaveGrace seconds, change sides or leave the game. The car despawns at the end, whatever happens.
Businesses.Detail = {
	DistMin = 600, -- studs (straight line) from the business to the address...
	DistMax = 1500,
	Base = 500, -- $ a delivery at level 1...
	PerStud = 0.65, -- ...plus this per stud of the road route (GPS length), x JobMult and RateScale
	TipMax = 300, -- $ speed tip at level 1: all of it at or under the estimate...
	TipFade = 0.5, -- ...falling to nothing at estimate x (1 + TipFade)
	EstSpeed = 75, -- the estimate: road length / EstSpeed + EstExtra seconds (a taxi's is /80 + 10)
	EstExtra = 12,
	DentCost = 60, -- $ off the tip for every dent (never below 0)
	-- A dent (the server samples the car's speed 4 times a second; nothing else tracks car damage): the speed
	-- falls faster than DentDecel studs/s^2 (1.5x the hardest brake, Config.Vehicles Brake = 120: a crash, not a
	-- stop) from at least DentMinSpeed, at most one per DentGap seconds. Another car shoving it (ImpactService
	-- stamps the car's BumpedAt) is a dent too.
	DentDecel = 180,
	DentMinSpeed = 25,
	DentGap = 1,
	StopRadius = 32, -- the drop ring (as a taxi's: ActivityClient's ring is 64 across)
	StopSpeed = 6, -- studs/s: stopped
	FastSlack = 1.15, -- as JobService: reached sooner than the straight line at the car's nitro top speed x this = refused
	LeaveGrace = 10, -- seconds out of the car before the job ends
	-- The customer cars, by the business level of the owner the job is for (each level adds to the last).
	-- Never police cars, boats, game-pass or heist-locked cars, or Hidden street cars.
	Cars = {
		{ "Palmetto", "Gatorback", "Mangrove" },
		{ "Sandpiper", "Flamingo" },
		{ "NightHeron", "Voltline" },
		{ "SolanaGT", "SilverEgret" },
		{ "AlbatrossGT" },
	},
}

-- DRIVE-THROUGH SHINE (player customers, PRD section 6): drive your own car under the gantry in the shine lane
-- and press "Shine $100": your car sparkles for Seconds (player attribute ShineUntil, server time; every device
-- draws the sparkle on that player's cars near its camera). CustomerShare of the price goes to the featured
-- owner if one is in the server (never to the buyer themselves: an owner shining their own car pays and the
-- game keeps it); the rest is a sink.
Businesses.Shine = {
	Price = 100,
	Seconds = 30 * 60,
	Reach = 18, -- studs from the gantry to the car's driver seat (the prompt reaches 14)
	MaxSpeed = 8, -- studs/s: you have to stop under it
	RebuyLeft = 25 * 60, -- refused while more than this is left on your shine (no double-buying by mistake)
}

------------------------------------------------------------------ Palm Grind Coffee's job and service (M2)

-- RUSH ORDERS (START JOB at Palm Grind): hold GRAB at the RUSH ORDERS shelf (the server times it), get in your
-- own car (CAR calls it) and drive the order to Drops[level] addresses in a row, each on a kerb
-- (JobService.RoadsideSpot); from VIPLevel the last one may be a VIP order at a big home (VIPHomes in
-- Config.Housing: its verge parking spot), paying VIPMult. Every address has its own clock (Businesses.RushTimer,
-- shown on the job strip): stop in its ring and you're paid the base whatever the clock says; the tip is full
-- while at least TipFull of the clock is left, then shrinks to $0 at 0:00 (late pays the base only). After
-- the last address, drive back to the café for the next order. The same rules as a taxi fare: the speed
-- check on every leg (FastSlack, VehicleGuard), END JOB, and the job ends if you're wanted, change sides, die,
-- leave the game, stay out of your car too long (CarGrace after grabbing, LeaveGrace once you've driven
-- off), or don't grab another order within IdleTime. The pay maths is in BALANCE at the top.
Businesses.Rush = {
	GrabHold = 2, -- seconds holding GRAB at the shelf
	HoldSlack = 0.4, -- a hold may end this much early (lag) and still count
	GrabRange = 10, -- studs (flat) from the shelf spot (Layout.Orders) a grab counts from (BusinessClient shows HOLD within 7)
	Drops = { 1, 2, 2, 3, 3 }, -- addresses an order has, by the owner's level
	FirstMin = 400, -- studs (straight line) from the café to the first address...
	FirstMax = 1000,
	NextMin = 300, -- ...and from one address to the next
	NextMax = 700,
	VIPLevel = 4, -- from this level an order's last address may be a VIP order...
	VIPChance = { [4] = 0.35, [5] = 0.5 }, -- ...this often (by level)
	VIPMax = 2600, -- studs (straight line) from the stop before: a VIP home further away isn't picked
	VIPMult = 1.5, -- x a VIP drop's pay and tip
	VIPHomes = { "SolanaHeightsPenthouse", "MarinaRowVilla", "FlamingoBeachMansion" }, -- Config.Housing ids: the penthouse, the villa, the mansion
	OrderPay = 330, -- $ an order at level 1 (paid with its first drop: the time at the café)
	DropPay = 60, -- $ every address at level 1...
	PerStud = 0.40, -- ...plus this a stud of the road route: every leg, and the way back to the café (with the last drop)
	TipMax = 200, -- $ an address's speed tip at level 1
	TipFull = 0.35, -- the tip is full while at least this share of the clock is left, then falls to $0 at 0:00
	EstSpeed = 45, -- the clock: road length / EstSpeed + FirstExtra (the first address: walking out to your car) or NextExtra
	FirstExtra = 18,
	NextExtra = 8,
	StopRadius = 32, -- the drop ring (as a taxi's; BusinessClient's ring is 64 across)
	StopSpeed = 6, -- studs/s: stopped
	FastSlack = 1.15, -- as JobService: a leg done sooner than the straight line at the car's nitro top speed x this = refused
	CarGrace = 45, -- seconds after grabbing an order to get into your own car
	LeaveGrace = 10, -- seconds out of your car once you've driven off with the order
	IdleTime = 300, -- seconds without grabbing an order (at the café, or on the way back) before the job ends
}

-- COLD BREW (player customers at Palm Grind, PRD section 6): walk up to the ORDER HERE spot at the counter and
-- press "Cold brew $60": +Stamina sprint stamina for Seconds (player attribute ColdBrewUntil, server time;
-- LocomotionClient drains the sprint 1 / (1 + Stamina) as fast while it's ahead). Paid exactly like the shine:
-- CustomerShare to the featured owner (never the buyer), the rest a sink, Empire XP capped per buyer per hour.
Businesses.ColdBrew = {
	Seconds = 5 * 60, -- how long it lasts
	Stamina = 0.25, -- +25% sprint stamina (the sprint lasts 1.25x as long)
	Reach = 12, -- studs (flat) from the ORDER HERE spot to the buyer (the prompt reaches 8)
	RebuyLeft = 4 * 60, -- refused while more than this is left on yours (no double-buying by mistake)
}

-- NPC BREAK-INS (PvE, legit businesses; PRD section 5, pillar 3). Only while the owner is in the server, on
-- the Civilian side, has played MinPlay seconds this session, and one of their registers holds MinRegister+.
-- At most one every Gap seconds of play, at a random moment inside the Window after that. 1-2 robbers appear
-- at that business's register; the owner and their crewmates in the server get the alert (toast, a GPS route,
-- a flashing red icon on both maps) and Time seconds. Scare them off by pointing a gun at them, or knock them
-- down (punch or shoot): Reward per robber to whoever stopped it, and the owner gets Empire XP when all are
-- stopped. Time runs out: they take Loss of that owner's register and leave. Anyone can SEE them; only the
-- owner and crew can scare or hit them (nobody else can trigger, farm or spoil one).
Businesses.BreakIn = {
	MinPlay = 600, -- seconds of play this session before the first one can happen
	Gap = 1200, -- seconds of play between two (per owner, across all their businesses)
	Window = 900, -- ...then a random moment within this many more seconds
	Retry = 60, -- seconds of play before trying again when one was due but couldn't happen (not a citizen, registers low)
	MinRegister = 800, -- $ the register must hold
	Time = 120, -- seconds to stop it
	Robbers = { 1, 2 },
	Loss = 0.10, -- share of that owner's register taken when the time runs out
	Reward = 250, -- $ per robber stopped, to whoever stopped it (the owner or a crewmate)
	ScareReach = 26, -- studs: the server's limit for a gun pointed at a robber (the client asks within 22)
	ScareCone = 0.6, -- cosine: how squarely the scarer must face the robber (as a clerk robbery)
}

------------------------------------------------------------------ the businesses

-- Levels[n] = { Trickle ($/min while the owner is online, x RateScale), Cap (the register's size), JobMult
-- (x every job's pay), Adds (what that level brings, for the cards) }. Bays = wash bays open at each level.
-- MapLetter / MapColor: the business's blip on the minimap and the big map (yours get a gold ring).

-- Even steps from a to b over the five levels (rounded to whole dollars): the PRD's "Lv 1 -> Lv 5" ranges.
local function steps(a, b)
	local out = {}
	for i = 0, 4 do
		out[i + 1] = math.floor(a + (b - a) * i / 4 + 0.5)
	end
	return out
end

local JOB_MULT = { 1.0, 1.06, 1.12, 1.18, 1.25 } -- every business: +6% job pay a level, +25% at level 5

local function levels(trickle, cap, adds)
	local t, c = steps(trickle[1], trickle[2]), steps(cap[1], cap[2])
	local out = {}
	for i = 1, 5 do
		out[i] = { Trickle = t[i], Cap = c[i], JobMult = JOB_MULT[i], Adds = adds and adds[i] or nil }
	end
	return out
end

Businesses.List = {
	{
		Id = "CarWash",
		Name = "Suds & Shine Car Wash",
		Short = "Car Wash", -- in toasts ("Your Car Wash register is full")
		Brand = "Suds & Shine", -- on signs ("Player1's Suds & Shine")
		Kind = "Legit",
		Enabled = true,
		Price = 25000,
		Unlock = 1, -- Empire rank needed to buy it (1 = none)
		Style = "CarWash", -- BusinessService's building
		Blurb = "A hand-wash bay on Solana Avenue. Wash cars, deliver them across town, and grow it into a full tunnel wash.",
		JobLine = "Wash cars in the bay, and drive detailed cars to their owners",
		JobPay = "about $1,150 a minute of work",
		Hint = "Press Manage at the door: START JOB to wash and deliver cars. The register fills while you play.",
		Jobs = { { Kind = "Wash", Label = "WASH A CAR" }, { Kind = "Detail", Label = "DELIVER A CAR" } },
		Service = { Name = "Drive-through shine", Price = 100, Kind = "Shine", Words = "a shine" },
		-- Palm Hills' south edge, on the east side of Solana Avenue (x = 50), facing it; downtown's first block
		-- starts 12 studs south of the lot.
		Position = Vector3.new(112, 0, -860),
		Facing = Vector3.new(-1, 0, 0),
		Layout = {
			Door = Vector3.new(21, 0, 1),
			Register = Vector3.new(21.8, 0, 14),
			Robbers = { Vector3.new(19.6, 0, 10.4), Vector3.new(24, 0, 10.4) },
			Exit = Vector3.new(21, 0, -12),
			Bays = { Vector3.new(-22, 0, 9.5), Vector3.new(-12, 0, 9.5), Vector3.new(-2, 0, 9.5) },
			BayMouth = -3,
			Shine = Vector3.new(9, 0, -12),
			Pickup = Vector3.new(20.5, 0, -14),
		},
		Bays = { 1, 2, 3, 3, 3 },
		Levels = levels({ 60, 150 }, { 2000, 9000 }, {
			"One hand-wash bay and a painted sign",
			"A second wash bay and a vacuum station",
			"A third bay, the neon sign, a waiting bench: more customers",
			"The detailing garage opens",
			"A full drive-through tunnel with lights",
		}),
		Accent = Color3.fromRGB(40, 132, 214), -- wash-bay blue
		Neon = Color3.fromRGB(34, 225, 255),
		MapLetter = "W",
		MapColor = Color3.fromRGB(64, 156, 230),
	},
	{
		Id = "PalmGrind",
		Name = "Palm Grind Coffee",
		Short = "Coffee Shop",
		Brand = "Palm Grind",
		Kind = "Legit",
		Enabled = true, -- M2
		Price = 45000,
		Unlock = 1, -- no Empire rank needed
		Style = "Coffee", -- its building: ServerScriptService.Services.BusinessJobs.Coffee
		Blurb = "A corner café on Marina Row, by the Car Meet. Rush coffee orders across town against the clock, and grow it into a rooftop café.",
		JobLine = "Rush orders: deliver coffee across town against the clock",
		JobPay = "about $1,250 a minute of work",
		Hint = "Press Manage at the door: START JOB for rush orders. Grab one at the RUSH ORDERS shelf and drive it over.",
		Jobs = { { Kind = "Rush", Label = "RUSH ORDERS" } },
		Service = { Name = "Cold brew", Price = 60, Kind = "ColdBrew", Words = "a cold brew" },
		-- Marina Row, on the east side of Marina Link (x = 450), facing it; the Car Meet is ~170 studs to the
		-- north-east. (Lot re-checked for M2: see PLACES above.)
		Position = Vector3.new(505, 0, 905),
		Facing = Vector3.new(-1, 0, 0),
		-- The café (x -17..10, z 2..14; the door in the middle of its glass front), the counter at z 9..10.8
		-- with the register, ORDER HERE (cold brew) on its left and the RUSH ORDERS shelf on its right; the
		-- terrace and the parking bays on the forecourt; the drive-through loop (level 3) round the café.
		Layout = {
			Door = Vector3.new(0, 0, 2),
			Register = Vector3.new(2, 0, 9.8),
			Robbers = { Vector3.new(0.4, 0, 7.4), Vector3.new(3.6, 0, 7.4) },
			Exit = Vector3.new(0, 0, -16),
			Service = Vector3.new(-2.5, 0, 7.6),
			Orders = Vector3.new(6.5, 0, 7.6),
		},
		Levels = levels({ 80, 200 }, { 3000, 12000 }, {
			"A counter, two tables and the RUSH ORDERS shelf",
			"A terrace with umbrellas · orders with 2 stops",
			"The drive-through window and the neon signs",
			"A roastery corner and a queue outside · 3 stops, VIP orders",
			"A rooftop café · more VIP orders",
		}),
		Accent = Color3.fromRGB(38, 128, 102), -- palm green
		Neon = Color3.fromRGB(255, 160, 64), -- warm amber
		MapLetter = "E",
		MapColor = Color3.fromRGB(196, 128, 70), -- coffee brown
	},
	-- Placeholders (M3-M5): not built, listed or buyable yet. The EMPIRE app shows them as "Coming soon".
	{
		Id = "PrintShop",
		Name = "Backlot Print Shop",
		Short = "Print Shop",
		Brand = "Backlot Print",
		Kind = "Shady",
		Enabled = false, -- M3
		Price = 90000,
		Unlock = 1,
		Blurb = "Flyers out front, something else in the back. Print it, launder it, and watch for police raids.",
		JobLine = "Print and launder fake cash (cops can spot you)",
		JobPay = "about $1,600 a minute of work, with the risk",
		Position = Vector3.new(807, 0, -895), -- (lot checked Nov 4; layout comes with M3)
		Facing = Vector3.new(-1, 0, 0),
		Levels = levels({ 110, 260 }, { 4000, 15000 }),
		MapLetter = "X",
		MapColor = Color3.fromRGB(150, 120, 235),
	},
	{
		Id = "BoatRentals",
		Name = "Coastline Boat Rentals",
		Short = "Boat Rentals",
		Brand = "Coastline Boats",
		Kind = "Legit",
		Enabled = false, -- M4
		Price = 120000,
		Unlock = 2,
		Blurb = "A dock beside Marina Boat Sales. Take tourists on sightseeing tours of the coast.",
		JobLine = "Boat tours on a sightseeing route",
		JobPay = "about $1,400 a minute of work",
		Service = { Name = "Jet ski rental", Price = 150 },
		-- (lot to be picked in M4)
		Levels = levels({ 130, 300 }, { 5000, 18000 }),
		MapLetter = "Y",
		MapColor = Color3.fromRGB(40, 180, 170),
	},
	{
		Id = "Nightclub",
		Name = "Afterglow Nightclub",
		Short = "Nightclub",
		Brand = "Afterglow",
		Kind = "Legit", -- (with a shady back room: raids come with M5)
		Enabled = false, -- M5
		Price = 250000,
		Unlock = 3,
		Blurb = "The boardwalk's hottest club. VIP pickups in the club's limo, and double takings at night.",
		JobLine = "VIP pickups in a limo",
		JobPay = "about $1,500 a minute of work",
		Service = { Name = "Cover charge", Price = 50 },
		-- (lot to be picked in M5)
		Levels = levels({ 180, 420 }, { 8000, 25000 }),
		MapLetter = "N",
		MapColor = Color3.fromRGB(255, 62, 165),
	},
}

Businesses.ById = {}
for _, def in ipairs(Businesses.List) do
	Businesses.ById[def.Id] = def
end

------------------------------------------------------------------ places

-- A lot's frame: origin at the lot centre on the ground, -Z toward the street.
function Businesses.Frame(def)
	return CFrame.lookAt(def.Position, def.Position + def.Facing)
end

-- A lot-space point (Vector3) in the world.
function Businesses.At(def, v)
	return (Businesses.Frame(def) * CFrame.new(v)).Position
end

function Businesses.DoorPosition(def)
	return Businesses.At(def, def.Layout.Door)
end

-- Bay i's centre on the ground, facing into the bay (+Z of the lot: nose toward the back wall).
function Businesses.BayCFrame(def, i)
	local bay = def.Layout.Bays[i]
	if not bay then
		return nil
	end
	return Businesses.Frame(def) * CFrame.new(bay) * CFrame.Angles(0, math.pi, 0)
end

------------------------------------------------------------------ maths (pure: the server, the cards and the logic tests use these)

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

-- A level clamped to 1..MaxLevel.
function Businesses.ClampLevel(n)
	return math.clamp(math.floor(num(n)), 1, Businesses.MaxLevel)
end

function Businesses.LevelInfo(def, level)
	return def.Levels[Businesses.ClampLevel(level)]
end

-- $ a minute the register fills at this level (busy: a crewmate is at the business).
function Businesses.Trickle(def, level, busy)
	local base = Businesses.LevelInfo(def, level).Trickle * Businesses.RateScale
	return busy and base * (1 + Businesses.BusyBonus) or base
end

-- The register's size at this level.
function Businesses.Cap(def, level)
	return Businesses.LevelInfo(def, level).Cap
end

-- `seconds` of trickle (the owner was in the server): up to the cap. Returns the new register and what was
-- earned. A register already over its cap (a cap lowered in this config) keeps its money and earns nothing.
function Businesses.Accrue(def, register, level, seconds, busy)
	register = math.max(0, num(register))
	seconds = math.max(0, num(seconds))
	local cap = Businesses.Cap(def, level)
	local perSecond = Businesses.Trickle(def, level, busy) / 60
	if seconds <= 0 or register >= cap or perSecond <= 0 then
		return register, 0
	end
	local earned = math.min(perSecond * seconds, cap - register)
	return register + earned, earned
end

-- The price of the next level from `level` (nil at the top).
function Businesses.UpgradePrice(def, level)
	level = Businesses.ClampLevel(level)
	local share = Businesses.UpgradeShare[level + 1]
	if level >= Businesses.MaxLevel or not share then
		return nil
	end
	return math.floor(def.Price * share + 0.5)
end

-- x every job's pay at this level (and RateScale).
function Businesses.JobMult(def, level)
	return Businesses.LevelInfo(def, level).JobMult * Businesses.RateScale
end

-- Open wash bays at this level.
function Businesses.BayCount(def, level)
	local bays = def.Bays or { 1 }
	return math.min(bays[Businesses.ClampLevel(level)] or 1, #(def.Layout and def.Layout.Bays or { 1 }))
end

-- A finished wash: the pay and the clean-finish tip (0 when not clean), whole dollars.
function Businesses.WashPay(def, level, clean)
	local mult = Businesses.JobMult(def, level)
	local pay = math.floor(Businesses.Wash.Pay * mult + 0.5)
	local tip = clean and math.floor(Businesses.Wash.Tip * mult + 0.5) or 0
	return pay, tip
end

-- The estimate (seconds) for a delivery of `length` studs of road.
function Businesses.DetailEstimate(length)
	local D = Businesses.Detail
	return math.max(0, num(length)) / D.EstSpeed + D.EstExtra
end

-- A finished delivery: the pay and the tip (whole dollars). took / est in seconds; dents counted.
function Businesses.DetailPay(def, level, length, took, est, dents)
	local D = Businesses.Detail
	local mult = Businesses.JobMult(def, level)
	length, took, est = math.max(0, num(length)), math.max(0, num(took)), math.max(1, num(est))
	local pay = math.floor((D.Base + D.PerStud * length) * mult + 0.5)
	local share = 1
	if took > est then
		share = math.clamp(1 - (took - est) / (est * D.TipFade), 0, 1)
	end
	local tip = math.max(0, math.floor(D.TipMax * share + 0.5) - D.DentCost * math.max(0, math.floor(num(dents))))
	return pay, math.floor(tip * mult + 0.5)
end

-- How many addresses a rush order has at this level.
function Businesses.RushDrops(level)
	return Businesses.Rush.Drops[Businesses.ClampLevel(level)] or 1
end

-- The clock (seconds) for one rush-order address `road` studs of road away. first: the order's first
-- address (the clock also covers walking out to your car).
function Businesses.RushTimer(road, first)
	local Ru = Businesses.Rush
	return math.max(0, num(road)) / Ru.EstSpeed + (first and Ru.FirstExtra or Ru.NextExtra)
end

-- The share (0-1) of the speed tip for an address reached `took` seconds into its `timer`-second clock:
-- full while TipFull of the clock is left, then down to 0 at 0:00; nothing late.
function Businesses.RushTipShare(took, timer)
	took, timer = math.max(0, num(took)), math.max(1, num(timer))
	local left = timer - took
	if left <= 0 then
		return 0
	end
	return math.clamp(left / (timer * Businesses.Rush.TipFull), 0, 1)
end

-- One rush-order address delivered: the pay and the tip (whole dollars). road = this leg's road length;
-- back = the road from this address back to the café when it's the order's last (else 0); first = the
-- order's first address (it carries the order's own pay); took / timer in seconds; vip = a VIP order.
function Businesses.RushPay(def, level, road, back, first, took, timer, vip)
	local Ru = Businesses.Rush
	local mult = Businesses.JobMult(def, level)
	local vipMult = vip and Ru.VIPMult or 1
	local pay = (Ru.DropPay + Ru.PerStud * math.max(0, num(road))) * vipMult + Ru.PerStud * math.max(0, num(back))
		+ (first and Ru.OrderPay or 0)
	local tip = Ru.TipMax * Businesses.RushTipShare(took, timer) * vipMult
	return math.floor(pay * mult + 0.5), math.floor(tip * mult + 0.5)
end

-- The tip an address would pay if reached now (the job strip's live number).
function Businesses.RushTip(def, level, took, timer, vip)
	local _, tip = Businesses.RushPay(def, level, 0, 0, false, took, timer, vip)
	return tip
end

-- LocomotionClient's sprint drain multiplier while a cold brew is on (untilT, now: server time).
function Businesses.ColdBrewDrain(untilT, now)
	if type(untilT) == "number" and type(now) == "number" and untilT > now then
		return 1 / (1 + Businesses.ColdBrew.Stamina)
	end
	return 1
end

-- Does this purchase still earn the featured owner Empire XP? rec = the owner's record for this buyer
-- ({ since, count } or nil), now = os.clock(). One buyer counts at most Empire.XP.CustomerPerBuyerHour times
-- an hour (a second account buying again and again can't farm a rank; the money still goes to the owner).
-- Returns yes / no and the record to keep.
function Businesses.CustomerXP(rec, now)
	now = num(now)
	if type(rec) ~= "table" or type(rec.since) ~= "number" or type(rec.count) ~= "number" or now - rec.since >= 3600 then
		rec = { since = now, count = 0 }
	end
	if rec.count < (Businesses.Empire.XP.CustomerPerBuyerHour or 2) then
		rec.count += 1
		return true, rec
	end
	return false, rec
end

-- The kinds of job START JOB offers at this business (its Jobs list).
function Businesses.HasJob(def, kind)
	for _, j in ipairs(def and def.Jobs or {}) do
		if j.Kind == kind then
			return true
		end
	end
	return false
end

-- Empire rank for this much Empire XP.
function Businesses.RankFor(xp)
	xp = num(xp)
	local E = Businesses.Empire
	local rank = 1
	while rank < E.MaxRank and xp >= E.XPFor[rank + 1] do
		rank += 1
	end
	return rank
end

-- rank, share of the way to the next rank (0-1), XP into this rank, XP this rank needs (0 at the top).
function Businesses.RankProgress(xp)
	xp = math.max(0, num(xp))
	local E = Businesses.Empire
	local rank = Businesses.RankFor(xp)
	if rank >= E.MaxRank then
		return rank, 1, xp - E.XPFor[rank], 0
	end
	local from, to = E.XPFor[rank], E.XPFor[rank + 1]
	return rank, (xp - from) / (to - from), xp - from, to - from
end

-- The highest title reached at this rank (nil below the first).
function Businesses.TitleFor(rank)
	local best
	for r, title in pairs(Businesses.Empire.Titles) do
		if rank >= r and (not best or r > best) then
			best = r
		end
	end
	return best and Businesses.Empire.Titles[best] or nil
end

-- May someone of this Empire rank buy this business?
function Businesses.Unlocked(def, rank)
	return num(rank) >= (def.Unlock or 1)
end

-- A player customer's payment: the featured owner's share and the sink (whole dollars, adding up to price).
function Businesses.Split(price)
	price = math.max(0, math.floor(num(price)))
	local owner = math.floor(price * Businesses.CustomerShare)
	return owner, price - owner
end

-- The owner's cut of a crewmate's job pay (paid by the game on top).
function Businesses.CrewCutFor(pay)
	return math.floor(math.max(0, num(pay)) * Businesses.CrewCut)
end

-- What break-in robbers take when the time runs out (whole dollars, never more than the register).
function Businesses.BreakInLoss(register)
	register = math.max(0, num(register))
	return math.min(math.floor(register), math.floor(register * Businesses.BreakIn.Loss))
end

-- Hours online to earn the price back on the trickle alone, at level 1.
function Businesses.PaybackHours(def)
	return def.Price / Businesses.Trickle(def, 1, false) / 60
end

-- A short price for tight labels: "$25k", "$1.2M".
function Businesses.ShortPrice(price)
	if price >= 1000000 then
		return string.format("$%gM", math.floor(price / 100000) / 10)
	end
	return string.format("$%dk", math.floor(price / 1000))
end

return Businesses
