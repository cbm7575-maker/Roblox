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
-- The bag. A daytime Coastal Bank fits in the base bag even with the crew and friend bonuses
-- (16k x1.3 = 20,800), and the Big Duffel's +50% (33,000) fits the biggest bank: 16k x1.25 night
-- x1.25 VIP x1.3 crew+friend = 32,500. So the pass saves trips instead of being the only way to keep
-- a bank's cash. Raise this if heist payouts or bonuses grow.
-- Crew cuts (CrewShareBonus below) are worked out from the robber's take, their VIP included, and each
-- goes into that member's own bag. A cut is at most 3/4 of the take (one helper), so the Big Duffel
-- still fits any of them, but a cut can outgrow a helper's base bag: a VIP robber's night bank with one
-- helper is 24,375 each, and the rest is left behind (LeftBehind in that helper's HeistResult). The Big
-- Score pays banked cash, so no bag limit applies to it.
Heists.CarryLimit = 22000
Heists.CrewBonus = 0.2
-- Big heists: every heist of this tier (Coastal Bank, Sea Dream) counts toward the heist-locked cars
-- (Config.Vehicles UnlockHeists), for the robber and for crewmates helping within BigCrewRange studs.
Heists.BigTier = 3
Heists.BigCrewRange = 80 -- covers the bank's fuse box (about 40 studs from the vault) and its door
-- Crew cuts on big heists (HeistService): the pot grows by this share of the payout for each Civilian
-- crewmate helping nearby, then the robber and the helpers each get an even cut (0.5 = each helper adds
-- half a payout to the pot).
Heists.CrewShareBonus = 0.5
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

-- The Big Score (BigScoreService): a six-step crew heist, one crew at a time per server, started from the
-- phone. Hack the armored van at the Ironclad depot, drive it to the Solana Gold Reserve, hold both gate
-- consoles together, drill the vault, load the gold bars into the van and bring it to the Hideout. Paid
-- in banked cash, split evenly. Times are in seconds, distances in studs (flat). The places are on the
-- ground (y = 0 at both sites); BigScoreService builds them at start-up in Workspace.BigScore.
-- Rects are { x1, x2, z1, z2 }; north is -Z.
Heists.BigScore = {
	Display = "The Big Score",
	CrewMin = game:GetService("RunService"):IsStudio() and 1 or 2, -- Studio: 1, so it can be tested alone
	CrewMax = 4,
	MinRank = 3, -- free-roam rank (player attribute CivRank)
	TimeLimit = 1200,
	Cooldown = 1800, -- per player, after a pass
	FailCooldown = 300, -- per player, after a failed run or a quit
	-- Holds (every one is timed by the server)
	VanHold = 5, -- hack the van's lock
	ConsoleHold = 4,
	ConsoleSync = 3, -- both gate consoles must finish within this many seconds of each other...
	StudioSoloSync = 45, -- ...or this in Studio for a crew of one (one player runs between the consoles)
	DrillHold = 3, -- start the drill
	DrillTime = 30, -- seconds of drilling; it only turns while a crew member on foot is within DrillRange
	DrillRange = 14,
	GrabHold = 1,
	LoadHold = 0.5,
	LoadReach = 10, -- the Load prompt's reach from the van's LoadPoint
	LoadRange = 80, -- the van must be this close to the vault door while the gold goes in
	-- Pay
	Bars = 12,
	BarValue = 8000,
	MemberBonus = 0.1, -- the pot grows 10% for each crew member beyond 2
	NightBonus = 1.25,
	XPTier = 4, -- ProgressService.Event(p, "Heist", 4) = 160 XP
	-- Heat
	VanHeat = 1, -- stars for the hacker ("van reported stolen")
	AlarmHeat = 2, -- stars for every crew member within AlarmRange of the vault when the drill starts
	AlarmRange = 200,
	AlarmSeconds = 60,
	-- Step distances
	StreetRadius = 45, -- step 2 ends with the van this close to Street
	LeaveRadius = 150, -- step 6 starts with gold loaded and the van this far from ReserveCenter
	CarryLeash = 250, -- a carried bar goes back to the pile when its carrier is this far from it
	-- Where the two sites are. Design = the layout as drawn (BigScoreService builds both sites from these
	-- numbers and its own K.BUILDING / K.VAULT_ROOM); the lots it was drawn on turned out to be home plots
	-- (HousingService builds the Solana Heights Penthouse and the Palm Hills Ranch there), so each site is
	-- built at its design spot and then moved as one piece: turned Turn degrees about its centre (the
	-- depot rect's middle / ReserveCenter), then that centre put at To. The real positions below the
	-- design are worked out from the moves, so code reads CFG.Street & co. and gets the real place.
	Design = {
		-- Ironclad depot: low fence, open gate on the south side (+Z)
		DepotRect = { 430, 578, 4, 116 },
		DepotGateX = { 485, 525 },
		VanSpot = Vector3.new(505, 0, 50), -- the van parks here facing +Z (toward the gate)
		-- Solana Gold Reserve: walled compound, sliding gate on the design's east side (+X)
		ReserveRect = { 150, 372, -1624, -1532 },
		ReserveGateZ = { -1588, -1568 },
		ReserveCenter = Vector3.new(261, 0, -1578),
		Street = Vector3.new(392, 0, -1578), -- the street outside the gate
		ConsoleAPos = Vector3.new(376, 0, -1561),
		ConsoleBPos = Vector3.new(376, 0, -1595),
		VaultDoorPos = Vector3.new(262, 0, -1578), -- the vault doorway in the building's gate-side wall
		DrillPos = Vector3.new(266, 0, -1578),
		GoldPilePos = Vector3.new(240, 0, -1578),
		VanBayPos = Vector3.new(300, 0, -1578), -- where the van parks for loading (GPS target)
	},
	-- The port lot by the Hideout (gate onto the street to the south), and the open Palm Hills block just
	-- north of downtown (turned round so its gate faces the street on the west, x -312..-284).
	DepotMove = { To = Vector3.new(-475, 0, 1220), Turn = 0 },
	ReserveMove = { To = Vector3.new(-161, 0, -940), Turn = 180 },
}

-- The moves as CFrames (design space -> the world), and every design position at its real place.
do
	local B, D = Heists.BigScore, Heists.BigScore.Design
	local function move(from, m)
		return CFrame.new(m.To) * CFrame.Angles(0, math.rad(m.Turn or 0), 0) * CFrame.new(-from)
	end
	local function rect(cf, r)
		local a = (cf * CFrame.new(r[1], 0, r[3])).Position
		local b = (cf * CFrame.new(r[2], 0, r[4])).Position
		return { math.min(a.X, b.X), math.max(a.X, b.X), math.min(a.Z, b.Z), math.max(a.Z, b.Z) }
	end
	local dr = D.DepotRect
	B.DepotCF = move(Vector3.new((dr[1] + dr[2]) / 2, 0, (dr[3] + dr[4]) / 2), B.DepotMove)
	B.ReserveCF = move(D.ReserveCenter, B.ReserveMove)
	B.DepotRect = rect(B.DepotCF, D.DepotRect)
	B.VanSpot = (B.DepotCF * CFrame.new(D.VanSpot)).Position
	B.ReserveRect = rect(B.ReserveCF, D.ReserveRect)
	for _, key in ipairs({ "ReserveCenter", "Street", "ConsoleAPos", "ConsoleBPos", "VaultDoorPos", "DrillPos", "GoldPilePos", "VanBayPos" }) do
		B[key] = (B.ReserveCF * CFrame.new(D[key])).Position
	end
end

-- "Coastal Bank or Sea Dream": the big heists' names, for lock hints (DealerClient, HeistClient).
function Heists.BigNames()
	local names = {}
	for _, def in pairs(Heists.Types) do
		if def.Tier == Heists.BigTier then
			table.insert(names, def.Display)
		end
	end
	table.sort(names)
	return table.concat(names, " or ")
end

return Heists
