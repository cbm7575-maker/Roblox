-- Missions (ModuleScript, ReplicatedStorage.Shared.Config.Missions)
-- Phone missions (PRD Phase 6): short GPS-guided jobs started from the phone's JOBS app.
-- Each mission is a list of steps done in order, all within TimeLimit seconds.
--   { Kind = "Goto", Pos, Radius, Text }            reach the spot (on foot or driving)
--   { Kind = "Hold", Pos, Radius, Seconds, Text }   stay there (stopped) for a few seconds ("snap a photo")
--   { Kind = "Collect", Points = { ... }, Radius, Text }   touch every point, any order
--   { Kind = "Escape", Stars, Pos, Text }           the cops get a tip: the server gives you Stars of heat
--                                                    (HeatService.Add) and the step ends when your heat is
--                                                    back to 0. Being wanted doesn't fail the mission
--                                                    during this step; getting caught does. Pos is only a
--                                                    GPS hint (the hideout, where laying low unseen clears
--                                                    heat). This heat earns no Escape XP or challenge credit.
--   { Kind = "Fragile", Pos, Radius, Text }         drive to the spot without a crash: losing more than
--                                                    FragileDrop of your speed at once from above
--                                                    FragileMinSpeed (or FragileDamage car Health) fails it.
-- Side (optional, default "Civilian"): who can take the mission. "Cop" missions are for the police
-- (the phone lists only your side's missions); they pay cash and cop XP.
-- Rewards are paid once per mission per day at full rate, then at RepeatShareFor(m) (so they can't be
-- farmed); a mission can set its own RepeatShare.

local Missions = {}

Missions.RepeatShare = 0.25
Missions.Cooldown = 20 -- seconds between missions
Missions.FragileMinSpeed = 60 -- studs/s: below this a sudden stop isn't a crash
Missions.FragileDrop = 0.4 -- losing more than 40% of your speed in a tenth of a second = a crash
Missions.FragileDamage = 20 -- or the car losing this much Health (0-100) during the step

local HIDEOUT = Vector3.new(-475, 0, 1100) -- GPS hint for "lose the cops" steps

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

	-- Hot jobs: the cops get involved (Escape steps) or the cargo can't take a bump (Fragile steps).
	{
		Id = "HotPackage",
		Name = "Hot Package",
		Blurb = "A 'no questions asked' parcel from the beach strip. Someone tipped off the cops: lose them, then drop it at the Docks.",
		TimeLimit = 360,
		Cash = 2500,
		XP = 160,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(1000, 0, -150), Radius = 30, Text = "Grab the package at the beach junction" },
			{ Kind = "Escape", Stars = 2, Pos = HIDEOUT, Text = "Cops tipped off! Lose them (or lay low at the hideout)" },
			{ Kind = "Goto", Pos = Vector3.new(-300, 0, 900), Radius = 30, Text = "Drop the package at the Rustwater warehouses" },
		},
	},
	{
		Id = "GlassCargo",
		Name = "Glass Cargo",
		Blurb = "A giant mirror for a Solana Heights gallery. Drive fast, but one crash and it's in pieces.",
		TimeLimit = 120,
		Cash = 1400,
		XP = 110,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-300, 0, -1250), Radius = 30, Text = "Load the mirror in Palm Hills" },
			{ Kind = "Fragile", Pos = Vector3.new(400, 0, 450), Radius = 30, Text = "Deliver it to the gallery. Don't crash!" },
		},
	},
	{
		Id = "WeddingCake",
		Name = "Wedding Cake",
		Blurb = "Five tiers of cake from Sunny Side Donuts to a wedding on Marina Row. Smooth driving only.",
		TimeLimit = 120,
		Cash = 1200,
		XP = 100,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-600, 0, 150), Radius = 30, Text = "Pick up the cake downtown" },
			{ Kind = "Fragile", Pos = Vector3.new(700, 0, 1000), Radius = 35, Text = "Get it to the Marina Row wedding in one piece" },
		},
	},
	{
		Id = "GetawayDriver",
		Name = "Getaway Driver",
		Blurb = "A crew needs a wheelman. Pick them up downtown, shake a 3-star chase, drop them at the Chop Shop.",
		TimeLimit = 420,
		Cash = 3500,
		XP = 220,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-300, 0, -600), Radius = 30, Text = "Pick up the crew downtown" },
			{ Kind = "Escape", Stars = 3, Pos = HIDEOUT, Text = "They're hot! Lose the cops (or lay low at the hideout)" },
			{ Kind = "Goto", Pos = Vector3.new(-780, 0, 1580), Radius = 35, Text = "Drop the crew at the Chop Shop" },
		},
	},
	{
		Id = "SwampSyrup",
		Name = "Swamp Syrup Run",
		Blurb = "Jars of famous Gator Glades hot sauce for a Docks warehouse. Glass jars, nosy inspectors.",
		TimeLimit = 300,
		Cash = 2200,
		XP = 150,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-1300, 0, -1000), Radius = 30, Text = "Load the jars in Gator Glades" },
			{ Kind = "Fragile", Pos = Vector3.new(-300, 0, 900), Radius = 30, Text = "Get the jars to the Docks without a crash" },
			{ Kind = "Escape", Stars = 1, Pos = HIDEOUT, Text = "Inspectors called the cops! Lose them" },
		},
	},

	-- Police missions (Side = "Cop"): cash + cop XP, and a bigger repeat share so cops can rank up
	-- without waiting for robbers.
	{
		Id = "BeatPatrol",
		Side = "Cop",
		Name = "Beat Patrol",
		Blurb = "Show the badge across town: check in at downtown, the beach, Palm Hills, the Glades and the Docks.",
		TimeLimit = 360,
		Cash = 1500,
		XP = 140,
		RepeatShare = 0.4,
		Steps = {
			{ Kind = "Collect", Radius = 35, Text = "Check in at every district", Points = {
				Vector3.new(50, 0, -150), Vector3.new(1000, 0, -600), Vector3.new(50, 0, -1250),
				Vector3.new(-1300, 0, -500), Vector3.new(-300, 0, 1300),
			} },
		},
	},
	{
		Id = "Code3Call",
		Side = "Cop",
		Name = "Code 3 Call",
		Blurb = "Break-in reported at a Rustwater warehouse. Lights on, get there fast and take the statement.",
		TimeLimit = 90,
		Cash = 900,
		XP = 80,
		RepeatShare = 0.4,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(-560, 0, 1300), Radius = 35, Text = "Respond to the break-in at the Docks" },
			{ Kind = "Hold", Pos = Vector3.new(-560, 0, 1300), Radius = 40, Seconds = 3, Text = "Stop and take the witness statement" },
		},
	},
	{
		Id = "SpeedTrap",
		Side = "Cop",
		Name = "Speed Trap",
		Blurb = "Run the radar on Highway 1: park by the beach stretch, then by the Glades stretch.",
		TimeLimit = 200,
		Cash = 1000,
		XP = 90,
		RepeatShare = 0.4,
		Steps = {
			{ Kind = "Hold", Pos = Vector3.new(1060, 0, -300), Radius = 30, Seconds = 15, Text = "Park beside Highway 1 at the beach and run the radar" },
			{ Kind = "Hold", Pos = Vector3.new(-1790, 0, 400), Radius = 30, Seconds = 15, Text = "Now the Glades stretch of Highway 1" },
		},
	},
	{
		Id = "HarborPatrol",
		Side = "Cop",
		Name = "Harbor Patrol",
		Blurb = "Take the Harbor Patrol boat out: sweep the marina, check the yacht, round the Key, back to the pier.",
		TimeLimit = 300,
		Cash = 1600,
		XP = 130,
		RepeatShare = 0.4,
		NeedsBoat = true,
		Steps = {
			{ Kind = "Goto", Pos = Vector3.new(1800, 0, 1480), Radius = 50, Text = "Sweep the marina (launch the boat: GARAGE)" },
			{ Kind = "Goto", Pos = Vector3.new(1760, 0, 1250), Radius = 45, Text = "Check on the Sea Dream yacht" },
			{ Kind = "Goto", Pos = Vector3.new(2500, 0, -1300), Radius = 60, Text = "Round the tip of Lighthouse Key" },
			{ Kind = "Goto", Pos = Vector3.new(1600, 0, -520), Radius = 45, Text = "Finish at the beach pier" },
		},
	},
}

Missions.ById = {}
for _, m in ipairs(Missions.List) do
	m.Side = m.Side or "Civilian"
	Missions.ById[m.Id] = m
end

-- Share of the cash and XP a repeat (2nd+ finish the same UTC day) pays.
function Missions.RepeatShareFor(m)
	return m.RepeatShare or Missions.RepeatShare
end

return Missions
