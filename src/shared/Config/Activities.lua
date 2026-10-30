-- Activities (ModuleScript, ReplicatedStorage.Shared.Config.Activities)
-- Open-world activities around Port Solana: street races (one on the water), stunt jumps, the drift zone.
-- Coordinates are world studs (y ignored).

local Activities = {}

-- Street races (RaceService runs them; RaceRules below): drive onto the start pad and press E. That opens
-- a lobby others join the same way; then everyone lines up on a grid behind Start (NPC racers fill it up
-- to RaceRules.Field cars) and races. Checkpoints are passed in order, within CheckRadius studs (or the
-- race's own Radius). Par = a good time for the WHOLE race (every lap); 1st place at or under it adds
-- ParBonus. Laps (default 1): the checkpoints are driven that many times over, so only a course whose
-- last checkpoint leads back round to its first (a loop) may have more than one.
-- Laying out a race: put every checkpoint ON a road, and keep each pair of neighbours on one street (or
-- one highway stretch), so the shortest way between them is the only sensible one. ActivityClient draws
-- the guide line along the roads between them (RoadGraph), and its turn arrows come from that line, so
-- a turn at a crossing belongs AT a checkpoint, never somewhere between two of them (a road that bends
-- by itself, like the highway's corners, is fine).
-- The road line runs on the centre line. A race laid out in its own lanes sets LineOffset (studs right
-- of the centre line, in the way it is driven): the line is drawn there, so the chevrons never lead
-- into the oncoming lanes (where the stunt ramps sit, see Stunts below). Put its checkpoints in those
-- lanes too, so the rings and the line agree.
-- Boat races (Boat = true) are drawn as straight lines over the water (in white: cyan is lost on the
-- sea): keep those clear of piers. Nothing fences a ring in out there, so a boat can go round one: the
-- client then turns its line back to the ring that was missed.
-- Route check (2026-10, against CityGen's roads):
--   OceanSprint   one straight run south down Ocean Drive (Highway 1's east side, x = 1000).
--   DowntownDash  every leg is one street; the turn is always at the checkpoint's crossing
--                 (right, left, left, right, right, right, right).
--   HighwayLoop   every leg stays on Highway 1; the four bends are the highway's own corners. Driven
--                 clockwise (right-hand bends), all of it 12 studs right of the centre line. A real loop:
--                 the last checkpoint (-700, -1838) is 100 studs short of Start on the same stretch, so
--                 lap 2 runs on past the pad to checkpoint 1. 2 laps (about 24,400 studs): Par 215 (one
--                 lap took 110 from a standing start), the pay raised to match.
--   SurfSprint    open water; the last leg passes 120 studs east of the Ferris pier's end.
Activities.CheckRadius = 32
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
		-- The whole loop runs 12 studs right of the centre line (the racer's own lanes): on the north and
		-- south straights that keeps it clear of the Northern Lights and Rustwater Rocket ramps in the
		-- oncoming lanes. Start, checkpoints and the guide line (LineOffset) all sit in those lanes.
		-- Radius 44: the checkpoints sit off-centre on a 60-stud road, and the far lane must count too.
		Id = "HighwayLoop",
		Name = "Highway 1 Loop",
		Radius = 44,
		LineOffset = 12,
		Laps = 2,
		Start = Vector3.new(-600, 0, -1838),
		Heading = Vector3.new(1, 0, 0),
		Checkpoints = {
			Vector3.new(780, 0, -1838), Vector3.new(988, 0, -1100), Vector3.new(988, 0, 800),
			Vector3.new(780, 0, 1838), Vector3.new(-1000, 0, 1838), Vector3.new(-1630, 0, 1838),
			Vector3.new(-1838, 0, 700), Vector3.new(-1838, 0, -1000), Vector3.new(-1630, 0, -1838),
			Vector3.new(-700, 0, -1838),
		},
		Par = 215, -- (2 laps)
		Reward = 2000,
		ParBonus = 1600,
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

-- How street races with others run (RaceService; ActivityClient shows the lobby banner and the field).
Activities.RaceRules = {
	Lobby = 12, -- seconds a race's lobby stays open after the first press of Race on its pad...
	LobbySolo = 6, -- ...or this, when no other citizen is within 2 x LobbyShow studs of the pad then
	LobbyShow = 150, -- studs from the pad: citizens this close see the lobby banner
	MaxRacers = 6, -- players in one race
	NPCs = true, -- fill the grid with NPC racers (never on the water)...
	Field = 4, -- ...up to this many cars in all
	NPCSpeed = 0.94, -- an NPC's top speed, x the fastest player car's in the race (they never use nitro)
	NPCCatchUp = 0.05, -- NPCs ease off this much while they lead every player, push this much while they trail all
	Pay = { 1, 0.6, 0.35 }, -- share of Reward by place (1st also gets ParBonus at or under par)...
	PayRest = 0.15, -- ...and for every later place
	SpotChance = 0.35, -- chance the police spot a race (not on the water): +1 star for everyone still racing...
	SpotFrom = 0.25, -- ...at a random moment between these shares of par after GO
	SpotTo = 0.6,
}

-- Race challenges: two drivers next to each other race on a route the server makes up on the spot
-- (RaceService). No money, never police.
Activities.Challenge = {
	ShowReach = 60, -- studs: CHALLENGE shows with another free driver this close
	Reach = 80, -- studs: the server's limit for a challenge (some lag and drift allowed)
	AcceptReach = 150, -- studs apart at most when it is accepted (and for a rematch)
	Expire = 15, -- seconds a challenge waits for an answer
	MinLength = 1000, -- studs by road from the start crossing to the finish...
	MaxLength = 1600,
	CheckpointEvery = 200, -- studs between checkpoints (plus one at every bend and the finish)
	Rematch = 15, -- seconds REMATCH stays on the result
}

-- Stunt jumps: ramp (low edge first, you drive up it along Travel) and how far you must fly.
-- Ramps on a road sit in the lanes that drive along Travel (traffic keeps right), so nobody
-- driving the other way meets the tall back face. Moving one means re-running CityGen in Studio.
Activities.Stunts = {
	{ Id = "BeachLaunch", Name = "Beach Launch", Ramp = Vector3.new(1250, 0, -1780), Travel = Vector3.new(0, 0, 1), MinDist = 50 },
	{ Id = "BoardwalkHop", Name = "Boardwalk Hop", Ramp = Vector3.new(1320, 0, -250), Travel = Vector3.new(0, 0, -1), MinDist = 50 },
	{ Id = "SolanaAve", Name = "Solana Avenue Air", Ramp = Vector3.new(62, 0, 1400), Travel = Vector3.new(0, 0, -1), MinDist = 55 },
	{ Id = "PalmBlvdLeap", Name = "Palm Blvd Leap", Ramp = Vector3.new(-1600, 0, -138), Travel = Vector3.new(1, 0, 0), MinDist = 55 },
	{ Id = "DocksDrop", Name = "Rustwater Rocket", Ramp = Vector3.new(-200, 0, 1862), Travel = Vector3.new(1, 0, 0), MinDist = 60 },
	{ Id = "CausewayFlyer", Name = "Causeway Flyer", Ramp = Vector3.new(1500, 0, -1340), Travel = Vector3.new(1, 0, 0), MinDist = 65 },
	{ Id = "GladesHopper", Name = "Glades Hopper", Ramp = Vector3.new(-1500, 0, 150), Travel = Vector3.new(0, 0, -1), MinDist = 50 },
	{ Id = "HighwayNorth", Name = "Northern Lights", Ramp = Vector3.new(-500, 0, -1862), Travel = Vector3.new(-1, 0, 0), MinDist = 60 },
}
Activities.StuntFirstReward = 250
Activities.StuntRepeatReward = 50

-- The drift zone on Lighthouse Key. The pad itself is Workspace.Activities.DriftZone (built by CityGen
-- with these numbers); the client uses them while that part isn't streamed in yet.
Activities.DriftZone = {
	Center = Vector3.new(2200, 0, -1350),
	Size = Vector3.new(190, 0, 340),
}
-- How drift points turn into cash: $1 per PointsPerDollar, at most MaxPayout a chain, nothing under
-- MinScore points. DriftService pays by these numbers and ActivityClient shows "worth so far" from
-- them while you slide: this table is the only place to change them.
Activities.Drift = {
	PointsPerDollar = 25,
	MaxPayout = 600,
	MinScore = 50,
}

return Activities
