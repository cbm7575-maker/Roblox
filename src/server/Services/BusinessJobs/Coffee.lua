-- Coffee (ModuleScript, ServerScriptService.Services.BusinessJobs.Coffee)
-- Palm Grind Coffee, Empire's second business (M2 of launch/10-BUSINESSES-PRD.md v2; every number in
-- Config.Businesses: the PalmGrind entry, Rush and ColdBrew). This module is BusinessService's "job module" for
-- the café: it draws the building and runs its job, RUSH ORDERS. Everything else (owning it, its register and
-- levels, the featured-owner sign, the cold brew, break-ins, crew cuts, Empire XP, saving, the remotes) is
-- BusinessService's, which calls in here with its own helpers (Api: see JOB MODULES in its header). Nothing
-- here runs unless BusinessService does (the launch switch, Config.Businesses.Live).
--
-- THE BUILDING (Coffee.Style; Look 3.0: real materials, one accent colour per place (the config's palm green),
-- neon only after dark via tag "NightNeon", lamps "NightLamp"). Lot space as every business lot: origin at the
-- lot centre, -Z toward the street (Marina Link, to the west), +X to the right looking at the street.
--   * The café (x -17..10, z 2..14, 12 tall): cream stucco, a glass front with the door in the middle (x -2.5..
--     2.5, Layout.Door), a side window on the right wall (the drive-through hatch from level 3). Inside: the
--     counter (front face z 9) with the register (Layout.Register: break-in robbers rummage here), ORDER HERE
--     on its left (Layout.Service: the cold brew prompt, BusinessService's BizServicePrompt) and the RUSH ORDERS
--     pick-up shelf on its right (Layout.Orders, a yellow mat on the floor: where a worker holds GRAB); the back
--     bar with the espresso machine, the menu board, two tables (level 1: "a counter and 2 tables").
--   * Outside: the owner plate on the front header (FOR SALE · $45,000, or the featured owner's name; the
--     client re-dresses it), a COLD BREW sign beside it, the roof sign PALM GRIND, an awning and a night lamp
--     over the door, a chalkboard, three parking bays on the forecourt (park here for the next order), a palm
--     at each right-hand corner, a dumpster in the back corner. Only the café's walls, glass, counters, the
--     roof sign, the planters and the dumpster are solid, and all of it stays inside the lot.
--   * LEVEL PROPS (PRD section 5; child Models with MinLevel / MaxLevel, drawn per device by BusinessClient,
--     never solid):
--       2  the terrace: wooden decks either side of the door path, three tables with umbrellas, planters
--       3  the drive-through: a loop painted round the café (in on the right, behind it, out on the left) with
--          arrows, DRIVE-THRU / EXIT words, the window's awning, ledge and sign, the menu board and speaker,
--          the DRIVE-THRU pole sign; and the neon: round the roof sign and along the roof's front edge
--       4  the roastery corner (a copper roaster with its hopper, cooling tray and chimney, burlap sacks, the
--          ROASTERY sign) and a queue of four customers outside the door (simple part figures: light on phones)
--       5  the rooftop café: glass balustrades with string lights, three tables with umbrellas, potted palms,
--          the stair house and a ROOFTOP CAFÉ sign
--   Returns the owner plate's title label (BusinessService's publishOwners writes FOR SALE / the owner).
--
-- RUSH ORDERS (Config.Businesses.Rush; JobKind "BizRush"). Started by BusinessService (START JOB > RUSH
-- ORDERS at the door: the owner, or a crewmate working for an owner in the server; the owner's level sets the
-- order sizes and the pay, the crewmate's pay gives the owner the 20% cut, as M1's jobs).
--   1. PICK-UP: BusinessJob "Rush" { Id, Stage = "pickup", Back (after an order), Level, Owner, OwnerName,
--      Count, Earned, Orders, Hold }. Walk to the RUSH ORDERS shelf and hold GRAB (BusinessClient's HOLD
--      button): RequestBusiness("Step", "GrabOn") then "GrabOff"; the server times it (GrabHold, less
--      HoldSlack) and wants the worker on foot within GrabRange of Layout.Orders both times, else "RushStep"
--      { Again = true, Far } and the hold starts over.
--   2. THE ORDER: Businesses.RushDrops(level) addresses in a row: the first FirstMin-FirstMax studs from the
--      café, the next NextMin-NextMax from the one before, each a kerb spot from JobService.RoadsideSpot. From
--      VIPLevel (or after Debug "vip") the last one may be a VIP order instead: the verge parking spot of one
--      of RU.VIPHomes (Config.Housing) between NextMin and VIPMax studs away. Every address gets its road length
--      (RoadGraph's route, never less than the straight line) and its clock (Businesses.RushTimer); the last
--      one also the road back to the café. A refusal when no address can be found ("NoAddress").
--   3. EACH ADDRESS: "RushLeg" { Id, Leg, Of, Pos, Name, Who (a VIP's name), Vip, Drink (what they ordered,
--      K.DRINKS: the strip's cup), Timer, Ends (server time), Level, First, Earned, Streak (GOLDs in a row so
--      far), Owner }. Drive there in your own car (the driver's seat of a car whose OwnerUserId is yours, not a
--      boat) and stop in the ring (StopRadius, under StopSpeed). Refused like a taxi fare (the job ends,
--      "Invalid", nothing paid) when the leg was done sooner than the straight line from where it began at the
--      fastest car you drove on it x FastSlack, or VehicleGuard flagged you meanwhile. Else paid:
--      Businesses.RushPay (the order's pay with the first address, the road back with the last, the tip by the
--      clock, x VIPMult for a VIP, the gold streak, +TipBoost in the owner's rush hour) and, after an order's
--      last stop, Businesses.PerfectRunBonus (2+ stops, all GOLD), reason "bizjob:<id>:rush", the worker's Empire
--      XP Rush, the owner's books (jobsDone, lifetime, crew cut), "RushPaid" { Pay, Tip, Bonus (the perfect run),
--      Medal ("Gold" | "Silver" | "Bronze": Businesses.RushMedal), Streak, Mult (the streak's), Broke (the streak
--      it ended, 2+), RushHour, Golds (this order's), Late, Vip, Who, Name, Drink, Pos, Leg, Of, Took, Last, Order
--      (this order so far), Count, Earned }. The next address's clock starts at once; after the last, back to 1.
--   4. ENDS (BusinessJob "Ended" from BusinessService): out of your car for CarGrace seconds after grabbing
--      ("NoCarYet") or LeaveGrace once you've driven off ("LeftOwnCar"); no order grabbed for IdleTime
--      ("Idle"); "Invalid"; and BusinessService's own rules (END JOB, wanted, side, died, the owner leaving,
--      another job taking JobKind). Coffee.End adds the shift's Report { Orders, Drops, Gold, Silver, Bronze,
--      PerfectRuns, Vips, Best (the best gold streak), RushDrops (stops made in a rush hour) }.
--
-- RUSH HOUR (Config.Businesses.Rush.RushHour; Coffee.Second, once a second): every owner of the café in the server
-- has a play clock (BusinessService's, x BusinessTimeScale in Studio). Gap seconds of play after their last rush
-- hour ended (the first: Gap into the session), their café gets a RUSH HOUR for Length (real) seconds: player
-- attribute BizRushHour = the server time it ends (the clients read it for the banner and the strip), and every
-- rush-order tip for that owner (theirs, or a crewmate's working for them) gets +TipBoost. BusinessResult
-- "RushHour" { Id, Until, Owner, OwnerName, Boost } to the owner and anyone working for them there, "RushHourOver"
-- at the end. Studio: Debug "rushhour" (value = seconds) starts one now at your café.
--
-- API (BusinessService calls these; A = its Api table):
--   Coffee.Style(model, frame, def, A) -> the plate's title TextLabel
--   Coffee.Start(player, job, A)          a new rush job (stage "pickup")
--   Coffee.Resend(player, job, A)         START JOB pressed again while on it: the HUD again
--   Coffee.Step(player, job, step, A)     "GrabOn" / "GrabOff"
--   Coffee.Tick(player, job, t, A)        four times a second (t = os.clock())
--   Coffee.End(player, job, reason, A)    the job's end: the shift Report
--   Coffee.Second(dt, A)                  once a second: the rush hours
--   Coffee.PlayerLeft(player, A)          forget their rush-hour clock
--   Coffee.Debug(player, cmd, id, value, A) "rushhour" (Studio)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local Coffee = {}

-- The job kinds this module runs, and the JobKind attribute for each (BusinessService's JOB MODULES).
Coffee.Kinds = { Rush = "BizRush" }

local RU = Businesses.Rush
local E = Businesses.Empire

-- Looks and words (balance lives in Config.Businesses).
local K = {
	H = 12, -- the café's height (the roof slab sits on it)
	WALL = Color3.fromRGB(244, 232, 214), -- cream stucco
	WOOD = Color3.fromRGB(122, 84, 58), -- the counters and tables
	FLOOR = Color3.fromRGB(150, 104, 70), -- the café's wooden floor
	DECK = Color3.fromRGB(170, 126, 88), -- the terrace decking
	COPPER = Color3.fromRGB(184, 115, 64), -- the roaster
	KRAFT = Color3.fromRGB(196, 160, 112), -- paper bags, burlap sacks
	CANVAS = Color3.fromRGB(250, 244, 230), -- cream umbrellas
	BIN = Color3.fromRGB(46, 92, 64), -- the dumpster
	CREAM = Color3.fromRGB(255, 228, 170), -- the roof sign's sub line
	-- The queue's customers (level 4): skin, shirt, shorts, hair.
	LOOKS = {
		{ Color3.fromRGB(234, 192, 150), Color3.fromRGB(255, 140, 120), Color3.fromRGB(60, 80, 120), Color3.fromRGB(60, 40, 30) },
		{ Color3.fromRGB(160, 110, 75), Color3.fromRGB(120, 200, 230), Color3.fromRGB(230, 220, 200), Color3.fromRGB(28, 24, 22) },
		{ Color3.fromRGB(255, 220, 185), Color3.fromRGB(250, 220, 90), Color3.fromRGB(70, 70, 76), Color3.fromRGB(200, 150, 80) },
		{ Color3.fromRGB(110, 75, 55), Color3.fromRGB(170, 120, 220), Color3.fromRGB(40, 110, 90), Color3.fromRGB(20, 18, 18) },
	},
	-- Rush-order customers (an address's name on the strip and in the toasts).
	CUSTOMERS = { "Coast FM studio", "Seaside Realty", "Dr. Patel", "the lifeguard tower", "Marina Yacht Club", "Ms. Okafor",
		"Solana Tattoo", "Coach Rivera", "the Sunshine Gym", "Mr. Delgado", "Glow-Up Nails", "Captain Shaw", "Aunt Rosa",
		"the film crew", "Professor Lane" },
	-- VIP orders' celebrities (made up: the strip's "VIP · STELLA STARR" and the VIP DELIVERED stamp).
	VIPS = { "Stella Starr", "DJ Marlo", "Rico Diamante", "Lexi Lux", "Captain Neon", "Ms. Vanderbilt", "Kai Sterling" },
	-- What each address ordered (the strip's cup: "PROFESSOR LANE · ICED LATTE"; 10 letters at most so it fits).
	DRINKS = { "Iced Latte", "Cold Brew", "Flat White", "Cortado", "Mocha", "Cafecito", "Cappuccino", "Oat Latte", "Espresso",
		"Matcha", "Cubano", "Chai Latte" },
}

local R = {
	next = {}, -- [owner] = play seconds of their next rush hour (cleared in Coffee.PlayerLeft)
	def = nil, -- the café's Config entry (its Style is "Coffee")
}

-- The café's Config entry.
local function cafe()
	if not R.def then
		for _, d in ipairs(Businesses.List) do
			if d.Style == "Coffee" then
				R.def = d
			end
		end
	end
	return R.def
end

------------------------------------------------------------------ the building (Look 3.0)

-- A blocky customer (legs, body, arms, head, hair; 7 parts) standing on (x, z), turned by yaw.
local function person(A, parent, f, x, z, yaw, look)
	local P, DETAIL = A.Build.part, A.DETAIL
	local base = f * CFrame.new(x, 0.2, z) * CFrame.Angles(0, yaw, 0)
	local skin, shirt, shorts, hair = look[1], look[2], look[3], look[4]
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "Leg", Vector3.new(0.95, 2, 1), base * CFrame.new(s * 0.5, 1, 0), shorts, Enum.Material.SmoothPlastic, DETAIL)
		P(parent, "Arm", Vector3.new(0.9, 2, 0.9), base * CFrame.new(s * 1.47, 3, 0), skin, Enum.Material.SmoothPlastic, DETAIL)
	end
	P(parent, "Body", Vector3.new(2, 2, 1), base * CFrame.new(0, 3, 0), shirt, Enum.Material.Fabric, DETAIL)
	P(parent, "Head", Vector3.new(1.15, 1.15, 1.15), base * CFrame.new(0, 4.6, 0), skin, Enum.Material.SmoothPlastic, DETAIL)
	P(parent, "Hair", Vector3.new(1.2, 0.35, 1.2), base * CFrame.new(0, 5.3, 0.04), hair, Enum.Material.SmoothPlastic, DETAIL)
end

-- A round café table with two stools, standing on y0; umbrella = its canopy colour (nil: none).
local function tableSet(A, parent, f, x, z, y0, stool, umbrella)
	local Build, C, DETAIL, SHADE = A.Build, A.C, A.DETAIL, A.SHADE
	Build.post(parent, "TableLeg", f, x, z, y0, 2.6, 0.35, C.DARK_METAL, Enum.Material.Metal, DETAIL)
	local top = Build.part(parent, "TableTop", Vector3.new(0.2, 3, 3), f * CFrame.new(x, y0 + 2.7, z) * CFrame.Angles(0, 0, math.rad(90)),
		K.WOOD, Enum.Material.WoodPlanks, DETAIL)
	top.Shape = Enum.PartType.Cylinder
	for _, dx in ipairs({ -2.1, 2.1 }) do
		Build.post(parent, "Stool", f, x + dx, z, y0, 1.7, 1.3, stool, Enum.Material.SmoothPlastic, DETAIL)
	end
	if umbrella then
		Build.post(parent, "UmbrellaPole", f, x, z, y0 + 2.8, 4.6, 0.22, C.WHITE, Enum.Material.Metal, DETAIL)
		local canopy = Build.part(parent, "Umbrella", Vector3.new(0.5, 7, 7), f * CFrame.new(x, y0 + 7.2, z) * CFrame.Angles(0, 0, math.rad(90)),
			umbrella, Enum.Material.Fabric, SHADE)
		canopy.Shape = Enum.PartType.Cylinder
		local cap = Build.part(parent, "UmbrellaTop", Vector3.new(0.5, 3.4, 3.4), f * CFrame.new(x, y0 + 7.65, z) * CFrame.Angles(0, 0, math.rad(90)),
			umbrella, Enum.Material.Fabric, DETAIL)
		cap.Shape = Enum.PartType.Cylinder
	end
end

-- Palm Grind (see the header). Returns the plate's title label.
function Coffee.Style(m, f, def, A)
	local Build, C, DETAIL, SHADE = A.Build, A.C, A.DETAIL, A.SHADE
	local box, post, neon, group = Build.box, Build.post, Build.neon, Build.group
	local accent, glow = def.Accent, def.Neon
	local H = K.H
	local L = def.Layout
	local front, rightFace, leftFace = Enum.NormalId.Front, Enum.NormalId.Right, Enum.NormalId.Left
	local plaster, planks, metal = Enum.Material.Plaster, Enum.Material.WoodPlanks, Enum.Material.Metal
	local smooth = Enum.Material.SmoothPlastic
	local CB = Businesses.ColdBrew

	-- THE CAFÉ (x -17..10, z 2..14) ----------------------------------------------------------------------------
	box(m, "CafeFloor", f, -17, 10, 0.2, 0.4, 2, 14, K.FLOOR, planks)
	box(m, "BackWall", f, -17, 10, 0.4, H, 13, 14, K.WALL, plaster)
	box(m, "SideWall", f, -17, -16, 0.4, H, 3, 13, K.WALL, plaster)
	-- The right wall with its side window (z 6..10): the drive-through hatch from level 3.
	box(m, "SideWall", f, 9, 10, 0.4, H, 3, 6, K.WALL, plaster)
	box(m, "SideWall", f, 9, 10, 0.4, H, 10, 13, K.WALL, plaster)
	box(m, "SideWall", f, 9, 10, 0.4, 3, 6, 10, K.WALL, plaster)
	box(m, "SideWall", f, 9, 10, 7.5, H, 6, 10, K.WALL, plaster)
	Build.glass(m, f, 9.3, 9.7, 3, 7.5, 6, 10)
	-- The glass front either side of the door (x -2.5..2.5) and the lintel over it.
	Build.shopfront(m, f, -17, -2.5, 2, 3, H, K.WALL, plaster, 2.4, 8.4)
	Build.shopfront(m, f, 2.5, 10, 2, 3, H, K.WALL, plaster, 2.4, 8.4)
	box(m, "Lintel", f, -2.5, 2.5, 9, H, 2, 3, K.WALL, plaster)
	for _, x in ipairs({ -2.8, 2.5 }) do
		box(m, "DoorFrame", f, x, x + 0.3, 0.4, 9, 1.9, 3.1, C.DARK_METAL, metal, DETAIL)
	end
	box(m, "Roof", f, -17.5, 10.5, H, H + 0.8, 1.5, 14.5, C.WHITE, Enum.Material.Concrete, { CastShadow = true })
	box(m, "Awning", f, -4, 4, 9.2, 9.6, -1, 2, accent, Enum.Material.Fabric, SHADE)
	Build.lamp(m, f, -0.5, 0.5, 8.4, 8.9, -0.6, 0.4, 18)
	-- The owner plate on the header (FOR SALE, or the featured owner's name) and the COLD BREW sign.
	local plate = box(m, "OwnerPlate", f, -15.5, -5, 9.4, 11.4, 1.84, 1.96, C.DARK, metal, DETAIL)
	local plateGui = Build.signGui(plate, front, "FOR SALE · " .. A.money(def.Price), nil, C.GOLD)
	local brew = box(m, "BrewSign", f, 4.6, 9.6, 9.4, 11.4, 1.84, 1.96, accent, Enum.Material.Wood, DETAIL)
	Build.signGui(brew, front, "COLD BREW " .. A.money(def.Service.Price),
		string.format("+%d%% SPRINT · %d MIN", math.floor(CB.Stamina * 100 + 0.5), math.floor(CB.Seconds / 60)), C.WHITE, C.GOLD, true)
	-- The roof sign (painted at levels 1-2; level 3 adds neon round it).
	box(m, "SignLeg", f, -10.3, -9.7, H + 0.8, H + 1.6, 1.8, 2.4, C.DARK_METAL, metal, DETAIL)
	box(m, "SignLeg", f, -0.3, 0.3, H + 0.8, H + 1.6, 1.8, 2.4, C.DARK_METAL, metal, DETAIL)
	local sign = box(m, "Sign", f, -14, 4, H + 1.6, H + 6.6, 1.6, 2.2, accent, Enum.Material.Wood)
	Build.signGui(sign, front, "PALM GRIND", "COFFEE · COLD BREW", C.WHITE, K.CREAM, true)

	-- Inside: the counter (front face z 9) and the register.
	box(m, "Counter", f, -4.5, 8.4, 0.4, 3.8, 9, 10.8, K.WOOD, planks)
	box(m, "CounterTop", f, -4.7, 8.6, 3.8, 4.2, 8.8, 11, C.WHITE, Enum.Material.Marble)
	local reg = L.Register
	box(m, "Register", f, reg.X - 0.8, reg.X + 0.8, 4.2, 5.3, reg.Z - 0.6, reg.Z + 0.6, C.DARK, smooth, DETAIL)
	-- ORDER HERE (the cold brew prompt hangs in front of it) and the RUSH ORDERS shelf, each under its sign.
	local sv, od = L.Service, L.Orders
	local orderSign = box(m, "OrderSign", f, sv.X - 1.8, sv.X + 1.8, 7.4, 8.8, 10.9, 11.05, C.DARK, smooth, DETAIL)
	Build.signGui(orderSign, front, "ORDER HERE", "COLD BREW " .. A.money(def.Service.Price), C.WHITE, C.GOLD)
	local rushSign = box(m, "RushSign", f, od.X - 1.8, od.X + 1.8, 7.4, 8.8, 10.9, 11.05, accent, smooth, DETAIL)
	Build.signGui(rushSign, front, "RUSH ORDERS", "PICK-UP", C.WHITE, C.GOLD)
	for _, x in ipairs({ sv.X - 1.5, sv.X + 1.5, od.X - 1.5, od.X + 1.5 }) do
		box(m, "Hanger", f, x - 0.05, x + 0.05, 8.8, H, 10.95, 11, C.DARK_METAL, metal, DETAIL)
	end
	box(m, "PickupShelf", f, od.X - 1.7, od.X + 1.7, 5.6, 5.8, 9.2, 10.6, C.STEEL, metal, DETAIL)
	for _, x in ipairs({ od.X - 1.6, od.X + 1.6 }) do
		box(m, "ShelfPost", f, x - 0.1, x + 0.1, 4.2, 5.6, 9.3, 9.5, C.STEEL, metal, DETAIL)
	end
	for i = -1, 1 do
		local x = od.X + i * 1.1
		box(m, "OrderBag", f, x - 0.4, x + 0.4, 4.2, 5.3, 9.6, 10.3, K.KRAFT, Enum.Material.Fabric, DETAIL)
		post(m, "Cup", f, x, 9.9, 5.8, 0.8, 0.5, C.WHITE, smooth, DETAIL)
	end
	box(m, "PickupMat", f, od.X - 1.4, od.X + 1.4, 0.4, 0.43, od.Z - 1.2, od.Z + 1.2, C.SAFETY, Enum.Material.Fabric, DETAIL)
	-- The back bar: espresso machine, grinder, cups, the menu.
	box(m, "BackBar", f, -4.5, 8.5, 0.4, 3.6, 12.2, 13, K.WOOD, planks)
	box(m, "BackBarTop", f, -4.5, 8.5, 3.6, 3.9, 12.1, 13, C.WHITE, Enum.Material.Marble, DETAIL)
	box(m, "Espresso", f, -2, 1.4, 3.9, 6, 12.2, 12.95, C.STEEL, metal, DETAIL)
	box(m, "EspressoTop", f, -1.8, 1.2, 6, 6.2, 12.3, 12.9, C.DARK_METAL, metal, DETAIL)
	box(m, "Grinder", f, 2.2, 3.2, 3.9, 6.2, 12.3, 12.95, C.DARK_METAL, metal, DETAIL)
	for i = 0, 4 do
		post(m, "Cup", f, 4.4 + i * 0.8, 12.6, 3.9, 0.7, 0.5, i % 2 == 0 and C.WHITE or accent, smooth, DETAIL)
	end
	local menu = box(m, "MenuBoard", f, -4, 8, 6.8, 10.4, 12.84, 12.98, C.DARK, smooth, DETAIL)
	Build.signGui(menu, front, "MENU", "ESPRESSO · LATTE · CUBANO · COLD BREW", C.WHITE, C.GOLD)
	Build.roomLight(m, f, -14, 7, H - 0.1, 5, 8, Color3.fromRGB(255, 236, 210), 22)
	-- Level 1: two tables by the front glass.
	tableSet(A, m, f, -12.5, 5.6, 0.4, accent, nil)
	tableSet(A, m, f, -7, 5.6, 0.4, accent, nil)

	-- THE FORECOURT -------------------------------------------------------------------------------------------
	-- Three parking bays in front of the terrace (park here, walk in for the next order).
	for i, x in ipairs({ -12.5, -3.5, 5.5 }) do
		Build.bayLines(m, f, x, -18, 9, 12, i == 2 and "PARKING" or nil)
	end
	-- A chalkboard by the door.
	local chalk = Build.part(m, "Chalkboard", Vector3.new(2.4, 3, 0.2), f * CFrame.new(4.4, 1.7, -1.4) * CFrame.Angles(math.rad(-12), 0, 0),
		C.DARK, smooth, DETAIL)
	Build.signGui(chalk, front, "COLD BREW", string.format("+%d%% SPRINT", math.floor(CB.Stamina * 100 + 0.5)), C.WHITE, C.GOLD, true)
	Build.part(m, "Chalkboard", Vector3.new(2.4, 3, 0.2), f * CFrame.new(4.4, 1.7, -0.6) * CFrame.Angles(math.rad(12), 0, 0), C.DARK, smooth, DETAIL)
	-- Palms at the right-hand corners (clear of the drive-through lane) and a dumpster in the back corner.
	Build.planterPalm(m, f, 25, -21, 16)
	Build.planterPalm(m, f, 25, 11, 14)
	box(m, "Dumpster", f, 23, 27.4, 0.2, 4.2, 19.6, 23.8, K.BIN, metal)
	box(m, "DumpsterLid", f, 22.9, 27.5, 4.2, 4.5, 19.5, 23.9, C.DARK_METAL, metal, DETAIL)

	-- LEVEL 2: the terrace (decks either side of the door path, three tables with umbrellas, planters).
	local terr = group(m, "Terrace2", 2, nil)
	box(terr, "Deck", f, -16, -3.5, 0.2, 0.36, -11, 1.8, K.DECK, planks)
	box(terr, "Deck", f, 3.5, 10, 0.2, 0.36, -9, 1.8, K.DECK, planks)
	box(terr, "TerracePlanter", f, -16, -3.5, 0.2, 1.6, -12, -11, C.CONCRETE, Enum.Material.Concrete)
	box(terr, "Shrubs", f, -15.8, -3.7, 1.6, 2.5, -11.9, -11.1, C.LEAF, Enum.Material.Grass)
	box(terr, "TerracePlanter", f, 3.5, 10, 0.2, 1.6, -10, -9, C.CONCRETE, Enum.Material.Concrete)
	box(terr, "Shrubs", f, 3.7, 9.8, 1.6, 2.5, -9.9, -9.1, C.LEAF, Enum.Material.Grass)
	tableSet(A, terr, f, -12, -3.5, 0.36, C.WHITE, K.CANVAS)
	tableSet(A, terr, f, -7, -8, 0.36, C.WHITE, accent)
	tableSet(A, terr, f, 6.8, -4, 0.36, C.WHITE, K.CANVAS)

	-- LEVEL 3: the drive-through loop round the café (in on the right, behind it, out on the left) and the neon.
	local dt = group(m, "DriveThru3", 3, nil)
	box(dt, "WindowAwning", f, 10, 12.2, 8, 8.4, 5.4, 10.6, accent, Enum.Material.Fabric, SHADE)
	box(dt, "WindowLedge", f, 10, 10.8, 3, 3.3, 6, 10, C.WHITE, Enum.Material.Marble, DETAIL)
	local wsign = box(dt, "WindowSign", f, 10, 10.15, 8.6, 10.6, 5.6, 10.4, C.DARK, metal, DETAIL)
	Build.signGui(wsign, rightFace, "DRIVE-THRU", "PICK UP HERE", C.WHITE, C.GOLD)
	neon(dt, f, 10, 10.2, 10.6, 10.9, 5.6, 10.4, glow)
	local function line(x0, x1, z0, z1)
		box(dt, "LaneLine", f, x0, x1, 0.2, 0.24, z0, z1, C.SAFETY, smooth, DETAIL)
	end
	line(12, 12.4, -24.5, 16) -- in lane, by the café
	line(20.6, 21, -24.5, 24.6) -- in lane, outer edge (and up the back corner)
	line(-19, 12.4, 15.6, 16) -- the back lane, by the café
	line(-27.6, 21, 24.2, 24.6) -- the back lane, outer edge
	line(-19.4, -19, -24.5, 16) -- out lane, by the café
	line(-27.6, -27.2, -24.5, 24.6) -- out lane, outer edge
	local function arrow(cx, cz, dx, dz) -- a painted arrow: a shaft and a bar across its head, pointing (dx, dz)
		if dx ~= 0 then
			box(dt, "LaneArrow", f, cx - 2.5, cx + 2.5, 0.2, 0.24, cz - 0.4, cz + 0.4, C.WHITE, smooth, DETAIL)
			box(dt, "LaneArrow", f, cx + dx * 2.5 - 0.4, cx + dx * 2.5 + 0.4, 0.2, 0.24, cz - 1.6, cz + 1.6, C.WHITE, smooth, DETAIL)
		else
			box(dt, "LaneArrow", f, cx - 0.4, cx + 0.4, 0.2, 0.24, cz - 2.5, cz + 2.5, C.WHITE, smooth, DETAIL)
			box(dt, "LaneArrow", f, cx - 1.6, cx + 1.6, 0.2, 0.24, cz + dz * 2.5 - 0.4, cz + dz * 2.5 + 0.4, C.WHITE, smooth, DETAIL)
		end
	end
	arrow(16.5, -15, 0, 1)
	arrow(16.5, 4, 0, 1)
	arrow(2, 20.3, -1, 0)
	arrow(-13, 20.3, -1, 0)
	arrow(-23.3, 5, 0, -1)
	arrow(-23.3, -14, 0, -1)
	for _, w in ipairs({ { 16.5, "DRIVE-THRU", 8 }, { -23.3, "EXIT", 7 } }) do
		local paint = box(dt, "LanePaint", f, w[1] - w[3] / 2, w[1] + w[3] / 2, 0.2, 0.22, -23, -20, C.CONCRETE, smooth,
			{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		Build.signGui(paint, Enum.NormalId.Top, w[2], nil, C.SAFETY, nil, true)
	end
	-- The menu board and the speaker on the right of the in lane, and the pole sign at its mouth.
	for _, z in ipairs({ -5.6, -0.6 }) do
		box(dt, "MenuPost", f, 22.5, 22.9, 0.2, 2.2, z - 0.2, z + 0.2, C.DARK_METAL, metal, DETAIL)
	end
	local board = box(dt, "MenuBoardOut", f, 22.3, 22.7, 2.2, 6.6, -6.2, 0, C.DARK, metal, DETAIL)
	Build.signGui(board, leftFace, "MENU", "ESPRESSO · LATTE · COLD BREW", C.WHITE, C.GOLD)
	post(dt, "Speaker", f, 21.8, 2.2, 0.2, 3.4, 0.6, C.DARK_METAL, metal, DETAIL)
	box(dt, "SpeakerHead", f, 21.4, 22.2, 3.4, 4.4, 1.8, 2.6, C.STEEL, metal, DETAIL)
	post(dt, "DriveThruPole", f, 24.5, -13.6, 0.2, 9, 0.6, C.STEEL, metal, DETAIL)
	local ds = box(dt, "DriveThruSign", f, 22, 27, 9, 11.2, -13.9, -13.7, C.DARK, metal, DETAIL)
	Build.signGui(ds, front, "DRIVE-THRU", "OPEN · ORDER AHEAD", C.WHITE, C.GOLD)
	neon(dt, f, 22, 27, 11.2, 11.45, -13.9, -13.7, glow)
	local lit = group(m, "Neon3", 3, nil)
	neon(lit, f, -14.2, 4.2, H + 6.6, H + 6.9, 1.5, 2.3, glow)
	neon(lit, f, -14.2, 4.2, H + 1.3, H + 1.6, 1.5, 2.3, glow)
	neon(lit, f, -14.5, -14.2, H + 1.3, H + 6.9, 1.5, 2.3, glow)
	neon(lit, f, 4.2, 4.5, H + 1.3, H + 6.9, 1.5, 2.3, glow)
	neon(lit, f, -17.5, 10.5, H + 0.1, H + 0.45, 1.2, 1.5, glow)

	-- LEVEL 4: the roastery corner (back left, inside) and a queue of customers outside the door.
	local roast = group(m, "Roastery4", 4, nil)
	local rx, rz = -12.5, 11
	box(roast, "RoasterBase", f, rx - 2.2, rx + 2.2, 0.4, 2.8, rz - 1.4, rz + 1.4, C.DARK_METAL, metal, DETAIL)
	local drum = Build.part(roast, "RoasterDrum", Vector3.new(3.8, 2.8, 2.8), f * CFrame.new(rx, 4.2, rz), K.COPPER, metal, DETAIL)
	drum.Shape = Enum.PartType.Cylinder
	box(roast, "Hopper", f, rx - 0.8, rx + 0.8, 5.6, 7.2, rz - 0.8, rz + 0.8, C.STEEL, metal, DETAIL)
	post(roast, "TrayStand", f, rx + 3.6, rz - 0.6, 0.4, 1.9, 0.6, C.DARK_METAL, metal, DETAIL)
	local tray = Build.part(roast, "CoolingTray", Vector3.new(0.6, 3.2, 3.2), f * CFrame.new(rx + 3.6, 2.6, rz - 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		K.COPPER, metal, DETAIL)
	tray.Shape = Enum.PartType.Cylinder
	post(roast, "Chimney", f, rx - 1.2, rz + 0.8, 5.6, H + 3 - 5.6, 0.8, C.STEEL, metal, DETAIL)
	post(roast, "ChimneyCap", f, rx - 1.2, rz + 0.8, H + 3, 0.4, 1.4, C.DARK_METAL, metal, DETAIL)
	for _, s in ipairs({ { -15.9, -14.9, 0.4, 1.6, 7.4, 8.6 }, { -15.9, -14.9, 0.4, 1.6, 6, 7.2 }, { -15.8, -15, 1.6, 2.6, 6.7, 7.9 } }) do
		box(roast, "Sack", f, s[1], s[2], s[3], s[4], s[5], s[6], K.KRAFT, Enum.Material.Fabric, DETAIL)
	end
	local rs = box(roast, "RoasterySign", f, -16, -9, 8.6, 10.2, 12.84, 12.98, C.DARK, smooth, DETAIL)
	Build.signGui(rs, front, "ROASTERY", "ROASTED RIGHT HERE", K.COPPER, C.WHITE)
	local queue = group(m, "Queue4", 4, nil)
	for i, z in ipairs({ -1.2, -3.8, -6.4, -9 }) do
		person(A, queue, f, (i % 2 == 0) and 0.4 or -0.3, z, math.pi + (i - 2.5) * 0.12, K.LOOKS[i])
	end

	-- LEVEL 5: the rooftop café.
	local roof = group(m, "Rooftop5", 5, nil)
	local ry = H + 0.8
	for _, e in ipairs({ { -17.3, 10.3, 2.6, 2.8 }, { -17.3, 10.3, 14.1, 14.3 }, { -17.3, -17.1, 2.6, 14.3 }, { 10.1, 10.3, 2.6, 14.3 } }) do
		box(roof, "Balustrade", f, e[1], e[2], ry, ry + 3, e[3], e[4], C.GLASS, Enum.Material.Glass,
			{ Transparency = 0.6, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		box(roof, "Rail", f, e[1], e[2], ry + 3, ry + 3.25, e[3], e[4], C.WHITE, metal, DETAIL)
		neon(roof, f, e[1], e[2], ry + 3.25, ry + 3.4, e[3], e[4], glow) -- string lights along the rail (after dark)
	end
	-- (Clear of the roastery's chimney at x -13.7, z 11.8 and of the stair house in the back right corner.)
	tableSet(A, roof, f, -8, 9, ry, C.WHITE, accent)
	tableSet(A, roof, f, 0, 6, ry, C.WHITE, K.CANVAS)
	tableSet(A, roof, f, 2, 12, ry, C.WHITE, nil)
	Build.planterPalm(roof, f * CFrame.new(0, ry - 0.2, 0), -15, 5, 10)
	box(roof, "StairHouse", f, 5.5, 10, ry, ry + 7, 10.5, 14.2, K.WALL, plaster)
	box(roof, "StairHouseRoof", f, 5.3, 10.2, ry + 7, ry + 7.4, 10.3, 14.4, C.WHITE, Enum.Material.Concrete, DETAIL)
	box(roof, "StairDoor", f, 6.8, 9, ry, ry + 6, 10.36, 10.5, C.DARK, metal, DETAIL)
	local rsign = box(roof, "RooftopSign", f, 5, 10, ry + 3.6, ry + 5.6, 2.4, 2.6, accent, Enum.Material.Wood, DETAIL)
	Build.signGui(rsign, front, "ROOFTOP CAFÉ", "OPEN NOW", C.WHITE, C.GOLD)

	return plateGui:FindFirstChild("Title")
end

------------------------------------------------------------------ RUSH ORDERS

-- The player's own land car if they sit in its driver's seat, else nil.
local function ownCar(player, A)
	local hum = A.humOf(player)
	local seat = hum and hum.Health > 0 and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	if car and car:IsA("Model") and car:GetAttribute("OwnerUserId") == player.UserId and car:GetAttribute("Boat") ~= true
		and car.PrimaryPart then
		return car
	end
	return nil
end

-- The car's top speed on nitro (as JobService and VehicleGuard read it).
local function topSpeed(car)
	return (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
end

-- Studs of road from a to b (RoadGraph's route), never less than the straight line.
local function roadLength(a, b)
	local straight = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
	local ok, path = pcall(RoadGraph.Path, a, b)
	local len = 0
	if ok and path then
		for i = 2, #path do
			len += (path[i] - path[i - 1]).Magnitude
		end
	else
		len = straight * 1.4 -- (no route: as JobService)
	end
	return math.max(len, straight)
end

-- Is the worker on foot at the RUSH ORDERS shelf?
local function atShelf(player, job, A)
	local root, hum = A.rootOf(player), A.humOf(player)
	if not root or not hum or hum.Health <= 0 or hum.SeatPart then
		return false
	end
	local spot = Businesses.At(job.def, job.def.Layout.Orders)
	return A.flat(root.Position - spot).Magnitude <= RU.GrabRange and math.abs(root.Position.Y - spot.Y) < 12
end

-- A VIP home's verge spot between NextMin and VIPMax studs from `from`, or nil.
local function vipStop(from, A)
	local list = {}
	for _, id in ipairs(RU.VIPHomes) do
		local home = Housing.ById[id]
		local spots = home and Housing.Spot(home, "Driveway")
		if spots and #spots > 0 then
			local pos = (Housing.Frame(home) * CFrame.new(spots[#spots])).Position
			local d = A.flat(pos - from).Magnitude
			if d >= RU.NextMin and d <= RU.VIPMax then
				table.insert(list, { pos = Vector3.new(pos.X, 0, pos.Z), name = home.Name })
			end
		end
	end
	if #list == 0 then
		return nil
	end
	return list[A.rng:NextInteger(1, #list)]
end

-- The addresses of a new order (see the header), its level; nil when none can be found.
local function planOrder(player, job, A)
	local def = job.def
	local level = A.levelOf(job.owner, def)
	local count = Businesses.RushDrops(level)
	local forced = A.takeVip(player)
	local vip = forced or (level >= RU.VIPLevel and A.rng:NextNumber() < (RU.VIPChance[level] or 0))
	local JobService = A.service("JobService")
	local roadside = JobService and JobService.RoadsideSpot
	if type(roadside) ~= "function" then
		return nil
	end
	local names = table.clone(K.CUSTOMERS)
	for i = #names, 2, -1 do
		local j = A.rng:NextInteger(1, i)
		names[i], names[j] = names[j], names[i]
	end
	local drops = {}
	local prev = def.Position
	for k = 1, count do
		local stop
		if vip and k == count then
			local v = vipStop(prev, A)
			if v then
				stop = { pos = v.pos, name = v.name, who = K.VIPS[A.rng:NextInteger(1, #K.VIPS)], vip = true }
			end
		end
		if not stop then
			local spot = roadside(prev, k == 1 and RU.FirstMin or RU.NextMin, k == 1 and RU.FirstMax or RU.NextMax)
			if spot then
				stop = { pos = spot, name = names[(k - 1) % #names + 1], vip = false }
			end
		end
		if not stop then
			break -- (a shorter order beats none)
		end
		stop.drink = K.DRINKS[A.rng:NextInteger(1, #K.DRINKS)]
		table.insert(drops, stop)
		prev = stop.pos
	end
	if #drops == 0 then
		return nil
	end
	local from = Businesses.At(def, def.Layout.Orders)
	for k, d in ipairs(drops) do
		d.road = roadLength(from, d.pos)
		d.timer = Businesses.RushTimer(d.road, k == 1)
		from = d.pos
	end
	drops[#drops].back = roadLength(drops[#drops].pos, def.Position)
	return drops, level
end

-- Back to the counter: stage "pickup" (back = an order was just finished).
local function toCounter(player, job, A, back)
	job.stage = "pickup"
	job.drops, job.leg = nil, nil
	job.holdAt, job.outSince, job.boarded = nil, nil, nil
	job.idleSince = os.clock()
	A.fire(player, "Rush", {
		Id = job.id, Stage = "pickup", Back = back == true, Level = A.levelOf(job.owner, job.def), Owner = job.owner.UserId,
		OwnerName = job.owner.DisplayName, Count = job.count, Earned = job.earned, Orders = job.orders or 0, Hold = RU.GrabHold,
		Streak = job.goldStreak or 0,
	})
end

-- The address the worker is driving to now.
local function sendLeg(player, job, A)
	local d = job.drops[job.leg]
	A.fire(player, "RushLeg", {
		Id = job.id, Leg = job.leg, Of = #job.drops, Pos = d.pos, Name = d.name, Who = d.who, Vip = d.vip == true,
		Drink = d.drink, Timer = d.timer, Ends = Workspace:GetServerTimeNow() + (d.startedAt + d.timer - os.clock()),
		Level = job.level, First = job.leg == 1, Earned = job.earned, Streak = job.goldStreak or 0, Owner = job.owner.UserId,
	})
end

-- GRAB held long enough at the shelf: plan the order and send the first address.
local function beginOrder(player, job, A)
	local drops, level = planOrder(player, job, A)
	if not drops then
		A.refuse(player, job.id, "NoAddress")
		return
	end
	job.stage = "drive"
	job.drops, job.leg, job.level = drops, 1, level
	job.boarded, job.outSince, job.top = false, nil, 0
	job.orderEarned = 0
	job.orderGolds = 0 -- (GOLDs at this order's stops: all of them on 2+ stops is a PERFECT RUN)
	drops[1].startedAt = os.clock()
	drops[1].from = Businesses.At(job.def, job.def.Layout.Orders)
	sendLeg(player, job, A)
	Telemetry.Custom(player, "BizRushOrder_" .. job.id, #drops)
end

-- Stopped in the current address's ring: the speed check, then the pay (see the header).
local function deliver(player, job, car, t, A)
	local d = job.drops[job.leg]
	local took = t - d.startedAt
	local gap = math.max(0, A.flat(d.pos - d.from).Magnitude - RU.StopRadius)
	local fastest = gap / (math.max(job.top or 0, topSpeed(car)) * RU.FastSlack)
	local guard = A.service("VehicleGuard")
	if took < fastest or (guard and type(guard.RecentlyFlagged) == "function" and guard.RecentlyFlagged(player, took)) then
		warn(string.format("[Coffee] refused %s's rush drop: %.2fs (at least %.2fs)", player.Name, took, fastest))
		A.endJob(player, "Invalid")
		return
	end
	local level = A.levelOf(job.owner, job.def)
	local last = job.leg >= #job.drops
	-- The medal, the gold streak and the owner's rush hour: all decided here (the strip only shows them).
	local rushHour = Businesses.RushHourOn(job.owner:GetAttribute("BizRushHour"), Workspace:GetServerTimeNow())
	local hadStreak = job.goldStreak or 0
	local pay, tip, medal, streak = Businesses.RushPay(job.def, level, d.road, last and (d.back or 0) or 0, job.leg == 1, took,
		d.timer, d.vip, hadStreak, rushHour)
	job.goldStreak = streak
	job.orderGolds = (job.orderGolds or 0) + (medal == "Gold" and 1 or 0)
	local bonus = last and Businesses.PerfectRunBonus(job.def, level, #job.drops, job.orderGolds) or 0
	local total = pay + tip + bonus
	EconomyService.AddCash(player, total, "bizjob:" .. job.id .. ":rush")
	job.count += 1
	job.earned += total
	job.orderEarned = (job.orderEarned or 0) + total
	local st = job.stats
	if st then
		st.drops += 1
		st[medal] = (st[medal] or 0) + 1
		st.best = math.max(st.best, streak)
		st.rushDrops += rushHour and 1 or 0
		st.vips += d.vip and 1 or 0
		st.perfectRuns += bonus > 0 and 1 or 0
	end
	A.creditOwner(job, player, total)
	A.addEmpireXP(player, E.XP.Rush)
	A.progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizRush_" .. job.id, total)
	A.fire(player, "RushPaid", {
		Id = job.id, Pay = pay, Tip = tip, Bonus = bonus, Medal = medal, Streak = streak,
		Mult = Businesses.StreakMult(streak, Businesses.Streak), Broke = hadStreak >= 2 and streak == 0 and hadStreak or nil,
		RushHour = rushHour, Golds = job.orderGolds, Late = took > d.timer, Vip = d.vip == true, Who = d.who, Name = d.name,
		Drink = d.drink, Pos = d.pos, Leg = job.leg, Of = #job.drops, Took = took, Last = last, Order = job.orderEarned,
		Count = job.count, Earned = job.earned,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
	if last then
		job.orders = (job.orders or 0) + 1
		toCounter(player, job, A, true)
		return
	end
	job.leg += 1
	local nxt = job.drops[job.leg]
	nxt.startedAt = t
	nxt.from = car.PrimaryPart.Position
	job.top = topSpeed(car)
	sendLeg(player, job, A)
end

function Coffee.Start(player, job, A)
	job.orders = 0
	job.goldStreak = 0
	job.stats = { drops = 0, Gold = 0, Silver = 0, Bronze = 0, best = 0, rushDrops = 0, vips = 0, perfectRuns = 0 }
	toCounter(player, job, A, false)
end

-- The job's end (any reason): the shift report's numbers (BusinessJob "Ended" Report).
function Coffee.End(_player, job, _reason, _A)
	local st = job.stats or {}
	return {
		Report = {
			Orders = job.orders or 0, Drops = st.drops or 0, Gold = st.Gold or 0, Silver = st.Silver or 0, Bronze = st.Bronze or 0,
			PerfectRuns = st.perfectRuns or 0, Vips = st.vips or 0, Best = st.best or 0, RushDrops = st.rushDrops or 0,
		},
	}
end

------------------------------------------------------------------ RUSH HOUR (see the header)

-- A rush hour at this owner's café for `seconds` (real) seconds from now: the attribute, and the news to the owner
-- and to anyone working for them there.
local function startRushHour(owner, seconds, A)
	local def = cafe()
	if not def then
		return
	end
	local untilT = Workspace:GetServerTimeNow() + seconds
	owner:SetAttribute("BizRushHour", untilT)
	local info = { Kind = "RushHour", Id = def.Id, Until = untilT, Owner = owner.UserId, OwnerName = owner.DisplayName,
		Boost = RU.RushHour.TipBoost }
	A.result(owner, info)
	for _, p in ipairs(Players:GetPlayers()) do
		local job = p ~= owner and A.jobOf(p)
		if job and job.id == def.Id and job.owner == owner then
			A.result(p, info)
		end
	end
	Telemetry.Custom(owner, "BizRushHour_" .. def.Id, 1)
end

-- Once a second: every café owner's rush-hour clock (their play seconds), and the ones running out.
function Coffee.Second(_dt, A)
	local def = cafe()
	if not def then
		return
	end
	local RH = RU.RushHour
	local now = Workspace:GetServerTimeNow()
	for _, p in ipairs(Players:GetPlayers()) do
		local untilT = p:GetAttribute("BizRushHour")
		if type(untilT) == "number" and untilT <= now then
			p:SetAttribute("BizRushHour", nil)
			local over = { Kind = "RushHourOver", Id = def.Id, Owner = p.UserId }
			A.result(p, over)
			for _, q in ipairs(Players:GetPlayers()) do
				local job = q ~= p and A.jobOf(q)
				if job and job.id == def.Id and job.owner == p then
					A.result(q, over)
				end
			end
		end
		local play = A.play(p)
		if play and A.owned(p, def.Id) then
			local nextAt = R.next[p]
			if not nextAt then
				R.next[p] = play + A.rng:NextNumber(RH.Gap[1], RH.Gap[2]) -- (the first: Gap into the session)
			elseif play >= nextAt and not Businesses.RushHourOn(p:GetAttribute("BizRushHour"), now) then
				startRushHour(p, RH.Length, A)
				-- (the next: Gap after this one ends; Length is real time, the clock is play time x the Studio scale)
				R.next[p] = play + RH.Length * A.timeScale() + A.rng:NextNumber(RH.Gap[1], RH.Gap[2])
			end
		end
	end
end

function Coffee.PlayerLeft(player, _A)
	R.next[player] = nil
end

-- Studio helpers (BusinessService.Debug): "rushhour" (value = seconds) starts one at your café now.
function Coffee.Debug(player, cmd, _id, value, A)
	if cmd ~= "rushhour" then
		return nil
	end
	local def = cafe()
	if not def or not A.owned(player, def.Id) then
		return "doesn't own Palm Grind"
	end
	local seconds = math.clamp(tonumber(value) or RU.RushHour.Length, 5, 1800)
	startRushHour(player, seconds, A)
	R.next[player] = (A.play(player) or 0) + seconds * A.timeScale() + RU.RushHour.Gap[1]
	return string.format("rush hour at your Palm Grind for %ds", seconds)
end

function Coffee.Resend(player, job, A)
	if job.stage == "drive" and job.drops then
		sendLeg(player, job, A)
	else
		toCounter(player, job, A, false)
	end
end

-- RequestBusiness("Step", "GrabOn" | "GrabOff"): the GRAB hold at the shelf, timed here.
function Coffee.Step(player, job, step, A)
	if job.stage ~= "pickup" then
		return
	end
	local now = os.clock()
	if step == "GrabOn" then
		if atShelf(player, job, A) then
			job.holdAt = now
		else
			A.fire(player, "RushStep", { Again = true, Far = true })
		end
	elseif step == "GrabOff" then
		local held = job.holdAt and now - job.holdAt or 0
		job.holdAt = nil
		local near = atShelf(player, job, A)
		if not near or held < RU.GrabHold - RU.HoldSlack then
			A.fire(player, "RushStep", { Again = true, Far = not near })
			return
		end
		beginOrder(player, job, A)
	end
end

-- Four times a second (BusinessService's jobsTick, after its own end rules).
function Coffee.Tick(player, job, t, A)
	if job.stage ~= "drive" or not job.drops then
		if t - (job.idleSince or t) > RU.IdleTime then
			A.endJob(player, "Idle")
		end
		return
	end
	local car = ownCar(player, A)
	if not car then
		job.outSince = job.outSince or t
		if t - job.outSince > (job.boarded and RU.LeaveGrace or RU.CarGrace) then
			A.endJob(player, job.boarded and "LeftOwnCar" or "NoCarYet")
		end
		return
	end
	job.outSince = nil
	job.boarded = true
	job.top = math.max(job.top or 0, topSpeed(car))
	local d = job.drops[job.leg]
	local chassis = car.PrimaryPart
	if A.flat(chassis.Position - d.pos).Magnitude >= RU.StopRadius or chassis.AssemblyLinearVelocity.Magnitude >= RU.StopSpeed then
		return
	end
	deliver(player, job, car, t, A)
end

return Coffee
