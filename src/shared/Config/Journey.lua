-- Journey (ModuleScript, ReplicatedStorage.Shared.Config.Journey)
-- "Road to the Coast": the goal chains that follow the tutorial on the same NEXT pill, each goal with
-- a SHOW ME button and a small cash reward (JourneyService on the server, TutorialClient draws it).
-- Only players who first join after this shipped get them (a brand-new save). Civ runs in free roam
-- once the tutorial is done (or skipped); Cop runs on the police side from the first shift.
-- Tuning, for the $10,000 Gatorback about 15 minutes in (12-15 before the gun goal): the tutorial's
-- store (about $1,200) and $500 bonus, day 1's $1,000 login reward, the jack, chop and paint goals
-- ($1,100, of which $500 pays back the paint) and a Chop Shop sale (about $350) leave about $3,650 when
-- the gun goal comes up, enough for the $2,500 pistol (Config.Combat; its $1,000 reward pays part of
-- it back). The bigger store (about $5,000, +$400) then makes about $7,500; one more store (or a daily
-- challenge's $2,000) gets the Gatorback, and until then the buy goals' button reads EARN and points at
-- the nearest store (Earn below). All the free-roam rewards add up to $6,800, the police ones to $2,250.
--
-- NEVER REORDER, RENAME OR REMOVE GOALS. A new goal may go anywhere in a list: saves keep how many goals
-- are done and the next goal's Id (JourneyService), and the count follows that Id, so a player already
-- past the new goal skips it (unpaid) and one before it meets it on the way; a chain finished before the
-- new goal existed stays finished. (Free-roam funnel steps are 6 + the goal's position, so the goals
-- after an insert log under new step numbers.) Moving a goal is what breaks: goals already done aren't
-- tracked by Id, so one moved from before a player's goal to after it would come round (and pay) again.
--
-- Fields of a goal:
--   Id      saved (the next goal's Id) and in analytics ("Journey_<Id>" in the onboarding funnel,
--           "JourneyCop_<Id>" for cops); never rename one
--   Text    what the pill says (kept short: it wraps onto two to five lines on a phone)
--   Show    where SHOW ME points: a place name from MapService's "Places" list, or one of
--           "OpenHeist" (nearest open heist the player's rank allows, see ShowTier), "Stunt" / "Race"
--           (nearest stunt ramp / street race start), "Wanted" (nearest wanted robber, for cops),
--           "Garage" / "Goals" (opens that phone app). Left out: no SHOW ME button.
--   ShowTier, ShowMaxTier  with "OpenHeist": the heist tiers to point at (2 = Sparkle & Co. / Club
--           Nova). ShowMaxTier defaults to the biggest tier without a prep job (below Heists.BigTier),
--           or ShowTier if that's bigger; set lower, it's a preference (none open: up to that default).
--   Earn    with Cash: while the savings bar isn't full, the button reads EARN and points here
--           instead ("OpenHeist": the nearest open store a player can rob alone, no prep jobs)
--   Kind    the ProgressService event that counts ("Carjack", "ChopSale", "Paint", "BuyCar", "BuyHome",
--           "Heist", "Stunt", "RaceFinish", "Drift", "TaxiFare", "PatrolMinute", "TaserHit", "SpikeHit",
--           "Arrest"), "CivRank" / "CopRank": reach that rank, or "BuyGun": own a gun (no event: the save
--           shows it, data.gear.guns, checked when the "Guns" attribute changes after a purchase at
--           Coast Arms). Paint, BuyCar and BuyHome also count
--           as done when the save already shows one (a painted car, a bought car, a home), a Heist goal
--           when the player has a big heist (BigHeists: robbed, or helped their crew rob, the Coastal
--           Bank or Sea Dream), and TaserHit / SpikeHit / Arrest when they happened before the goal
--           came up (they need a wanted robber, so none is lost).
--   Goal    how many events it takes (or points, with Sum; or the rank, for the rank kinds)
--   Min     only events whose amount is at least this count (the heist's tier)
--   Sum     add each event's amount instead of 1 (drift points)
--   Unit    word after the count on the bar ("pts", "min")
--   Cash    draw a savings bar: the player's banked cash out of this much (buy goals)
--   Reward  cash paid when the goal is done

local Journey = {}

Journey.Civ = {
	{ Id = "jack", Text = "Grab a street car: walk up to traffic and press JACK",
		Kind = "Carjack", Goal = 1, Reward = 200 },
	{ Id = "chop", Text = "Sell a stolen car at the Chop Shop (lose the cops first)", Show = "Chop Shop",
		Kind = "ChopSale", Goal = 1, Reward = 400 },
	{ Id = "paint", Text = "Paint your ride: PHONE > GARAGE > STYLE (we pay it back)", Show = "Garage",
		Kind = "Paint", Goal = 1, Reward = 500 }, -- = Garage.PaintPrice
	-- Before the bigger store: guns are bought once at Coast Arms (CombatService), the pistol is the
	-- cheapest. Cash = Config.Combat's Pistol price: EARN points at a store until it's saved up.
	{ Id = "gun", Text = "Gear up: buy your first gun at Coast Arms", Show = "Coast Arms",
		Earn = "OpenHeist", Kind = "BuyGun", Goal = 1, Cash = 2500, Reward = 1000 },
	{ Id = "bigstore", Text = "Rob a bigger store: Sparkle & Co. or Club Nova", Show = "OpenHeist",
		ShowTier = 2, ShowMaxTier = 2, Kind = "Heist", Min = 2, Goal = 1, Reward = 400 },
	{ Id = "gatorback", Text = "Save up and buy the Gatorback at AutoNeon Motors", Show = "AutoNeon Motors",
		Earn = "OpenHeist", Kind = "BuyCar", Goal = 1, Cash = 10000, Reward = 500 },
	{ Id = "stunt", Text = "Land a stunt jump: hit a ramp at full speed", Show = "Stunt",
		Kind = "Stunt", Goal = 1, Reward = 250 },
	{ Id = "race", Text = "Finish a street race: drive onto a start pad to begin", Show = "Race",
		Kind = "RaceFinish", Goal = 1, Reward = 300 },
	{ Id = "drift", Text = "Score 1,000 drift points in the Drift Zone", Show = "Drift Zone",
		Kind = "Drift", Goal = 1000, Sum = true, Unit = "pts", Reward = 250 },
	{ Id = "taxi", Text = "Drive one taxi fare: start a shift at the Taxi Stand", Show = "Taxi Stand",
		Kind = "TaxiFare", Goal = 1, Reward = 250 },
	{ Id = "rank3", Text = "Reach rank 3: heists, races and jobs all give XP", Show = "Goals",
		Kind = "CivRank", Goal = 3, Reward = 250 },
	{ Id = "bank", Text = "Rob the Coastal Bank (every 15 min) or the Sea Dream", Show = "OpenHeist", ShowTier = 3,
		Kind = "Heist", Min = 3, Goal = 1, Reward = 500 },
	{ Id = "loft", Text = "Buy your first home: the Rustwater Loft", Show = "Rustwater Loft",
		Earn = "OpenHeist", Kind = "BuyHome", Goal = 1, Cash = 25000, Reward = 1000 },
	{ Id = "tune", Text = "Tune your ride: PHONE > GARAGE > TUNE (we pay it back)", Show = "Garage",
		Kind = "Tune", Goal = 1, Reward = 1000 }, -- = the cheapest upgrade (Brakes 1 on a tier 1 car, Config.Garage.Tune)
}

-- A chase in the order it happens: spike the car, tase the driver who bails, cuff them.
Journey.Cop = {
	{ Id = "patrol", Text = "Patrol for 2 minutes: cruise the streets, watch the map",
		Kind = "PatrolMinute", Goal = 2, Unit = "min", Reward = 200 },
	{ Id = "spike", Text = "Drop SPIKES in front of a wanted driver", Show = "Wanted",
		Kind = "SpikeHit", Goal = 1, Reward = 300 },
	{ Id = "tase", Text = "On foot, tase a wanted robber: get close, press TASER", Show = "Wanted",
		Kind = "TaserHit", Goal = 1, Reward = 250 },
	{ Id = "arrest", Text = "Arrest a wanted robber: tase them, then hold Cuff", Show = "Wanted",
		Kind = "Arrest", Goal = 1, Reward = 500 },
	{ Id = "rank5", Text = "Reach police rank 5 to unlock the Pursuit Special", Show = "Goals",
		Kind = "CopRank", Goal = 5, Reward = 1000 },
}

-- The big stamp when a whole chain is done.
Journey.Finished = {
	Civ = "ROAD TO THE COAST: DONE!",
	Cop = "ROOKIE NO MORE!",
}

return Journey
