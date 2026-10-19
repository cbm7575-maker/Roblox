-- Progression (ModuleScript, ReplicatedStorage.Shared.Config.Progression)
-- Ranks 1-20, levelled separately for free roam ("civ") and police ("cop") from XP (PRD "Ranks"),
-- and the daily challenge pool (PRD "Daily reasons to come back").

local Progression = {}

Progression.MaxRank = 20

-- Total XP needed to reach a rank. Rank 20 is about 12,000 XP: roughly 12-15 hours of play.
function Progression.XPFor(rank)
	if rank <= 1 then
		return 0
	end
	return math.floor(100 * (rank - 1) ^ 1.6)
end

function Progression.RankFor(xp)
	local rank = 1
	while rank < Progression.MaxRank and xp >= Progression.XPFor(rank + 1) do
		rank += 1
	end
	return rank
end

-- XP per event. Events come from the services (ProgressService.Event).
Progression.XP = {
	Heist = 40, -- x heist tier
	Bank = 1, -- per $250 banked
	Escape = 25, -- x stars you had
	RaceFinish = 30,
	RaceUnderPar = 40,
	Stunt = 25,
	Drift = 1, -- per 250 points
	TaxiFare = 15,
	CarBoost = 40,
	Arrest = 60, -- + ArrestPerStar x stars
	ArrestPerStar = 20,
	SpikeHit = 10,
	TaserHit = 5,
	PatrolMinute = 5,
}

-- What each rank unlocks (shown on rank-up and in the phone's GOALS app).
Progression.Unlocks = {
	civ = {
		[3] = "Coastal Bank heists",
		[5] = "Longer smoke trail",
		[10] = "Exclusive paint: Neon Legend",
		[15] = "Title: Legend of the Coast",
		[20] = "Gold rims",
	},
	cop = {
		[3] = "Carry 3 spike strips",
		[5] = "Pursuit Special interceptor",
		[10] = "Exclusive livery: Midnight Blue",
		[15] = "Title: Chief",
		[20] = "Gold badge rims",
	},
}

Progression.Titles = {
	civ = { [15] = "Legend of the Coast" },
	cop = { [15] = "Chief" },
}

Progression.ChallengeReward = { Cash = 2000, XP = 100 }
Progression.ChallengesPerDay = 3

-- Daily challenge pool. Kind matches the ProgressService event; Goal is the amount needed.
Progression.Challenges = {
	{ Id = "rob3", Side = "Civilian", Kind = "Heist", Goal = 3, Text = "Rob 3 stores" },
	{ Id = "bank5k", Side = "Civilian", Kind = "BankBig", Goal = 1, Text = "Bank $5,000 or more in one trip" },
	{ Id = "escape2", Side = "Civilian", Kind = "EscapeBig", Goal = 1, Text = "Lose the cops with 2+ stars" },
	{ Id = "race1", Side = "Civilian", Kind = "RaceUnderPar", Goal = 1, Text = "Win a street race under par" },
	{ Id = "stunt2", Side = "Civilian", Kind = "Stunt", Goal = 2, Text = "Land 2 stunt jumps" },
	{ Id = "taxi3", Side = "Civilian", Kind = "TaxiFare", Goal = 3, Text = "Finish 3 taxi fares" },
	{ Id = "drift3k", Side = "Civilian", Kind = "DriftPoints", Goal = 3000, Text = "Score 3,000 drift points" },
	{ Id = "boost1", Side = "Civilian", Kind = "CarBoost", Goal = 1, Text = "Deliver a boosted car" },
	{ Id = "arrest2", Side = "Cop", Kind = "Arrest", Goal = 2, Text = "Make 2 arrests" },
	{ Id = "arrest3star", Side = "Cop", Kind = "ArrestBig", Goal = 1, Text = "Arrest someone with 3+ stars" },
	{ Id = "spike2", Side = "Cop", Kind = "SpikeHit", Goal = 2, Text = "Pop 2 sets of tires with spikes" },
	{ Id = "patrol10", Side = "Cop", Kind = "PatrolMinute", Goal = 10, Text = "Patrol for 10 minutes" },
	{ Id = "taser3", Side = "Cop", Kind = "TaserHit", Goal = 3, Text = "Tase 3 suspects" },
}

return Progression
