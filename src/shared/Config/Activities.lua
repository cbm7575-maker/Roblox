-- Activities (ModuleScript, ReplicatedStorage.Shared.Config.Activities)
-- Open-world activities around Port Solana: street races (one on the water), stunt jumps, the drift
-- zone, taxi/courier shifts and the car meet. Coordinates are world studs (y ignored).
-- Economy rule of thumb: risk-free activities pay about $500 a minute at best, so crime (heists, about
-- $1,000-2,000 a minute) always pays at least twice as much. The UTC-day limits below are per player.

local Activities = {}

-- Street races: solo time trials with a server leaderboard. Drive onto the start pad and press E.
-- Checkpoints are passed within 30 studs, in order. Par = a good time; beating it pays the bonus.
-- The first finish of each race per UTC day pays Reward (+ ParBonus under par); later finishes that day
-- pay RaceRepeatShare of it (XP too). After a finish the same race can't start again for RaceCooldown s.
Activities.RaceRepeatShare = 0.3
Activities.RaceCooldown = 30

Activities.Races = {
	{
		Id = "OceanSprint",
		Name = "Ocean Drive Sprint",
		Start = Vector3.new(1000, 0, -1560),
		Heading = Vector3.new(0, 0, 1),
		Checkpoints = {
			Vector3.new(1000, 0, -1150), Vector3.new(1000, 0, -750), Vector3.new(1000, 0, -350),
			Vector3.new(1000, 0, 50), Vector3.new(1000, 0, 450), Vector3.new(1000, 0, 850),
			Vector3.new(1000, 0, 1250),
		},
		Par = 26,
		Reward = 400,
		ParBonus = 400,
	},
	{
		Id = "DowntownDash",
		Name = "Downtown Dash",
		Start = Vector3.new(-760, 0, -600),
		Heading = Vector3.new(1, 0, 0),
		Checkpoints = {
			Vector3.new(-300, 0, -600), Vector3.new(-300, 0, 150), Vector3.new(400, 0, 150),
			Vector3.new(400, 0, -600), Vector3.new(750, 0, -600), Vector3.new(750, 0, 450),
			Vector3.new(50, 0, 450), Vector3.new(50, 0, -150),
		},
		Par = 48,
		Reward = 600,
		ParBonus = 600,
	},
	{
		Id = "HighwayLoop",
		Name = "Highway 1 Loop",
		Start = Vector3.new(-600, 0, -1850),
		Heading = Vector3.new(1, 0, 0),
		Checkpoints = {
			Vector3.new(780, 0, -1850), Vector3.new(1000, 0, -1100), Vector3.new(1000, 0, 800),
			Vector3.new(780, 0, 1850), Vector3.new(-1000, 0, 1850), Vector3.new(-1630, 0, 1850),
			Vector3.new(-1850, 0, 700), Vector3.new(-1850, 0, -1000), Vector3.new(-1630, 0, -1850),
			Vector3.new(-700, 0, -1850),
		},
		Par = 110,
		Reward = 1200,
		ParBonus = 1000,
	},
	{
		-- Jet ski course (Boat = true: needs a boat; the start pad floats by the beach pier).
		Id = "SurfSprint",
		Name = "Surf Sprint (boats)",
		Boat = true,
		Start = Vector3.new(1640, 0, -540),
		Heading = Vector3.new(1, 0, 0),
		Checkpoints = {
			Vector3.new(1950, 0, -540), Vector3.new(2250, 0, -150), Vector3.new(2420, 0, 500),
			Vector3.new(2150, 0, 1000), Vector3.new(1850, 0, 750), Vector3.new(1950, 0, 100),
			Vector3.new(1860, 0, -620),
		},
		Par = 42,
		Reward = 700,
		ParBonus = 600,
	},
}

-- Stunt jumps: ramp (low edge first, you drive up it along Travel) and how far you must fly.
Activities.Stunts = {
	{ Id = "BeachLaunch", Name = "Beach Launch", Ramp = Vector3.new(1250, 0, -1780), Travel = Vector3.new(0, 0, 1), MinDist = 50 },
	{ Id = "BoardwalkHop", Name = "Boardwalk Hop", Ramp = Vector3.new(1320, 0, -250), Travel = Vector3.new(0, 0, -1), MinDist = 50 },
	{ Id = "SolanaAve", Name = "Solana Avenue Air", Ramp = Vector3.new(38, 0, 1400), Travel = Vector3.new(0, 0, -1), MinDist = 55 },
	{ Id = "PalmBlvdLeap", Name = "Palm Blvd Leap", Ramp = Vector3.new(-1600, 0, -138), Travel = Vector3.new(1, 0, 0), MinDist = 55 },
	{ Id = "DocksDrop", Name = "Rustwater Rocket", Ramp = Vector3.new(-200, 0, 1838), Travel = Vector3.new(1, 0, 0), MinDist = 60 },
	{ Id = "CausewayFlyer", Name = "Causeway Flyer", Ramp = Vector3.new(1500, 0, -1350), Travel = Vector3.new(1, 0, 0), MinDist = 65 },
	{ Id = "GladesHopper", Name = "Glades Hopper", Ramp = Vector3.new(-1500, 0, 150), Travel = Vector3.new(0, 0, -1), MinDist = 50 },
	{ Id = "HighwayNorth", Name = "Northern Lights", Ramp = Vector3.new(-500, 0, -1862), Travel = Vector3.new(-1, 0, 0), MinDist = 60 },
}
-- First landing ever on a ramp: StuntFirstReward (counts toward 8/8). After that the first landing on
-- each ramp per UTC day pays StuntDailyReward (+ XP); more landings that day pay nothing.
Activities.StuntFirstReward = 250
Activities.StuntDailyReward = 100

-- Drift zone: $1 per PointsPerDollar points, at most MaxChainPay a chain (XP is capped the same way).
-- The first DailyFull dollars each UTC day pay in full, then AfterShare (cash and XP).
-- Circling on the spot (every position of the last CircleSeconds within CircleRadius studs) scores nothing.
Activities.Drift = {
	PointsPerDollar = 25,
	MaxChainPay = 600,
	DailyFull = 5000,
	AfterShare = 0.25,
	CircleRadius = 40,
	CircleSeconds = 6,
}

-- Taxi and courier shifts (JobService): Base + PerStud x route length, + Tip for beating the estimate.
-- A typical fare (about 1,200 studs in 40-50 s) pays about $350-400: roughly $500 a minute.
Activities.Jobs = {
	Taxi = { Base = 80, PerStud = 0.18, Tip = 50 },
	Courier = { Base = 70, PerStud = 0.2, Tip = 60 },
}

-- Neon Nights car meet (CarMeetService). LikeCap = paid player likes per car per meet; NPC fans add up
-- to NpcCap likes. Crowd Favourite needs at least one like from a real player (no AFK solo wins).
-- ShowXP goes to every shown car that got a real like.
Activities.CarMeet = {
	LikePay = 150,
	LikeCap = 10,
	NpcCap = 3,
	FavouriteBonus = 1000,
	ShowXP = 40,
}

return Activities
