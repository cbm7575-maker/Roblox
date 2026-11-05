-- Nightclub (ModuleScript, ServerScriptService.Services.BusinessJobs.Nightclub)
-- The Afterglow Nightclub, Empire's fifth business (M5 of launch/10-BUSINESSES-PRD.md v2; unlocked at Empire rank 3;
-- every number in Config.Businesses: the Nightclub entry, NightShare, Vip, Club and BackRoom). This is BusinessService's
-- "job module" for it: it draws the club on the boardwalk, runs its job (VIP PICKUPS in the club's limo, with
-- paparazzi), its customer services (the COVER CHARGE into the club's inside, built off the map per visit, and the VIP
-- BOOTH there) and its shady BACK ROOM (dirty cash at night, WASH at the safe, police raids through the shared raid
-- engine, BusinessJobs.Raids). Everything else (owning it, its register and levels and the night x2 on it, the
-- featured-owner sign, NPC break-ins at its till, crew cuts, Empire XP, saving, the remotes, the customers' 70/30 split)
-- is BusinessService's, which calls in here with its own helpers (Api: see JOB MODULES in its header). Nothing here
-- runs unless BusinessService does (the launch switch, Config.Businesses.Live).
--
-- THE BUILDING (Nightclub.Style; Look 3.0, night-first: charcoal-plum stucco, black glass, brass, the red carpet, hot
-- pink and violet neon that only lights after dark: tag "NightNeon"). Lot space as every business lot: origin at the lot
-- centre, -Z toward the "street" (west: the boardwalk and Highway 1 beyond it), +X to the right looking at it (north).
--   * The club (x -22..22, z -4..24, 18 tall): the glass front with the doors in the middle (Layout.Door), the marquee
--     over them with the owner plate (FOR SALE · $250,000, or the featured owner's name; the client re-dresses it), the
--     AFTERGLOW roof sign. Inside: the lobby (the ticket counter and its till: Layout.Register, where break-in robbers
--     rummage; a small bar), and behind it the BACK ROOM (x 5..21, z 11..23: its door Layout.BackDoor, a card table,
--     the safe: Layout.Safe, the BizWashPrompt). The way into the club's hall is the cover charge (the club's inside is
--     off the map).
--   * The forecourt: the red carpet from the doors to the lot's front edge (x -2..2) between velvet ropes, the VIP mark
--     beside it (Layout.Carpet: a pink box, the limo's red-carpet stop), the LIMO bay on the other side
--     (Layout.LimoBay), the velvet rope, the bouncer and the cover charge (Layout.Service: BusinessService's
--     BizServicePrompt), the press pen (Layout.Flashes: their flashes go off as a VIP walks in), palms.
--   * LEVEL PROPS (PRD section 5's Nightclub column; child Models with MinLevel / MaxLevel, drawn per device):
--       1  a small bar and house music (the BAR · HOUSE MUSIC chalkboard; levels 1-2)
--       2  dance floor lights: colour panels glowing behind the front glass, uplights on the facade
--       3  the DJ booth on the marquee and a light show (searchlights on the roof, neon round the sign)
--       4  the VIP balcony: two wings over the marquee with lounge chairs, a glass rail and a VIP sign
--       5  a rooftop pool party: a pool on the roof, loungers, palms, string lights, a POOL PARTY sign
--   Returns the owner plate's title label (BusinessService's publishOwners writes FOR SALE / the owner).
--
-- VIP PICKUPS (Config.Businesses.Vip; JobKind "BizVip"). Started by BusinessService (START JOB > VIP PICKUPS at the
-- door: the owner, or a crewmate working for an owner in the server; the owner's level sets the limo and the pay, a
-- crewmate's pay gives the owner the 20% cut, as M1). One shift, VIP after VIP:
--   1. THE LIMO: the club's own car (Vip.Limo in Businesses.VipPaint, its fit-out Businesses.VipFitout) appears in its bay
--      (refused "LimoBlocked" when something's in it, "NoLimo" when it can't be built) with the worker at the wheel. Car
--      attributes BizCar = true, BizVip = true, BizDriverUserId, BizId; no OwnerUserId (M1's customer-car rules: no
--      garage, selling, races, taxi fares or riders); its Drive / Ride bubbles are replaced by "BizDrivePrompt" (only
--      the worker may sit; nobody else rides along). It's job.car, so BusinessService removes it with the job.
--   2. A NEW VIP (setupVip): a celebrity (Vip.Names, a special one about 1 in 8: Businesses.RollVipSpecial; Studio:
--      player attribute BizTestVip) at a pickup (pickPlace: a Vip.Homes home's verge, an apartment tower's kerb, else a
--      hotel's kerb from JobService.RoadsideSpot; Studio: BizTestPickup) waits there in the pedestrians' looks with
--      sunglasses and a gold name tag, for everyone to see. BusinessJob "Vip" { Id, Stage = "pickup", Name, Place, Kind,
--      Pos, Carpet, Special, Night, Level, Owner, OwnerName, Count, Earned, Streak, Limo, Vips }.
--   3. THE PICKUP (Tick): stopped in the ring (Vip.PickupRadius, under StopSpeed): the leg's speed check (from where it
--      began at the limo's nitro top speed x FastSlack, and VehicleGuard; failing it ends the shift, "Invalid"), then
--      the VIP walks to the limo's passenger door and gets in (VehicleService.SeatNPC). "VipAboard" { Par, Line, Pap }.
--   4. THE RIDE: THE COMFORT (Businesses.VipComfort; player attribute BizVipComfort 0-100): the turn rate from the
--      chassis's heading between checks x its speed, crashes (the speed more than halving at RamDecel+, or
--      ImpactService's BumpedAt), the limo leaving the ground (AirSpeed up or down), paparazzi flashing close by.
--      "VipComfort" { Comfort, Why = "Turn" | "Ram" | "Air" | "Flash" } with the VIP's complaint in a bubble.
--      PAPARAZZI (Businesses.PapRoll; Studio: BizTestPap): Delay seconds after boarding, Businesses.PapCars cars
--      (RaceAIService's NPC drivers, at Pap.Top, a dark SUV with PAPARAZZI over the roof and camera flashes) appear on a
--      road behind the limo and chase it (a new route every Replan seconds; easing off within Near). "VipPap" { Cars }.
--      Businesses.PapStep with the nearest one each check: LOST THEM! ("VipLost" { Bonus }) once they've all been
--      LoseDist away for LoseHold seconds; they drive off and go. (No RaceAIService.Route: no paparazzi, ever.)
--   5. THE RED CARPET: stopped in the red-carpet ring (Vip.CarpetRadius from Layout.Carpet, under StopSpeed): the leg's
--      speed check, then the stop's grade (Businesses.VipStop on the distance to the mark) and the pay:
--      Businesses.VipPay (both legs' road, the time against Businesses.VipPar, the comfort, the stop, the paparazzi
--      lost, the special, the ★★★ streak, night: Api.isNight), reason "bizjob:<id>:vip", the worker's Empire XP Vip, the
--      owner's books (jobsDone, lifetime, crew cut), "VipPaid" { Pay, Tip, Bonus, Stars, Streak, Mult, Broke, Stop,
--      Dist, Comfort, OnTime, Took, Par, Lost, Pap, Night, Special, Name, Share, Count, Earned }. The VIP steps out and
--      walks up the carpet to the doors as the press's flashes go off (lights at Layout.Flashes, for everyone), then
--      "Vip" { Stage = "after" }: NEXT VIP (RequestBusiness "Step", "Next": a new VIP from 2) or END JOB.
--   6. ENDS (BusinessJob "Ended"): out of the limo for LeaveGrace seconds on a pickup or a ride, or LeaveRange away
--      from it at the club for as long ("LeftLimo"); not in it within SeatGrace of the start ("LeftLimo"); the limo gone
--      or sunk ("LimoGone"); IdleTime at the club without a NEXT VIP ("Idle"); "Invalid"; and BusinessService's own
--      rules (END JOB, wanted, side, died, the owner leaving, another job taking JobKind). The limo goes (BusinessService),
--      the VIP and the paparazzi with it (End). Nightclub.End adds the Report { Pickups, Stars3, Perfects, Paps, Lost,
--      Best, Specials, Night, Comfort (the average at the carpet, %) }.
--
-- THE CLUB (Config.Businesses.Club; one inside per server, built off the map at Club.Origin when the first guest walks
-- in, taken down EmptyFor seconds after the last one leaves; Workspace "BizClubInterior").
--   * COVER CHARGE (Nightclub.Service, BusinessService's BizServicePrompt at the velvet rope): a citizen ("ClubCivOnly"),
--     not wanted ("ClubWanted"), on foot ("ClubOnFoot"), within Club.Reach ("TooFar"), not on a job ("ClubBusy").
--     Owners of the club and their crewmates walk in free; a pass (player attribute BizCoverUntil, server time) lets you
--     back in free; else Service.Price through Api.serveCustomer ("bizcover:<id>": the featured owner's 70%, the
--     customer-XP cap, the rest a sink) and a new pass for CoverValid. Then the trip (HouseClient's HouseFade, the area
--     streamed in, the character moved to Club.Arrive), player attribute BizClub = the business id (CombatService
--     makes it a safe zone), BusinessResult "ClubIn" { Id, Free, Price, Owner }.
--   * Inside: the dance floor (its tiles light up on the guests' devices from level 2: BusinessClient), the bar, the DJ
--     (level 3), the VIP balcony (4), the pool corner (5) as level props tagged BizProp (each device its own level), a
--     few dancing NPCs (Club.Dancers by the featured owner's level), the music (Config.Sounds' Neon FM tracks, one Sound
--     in the club's speaker: only guests hear it), the lights. The EXIT door ("BizClubExit") or LEAVE on the screen
--     (RequestBusiness "Mod", "Nightclub", "Leave") takes you back outside the doors ("ClubOut" { Why }). Wanted inside:
--     put out ("Wanted"). A respawn, an arrest, leaving the game: you're simply gone from the list.
--   * VIP BOOTH ("BizBoothPrompt" at the booth's rope inside; Nightclub.Booth): a guest, not wanted, within Club.Reach;
--     free while nobody has it ("BoothTaken" while another party does, "BoothAlready" while you and your crew do).
--     Owners of the club book free; else Booth.Price through Api.serveCustomer ("bizbooth:<id>", the words "a VIP
--     booth"). For BoothSeconds (/ BusinessTimeScale in Studio): player attribute BizBoothUntil, the booth's sign reads
--     RESERVED · <NAME> and its bucket sparkles; anyone but the holder and their crewmates who walks in is shown out to
--     Club.BoothOut ("No" BoothReserved). "BoothBooked" { Until, Price, Free, Owner }, "BoothCrew" to their crewmates,
--     "BoothWarn" { Left } at BoothWarn seconds, "BoothOver" at the end.
--
-- THE BACK ROOM (Config.Businesses.BackRoom; Nightclub.Second). Every owner online gets Businesses.BackRoomAccrue each
-- second at night (x BusinessTimeScale in Studio) into data.businesses.Nightclub.dirty. WASH ("BizWashPrompt" at the
-- safe, held WashHold seconds, timed here as the raid prompts are): the owner only ("WashNotYours"), a citizen, on foot
-- within Reach, the tills free again ("WashWait" { Left }: WashGap after the last wash, by UserId), something in the safe
-- ("BackRoomEmpty"): Businesses.BackRoomWashAmount of it into clean cash ("bizbackroom:<id>"), Empire XP BackRoom,
-- "Washed" { Amount, Dirty, Next }. POLICE RAIDS on the back-room stock: BusinessJobs.Raids, registered in Init with the
-- back room's cap and MinDirty, the back door to breach, the safe to search, the officers' way in (Layout.RaidWayIn,
-- RaidPathIn); holding the door = an owner or crewmate inside the club building (Layout.Inside).
--
-- STUDIO (Nightclub.Debug, through BusinessService.Debug): "celeb" (value "Superstar" | "Tabloid" | "Late": your next VIP;
-- "" clears it), "papz" (paparazzi on your next ride; on a ride now: they come at once), "comfort" (value 0-1), "night"
-- (value "on" | "off" | "": Workspace BizTestNight), "pickup" (value "MANSION" | "VILLA" | "PENTHOUSE" | "TOWER" | "HOTEL"),
-- "backroom" (value: your back-room stock; none = full), "washready", "booth" (value seconds: the booth's time left),
-- "club" (value "in" | "out": in or out of the club, free), and "raid" / "endraid" with id "Nightclub" (Raids.Debug).
--
-- API (BusinessService calls these; A = its Api table): Kinds, Style, Start, Resend, Step, Tick, End, Init, Second,
-- State, Alarms, Service, Request, PlayerLeft, Debug (see JOB MODULES in its header).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Housing = require(ReplicatedStorage.Shared.Config.Housing)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)
local Raids = require(script.Parent:WaitForChild("Raids"))

local Nightclub = {}

-- The job kinds this module runs, and the JobKind attribute for each (BusinessService's JOB MODULES).
Nightclub.Kinds = { Vip = "BizVip" }

local V = Businesses.Vip
local CL = Businesses.Club
local BR = Businesses.BackRoom
local RA = Businesses.Raid
local E = Businesses.Empire

-- Looks, words and constants that aren't balance (balance lives in Config.Businesses).
local K = {
	H = 18, -- the club's height (the roof slab sits on it)
	SEAT_UP = 3.4, -- a car's pivot above the lot's ground (as BusinessService)
	STUCCO = Color3.fromRGB(58, 50, 64), -- charcoal-plum stucco
	STUCCO_DARK = Color3.fromRGB(40, 35, 46),
	GLASS = Color3.fromRGB(28, 24, 36), -- black tinted glass
	FLOOR = Color3.fromRGB(38, 34, 44), -- polished dark stone
	CARPET = Color3.fromRGB(170, 22, 42), -- the red carpet
	VELVET = Color3.fromRGB(128, 16, 36),
	BRASS = Color3.fromRGB(214, 176, 92),
	FELT = Color3.fromRGB(24, 104, 66), -- the card table
	WOOD = Color3.fromRGB(86, 58, 42),
	LEATHER = Color3.fromRGB(26, 22, 28),
	SUIT = Color3.fromRGB(18, 18, 22),
	WATER = Color3.fromRGB(70, 196, 232),
	CYAN = Color3.fromRGB(60, 230, 255),
	VIOLET = Color3.fromRGB(170, 100, 255),
	WHITE_LINE = Color3.fromRGB(236, 234, 228),
	SKINS = { Color3.fromRGB(234, 192, 150), Color3.fromRGB(160, 110, 75), Color3.fromRGB(255, 220, 185), Color3.fromRGB(110, 75, 55) },
	SHIRTS = { Color3.fromRGB(255, 90, 160), Color3.fromRGB(80, 200, 255), Color3.fromRGB(250, 220, 90), Color3.fromRGB(170, 120, 220),
		Color3.fromRGB(240, 240, 240) },
	DANCES = { "rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268" }, -- Roblox's stock R15 dances
	IDLE = "rbxassetid://507766388", -- Roblox's stock R15 idle
	WALK = 8, -- studs/s a VIP walks at
	SIT_UP = 1.3, -- (as VehicleService's NPC_SEAT_UP)
	DRIVE_REACH = 14, -- studs: the limo's "Drive" bubble
	COMFORT_STEP = 0.01, -- the comfort attribute in whole percent
	SAY_GAP = 2, -- seconds between two VIP complaints
	FLASH_TIME = 1.6, -- seconds the press's flashes go off at the carpet
	MUSIC_GAP = 1, -- seconds between two music checks
	OUTSIDE = Vector3.new(-1.5, 0, -9), -- lot space: where you come out of the club (on the carpet, facing the street)
	-- What a VIP says (their bubble, for everyone).
	BOARD = { "To Afterglow, darling!", "Drive smooth. I just did my hair.", "The club, please. Fashionably late.",
		"Is that a camera? Step on it!", "Champagne's in the back, right?" },
	COMPLAIN = {
		Turn = { "Easy on the turns!", "My drink!", "Whoa, darling!", "Not the hair!" },
		Ram = { "OW! My tiara!", "Was that a car?!", "I'm suing!", "My nails!" },
		Air = { "Did we just FLY?!", "My stomach!", "Wheee... no!" },
		Flash = { "Ugh, cameras!", "No photos!", "Lose them!" },
	},
	ARRIVE = {
		[3] = { "Fabulous ride!", "Five stars, darling!", "You're hired. Forever." },
		[2] = { "Not bad at all!", "Thank you, driver!", "Lovely." },
		[1] = { "...I need a drink.", "Was that a ride or a rodeo?", "Never again." },
	},
}

local S = {
	A = nil, -- BusinessService's Api (Init)
	def = nil, -- the Config entry (Style "Nightclub")
	club = nil, -- the club's inside while it's up: { model, music, trackAt, track, sign, sparkle, emptySince, built }
	guests = {}, -- [UserId] = { char } (never an Instance key: the Nov 4 lesson)
	busy = {}, -- [UserId] = true during a trip in or out
	booth = nil, -- { userId, name, untilT (server time), warned }
	washAt = {}, -- [UserId] = os.clock() before which that owner can't WASH again
	fadeRemote = nil,
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

local function clubDef()
	if not S.def then
		for _, d in ipairs(Businesses.List) do
			if d.Style == "Nightclub" then
				S.def = d
			end
		end
	end
	return S.def
end

local function isNight(A)
	if A and type(A.isNight) == "function" then
		return A.isNight()
	end
	return Workspace:GetAttribute("IsNight") == true
end

-- The car's top speed on nitro (as JobService and VehicleGuard read it).
local function topSpeed(car)
	return (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
end

local function wanted(p)
	return (p:GetAttribute("Heat") or 0) > 0
end

-- Is this player sitting at the limo's wheel?
local function atWheel(player, limo, A)
	local hum = A.humOf(player)
	local seat = limo and limo:FindFirstChild("DriverSeat")
	return hum ~= nil and seat ~= nil and seat.Occupant == hum
end

-- Studio only: a test value on the player (BizTestVip / BizTestPickup / BizTestPap), used up here.
local function takeTest(player, name, valid)
	if not RunService:IsStudio() then
		return nil
	end
	local v = player:GetAttribute(name)
	if v == nil or not valid(v) then
		return nil
	end
	player:SetAttribute(name, nil)
	return v
end

-- Move a living character (out of any seat first), as ApartmentService does.
local function moveTo(player, cf)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hum or not root or hum.Health <= 0 then
		return false
	end
	local seat = hum.SeatPart
	if seat then
		local w = seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		hum.Sit = false
	end
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- A blocky figure (legs, body, arms, head, hair; 7 parts, looks only) standing on (x, y0, z) of a frame, turned by yaw.
local function person(A, parent, f, x, z, yaw, skin, shirt, legs, y0)
	local P, DETAIL = A.Build.part, A.DETAIL
	local base = f * CFrame.new(x, y0 or 0.2, z) * CFrame.Angles(0, yaw, 0)
	for _, s in ipairs({ -1, 1 }) do
		P(parent, "Leg", Vector3.new(0.95, 2, 1), base * CFrame.new(s * 0.5, 1, 0), legs, Enum.Material.SmoothPlastic, DETAIL)
		P(parent, "Arm", Vector3.new(0.9, 2, 0.9), base * CFrame.new(s * 1.47, 3, 0), skin, Enum.Material.SmoothPlastic, DETAIL)
	end
	P(parent, "Body", Vector3.new(2, 2, 1), base * CFrame.new(0, 3, 0), shirt, Enum.Material.Fabric, DETAIL)
	P(parent, "Head", Vector3.new(1.15, 1.15, 1.15), base * CFrame.new(0, 4.6, 0), skin, Enum.Material.SmoothPlastic, DETAIL)
	P(parent, "Hair", Vector3.new(1.2, 0.35, 1.2), base * CFrame.new(0, 5.3, 0.04), Color3.fromRGB(28, 22, 20), Enum.Material.SmoothPlastic, DETAIL)
	return base
end

-- A palm in a planter (the business Build's), and a lounge chair.
local function lounger(A, parent, f, x, z, y0, yaw, color)
	local base = f * CFrame.new(x, y0, z) * CFrame.Angles(0, yaw or 0, 0)
	local P, DETAIL = A.Build.part, A.DETAIL
	P(parent, "LoungerBed", Vector3.new(2.4, 0.5, 5.5), base * CFrame.new(0, 0.9, 0.6), color, Enum.Material.Fabric, DETAIL)
	P(parent, "LoungerBack", Vector3.new(2.4, 2.2, 0.4), base * CFrame.new(0, 1.9, -2.2) * CFrame.Angles(math.rad(-25), 0, 0), color,
		Enum.Material.Fabric, DETAIL)
	P(parent, "LoungerLegs", Vector3.new(2.2, 0.65, 5), base * CFrame.new(0, 0.33, 0.6), A.C.DARK_METAL, Enum.Material.Metal, DETAIL)
end

------------------------------------------------------------------ the building (Look 3.0, night-first)

-- The velvet rope between two brass posts (lot space, on the ground), looks only.
local function rope(A, parent, f, x0, z0, x1, z1)
	local Build, DETAIL = A.Build, A.DETAIL
	for _, p in ipairs({ { x0, z0 }, { x1, z1 } }) do
		Build.post(parent, "Stanchion", f, p[1], p[2], 0.2, 3.2, 0.35, K.BRASS, Enum.Material.Metal, DETAIL)
		Build.post(parent, "StanchionBase", f, p[1], p[2], 0.2, 0.25, 1.1, K.BRASS, Enum.Material.Metal, DETAIL)
	end
	local a, b = Vector3.new(x0, 2.75, z0), Vector3.new(x1, 2.75, z1)
	local len = (b - a).Magnitude
	if len > 0.1 then
		local mid = (a + b) / 2
		local cf = f * CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
		local r = Build.part(parent, "VelvetRope", Vector3.new(len, 0.28, 0.28), cf, K.VELVET, Enum.Material.Fabric, DETAIL)
		r.Shape = Enum.PartType.Cylinder
	end
end

-- Painted lines round a box on the ground (lot space) in a colour, and a stencil word in it.
local function boxLines(A, parent, f, cx, cz, w, d, color, word)
	local box, DETAIL = A.Build.box, A.DETAIL
	local y0, y1 = 0.2, 0.24
	box(parent, "Line", f, cx - w / 2, cx + w / 2, y0, y1, cz - d / 2, cz - d / 2 + 0.4, color, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "Line", f, cx - w / 2, cx + w / 2, y0, y1, cz + d / 2 - 0.4, cz + d / 2, color, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "Line", f, cx - w / 2, cx - w / 2 + 0.4, y0, y1, cz - d / 2, cz + d / 2, color, Enum.Material.SmoothPlastic, DETAIL)
	box(parent, "Line", f, cx + w / 2 - 0.4, cx + w / 2, y0, y1, cz - d / 2, cz + d / 2, color, Enum.Material.SmoothPlastic, DETAIL)
	if word then
		local paint = box(parent, "Paint", f, cx - w / 2 + 1, cx + w / 2 - 1, y0, y0 + 0.02, cz - 2.5, cz + 2.5, color, Enum.Material.SmoothPlastic,
			{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
		A.Build.signGui(paint, Enum.NormalId.Top, word, nil, color, nil, true)
	end
end

-- The Afterglow Nightclub (see the header). Returns the plate's title label.
function Nightclub.Style(m, f, def, A)
	local Build, C, DETAIL, SHADE = A.Build, A.C, A.DETAIL, A.SHADE
	local box, post, neon, group = Build.box, Build.post, Build.neon, Build.group
	local H = K.H
	local L = def.Layout
	local glow, accent = def.Neon, def.Accent
	local front = Enum.NormalId.Front
	local plaster, metal, smooth = Enum.Material.Plaster, Enum.Material.Metal, Enum.Material.SmoothPlastic

	-- THE SHELL (x -22..22, z -4..24) ----------------------------------------------------------------------------
	box(m, "ClubFloor", f, -21, 21, 0.2, 0.4, -3, 23, K.FLOOR, Enum.Material.Marble)
	box(m, "BackWall", f, -22, 22, 0.2, H, 23, 24, K.STUCCO, plaster)
	box(m, "SideWall", f, -22, -21, 0.2, H, -4, 23, K.STUCCO, plaster)
	box(m, "SideWall", f, 21, 22, 0.2, H, -4, 23, K.STUCCO, plaster)
	-- The glass front either side of the doors (x -3..3), the lintel over them.
	Build.shopfront(m, f, -22, -3, -4, -3, H, K.STUCCO, plaster, 2.4, 9.4)
	Build.shopfront(m, f, 3, 22, -4, -3, H, K.STUCCO, plaster, 2.4, 9.4)
	box(m, "Lintel", f, -3, 3, 10, H, -4, -3, K.STUCCO, plaster)
	for _, x in ipairs({ -3.3, 3 }) do
		box(m, "DoorFrame", f, x, x + 0.3, 0.4, 10, -4.2, -2.8, K.BRASS, metal, DETAIL)
	end
	box(m, "DoorHead", f, -3.3, 3.3, 9.7, 10, -4.2, -2.8, K.BRASS, metal, DETAIL)
	box(m, "Roof", f, -22.5, 22.5, H, H + 0.8, -4.5, 24.5, K.STUCCO_DARK, Enum.Material.Concrete, { CastShadow = true })
	box(m, "Parapet", f, -22.5, 22.5, H + 0.8, H + 2, -4.5, -3.9, K.STUCCO_DARK, plaster)
	box(m, "Plinth", f, -22.1, 22.1, 0.2, 1, -4.15, -3.95, K.STUCCO_DARK, plaster, DETAIL)
	-- After dark: a pink line along the parapet and round the doors (every level: neon only at night).
	neon(m, f, -22.5, 22.5, H + 1.85, H + 2.1, -4.6, -4.4, glow)
	neon(m, f, -3.6, -3.3, 0.4, 10.3, -4.35, -4.2, glow)
	neon(m, f, 3.3, 3.6, 0.4, 10.3, -4.35, -4.2, glow)
	neon(m, f, -3.6, 3.6, 10.3, 10.6, -4.35, -4.2, glow)
	-- The roof sign: AFTERGLOW on the parapet (painted; level 3 rings it with neon).
	local sign = box(m, "Sign", f, -16, 16, H + 2, H + 8, -4.4, -3.9, accent, Enum.Material.Wood)
	Build.signGui(sign, front, "AFTERGLOW", "NIGHTCLUB · BOARDWALK", Color3.fromRGB(255, 140, 200), C.GOLD, true)
	for _, x in ipairs({ -12, 0, 12 }) do
		box(m, "SignLeg", f, x - 0.3, x + 0.3, H + 0.8, H + 2, -3.9, -3.3, C.DARK_METAL, metal, DETAIL)
	end
	-- The marquee over the doors, the owner plate on its front, lamps under it.
	box(m, "Marquee", f, -7, 7, 10, 10.8, -9.2, -4, accent, metal, SHADE)
	box(m, "MarqueeTrim", f, -7.1, 7.1, 9.8, 10, -9.3, -9.1, K.BRASS, metal, DETAIL)
	neon(m, f, -7, 7, 9.6, 9.8, -9.35, -9.15, glow)
	local plate = box(m, "OwnerPlate", f, -6, 6, 10.9, 12.4, -9.16, -9.04, C.DARK, metal, DETAIL)
	local plateGui = Build.signGui(plate, front, "FOR SALE · " .. A.money(def.Price), nil, C.GOLD)
	for _, x in ipairs({ -4.5, 4.5 }) do
		Build.lamp(m, f, x - 0.5, x + 0.5, 9.3, 9.8, -7.5, -6.5, 20)
		post(m, "MarqueeRod", f, x, -8.6, 10.8, 3, 0.15, C.DARK_METAL, metal, DETAIL)
	end

	-- THE LOBBY (x -21..21, z -3..10) ----------------------------------------------------------------------------
	-- The inner wall (z 10..11): the back room's door at x 8..11; the club hall's padded doors (the way in is the cover).
	box(m, "InnerWall", f, -21, 8, 0.4, H, 10, 11, K.STUCCO, plaster)
	box(m, "InnerWall", f, 11, 21, 0.4, H, 10, 11, K.STUCCO, plaster)
	box(m, "BackDoorHead", f, 8, 11, 9, H, 10, 11, K.STUCCO, plaster)
	box(m, "HallDoors", f, -8, -2, 0.4, 9, 9.85, 10, K.LEATHER, Enum.Material.Leather, DETAIL)
	local hall = box(m, "HallSign", f, -8, -2, 9.2, 10.6, 9.82, 9.9, C.DARK, smooth, DETAIL)
	Build.signGui(hall, front, "DANCE FLOOR", "COVER AT THE ROPE", glow, C.WHITE)
	box(m, "LobbyCeiling", f, -21, 21, 11, 11.3, -3, 10, C.DARK, smooth, DETAIL)
	Build.roomLight(m, f, -14, -6, 10.9, 1, 4, Color3.fromRGB(255, 150, 210), 22)
	Build.roomLight(m, f, 6, 14, 10.9, 1, 4, Color3.fromRGB(190, 150, 255), 22)
	-- The ticket counter with its till (break-in robbers rummage here).
	box(m, "Counter", f, -20, -12, 0.4, 3.6, 4, 6, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "CounterTop", f, -20.2, -11.8, 3.6, 3.9, 3.8, 6.2, K.BRASS, metal)
	local reg = L.Register
	box(m, "Register", f, reg.X - 0.8, reg.X + 0.8, 3.9, 4.9, reg.Z - 0.5, reg.Z + 0.5, C.DARK, smooth, DETAIL)
	local tix = box(m, "TicketSign", f, -20, -12, 6.6, 8.6, 9.84, 9.98, C.DARK, smooth, DETAIL)
	Build.signGui(tix, front, "TICKETS", "COAT CHECK · VIP LIST", C.GOLD, C.WHITE)
	-- Level 1's small bar (it stays at every level): the counter, stools, the bottles behind it.
	box(m, "Bar", f, 12, 20, 0.4, 3.6, 7, 8.6, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "BarTop", f, 11.8, 20.2, 3.6, 3.9, 6.8, 8.8, C.WHITE, Enum.Material.Marble)
	box(m, "BarShelf", f, 12, 20, 4.5, 4.8, 9.3, 9.9, C.DARK_METAL, metal, DETAIL)
	for i = 0, 6 do
		local x = 12.6 + i * 1.1
		box(m, "Bottle", f, x - 0.3, x + 0.3, 4.8, 6.1, 9.4, 9.8, ({ Color3.fromRGB(120, 200, 140), Color3.fromRGB(230, 160, 70), Color3.fromRGB(200, 60, 90) })[i % 3 + 1],
			Enum.Material.Glass, DETAIL)
	end
	for _, x in ipairs({ 13.5, 16, 18.5 }) do
		post(m, "BarStool", f, x, 5.8, 0.4, 2.6, 0.3, C.DARK_METAL, metal, DETAIL)
		post(m, "BarStoolSeat", f, x, 5.8, 2.6, 0.3, 1.4, K.VELVET, Enum.Material.Fabric, DETAIL)
	end

	-- THE BACK ROOM (x 5.5..21, z 11..23) ------------------------------------------------------------------------
	box(m, "BackRoomWall", f, 4.5, 5.5, 0.4, H, 11, 23, K.STUCCO, plaster)
	box(m, "BackRoomCeiling", f, 5.5, 21, 10, 10.3, 11, 23, C.DARK, smooth, DETAIL)
	box(m, "BackDoorLeaf", f, 8, 8.2, 0.4, 8.6, 11, 14, Color3.fromRGB(60, 40, 34), Enum.Material.Wood, DETAIL)
	local priv = box(m, "PrivateSign", f, 8.2, 10.8, 7.2, 8.4, 9.8, 9.88, C.DARK, smooth, DETAIL)
	Build.signGui(priv, front, "PRIVATE", nil, Color3.fromRGB(255, 90, 90))
	Build.roomLight(m, f, 9, 13, 9.9, 16.5, 19.5, Color3.fromRGB(255, 214, 150), 16)
	-- The card table under its lamp, four chairs, chips and cards.
	box(m, "CardTable", f, 7.5, 11, 2.6, 2.9, 16, 20, K.FELT, Enum.Material.Fabric)
	box(m, "CardTableRim", f, 7.3, 11.2, 2.4, 2.6, 15.8, 20.2, K.WOOD, Enum.Material.Wood, DETAIL)
	post(m, "CardTableLeg", f, 9.25, 18, 0.4, 2, 1.2, C.DARK_METAL, metal, DETAIL)
	for _, c in ipairs({ { 6.6, 18 }, { 12, 18 }, { 9.25, 15 }, { 9.25, 21 } }) do
		box(m, "Chair", f, c[1] - 0.7, c[1] + 0.7, 0.4, 1.9, c[2] - 0.7, c[2] + 0.7, K.LEATHER, Enum.Material.Leather, DETAIL)
	end
	for i = 0, 3 do
		post(m, "Chips", f, 8.2 + i * 0.6, 17 + (i % 2) * 1.6, 2.9, 0.25 + i * 0.1, 0.45, ({ C.WHITE, Color3.fromRGB(220, 40, 60), K.BRASS })[i % 3 + 1],
			smooth, DETAIL)
	end
	-- The safe (WASH here) and its sign.
	local sf = L.Safe
	box(m, "Safe", f, sf.X - 1.6, sf.X + 1.6, 0.4, 4.4, sf.Z + 0.4, sf.Z + 2, C.DARK_METAL, Enum.Material.DiamondPlate)
	local dial = Build.part(m, "SafeDial", Vector3.new(0.14, 0.8, 0.8), f * CFrame.new(sf.X, 2.6, sf.Z + 0.34) * CFrame.Angles(0, math.rad(90), 0), K.BRASS,
		metal, DETAIL)
	dial.Shape = Enum.PartType.Cylinder
	box(m, "SafeHandle", f, sf.X + 0.6, sf.X + 1.2, 2.2, 2.4, sf.Z + 0.25, sf.Z + 0.4, K.BRASS, metal, DETAIL)
	local safeSign = box(m, "SafeSign", f, sf.X - 1.6, sf.X + 1.6, 5.4, 6.6, sf.Z + 1.84, sf.Z + 1.98, C.DARK, smooth, DETAIL)
	Build.signGui(safeSign, front, "THE TILLS", "WASH THE TAKE HERE", C.GOLD, C.WHITE)
	-- The WASH prompt at the safe (the owner only: BusinessClient shows it to them; the server checks again).
	local washPoint = Build.holder(m, "WashPoint", f, Vector3.new(sf.X, 3.4, sf.Z - 0.6), Vector3.new(2, 2, 1))
	local wash = Build.prompt(washPoint, "BizWashPrompt", "Wash the take", "Back room safe", 8)
	wash.HoldDuration = BR.WashHold
	wash:SetAttribute("BusinessId", def.Id)
	Raids.TimedPrompt(wash, BR.WashHold, function(p)
		Nightclub._Wash(p)
	end)

	-- THE FORECOURT ----------------------------------------------------------------------------------------------
	-- The red carpet from the doors to the lot's front edge, brass edges, the velvet ropes along its top half.
	box(m, "RedCarpet", f, -2, 2, 0.2, 0.27, -25, -4, K.CARPET, Enum.Material.Fabric, DETAIL)
	for _, x in ipairs({ -2.2, 2 }) do
		box(m, "CarpetEdge", f, x, x + 0.2, 0.2, 0.28, -25, -4, K.BRASS, metal, DETAIL)
	end
	rope(A, m, f, -2.8, -12.5, -2.8, -8.7)
	rope(A, m, f, -2.8, -8.7, -2.8, -4.8)
	rope(A, m, f, 2.8, -12.5, 2.8, -8.7)
	rope(A, m, f, 2.8, -8.7, 2.8, -4.8)
	-- The VIP mark (the limo's red-carpet stop) and the limo's bay.
	local cp = L.Carpet
	boxLines(A, m, f, cp.X, cp.Z, 8, 17, glow, "VIP")
	neon(m, f, cp.X - 0.25, cp.X + 0.25, 0.22, 0.3, cp.Z - 1.5, cp.Z + 1.5, glow) -- (the mark's centre line, after dark)
	local lb = L.LimoBay
	boxLines(A, m, f, lb.X, lb.Z, 8, 17, K.WHITE_LINE, "LIMO")
	post(m, "LimoSignPole", f, lb.X - 5.2, -7, 0.2, 5, 0.3, C.DARK_METAL, metal)
	local limoSign = box(m, "LimoSign", f, lb.X - 6.8, lb.X - 3.6, 5, 6.6, -7.1, -6.9, C.DARK, metal, DETAIL)
	Build.signGui(limoSign, front, "LIMO", "AFTERGLOW VIP", C.GOLD, C.WHITE)
	-- The press pen behind its own rope (their flashes go off as a VIP walks in: Layout.Flashes).
	rope(A, m, f, 2.9, -7.6, 10.6, -7.6)
	for i, fl in ipairs(L.Flashes) do
		if fl.Z > -8 then
			local base = person(A, m, f, fl.X, fl.Z + 0.6, 0, K.SKINS[i % #K.SKINS + 1], C.DARK, Color3.fromRGB(50, 52, 60))
			Build.part(m, "Camera", Vector3.new(0.8, 0.6, 0.6), base * CFrame.new(0, 4.6, -0.8), C.DARK, smooth, DETAIL)
		end
	end
	-- The bouncer at the rope (the cover charge prompt hangs here) and his rope.
	local sv = L.Service
	person(A, m, f, sv.X, sv.Z + 1.6, 0, K.SKINS[2], K.SUIT, K.SUIT)
	rope(A, m, f, -3.4, -6.4, -8.6, -6.4)
	local cover = box(m, "CoverSign", f, sv.X - 2.6, sv.X + 2.6, 6.2, 7.6, -4.2, -4.1, C.DARK, smooth, DETAIL)
	Build.signGui(cover, Enum.NormalId.Front, "COVER " .. A.money(def.Service.Price), "VIP BOOTHS INSIDE", glow, C.WHITE)
	-- Palms at the front corners and the back corners.
	for _, c in ipairs({ { -25.2, -22, 16 }, { 25.2, -22, 18 }, { -25.2, 20, 14 }, { 25.2, 20, 15 } }) do
		Build.planterPalm(m, f, c[1], c[2], c[3])
	end

	-- LEVELS 1-2: the chalkboard (a small bar, house music) -----------------------------------------------------
	local one = group(m, "Chalk12", 1, 2)
	local chalk = Build.part(one, "Chalkboard", Vector3.new(2.6, 3.2, 0.2), f * CFrame.new(-9.8, 1.8, -5) * CFrame.Angles(math.rad(-12), 0, 0),
		C.DARK, smooth, DETAIL)
	Build.signGui(chalk, front, "BAR · HOUSE MUSIC", "OPEN TILL LATE", C.WHITE, C.GOLD, true)

	-- LEVEL 2: dance floor lights (colour panels behind the front glass) and uplights on the facade ---------------
	local two = group(m, "Lights2", 2, nil)
	local tints = { glow, K.CYAN, K.VIOLET }
	for i, span in ipairs({ { -20, -15 }, { -14.5, -9.5 }, { -9, -4 }, { 4, 9 }, { 9.5, 14.5 }, { 15, 20 } }) do
		neon(two, f, span[1], span[2], 3, 8.8, -2.75, -2.6, tints[i % 3 + 1])
	end
	for _, x in ipairs({ -19, -11, 11, 19 }) do
		neon(two, f, x - 0.5, x + 0.5, 0.2, 0.8, -4.8, -4.3, glow)
		neon(two, f, x - 0.08, x + 0.08, 1, 9, -4.15, -4.05, glow)
	end

	-- LEVEL 3: the DJ booth on the marquee and the light show (searchlights, neon round the sign) ----------------
	local three = group(m, "LightShow3", 3, nil)
	neon(three, f, -16.2, 16.2, H + 8, H + 8.3, -4.5, -4.3, glow)
	neon(three, f, -16.2, 16.2, H + 1.7, H + 2, -4.5, -4.3, glow)
	neon(three, f, -16.5, -16.2, H + 1.7, H + 8.3, -4.5, -4.3, glow)
	neon(three, f, 16.2, 16.5, H + 1.7, H + 8.3, -4.5, -4.3, glow)
	box(three, "DJDeck", f, -2.5, 2.5, 10.8, 12.2, -7.8, -6.2, C.DARK_METAL, metal, DETAIL)
	for _, x in ipairs({ -1.2, 1.2 }) do
		local deck = Build.part(three, "Turntable", Vector3.new(0.12, 1.3, 1.3), f * CFrame.new(x, 12.25, -7) * CFrame.Angles(0, 0, math.rad(90)), C.DARK,
			smooth, DETAIL)
		deck.Shape = Enum.PartType.Cylinder
	end
	for _, x in ipairs({ -4.5, 4.5 }) do
		box(three, "Speaker", f, x - 1, x + 1, 10.8, 14, -8, -6, C.DARK, smooth, DETAIL)
		neon(three, f, x - 0.6, x + 0.6, 12.2, 13.4, -8.05, -7.95, K.CYAN)
	end
	local dj = box(three, "DJSign", f, -2, 2, 12.4, 13.4, -7.85, -7.75, C.DARK, smooth, DETAIL)
	Build.signGui(dj, front, "DJ", nil, K.CYAN)
	for _, x in ipairs({ -12, 12 }) do
		post(three, "SearchlightBase", f, x, 16, H + 0.8, 1.2, 2, C.DARK_METAL, metal, DETAIL)
		local beam = Build.part(three, "Searchlight", Vector3.new(1.2, 60, 1.2), f * CFrame.new(x, H + 2, 16) * CFrame.Angles(0, 0, math.rad(x < 0 and 18 or -18))
			* CFrame.new(0, 30, 0), C.TRIM_DAY, Enum.Material.Metal, { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 0.7 })
		Build.nightNeon(beam, x < 0 and glow or K.VIOLET)
	end

	-- LEVEL 4: the VIP balcony (two wings over the marquee) ----------------------------------------------------
	local four = group(m, "Balcony4", 4, nil)
	for _, w in ipairs({ { -20, -8 }, { 8, 20 } }) do
		box(four, "BalconySlab", f, w[1], w[2], 12, 12.4, -8, -4, K.STUCCO_DARK, Enum.Material.Concrete)
		box(four, "BalconyRail", f, w[1], w[2], 12.4, 15, -8.1, -7.9, C.GLASS, Enum.Material.Glass, { Transparency = 0.55, CastShadow = false })
		box(four, "BalconyRailTop", f, w[1], w[2], 15, 15.2, -8.15, -7.85, K.BRASS, metal, DETAIL)
		neon(four, f, w[1], w[2], 11.8, 12, -8.15, -7.95, K.VIOLET)
		lounger(A, four, f, (w[1] + w[2]) / 2 - 2.5, -5.8, 12.4, math.rad(90), C.WHITE)
		lounger(A, four, f, (w[1] + w[2]) / 2 + 2.5, -5.8, 12.4, math.rad(90), C.WHITE)
	end
	local vipSign = box(four, "VipSign", f, -17, -11, 15.6, 17.4, -4.2, -4.05, C.DARK, smooth, DETAIL)
	Build.signGui(vipSign, front, "VIP", "BALCONY", C.GOLD, C.WHITE)
	neon(four, f, -17, -11, 17.4, 17.6, -4.25, -4.05, C.GOLD)

	-- LEVEL 5: the rooftop pool party -------------------------------------------------------------------------
	local five = group(m, "Pool5", 5, nil)
	local ry = H + 0.8
	box(five, "PoolRim", f, -11, 11, ry, ry + 1.2, 5, 17, C.WHITE, Enum.Material.Marble)
	box(five, "PoolWater", f, -10, 10, ry + 1.2, ry + 1.3, 6, 16, K.WATER, Enum.Material.Glass, { Transparency = 0.25, Reflectance = 0.1, CastShadow = false })
	neon(five, f, -10, 10, ry + 1.05, ry + 1.2, 5.9, 6.05, K.CYAN)
	for i, x in ipairs({ -8, -3, 3, 8 }) do
		lounger(A, five, f, x, 1.5, ry, 0, i % 2 == 0 and glow or C.WHITE)
	end
	Build.planterPalm(five, f * CFrame.new(0, ry - 0.2, 0), -17, 12, 10)
	Build.planterPalm(five, f * CFrame.new(0, ry - 0.2, 0), 17, 12, 11)
	for i, x in ipairs({ -14, 14 }) do
		post(five, "LightPost", f, x, 2, ry, 6, 0.25, C.DARK_METAL, metal, DETAIL)
		post(five, "LightPost", f, x, 20, ry, 6, 0.25, C.DARK_METAL, metal, DETAIL)
		neon(five, f, x - 0.06, x + 0.06, ry + 5.8, ry + 6, 2, 20, i == 1 and glow or K.CYAN)
	end
	neon(five, f, -14, 14, ry + 5.8, ry + 6, 1.94, 2.06, K.VIOLET)
	for i, c in ipairs({ { -6, 19 }, { 0, 19.5 }, { 6, 19 } }) do
		person(A, five, f, c[1], c[2], 0, K.SKINS[i], K.SHIRTS[i], Color3.fromRGB(40, 60, 120), ry)
	end
	local pool = box(five, "PoolSign", f, -7, 7, ry + 9.6, ry + 11.6, -3.4, -3.2, C.DARK, smooth, DETAIL)
	Build.signGui(pool, front, "ROOFTOP POOL PARTY", "TONIGHT · ALL NIGHT", K.CYAN, C.GOLD)

	return plateGui:FindFirstChild("Title")
end

------------------------------------------------------------------ the club's inside (off the map, per visit)

-- The club's own frame (its Origin, facing north: -Z).
local function clubFrame()
	return CFrame.new(CL.Origin)
end

-- A dancing NPC (the pedestrians' looks, anchored, its Humanoid kept for the stock dance), or nil.
local function dancer(A, parent, cf)
	local ok, model = pcall(function()
		local looks = ReplicatedStorage:FindFirstChild("PedTemplates")
		local list = looks and looks:GetChildren() or {}
		local p = #list > 0 and list[A.rng:NextInteger(1, #list)] or nil
		if p and p:IsA("Model") and p:FindFirstChild("HumanoidRootPart") and p:FindFirstChildOfClass("Humanoid") then
			return p:Clone()
		end
		return nil
	end)
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		model:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	model.Name = "BizClubDancer"
	model:PivotTo(cf * CFrame.new(0, hum.HipHeight + root.Size.Y / 2, 0))
	model.Parent = parent
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local anim = Instance.new("Animation")
		anim.AnimationId = K.DANCES[A.rng:NextInteger(1, #K.DANCES)]
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
	return model
end

-- The music: one Sound in the club's speaker, Config.Sounds' first radio station (Neon FM), track after track.
local function musicTracks()
	local ok, Sounds = pcall(require, ReplicatedStorage.Shared.Config.Sounds)
	local station = ok and type(Sounds) == "table" and type(Sounds.Radio) == "table" and Sounds.Radio[1] or nil
	return station and station.Tracks or {}
end

local function nextTrack()
	local club = S.club
	local tracks = musicTracks()
	if not club or not club.music or #tracks == 0 then
		return
	end
	club.track = (club.track or 0) % #tracks + 1
	local t = tracks[club.track]
	club.music.SoundId = "rbxassetid://" .. tostring(t.Id)
	club.music.TimePosition = 0
	club.music:Play()
	club.trackAt = os.clock() + (tonumber(t.Length) or 150)
end

-- Build the club's inside at Club.Origin (see the header). Its level props show each device's own level.
local function buildClub(A)
	local def = clubDef()
	local Build, C, DETAIL = A.Build, A.C, A.DETAIL
	local box, post, neon, group = Build.box, Build.post, Build.neon, Build.group
	local f = clubFrame()
	local m = Instance.new("Model")
	m.Name = "BizClubInterior"
	m:SetAttribute("BizClub", def.Id)
	local glow = def.Neon
	local front, back = Enum.NormalId.Front, Enum.NormalId.Back
	local smooth, metal = Enum.Material.SmoothPlastic, Enum.Material.Metal
	local HH = 20
	-- The hall (x -36..36, z -28..28): floor, walls, ceiling. Everything here is solid where you'd touch it.
	local floor = box(m, "Floor", f, -36, 36, -0.6, 0, -28, 28, Color3.fromRGB(22, 20, 26), Enum.Material.Marble)
	m.PrimaryPart = floor
	box(m, "Ceiling", f, -36, 36, HH, HH + 0.6, -28, 28, Color3.fromRGB(14, 12, 18), smooth)
	for _, w in ipairs({ { -37, 37, -29, -28 }, { -37, 37, 28, 29 }, { -37, -36, -28, 28 }, { 36, 37, -28, 28 } }) do
		box(m, "Wall", f, w[1], w[2], 0, HH, w[3], w[4], K.STUCCO_DARK, Enum.Material.Plaster)
	end
	-- Coloured wall washes and strips (always lit inside: it's always night in here).
	for i, x in ipairs({ -30, -15, 0, 15, 30 }) do
		local p = box(m, "WallGlow", f, x - 3, x + 3, 2, 16, -27.9, -27.7, ({ glow, K.VIOLET, K.CYAN })[i % 3 + 1], Enum.Material.Neon,
			{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.55 })
		p:SetAttribute("ClubGlow", true)
	end
	for _, z in ipairs({ -27.8, 27.8 }) do
		box(m, "Strip", f, -36, 36, HH - 0.6, HH - 0.3, z - 0.1, z + 0.1, glow, Enum.Material.Neon, DETAIL)
	end
	for i, spec in ipairs({ { -18, -10, glow }, { 18, -10, K.VIOLET }, { -18, 12, K.CYAN }, { 18, 12, glow }, { 0, 0, Color3.fromRGB(255, 220, 240) } }) do
		local holder = Build.holder(m, "ClubLight", f, Vector3.new(spec[1], HH - 1, spec[2]), Vector3.new(1, 1, 1))
		local l = Instance.new("PointLight")
		l.Color = spec[3]
		l.Range = i == 5 and 40 or 34
		l.Brightness = i == 5 and 1.4 or 2.2
		l.Shadows = false
		l.Parent = holder
		holder:SetAttribute("ClubLight", true)
	end
	-- The entrance (south) and the EXIT door.
	box(m, "ExitDoor", f, -3, 3, 0, 9, 27.6, 27.95, K.LEATHER, Enum.Material.Leather, DETAIL)
	local exitSign = box(m, "ExitSign", f, -2.5, 2.5, 9.4, 10.6, 27.5, 27.6, C.DARK, smooth, DETAIL)
	Build.signGui(exitSign, front, "EXIT", "BACK TO THE BOARDWALK", Color3.fromRGB(110, 242, 160), C.WHITE)
	local exitPoint = Build.holder(m, "ExitPoint", f, CL.Exit + Vector3.new(0, 4, 0), Vector3.new(4, 6, 1))
	local exitPrompt = Build.prompt(exitPoint, "BizClubExit", "Leave the club", "Afterglow", 10)
	exitPrompt.Triggered:Connect(function(p)
		if RateLimit.Allow(p, "BizClubExit", 1, 2) then
			Nightclub._Leave(p, "Player")
		end
	end)
	local welcome = box(m, "Welcome", f, -10, 10, 12, 15, 27.5, 27.6, def.Accent or C.DARK, smooth, DETAIL)
	Build.signGui(welcome, front, "AFTERGLOW", "DANCE · DRINK · SHINE", glow, C.GOLD)

	-- THE DANCE FLOOR (x -12..12, z -10..10): plain wood at level 1; light-up tiles from level 2 (BusinessClient makes
	-- them dance on the guests' devices).
	box(group(m, "FloorPlain1", 1, 1), "DanceFloor", f, -12, 12, 0, 0.2, -10, 10, Color3.fromRGB(70, 46, 34), Enum.Material.WoodPlanks)
	local tiles = group(m, "FloorLights2", 2, nil)
	local n = 0
	for gx = 0, 5 do
		for gz = 0, 4 do
			n += 1
			local x0, z0 = -12 + gx * 4, -10 + gz * 4
			local t = box(tiles, "DanceTile", f, x0 + 0.1, x0 + 3.9, 0, 0.2, z0 + 0.1, z0 + 3.9, ({ glow, K.CYAN, K.VIOLET })[n % 3 + 1], Enum.Material.Neon)
			t:SetAttribute("DanceTile", n)
		end
	end
	box(m, "FloorEdge", f, -12.5, 12.5, 0, 0.15, -10.5, 10.5, K.BRASS, metal, DETAIL)
	-- The dancers.
	local level = 1
	local featured = A.featuredOf and select(2, A.featuredOf(def.Id))
	if type(featured) == "table" then
		level = Businesses.ClampLevel(featured.level)
	end
	local spots = { { -6, -4 }, { 5, -6 }, { -2, 5 }, { 7, 4 }, { -8, 6 }, { 2, -1 } }
	for i = 1, math.min(CL.Dancers[level] or 2, #spots) do
		local s = spots[i]
		dancer(A, m, f * CFrame.new(s[1], 0.2, s[2]) * CFrame.Angles(0, math.rad(A.rng:NextInteger(0, 359)), 0))
	end

	-- THE BAR (east: x 24..35, z -14..14).
	box(m, "Bar", f, 24, 26, 0, 3.8, -14, 14, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "BarTop", f, 23.8, 26.2, 3.8, 4.1, -14.2, 14.2, C.WHITE, Enum.Material.Marble)
	neon(m, f, 23.7, 23.9, 0.4, 0.7, -14, 14, glow)
	box(m, "BackBar", f, 33, 35.9, 0, 3.6, -14, 14, K.WOOD, Enum.Material.WoodPlanks)
	box(m, "BottleWall", f, 35.6, 35.9, 4, 12, -13, 13, Color3.fromRGB(40, 30, 50), Enum.Material.Glass, { Transparency = 0.2 })
	for i = 0, 11 do
		local z = -12 + i * 2.2
		box(m, "Bottle", f, 34.8, 35.5, 4.2 + (i % 3) * 2.6, 5.6 + (i % 3) * 2.6, z - 0.35, z + 0.35, ({ Color3.fromRGB(120, 220, 160),
			Color3.fromRGB(240, 170, 70), Color3.fromRGB(230, 70, 120) })[i % 3 + 1], Enum.Material.Neon, DETAIL)
	end
	for _, z in ipairs({ -10, -5, 0, 5, 10 }) do
		post(m, "BarStool", f, 22, z, 0, 2.8, 0.3, C.DARK_METAL, metal, DETAIL)
		post(m, "BarStoolSeat", f, 22, z, 2.8, 0.3, 1.5, K.VELVET, Enum.Material.Fabric, DETAIL)
	end
	person(A, m, f, 29.5, 0, math.rad(90), K.SKINS[3], C.WHITE, K.SUIT, 0)
	local barSign = box(m, "BarSign", f, 35.5, 35.6, 13, 15, -6, 6, C.DARK, smooth, DETAIL)
	Build.signGui(barSign, Enum.NormalId.Left, "THE GLOW BAR", nil, glow)

	-- The sound system (north wall, every level) and the music.
	for _, x in ipairs({ -16, 16 }) do
		box(m, "Speaker", f, x - 2, x + 2, 0, 9, -27.6, -24, C.DARK, smooth)
		for _, y in ipairs({ 2, 5.5 }) do
			local cone = Build.part(m, "SpeakerCone", Vector3.new(0.1, 2.6, 2.6), f * CFrame.new(x, y, -23.95) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(40, 40, 46), smooth, DETAIL)
			cone.Shape = Enum.PartType.Cylinder
		end
	end
	local speaker = Build.holder(m, "MusicPoint", f, Vector3.new(0, 6, -12), Vector3.new(1, 1, 1))
	local music = Instance.new("Sound")
	music.Name = "ClubMusic"
	music.Volume = CL.MusicVolume
	music.RollOffMode = Enum.RollOffMode.Linear
	music.RollOffMinDistance = 60
	music.RollOffMaxDistance = 120
	music.Looped = false
	music.Parent = speaker

	-- LEVEL 3: the DJ booth on a stage (north) and the lasers.
	local three = group(m, "DJ3", 3, nil)
	box(three, "Stage", f, -10, 10, 0, 2.4, -27.5, -19, Color3.fromRGB(30, 26, 36), smooth)
	box(three, "DJDeck", f, -4, 4, 2.4, 5.4, -23.5, -21.5, C.DARK_METAL, metal)
	neon(three, f, -4, 4, 5.4, 5.6, -21.6, -21.4, K.CYAN)
	local djs = box(three, "DJSign", f, -6, 6, 9, 12, -27.6, -27.5, C.DARK, smooth)
	Build.signGui(djs, back, "DJ MARLO", "LIVE TONIGHT", K.CYAN, C.GOLD)
	person(A, three, f, 0, -24.8, math.pi, K.SKINS[2], glow, K.SUIT, 2.4)
	for i, x in ipairs({ -8, -4, 4, 8 }) do
		local laser = Build.part(three, "Laser", Vector3.new(0.15, 34, 0.15), f * CFrame.new(x, HH - 1, -22) * CFrame.Angles(math.rad(-55), 0, math.rad((i - 2.5) * 14))
			* CFrame.new(0, -17, 0), ({ glow, K.CYAN, K.VIOLET, Color3.fromRGB(120, 255, 140) })[i], Enum.Material.Neon, DETAIL)
		laser.Transparency = 0.35
		laser:SetAttribute("ClubLaser", i)
	end

	-- THE VIP BOOTH (west: x -35..-22, z -14..6): raised, a curved sofa (seats), a table, the rope with its gap.
	local bx = CL.Booth
	box(m, "BoothFloor", f, bx.X0, bx.X1, 0, 1.4, bx.Z0, bx.Z1, Color3.fromRGB(46, 20, 40), Enum.Material.Fabric)
	box(m, "BoothStep", f, bx.X1, bx.X1 + 1.2, 0, 0.7, -6.5, -1.5, Color3.fromRGB(46, 20, 40), Enum.Material.Fabric)
	box(m, "BoothBack", f, -35.9, -35, 1.4, 6, bx.Z0, bx.Z1, K.VELVET, Enum.Material.Fabric)
	for i, z in ipairs({ -11, -7, -3, 1, 4.5 }) do
		local seat = Instance.new("Seat")
		seat.Name = "BoothSeat"
		seat.Anchored = true
		seat.Size = Vector3.new(3, 1, 3)
		seat.CFrame = f * CFrame.new(-33.2, 2.1, z) * CFrame.Angles(0, math.rad(-90), 0)
		seat.Color = K.VELVET
		seat.Material = Enum.Material.Fabric
		seat:SetAttribute("BoothSeat", i)
		seat.Parent = m
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			Nightclub._BoothSeat(seat)
		end)
	end
	box(m, "BoothTable", f, -29.5, -26.5, 1.4, 3.6, -8, 0, Color3.fromRGB(26, 22, 30), Enum.Material.Marble)
	local bucket = Build.part(m, "ChampagneBucket", Vector3.new(1.4, 1.2, 1.2), f * CFrame.new(-28, 4.3, -4) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(200, 200, 210), metal, DETAIL)
	bucket.Shape = Enum.PartType.Cylinder
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "BoothSparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.LightEmission = 1
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.6, 1.1)
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
	sparkle.Enabled = false
	sparkle.Parent = bucket
	for _, seg in ipairs({ { -21.6, bx.Z0, -21.6, -6.5 }, { -21.6, -1.5, -21.6, bx.Z1 } }) do
		rope(A, m, f * CFrame.new(0, 1.4, 0), seg[1], seg[2], seg[3], seg[4])
	end
	local boothSign = box(m, "BoothSign", f, -34, -23, 9, 11.4, 6.4, 6.5, C.DARK, smooth, DETAIL)
	local signGui = Build.signGui(boothSign, back, "VIP BOOTH", "BOOK IT AT THE ROPE", C.GOLD, C.WHITE)
	neon(m, f, -34, -23, 11.4, 11.6, 6.35, 6.55, C.GOLD)
	local boothPoint = Build.holder(m, "BoothPoint", f, CL.BoothRope + Vector3.new(0, 4, 0), Vector3.new(2, 2, 1))
	local boothPrompt = Build.prompt(boothPoint, "BizBoothPrompt", "VIP booth " .. A.money(def.Booth.Price), "15 minutes · you and your crew", 10)
	boothPrompt.Triggered:Connect(function(p)
		Nightclub._Book(p)
	end)

	-- LEVEL 4: the VIP balcony over the entrance (looks only: a mezzanine with lounge chairs and its VIPs).
	local four = group(m, "Balcony4", 4, nil)
	box(four, "Mezzanine", f, -24, 24, 9, 9.6, 19, 27.9, Color3.fromRGB(30, 26, 36), Enum.Material.Concrete)
	box(four, "MezzRail", f, -24, 24, 9.6, 12.4, 18.8, 19, C.GLASS, Enum.Material.Glass, { Transparency = 0.55 })
	neon(four, f, -24, 24, 9.3, 9.5, 18.7, 18.9, K.VIOLET)
	for i, x in ipairs({ -18, -9, 9, 18 }) do
		lounger(A, four, f, x, 23.5, 9.6, math.pi, i % 2 == 0 and glow or C.WHITE)
	end
	for i, x in ipairs({ -13, 13 }) do
		person(A, four, f, x, 21, 0, K.SKINS[i + 1], K.SHIRTS[i + 2], K.SUIT, 9.6)
	end
	local mezz = box(four, "MezzSign", f, -6, 6, 13, 15, 27.8, 27.9, C.DARK, smooth, DETAIL)
	Build.signGui(mezz, front, "VIP BALCONY", nil, C.GOLD)

	-- LEVEL 5: the pool party corner (north-west).
	local five = group(m, "Pool5", 5, nil)
	box(five, "PoolRim", f, -35, -20, 0, 1.2, -27.5, -16, C.WHITE, Enum.Material.Marble)
	box(five, "PoolWater", f, -34, -21, 1.2, 1.3, -26.5, -17, K.WATER, Enum.Material.Glass, { Transparency = 0.25 })
	neon(five, f, -34, -21, 1.05, 1.2, -17.1, -16.95, K.CYAN)
	local ring = Build.part(five, "PoolRing", Vector3.new(0.8, 3.4, 3.4), f * CFrame.new(-27, 1.6, -22) * CFrame.Angles(0, 0, math.rad(90)), glow,
		smooth, DETAIL)
	ring.Shape = Enum.PartType.Cylinder
	box(five, "Flamingo", f, -24, -22.6, 1.4, 3.8, -20, -19, Color3.fromRGB(255, 120, 180), smooth, DETAIL)
	Build.planterPalm(five, f, -18, -26, 11)
	local poolSign = box(five, "PoolSign", f, -34, -22, 10, 12.5, -27.6, -27.5, C.DARK, smooth, DETAIL)
	Build.signGui(poolSign, back, "POOL PARTY", "ON THE HOUSE", K.CYAN, C.GOLD)

	Build.tagProps(m, def.Id) -- (the level groups: BizProp, each device its own level)
	pcall(function()
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m.Parent = Workspace
	S.club = { model = m, music = music, track = 0, trackAt = 0, sign = signGui, sparkle = sparkle, emptySince = nil }
	nextTrack()
	return S.club
end


local function clubDown()
	local club = S.club
	S.club = nil
	if club and club.model and club.model.Parent then
		club.model:Destroy()
	end
end

-- The booth's sign and sparkle, for whoever holds it now.
local function boothLooks()
	local club = S.club
	if not club then
		return
	end
	local b = S.booth
	local title = club.sign and club.sign:FindFirstChild("Title")
	local sub = club.sign and club.sign:FindFirstChild("Sub")
	if title and sub then
		title.Text = b and "RESERVED" or "VIP BOOTH"
		sub.Text = b and (string.upper(b.name) .. "'S CREW") or "BOOK IT AT THE ROPE"
	end
	if club.sparkle then
		club.sparkle.Enabled = b ~= nil
	end
end

------------------------------------------------------------------ the club: in and out

local function fade(player, phase)
	if player.Parent == Players and S.fadeRemote then
		S.fadeRemote:FireClient(player, phase)
	end
end

-- Is this player a guest of the club now?
local function isGuest(player)
	return S.guests[player.UserId] ~= nil
end

-- The trip in: fade, the area loaded, the character at the club's entrance. True if they're in.
local function enterClub(player, A, info)
	local uid = player.UserId
	if S.busy[uid] or isGuest(player) then
		return false
	end
	S.busy[uid] = true
	local char = player.Character
	local moved = false
	local ok, err = pcall(function()
		if not S.club then
			buildClub(A)
		end
		S.club.emptySince = nil
		fade(player, "Out")
		task.wait(CL.FadeTime)
		local at = CL.Origin + CL.Arrive
		pcall(function()
			player:RequestStreamAroundAsync(at, 3)
		end)
		if player.Parent == Players and player.Character == char and not wanted(player) then
			moved = moveTo(player, CFrame.lookAt(at + Vector3.new(0, 3.5, 0), at + Vector3.new(0, 3.5, -10)))
		end
	end)
	if not ok then
		warn("[Nightclub] going in: " .. tostring(err))
	end
	if moved then
		S.guests[uid] = { char = char }
		player:SetAttribute("BizClub", clubDef().Id)
		A.result(player, { Kind = "ClubIn", Id = clubDef().Id, Free = info.free == true, Price = info.price, Owner = info.paidTo,
			Booth = S.booth and S.booth.name or nil })
		Telemetry.Custom(player, "BizClubIn", info.price or 0)
	end
	fade(player, "In")
	S.busy[uid] = nil
	return moved
end

-- Out of the club (why: "Player" | "Wanted"): back outside the doors. gone = the character is no longer here (no trip).
local function leaveClub(player, why, gone)
	local uid = player.UserId
	if not S.guests[uid] or S.busy[uid] then
		return
	end
	S.guests[uid] = nil
	if player.Parent == Players then
		player:SetAttribute("BizClub", nil)
	end
	if gone or player.Parent ~= Players then
		return
	end
	local A = S.A
	S.busy[uid] = true
	local def = clubDef()
	local ok, err = pcall(function()
		fade(player, "Out")
		task.wait(CL.FadeTime)
		local at = Businesses.At(def, K.OUTSIDE)
		pcall(function()
			player:RequestStreamAroundAsync(at, 3)
		end)
		moveTo(player, CFrame.lookAt(at + Vector3.new(0, 3.5, 0), at + Vector3.new(0, 3.5, 0) + def.Facing))
	end)
	if not ok then
		warn("[Nightclub] going out: " .. tostring(err))
	end
	fade(player, "In")
	S.busy[uid] = nil
	if A then
		A.result(player, { Kind = "ClubOut", Id = def.Id, Why = why })
	end
end

function Nightclub._Leave(player, why)
	task.spawn(leaveClub, player, why or "Player")
end

-- Does this player walk in free (an owner of the club, or a crewmate of one in the server)?
local function freeEntry(player, A, def)
	if A.owned(player, def.Id) then
		return true
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and A.owned(p, def.Id) and A.sameCrew(player, p) then
			return true
		end
	end
	return false
end

-- BizServicePrompt at the velvet rope: the COVER CHARGE (see the header).
function Nightclub.Service(player, def, A)
	S.A = A
	local hum, root = A.humOf(player), A.rootOf(player)
	if not hum or hum.Health <= 0 or not root or player:GetAttribute("Side") == "Prisoner" then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		A.refuse(player, def.Id, "ClubCivOnly")
		return
	end
	if wanted(player) then
		A.refuse(player, def.Id, "ClubWanted")
		return
	end
	if hum.SeatPart then
		A.refuse(player, def.Id, "ClubOnFoot")
		return
	end
	if player:GetAttribute("JobKind") ~= nil or A.jobOf(player) then
		A.refuse(player, def.Id, "ClubBusy")
		return
	end
	local spot = Businesses.At(def, def.Layout.Service)
	if flat(root.Position - spot).Magnitude > CL.Reach or math.abs(root.Position.Y - spot.Y) > 12 then
		A.refuse(player, def.Id, "TooFar")
		return
	end
	if S.busy[player.UserId] or isGuest(player) then
		return
	end
	local info = { free = false, price = 0 }
	local now = serverNow()
	if freeEntry(player, A, def) then
		info.free = true
	elseif Businesses.TimeLeft(player:GetAttribute("BizCoverUntil"), now) > 0 then
		info.free = true
		info.pass = true
	else
		local price = def.Service.Price
		local paid, paidTo = A.serveCustomer(player, def, price, "bizcover", def.Service.Words)
		if not paid then
			return
		end
		info.price, info.paidTo = price, paidTo
		player:SetAttribute("BizCoverUntil", now + CL.CoverValid)
	end
	task.spawn(enterClub, player, A, info)
end

-- RequestBusiness("Mod", "Nightclub", "Leave"): LEAVE on the screen inside the club.
function Nightclub.Request(player, _def, arg, _arg2, A)
	S.A = A
	if arg == "Leave" and isGuest(player) then
		Nightclub._Leave(player, "Player")
	end
end

------------------------------------------------------------------ the club: the VIP booth

-- May this player use the booth now (its holder or a crewmate of theirs)?
local function boothAllowed(player)
	local b = S.booth
	if not b then
		return false
	end
	if b.userId == player.UserId then
		return true
	end
	local holder = Players:GetPlayerByUserId(b.userId)
	return holder ~= nil and S.A ~= nil and S.A.sameCrew(holder, player)
end

-- A booth seat taken: anyone the booth isn't for is stood up (before booking: anyone may sit).
function Nightclub._BoothSeat(seat)
	local occ = seat.Occupant
	local p = occ and Players:GetPlayerFromCharacter(occ.Parent)
	if p and S.booth and not boothAllowed(p) then
		local w = seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		if S.A then
			S.A.refuse(p, clubDef().Id, "BoothReserved")
		end
	end
end

local function endBooth(why)
	local b = S.booth
	S.booth = nil
	if b then
		local p = Players:GetPlayerByUserId(b.userId)
		if p then
			p:SetAttribute("BizBoothUntil", nil)
			if why and S.A then
				S.A.result(p, { Kind = "BoothOver", Id = clubDef().Id, Why = why })
			end
		end
	end
	boothLooks()
end

-- BizBoothPrompt at the booth's rope (see the header).
function Nightclub._Book(player)
	local A = S.A
	local def = clubDef()
	if not A or not def or not RateLimit.Allow(player, "BizBooth", 1, 2) then
		return
	end
	local hum, root = A.humOf(player), A.rootOf(player)
	if not hum or hum.Health <= 0 or not root or not isGuest(player) then
		return
	end
	if wanted(player) then
		A.refuse(player, def.Id, "ClubWanted")
		return
	end
	local at = CL.Origin + CL.BoothRope
	if flat(root.Position - at).Magnitude > CL.Reach then
		A.refuse(player, def.Id, "TooFar")
		return
	end
	local now = serverNow()
	if S.booth and Businesses.TimeLeft(S.booth.untilT, now) > 0 then
		A.refuse(player, def.Id, boothAllowed(player) and "BoothAlready" or "BoothTaken")
		return
	end
	local price, paidTo, free = def.Booth.Price, nil, A.owned(player, def.Id) ~= nil
	if free then
		price = 0
	else
		local paid
		paid, paidTo = A.serveCustomer(player, def, price, "bizbooth", def.Booth.Words)
		if not paid then
			return
		end
	end
	local untilT = now + CL.BoothSeconds / math.max(A.timeScale(), 0.01)
	S.booth = { userId = player.UserId, name = player.DisplayName, untilT = untilT, warned = false }
	player:SetAttribute("BizBoothUntil", untilT)
	boothLooks()
	A.result(player, { Kind = "BoothBooked", Id = def.Id, Until = untilT, Price = price, Free = free, Owner = paidTo })
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and A.sameCrew(player, p) then
			A.result(p, { Kind = "BoothCrew", Id = def.Id, Until = untilT, Name = player.DisplayName })
		end
	end
	Telemetry.Custom(player, "BizBooth_" .. def.Id, price)
end

------------------------------------------------------------------ the back room: WASH

-- The WASH hold at the safe counted (Raids.TimedPrompt timed it): see the header.
function Nightclub._Wash(player)
	local A = S.A
	local def = clubDef()
	if not A or not def then
		return
	end
	local entry = A.owned(player, def.Id)
	if not entry then
		A.refuse(player, def.Id, "WashNotYours")
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" then
		A.refuse(player, def.Id, "WashCivOnly")
		return
	end
	local hum, root = A.humOf(player), A.rootOf(player)
	local safe = Businesses.At(def, def.Layout.Safe)
	if not hum or hum.Health <= 0 or hum.SeatPart or not root or flat(root.Position - safe).Magnitude > BR.Reach + 2
		or math.abs(root.Position.Y - safe.Y) > 12 then
		A.refuse(player, def.Id, "TooFar")
		return
	end
	local t = os.clock()
	local readyAt = S.washAt[player.UserId] or 0
	if t < readyAt then
		A.result(player, { Kind = "No", Id = def.Id, Reason = "WashWait", Left = math.ceil(readyAt - t) })
		return
	end
	local amount, left = Businesses.BackRoomWashAmount(entry.dirty or 0, entry.level)
	if amount < 1 then
		A.refuse(player, def.Id, "BackRoomEmpty")
		return
	end
	entry.dirty = left
	entry.lifetime += amount
	EconomyService.AddCash(player, amount, "bizbackroom:" .. def.Id)
	A.addEmpireXP(player, E.XP.BackRoom)
	S.washAt[player.UserId] = t + BR.WashGap
	A.result(player, { Kind = "Washed", Id = def.Id, Amount = amount, Dirty = math.floor(left), Next = serverNow() + BR.WashGap })
	Telemetry.Custom(player, "BizBackRoomWash_" .. def.Id, amount)
	A.pushState(player)
end

------------------------------------------------------------------ VIP PICKUPS: the limo

-- The club's looks on the limo (Businesses.VipFitout): "Neon" pink underglow and an AFTERGLOW roof light; "Gold" gold
-- trim along both sides and the roof light in gold. Welded to the body (BodyRoot when the car has one), massless, never solid.
local function fitLimo(limo, kind, def)
	if kind ~= "Neon" and kind ~= "Gold" then
		return
	end
	local chassis = limo.PrimaryPart
	if not chassis then
		return
	end
	local body = limo:FindFirstChild("BodyRoot")
	local anchor = (body and body:IsA("BasePart")) and body or chassis
	local size = chassis.Size
	local function add(name, sz, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = sz
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		p.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = anchor, p
		w.Parent = p
		p.Parent = limo
		return p
	end
	local gold = kind == "Gold"
	local trim = gold and K.BRASS or def.Neon
	for _, sx in ipairs({ -1, 1 }) do
		add(gold and "GoldTrim" or "Underglow", Vector3.new(0.15, 0.2, size.Z - 2.5), chassis.CFrame * CFrame.new(sx * (size.X / 2 + 0.05), -size.Y / 2 + 0.15, 0),
			trim, gold and Enum.Material.Metal or Enum.Material.Neon)
	end
	local roof = add("RoofLight", Vector3.new(2.6, 0.5, 0.9), chassis.CFrame * CFrame.new(0, size.Y / 2 + 2.3, 1.5), Color3.fromRGB(24, 20, 28))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Oswald
	l.TextScaled = true
	l.TextColor3 = gold and K.BRASS or def.Neon
	l.Text = "AFTERGLOW"
	l.Parent = gui
	gui.Parent = roof
	local front = gui:Clone()
	front.Face = Enum.NormalId.Front
	front.Parent = roof
end

-- The limo in its bay, locked to the worker (M1's customer-car rules). Returns true when it's there.
local function spawnLimo(player, job, A)
	local def = job.def
	local level = A.levelOf(job.owner, def)
	local id = Vehicles.ById[V.Limo] and V.Limo or "Palmetto"
	local CarBuilder = require(ServerStorage.Tools.CarBuilder)
	local ok, limo = pcall(CarBuilder.Build, id, { Paint = Businesses.VipPaint(level) })
	if not ok or not limo or not limo.PrimaryPart or not limo:FindFirstChild("DriverSeat") then
		warn("[Nightclub] couldn't build the limo " .. tostring(id) .. ": " .. tostring(limo))
		if ok and typeof(limo) == "Instance" then
			limo:Destroy()
		end
		A.refuse(player, def.Id, "NoLimo")
		return false
	end
	local cf = Businesses.Frame(def) * CFrame.new(def.Layout.LimoBay) * CFrame.new(0, K.SEAT_UP, 0) -- (nose to the street)
	-- Nothing (a car, or anyone but the worker) in the bay?
	local list = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p ~= player then
			table.insert(list, p.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	if #Workspace:GetPartBoundsInBox(cf, limo.PrimaryPart.Size + Vector3.new(2, 4, 3), params) > 0 then
		limo:Destroy()
		A.refuse(player, def.Id, "LimoBlocked")
		return false
	end
	limo.Name = "ClubLimo"
	limo:SetAttribute("BizCar", true)
	limo:SetAttribute("BizVip", true)
	limo:SetAttribute("BizDriverUserId", player.UserId)
	limo:SetAttribute("BizId", def.Id)
	for _, d in ipairs(limo:GetDescendants()) do
		if d:IsA("ProximityPrompt") and (d.Name == "DrivePrompt" or d.Name == "RidePrompt") then
			d:Destroy()
		end
	end
	local seat = limo:FindFirstChild("DriverSeat")
	local chassis = limo.PrimaryPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BizDrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = "Club limo"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = K.DRIVE_REACH
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local p = occ and Players:GetPlayerFromCharacter(occ.Parent)
		if occ and (not p or p.UserId ~= limo:GetAttribute("BizDriverUserId")) then
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			return
		end
		if p then
			limo:SetAttribute("DriverUserId", p.UserId)
			pcall(function()
				chassis:SetNetworkOwner(p)
			end)
		else
			limo:SetAttribute("DriverUserId", nil)
			task.delay(1.5, function()
				if limo.Parent and seat.Occupant == nil and chassis:IsDescendantOf(Workspace) then
					pcall(function()
						chassis:SetNetworkOwner(nil)
					end)
				end
			end)
		end
	end)
	local pseat = limo:FindFirstChild("PassengerSeat")
	if pseat and pseat:IsA("Seat") then
		pseat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local sw = pseat.Occupant and pseat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy() -- (the VIP's seat: no player rides along)
			end
		end)
	end
	prompt.Triggered:Connect(function(who)
		local h = A.humOf(who)
		if who == player and A.jobOf(player) == job and job.car == limo and h and h.Health > 0 and h.SeatPart == nil and seat.Occupant == nil then
			seat:Sit(h)
		end
	end)
	fitLimo(limo, Businesses.VipFitout(level), def)
	job.car = limo -- (set before anything below can fail: BusinessService's endJob always finds and removes it)
	limo:PivotTo(cf)
	limo.Parent = Workspace.Vehicles
	pcall(function()
		chassis:SetNetworkOwner(nil)
	end)
	local guard = A.service("VehicleGuard")
	if guard and type(guard.Allow) == "function" then
		guard.Allow(limo, 3)
	end
	return true
end

------------------------------------------------------------------ VIP PICKUPS: the VIP

-- A VIP: one of the pedestrian looks (or plain colours), a posed statue (no Humanoid: SeatNPC's rule), every part
-- massless, not solid, invisible to rays; sunglasses, a gold name tag, a little sparkle. Anchored at `cf`.
local function makeVip(A, cf, name, special)
	local ok, model = pcall(function()
		local looks = ReplicatedStorage:FindFirstChild("PedTemplates")
		local list = looks and looks:GetChildren() or {}
		local p = #list > 0 and list[A.rng:NextInteger(1, #list)] or nil
		if p and p:IsA("Model") and p:FindFirstChild("HumanoidRootPart") and p:FindFirstChildOfClass("Humanoid") then
			return p:Clone()
		end
		local desc = Instance.new("HumanoidDescription")
		local c = K.SKINS[A.rng:NextInteger(1, #K.SKINS)]
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = c, c, c
		desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(20, 20, 24), Color3.fromRGB(20, 20, 24)
		desc.TorsoColor = K.SHIRTS[A.rng:NextInteger(1, #K.SHIRTS)]
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
	model.Name = "BizVip"
	model:SetAttribute("BizVip", true)
	model:PivotTo(cf)
	if head and head:IsA("BasePart") then
		local shades = Instance.new("Part")
		shades.Name = "Sunglasses"
		shades.Size = Vector3.new(1.05, 0.28, 0.12)
		shades.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.08, -head.Size.Z / 2 - 0.02)
		shades.Color = Color3.fromRGB(14, 14, 18)
		shades.Material = Enum.Material.Glass
		shades.Reflectance = 0.3
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, shades
		w.Parent = shades
		shades.Parent = model
		local tag = Instance.new("BillboardGui")
		tag.Name = "VipTag"
		tag.Size = UDim2.fromOffset(180, 26)
		tag.StudsOffset = Vector3.new(0, 3, 0)
		tag.MaxDistance = 160
		tag.AlwaysOnTop = true
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextScaled = true
		l.TextColor3 = Color3.fromRGB(255, 214, 10)
		l.TextStrokeTransparency = 0.4
		l.Text = "★ " .. string.upper(name) .. " ★"
		l.Parent = tag
		tag.Parent = head
		if special then
			local e = Instance.new("ParticleEmitter")
			e.Name = "VipSparkle"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.LightEmission = 1
			e.Rate = 5
			e.Lifetime = NumberRange.new(0.5, 0.9)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0) })
			e.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
			e.Parent = head
		end
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

-- Play one of CarBuilder's poses on the VIP ("sit" | "walk"), stopping any other.
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

-- The VIP says something (a bubble for everyone; BusinessService's say keeps its token on the record).
local function vipSay(job, words, seconds, A)
	local vip = job.vip
	if vip and vip.Parent then
		if not job.sayRec or job.sayRec.model ~= vip then
			job.sayRec = { model = vip }
		end
		A.say(job.sayRec, words, seconds or 2)
	end
end

local function clearVip(job)
	local vip = job.vip
	job.vip = nil
	if vip and vip.Parent then
		vip:Destroy()
	end
end

-- The road's kerb nearest `pos`, on the side of `pos` (within `reach` studs of the road's middle line), or nil.
local function kerbNear(pos, reach)
	local nodes = RoadGraph.Nodes
	local best, bestD, bestW
	for i, links in pairs(RoadGraph.Edges) do
		local a = nodes[i]
		if a then
			for j in pairs(links) do
				local b = nodes[j]
				if b and j > i then
					local ab = b - a
					local len2 = ab:Dot(ab)
					local t = len2 > 0 and math.clamp((flat(pos) - a):Dot(ab) / len2, 0, 1) or 0
					local p = a + ab * t
					local d = (flat(pos) - p).Magnitude
					if not bestD or d < bestD then
						best, bestD, bestW = p, d, RoadGraph.Width(i, j)
					end
				end
			end
		end
	end
	if not best or bestD > reach or bestD < 1 then
		return nil
	end
	return best + (flat(pos) - best).Unit * ((bestW or 32) / 2 + 4)
end

-- A pickup for a new VIP (see the header): { pos (the ring), wait (where the VIP stands), name, kind }, or nil.
local function pickPlace(player, job, A)
	local def = job.def
	local from = flat(def.Position)
	local want = takeTest(player, "BizTestPickup", function(v)
		return type(v) == "string"
	end)
	local named = {}
	for _, h in ipairs(V.Homes) do
		local home = Housing.ById[h.Id]
		local spots = home and Housing.Spot(home, "Driveway")
		if spots and #spots > 0 then
			local frame = Housing.Frame(home)
			local verge = (frame * CFrame.new(spots[#spots])).Position
			local d = (flat(verge) - from).Magnitude
			if (d >= V.DistMin and d <= V.DistMax) or want == h.Kind then
				table.insert(named, { pos = flat(verge), wait = flat((frame * CFrame.new(spots[#spots] + Vector3.new(-7, 0, 2))).Position),
					name = home.Name, kind = h.Kind })
			end
		end
	end
	local apts = A.service("ApartmentService")
	local okT, towers = false, nil
	if apts and type(apts.Towers) == "function" then
		okT, towers = pcall(apts.Towers)
	end
	for _, t in ipairs(okT and type(towers) == "table" and towers or {}) do
		if typeof(t.Door) == "Vector3" then
			local d = (flat(t.Door) - from).Magnitude
			if (d >= V.DistMin and d <= V.DistMax) or want == "TOWER" then
				local kerb = kerbNear(t.Door, V.TowerReach)
				if kerb then
					table.insert(named, { pos = kerb, wait = flat(kerb + (flat(t.Door) - kerb).Unit * 5), name = tostring(t.Name or "the tower"),
						kind = "TOWER" })
				end
			end
		end
	end
	local pool = {}
	for _, p in ipairs(named) do
		if not want or p.kind == want then
			table.insert(pool, p)
		end
	end
	if #pool > 0 and (want or A.rng:NextNumber() < V.NamedShare) then
		return pool[A.rng:NextInteger(1, #pool)]
	end
	local js = A.service("JobService")
	local roadside = js and js.RoadsideSpot
	local spot = type(roadside) == "function" and roadside(def.Position, V.HotelMin, V.HotelMax) or nil
	if spot then
		return { pos = flat(spot), wait = flat(spot), name = pick(V.Hotels, A), kind = "HOTEL" }
	end
	return named[1]
end

-- The VIP's numbers to the worker (the shift's "Vip" event: pickup or after).
local function sendVip(player, job, A, stage)
	local def = job.def
	A.fire(player, "Vip", {
		Id = job.id, Stage = stage, Name = job.vipName, Place = job.place and job.place.name, Kind = job.place and job.place.kind,
		Pos = job.place and job.place.pos, Carpet = Businesses.At(def, def.Layout.Carpet), Special = job.special, Night = isNight(A),
		Level = A.levelOf(job.owner, def), Owner = job.owner.UserId, OwnerName = job.owner.DisplayName, Count = job.count,
		Earned = job.earned, Streak = job.vipStreak or 0, Limo = job.car, Vips = job.vips or 0, Seated = job.car ~= nil and atWheel(player, job.car, A),
	})
end

-- A new VIP (stage "pickup"): who, where, the VIP waiting there.
local function setupVip(player, job, A)
	local place = pickPlace(player, job, A)
	if not place then
		A.refuse(player, job.id, "NoPickup")
		A.endJob(player, "NoPickup")
		return false
	end
	clearVip(job)
	job.place = place
	job.special = takeTest(player, "BizTestVip", function(v)
		return V.Specials[v] ~= nil
	end) or Businesses.RollVipSpecial(A.rng:NextNumber(), A.rng:NextNumber())
	job.vipName = pick(V.Names, A)
	job.stage = "pickup"
	job.comfort, job.comfortSent = 1, 100
	job.legFrom, job.legAt = nil, nil
	job.outSince = nil
	job.pap = nil
	job.papHeld, job.papLost = 0, false
	job.boardToken = (job.boardToken or 0) + 1
	player:SetAttribute("BizVipComfort", nil)
	local wait = place.wait or place.pos
	local cf = CFrame.lookAt(wait + Vector3.new(0, 3, 0), place.pos + Vector3.new(0, 3, 0) + Vector3.new(0.01, 0, 0.01))
	job.vip = makeVip(A, cf, job.vipName, job.special)
	if job.vip then
		local vip = job.vip
		pcall(function()
			local ctl = vip:FindFirstChildOfClass("AnimationController")
			local animator = ctl and (ctl:FindFirstChildOfClass("Animator") or Instance.new("Animator", ctl))
			local anim = Instance.new("Animation")
			anim.AnimationId = K.IDLE
			local track = animator:LoadAnimation(anim)
			track.Looped = true
			track:Play()
		end)
	end
	local limo = job.car
	local chassis = limo and limo.PrimaryPart
	if chassis then
		job.legFrom, job.legAt = flat(chassis.Position), os.clock()
		job.top = topSpeed(limo)
	end
	sendVip(player, job, A, "pickup")
	return true
end

-- The leg just finished passed the speed check (as a taxi fare's)? Ends the shift ("Invalid") when not.
local function legOk(player, job, t, at, radius, A)
	local took = t - (job.legAt or t)
	local gap = math.max(0, (flat(at) - (job.legFrom or flat(at))).Magnitude - radius)
	local fastest = gap / (math.max(job.top or 0, 1) * V.FastSlack)
	local guard = A.service("VehicleGuard")
	if took < fastest or (guard and type(guard.RecentlyFlagged) == "function" and guard.RecentlyFlagged(player, took)) then
		warn(string.format("[Nightclub] refused %s's VIP leg: %.2fs (at least %.2fs)", player.Name, took, fastest))
		A.endJob(player, "Invalid")
		return false
	end
	return true
end

------------------------------------------------------------------ VIP PICKUPS: the paparazzi

local function raceAI(A)
	local r = A.service("RaceAIService")
	if r and type(r.Spawn) == "function" and type(r.Route) == "function" and type(r.Plan) == "function" and type(r.Release) == "function"
		and type(r.Position) == "function" and type(r.Remove) == "function" then
		return r
	end
	return nil
end

-- The paparazzi go (after `delay` seconds: they drive off first).
local function papClear(job, delay)
	local list = job.paps
	job.paps = nil
	if not list then
		return
	end
	local A = S.A
	local r = A and raceAI(A)
	if not r then
		return
	end
	for _, rec in ipairs(list) do
		pcall(function()
			if type(r.Done) == "function" then
				r.Done(rec.bot)
			end
		end)
	end
	task.delay(delay or 0, function()
		for _, rec in ipairs(list) do
			pcall(r.Remove, rec.bot)
		end
	end)
end

-- The paparazzi appear on a road behind the limo and give chase (see the header).
local function papSpawn(player, job, A)
	local r = raceAI(A)
	local limo = job.car
	local chassis = limo and limo.PrimaryPart
	if not r or not chassis then
		job.pap = "none"
		return
	end
	local pos = flat(chassis.Position)
	local look = flat(chassis.CFrame.LookVector)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local cands = {}
	for _, n in ipairs(RoadGraph.Nodes) do
		local d = (n - pos).Magnitude
		if d >= V.Pap.SpawnMin and d <= V.Pap.SpawnMax then
			table.insert(cands, { n = n, behind = (n - pos):Dot(look) < 0, d = d })
		end
	end
	table.sort(cands, function(a, b)
		if a.behind ~= b.behind then
			return a.behind
		end
		return a.d < b.d
	end)
	job.paps = {}
	local count = Businesses.PapCars(A.levelOf(job.owner, job.def))
	for i = 1, count do
		local c = cands[i] or cands[1]
		if c then
			local at = c.n + Vector3.new((i - 1) * 6, 3.2, 0)
			local cf = CFrame.lookAt(at, Vector3.new(pos.X, at.Y, pos.Z))
			local okSpawn, bot = pcall(r.Spawn, { CFrame = cf, Name = "PAPARAZZI", Legs = r.Plan(nil, at, { pos }), Lane = i == 1 and -3 or 3,
				Top = V.Pap.Top, Car = V.Pap.Car, Paint = V.Pap.Paint })
			if okSpawn and bot and bot.car then
				bot.car:SetAttribute("BizPap", true)
				bot.car:SetAttribute("BizPapFor", player.UserId)
				local flash = Instance.new("PointLight")
				flash.Name = "PapFlash"
				flash.Color = Color3.new(1, 1, 1)
				flash.Brightness = 7
				flash.Range = 20
				flash.Shadows = false
				flash.Enabled = false
				flash.Parent = bot.chassis or bot.car.PrimaryPart
				pcall(r.Release, bot)
				table.insert(job.paps, { bot = bot, flash = flash, planAt = 0, near = false })
			end
		end
	end
	if #job.paps == 0 then
		job.paps = nil
		job.pap = "none"
		return
	end
	job.pap = "chase"
	job.papHeld = 0
	A.fire(player, "VipPap", { Id = job.id, Cars = #job.paps })
	vipSay(job, pick(K.COMPLAIN.Flash, A), 2, A)
	Telemetry.Custom(player, "BizVipPap_" .. job.id, #job.paps)
end

-- Four times a second on a ride with paparazzi: their routes, their flashes, losing them. Returns true while one of
-- them is flashing close by (the comfort drains).
local function papTick(player, job, t, dt, A)
	if job.pap ~= "chase" or not job.paps then
		return false
	end
	local r = raceAI(A)
	local chassis = job.car and job.car.PrimaryPart
	if not r or not chassis then
		return false
	end
	local pos = chassis.Position
	local nearest
	local flashing = false
	for i = #job.paps, 1, -1 do
		local rec = job.paps[i]
		local at = r.Position(rec.bot)
		if not at then
			table.remove(job.paps, i) -- (a broken or stuck-for-good NPC: it's simply gone)
		else
			local d = (flat(at) - flat(pos)).Magnitude
			nearest = nearest and math.min(nearest, d) or d
			if t - rec.planAt >= V.Pap.Replan then
				rec.planAt = t
				if d < V.Pap.Near then
					if type(r.Done) == "function" then
						r.Done(rec.bot) -- (right behind you: ease off, no ramming)
					end
					rec.near = true
				else
					pcall(r.Route, rec.bot, r.Plan(nil, at, { flat(pos) }))
					rec.near = false
				end
			end
			local close = d < V.Pap.FlashRange
			flashing = flashing or close
			if rec.flash and rec.flash.Parent then
				rec.flash.Enabled = close and not rec.flash.Enabled -- (blinking)
			end
		end
	end
	local held, lost = Businesses.PapStep(nearest, job.papHeld, dt)
	job.papHeld = held
	if lost then
		job.pap = "lost"
		job.papLost = true
		local level = A.levelOf(job.owner, job.def)
		local sp = job.special and V.Specials[job.special]
		A.fire(player, "VipLost", { Id = job.id, Bonus = math.floor(V.Pap.Bonus * (sp and sp.PapMult or 1) * Businesses.JobMult(job.def, level) + 0.5) })
		vipSay(job, "Ha! Lost them!", 2, A)
		papClear(job, 4)
		Telemetry.Custom(player, "BizVipLost_" .. job.id, 1)
	end
	return flashing
end

------------------------------------------------------------------ VIP PICKUPS: the pickup and the carpet

-- Stopped at the pickup: the VIP walks to the limo and gets in, then the ride begins.
local function board(player, job, t, A)
	job.stage = "board"
	local token = job.boardToken
	local limo = job.car
	task.spawn(function()
		local function live()
			return A.jobOf(player) == job and job.boardToken == token and job.car == limo and limo.Parent ~= nil
		end
		local vip = job.vip
		local root = vip and vip.Parent and vip:FindFirstChild("HumanoidRootPart")
		local chassis = limo.PrimaryPart
		if root and chassis then
			local door = chassis:FindFirstChild("PassengerDoor")
			local to = (door and door:IsA("Attachment")) and door.WorldPosition or (chassis.CFrame * CFrame.new(chassis.Size.X / 2 + 2.2, 0, 0)).Position
			to = Vector3.new(to.X, root.Position.Y, to.Z)
			pose(vip, "walk")
			local d = (to - root.Position).Magnitude
			if d > 0.5 then
				local tw = TweenService:Create(root, TweenInfo.new(math.clamp(d / K.WALK, 0.3, V.BoardTime), Enum.EasingStyle.Linear),
					{ CFrame = CFrame.lookAt(to, to + (to - root.Position).Unit) })
				tw:Play()
				tw.Completed:Wait()
			end
		end
		if not live() then
			return
		end
		local seated = false
		if vip and vip.Parent then
			local vs = A.service("VehicleService")
			if vs and type(vs.SeatNPC) == "function" then
				local okSeat, seat = pcall(vs.SeatNPC, limo, vip)
				seated = okSeat and seat ~= nil
			end
			if seated then
				pose(vip, "sit")
			else
				vip:Destroy() -- (no seat for them: they ride out of sight, as a taxi fare would)
				job.vip = nil
			end
		end
		task.wait(0.4)
		if not live() then
			return
		end
		-- The ride begins: the clock, the comfort, maybe the paparazzi.
		local here = flat(limo.PrimaryPart.Position)
		local carpet = flat(Businesses.At(job.def, job.def.Layout.Carpet))
		local road = here and carpet and (function()
			local okPath, path = pcall(RoadGraph.Path, here, carpet)
			local len = 0
			if okPath and path then
				for i = 2, #path do
					len += (path[i] - path[i - 1]).Magnitude
				end
			end
			return math.max(len, (carpet - here).Magnitude)
		end)() or 0
		local sp = job.special and V.Specials[job.special]
		job.roadBack = road
		job.par = Businesses.VipPar(road, sp and sp.ParMult)
		job.stage = "ride"
		job.rideAt = os.clock()
		job.legFrom, job.legAt = here, os.clock()
		job.top = topSpeed(limo)
		job.lastPos, job.lastT, job.lastSpeed, job.lastYaw = here, os.clock(), 0, nil
		job.lastRamAt, job.lastAirAt, job.lastSayAt, job.drained = -math.huge, -math.huge, 0, 0
		job.bumpedAt = limo:GetAttribute("BumpedAt")
		local forced = takeTest(player, "BizTestPap", function(v)
			return v == true
		end)
		local papComing = forced == true or Businesses.PapRoll(A.rng:NextNumber(), job.special)
		job.pap = papComing and "coming" or nil
		job.papAt = os.clock() + V.Pap.Delay
		player:SetAttribute("BizVipComfort", 100)
		local line = pick(K.BOARD, A)
		vipSay(job, line, 2.5, A)
		A.fire(player, "VipAboard", { Id = job.id, Par = job.par, Road = road, Line = line, Special = job.special, Name = job.vipName,
			Night = isNight(A), Pap = papComing and raceAI(A) ~= nil })
	end)
end

-- The press's flashes at the carpet (lights at Layout.Flashes, a few quick blinks, for everyone).
local function carpetFlashes(def, A)
	local site = A.site(def.Id)
	if not site or not site.model.Parent then
		return
	end
	local f = Businesses.Frame(def)
	for i, spot in ipairs(def.Layout.Flashes or {}) do
		local holder = A.Build.holder(site.model, "PressFlash", f, spot + Vector3.new(0, 5, 0), Vector3.new(0.5, 0.5, 0.5))
		local l = Instance.new("PointLight")
		l.Color = Color3.new(1, 1, 1)
		l.Brightness = 9
		l.Range = 14
		l.Shadows = false
		l.Enabled = false
		l.Parent = holder
		task.spawn(function()
			task.wait((i - 1) * 0.11)
			for _ = 1, 5 do
				if not l.Parent then
					return
				end
				l.Enabled = true
				task.wait(0.07)
				l.Enabled = false
				task.wait(K.FLASH_TIME / 5 - 0.07)
			end
			holder:Destroy()
		end)
	end
end

-- The VIP steps out and walks up the carpet through the flashes, then fades at the doors; then the AFTER panel.
local function walkCarpet(player, job, stars, A)
	local token = job.boardToken
	local def = job.def
	local vip = job.vip
	local limo = job.car
	task.spawn(function()
		if vip and vip.Parent then
			local vs = A.service("VehicleService")
			if vs and type(vs.ReleaseNPC) == "function" then
				pcall(vs.ReleaseNPC, vip)
			end
			local root = vip:FindFirstChild("HumanoidRootPart")
			local chassis = limo and limo.PrimaryPart
			if root and chassis then
				local door = chassis:FindFirstChild("PassengerDoor")
				local out = (door and door:IsA("Attachment")) and door.WorldPosition or (chassis.CFrame * CFrame.new(chassis.Size.X / 2 + 2.2, 0, 0)).Position
				vip.Parent = A.npcFolder()
				root.Anchored = true
				local y = Businesses.At(def, Vector3.new(0, 3.1, 0)).Y
				local start = Vector3.new(out.X, y, out.Z)
				local onCarpet = Businesses.At(def, Vector3.new(0, 3.1, def.Layout.Carpet.Z))
				local doorAt = Businesses.At(def, def.Layout.Door + Vector3.new(0, 3.1, 1.5))
				root.CFrame = CFrame.lookAt(start, onCarpet)
				pose(vip, "walk")
				local legs = { onCarpet, doorAt }
				local total = (onCarpet - start).Magnitude + (doorAt - onCarpet).Magnitude
				local from = start
				task.delay(0.3, function()
					vipSay(job, pick(K.ARRIVE[math.clamp(stars, 1, 3)], A), 2, A)
				end)
				for _, to in ipairs(legs) do
					local d = (to - from).Magnitude
					if d > 0.3 and vip.Parent then
						local tw = TweenService:Create(root, TweenInfo.new(math.max(0.2, V.CarpetTime * d / math.max(total, 1)), Enum.EasingStyle.Linear),
							{ CFrame = CFrame.lookAt(to, to + (to - from).Unit) })
						tw:Play()
						tw.Completed:Wait()
					end
					from = to
				end
				if vip.Parent then
					A.fadeOut(vip, 0.5)
				end
			elseif vip.Parent then
				vip:Destroy()
			end
		else
			task.wait(V.CarpetTime)
		end
		if job.vip == vip then
			job.vip = nil
		end
		if A.jobOf(player) ~= job or job.boardToken ~= token then
			return
		end
		job.stage = "after"
		job.afterSince = os.clock()
		sendVip(player, job, A, "after")
	end)
end

-- Stopped in the red-carpet ring: the speed check, the stop's grade, the pay (see the header).
local function arrive(player, job, t, A)
	local def = job.def
	local limo = job.car
	local chassis = limo.PrimaryPart
	local mark = flat(Businesses.At(def, def.Layout.Carpet))
	if not legOk(player, job, t, mark, V.CarpetRadius, A) then
		return
	end
	job.stage = "carpet"
	local dist = (flat(chassis.Position) - mark).Magnitude
	local stop = Businesses.VipStop(dist)
	local level = A.levelOf(job.owner, def)
	local took = t - (job.rideAt or t)
	local night = isNight(A)
	local hadStreak = job.vipStreak or 0
	local pap = job.pap == "chase" or job.pap == "lost"
	local pay, tip, stars, streak, bonus, share = Businesses.VipPay(def, level, {
		road = (job.roadOut or 0) + (job.roadBack or 0), took = took, par = job.par, comfort = job.comfort, stop = stop, lost = job.papLost == true,
		special = job.special, streak = hadStreak, night = night,
	})
	job.vipStreak = streak
	if job.pap == "chase" then
		job.pap = "shot" -- (they got their photos: no bonus, and they go)
		papClear(job, 4)
	end
	player:SetAttribute("BizVipComfort", nil)
	local total = pay + tip + bonus
	EconomyService.AddCash(player, total, "bizjob:" .. job.id .. ":vip")
	job.count += 1
	job.earned += total
	job.vips = (job.vips or 0) + 1
	local st = job.stats
	st.pickups += 1
	st.stars3 += stars == 3 and 1 or 0
	st.perfects += stop == "Perfect" and 1 or 0
	st.paps += pap and 1 or 0
	st.lost += job.papLost and 1 or 0
	st.best = math.max(st.best, streak)
	st.specials += job.special and 1 or 0
	st.night += night and 1 or 0
	st.comfortSum += job.comfort or 0
	A.creditOwner(job, player, total)
	A.addEmpireXP(player, E.XP.Vip)
	A.progressEvent(player, "BusinessJob", 1)
	Telemetry.Custom(player, "BizVip_" .. job.id, total)
	A.fire(player, "VipPaid", {
		Id = job.id, Pay = pay, Tip = tip, Bonus = bonus, Stars = stars, Streak = streak, Mult = Businesses.StreakMult(streak, Businesses.Streak),
		Broke = hadStreak >= 2 and streak == 0 and hadStreak or nil, Stop = stop, Dist = math.floor(dist * 10) / 10, Comfort = job.comfort,
		OnTime = took <= (job.par or 0), Took = took, Par = job.par, Lost = job.papLost == true, Pap = pap, Night = night, Special = job.special,
		Name = job.vipName, Share = share, Count = job.count, Earned = job.earned,
	})
	if job.owner ~= player then
		A.pushState(job.owner)
	end
	carpetFlashes(def, A)
	walkCarpet(player, job, stars, A)
end

-- Four times a second on a ride: the comfort, the paparazzi, the carpet.
local function rideTick(player, job, t, A)
	local limo = job.car
	local chassis = limo.PrimaryPart
	local pos = flat(chassis.Position)
	if pos.X ~= pos.X or pos.Z ~= pos.Z then
		return
	end
	local dt = math.max(t - (job.lastT or t), 0.05)
	local vel = chassis.AssemblyLinearVelocity
	local speed = flat(vel).Magnitude
	job.top = math.max(job.top or 0, topSpeed(limo))
	-- THE COMFORT: the turn (heading change x speed), crashes, leaving the ground, paparazzi flashing.
	local look = flat(chassis.CFrame.LookVector)
	local yaw = look.Magnitude > 0.1 and math.atan2(look.X, look.Z) or nil
	local lat = 0
	if yaw and job.lastYaw then
		local d = (yaw - job.lastYaw + math.pi) % (2 * math.pi) - math.pi
		lat = speed * math.abs(d) / dt
	end
	job.lastYaw = yaw
	local M = V.Comfort
	local ram = false
	local last = job.lastSpeed or 0
	if last >= M.RamMinSpeed and (last - speed) / dt >= M.RamDecel and speed < last * 0.5 and t - job.lastRamAt >= M.RamGap then
		ram = true
	end
	local bumped = limo:GetAttribute("BumpedAt")
	if bumped ~= job.bumpedAt then
		job.bumpedAt = bumped
		if t - job.lastRamAt >= M.RamGap then
			ram = true
		end
	end
	if ram then
		job.lastRamAt = t
	end
	local air = false
	if math.abs(vel.Y) > M.AirSpeed and t - job.lastAirAt >= M.AirGap then
		air = true
		job.lastAirAt = t
	end
	-- The paparazzi: appear after their delay, then chase.
	if job.pap == "coming" and os.clock() >= (job.papAt or 0) then
		papSpawn(player, job, A)
	end
	local flash = papTick(player, job, t, dt, A)
	local comfort, drop = Businesses.VipComfort(job.comfort, dt, lat, ram, air, flash)
	job.comfort = comfort
	local pct = math.floor(comfort * 100 + 0.5)
	if math.abs(pct - (job.comfortSent or 100)) >= K.COMFORT_STEP * 100 then
		job.comfortSent = pct
		player:SetAttribute("BizVipComfort", pct)
	end
	job.drained = (job.drained or 0) * 0.8 + ((ram or air) and 0 or drop)
	local why = (ram and "Ram") or (air and "Air") or (job.drained >= M.Say and (flash and "Flash" or "Turn")) or nil
	if why and t - job.lastSayAt >= K.SAY_GAP then
		job.lastSayAt = t
		job.drained = 0
		vipSay(job, pick(K.COMPLAIN[why], A), 1.8, A)
		A.fire(player, "VipComfort", { Id = job.id, Comfort = comfort, Why = why })
	end
	-- THE RED CARPET: stopped in its ring.
	local mark = flat(Businesses.At(job.def, job.def.Layout.Carpet))
	if (pos - mark).Magnitude <= V.CarpetRadius and speed < V.StopSpeed then
		arrive(player, job, t, A)
		return
	end
	job.lastPos, job.lastT, job.lastSpeed = pos, t, speed
end

------------------------------------------------------------------ VIP PICKUPS: the hooks

function Nightclub.Start(player, job, A)
	S.A = A
	job.vips = 0
	job.vipStreak = 0
	job.stats = { pickups = 0, stars3 = 0, perfects = 0, paps = 0, lost = 0, best = 0, specials = 0, night = 0, comfortSum = 0 }
	job.startedAt = os.clock()
	if not spawnLimo(player, job, A) then
		A.endJob(player, "NoLimo")
		return
	end
	if not setupVip(player, job, A) then
		return
	end
	-- At the wheel straight away (the bay is a few steps from the door; Tick waits SeatGrace for the walk).
	local hum = A.humOf(player)
	local limo = job.car
	task.defer(function()
		local seat = limo and limo.Parent and limo:FindFirstChild("DriverSeat")
		if A.jobOf(player) == job and seat and seat.Occupant == nil and hum and hum.Parent and hum.Health > 0 and hum.SeatPart == nil then
			seat:Sit(hum)
		end
	end)
end

function Nightclub.Resend(player, job, A)
	if job.stage == "ride" then
		sendVip(player, job, A, "pickup")
		A.fire(player, "VipAboard", { Id = job.id, Par = job.par, Road = job.roadBack, Special = job.special, Name = job.vipName, Night = isNight(A),
			Pap = job.pap == "coming" or job.pap == "chase", Resend = true })
	else
		sendVip(player, job, A, job.stage == "after" and "after" or "pickup")
	end
end

-- RequestBusiness("Step", "Next"): NEXT VIP at the club (after the last one walked in).
function Nightclub.Step(player, job, step, A)
	if step == "Next" and job.stage == "after" then
		local limo = job.car
		local hum, root = A.humOf(player), A.rootOf(player)
		local seat = limo and limo:FindFirstChild("DriverSeat")
		setupVip(player, job, A)
		if seat and hum and root and hum.Health > 0 and hum.SeatPart == nil and seat.Occupant == nil and (root.Position - seat.Position).Magnitude <= 40 then
			seat:Sit(hum)
		end
	end
end

-- Four times a second (BusinessService's jobsTick, after its own end rules).
function Nightclub.Tick(player, job, t, A)
	local limo = job.car
	local chassis = limo and limo.Parent and limo.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
		A.endJob(player, "LimoGone")
		return
	end
	if chassis.Position.Y < 0.2 then
		job.sunkSince = job.sunkSince or t
		if t - job.sunkSince >= 2 then
			A.endJob(player, "LimoGone")
		end
		return
	end
	job.sunkSince = nil
	if job.stage == "pickup" or job.stage == "ride" then
		if not atWheel(player, limo, A) then
			job.outSince = job.outSince or t
			if t - job.outSince > (job.everSeated and V.LeaveGrace or V.SeatGrace) then
				A.endJob(player, "LeftLimo")
			end
			job.lastPos, job.lastT, job.lastSpeed, job.lastYaw = flat(chassis.Position), t, 0, nil
			return
		end
		job.outSince = nil
		if not job.everSeated then
			job.everSeated = true
			job.legFrom, job.legAt = flat(chassis.Position), t -- (the first leg starts when you first drive)
		end
		if job.stage == "pickup" then
			local p = job.place
			local speed = chassis.AssemblyLinearVelocity.Magnitude
			if p and (flat(chassis.Position) - p.pos).Magnitude <= V.PickupRadius and speed < V.StopSpeed then
				if not legOk(player, job, t, p.pos, V.PickupRadius, A) then
					return
				end
				-- The road out (paid with the ride back).
				local okPath, path = pcall(RoadGraph.Path, flat(job.def.Position), p.pos)
				local len = 0
				if okPath and path then
					for i = 2, #path do
						len += (path[i] - path[i - 1]).Magnitude
					end
				end
				job.roadOut = math.max(len, (p.pos - flat(job.def.Position)).Magnitude)
				board(player, job, t, A)
			end
		else
			rideTick(player, job, t, A)
		end
	elseif job.stage == "after" then
		-- Between VIPs at the club: wander a little if you like, but not off, and not for ever.
		local root = A.rootOf(player)
		if not root or (root.Position - chassis.Position).Magnitude > V.LeaveRange then
			job.outSince = job.outSince or t
			if t - job.outSince > V.LeaveGrace then
				A.endJob(player, "LeftLimo")
				return
			end
		else
			job.outSince = nil
		end
		if t - (job.afterSince or t) > V.IdleTime then
			A.endJob(player, "Idle")
		end
	end
end

-- The shift's end (any reason): the VIP and the paparazzi go (BusinessService removes the limo), and the report.
function Nightclub.End(player, job, _reason, _A)
	job.boardToken = (job.boardToken or 0) + 1
	clearVip(job)
	papClear(job, 0)
	if player.Parent == Players then
		player:SetAttribute("BizVipComfort", nil)
	end
	local st = job.stats or {}
	return {
		Report = {
			Pickups = st.pickups or 0, Stars3 = st.stars3 or 0, Perfects = st.perfects or 0, Paps = st.paps or 0, Lost = st.lost or 0,
			Best = st.best or 0, Specials = st.specials or 0, Night = st.night or 0,
			Comfort = (st.pickups or 0) > 0 and math.floor((st.comfortSum or 0) / st.pickups * 100 + 0.5) or nil,
		},
	}
end

------------------------------------------------------------------ the hooks BusinessService calls

function Nightclub.Init(A)
	S.A = A
	S.fadeRemote = Remotes.Event("HouseFade")
	local def = clubDef()
	if not def then
		return
	end
	local L = def.Layout
	Raids.Init(A)
	Raids.Register(def.Id, {
		cap = function(level)
			return Businesses.BackRoomStock(level)
		end,
		minDirty = BR.MinDirty,
		breachHold = function(_level)
			return RA.BreachHold
		end,
		breach = L.BackDoor, breachOut = 0.8, breachUp = 4,
		search = L.Search, searchUp = 3.5, face = L.Safe,
		wayIn = L.RaidWayIn, pathIn = L.RaidPathIn,
		words = {
			place = "Afterglow back room", stuff = "in dirty cash", searchObject = "The safe", inSay = "We're in! Check the safe!",
			heldSay = "Step away from the safe!",
		},
	})
	-- Nobody is in a club that isn't there (a place saved mid-visit).
	local old = Workspace:FindFirstChild("BizClubInterior")
	if old then
		old:Destroy()
	end
end

-- Once a second: the back room's card game, the raids, the club's guests and booth, the music, taking the club down.
function Nightclub.Second(dt, A)
	S.A = A
	local def = clubDef()
	if not def or not A.site(def.Id) then
		return
	end
	-- The back room: dirty cash at night for every owner online.
	local night = isNight(A)
	local scale = A.timeScale()
	for _, p in ipairs(Players:GetPlayers()) do
		local entry = A.play(p) and A.owned(p, def.Id)
		if entry then
			entry.dirty = Businesses.BackRoomAccrue(entry.dirty or 0, entry.level, dt * scale, night)
		end
	end
	Raids.Second(def.Id, dt, A)
	-- The club's guests.
	local now = serverNow()
	local count = 0
	for uid, g in pairs(S.guests) do
		local p = Players:GetPlayerByUserId(uid)
		if not p then
			S.guests[uid] = nil
		elseif not S.busy[uid] then
			local root = A.rootOf(p)
			if p.Character ~= g.char or not A.alive(p) or not root or (root.Position - CL.Origin).Magnitude > CL.KeepIn then
				leaveClub(p, "Gone", true) -- (respawned, arrested or moved off by something else)
			elseif wanted(p) then
				task.spawn(leaveClub, p, "Wanted")
			else
				count += 1
				-- The booth: only its party inside it.
				if S.booth and Businesses.InBooth(root.Position) and not boothAllowed(p) then
					moveTo(p, CFrame.lookAt(CL.Origin + CL.BoothOut + Vector3.new(0, 3.5, 0), CL.Origin + Vector3.new(0, 3.5, -4)))
					A.refuse(p, def.Id, "BoothReserved")
				end
			end
		else
			count += 1
		end
	end
	-- The booth's clock.
	local b = S.booth
	if b then
		local holder = Players:GetPlayerByUserId(b.userId)
		local left = Businesses.TimeLeft(b.untilT, now)
		if not holder then
			endBooth(nil)
		elseif left <= 0 then
			endBooth("Time")
		elseif not b.warned and left <= CL.BoothWarn then
			b.warned = true
			A.result(holder, { Kind = "BoothWarn", Id = def.Id, Left = left })
		end
	end
	-- The club itself: the music, and taking it down when it's been empty for a while.
	local club = S.club
	if club then
		if count > 0 then
			club.emptySince = nil
			if club.music and os.clock() >= (club.trackAt or 0) then
				nextTrack()
			end
		else
			club.emptySince = club.emptySince or os.clock()
			if os.clock() - club.emptySince >= CL.EmptyFor then
				clubDown()
			end
		end
	end
end

-- This business's extra numbers in BusinessState (the card, the EMPIRE app): the back room, the raid, the night.
function Nightclub.State(player, def, entry)
	local A = S.A
	local level = entry.level
	local ready = S.washAt[player.UserId]
	return {
		Dirty = math.floor(entry.dirty or 0), Stock = Businesses.BackRoomStock(level), Wash = Businesses.BackRoomWash(level),
		WashAt = (ready and ready > os.clock()) and (serverNow() + (ready - os.clock())) or nil, Raid = Raids.State(player, def.Id),
		Night = isNight(A), BackRoom = true,
	}
end

-- The raid at the club this player is part of (their BizAlarm: the map flashes).
function Nightclub.Alarms(player)
	local def = clubDef()
	return def and Raids.Alarms(player, def.Id) or {}
end

function Nightclub.PlayerLeft(player, _A)
	local def = clubDef()
	if def then
		Raids.PlayerLeft(player, def.Id)
	end
	S.guests[player.UserId] = nil
	S.busy[player.UserId] = nil
	S.washAt[player.UserId] = nil
	if S.booth and S.booth.userId == player.UserId then
		endBooth(nil)
	end
end

-- Studio helpers (see the header). nil = not one of ours.
function Nightclub.Debug(player, cmd, id, value, A)
	S.A = A
	local def = clubDef()
	if not def then
		return nil
	end
	if cmd == "raid" or cmd == "endraid" then
		if id ~= def.Id then
			return nil -- (the Print Shop's, by default)
		end
		return Raids.Debug(player, cmd, def.Id, value, A)
	elseif cmd == "celeb" then
		local v = tostring(value or "")
		if v == "" or v == "none" then
			player:SetAttribute("BizTestVip", nil)
			return "next VIP: whatever the roll says"
		end
		if not V.Specials[v] then
			return "celeb: Superstar, Tabloid or Late (\"\" clears it)"
		end
		player:SetAttribute("BizTestVip", v) -- (an attribute, not a table keyed by the player: used up by the next VIP)
		return "your next VIP is a " .. V.Specials[v].Name
	elseif cmd == "pickup" then
		local v = string.upper(tostring(value or ""))
		player:SetAttribute("BizTestPickup", v ~= "" and v or nil)
		return v ~= "" and ("your next pickup: " .. v) or "next pickup: any"
	elseif cmd == "papz" then
		local job = A.jobOf(player)
		if job and job.mod == Nightclub and job.stage == "ride" and job.pap ~= "chase" then
			job.pap = "coming"
			job.papAt = 0
			return "paparazzi coming now"
		end
		player:SetAttribute("BizTestPap", true)
		return "paparazzi on your next ride"
	elseif cmd == "comfort" then
		local job = A.jobOf(player)
		if not job or job.mod ~= Nightclub then
			return "not on VIP pickups"
		end
		job.comfort = math.clamp(tonumber(value) or 1, 0, 1)
		return string.format("VIP comfort %d%%", math.floor(job.comfort * 100 + 0.5))
	elseif cmd == "night" then
		local v = tostring(value or "")
		local want = nil
		if v == "on" or v == "true" then
			want = true
		elseif v == "off" or v == "false" then
			want = false
		end
		Workspace:SetAttribute("BizTestNight", want)
		return "BizTestNight = " .. tostring(want)
	elseif cmd == "backroom" or cmd == "washready" or cmd == "booth" or cmd == "club" then
		local entry = A.owned(player, def.Id)
		if cmd == "backroom" then
			if not entry then
				return "doesn't own the Nightclub (give it first)"
			end
			entry.dirty = math.max(0, math.floor(tonumber(value) or Businesses.BackRoomStock(entry.level)))
			A.pushState(player)
			return "back room " .. entry.dirty .. " / " .. Businesses.BackRoomStock(entry.level)
		elseif cmd == "washready" then
			S.washAt[player.UserId] = nil
			return "the tills are free: WASH again now"
		elseif cmd == "booth" then
			if not S.booth then
				return "nobody has the booth"
			end
			S.booth.untilT = serverNow() + math.max(1, tonumber(value) or 70)
			S.booth.warned = Businesses.TimeLeft(S.booth.untilT, serverNow()) <= CL.BoothWarn and S.booth.warned or false
			local p = Players:GetPlayerByUserId(S.booth.userId)
			if p then
				p:SetAttribute("BizBoothUntil", S.booth.untilT)
			end
			return string.format("the booth ends in %ds", math.floor(S.booth.untilT - serverNow()))
		else
			if value == "out" then
				if not isGuest(player) then
					return "not in the club"
				end
				Nightclub._Leave(player, "Player")
				return "out of the club"
			end
			if isGuest(player) then
				return "in the club already"
			end
			task.spawn(enterClub, player, A, { free = true, price = 0 })
			return "into the club (free)"
		end
	end
	return nil
end

return Nightclub
