-- Heists (ModuleScript, ReplicatedStorage.Shared.Config.Heists)
-- Every heist type, from the Game Design Spec. Payouts are in in-game dollars.
-- Hold = seconds the Rob button must be held (quick heists); multi-step heists add their steps in 2.3.

local Heists = {}

Heists.Types = {
	GlowMart = { Display = "Glow Mart", Tier = 1, CrewMin = 1, Hold = 8, Payout = { 1200, 1200 }, Heat = 1, Cooldown = 150 },
	FuelStop = { Display = "Fuel Stop", Tier = 1, CrewMin = 1, Hold = 10, Payout = { 1500, 1500 }, Heat = 1, Cooldown = 150 },
	ATM = { Display = "ATM", Tier = 1, CrewMin = 1, Hold = 12, Payout = { 900, 900 }, Heat = 1, Cooldown = 120 },
	SparkleCo = { Display = "Sparkle & Co.", Tier = 2, CrewMin = 1, Hold = 14, Payout = { 4000, 6000 }, Heat = 2, Cooldown = 240 },
	ClubNova = { Display = "Club Nova", Tier = 2, CrewMin = 1, Hold = 14, Payout = { 5000, 5000 }, Heat = 2, Cooldown = 240 },
	CoastalBank = { Display = "Coastal Bank", Tier = 3, CrewMin = 2, Hold = 20, Payout = { 16000, 16000 }, Heat = 3, Cooldown = 900, Event = true, MinRank = 3 },
	SeaDream = { Display = "Sea Dream", Tier = 3, CrewMin = 2, Hold = 18, Payout = { 14000, 14000 }, Heat = 3, Cooldown = 300 },
}

Heists.OpenCount = 4 -- rotating (non-event) heist types open at once
Heists.RotateEvery = 20 -- seconds between rotation checks
Heists.AlarmDelay = 10 -- robbers' head start before cops are alerted
Heists.AlarmSeconds = 45 -- how long a heist stays "hot" on the cops' map
Heists.CarryLimit = 15000
Heists.CrewBonus = 0.2
Heists.BankEvery = 900 -- the bank opens as a server event every 15 minutes...
Heists.BankOpenFor = 180 -- ...for 3 minutes
Heists.BankWarning = 60 -- Coast Feed countdown before it opens

-- Multi-step heists: a prep job must be done first (by you or a crewmate), then the main hold has to
-- start within Window seconds. Pos is the prep panel (placed by HeistService), Facing its front.
Heists.Types.CoastalBank.Prep = {
	Action = "Cut the power", Object = "Fuse box", Hold = 6, Window = 90,
	Pos = Vector3.new(271.4, 5, 300), Facing = Vector3.new(1, 0, 0),
	Done = "Power's out! The vault's cameras are down: crack it within 90 seconds.",
}
Heists.Types.SeaDream.Prep = {
	Action = "Disable security", Object = "Yacht alarm panel", Hold = 5, Window = 90,
	Pos = Vector3.new(1716, 3.2, 1326), Facing = Vector3.new(0, 0, -1),
	Done = "Yacht alarm off! Get to the safe within 90 seconds.",
}

-- Solo is allowed on crew heists during early testing (CrewMin enforced once crews exist, step 2.3).
Heists.EnforceCrewMin = false

return Heists
