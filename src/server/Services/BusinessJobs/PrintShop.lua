-- PrintShop (ModuleScript, ServerScriptService.Services.BusinessJobs.PrintShop)
-- The Backlot Print Shop, Empire's third business and its first SHADY one (M3 of launch/10-BUSINESSES-PRD.md v2;
-- every number in Config.Businesses: the PrintShop entry, Print, Launder and Raid). This is BusinessService's
-- "job module" for it: it draws the building, runs its shift (PRINT and LAUNDER, the dirty cash) and runs its
-- POLICE RAIDS. Everything else (owning it, its register and levels, the featured-owner sign, crew cuts, Empire
-- XP, saving, the remotes) is BusinessService's, which calls in here with its own helpers (Api: see JOB MODULES
-- in its header). Nothing here runs unless BusinessService does (the launch switch, Config.Businesses.Live).
--
-- THE BUILDING (PrintShop.Style; Look 3.0, gritty: dark brick, corrugated and diamond-plate steel, concrete, no
-- big neon sign: a small painted PRINT & COPY board is its front). Lot space as every business lot: origin at the
-- lot centre, -Z toward the street (Rustwater Docks' z = 1650 street, to the south), +X to the right looking at
-- the street.
--   * The shop (x -26..16, z -2..22, 14 tall). Its front: the PRINT & COPY office on the left (the door at x
--     -21..-17, Layout.Door, and a small window), a blank brick stretch with a high window band, and the roll-up
--     loading door (x 0..8) with its shutter half down, a floodlight over it and the owner plate on its header
--     (FOR SALE · $90,000, or the featured owner's name; the client re-dresses it).
--   * The front office (x -25..-12, z -1..6): the counter with the till (Layout.Register), a copier, a flyer rack.
--     A doorway at the back of it leads into the workshop.
--   * The workshop: the three print stations along the back (Layout.Stations): the paper pallet, the plate bench,
--     the old press (its out tray: Layout.Tray), the counting table between the bench and the press (Layout.Cash:
--     the fake bills stack up here on the owner's device), the spot the cops search (Layout.Search).
--   * The forecourt: the painted LOADING bay in front of the roll-up door (Layout.Bay), the cash cart beside the
--     door (Layout.Load), yellow bollards, oil stains; a dumpster, a pallet stack and a chain-link fence in the
--     side yard. Solid: the walls, roof, counters, the stations, the dumpster, the pallets, the fence, the
--     bollards; all inside the lot.
--   * LEVEL PROPS (PRD section 5; child Models with MinLevel / MaxLevel, drawn per device, never solid):
--       1  one old press in a back room (the stations; the wooden door: levels 1-3)
--       2  a second press and the paper store (shelves of reams along the left wall)
--       3  drying racks (lines of fresh bills hung over the workshop) and a hidden back door (a shelf that swings)
--       4  the counting room (a steel cage with a cash table, a money counter and a safe) and the armored door
--          (a riveted steel door and frame on the shop door: breaches take Raid.ArmoredHold)
--       5  the full counterfeit floor: a big modern press, a guillotine cutter, pallets of shrink-wrapped bills and
--          violet UV work lights
--   Returns the owner plate's title label (BusinessService's publishOwners writes FOR SALE / the owner).
--
-- THE SHIFT (JobKind "BizPrint" at the shop, "BizLaunder" on a run with the bags). START JOB > PRINT or LAUNDER
-- starts it (the owner, or a crewmate working for an owner in the server: the owner's level sets the numbers, the
-- dirty cash is the owner's stock, a crewmate's launder pay gives the owner the 20% cut, as M1). Both work for the
-- whole shift; the button only says which the HUD suggests first (Switch changes it).
--   * BusinessJob "Print" { Id, Stage = "shop", Mode, Station (the next one, 1-3), Streak, Mult, Level, Owner,
--     OwnerName, Count, Earned, Dirty, Stock, Carry, Back (after a run), Stations (the config's, for the gauge) }.
--   * PRINT: RequestBusiness("Step", "HoldOn") then "HoldOff". The server picks what the hold is from where you
--     stand on foot: within Launder.LoadRange of the cash cart = LOAD; within Print.Range of the next station = that
--     station (any other station: "PrintStep" { Again, Far, Station }). It times the hold on its own clock and
--     grades it (Businesses.PrintGrade): Early = it didn't count ("PrintStep" { Again, Early, Station }, the
--     streak back to 0); OK or PERFECT = the next station ("PrintStep" { Grade, Station, Streak, Mult }; PERFECT
--     adds to the streak, OK resets it). The third station is the press run: Businesses.PrintBatch(the owner's
--     level, PERFECTs in this run, the streak) into the owner's dirty stock (up to Businesses.Stock), the owner's
--     jobsDone, Empire XP Print for the worker, "Printed" { Grade, Amount, Batch, Perfects, Streak, Mult, Dirty,
--     Stock, Full, Count }. Starting station 1 with a full stock: refused ("StockFull": launder some first).
--   * LOAD (the cash cart, Launder.LoadHold): your own car (VehicleService.GetCar, not a boat, OwnerUserId yours)
--     standing in the loading bay (within BayRange of Layout.Bay, under BaySpeed), stock in the shop ("NoStock",
--     "NotInBay" otherwise) and a drop point (JobService.RoadsideSpot DistMin-DistMax away; "NoAddress"). Then
--     Businesses.Carry(level) of the stock goes into that car (job.bags; out of the stock at once), JobKind
--     "BizLaunder", "Loaded" { Bags, Pos, Name, Dirty, Grace }.
--   * THE RUN (four times a second, Tick): in that car's driver's seat (out of it LeaveGrace seconds: the bags are
--     lost, "BagsLeft"; the car gone or sunk: "BagsCar"). THE HEAT METER (Businesses.HeatStep; player attribute
--     BizHeat, 0-1 in 0.05 steps, for the strip): the nearest police within HeatRange (a player cop, an AI patrol
--     car, an AI officer on foot, the police HQ: Workspace.Spawns.CopSpawn and Workspace.City.Landmarks.PoliceHQ)
--     fill it, a wall between you slows it (one raycast a tick); it drains with none in range. Full = SPOTTED.
--     Tip-offs: every SpotEvery seconds while moving faster than MinSpeed, a SpotChance[level] roll. Spotted =
--     HeatService.Add(Stars, or PatrolStars with the police within PatrolNear), "Spotted" { Stars, How }, and the
--     run is no longer clean. Being wanted doesn't end the run (KeepWanted). Stopped in the drop ring: the taxi's
--     speed check (FastSlack from the bay, VehicleGuard; failing it ends the shift, "Invalid", the bags lost), then
--     Businesses.LaunderPay (the clean-run bonus if you were never wanted on the way), reason
--     "bizjob:<id>:launder", the owner's books (jobsDone, lifetime, crew cut), Empire XP Launder, "Laundered"
--     { Pay, Bonus, Clean, Bags, Count, Earned, Runs }, and back to the shop ("Print" with Back).
--   * THE BAGS ARE LOST (End, "BagsLost" { Amount, Why }) when the shift ends any way with bags in the car, except
--     END JOB while you're at the shop and not wanted ("BagsBack": they go back into the stock). Arrested shows as
--     Why = "Arrested".
--   * ENDS: no hold that counted at the shop for IdleTime ("Idle"), the ones above, and BusinessService's own
--     (END JOB, wanted at the shop, side, died, the owner leaving, another job taking JobKind). "Ended" carries the
--     shift's Summary { Prints, Perfects, Best (the best streak), BestMult, Runs, CleanRuns, Dirty (printed) }.
--
-- POLICE RAIDS (Config.Businesses.Raid; Second runs them once a second). (M5: the raid code below now lives in the
-- shared module Services.BusinessJobs.Raids, which the Nightclub's back room uses too; this shop registers itself
-- there with its stock, the armored door's breach, the presses and the officers' way in, and its behaviour is
-- unchanged.) Per owner (clocks by UserId: never an Instance as a weak key, the Nov 4 Studio lesson): the first roll at Raid.MinPlay of their play clock
-- (BusinessService's, x BusinessTimeScale in Studio), then one every Check; a raid's end pushes the next one Gap
-- away. A roll happens with Raid.MinDirty+ in their stock, the owner a living citizen and no raid at the building
-- (nor in the SiteGap after one), and hits at Businesses.WarrantChance. At most one raid per building.
--   * A PLAYER RAID when an eligible cop is in the server (Side "Cop" and ArrestService.IsActiveCop, or the Studio
--     test cop, Workspace attribute BizTestCop = their Name; never the owner or the owner's crewmates). Prompts on
--     the building: "BizBreachPrompt" at the door (HoldDuration Businesses.BreachHold(the owner's level)), then
--     after the breach "BizSearchPrompt" at the presses (Raid.SearchHold). The server times both holds itself
--     (PromptButtonHoldBegan -> Triggered, as ArrestService's cuffs), checks the cop again, on foot, within
--     CopRange, the right stage, rate-limited. The breach stretches the warrant to SearchMin from then. The search
--     SEIZES all of that owner's dirty cash; every eligible cop within Reach of the lot then gets
--     Businesses.RaidReward (reason "bizraid:<id>") and the SEIZED stamp; ProgressService event "BizRaid". If the
--     last eligible cop leaves or goes off duty before the breach, the raid turns into an AI one.
--   * AN AI RAID otherwise: AIArrive seconds in, a police car (CarBuilder "SunrayPatrol", anchored, prompts and
--     seats off, in Workspace "BizRaid", attribute BizRaidCar) pulls up at Layout.RaidCar and AIOfficers officers
--     (PoliceOfficerService's OfficerTemplates looks, anchored, no NPCKind: nobody can hit them) walk to the door.
--     Their breach (AIBreach) and search (AISearch) only count down while NOBODY holds the door; a search takes
--     Businesses.AISeizeAmount, no reward.
--   * THE OWNER AND CREW: BusinessResult "Raid" { Id, Role = "Owner" | "Crew" | "Cop", Until (server time), Owner,
--     OwnerName, Ai, Hold }, then "RaidBreached" { Until }, and the end: "RaidSeized" { Amount, Reward (a cop's
--     own) }, "RaidHeld" { Bonus, XP } (owner and crew), or "RaidOver" { Why = "Expired" | "Gone" }. HOLDING THE
--     DOOR: an owner or crewmate inside (Businesses.Inside) counts; with no seizure and HeldMin seconds held when
--     the warrant runs out, the owner gets HeldBonus and Empire XP RaidHeld, and every crewmate who was inside
--     HeldMin seconds CrewHeldBonus and the same XP ("bizraidheld:<id>"). A Coast Feed post (FeedController's
--     generic "Event") tells the server how it ended.
--   * The owner leaving: after a breach their stock is seized as they go (no dodging a search by quitting; their
--     save is written after this); before it, the raid is called off.
--   * Everyone sees the raids through ReplicatedStorage attribute BizRaids = JSON { [id] = { o = owner UserId,
--     n = owner name, s = "warrant" | "search", u = server time it ends, ai, b = the AI's progress 0-1, h = held
--     (someone inside now), c = { cop UserIds sent } } }; BizAlarm (BusinessService) flashes the map for everyone in
--     a raid (Alarms). Dirty cash, clean money and upgrades: only the dirty cash is ever taken.
--
-- STUDIO (PrintShop.Debug, through BusinessService.Debug): "dirty" (value: set your stock; none = full), "raid"
-- (a warrant at your Print Shop now, whatever the clocks: value "ai" = the AI raid, a number = seconds on it),
-- "endraid", "testcop" (value: a player Name who counts as an on-duty cop; "" for none), "heat" (value 0-1: your
-- run's meter).
--
-- API (BusinessService calls these; A = its Api table): Kinds, Style, Start, Resend, Switch, Step, Tick, End,
-- KeepWanted, Init, Second, State, Alarms, PlayerLeft, Debug (see JOB MODULES in its header).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)
local Raids = require(script.Parent:WaitForChild("Raids")) -- (M5: the shared raid engine)

local PrintShop = {}

-- The job kinds this module runs, and the JobKind attribute for each (BusinessService's JOB MODULES).
PrintShop.Kinds = { Print = "BizPrint", Launder = "BizLaunder" }

local PR = Businesses.Print
local LA = Businesses.Launder
local RA = Businesses.Raid
local E = Businesses.Empire

-- Looks, words and constants that aren't balance (balance lives in Config.Businesses).
local K = {
	H = 14, -- the shop's height (the roof slab sits on it)
	BRICK = Color3.fromRGB(116, 62, 50), -- old dark-red brick
	BRICK_DARK = Color3.fromRGB(88, 50, 42),
	STEEL = Color3.fromRGB(104, 108, 112), -- corrugated sheet, the shutter
	RUST = Color3.fromRGB(132, 86, 56),
	FLOOR = Color3.fromRGB(128, 126, 120), -- the workshop's concrete
	OIL = Color3.fromRGB(42, 42, 44),
	PRESS = Color3.fromRGB(56, 82, 70), -- the old press's green enamel
	PAPER = Color3.fromRGB(238, 234, 220),
	BILL = Color3.fromRGB(122, 168, 112), -- fresh fake bills
	WOOD = Color3.fromRGB(150, 116, 76), -- pallets, the counter
	BEIGE = Color3.fromRGB(214, 206, 186), -- the copier
	UV = Color3.fromRGB(170, 110, 255), -- the level-5 work lights
	WRAP = Color3.fromRGB(220, 236, 230), -- shrink wrap
	SEAT_UP = 3.4, -- a car's pivot above the lot's ground (as BusinessService)
	WALK = 11, -- studs/s an AI officer walks at
	CAR_IN = 2.5, -- seconds the AI police car takes to pull up
	-- The AI officers' way in (lot space): the door, through the office, to the presses.
	PATH_IN = { Vector3.new(-19, 0, -0.5), Vector3.new(-18.5, 0, 8.5), Vector3.new(-7, 0, 11) },
	-- Where launder drops are (the toasts and the strip).
	DROPS = { "the laundromat", "a car wash out back", "the pawn shop", "a taxi depot", "the arcade", "a nail salon",
		"the scrapyard", "a bodega", "the bowling alley", "a tattoo parlour", "the fish market", "a parking garage" },
	SAY_GAP = 6, -- seconds between two shouts from a waiting AI officer
	CHECK_CAR = 0.5, -- seconds between two line-of-sight rays for the heat meter
	ONE_BUILDING = "PrintShop", -- (the only shady business so far: raids look it up by id)
}

local S = {
	A = nil, -- BusinessService's Api (Init)
	hq = {}, -- the police HQ's positions (the heat meter's fixed police)
	-- (the raids' own state, S.raids / S.owners / BizRaids, lives in BusinessJobs.Raids since M5)
}

------------------------------------------------------------------ small helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(p)
	local char = p and p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil, hum
	end
	return char:FindFirstChild("HumanoidRootPart"), hum
end

-- On foot within `range` (flat) of a lot-space spot, and on the same floor.
local function onFootAt(p, def, spot, range)
	local root, hum = rootOf(p)
	if not root or not hum or hum.SeatPart then
		return false
	end
	local at = Businesses.At(def, spot)
	return flat(root.Position - at).Magnitude <= range and math.abs(root.Position.Y - at.Y) < 12
end

local function topSpeed(car)
	return (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
end

local function studioCop(p)
	return RunService:IsStudio() and p ~= nil and Workspace:GetAttribute("BizTestCop") == p.Name
end

local function setHeat(player, v)
	local want = v and math.floor(math.clamp(v, 0, 1) * 20 + 0.5) / 20 or nil
	if player.Parent == Players and player:GetAttribute("BizHeat") ~= want then
		player:SetAttribute("BizHeat", want)
	end
end

------------------------------------------------------------------ the building (Look 3.0, gritty)

-- Shop-floor odds and ends (a pallet, its stacks), so Style stays readable.
local function pallet(A, parent, f, x0, x1, z0, z1, solid)
	local Build, DETAIL = A.Build, A.DETAIL
	Build.box(parent, "Pallet", f, x0, x1, 0.35, 0.85, z0, z1, K.WOOD, Enum.Material.WoodPlanks, if solid then nil else DETAIL)
end

-- Bills stacked on a surface at height y: n bundles in a row along x from x0 (looks only).
local function bundles(A, parent, f, x0, z, y, n, color)
	for i = 0, n - 1 do
		local x = x0 + i * 0.9
		A.Build.box(parent, "Bundle", f, x, x + 0.75, y, y + 0.35, z - 0.35, z + 0.35, color or K.BILL, Enum.Material.SmoothPlastic, A.DETAIL)
		A.Build.box(parent, "Band", f, x + 0.3, x + 0.45, y + 0.35, y + 0.37, z - 0.36, z + 0.36, Color3.fromRGB(240, 220, 120),
			Enum.Material.SmoothPlastic, A.DETAIL)
	end
end

-- The Backlot Print Shop (see the header). Returns the plate's title label.
function PrintShop.Style(m, f, def, A)
	local Build, C, DETAIL = A.Build, A.C, A.DETAIL
	local box, post, group = Build.box, Build.post, Build.group
	local H = K.H
	local L = def.Layout
	local front = Enum.NormalId.Front
	local brick, metal, plate = Enum.Material.Brick, Enum.Material.Metal, Enum.Material.DiamondPlate
	local smooth, concrete = Enum.Material.SmoothPlastic, Enum.Material.Concrete

	-- THE SHELL (x -26..16, z -2..22) ---------------------------------------------------------------------------
	box(m, "ShopFloor", f, -25, 15, 0.2, 0.35, -1, 21, K.FLOOR, concrete)
	box(m, "BackWall", f, -26, 16, 0.2, H, 21, 22, K.BRICK, brick)
	box(m, "SideWall", f, -26, -25, 0.2, H, -2, 21, K.BRICK, brick)
	box(m, "SideWall", f, 15, 16, 0.2, H, -2, 21, K.BRICK, brick)
	-- The front: wall | shop door (x -21..-17) | pier | window (x -16..-13) | wall with a high window band |
	-- the roll-up door (x 0..8) | wall.
	box(m, "FrontWall", f, -26, -21, 0.2, H, -2, -1, K.BRICK, brick)
	box(m, "Lintel", f, -21, -17, 8.4, H, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, -17, -16, 0.2, H, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, -16, -13, 0.2, 3, -2, -1, K.BRICK, brick)
	Build.glass(m, f, -16, -13, 3, 7.5, -1.8, -1.2)
	box(m, "FrontWall", f, -16, -13, 7.5, H, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, -13, 0, 0.2, 10, -2, -1, K.BRICK, brick)
	Build.glass(m, f, -12, -1, 10, 12, -1.8, -1.2)
	box(m, "FrontWall", f, -13, -12, 10, 12, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, -1, 0, 10, 12, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, -13, 0, 12, H, -2, -1, K.BRICK, brick)
	box(m, "RollupHeader", f, 0, 8, 10, H, -2, -1, K.BRICK, brick)
	box(m, "FrontWall", f, 8, 16, 0.2, H, -2, -1, K.BRICK, brick)
	-- Brick trims: a darker band at the plinth and under the roof.
	box(m, "Plinth", f, -26.1, 16.1, 0.2, 1, -2.1, -1.9, K.BRICK_DARK, brick, DETAIL)
	box(m, "Cornice", f, -26.3, 16.3, H - 0.6, H, -2.3, -1.9, K.BRICK_DARK, brick, DETAIL)
	box(m, "Roof", f, -26.5, 16.5, H, H + 0.6, -2.5, 22.5, C.CONCRETE, concrete, { CastShadow = true })
	box(m, "Parapet", f, -26.5, 16.5, H + 0.6, H + 1.4, -2.5, -2, K.BRICK_DARK, brick, DETAIL)
	box(m, "RoofUnit", f, -8, -2, H + 0.6, H + 3, 8, 13, K.STEEL, metal, DETAIL)
	post(m, "Vent", f, 10, 15, H + 0.6, 3.5, 1.2, K.STEEL, metal, DETAIL)
	-- The roll-up door: its shutter half down (it never blocks the way in), the drum box, the floodlight.
	box(m, "Shutter", f, 0, 8, 7, 10, -1.9, -1.5, K.STEEL, Enum.Material.CorrodedMetal, DETAIL)
	for y = 7.3, 9.8, 0.5 do
		box(m, "ShutterRib", f, 0, 8, y, y + 0.08, -1.95, -1.9, C.DARK_METAL, metal, DETAIL)
	end
	box(m, "ShutterBox", f, -0.3, 8.3, 10, 11, -2.6, -2, C.DARK_METAL, metal, DETAIL)
	for _, x in ipairs({ -0.2, 7.9 }) do
		box(m, "ShutterRail", f, x, x + 0.3, 0.35, 10, -2.05, -1.85, C.DARK_METAL, metal, DETAIL)
	end
	Build.lamp(m, f, 3, 5, 12.4, 12.8, -3, -2.2, 26)
	-- The owner plate on the roll-up door's header, and the small PRINT & COPY board over the shop door.
	local plateBox = box(m, "OwnerPlate", f, 0.2, 7.8, 11.6, 13.2, -2.16, -2.04, C.DARK, metal, DETAIL)
	local plateGui = Build.signGui(plateBox, front, "FOR SALE · " .. A.money(def.Price), nil, C.GOLD)
	local board = box(m, "Sign", f, -24.5, -13.5, 8.8, 11.2, -2.3, -2.05, Color3.fromRGB(232, 226, 210), Enum.Material.Wood)
	Build.signGui(board, front, "PRINT & COPY", "FLYERS · POSTERS · COPIES", Color3.fromRGB(40, 40, 46), Color3.fromRGB(150, 40, 40), true)
	-- Spray paint on the right-hand wall (looks only).
	local tag = box(m, "Tag", f, 9, 15, 2, 6, -2.06, -2.02, K.BRICK, smooth,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	Build.signGui(tag, front, "BACKLOT", nil, Color3.fromRGB(255, 92, 170), nil, true)

	-- THE FRONT OFFICE (x -25..-12, z -1..6) --------------------------------------------------------------------
	box(m, "Partition", f, -25, -20, 0.35, 10, 6, 6.6, K.BRICK, brick)
	box(m, "Partition", f, -17, -12, 0.35, 10, 6, 6.6, K.BRICK, brick)
	box(m, "Partition", f, -20, -17, 8.4, 10, 6, 6.6, K.BRICK, brick)
	box(m, "Partition", f, -12.6, -12, 0.35, 10, -1, 6, K.BRICK, brick)
	box(m, "OfficeCeiling", f, -25, -12, 10, 10.3, -1, 6.6, C.WHITE, Enum.Material.Plaster, DETAIL)
	Build.roomLight(m, f, -22, -15, 10, 1, 4, Color3.fromRGB(240, 240, 230), 16)
	box(m, "Counter", f, -25, -22.5, 0.35, 3.4, 0.5, 5, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "CounterTop", f, -25, -22.3, 3.4, 3.7, 0.3, 5.2, C.DARK_METAL, metal)
	local reg = L.Register
	box(m, "Register", f, reg.X - 0.6, reg.X + 0.6, 3.7, 4.6, reg.Z - 0.5, reg.Z + 0.5, C.DARK, smooth, DETAIL)
	box(m, "Copier", f, -16, -13.5, 0.35, 3.4, 3.8, 5.8, K.BEIGE, smooth)
	box(m, "CopierLid", f, -16, -13.5, 3.4, 3.6, 3.8, 5.8, C.DARK_METAL, smooth, DETAIL)
	box(m, "FlyerRack", f, -20, -17.4, 1, 6, 5.6, 6, C.DARK_METAL, metal, DETAIL)
	for i = 0, 2 do
		box(m, "Flyer", f, -19.8 + i * 0.85, -19.1 + i * 0.85, 2 + i, 3 + i, 5.5, 5.6,
			({ Color3.fromRGB(255, 200, 80), Color3.fromRGB(110, 190, 255), Color3.fromRGB(255, 120, 140) })[i + 1], smooth, DETAIL)
	end
	local open = box(m, "OpenSign", f, -24.6, -22.6, 5, 6.2, 5.9, 5.98, C.DARK, smooth, DETAIL)
	Build.signGui(open, front, "OPEN", "COPIES 10¢", Color3.fromRGB(255, 90, 90), C.WHITE, true)

	-- THE WORKSHOP --------------------------------------------------------------------------------------------
	Build.roomLight(m, f, -20, 10, H - 0.1, 9, 12, Color3.fromRGB(255, 226, 190), 26)
	Build.roomLight(m, f, -20, 10, H - 0.1, 15, 18, Color3.fromRGB(255, 226, 190), 22)
	local st = L.Stations
	-- 1: the paper pallet (back left).
	pallet(A, m, f, -24, -18, 15.5, 19.5, true)
	for i, x in ipairs({ -23.6, -21.4, -19.2 }) do
		box(m, "Reams", f, x, x + 1.8, 0.85, 3 + (i % 2) * 0.8, 15.9, 19.1, K.PAPER, smooth)
	end
	local s1 = box(m, "StationSign", f, -23, -19, 7, 8.4, 20.84, 20.98, C.DARK, smooth, DETAIL)
	Build.signGui(s1, front, "1 · PAPER", nil, C.WHITE)
	-- 2: the plate bench.
	for _, x in ipairs({ -13.6, -6.4 }) do
		box(m, "BenchLeg", f, x - 0.2, x + 0.2, 0.35, 3.2, 16.2, 16.6, C.DARK_METAL, metal, DETAIL)
		box(m, "BenchLeg", f, x - 0.2, x + 0.2, 0.35, 3.2, 18, 18.4, C.DARK_METAL, metal, DETAIL)
	end
	box(m, "Bench", f, -14, -6, 3.2, 3.5, 16, 18.6, C.STEEL, plate)
	for i = 0, 3 do
		box(m, "Plate", f, -13.4 + i * 1.9, -12 + i * 1.9, 3.5, 3.56, 16.4, 17.6, Color3.fromRGB(196, 200, 206), metal, DETAIL)
	end
	post(m, "LampArm", f, -7, 18.2, 3.5, 3, 0.15, C.DARK_METAL, metal, DETAIL)
	box(m, "BenchLamp", f, -7.6, -6.4, 6.3, 6.8, 17, 18, C.SAFETY, metal, DETAIL)
	local s2 = box(m, "StationSign", f, -12, -8, 7, 8.4, 20.84, 20.98, C.DARK, smooth, DETAIL)
	Build.signGui(s2, front, "2 · PLATES", nil, C.WHITE)
	-- The counting table (fake bills stack up here on the owner's device: BusinessClient) and its lamp.
	box(m, "CashTable", f, -5, -1.6, 2.6, 2.9, 18.8, 20.8, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "CashTableLeg", f, -4.8, -4.5, 0.35, 2.6, 19, 19.3, C.DARK_METAL, metal, DETAIL)
	box(m, "CashTableLeg", f, -2.1, -1.8, 0.35, 2.6, 20.3, 20.6, C.DARK_METAL, metal, DETAIL)
	-- 3: the old press (x 0..8, z 13..18): its base, the green body, rollers, a flywheel, the out tray in front.
	box(m, "PressBase", f, 0, 8, 0.35, 2, 13, 18, C.DARK_METAL, metal)
	box(m, "PressBody", f, 0.5, 7.5, 2, 6, 13.5, 17.5, K.PRESS, metal)
	for _, z in ipairs({ 14.2, 15.5, 16.8 }) do
		local roller = Build.part(m, "Roller", Vector3.new(7.4, 0.7, 0.7), f * CFrame.new(4, 6.3, z), C.STEEL, metal, DETAIL)
		roller.Shape = Enum.PartType.Cylinder
	end
	local wheel = Build.part(m, "Flywheel", Vector3.new(0.4, 4, 4), f * CFrame.new(8.25, 4, 15.5), C.DARK_METAL, metal, DETAIL)
	wheel.Shape = Enum.PartType.Cylinder
	local tray = L.Tray
	box(m, "OutTray", f, tray.X - 2.2, tray.X + 2.2, 3.2, 3.4, tray.Z - 0.6, 13.5, C.STEEL, metal, DETAIL)
	box(m, "Sheets", f, tray.X - 1.6, tray.X + 1.6, 3.4, 3.6, tray.Z - 0.4, 13.2, K.PAPER, smooth, DETAIL)
	local s3 = box(m, "StationSign", f, 2, 6, 7, 8.4, 20.84, 20.98, C.DARK, smooth, DETAIL)
	Build.signGui(s3, front, "3 · PRESS", nil, C.WHITE)
	-- A mat at every station spot (where to stand), and the stack of empty pallets by the press.
	for _, v in ipairs(st) do
		box(m, "StationMat", f, v.X - 1.4, v.X + 1.4, 0.35, 0.38, v.Z - 1.2, v.Z + 1.2, C.SAFETY, Enum.Material.Fabric, DETAIL)
	end

	-- THE FORECOURT ---------------------------------------------------------------------------------------------
	local bay = L.Bay
	Build.bayLines(m, f, bay.X, bay.Z, 11, 18, "LOADING")
	for _, x in ipairs({ -4.2, 10.6 }) do
		post(m, "Bollard", f, x, -2.7, 0.2, 3, 0.8, C.SAFETY, metal)
	end
	-- The cash cart beside the roll-up door (looks only: never in a car's way).
	local ld = L.Load
	box(m, "CartBed", f, ld.X - 1.4, ld.X + 1.4, 1, 1.3, ld.Z - 1, ld.Z + 1, C.STEEL, plate, DETAIL)
	box(m, "CartHandle", f, ld.X - 1.4, ld.X + 1.4, 1.3, 3.2, ld.Z + 0.9, ld.Z + 1.05, C.DARK_METAL, metal, DETAIL)
	for _, dx in ipairs({ -1.1, 1.1 }) do
		for _, dz in ipairs({ -0.7, 0.7 }) do
			local w = Build.part(m, "CartWheel", Vector3.new(0.3, 0.8, 0.8), f * CFrame.new(ld.X + dx, 0.6, ld.Z + dz), C.DARK, smooth, DETAIL)
			w.Shape = Enum.PartType.Cylinder
		end
	end
	for i, dx in ipairs({ -0.8, 0.1, 0.9 }) do
		box(m, "Bag", f, ld.X + dx - 0.45, ld.X + dx + 0.45, 1.3, 2.2 + (i % 2) * 0.3, ld.Z - 0.6, ld.Z + 0.5,
			Color3.fromRGB(46, 70, 52), Enum.Material.Fabric, DETAIL)
	end
	local cartSign = box(m, "CartSign", f, ld.X - 1.2, ld.X + 1.2, 3.3, 4.1, ld.Z + 0.95, ld.Z + 1.02, C.DARK, smooth, DETAIL)
	Build.signGui(cartSign, front, "LOAD HERE", nil, C.SAFETY)
	-- Oil stains, a dumpster, a stack of pallets, a chain-link fence round the side yard.
	for _, o in ipairs({ { 2, -12, 2.4 }, { 7, -17, 1.8 }, { -16, -10, 2 }, { 20, -6, 1.6 } }) do
		local stain = Build.part(m, "OilStain", Vector3.new(0.05, o[3] * 2, o[3] * 2.6), f * CFrame.new(o[1], 0.22, o[2]) * CFrame.Angles(0, 0, math.rad(90)),
			K.OIL, smooth, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 0.35 })
		stain.Shape = Enum.PartType.Cylinder
	end
	box(m, "Dumpster", f, 19, 24, 0.2, 4.2, 15, 19.5, Color3.fromRGB(52, 74, 92), metal)
	box(m, "DumpsterLid", f, 18.9, 24.1, 4.2, 4.5, 14.9, 19.6, C.DARK_METAL, metal, DETAIL)
	pallet(A, m, f, 19, 23.5, 4, 8, true)
	for i = 0, 3 do
		box(m, "PalletStack", f, 19, 23.5, 0.85 + i * 0.6, 1.4 + i * 0.6, 4, 8, K.WOOD, Enum.Material.WoodPlanks)
	end
	for _, d in ipairs({ { 27.6, 28, -8, 25 }, { 16, 28, 24.6, 25 } }) do
		box(m, "Fence", f, d[1], d[2], 0.2, 7, d[3], d[4], Color3.fromRGB(150, 154, 150), Enum.Material.Metal,
			{ Transparency = 0.55, CastShadow = false })
		box(m, "FenceRail", f, d[1] - 0.05, d[2] + 0.05, 7, 7.25, d[3], d[4], C.DARK_METAL, metal, DETAIL)
	end
	for z = -8, 24, 8 do
		post(m, "FencePost", f, 27.8, z, 0.2, 7.3, 0.35, C.DARK_METAL, metal, DETAIL)
	end
	for _, o in ipairs({ { 25.5, 11 }, { 25.2, 12.6 } }) do
		post(m, "OilDrum", f, o[1], o[2], 0.2, 3, 1.5, K.RUST, Enum.Material.CorrodedMetal)
	end

	-- LEVELS 1-3: the old wooden shop door (open, against the office wall); 4+: the armored door ------------------
	local wood = group(m, "WoodDoor1", 1, 3)
	box(wood, "DoorLeaf", f, -21.1, -20.9, 0.35, 8.2, -1, 2.8, Color3.fromRGB(104, 72, 48), Enum.Material.Wood, DETAIL)
	local armor = group(m, "ArmoredDoor4", 4, nil)
	box(armor, "SteelFrame", f, -21.5, -21, 0.35, 8.8, -2.4, -1.9, C.DARK_METAL, plate, DETAIL)
	box(armor, "SteelFrame", f, -17, -16.5, 0.35, 8.8, -2.4, -1.9, C.DARK_METAL, plate, DETAIL)
	box(armor, "SteelFrame", f, -21.5, -16.5, 8.4, 8.9, -2.4, -1.9, C.DARK_METAL, plate, DETAIL)
	box(armor, "SteelLeaf", f, -21.2, -20.8, 0.35, 8.2, -1, 3, C.STEEL, plate, DETAIL)
	for y = 1.2, 7.4, 1.55 do
		for _, z in ipairs({ -0.5, 2.5 }) do
			box(armor, "Rivet", f, -20.8, -20.65, y, y + 0.2, z, z + 0.2, C.DARK_METAL, metal, DETAIL)
		end
	end

	-- LEVEL 2: a second press (x 9..14.5) and the paper store (shelves of reams along the left wall) -------------
	local two = group(m, "Press2", 2, nil)
	box(two, "PressBase", f, 9, 14.5, 0.35, 1.8, 13, 18, C.DARK_METAL, metal)
	box(two, "PressBody", f, 9.4, 14.1, 1.8, 5.2, 13.4, 17.6, Color3.fromRGB(110, 112, 104), metal)
	local r2 = Build.part(two, "Roller", Vector3.new(4.8, 0.6, 0.6), f * CFrame.new(11.75, 5.5, 15.5), C.STEEL, metal)
	r2.Shape = Enum.PartType.Cylinder
	box(two, "OutTray", f, 10, 13.5, 2.8, 3, 12.2, 13.4, C.STEEL, metal)
	box(two, "Sheets", f, 10.4, 13.1, 3, 3.2, 12.4, 13.2, K.PAPER, smooth)
	for y = 1.5, 7.5, 2 do
		box(two, "Shelf", f, -25, -23, y, y + 0.2, 7.4, 13.4, C.DARK_METAL, metal)
		for z = 7.7, 12.4, 1.6 do
			box(two, "Reams", f, -24.8, -23.2, y + 0.2, y + 1.4, z, z + 1.3, K.PAPER, smooth)
		end
	end
	local storeSign = box(two, "StoreSign", f, -24.9, -24.8, 9.6, 10.8, 8, 12.8, C.DARK, smooth)
	Build.signGui(storeSign, Enum.NormalId.Right, "PAPER STORE", nil, C.WHITE)

	-- LEVEL 3: drying racks (bills hung on lines over the workshop) and the hidden back door ----------------------
	local three = group(m, "Drying3", 3, nil)
	for _, z in ipairs({ 8.2, 9.7, 11.2 }) do
		box(three, "DryLine", f, -22, 12, 10.2, 10.3, z - 0.05, z + 0.05, C.DARK_METAL, metal)
		for x = -21, 11, 3.6 do
			box(three, "DryingBill", f, x, x + 1.4, 9.4, 10.2, z - 0.03, z + 0.03, K.BILL, smooth)
		end
	end
	for _, x in ipairs({ -22.4, 12.2 }) do
		box(three, "RackPost", f, x, x + 0.3, 0.35, 10.6, 7.9, 11.5, C.DARK_METAL, metal)
	end
	box(three, "HiddenDoor", f, 10, 13.6, 0.35, 8.4, 20.3, 20.9, Color3.fromRGB(96, 74, 54), Enum.Material.WoodPlanks)
	for y = 1.6, 7, 1.8 do
		box(three, "DoorShelf", f, 10, 13.6, y, y + 0.15, 19.7, 20.3, Color3.fromRGB(96, 74, 54), Enum.Material.WoodPlanks)
	end
	box(three, "DoorGap", f, 13.6, 13.9, 0.35, 8.4, 20.4, 21, Color3.fromRGB(8, 8, 10), smooth)
	box(three, "BackDoor", f, 10, 13.6, 0.2, 8.4, 22, 22.15, Color3.fromRGB(60, 62, 66), plate)

	-- LEVEL 4: the counting room (a steel cage, x -11..-2, z 0..6) ---------------------------------------------
	local four = group(m, "Counting4", 4, nil)
	for _, c in ipairs({ { -11, 0 }, { -2, 0 }, { -11, 6 }, { -2, 6 } }) do
		box(four, "CagePost", f, c[1] - 0.15, c[1] + 0.15, 0.35, 9, c[2] - 0.15, c[2] + 0.15, C.DARK_METAL, metal)
	end
	for _, y in ipairs({ 3, 9 }) do
		box(four, "CageRail", f, -11, -2, y - 0.1, y + 0.1, -0.1, 0.1, C.DARK_METAL, metal)
		box(four, "CageRail", f, -11, -2, y - 0.1, y + 0.1, 5.9, 6.1, C.DARK_METAL, metal)
		box(four, "CageRail", f, -11.1, -10.9, y - 0.1, y + 0.1, 0, 6, C.DARK_METAL, metal)
		box(four, "CageRail", f, -2.1, -1.9, y - 0.1, y + 0.1, 0, 6, C.DARK_METAL, metal)
	end
	box(four, "CageMesh", f, -11, -2, 0.35, 9, -0.05, 0.05, C.STEEL, metal, { Transparency = 0.7, CastShadow = false })
	box(four, "CountTable", f, -9, -4, 2.8, 3.1, 2, 4, K.WOOD, Enum.Material.WoodPlanks)
	bundles(A, four, f, -8.7, 2.6, 3.1, 5)
	bundles(A, four, f, -8.7, 3.4, 3.1, 4)
	box(four, "MoneyCounter", f, -5.6, -4.3, 3.1, 4, 2.4, 3.6, C.DARK, smooth)
	box(four, "Safe", f, -10.8, -9, 0.35, 3.6, 4.4, 5.8, C.DARK_METAL, plate)
	post(four, "SafeDial", f, -9.9, 4.36, 2, 0.1, 0.6, C.STEEL, metal)
	local cs = box(four, "CountSign", f, -9, -4, 9.2, 10.2, -0.2, -0.12, C.DARK, smooth)
	Build.signGui(cs, front, "COUNTING ROOM", "STAFF ONLY", C.SAFETY, C.WHITE)

	-- LEVEL 5: the full counterfeit floor --------------------------------------------------------------------
	local five = group(m, "Floor5", 5, nil)
	box(five, "BigPressBase", f, 9.5, 14.5, 0.35, 1.6, 1, 7, C.DARK_METAL, metal)
	box(five, "BigPress", f, 9.8, 14.2, 1.6, 7.5, 1.4, 6.6, Color3.fromRGB(226, 232, 230), smooth)
	box(five, "BigPressStripe", f, 9.75, 14.25, 5.4, 5.8, 1.35, 6.65, Color3.fromRGB(40, 150, 140), smooth)
	box(five, "BigPressScreen", f, 9.7, 9.8, 4, 5.2, 2.5, 4, Color3.fromRGB(80, 220, 160), Enum.Material.Neon)
	for _, z in ipairs({ 8.4, 10.2 }) do
		box(five, "CashPallet", f, 10, 14.4, 0.35, 0.8, z, z + 1.6, K.WOOD, Enum.Material.WoodPlanks)
		box(five, "CashBlock", f, 10.2, 14.2, 0.8, 3, z + 0.1, z + 1.5, K.BILL, smooth)
		box(five, "Wrap", f, 10.1, 14.3, 0.8, 3.1, z + 0.05, z + 1.55, K.WRAP, Enum.Material.Glass, { Transparency = 0.6 })
	end
	box(five, "Cutter", f, -11, -7.5, 0.35, 3.2, 7.6, 9.8, C.DARK_METAL, metal)
	box(five, "CutterBlade", f, -10.8, -7.7, 3.2, 3.6, 8.5, 8.7, C.STEEL, metal)
	bundles(A, five, f, -10.6, 9.2, 3.2, 3)
	Build.roomLight(five, f, -16, 8, H - 0.4, 6.5, 7.5, K.UV, 30)
	Build.roomLight(five, f, -16, 8, H - 0.4, 12.5, 13.5, K.UV, 26)
	local fs = box(five, "FloorSign", f, 9.8, 14.2, 7.8, 9, 1.3, 1.4, C.DARK, smooth)
	Build.signGui(fs, front, "MINT", "NO PHONES", Color3.fromRGB(80, 220, 160), C.WHITE)

	return plateGui:FindFirstChild("Title")
end

------------------------------------------------------------------ the shift: messages

local function ownerEntry(job)
	local A = S.A
	return A.owned(job.owner, job.id)
end

local function levelOf(job)
	return S.A.levelOf(job.owner, job.def)
end

-- The shop stage's HUD (start, resend, after a run).
local function sendShop(player, job, back)
	local A = S.A
	local entry = ownerEntry(job)
	local level = levelOf(job)
	A.fire(player, "Print", {
		Id = job.id, Stage = "shop", Mode = job.kind, Station = job.station, Streak = job.streak,
		Mult = Businesses.StreakMult(job.streak), Level = level, Owner = job.owner.UserId, OwnerName = job.owner.DisplayName,
		Count = job.count, Earned = job.earned, Dirty = entry and math.floor(entry.dirty or 0) or 0, Stock = Businesses.Stock(level),
		Carry = Businesses.Carry(level), Back = back == true, Stations = PR.Stations,
	})
end

local function sendRun(player, job)
	S.A.fire(player, "Loaded", {
		Id = job.id, Bags = job.bags, Pos = job.drop, Name = job.dropName, Dirty = job.dirtyLeft or 0, Grace = LA.LeaveGrace,
		Count = job.count, Earned = job.earned, Resend = true,
	})
end

------------------------------------------------------------------ the shift: start, switch, holds

function PrintShop.Start(player, job, _A)
	job.stage = "shop"
	job.station = 1
	job.streak, job.best, job.runPerfects = 0, 0, 0
	job.prints, job.perfects, job.runs, job.cleanRuns, job.dirtyMade = 0, 0, 0, 0, 0
	job.bags = 0
	job.idleSince = os.clock()
	sendShop(player, job, false)
	Telemetry.Custom(player, "BizPrintShift_" .. job.id, 1)
end

function PrintShop.Resend(player, job, _A)
	if job.stage == "drive" then
		sendRun(player, job)
	else
		sendShop(player, job, false)
	end
end

-- START JOB with the other kind during the shift: PRINT <-> LAUNDER (only what the HUD suggests changes).
function PrintShop.Switch(player, job, kind, A)
	if job.stage == "drive" then
		if kind == "Print" then
			A.refuse(player, job.id, "BagsAway") -- (deliver the bags first)
		end
		sendRun(player, job)
		return
	end
	job.kind = kind
	sendShop(player, job, false)
end

-- Your own land car standing still in the loading bay, or nil.
local function carInBay(player, def, A)
	local vs = A.service("VehicleService")
	local car = vs and type(vs.GetCar) == "function" and vs.GetCar(player) or nil
	local chassis = car and car.Parent and car.PrimaryPart
	if not chassis or car:GetAttribute("OwnerUserId") ~= player.UserId or car:GetAttribute("Boat") == true then
		return nil
	end
	local bay = Businesses.At(def, def.Layout.Bay)
	if flat(chassis.Position - bay).Magnitude > LA.BayRange or chassis.AssemblyLinearVelocity.Magnitude > LA.BaySpeed then
		return nil
	end
	return car
end

-- A drop point for a run (a kerb spot DistMin-DistMax from the shop), or nil.
local function dropPoint(def, A)
	local js = A.service("JobService")
	local roadside = js and js.RoadsideSpot
	if type(roadside) ~= "function" then
		return nil
	end
	return roadside(def.Position, LA.DistMin, LA.DistMax)
end

-- LOAD held long enough at the cart: the bags into the car, the drop point, the run begins.
local function load(player, job, A)
	local def = job.def
	local entry = ownerEntry(job)
	local stock = entry and math.floor(entry.dirty or 0) or 0
	if stock < 1 then
		A.refuse(player, job.id, "NoStock")
		return
	end
	local car = carInBay(player, def, A)
	if not car then
		A.refuse(player, job.id, "NotInBay")
		return
	end
	local drop = dropPoint(def, A)
	if not drop then
		A.refuse(player, job.id, "NoAddress")
		return
	end
	local level = levelOf(job)
	local bags = math.min(stock, Businesses.Carry(level))
	entry.dirty = math.max(0, (entry.dirty or 0) - bags)
	job.bags = bags
	job.dirtyLeft = math.floor(entry.dirty)
	job.runCar = car -- (never job.car: BusinessService destroys a job's car when the job ends, and this one is yours)
	job.stage = "drive"
	job.drop = drop
	job.dropName = K.DROPS[A.rng:NextInteger(1, #K.DROPS)]
	job.from = car.PrimaryPart.Position
	job.top = topSpeed(car)
	job.loadedAt = os.clock()
	job.outSince = os.clock() -- (you're on foot by the cart: LeaveGrace to get in)
	job.heat, job.clean, job.spottedHow = 0, true, nil
	job.nextRoll = os.clock() + A.rng:NextNumber(LA.SpotEvery[1], LA.SpotEvery[2])
	job.losAt, job.losSeen = 0, true
	A.setJobKind(player, job, "BizLaunder")
	setHeat(player, 0)
	A.fire(player, "Loaded", {
		Id = job.id, Bags = bags, Pos = drop, Name = job.dropName, Dirty = job.dirtyLeft, Grace = LA.LeaveGrace,
		Count = job.count, Earned = job.earned,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
	A.pushState(player)
	Telemetry.Custom(player, "BizLaunderLoad_" .. job.id, bags)
end

-- A station's hold that counted (OK or PERFECT): on to the next, or the press run after the third.
local function stationDone(player, job, grade, A)
	local perfect = grade == "Perfect"
	if perfect then
		job.streak += 1
		job.runPerfects += 1
		job.perfects += 1
		job.best = math.max(job.best, job.streak)
	else
		job.streak = 0
	end
	job.idleSince = os.clock()
	if job.station < #PR.Stations then
		job.station += 1
		A.fire(player, "PrintStep", { Grade = grade, Station = job.station, Streak = job.streak, Mult = Businesses.StreakMult(job.streak) })
		return
	end
	-- The press run.
	local def = job.def
	local level = levelOf(job)
	local entry = ownerEntry(job)
	local batch = Businesses.PrintBatch(def, level, job.runPerfects, job.streak)
	local added = 0
	if entry then
		entry.dirty, added = Businesses.AddDirty(entry.dirty or 0, batch, Businesses.Stock(level))
	end
	local perfects = job.runPerfects
	job.runPerfects = 0
	job.station = 1
	job.prints += 1
	job.count += 1
	job.dirtyMade += added
	A.creditOwner(job, player, 0) -- (the owner's jobsDone; dirty cash isn't earnings until it's laundered)
	A.addEmpireXP(player, E.XP.Print)
	A.progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizPrint_" .. job.id, added)
	A.fire(player, "Printed", {
		Grade = grade, Amount = added, Batch = batch, Perfects = perfects, Streak = job.streak, Mult = Businesses.StreakMult(job.streak),
		Dirty = entry and math.floor(entry.dirty) or 0, Stock = Businesses.Stock(level), Full = added < batch, Count = job.count,
		Station = 1,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
end

-- RequestBusiness("Step", "HoldOn" | "HoldOff"): a station's hold or LOAD, timed here (see the header).
function PrintShop.Step(player, job, step, A)
	if job.stage ~= "shop" then
		return
	end
	local def = job.def
	local now = os.clock()
	if step == "HoldOn" then
		if onFootAt(player, def, def.Layout.Load, LA.LoadRange) then
			local entry = ownerEntry(job)
			if not entry or (entry.dirty or 0) < 1 then
				A.refuse(player, job.id, "NoStock")
				A.fire(player, "PrintStep", { Again = true, Load = true, Station = job.station })
				return
			end
			if not carInBay(player, def, A) then
				A.refuse(player, job.id, "NotInBay")
				A.fire(player, "PrintStep", { Again = true, Load = true, Station = job.station })
				return
			end
			job.hold = { kind = "load", at = now }
			return
		end
		if not onFootAt(player, def, def.Layout.Stations[job.station], PR.Range) then
			job.hold = nil
			A.fire(player, "PrintStep", { Again = true, Far = true, Station = job.station })
			return
		end
		if job.station == 1 then
			local entry = ownerEntry(job)
			if entry and (entry.dirty or 0) >= Businesses.Stock(levelOf(job)) then
				A.refuse(player, job.id, "StockFull")
				A.fire(player, "PrintStep", { Again = true, Full = true, Station = job.station })
				return
			end
		end
		job.hold = { kind = "station", at = now, station = job.station }
	elseif step == "HoldOff" then
		local h = job.hold
		job.hold = nil
		if not h then
			return
		end
		local held = now - h.at
		if h.kind == "load" then
			if held < LA.LoadHold - RA.HoldSlack or not onFootAt(player, def, def.Layout.Load, LA.LoadRange) then
				A.fire(player, "PrintStep", { Again = true, Load = true, Station = job.station })
				return
			end
			job.idleSince = now
			load(player, job, A)
			return
		end
		if h.station ~= job.station or not onFootAt(player, def, def.Layout.Stations[job.station], PR.Range) then
			A.fire(player, "PrintStep", { Again = true, Far = true, Station = job.station })
			return
		end
		local grade = Businesses.PrintGrade(job.station, held)
		if grade == "Early" then
			job.streak = 0
			A.fire(player, "PrintStep", { Again = true, Early = true, Station = job.station, Streak = 0, Mult = 1 })
			return
		end
		stationDone(player, job, grade, A)
	end
end

------------------------------------------------------------------ the shift: the run

-- The nearest police to `pos` within HeatRange: distance and the part / position to look from (or nil).
local function nearestPolice(pos, player)
	local best, bestPos = LA.HeatRange, nil
	local function consider(p)
		local d = (p - pos).Magnitude
		if d < best then
			best, bestPos = d, p
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and (p:GetAttribute("Side") == "Cop" or studioCop(p)) then
			local root = rootOf(p)
			if root then
				consider(root.Position)
			end
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
		local chassis = car:GetAttribute("AIPolice") and car.PrimaryPart
		if chassis then
			consider(chassis.Position)
		end
	end
	local npcs = Workspace:FindFirstChild("NPCs")
	for _, m in ipairs(npcs and npcs:GetChildren() or {}) do
		local r = m:GetAttribute("NPCKind") == "Officer" and m:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			consider(r.Position)
		end
	end
	for _, at in ipairs(S.hq) do
		consider(at)
	end
	if not bestPos then
		return nil, nil
	end
	return best, bestPos
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

-- A clear line from the police at `from` to the car?
local function lineClear(from, car)
	local exclude = { car }
	for _, n in ipairs({ "Vehicles", "NPCs", "BizRaid" }) do
		local f = Workspace:FindFirstChild(n)
		if f then
			table.insert(exclude, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	losParams.FilterDescendantsInstances = exclude
	local to = car.PrimaryPart.Position + Vector3.new(0, 2, 0)
	local start = from + Vector3.new(0, 3, 0)
	return Workspace:Raycast(start, to - start, losParams) == nil
end

-- SPOTTED: the stars, and the run goes on (no longer clean).
local function spotted(player, job, stars, how, A)
	job.clean = false
	job.heat = 1
	job.spottedHow = how
	setHeat(player, 1)
	local hs = A.service("HeatService")
	if hs and type(hs.Add) == "function" then
		hs.Add(player, stars, "launder")
	end
	A.fire(player, "Spotted", { Stars = stars, How = how })
	Telemetry.Custom(player, "BizLaunderSpotted_" .. how, stars)
end

-- Stopped in the drop ring: the speed check, then the pay (see the header).
local function deliver(player, job, car, t, A)
	local took = t - job.loadedAt
	local gap = math.max(0, flat(job.drop - job.from).Magnitude - LA.StopRadius)
	local fastest = gap / (math.max(job.top or 0, topSpeed(car)) * LA.FastSlack)
	local guard = A.service("VehicleGuard")
	if took < fastest or (guard and type(guard.RecentlyFlagged) == "function" and guard.RecentlyFlagged(player, took)) then
		warn(string.format("[PrintShop] refused %s's launder run: %.2fs (at least %.2fs)", player.Name, took, fastest))
		A.endJob(player, "Invalid")
		return
	end
	local clean = job.clean and (player:GetAttribute("Heat") or 0) <= 0
	local bags = job.bags
	local pay, bonus = Businesses.LaunderPay(bags, clean)
	local total = pay + bonus
	job.bags = 0
	EconomyService.AddCash(player, total, "bizjob:" .. job.id .. ":launder")
	job.count += 1
	job.runs += 1
	job.cleanRuns += clean and 1 or 0
	job.earned += total
	A.creditOwner(job, player, total)
	A.addEmpireXP(player, E.XP.Launder)
	A.progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizLaunder_" .. job.id, total)
	A.fire(player, "Laundered", {
		Pay = pay, Bonus = bonus, Clean = clean, Bags = bags, Count = job.count, Earned = job.earned, Runs = job.runs, Took = took,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
	-- Back to the shop for the next load.
	job.stage = "shop"
	job.runCar = nil
	job.drop = nil
	job.idleSince = os.clock()
	setHeat(player, nil)
	A.setJobKind(player, job, "BizPrint")
	sendShop(player, job, true)
end

local function runTick(player, job, t, A)
	local car = job.runCar
	local chassis = car and car.Parent and car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
		A.endJob(player, "BagsCar")
		return
	end
	if chassis.Position.Y < 0.2 then
		job.sunkSince = job.sunkSince or t
		if t - job.sunkSince >= 2 then
			A.endJob(player, "BagsCar")
		end
		return
	end
	job.sunkSince = nil
	local wanted = (player:GetAttribute("Heat") or 0) > 0
	if wanted then
		job.clean = false
	end
	local seat = car:FindFirstChild("DriverSeat")
	local _, hum = rootOf(player)
	if not (seat and hum and seat.Occupant == hum) then
		job.outSince = job.outSince or t
		if t - job.outSince > LA.LeaveGrace then
			A.endJob(player, "BagsLeft")
		end
		return
	end
	job.outSince = nil
	local dt = math.clamp(t - (job.lastTick or t), 0, 1)
	job.lastTick = t
	job.top = math.max(job.top or 0, topSpeed(car))
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	if not wanted then
		-- THE HEAT METER: the nearest police in range (a ray for the line now and then).
		local dist, from = nearestPolice(chassis.Position, player)
		if from and t - (job.losAt or 0) >= K.CHECK_CAR then
			job.losAt = t
			job.losSeen = lineClear(from, car)
		end
		job.heat = Businesses.HeatStep(job.heat or 0, dt, dist, from ~= nil and job.losSeen)
		setHeat(player, job.heat)
		if job.heat >= 1 then
			spotted(player, job, (dist and dist <= LA.PatrolNear) and LA.PatrolStars or LA.Stars, "Meter", A)
			return
		end
		-- A tip-off now and then while on the move.
		if speed >= LA.MinSpeed and t >= (job.nextRoll or t) then
			job.nextRoll = t + A.rng:NextNumber(LA.SpotEvery[1], LA.SpotEvery[2])
			if A.rng:NextNumber() < Businesses.SpotChance(levelOf(job)) then
				spotted(player, job, LA.Stars, "Tip", A)
				return
			end
		end
	end
	-- Arrived: stopped inside the ring.
	if flat(chassis.Position - job.drop).Magnitude < LA.StopRadius and speed < LA.StopSpeed then
		deliver(player, job, car, t, A)
	end
end

-- Four times a second (BusinessService's jobsTick, after its own end rules).
function PrintShop.Tick(player, job, t, A)
	if job.stage == "drive" then
		runTick(player, job, t, A)
		return
	end
	if t - (job.idleSince or t) > PR.IdleTime then
		A.endJob(player, "Idle")
	end
end

-- A launder run with the bags in the car goes on while you're wanted (that's its risk).
function PrintShop.KeepWanted(job)
	return job.stage == "drive" and (job.bags or 0) > 0
end

-- The shift ends (any reason): the bags, and the summary for BusinessJob "Ended".
function PrintShop.End(player, job, reason, A)
	local bags = job.bags or 0
	job.bags = 0
	if bags > 0 then
		local entry = ownerEntry(job)
		local atShop = player.Parent == Players and A.atLot(player, job.def) and (player:GetAttribute("Heat") or 0) <= 0
		if reason == "Player" and atShop and entry then
			entry.dirty = (entry.dirty or 0) + bags -- (END JOB at the shop: unloaded again)
			A.fire(player, "BagsBack", { Amount = bags, Dirty = math.floor(entry.dirty) })
			if job.owner ~= player then
				A.pushState(job.owner)
			end
		else
			local why = reason
			if reason == "Side" and player:GetAttribute("Side") == "Prisoner" then
				why = "Arrested"
			end
			A.fire(player, "BagsLost", { Amount = bags, Why = why })
			Telemetry.Custom(player, "BizBagsLost_" .. tostring(why), bags)
		end
	end
	setHeat(player, nil)
	job.runCar = nil
	return {
		Summary = {
			Prints = job.prints or 0, Perfects = job.perfects or 0, Best = job.best or 0,
			BestMult = Businesses.StreakMult(job.best or 0), Runs = job.runs or 0, CleanRuns = job.cleanRuns or 0,
			Dirty = job.dirtyMade or 0,
		},
	}
end

------------------------------------------------------------------ raids (the shared engine: BusinessJobs.Raids)

-- This shop's raid spec (Raids.Register): its stock and cap, the armored door's breach, the presses as the search
-- spot and the officers' way in through the office. Everything else is the shared M3 raid code.
local function raidSpec()
	return {
		cap = function(level)
			return Businesses.Stock(level)
		end,
		minDirty = RA.MinDirty,
		breachHold = function(level)
			return Businesses.BreachHold(level)
		end,
		pathIn = K.PATH_IN,
		words = {
			place = "Backlot Print Shop", stuff = "in fake bills", searchObject = "The presses", inSay = "We're in! Search the presses!",
			heldSay = "Step away from the presses!",
		},
	}
end

------------------------------------------------------------------ hooks BusinessService calls

function PrintShop.Init(A)
	S.A = A
	-- The heat meter's fixed police: the cop spawn and the HQ building, if the place has them.
	local spawns = Workspace:FindFirstChild("Spawns")
	local cop = spawns and spawns:FindFirstChild("CopSpawn")
	if cop and cop:IsA("BasePart") then
		table.insert(S.hq, cop.Position)
	end
	local city = Workspace:FindFirstChild("City")
	local marks = city and city:FindFirstChild("Landmarks")
	local hq = marks and marks:FindFirstChild("PoliceHQ")
	if hq and hq:IsA("BasePart") then
		table.insert(S.hq, Vector3.new(hq.Position.X, 0, hq.Position.Z))
	end
	Raids.Init(A)
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and def.Style == "PrintShop" then
			Raids.Register(def.Id, raidSpec())
		end
	end
end

-- Once a second: the warrant rolls, and the raid on (the shared raid engine, for each print shop).
function PrintShop.Second(dt, A)
	S.A = A
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and def.Style == "PrintShop" then
			Raids.Second(def.Id, dt, A)
		end
	end
end

-- This business's extra numbers in BusinessState (the card, the EMPIRE app).
function PrintShop.State(player, def, entry)
	local level = entry.level
	return { Dirty = math.floor(entry.dirty or 0), Stock = Businesses.Stock(level), Carry = Businesses.Carry(level), Raid = Raids.State(player, def.Id) }
end

-- The raids this player is part of (their BizAlarm: the map flashes).
function PrintShop.Alarms(player)
	local ids = {}
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and def.Style == "PrintShop" then
			for _, id in ipairs(Raids.Alarms(player, def.Id)) do
				table.insert(ids, id)
			end
		end
	end
	return ids
end

function PrintShop.PlayerLeft(player, _A)
	for _, def in ipairs(Businesses.List) do
		if def.Style == "PrintShop" and Raids.Registered(def.Id) then
			Raids.PlayerLeft(player, def.Id)
		end
	end
end

-- Studio helpers (see the header). nil = not one of ours.
function PrintShop.Debug(player, cmd, id, value, A)
	S.A = A
	local def = Businesses.ById[(id ~= nil and id ~= "") and id or K.ONE_BUILDING]
	if cmd == "testcop" then
		local name = type(value) == "string" and value ~= "" and value or nil
		Workspace:SetAttribute("BizTestCop", name)
		return "BizTestCop = " .. tostring(name)
	elseif cmd == "dirty" or cmd == "raid" or cmd == "endraid" or cmd == "heat" then
		if def and def.Style ~= "PrintShop" and (cmd == "raid" or cmd == "endraid") and Raids.Registered(def.Id) then
			return nil -- (another building's raid: the Nightclub's back room answers it)
		end
		if not def or def.Style ~= "PrintShop" then
			return "not a print shop: " .. tostring(id)
		end
	else
		return nil
	end
	if cmd == "heat" then
		local job = A.jobOf(player)
		if not job or job.mod ~= PrintShop or job.stage ~= "drive" then
			return "not on a launder run"
		end
		job.heat = math.clamp(tonumber(value) or 0.9, 0, 1)
		setHeat(player, job.heat)
		return "heat " .. job.heat
	end
	local entry = A.owned(player, def.Id)
	if not entry then
		return "doesn't own " .. def.Id .. " (give it first)"
	end
	if cmd == "dirty" then
		entry.dirty = math.max(0, math.floor(tonumber(value) or Businesses.Stock(entry.level)))
		A.pushState(player)
		return "dirty " .. entry.dirty .. " / " .. Businesses.Stock(entry.level)
	end
	-- "raid" / "endraid": the shared raid engine.
	return Raids.Debug(player, cmd, def.Id, value, A)
end

return PrintShop
