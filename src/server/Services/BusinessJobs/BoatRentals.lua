-- BoatRentals (ModuleScript, ServerScriptService.Services.BusinessJobs.BoatRentals)
-- Coastline Boat Rentals, Empire's fourth business (M4 of launch/10-BUSINESSES-PRD.md v2; unlocked at Empire rank 2;
-- every number in Config.Businesses: the BoatRentals entry, Tour and Rental). This is BusinessService's "job module"
-- for it: it draws the floating dock, runs its job (BOAT TOURS) and the customer service (the JET SKI RENTAL).
-- Everything else (owning it, its register and levels, the featured-owner sign, break-ins, crew cuts, Empire XP,
-- saving, the remotes, the customers' 70/30 split) is BusinessService's, which calls in here with its own helpers
-- (Api: see JOB MODULES in its header). Nothing here runs unless BusinessService does (the launch switch,
-- Config.Businesses.Live).
--
-- THE BUILDING (BoatRentals.Style; Look 3.0, beachy marina: white timber and teak, a slate-blue roof, rope rails,
-- the business's sea blue and an aqua night glow). It stands on the WATER just off the end of the first marina pier,
-- beside Marina Boat Sales (Config PLACES). Lot space as every business lot: origin at the lot centre, -Z toward the
-- "street" (the marina pier, to the west), +Z out to sea. BusinessService lays a concrete slab under every lot;
-- here it's made see-through, not solid and invisible to rays (open water: the boats in the slips float on the
-- sea under it).
--   * Solid (walk on it): the front deck (x -27..27, z -25..-13), the gangway from the pier's end (x 0.5..6.5, z
--     -47.3..-25: the only part outside the lot, a walkway over the 22 studs of water between the two), the main
--     pier out to sea (x -3..3, z -13..23), a finger each side (x -20..-17.5 and 16..18.5); the TOURS ticket booth
--     (x 8..19, z -22..-15: its door and ticket window at the front, the counter and the till at the back:
--     Layout.Register, where break-in robbers rummage), the JET SKI RENTALS stand at the head of the rental slip
--     (Layout.Service: BusinessService's BizServicePrompt hangs in it), the entrance arch's posts, a palm planter.
--   * Looks only: the owner plate on the booth's roof edge (FOR SALE · $120,000, or the featured owner's name; the
--     client re-dresses it), the COASTLINE roof sign, the pilings, white edge boards, rope rails, benches, life rings,
--     lamps (NightLamp), the TOURS DEPART HERE sign, a flag at the pier's end.
--   * The slips: the tour boat's (x 3..16, Layout.Berth), the rental slip (x -17.5..-3: Layout.Rentals, two jet
--     skis side by side), and a berth for the fleet's display boats beyond each finger.
--   * LEVEL PROPS (PRD section 5, Boat Rentals; child Models with MinLevel / MaxLevel, drawn per device by
--     BusinessClient, never solid):
--       1  a dock and one small boat (a dinghy in the west berth) and a chalkboard at the hut (level 1 only)
--       2  a second boat (a white runabout) and the proper ticket booth: a striped awning, a TICKETS lightbox, a
--          brochure rack, the booth's flag
--       3  jet skis: three on a floating jet ski dock in the east berth, and string lights along the main pier
--       4  the tour boat: a long canopy boat (COASTLINE TOURS) moored in the east berth
--       5  the luxury yacht in the west berth (the dinghy and the runabout make room for it), gold trim on the sign
--   Returns the owner plate's title label (BusinessService's publishOwners writes FOR SALE / the owner).
--
-- BOAT TOURS (Config.Businesses.Tour; JobKind "BizTour"). Started by BusinessService (START JOB > BOAT TOURS at the
-- ticket booth: the owner, or a crewmate working for an owner in the server; the owner's level sets the boat, the
-- tourists, the routes and the pay; a crewmate's pay gives the owner the 20% cut, as M1's jobs). One shift, tour
-- after tour:
--   1. THE BOAT: the business's own boat (Businesses.TourBoat at the owner's level, its fit-out: Businesses.
--      TourFitout) appears ANCHORED in its berth (refused "BerthBlocked" when something's in it, "NoBoat" when it
--      can't be built). Car attributes BizCar = true, BizTour = true, BizDriverUserId, BizId; no OwnerUserId (no
--      garage, selling, races, taxi fares or riders: M1's customer-car rules); its DrivePrompt and RidePrompt are
--      replaced by "BizDrivePrompt" (only the worker may sit; anyone else is unseated; nobody rides along). It's
--      job.car, so BusinessService removes it with the job, whatever ends it. The worker is seated at the helm.
--   2. A NEW TOUR (setupTour): the route (Businesses.PickRoute; Studio: player attribute BizTestRoute), the special
--      tour (Businesses.RollTourSpecial, a Sunset Tour only at dusk / night: Businesses.SunsetTime with
--      Lighting.ClockTime and Workspace IsNight; Studio: BizTestTour), Businesses.TourTourists of the pedestrians'
--      looks (ReplicatedStorage.PedTemplates, as M1's robbers and JobService's taxi fares; posed statues: no
--      Humanoid, massless, never solid; a sun hat each, a fishing rod for a Fishing Party, a gold name tag on the
--      celebrity) waiting on the main pier (Layout.Queue). BusinessJob "Tour" { Id, Stage = "board", Level, Owner,
--      OwnerName, Count, Earned, Streak, Boat, Route, RouteId, Stops = { { Name, Pos, Line, Kind } }, Mouth (the
--      slip's mouth), Dock (the dock ring), Special, Celeb, Par, Length, Tourists, Tours }.
--   3. BOARDING: once the worker sits at the helm, the tourists hop aboard one by one (Tour.BoardEach apart) onto
--      their seats (Tour.Seats for that boat), welded to the hull. Then "TourGo" { Id, Par }: the boat is let go
--      (unanchored, its physics handed to the worker's device) and the clock starts.
--   4. THE ROUTE (Tick, four times a second): every stop in order. A PASS ring counts when the stretch driven since
--      the last check comes within Tour.Radius (Businesses.TourReached): "TourStop" { Id, Index, Next }. A PHOTO or
--      FISHING stop starts the same way ("TourPhotoOn" { Index, Kind }); then Businesses.PhotoStep on the boat's
--      speed each check until "TourPhoto" { Index, Grade = "Perfect" | "Ok" | "Missed", Kind, Next } (the tourists'
--      heads flash like cameras for everyone to see). Every leg gets the taxi's speed check (from where the last
--      stop was passed, at the fastest nitro top speed the boat had x Tour.FastSlack, and VehicleGuard): failing it
--      ends the shift ("Invalid", nothing paid). THE MOOD (Businesses.TourMood; player attribute BizTourHappy 0-100
--      for the strip): the turn rate from the hull's heading between checks x its speed, rams (the speed falling
--      over Mood.RamDecel and more than halving, or ImpactService's BumpedAt changing), running aground (a ray
--      down from the hull finds no water: twice a second). A big drop makes a tourist shout ("TourMood" { Mood,
--      Why = "Turn" | "Ram" | "Beach" }, and their bubble for everyone).
--   5. THE DOCK: after the last stop, stopped in the dock ring (Tour.DockRadius, under DockSpeed): the boat is
--      anchored and glides into its berth (VehicleGuard.Allow first), the tour is paid: Businesses.TourPay (the
--      route's length, every stop's grade, the time against Businesses.TourPar, the mood, the special, the ★★★
--      streak), reason "bizjob:<id>:tour", the worker's Empire XP Tour, the owner's books (jobsDone, lifetime,
--      crew cut), "TourPaid" { Pay, Tip, Bonus, Stars, Streak, Mult, Broke, Special, Celeb, Mood, Took, Par,
--      OnTime, Grades, Share, Route, Count, Earned }. The tourists step off onto the pier, cheer (their bubbles:
--      the stars decide what they say) and fade; then "Tour" { Stage = "after" }: NEXT TOUR (RequestBusiness
--      "Step", "Next": a new tour from 2, the worker seated again if they got out nearby) or END JOB.
--   6. ENDS (BusinessJob "Ended" from BusinessService): out of the boat for Tour.LeaveGrace seconds during a tour,
--      or walking more than Tour.LeaveRange from it at the dock for as long ("LeftBoat"); not at the helm within
--      BoardGrace of the start ("LeftBoat"); the boat gone or sunk ("BoatGone"); IdleTime at the dock without a
--      next tour ("Idle"); "Invalid"; and BusinessService's own rules (END JOB, wanted, side (arrested), died, the
--      owner leaving, another job taking JobKind). The boat goes (BusinessService), the tourists with it (End).
--      BoatRentals.End adds the shift's Report { Tours, Stars3, Photos, Perfects, Missed, Best (the best ★★★
--      streak), Specials, Tourists, Happy (the average mood at the dock, %), Route (the last one's name) }.
--
-- THE JET SKI RENTAL (Config.Businesses.Rental; BoatRentals.Service, called by BusinessService's BizServicePrompt
-- at the JET SKI RENTALS stand). Anyone may buy one who is a citizen ("RentCivOnly"), not wanted ("RentWanted"), on
-- foot ("RentOnFoot") within Rental.Reach of the stand ("TooFar"), without a rental out already ("RentAlready"),
-- when a rental slot (Layout.Rentals) is clear ("RentBusy"). The jet ski (Rental.Vehicle, built before any money
-- moves) is paid through BusinessService's serveCustomer (reason "bizrental:<id>": the featured owner's 70%, the
-- customer-XP cap, the rest a sink), then appears in the slot with the buyer aboard. Car attributes BizCar = true,
-- BizRental = true, BizDriverUserId, BizId, BizRentalUntil; no OwnerUserId; only the renter may sit (BizDrivePrompt).
-- Player attribute BizRentalUntil = the server time it ends (Rental.Seconds from now, / BusinessTimeScale in
-- Studio): the HUD's timer. BusinessResult "Rented" { Id, Price, Until, Owner, Label }, "RentalWarn" { Left } once at
-- Rental.Warn seconds left, "RentalOver" { Why = "Time" | "Left" | "Gone" | "Arrested" } when it goes (the renter
-- put off first): at the end of its time, after Rental.LeaveGrace seconds off it, the jet ski gone, or the renter
-- arrested. Leaving the game takes it too. Kept per renter by UserId (never an Instance key: the Nov 4 lesson).
--
-- STUDIO (BoatRentals.Debug, through BusinessService.Debug): "tour" (value "Celebrity" | "Fishing" | "Sunset":
-- your next tour is that special one; "" clears it), "route" (value a route Id: your next tour's), "mood" (value
-- 0-1: your tour's tourists' mood now), "rentleft" (value seconds: your rental's time left).
--
-- API (BusinessService calls these; A = its Api table): Kinds, Style, Start, Resend, Step, Tick, End, Init, Second,
-- Service, PlayerLeft, Debug (see JOB MODULES in its header).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyService = require(game:GetService("ServerScriptService").Services.EconomyService)
local Telemetry = require(game:GetService("ServerScriptService").Services.Telemetry)

local BoatRentals = {}

-- The job kinds this module runs, and the JobKind attribute for each (BusinessService's JOB MODULES).
BoatRentals.Kinds = { Tour = "BizTour" }

local TO = Businesses.Tour
local RE = Businesses.Rental
local E = Businesses.Empire

-- Looks, words and constants that aren't balance (balance lives in Config.Businesses).
local K = {
	WATER_Y = -1.5, -- the sea's surface (as DealershipService and ActivityClient)
	DECK_TOP = 0.2, -- the dock's planks: the lot's ground height (the door, the robbers and the props stand on it)
	BOOTH_H = 8, -- the ticket booth's walls
	-- Colours (Look 3.0: white timber, teak, slate, the sea blue of the config's Accent).
	DECK = Color3.fromRGB(150, 118, 84), -- weathered deck planks
	TIMBER = Color3.fromRGB(238, 236, 228), -- white-painted timber
	TEAK = Color3.fromRGB(128, 92, 62),
	ROOF = Color3.fromRGB(70, 92, 112), -- slate-blue metal roof
	PILING = Color3.fromRGB(96, 80, 62),
	TRIM = Color3.fromRGB(244, 244, 238),
	ROPE = Color3.fromRGB(224, 210, 176),
	WORKTOP = Color3.fromRGB(230, 228, 222),
	FLOOR = Color3.fromRGB(196, 176, 150),
	RING = Color3.fromRGB(255, 110, 40), -- life rings
	CANVAS = Color3.fromRGB(250, 246, 236),
	NAVY = Color3.fromRGB(28, 52, 92),
	HULL = Color3.fromRGB(244, 246, 250),
	GOLD_TRIM = Color3.fromRGB(214, 176, 92),
	HATS = { Color3.fromRGB(232, 210, 150), Color3.fromRGB(255, 120, 150), Color3.fromRGB(120, 200, 230), Color3.fromRGB(250, 220, 90),
		Color3.fromRGB(250, 250, 250) },
	ROD = Color3.fromRGB(60, 50, 40),
	FLASH = Color3.fromRGB(255, 255, 255),
	-- Celebrities on a Celebrity Tour (made up: the strip's "CELEBRITY TOUR · LEXI LUX" and the gold tag).
	CELEBS = { "Stella Starr", "DJ Marlo", "Rico Diamante", "Lexi Lux", "Captain Neon", "Kai Sterling", "Bianca Bling" },
	-- What tourists shout (their speech bubbles, for everyone).
	SHOUTS = {
		Turn = { "Whoa!", "My hat!", "Eek!", "Easy, captain!" },
		Ram = { "OW!", "Was that a rock?!", "My coffee!", "Captain!!" },
		Beach = { "Are we on LAND?!", "Sand! SAND!", "Boats float, right?" },
	},
	CHEERS = {
		[3] = { "Best. Tour. EVER!", "Bravo, captain!", "Five stars!", "Again! Again!" },
		[2] = { "Lovely tour!", "Thanks, captain!", "Great photos!" },
		[1] = { "...thanks, I guess.", "I feel seasick.", "Never again." },
	},
	BOARD_HOP = 0.35, -- seconds each half of a tourist's hop aboard (up to the gunwale, down onto the seat)
	SIT_UP = 1.3, -- a seated R15 rider's root part above the seat's top (as VehicleService's NPC_SEAT_UP)
	SAY_GAP = 1.6, -- seconds between two tourist shouts
	BEACH_CHECK = 0.5, -- seconds between two "are we aground?" rays
	DRIVE_REACH = 20, -- studs: the boat's "Drive" bubble reach (the berth is beside the pier; from the water a bit more)
	MOOD_STEP = 0.01, -- the mood attribute is sent in whole percent
	SEAT_SEARCH = 40, -- studs: NEXT TOUR seats a worker on foot this close to the boat again
}

local S = {
	A = nil, -- BusinessService's Api (Init)
	rentals = {}, -- [UserId] = { boat, untilT (server time), warned, outSince (os.clock), def }
	def = nil, -- the Config entry (Style "BoatRentals")
}

------------------------------------------------------------------ small helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function pick(list, A)
	return list[A.rng:NextInteger(1, #list)]
end

local function siteDef()
	if not S.def then
		for _, d in ipairs(Businesses.List) do
			if d.Style == "BoatRentals" then
				S.def = d
			end
		end
	end
	return S.def
end

-- The boat's top speed on nitro (as JobService and VehicleGuard read it).
local function topSpeed(boat)
	return (boat:GetAttribute("MaxSpeed") or 140) * (boat:GetAttribute("NitroSpeed") or 1.2)
end

-- The height a boat's chassis floats at in the water (DealershipService's: its springs settle at 45% of their travel).
local function floatY(id)
	local cfg = Vehicles.Resolve(id)
	if not cfg then
		return K.WATER_Y + 2
	end
	return K.WATER_Y + cfg.Size.Y / 2 - 0.6 + cfg.RestLength * 0.55 + cfg.WheelRadius
end

-- A boat's resting CFrame at a lot-space spot, its bow (-Z of a CarBuilder model) pointing out to sea (+Z).
local function mooredAt(def, spot, id)
	return Businesses.Frame(def) * CFrame.new(spot.X, floatY(id), spot.Z) * CFrame.Angles(0, math.pi, 0)
end

-- Nothing (a vehicle, or a player but `except`) in a box at cf of this size?
local function boxClear(cf, size, except)
	local list = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p ~= except then
			table.insert(list, p.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	return #Workspace:GetPartBoundsInBox(cf, size + Vector3.new(2, 4, 3), params) == 0
end

-- Strip a CarBuilder boat of its own Drive / Ride bubbles and give it a "Drive" bubble for one player (the
-- worker or the renter; BusinessClient shows it only to them). Only they may sit at the helm; nobody rides along.
local function lockBoat(boat, userId, what, onSit)
	boat:SetAttribute("BizCar", true)
	boat:SetAttribute("BizDriverUserId", userId)
	for _, d in ipairs(boat:GetDescendants()) do
		if d:IsA("ProximityPrompt") and (d.Name == "DrivePrompt" or d.Name == "RidePrompt") then
			d:Destroy()
		end
	end
	local seat = boat:FindFirstChild("DriverSeat")
	local chassis = boat.PrimaryPart
	if not seat or not chassis then
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BizDrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = what
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = K.DRIVE_REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local p = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if occupant and (not p or p.UserId ~= boat:GetAttribute("BizDriverUserId")) then
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			return
		end
		if p then
			boat:SetAttribute("DriverUserId", p.UserId)
			if not chassis.Anchored then
				pcall(function()
					chassis:SetNetworkOwner(p)
				end)
			end
		else
			boat:SetAttribute("DriverUserId", nil)
		end
		if onSit then
			onSit(p)
		end
	end)
	local pseat = boat:FindFirstChild("PassengerSeat")
	if pseat and pseat:IsA("Seat") then
		pseat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local sw = pseat.Occupant and pseat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy() -- (nobody rides along)
			end
		end)
	end
	prompt.Triggered:Connect(function(who)
		local char = who.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if who.UserId == boat:GetAttribute("BizDriverUserId") and hum and hum.Health > 0 and hum.SeatPart == nil and seat.Occupant == nil then
			seat:Sit(hum)
		end
	end)
	return seat
end

-- Is this player sitting at the boat's helm?
local function atHelm(player, boat, A)
	local hum = A.humOf(player)
	local seat = boat and boat:FindFirstChild("DriverSeat")
	return hum ~= nil and seat ~= nil and seat.Occupant == hum
end

------------------------------------------------------------------ the building (Look 3.0)

-- A moored boat to look at (a level prop), its bow to +Z: a hull with a narrower bow, a deck, a trim line and
-- (optionally) a windscreen. x, z = its middle in lot space; len, wid in studs.
local function boatProp(A, parent, f, x, z, len, wid, hull, trim, screen)
	local box, DETAIL = A.Build.box, A.DETAIL
	local smooth = Enum.Material.SmoothPlastic
	local w, y0, y1 = wid / 2, K.WATER_Y - 0.6, K.WATER_Y + 1.7
	local z0, z1 = z - len / 2, z + len / 2
	box(parent, "Hull", f, x - w, x + w, y0, y1, z0, z1 - 3, hull, smooth, DETAIL)
	box(parent, "Bow", f, x - w * 0.6, x + w * 0.6, y0 + 0.3, y1, z1 - 3, z1 - 1, hull, smooth, DETAIL)
	box(parent, "BowTip", f, x - w * 0.25, x + w * 0.25, y0 + 0.6, y1, z1 - 1, z1, hull, smooth, DETAIL)
	box(parent, "Deck", f, x - w + 0.3, x + w - 0.3, y1, y1 + 0.15, z0 + 0.3, z1 - 3, K.TEAK, Enum.Material.WoodPlanks, DETAIL)
	box(parent, "Trim", f, x - w - 0.05, x + w + 0.05, y1 - 0.5, y1 - 0.25, z0, z1 - 3, trim, smooth, DETAIL)
	if screen then
		box(parent, "Windscreen", f, x - w + 0.6, x + w - 0.6, y1 + 0.15, y1 + 1.6, z1 - 5, z1 - 4.7, A.C.GLASS, Enum.Material.Glass,
			{ Transparency = 0.35, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
end

-- A jet ski to look at (level 3), its nose to +Z.
local function skiProp(A, parent, f, x, z, color)
	local box, DETAIL = A.Build.box, A.DETAIL
	local y = K.WATER_Y
	box(parent, "JetSki", f, x - 1.3, x + 1.3, y - 0.4, y + 0.8, z - 3.2, z + 2.2, color, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "JetSkiNose", f, x - 0.7, x + 0.7, y - 0.2, y + 0.8, z + 2.2, z + 3.4, color, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "JetSkiSeat", f, x - 0.6, x + 0.6, y + 0.8, y + 1.3, z - 2.6, z + 0.4, A.C.DARK, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "JetSkiBars", f, x - 0.9, x + 0.9, y + 1.2, y + 1.45, z + 1, z + 1.3, A.C.DARK_METAL, Enum.Material.Metal, DETAIL)
end

-- Coastline Boat Rentals (see the header). Returns the plate's title label.
function BoatRentals.Style(m, f, def, A)
	local Build, C, DETAIL, SHADE = A.Build, A.C, A.DETAIL, A.SHADE
	local box, post, neon, group = Build.box, Build.post, Build.neon, Build.group
	local L = def.Layout
	local accent, glow = def.Accent, def.Neon
	local front, back = Enum.NormalId.Front, Enum.NormalId.Back
	local planks, wood, metal = Enum.Material.WoodPlanks, Enum.Material.Wood, Enum.Material.Metal
	local smooth, fabric = Enum.Material.SmoothPlastic, Enum.Material.Fabric
	local TOP, BH = K.DECK_TOP, K.BOOTH_H

	-- Open water: BusinessService's concrete slab and kerb go (see-through, not solid, never in a ray's way: the
	-- boats in the slips float on the sea under them).
	for _, name in ipairs({ "Lot", "Kerb" }) do
		local p = m:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Transparency = 1
			p.CanCollide = false
			p.CanQuery = false
			p.CastShadow = false
		end
	end

	-- THE DOCK (solid planks on the water, the marina pier's height) ------------------------------------------------
	box(m, "Deck", f, -27, 27, -0.6, TOP, -25, -13, K.DECK, planks)
	box(m, "Gangway", f, 0.5, 6.5, -0.45, 0.15, -47.3, -25, K.DECK, planks)
	box(m, "MainPier", f, -3, 3, -0.6, TOP, -13, 23, K.DECK, planks)
	box(m, "Finger", f, -20, -17.5, -0.6, TOP, -13, 8, K.DECK, planks)
	box(m, "Finger", f, 16, 18.5, -0.6, TOP, -13, 20, K.DECK, planks)
	-- White edge boards (looks).
	for _, e in ipairs({
		{ -27, 0.5, -25.15, -24.95 }, { 6.5, 27, -25.15, -24.95 }, { -27, -20, -13.05, -12.85 }, { -17.5, -3, -13.05, -12.85 },
		{ 3, 16, -13.05, -12.85 }, { 18.5, 27, -13.05, -12.85 }, { -3.15, -2.95, -13, 23 }, { 2.95, 3.15, -13, 23 },
	}) do
		box(m, "EdgeBoard", f, e[1], e[2], TOP - 0.06, TOP + 0.04, e[3], e[4], K.TRIM, smooth, DETAIL)
	end
	-- Pilings: dark timber posts at the corners and along the piers, a stud proud of the deck (looks).
	for _, p in ipairs({
		{ -27, -25 }, { 27, -25 }, { -27, -13 }, { 27, -13 }, { -3, -1 }, { 3, -1 }, { -3, 11 }, { 3, 11 }, { -3, 23 }, { 3, 23 },
		{ -20, 8 }, { -17.5, 8 }, { 16, 20 }, { 18.5, 20 }, { 16, 4 }, { 18.5, 4 }, { 0.5, -36 }, { 6.5, -36 }, { 0.5, -47 }, { 6.5, -47 },
	}) do
		post(m, "Piling", f, p[1], p[2], -6, 7.4, 1, K.PILING, wood, DETAIL)
	end
	-- The gangway's rope rails (looks).
	for _, x in ipairs({ 0.75, 6.25 }) do
		for _, z in ipairs({ -46, -41, -36, -31, -26 }) do
			post(m, "RailPost", f, x, z, 0.15, 3, 0.3, K.TRIM, wood, DETAIL)
		end
		box(m, "Rope", f, x - 0.08, x + 0.08, 2.7, 2.86, -46, -26, K.ROPE, fabric, DETAIL)
	end
	-- The entrance arch over the gangway's landing (its posts are solid; the name board faces the marina pier).
	for _, x in ipairs({ -0.4, 7.4 }) do
		box(m, "ArchPost", f, x - 0.4, x + 0.4, TOP, 11, -25, -24.2, K.TIMBER, wood)
	end
	box(m, "ArchBeam", f, -0.9, 7.9, 10.2, 11, -25, -24.2, K.TIMBER, wood, DETAIL)
	local arch = box(m, "ArchSign", f, 0, 7, 8, 10.2, -24.85, -24.6, accent, wood, DETAIL)
	Build.signGui(arch, front, "COASTLINE", "BOAT RENTALS · TOURS", C.WHITE, C.GOLD, true)
	neon(m, f, -0.9, 7.9, 11, 11.15, -24.85, -24.35, glow)

	-- THE TOURS TICKET BOOTH (x 8..19, z -22..-15): its door and window face the gangway ------------------------
	local bx0, bx1, bz0, bz1 = 8, 19, -22, -15
	box(m, "BoothFloor", f, bx0, bx1, TOP, 0.4, bz0, bz1, K.FLOOR, planks)
	box(m, "BoothWall", f, bx0, bx1, 0.4, BH, bz1 - 0.6, bz1, K.TIMBER, planks)
	box(m, "BoothWall", f, bx0, bx0 + 0.6, 0.4, BH, bz0, bz1 - 0.6, K.TIMBER, planks)
	box(m, "BoothWall", f, bx1 - 0.6, bx1, 0.4, BH, bz0, bz1 - 0.6, K.TIMBER, planks)
	-- The front: wall, the doorway (x 12..15, Layout.Door), the ticket window (x 15.6..18.4).
	box(m, "BoothFront", f, bx0 + 0.6, 12, 0.4, BH, bz0, bz0 + 0.6, K.TIMBER, planks)
	box(m, "Lintel", f, 12, 15, 7.4, BH, bz0, bz0 + 0.6, K.TIMBER, planks)
	box(m, "BoothFront", f, 15, bx1 - 0.6, 0.4, 3.2, bz0, bz0 + 0.6, K.TIMBER, planks)
	box(m, "BoothFront", f, 15, 15.6, 3.2, BH, bz0, bz0 + 0.6, K.TIMBER, planks)
	box(m, "BoothFront", f, 15, bx1 - 0.6, 6.4, BH, bz0, bz0 + 0.6, K.TIMBER, planks)
	Build.glass(m, f, 15.6, bx1 - 0.6, 3.2, 6.4, bz0 + 0.15, bz0 + 0.45)
	box(m, "WindowLedge", f, 15.4, bx1 - 0.4, 3.2, 3.5, bz0 - 0.9, bz0, K.TEAK, planks, DETAIL)
	for _, x in ipairs({ 11.7, 15 }) do
		box(m, "DoorFrame", f, x, x + 0.3, 0.4, 7.4, bz0 - 0.1, bz0 + 0.7, accent, wood, DETAIL)
	end
	box(m, "BoothRoof", f, bx0 - 0.8, bx1 + 0.8, BH, BH + 0.6, bz0 - 1.2, bz1 + 0.6, K.ROOF, metal, { CastShadow = true })
	Build.lamp(m, f, 13, 14, 6.6, 7.1, bz0 - 0.9, bz0 - 0.1, 16)
	-- Inside: the counter along the back wall, the till (Layout.Register), a tour map on the wall, a light.
	box(m, "Counter", f, 9, 18, 0.4, 3.8, -17.2, bz1 - 0.6, K.TEAK, planks)
	box(m, "CounterTop", f, 8.8, 18.2, 3.8, 4.2, -17.4, bz1 - 0.6, K.WORKTOP, Enum.Material.Marble, DETAIL)
	local reg = L.Register
	box(m, "Register", f, reg.X - 0.8, reg.X + 0.8, 4.2, 5.3, reg.Z - 0.5, reg.Z + 0.5, C.DARK, smooth, DETAIL)
	local map = box(m, "TourMap", f, 9.5, 17.5, 4.8, 7.4, bz1 - 0.75, bz1 - 0.6, K.NAVY, smooth, DETAIL)
	Build.signGui(map, front, "TODAY'S TOURS", "SEA DREAM · FERRIS WHEEL · LIGHTHOUSE KEY", C.WHITE, glow)
	Build.roomLight(m, f, 9.5, 17.5, BH - 0.1, -20.5, -17.5, Color3.fromRGB(255, 244, 228), 16)
	-- The owner plate on the roof's front edge (FOR SALE, or the featured owner's name) and the roof sign.
	local plate = box(m, "OwnerPlate", f, bx0 + 0.4, bx1 - 0.4, BH + 0.6, BH + 2.2, bz0 - 1.36, bz0 - 1.22, C.DARK, metal, DETAIL)
	local plateGui = Build.signGui(plate, front, "FOR SALE · " .. A.money(def.Price), nil, C.GOLD)
	for _, x in ipairs({ 9.8, 17.2 }) do
		box(m, "SignLeg", f, x - 0.25, x + 0.25, BH + 0.6, BH + 2.8, bz0 - 0.2, bz0 + 0.2, C.DARK_METAL, metal, DETAIL)
	end
	local sign = box(m, "Sign", f, bx0, bx1, BH + 2.8, BH + 5.8, bz0 - 0.35, bz0 + 0.15, accent, wood)
	Build.signGui(sign, front, "COASTLINE", "BOAT RENTALS · SEA TOURS", C.WHITE, Color3.fromRGB(255, 236, 170), true)
	Build.signGui(sign, back, "COASTLINE", "BOAT TOURS · JET SKIS", C.WHITE, Color3.fromRGB(255, 236, 170), true)

	-- THE JET SKI RENTALS STAND at the head of the rental slip (Layout.Service: the customer's spot in front) -----
	local sv = L.Service
	box(m, "RentalStand", f, sv.X - 2.5, sv.X + 2.5, TOP, 3.6, sv.Z + 1.1, sv.Z + 2.3, K.TEAK, planks)
	box(m, "RentalTop", f, sv.X - 2.7, sv.X + 2.7, 3.6, 3.9, sv.Z + 0.9, sv.Z + 2.5, K.WORKTOP, Enum.Material.Marble, DETAIL)
	for _, x in ipairs({ sv.X - 2.2, sv.X + 2.2 }) do
		post(m, "StandPost", f, x, sv.Z + 2.1, 3.9, 4.6, 0.3, C.DARK_METAL, metal, DETAIL)
	end
	local rs = box(m, "RentalSign", f, sv.X - 2.6, sv.X + 2.6, 6.2, 8.5, sv.Z + 1.95, sv.Z + 2.15, accent, wood, DETAIL)
	Build.signGui(rs, front, "JET SKI RENTALS", string.format("%s · %d MIN · NO LICENCE", A.money(def.Service and def.Service.Price or 0),
		math.floor(RE.Seconds / 60)), C.WHITE, C.GOLD, true)
	local skiBoard = box(m, "RentalBoard", f, -17.3, -3.2, 0.6, 1.8, -12.95, -12.8, K.NAVY, smooth, DETAIL)
	Build.signGui(skiBoard, back, "RENTAL JET SKIS", nil, C.WHITE)

	-- THE FRONT DECK: a palm, benches, a life ring; the TOURS DEPART HERE sign at the main pier -----------------
	Build.planterPalm(m, f, -24, -17.5, 14)
	for _, x in ipairs({ -21, -25 }) do
		box(m, "BenchSeat", f, x - 1.4, x + 1.4, 1.5, 1.8, -23.6, -22.4, K.TEAK, planks, DETAIL)
		box(m, "BenchBack", f, x - 1.4, x + 1.4, 1.8, 3.2, -22.5, -22.3, K.TEAK, planks, DETAIL)
		box(m, "BenchLeg", f, x - 1.2, x + 1.2, TOP, 1.5, -23.4, -22.6, C.DARK_METAL, metal, DETAIL)
	end
	for _, x in ipairs({ -2.3, 2.3 }) do
		post(m, "TourSignPost", f, x, -11.6, TOP, 6.2, 0.25, C.DARK_METAL, metal, DETAIL)
	end
	local depart = box(m, "TourSign", f, -2.4, 2.4, 4.4, 6.2, -11.75, -11.6, accent, wood, DETAIL)
	Build.signGui(depart, front, "TOURS DEPART HERE", "ALL ABOARD!", C.WHITE, C.GOLD, true)
	-- Lamps along the main pier and on the fingers' ends, a life ring on its post, a flag at the pier's end.
	for _, l in ipairs({ { 2.6, -2 }, { -2.6, 10 }, { 2.6, 21 }, { -18.75, 7 }, { 17.25, 19 } }) do
		post(m, "LampPost", f, l[1], l[2], TOP, 6, 0.3, C.DARK_METAL, metal, DETAIL)
		Build.lamp(m, f, l[1] - 0.45, l[1] + 0.45, 6, 6.7, l[2] - 0.45, l[2] + 0.45, 22)
	end
	post(m, "RingPost", f, -2.5, 4, TOP, 3.6, 0.25, K.TRIM, wood, DETAIL)
	local ring = Build.part(m, "LifeRing", Vector3.new(0.35, 2.2, 2.2), f * CFrame.new(-2.5, 2.6, 4.25), K.RING, smooth, DETAIL)
	ring.Shape = Enum.PartType.Cylinder
	post(m, "FlagPole", f, 0, 22, TOP, 12, 0.3, K.TRIM, metal, DETAIL)
	box(m, "Flag", f, 0.15, 3.6, 10, 12, 21.9, 22.1, accent, fabric, DETAIL)

	-- LEVEL 1 (only): a chalkboard at the hut. LEVELS 1-4: the dinghy in the west berth ---------------------------
	local chalkG = group(m, "Hut1", 1, 1)
	local chalk = Build.part(chalkG, "Chalkboard", Vector3.new(2.4, 3, 0.2), f * CFrame.new(10, 1.7, -23.6) * CFrame.Angles(math.rad(-12), 0, 0),
		C.DARK, smooth, DETAIL)
	Build.signGui(chalk, front, "BOAT TOURS", "TICKETS HERE", C.WHITE, C.GOLD, true)
	boatProp(A, group(m, "Boat1", 1, 4), f, -24, -3, 12, 5, Color3.fromRGB(110, 170, 210), K.TRIM, false)

	-- LEVEL 2: a second boat (levels 2-4) and the proper ticket booth --------------------------------------------
	boatProp(A, group(m, "Boat2", 2, 4), f, -24, 13, 15, 6, K.HULL, accent, true)
	local booth2 = group(m, "Booth2", 2, nil)
	for i = 0, 3 do
		local x = 15.4 + i * 0.85
		Build.part(booth2, "Awning", Vector3.new(0.85, 0.2, 2.6), f * CFrame.new(x + 0.425, 7.2, bz0 - 1.1) * CFrame.Angles(math.rad(18), 0, 0),
			i % 2 == 0 and accent or K.CANVAS, fabric, SHADE)
	end
	local tickets = box(booth2, "TicketsSign", f, 15.6, 18.4, 6.6, 7.6, bz0 - 0.15, bz0 - 0.02, C.DARK, smooth, DETAIL)
	Build.signGui(tickets, front, "TICKETS", nil, C.GOLD)
	neon(booth2, f, 15.6, 18.4, 7.6, 7.7, bz0 - 0.15, bz0 - 0.02, glow)
	box(booth2, "BrochureRack", f, 8.9, 10.9, TOP, 4, bz0 - 0.7, bz0 - 0.2, C.STEEL, metal, DETAIL)
	for i = 0, 2 do
		box(booth2, "Brochure", f, 9.1 + i * 0.6, 9.5 + i * 0.6, 2.6, 3.6, bz0 - 0.75, bz0 - 0.68,
			({ accent, C.GOLD, glow })[i + 1], smooth, DETAIL)
	end
	post(booth2, "BoothFlagPole", f, 18.6, -14.6, BH + 0.6, 6, 0.2, K.TRIM, metal, DETAIL)
	box(booth2, "BoothFlag", f, 18.7, 21, BH + 5, BH + 6.4, -14.7, -14.5, glow, fabric, DETAIL)

	-- LEVEL 3: jet skis (a floating jet ski dock in the east berth) and string lights along the main pier ---------
	local skis = group(m, "JetSkis3", 3, nil)
	box(skis, "SkiDock", f, 19.2, 27.5, -0.7, 0.05, -12.5, -11, K.DECK, planks, DETAIL)
	for i, x in ipairs({ 20.6, 23.4, 26.2 }) do
		skiProp(A, skis, f, x, -6.5, ({ C.PINK, glow, C.GOLD })[i])
	end
	post(skis, "FleetFlagPole", f, 27, -11.8, 0.05, 7, 0.2, K.TRIM, metal, DETAIL)
	local fleet = box(skis, "FleetFlag", f, 24.2, 26.9, 5.2, 6.9, -11.9, -11.7, C.PINK, fabric, DETAIL)
	Build.signGui(fleet, front, "JET SKIS", nil, C.WHITE, nil, true)
	neon(skis, f, -3.2, -2.95, TOP + 0.05, TOP + 0.2, -12.8, 22.8, glow) -- (LED strips along the main pier's edges)
	neon(skis, f, 2.95, 3.2, TOP + 0.05, TOP + 0.2, -12.8, 22.8, glow)

	-- LEVEL 4: the tour boat (a long canopy boat) moored in the east berth ----------------------------------------
	local tour = group(m, "TourBoat4", 4, nil)
	boatProp(A, tour, f, 23.5, 9.5, 22, 8, K.HULL, accent, true)
	local ty = K.WATER_Y + 1.85
	for _, x in ipairs({ 20.3, 26.7 }) do
		for _, z in ipairs({ 1.5, 13 }) do
			post(tour, "CanopyPost", f, x, z, ty, 5.2, 0.25, K.TRIM, metal, DETAIL)
		end
	end
	for _, b in ipairs({ { 20.4, 21.6 }, { 25.4, 26.6 } }) do
		box(tour, "Bench", f, b[1], b[2], ty, ty + 1.3, 2, 12.5, K.TEAK, planks, DETAIL)
	end
	for i = 0, 3 do
		box(tour, "Canopy", f, 19.9 + i * 1.8, 21.7 + i * 1.8, ty + 5.2, ty + 5.45, 0.8, 13.8, i % 2 == 0 and accent or K.CANVAS, fabric, SHADE)
	end
	local tourSign = box(tour, "TourBoatSign", f, 20.3, 26.7, ty + 4.1, ty + 5.2, 13.6, 13.75, K.NAVY, smooth, DETAIL)
	Build.signGui(tourSign, back, "COASTLINE TOURS", nil, C.WHITE)

	-- LEVEL 5: the luxury yacht in the west berth, gold trim on the roof sign -------------------------------------
	local yacht = group(m, "Yacht5", 5, nil)
	boatProp(A, yacht, f, -24, 5, 30, 8, K.HULL, K.NAVY, false)
	local yy = K.WATER_Y + 1.85
	box(yacht, "Cabin", f, -27, -21, yy, yy + 2.8, -5, 9, K.HULL, smooth, DETAIL)
	box(yacht, "CabinGlass", f, -27.1, -20.9, yy + 1, yy + 2.3, -4.8, 8.8, C.GLASS, Enum.Material.Glass,
		{ Transparency = 0.3, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	box(yacht, "Flybridge", f, -26.4, -21.6, yy + 2.8, yy + 3.2, -3, 5, K.HULL, smooth, DETAIL)
	box(yacht, "Radar", f, -24.4, -23.6, yy + 3.2, yy + 5, 0.6, 1.4, C.STEEL, metal, DETAIL)
	neon(yacht, f, -28.05, -27.95, K.WATER_Y + 1.25, K.WATER_Y + 1.45, -10, 16, K.GOLD_TRIM)
	neon(yacht, f, -20.05, -19.95, K.WATER_Y + 1.25, K.WATER_Y + 1.45, -10, 16, K.GOLD_TRIM)
	local name = box(yacht, "YachtName", f, -27, -21, K.WATER_Y + 0.4, K.WATER_Y + 1.2, -10.12, -10.02, K.HULL, smooth, DETAIL)
	Build.signGui(name, front, "COASTLINE", nil, K.GOLD_TRIM)
	local gold = group(m, "Gold5", 5, nil)
	neon(gold, f, bx0 - 0.1, bx1 + 0.1, BH + 5.8, BH + 6.05, bz0 - 0.4, bz0 + 0.2, K.GOLD_TRIM)
	neon(gold, f, bx0 - 0.1, bx1 + 0.1, BH + 2.55, BH + 2.8, bz0 - 0.4, bz0 + 0.2, K.GOLD_TRIM)

	return plateGui:FindFirstChild("Title")
end

------------------------------------------------------------------ tourists

-- A tourist: one of the pedestrian looks (or plain skin colours), a posed statue (no Humanoid: one welded into a
-- boat pushes it about), every part massless, not solid, invisible to rays; a sun hat; a fishing rod for a Fishing
-- Party; a gold name tag for the celebrity. Anchored at `cf` (its root part), in Workspace.NPCs.
local function makeTourist(A, cf, fishing, celeb)
	local ok, model = pcall(function()
		local looks = ReplicatedStorage:FindFirstChild("PedTemplates")
		local list = looks and looks:GetChildren() or {}
		local p = #list > 0 and list[A.rng:NextInteger(1, #list)] or nil
		if p and p:IsA("Model") and p:FindFirstChild("HumanoidRootPart") and p:FindFirstChildOfClass("Humanoid") then
			return p:Clone()
		end
		local desc = Instance.new("HumanoidDescription")
		local c = Color3.fromRGB(230, 190, 150)
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = c, c, c
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(70, 120, 170), Color3.fromRGB(70, 120, 170)
		desc.TorsoColor = Color3.fromRGB(255, 140, 120)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum:Destroy()
	end
	Instance.new("AnimationController").Parent = model
	model.Name = "BizTourist"
	model:SetAttribute("BizTourist", true)
	model:PivotTo(cf)
	-- A sun hat (a brim and a crown) and, for a Fishing Party, a rod in the right hand: welded, looks only.
	local function addOn(name, size, at, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = at
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end
	if head and head:IsA("BasePart") then
		local hat = K.HATS[A.rng:NextInteger(1, #K.HATS)]
		local top = head.CFrame * CFrame.new(0, head.Size.Y * 0.5, 0)
		local brim = addOn("HatBrim", Vector3.new(0.15, 2.2, 2.2), top * CFrame.Angles(0, 0, math.rad(90)), hat, Enum.Material.Fabric,
			Enum.PartType.Cylinder)
		local crown = addOn("HatCrown", Vector3.new(0.6, 1.25, 1.25), top * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), hat,
			Enum.Material.Fabric, Enum.PartType.Cylinder)
		for _, p in ipairs({ brim, crown }) do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, p
			w.Parent = p
		end
		if celeb then
			local tag = Instance.new("BillboardGui")
			tag.Name = "CelebTag"
			tag.Size = UDim2.fromOffset(170, 26)
			tag.StudsOffset = Vector3.new(0, 3.4, 0)
			tag.MaxDistance = 120
			tag.AlwaysOnTop = true
			local l = Instance.new("TextLabel")
			l.Size = UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBold
			l.TextScaled = true
			l.TextColor3 = Color3.fromRGB(255, 214, 10)
			l.TextStrokeTransparency = 0.4
			l.Text = "★ " .. string.upper(celeb) .. " ★"
			l.Parent = tag
			tag.Parent = head
		end
	end
	local hand = model:FindFirstChild("RightHand")
	if fishing and hand and hand:IsA("BasePart") then
		local rod = addOn("FishingRod", Vector3.new(0.15, 0.15, 7), hand.CFrame * CFrame.new(0, 0, -3.2) * CFrame.Angles(math.rad(35), 0, 0), K.ROD)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hand, rod
		w.Parent = rod
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.Anchored = false
		end
	end
	root.Anchored = true
	model.Parent = A.npcFolder()
	return model
end

-- Play one of CarBuilder's poses on a tourist ("sit" | "walk"), stopping any other.
local function pose(model, name)
	pcall(function()
		local ctl = model:FindFirstChildOfClass("AnimationController")
		local animator = ctl and ctl:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				t:Stop(0)
			end
		end
		require(ServerStorage.Tools.CarBuilder).PlayPose(model, name)
	end)
end

-- The spot a tourist waits at on the pier (its root's CFrame, facing the boat).
local function queueCFrame(def, i)
	local q = def.Layout.Queue[(i - 1) % #def.Layout.Queue + 1]
	local at = Businesses.At(def, Vector3.new(q.X, K.DECK_TOP + 3, q.Z))
	local berth = Businesses.At(def, def.Layout.Berth)
	return CFrame.lookAt(at, Vector3.new(berth.X, at.Y, berth.Z))
end

-- The seat-relative spots on this boat (Tour.Seats; the Marlin's when the boat has none of its own).
local function seatSpots(id)
	return TO.Seats[id] or TO.Seats.Marlin
end

-- Where tourist i sits on the boat (its root's CFrame), facing the bow.
local function seatCFrame(boat, i)
	local seat = boat:FindFirstChild("DriverSeat")
	local spots = seatSpots(boat:GetAttribute("VehicleId") or "")
	local s = spots[(i - 1) % #spots + 1]
	return seat.CFrame * CFrame.new(s[1], seat.Size.Y / 2 + K.SIT_UP, s[2])
end

-- Remove every tourist of this job (wherever they are).
local function clearTourists(job)
	for _, t in ipairs(job.tourists or {}) do
		if t.Parent then
			t:Destroy()
		end
	end
	job.tourists = {}
end

-- A tourist says something (a bubble over their head, for everyone; BusinessService's say).
local function sayAs(job, i, words, seconds, A)
	local t = job.tourists and job.tourists[i]
	if t and t.Parent then
		-- (one record per seat, by its number: BusinessService's say keeps its bubble's token on it)
		job.sayRec = job.sayRec or {}
		local rec = job.sayRec[i]
		if not rec or rec.model ~= t then
			rec = { model = t }
			job.sayRec[i] = rec
		end
		A.say(rec, words, seconds)
	end
end

local function shout(job, words, A)
	local n = #(job.tourists or {})
	if n > 0 then
		sayAs(job, A.rng:NextInteger(1, n), words, 1.6, A)
	end
end

-- The camera flashes: a white light on every tourist's head, three quick blinks (for everyone).
local function flashes(job)
	for i, t in ipairs(job.tourists or {}) do
		local head = t.Parent and t:FindFirstChild("Head")
		if head then
			task.delay((i - 1) * 0.12, function()
				if not head.Parent then
					return
				end
				local l = Instance.new("PointLight")
				l.Name = "CameraFlash"
				l.Color = K.FLASH
				l.Brightness = 8
				l.Range = 12
				l.Shadows = false
				l.Parent = head
				for blink = 1, 3 do
					task.delay(blink * 0.22, function()
						if l.Parent then
							l.Enabled = not l.Enabled
						end
					end)
				end
				task.delay(0.9, function()
					l:Destroy()
				end)
			end)
		end
	end
end

------------------------------------------------------------------ BOAT TOURS

-- The business's looks on its boat (Tour.Fitout): "Canopy" a striped sun canopy over the tourists' seats; "Luxury"
-- the canopy in navy and gold, gold trim along both sides. Welded, massless, never solid.
local function fitout(boat, kind, def)
	if kind ~= "Canopy" and kind ~= "Luxury" then
		return
	end
	local chassis, seat = boat.PrimaryPart, boat:FindFirstChild("DriverSeat")
	if not chassis or not seat then
		return
	end
	local spots = seatSpots(boat:GetAttribute("VehicleId") or "")
	local zMin, zMax, xMax = math.huge, -math.huge, 0
	for _, s in ipairs(spots) do
		zMin, zMax, xMax = math.min(zMin, s[2]), math.max(zMax, s[2]), math.max(xMax, math.abs(s[1]))
	end
	local base = seat.CFrame * CFrame.new(0, seat.Size.Y / 2, 0)
	local x, z0, z1, h = xMax + 1.1, zMin - 1.4, zMax + 1.4, 6
	local luxury = kind == "Luxury"
	local stripeA = luxury and K.NAVY or (def.Accent or K.NAVY)
	local stripeB = luxury and K.GOLD_TRIM or K.CANVAS
	local function add(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		p.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = chassis, p
		w.Parent = p
		p.Parent = boat
		return p
	end
	for _, sx in ipairs({ -x, x }) do
		for _, sz in ipairs({ z0, z1 }) do
			add("CanopyPost", Vector3.new(0.22, h, 0.22), base * CFrame.new(sx, h / 2, sz), K.TRIM, Enum.Material.Metal)
		end
	end
	local n = 4
	for i = 0, n - 1 do
		local w = 2 * x / n
		add("Canopy", Vector3.new(w, 0.2, z1 - z0 + 0.6), base * CFrame.new(-x + w * (i + 0.5), h, (z0 + z1) / 2), i % 2 == 0 and stripeA or stripeB,
			Enum.Material.Fabric)
	end
	if luxury then
		local size = chassis.Size
		for _, sx in ipairs({ -1, 1 }) do
			add("GoldTrim", Vector3.new(0.12, 0.2, size.Z - 2), chassis.CFrame * CFrame.new(sx * (size.X / 2 + 0.06), size.Y / 2 - 0.2, 0), K.GOLD_TRIM,
				Enum.Material.Metal)
		end
	end
end

-- The business's boat in its berth, anchored, locked to the worker. Returns true when it's there.
local function spawnBoat(player, job, A)
	local def = job.def
	local level = A.levelOf(job.owner, def)
	local id = Businesses.TourBoat(level)
	if not Vehicles.ById[id] then
		id = "Marlin"
	end
	local CarBuilder = require(ServerStorage.Tools.CarBuilder)
	local ok, boat = pcall(CarBuilder.Build, id)
	if not ok or not boat or not boat.PrimaryPart or not boat:FindFirstChild("DriverSeat") then
		warn("[BoatRentals] couldn't build a tour boat " .. tostring(id) .. ": " .. tostring(boat))
		if ok and boat then
			boat:Destroy()
		end
		A.refuse(player, def.Id, "NoBoat")
		return false
	end
	local cf = mooredAt(def, def.Layout.Berth, id)
	if not boxClear(cf, boat.PrimaryPart.Size, player) then
		boat:Destroy()
		A.refuse(player, def.Id, "BerthBlocked")
		return false
	end
	boat.Name = "TourBoat"
	boat:SetAttribute("BizTour", true)
	boat:SetAttribute("BizId", def.Id)
	local seat = lockBoat(boat, player.UserId, "Tour boat", function(p)
		if p == player and S.A then
			S.A.fire(player, "TourSeat", { Id = def.Id, Seated = true })
		end
	end)
	if not seat then
		boat:Destroy()
		A.refuse(player, def.Id, "NoBoat")
		return false
	end
	fitout(boat, Businesses.TourFitout(level), def)
	job.car = boat -- (set before anything below can fail: BusinessService's endJob always finds and removes it)
	job.boatId = id
	boat.PrimaryPart.Anchored = true
	boat:PivotTo(cf)
	boat.Parent = Workspace.Vehicles
	local guard = A.service("VehicleGuard")
	if guard and type(guard.Allow) == "function" then
		guard.Allow(boat, 3)
	end
	return true
end

-- The tour's numbers to the worker (the shift's "Tour" event: board or after).
local function sendTour(player, job, A, stage)
	local stops = {}
	for i, s in ipairs(job.stops or {}) do
		stops[i] = { Name = s.Name, Pos = s.Pos, Line = s.Line, Kind = s.Kind }
	end
	local def = job.def
	A.fire(player, "Tour", {
		Id = job.id, Stage = stage, Level = A.levelOf(job.owner, def), Owner = job.owner.UserId, OwnerName = job.owner.DisplayName,
		Count = job.count, Earned = job.earned, Streak = job.tourStreak or 0, Boat = job.car, Route = job.route and job.route.Name,
		RouteId = job.route and job.route.Id, Stops = stops, Mouth = Businesses.At(def, def.Layout.SlipMouth),
		Dock = Businesses.At(def, def.Layout.Dock), Berth = Businesses.At(def, def.Layout.Berth), Special = job.special, Celeb = job.celeb,
		Par = job.par, Length = job.length, Tourists = #(job.tourists or {}), Tours = job.tours or 0,
		Seated = job.car ~= nil and atHelm(player, job.car, A),
	})
end

-- Studio only: the special tour or route this player's next tour should be (player attributes BizTestTour /
-- BizTestRoute, used up here).
local function takeTest(player, name, valid)
	if not RunService:IsStudio() then
		return nil
	end
	local v = player:GetAttribute(name)
	if type(v) ~= "string" or not valid(v) then
		return nil
	end
	player:SetAttribute(name, nil)
	return v
end

-- A new tour (stage "board"): its route, special, tourists waiting on the pier. The worker is seated if they're
-- on foot nearby (NEXT TOUR after getting out).
local function setupTour(player, job, A)
	local def = job.def
	local level = A.levelOf(job.owner, def)
	local night = Businesses.SunsetTime(Lighting.ClockTime, Workspace:GetAttribute("IsNight"))
	job.special = takeTest(player, "BizTestTour", function(v)
		return TO.Specials[v] ~= nil
	end) or Businesses.RollTourSpecial(A.rng:NextNumber(), A.rng:NextNumber(), night)
	local sp = job.special and TO.Specials[job.special]
	local routeId = takeTest(player, "BizTestRoute", function(v)
		return Businesses.TourRoute(v) ~= nil
	end)
	job.route = (sp and sp.Route and Businesses.TourRoute(sp.Route)) or (routeId and Businesses.TourRoute(routeId))
		or Businesses.PickRoute(level, A.rng:NextNumber(), A.rng:NextNumber())
	job.stops = Businesses.TourStops(job.route)
	job.length = Businesses.TourLength(def, job.route)
	job.par = Businesses.TourPar(job.length, Businesses.TourStopCount(job.route), sp and sp.ParMult)
	job.celeb = job.special == "Celebrity" and K.CELEBS[A.rng:NextInteger(1, #K.CELEBS)] or nil
	job.leg, job.grades, job.photo = 1, {}, nil
	job.mood, job.moodSent = 1, 100
	job.stage = "board"
	job.boarding = false
	job.boardToken = (job.boardToken or 0) + 1
	job.outSince = nil
	job.boardSince = os.clock()
	player:SetAttribute("BizTourHappy", 100)
	clearTourists(job)
	local n = math.min(Businesses.TourTourists(level), #seatSpots(job.boatId or "Marlin"))
	for i = 1, n do
		local t = makeTourist(A, queueCFrame(def, i), job.special == "Fishing", i == 1 and job.celeb or nil)
		if t then
			table.insert(job.tourists, t)
			pose(t, "walk")
		end
	end
	-- Back at the helm for the next tour, if they got out at the dock and are still close by.
	local boat = job.car
	local hum, root = A.humOf(player), A.rootOf(player)
	local seat = boat and boat:FindFirstChild("DriverSeat")
	if seat and hum and root and hum.Health > 0 and hum.SeatPart == nil and seat.Occupant == nil
		and (root.Position - seat.Position).Magnitude <= K.SEAT_SEARCH then
		seat:Sit(hum)
	end
	sendTour(player, job, A, "board")
end

-- All aboard: the boat is let go and the clock starts.
local function go(player, job, A)
	local boat = job.car
	local chassis = boat and boat.PrimaryPart
	if not chassis then
		return
	end
	job.stage = "tour"
	job.goAt = os.clock()
	local root = chassis.Position
	job.lastPos, job.lastT, job.lastSpeed = flat(root), job.goAt, 0
	job.legFrom, job.legAt = flat(root), job.goAt
	job.top = topSpeed(boat)
	job.lastRamAt, job.lastSayAt, job.beachAt, job.aground = -math.huge, 0, 0, false
	job.bumpedAt = boat:GetAttribute("BumpedAt")
	job.lastYaw = nil
	local guard = A.service("VehicleGuard")
	if guard and type(guard.Allow) == "function" then
		guard.Allow(boat, 3)
	end
	chassis.Anchored = false
	local driver = boat:GetAttribute("DriverUserId")
	local p = driver and Players:GetPlayerByUserId(driver)
	if p then
		pcall(function()
			chassis:SetNetworkOwner(p)
		end)
	end
	A.fire(player, "TourGo", { Id = job.id, Par = job.par })
	Telemetry.Custom(player, "BizTourStart_" .. job.id .. "_" .. tostring(job.route and job.route.Id), 1)
end

-- The tourists hop aboard one by one, then go (a thread; a newer tour or the job's end stops it).
local function board(player, job, A)
	job.boarding = true
	local token = job.boardToken
	task.spawn(function()
		local function live()
			return A.jobOf(player) == job and job.boardToken == token and job.car ~= nil and job.car.Parent ~= nil
		end
		for i, t in ipairs(job.tourists) do
			if not live() then
				return
			end
			local root = t:FindFirstChild("HumanoidRootPart")
			if root and t.Parent then
				local to = seatCFrame(job.car, i)
				local from = root.CFrame
				local mid = CFrame.new((from.Position + to.Position) / 2 + Vector3.new(0, 2.2, 0)) * to.Rotation
				local tw = TweenService:Create(root, TweenInfo.new(K.BOARD_HOP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = mid })
				tw:Play()
				tw.Completed:Wait()
				if not live() then
					return
				end
				local tw2 = TweenService:Create(root, TweenInfo.new(K.BOARD_HOP, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = to })
				tw2:Play()
				tw2.Completed:Wait()
				if not live() then
					return
				end
				-- Welded to the hull (the boat is still anchored): part of the boat from here on.
				local chassis = job.car.PrimaryPart
				local w = Instance.new("WeldConstraint")
				w.Name = "TouristWeld"
				w.Part0, w.Part1 = chassis, root
				w.Parent = root
				root.Anchored = false
				t.Parent = job.car
				pose(t, "sit")
			end
			task.wait(TO.BoardEach)
		end
		task.wait(TO.BoardExtra)
		if live() and job.stage == "board" then
			go(player, job, A)
		end
	end)
end

-- The leg just finished passed the speed check (as a taxi fare's)? Ends the shift ("Invalid") when not.
local function legOk(player, job, t, cp, A)
	local took = t - (job.legAt or t)
	local gap = math.max(0, (flat(cp) - (job.legFrom or flat(cp))).Magnitude - TO.Radius)
	local fastest = gap / (math.max(job.top or 0, 1) * TO.FastSlack)
	local guard = A.service("VehicleGuard")
	if took < fastest or (guard and type(guard.RecentlyFlagged) == "function" and guard.RecentlyFlagged(player, took)) then
		warn(string.format("[BoatRentals] refused %s's tour leg: %.2fs (at least %.2fs)", player.Name, took, fastest))
		A.endJob(player, "Invalid")
		return false
	end
	return true
end

-- The tourists step off onto the pier, cheer and fade (stars: what they say); then the AFTER panel.
local function unboard(player, job, stars, A)
	local token = job.boardToken
	task.spawn(function()
		task.wait(TO.GlideTime)
		if A.jobOf(player) ~= job or job.boardToken ~= token then
			return
		end
		local def = job.def
		local words = K.CHEERS[math.clamp(stars, 1, 3)]
		for i, t in ipairs(job.tourists) do
			local root = t.Parent and t:FindFirstChild("HumanoidRootPart")
			if root then
				local w = root:FindFirstChild("TouristWeld")
				if w then
					w:Destroy()
				end
				root.Anchored = true
				t.Parent = A.npcFolder()
				pose(t, "walk")
				local to = queueCFrame(def, i)
				local mid = CFrame.new((root.Position + to.Position) / 2 + Vector3.new(0, 2.2, 0)) * to.Rotation
				local tw = TweenService:Create(root, TweenInfo.new(K.BOARD_HOP, Enum.EasingStyle.Quad), { CFrame = mid })
				tw:Play()
				task.delay(K.BOARD_HOP, function()
					if root.Parent then
						TweenService:Create(root, TweenInfo.new(K.BOARD_HOP, Enum.EasingStyle.Quad), { CFrame = to }):Play()
					end
				end)
				-- The cheer: a hop on the spot, and a word.
				task.delay(K.BOARD_HOP * 2 + 0.1 + i * 0.1, function()
					if root.Parent then
						TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 1, true),
							{ CFrame = to * CFrame.new(0, 1.4, 0) }):Play()
					end
				end)
				if i <= 3 then
					task.delay(K.BOARD_HOP * 2 + i * 0.25, function()
						sayAs(job, i, words[A.rng:NextInteger(1, #words)], 1.8, A)
					end)
				end
			end
		end
		task.wait(TO.UnboardTime)
		if A.jobOf(player) ~= job or job.boardToken ~= token then
			return
		end
		for _, t in ipairs(job.tourists) do
			if t.Parent then
				A.fadeOut(t, 0.6)
			end
		end
		job.tourists = {}
		job.stage = "after"
		job.afterSince = os.clock()
		sendTour(player, job, A, "after")
	end)
end

-- Stopped in the dock ring: the boat glides into its berth and the tour is paid (see the header).
local function dock(player, job, t, A)
	local boat = job.car
	local chassis = boat.PrimaryPart
	local def = job.def
	job.stage = "dock"
	job.outSince = nil
	local guard = A.service("VehicleGuard")
	if guard and type(guard.Allow) == "function" then
		guard.Allow(boat, TO.GlideTime + 3)
	end
	chassis.Anchored = true
	local berth = mooredAt(def, def.Layout.Berth, job.boatId or "Marlin")
	TweenService:Create(chassis, TweenInfo.new(TO.GlideTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = berth }):Play()
	player:SetAttribute("BizTourHappy", nil)
	-- The pay (all decided here).
	local level = A.levelOf(job.owner, def)
	local took = t - (job.goAt or t)
	local hadStreak = job.tourStreak or 0
	local pay, tip, stars, streak, bonus, share = Businesses.TourPay(def, level, {
		length = job.length, grades = job.grades, took = took, par = job.par, mood = job.mood, special = job.special, streak = hadStreak,
	})
	job.tourStreak = streak
	local total = pay + tip + bonus
	EconomyService.AddCash(player, total, "bizjob:" .. job.id .. ":tour")
	job.count += 1
	job.earned += total
	job.tours = (job.tours or 0) + 1
	local st = job.stats
	st.tours += 1
	st.stars3 += stars == 3 and 1 or 0
	st.best = math.max(st.best, streak)
	st.specials += job.special and 1 or 0
	st.tourists += #(job.tourists or {})
	st.moodSum += job.mood
	for _, g in ipairs(job.grades) do
		st.photos += 1
		st.perfects += g == "Perfect" and 1 or 0
		st.missed += g == "Missed" and 1 or 0
	end
	st.route = job.route and job.route.Name
	A.creditOwner(job, player, total)
	A.addEmpireXP(player, E.XP.Tour)
	A.progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizTour_" .. job.id, total)
	local grades = table.clone(job.grades)
	A.fire(player, "TourPaid", {
		Id = job.id, Pay = pay, Tip = tip, Bonus = bonus, Stars = stars, Streak = streak, Mult = Businesses.StreakMult(streak, Businesses.Streak),
		Broke = hadStreak >= 2 and streak == 0 and hadStreak or nil, Special = job.special, Celeb = job.celeb, Mood = job.mood, Took = took,
		Par = job.par, OnTime = took <= job.par, Grades = grades, Share = share, Route = job.route and job.route.Name, Count = job.count,
		Earned = job.earned,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
	unboard(player, job, stars, A)
end

-- Four times a second on a tour (stage "tour"): the mood, the stops, the dock.
local function tourTick(player, job, t, A)
	local boat = job.car
	local chassis = boat.PrimaryPart
	if not atHelm(player, boat, A) then
		job.outSince = job.outSince or t
		if t - job.outSince > TO.LeaveGrace then
			A.endJob(player, "LeftBoat")
		end
		job.lastPos, job.lastT, job.lastSpeed, job.lastYaw = flat(chassis.Position), t, 0, nil
		return
	end
	job.outSince = nil
	local pos = flat(chassis.Position)
	if pos.X ~= pos.X or pos.Z ~= pos.Z then
		return -- (a NaN position: broken physics; wait for a real one)
	end
	local dt = math.max(t - (job.lastT or t), 0.05)
	local speed = flat(chassis.AssemblyLinearVelocity).Magnitude
	job.top = math.max(job.top or 0, topSpeed(boat))
	-- THE MOOD: the turn (heading change x speed), rams, running aground.
	local look = flat(chassis.CFrame.LookVector)
	local yaw = look.Magnitude > 0.1 and math.atan2(look.X, look.Z) or nil
	local lat = 0
	if yaw and job.lastYaw then
		local d = (yaw - job.lastYaw + math.pi) % (2 * math.pi) - math.pi
		lat = speed * math.abs(d) / dt
	end
	job.lastYaw = yaw
	local M = TO.Mood
	local ram = false
	local last = job.lastSpeed or 0
	if last >= M.RamMinSpeed and (last - speed) / dt >= M.RamDecel and speed < last * 0.5 and t - job.lastRamAt >= M.RamGap then
		ram = true
	end
	local bumped = boat:GetAttribute("BumpedAt")
	if bumped ~= job.bumpedAt then
		job.bumpedAt = bumped
		if t - job.lastRamAt >= M.RamGap then
			ram = true
		end
	end
	if ram then
		job.lastRamAt = t
	end
	local newlyAground = false
	if t - job.beachAt >= K.BEACH_CHECK then
		job.beachAt = t
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { boat }
		for _, name in ipairs({ "NPCs", "Vehicles" }) do
			local folder = Workspace:FindFirstChild(name)
			if folder then
				table.insert(ignore, folder)
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		params.IgnoreWater = false
		local hit = Workspace:Raycast(chassis.Position + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), params)
		local aground = hit ~= nil and hit.Material ~= Enum.Material.Water
		newlyAground = aground and not job.aground
		job.aground = aground
	end
	local mood, drop = Businesses.TourMood(job.mood, dt, lat, ram, job.aground, newlyAground)
	job.mood = mood
	local pct = math.floor(mood * 100 + 0.5)
	if math.abs(pct - (job.moodSent or 100)) >= K.MOOD_STEP * 100 then
		job.moodSent = pct
		player:SetAttribute("BizTourHappy", pct)
	end
	-- (a hard turn drains a little every check: what it has drained lately decides when a tourist shouts)
	job.drained = (job.drained or 0) * 0.8 + ((ram or newlyAground) and 0 or drop)
	local why = (newlyAground and "Beach") or (ram and "Ram") or (job.drained >= M.Say and "Turn") or nil
	if why and t - job.lastSayAt >= K.SAY_GAP then
		job.lastSayAt = t
		job.drained = 0
		shout(job, pick(K.SHOUTS[why], A), A)
		A.fire(player, "TourMood", { Id = job.id, Mood = mood, Why = why })
	end
	-- THE STOPS, in order.
	local s = job.stops[job.leg]
	if s then
		if s.Kind == "Pass" then
			if Businesses.TourReached(job.lastPos, pos, s.Pos, TO.Radius) then
				if not legOk(player, job, t, s.Pos, A) then
					return
				end
				job.legFrom, job.legAt = pos, t
				job.leg += 1
				A.fire(player, "TourStop", { Id = job.id, Index = job.leg - 1, Next = job.stops[job.leg] and job.leg or nil })
			end
		elseif not job.photo then
			if Businesses.TourReached(job.lastPos, pos, s.Pos, TO.Radius) then
				if not legOk(player, job, t, s.Pos, A) then
					return
				end
				job.legFrom, job.legAt = pos, t
				job.photo = { hold = 0, steady = 0, entered = true }
				A.fire(player, "TourPhotoOn", { Id = job.id, Index = job.leg, Kind = s.Kind })
			end
		else
			local rule = s.Kind == "Fish" and TO.Fish or TO.Photo
			local inside = (pos - flat(s.Pos)).Magnitude <= TO.Radius + rule.Slack
			local grade
			job.photo, grade = Businesses.PhotoStep(job.photo, dt, inside, speed, s.Kind)
			if grade then
				table.insert(job.grades, grade)
				job.photo = nil
				job.legFrom, job.legAt = pos, t
				job.leg += 1
				if grade ~= "Missed" then
					flashes(job)
				end
				A.fire(player, "TourPhoto", { Id = job.id, Index = job.leg - 1, Grade = grade, Kind = s.Kind, Next = job.stops[job.leg] and job.leg or nil })
			end
		end
	else
		-- Every stop done: stop in the dock ring.
		local dockAt = flat(Businesses.At(job.def, job.def.Layout.Dock))
		if (pos - dockAt).Magnitude <= TO.DockRadius and speed < TO.DockSpeed then
			if not legOk(player, job, t, dockAt, A) then
				return
			end
			dock(player, job, t, A)
			return
		end
	end
	job.lastPos, job.lastT, job.lastSpeed = pos, t, speed
end

function BoatRentals.Start(player, job, A)
	job.tours = 0
	job.tourStreak = 0
	job.tourists = {}
	job.stats = { tours = 0, stars3 = 0, best = 0, specials = 0, tourists = 0, moodSum = 0, photos = 0, perfects = 0, missed = 0 }
	if not spawnBoat(player, job, A) then
		A.endJob(player, "NoBoat")
		return
	end
	setupTour(player, job, A)
	-- At the helm straight away (the berth is a short walk from the door; Tick waits BoardGrace for the walk).
	local hum = A.humOf(player)
	local boat = job.car
	task.defer(function()
		local seat = boat and boat.Parent and boat:FindFirstChild("DriverSeat")
		if A.jobOf(player) == job and seat and seat.Occupant == nil and hum and hum.Parent and hum.Health > 0 and hum.SeatPart == nil then
			seat:Sit(hum)
		end
	end)
end

function BoatRentals.Resend(player, job, A)
	if job.stage == "tour" then
		sendTour(player, job, A, "board")
		A.fire(player, "TourGo", { Id = job.id, Par = job.par, Leg = job.leg, Resend = true })
	else
		sendTour(player, job, A, job.stage == "after" and "after" or "board")
	end
end

-- RequestBusiness("Step", "Next"): NEXT TOUR at the dock (after the tourists stepped off).
function BoatRentals.Step(player, job, step, A)
	if step == "Next" and (job.stage == "after" or (job.stage == "dock" and #(job.tourists or {}) == 0)) then
		setupTour(player, job, A)
	end
end

-- Four times a second (BusinessService's jobsTick, after its own end rules).
function BoatRentals.Tick(player, job, t, A)
	local boat = job.car
	local chassis = boat and boat.Parent and boat.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
		A.endJob(player, "BoatGone")
		return
	end
	if job.stage == "tour" then
		tourTick(player, job, t, A)
	elseif job.stage == "board" then
		if atHelm(player, boat, A) then
			job.outSince = nil
			if not job.boarding then
				board(player, job, A)
			end
		elseif t - (job.boardSince or t) > TO.BoardGrace then
			A.endJob(player, "LeftBoat")
		end
	elseif job.stage == "after" or job.stage == "dock" then
		-- Between tours at the dock: wander a little if you like, but not off, and not for ever.
		local root = A.rootOf(player)
		if not root or (root.Position - chassis.Position).Magnitude > TO.LeaveRange then
			job.outSince = job.outSince or t
			if t - job.outSince > TO.LeaveGrace then
				A.endJob(player, "LeftBoat")
				return
			end
		else
			job.outSince = nil
		end
		if job.stage == "after" and t - (job.afterSince or t) > TO.IdleTime then
			A.endJob(player, "Idle")
		end
	end
end

-- The shift's end (any reason): the tourists go (BusinessService removes the boat), and the report's numbers.
function BoatRentals.End(player, job, _reason, _A)
	job.boardToken = (job.boardToken or 0) + 1 -- (stops a boarding or unboarding in progress)
	clearTourists(job)
	if player.Parent == Players then
		player:SetAttribute("BizTourHappy", nil)
	end
	local st = job.stats or {}
	return {
		Report = {
			Tours = st.tours or 0, Stars3 = st.stars3 or 0, Photos = st.photos or 0, Perfects = st.perfects or 0, Missed = st.missed or 0,
			Best = st.best or 0, Specials = st.specials or 0, Tourists = st.tourists or 0,
			Happy = (st.tours or 0) > 0 and math.floor((st.moodSum or 0) / st.tours * 100 + 0.5) or nil, Route = st.route,
		},
	}
end

------------------------------------------------------------------ THE JET SKI RENTAL

-- A rental slot with nothing in it, as its index and its CFrame (nil when both are busy).
local function freeSlot(def, size, buyer)
	for i, spot in ipairs(def.Layout.Rentals or {}) do
		local cf = mooredAt(def, spot, RE.Vehicle)
		if boxClear(cf, size, buyer) then
			return i, cf
		end
	end
	return nil, nil
end

-- A rental is over: the renter is put off, the jet ski goes, and they're told why (why = nil: silently).
local function endRental(userId, why)
	local rec = S.rentals[userId]
	S.rentals[userId] = nil
	if not rec then
		return
	end
	local boat = rec.boat
	if boat and boat.Parent then
		local vs = S.A and S.A.service("VehicleService")
		if vs and type(vs.EjectAll) == "function" then
			pcall(vs.EjectAll, boat)
		end
		task.delay(0.15, function()
			if boat.Parent then
				boat:Destroy()
			end
		end)
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("BizRentalUntil", nil)
		if why and S.A then
			S.A.result(player, { Kind = "RentalOver", Id = rec.def and rec.def.Id, Why = why, Label = RE.Label })
		end
	end
end

-- BizServicePrompt at the JET SKI RENTALS stand (BusinessService's onService; see the header).
function BoatRentals.Service(player, def, A)
	local hum, root = A.humOf(player), A.rootOf(player)
	if not hum or hum.Health <= 0 or not root or player:GetAttribute("Side") == "Prisoner" then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		A.refuse(player, def.Id, "RentCivOnly")
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then
		A.refuse(player, def.Id, "RentWanted")
		return
	end
	if hum.SeatPart then
		A.refuse(player, def.Id, "RentOnFoot")
		return
	end
	local spot = Businesses.At(def, def.Layout.Service)
	if flat(root.Position - spot).Magnitude > RE.Reach or math.abs(root.Position.Y - spot.Y) > 12 then
		A.refuse(player, def.Id, "TooFar")
		return
	end
	local rec = S.rentals[player.UserId]
	if rec and rec.boat and rec.boat.Parent then
		A.refuse(player, def.Id, "RentAlready")
		return
	end
	if rec then
		endRental(player.UserId, nil)
	end
	-- The jet ski first (a slot must be free); the money only once it exists.
	local CarBuilder = require(ServerStorage.Tools.CarBuilder)
	local ok, boat = pcall(CarBuilder.Build, RE.Vehicle)
	if not ok or not boat or not boat.PrimaryPart or not boat:FindFirstChild("DriverSeat") then
		warn("[BoatRentals] couldn't build a rental " .. tostring(RE.Vehicle) .. ": " .. tostring(boat))
		if ok and boat then
			boat:Destroy()
		end
		A.refuse(player, def.Id, "RentBusy")
		return
	end
	local slot, cf = freeSlot(def, boat.PrimaryPart.Size, player)
	if not slot then
		boat:Destroy()
		A.refuse(player, def.Id, "RentBusy")
		return
	end
	local price = def.Service.Price
	local paid, paidTo = A.serveCustomer(player, def, price, "bizrental")
	if not paid then
		boat:Destroy()
		return
	end
	boat.Name = "RentalJetSki"
	boat:SetAttribute("BizRental", true)
	boat:SetAttribute("BizId", def.Id)
	local untilT = serverNow() + RE.Seconds / math.max(A.timeScale(), 0.01)
	boat:SetAttribute("BizRentalUntil", untilT)
	local seat = lockBoat(boat, player.UserId, RE.Label .. " (rented)", nil)
	boat:PivotTo(cf)
	boat.Parent = Workspace.Vehicles
	local guard = A.service("VehicleGuard")
	if guard and type(guard.Allow) == "function" then
		guard.Allow(boat, 3)
	end
	S.rentals[player.UserId] = { boat = boat, untilT = untilT, warned = false, outSince = nil, def = def }
	player:SetAttribute("BizRentalUntil", untilT)
	if seat and hum.Parent and hum.Health > 0 and hum.SeatPart == nil then
		seat:Sit(hum)
	end
	A.result(player, { Kind = "Rented", Id = def.Id, Price = price, Until = untilT, Owner = paidTo, Label = RE.Label })
	Telemetry.Custom(player, "BizRental_" .. def.Id, price)
end

-- Once a second: every rental's clock, its warning, a renter off it too long or arrested, a jet ski gone.
function BoatRentals.Second(_dt, A)
	local now = serverNow()
	local t = os.clock()
	for userId, rec in pairs(S.rentals) do
		local player = Players:GetPlayerByUserId(userId)
		local boat = rec.boat
		if not player then
			endRental(userId, nil)
		elseif not boat or not boat.Parent or not boat.PrimaryPart or boat.PrimaryPart.Position.Y < -60 then
			endRental(userId, "Gone")
		elseif player:GetAttribute("Side") == "Prisoner" then
			endRental(userId, "Arrested")
		else
			local left = Businesses.RentalLeft(rec.untilT, now)
			if left <= 0 then
				endRental(userId, "Time")
			else
				if not rec.warned and left <= RE.Warn then
					rec.warned = true
					A.result(player, { Kind = "RentalWarn", Id = rec.def and rec.def.Id, Left = left, Label = RE.Label })
				end
				local seat = boat:FindFirstChild("DriverSeat")
				local hum = A.humOf(player)
				if seat and hum and seat.Occupant == hum then
					rec.outSince = nil
				else
					rec.outSince = rec.outSince or t
					if t - rec.outSince > RE.LeaveGrace then
						endRental(userId, "Left")
					end
				end
			end
		end
	end
end

function BoatRentals.Init(A)
	S.A = A
	siteDef()
end

function BoatRentals.PlayerLeft(player, _A)
	endRental(player.UserId, nil)
end

-- Studio helpers (BusinessService.Debug): "tour", "route", "mood", "rentleft" (see the header).
function BoatRentals.Debug(player, cmd, _id, value, A)
	if cmd == "tour" then
		local v = tostring(value or "")
		if v == "" or v == "none" then
			player:SetAttribute("BizTestTour", nil)
			return "next tour: whatever the roll says"
		end
		if not TO.Specials[v] then
			return "tour: Celebrity, Fishing or Sunset (\"\" clears it)"
		end
		player:SetAttribute("BizTestTour", v) -- (an attribute, not a table keyed by the player: used up by the next tour)
		return "your next tour is a " .. TO.Specials[v].Name
	elseif cmd == "route" then
		local v = tostring(value or "")
		if not Businesses.TourRoute(v) then
			local ids = {}
			for _, r in ipairs(TO.Routes) do
				table.insert(ids, r.Id)
			end
			return "route: " .. table.concat(ids, ", ")
		end
		player:SetAttribute("BizTestRoute", v)
		return "your next tour's route: " .. Businesses.TourRoute(v).Name
	elseif cmd == "mood" then
		local job = A.jobOf(player)
		if not job or job.mod ~= BoatRentals then
			return "not on a boat tour"
		end
		job.mood = math.clamp(tonumber(value) or 1, 0, 1)
		return string.format("tourists' mood %d%%", math.floor(job.mood * 100 + 0.5))
	elseif cmd == "rentleft" then
		local rec = S.rentals[player.UserId]
		if not rec then
			return "no jet ski rented"
		end
		rec.untilT = serverNow() + math.max(1, tonumber(value) or 70)
		if Businesses.RentalLeft(rec.untilT, serverNow()) > RE.Warn then
			rec.warned = false -- (the warning comes again at Warn seconds left)
		end
		player:SetAttribute("BizRentalUntil", rec.untilT)
		if rec.boat then
			rec.boat:SetAttribute("BizRentalUntil", rec.untilT)
		end
		return string.format("your rental ends in %ds", math.floor(rec.untilT - serverNow()))
	end
	return nil
end

return BoatRentals
