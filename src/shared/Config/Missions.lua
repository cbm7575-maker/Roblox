-- Missions (ModuleScript, ReplicatedStorage.Shared.Config.Missions)
-- Phone missions (PRD Phase 6): short GPS-guided jobs started from the phone's JOBS app.
-- Each mission is a list of steps done in order, all within TimeLimit seconds.
--   { Kind = "Goto", Pos, Radius, Text }            reach the spot (on foot or driving)
--   { Kind = "Hold", Pos, Radius, Seconds, Text }   stay there (stopped) for a few seconds ("snap a photo")
--   { Kind = "Collect", Points = { ... }, Radius, Text }   touch every point, any order
-- Rewards are paid once per mission per day at full rate, then at RepeatShare (so they can't be farmed).

local Missions = {}

Missions.RepeatShare = 0.25
Missions.Cooldown = 20 -- seconds between missions

Missions.List = {
	{
		Id = "PizzaRush",
		Name = "Pizza Rush",
		Blurb = "Grab a pizza at Taco Wave and get it to Palm Hills while it's hot.",
		TimeLimit = 120,
		Cash = 600,
		XP = 60,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(1116, 0, 260), Radius = 30, Text = "Pick up the pizza at Taco Wave" },
			{ Kind = "Goto", Pos = Vector3.new(-125, 0, -1177), Radius = 35, Text = "Deliver it to the Palm Hills Swim Club" },
		},
	},
	{
		Id = "PhotoOp",
		Name = "Photo Op",
		Blurb = "A travel blog wants three shots: the Sky Wheel, the lighthouse and the Solana Heights arch.",
		TimeLimit = 300,
		Cash = 800,
		XP = 80,
		Steps = {
			{ Kind = "Hold", Pos = Vector3.new(1650, 0, -400), Radius = 60, Seconds = 2, Text = "Stop near the Solana Sky Wheel for a photo" },
			{ Kind = "Hold", Pos = Vector3.new(2340, 0, -1300), Radius = 60, Seconds = 2, Text = "Stop by the lighthouse on Lighthouse Key" },
			{ Kind = "Hold", Pos = Vector3.new(0, 0, -200), Radius = 45, Seconds = 2, Text = "Snap the Solana Heights arch downtown" },
		},
	},
	{
		Id = "BeachCleanup",
		Name = "Beach Cleanup",
		Blurb = "Litter on Flamingo Beach! Grab all 6 pieces before the tide comes in.",
		TimeLimit = 150,
		Cash = 500,
		XP = 60,
		Steps = {
			{ Kind = "Collect", Radius = 10, Text = "Collect the litter on Flamingo Beach", Points = {
				Vector3.new(1220, 0, -1300), Vector3.new(1380, 0, -1100), Vector3.new(1260, 0, -820),
				Vector3.new(1400, 0, -560), Vector3.new(1240, 0, -200), Vector3.new(1360, 0, 120),
			} },
		},
	},
	{
		Id = "LostFlamingo",
		Name = "Lost Flamingo",
		Blurb = "Someone's lawn flamingo ran away. Find it in the Palm Hills park and bring it to Flo.",
		TimeLimit = 180,
		Cash = 700,
		XP = 70,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-125, 0, -1450), Radius = 30, Text = "Find the lost flamingo in Palm Hills Park" },
			{ Kind = "Goto", Pos = Vector3.new(1180, 0, -900), Radius = 40, Text = "Bring it home to Flo the Flamingo statue" },
		},
	},
	{
		Id = "IslandHop",
		Name = "Island Hop",
		Blurb = "Take a jet ski out to the yacht, round the Key, and back to the pier.",
		TimeLimit = 240,
		Cash = 900,
		XP = 90,
		NeedsBoat = true,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(1760, 0, 1250), Radius = 45, Text = "Cruise past the Sea Dream yacht" },
			{ Kind = "Goto", Pos = Vector3.new(2500, 0, -1300), Radius = 60, Text = "Round the tip of Lighthouse Key" },
			{ Kind = "Goto", Pos = Vector3.new(1600, 0, -520), Radius = 45, Text = "Back to the beach pier" },
		},
	},
}

Missions.ById = {}
for _, m in ipairs(Missions.List) do
	Missions.ById[m.Id] = m
end

return Missions
