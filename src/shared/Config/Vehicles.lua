-- Vehicles (ModuleScript, ReplicatedStorage.Shared.Config.Vehicles)
-- One entry per vehicle. Accelerations are in studs/s^2 so tuning doesn't depend on part mass.
-- Stats come from the Game Design Spec; they are starting values for playtest tuning.
-- Hidden = true: not a car anyone can buy, own or spawn (the carjack street cars and the Big Score's
-- armored van at the end); every list shown to players skips it.
-- UnlockHeists = N: bought with cash as usual, but only after N big heists (Coastal Bank / Sea Dream,
-- your own or your crew's: player attribute BigHeists, HeistService). GarageService refuses before
-- that (CarNeedsHeists); the dealer tags and card show "N BIG HEISTS (x/N)".
-- SeatDrop / SeatZ / SeatTilt (optional): a hand-tuned seat fit for a car with a mesh body, checked by eye
-- in game (CarBuilder.fitSeats). SeatDrop: studs the seat top sits below the greybox seat top (negative
-- raises it; also turns the automatic recline off). SeatZ: seat centre along the car (studs, front is -Z).
-- SeatTilt: degrees the seat leans back (0-45). The ServerStorage.CarBodies templates carry the same
-- values as attributes (tools/CAR_BODIES.md) and theirs win; these copies keep the fix when a body is
-- re-prepared and loses its attributes. Change both together.
-- Boats: SeatY (studs above the chassis centre: the seat's middle) and SeatZ place the driver on the deck
-- (the passenger 2.4 behind); the template's attributes win here too. Without either, the old spot just
-- over the chassis is kept, which on a tall hull is inside it.
-- Every seat a car's own fit put under a roof also fits each rider to their own size as they sit down
-- (CarBuilder.FitRider: taller avatars and hats sink in and lean back instead of poking through).
-- Drift feel (CarPhysics, its header explains the model): Grip is the everyday sideways grip, DriftGrip
-- the grip once the handbrake has let the tyres go, DriftSteer how much harder the car steers while it
-- slides. The slide settles near atan(SteerRate x DriftSteer x 0.75 / DriftGrip): about 37 degrees with
-- the defaults at half speed. Lower DriftGrip = wider, lazier slides. DriftPower is the share of the
-- speed lost to sliding that the engine pays back on the throttle (0 = every drift dies in a second,
-- 1 = sliding costs no speed).

local Vehicles = {}

-- Shared physics defaults; any entry can override a field.
Vehicles.Defaults = {
	-- Suspension (raycast springs)
	RestLength = 1.4, -- studs of spring travel
	WheelRadius = 1.2,
	-- SpringHz (natural frequency; higher = stiffer) is worked out from RestLength below so every
	-- car settles at about 45% of its travel, unless an entry sets its own.
	DampingRatio = 0.5,
	-- Driving
	ReverseSpeed = 40,
	Brake = 120, -- studs/s^2
	Coast = 10, -- rolling slow-down with no throttle
	TireFriction = 1.7, -- max grip force = friction x wheel load
	Grip = 14, -- how fast sideways sliding is cancelled (per second); higher = grippier
	DriftGrip = 2.6, -- the same while sliding (handbrake, then throttle + steer); low = wide slides
	DriftSteer = 1.35, -- steering multiplier while sliding (swings the tail out)
	DriftPower = 0.55, -- share of the speed scrubbed off by a slide that the throttle gives back
	YawResponse = 9, -- how fast the car reaches the steering yaw rate
	HighSpeedSteer = 0.5, -- steering multiplier at top speed
	UprightStrength = 14,
	UprightDamp = 4,
	-- Nitro
	NitroAccel = 1.6, -- accel multiplier
	NitroSpeed = 1.2, -- top speed multiplier
	NitroSeconds = 3,
	NitroRecharge = 20,
	-- Size of the greybox body (studs)
	Size = Vector3.new(7.2, 1.8, 15),
}

-- Accel rating 1-5 -> studs/s^2, Handling 1-5 -> steer rate (rad/s) and grip.
local ACCEL = { 40, 50, 60, 72, 85 }
local STEER = { 1.5, 1.7, 1.9, 2.1, 2.3 }
local GRIP = { 10, 12, 14, 16, 18 }

local function car(id, def)
	def.Id = id
	def.DisplayName = def.DisplayName or id
	def.Accel = ACCEL[def.AccelRating]
	def.SteerRate = STEER[def.HandlingRating]
	def.Grip = def.Grip or GRIP[def.HandlingRating]
	return def
end

Vehicles.List = {
	car("Palmetto", { Class = "Compact", Price = 0, Starter = "Civilian", MaxSpeed = 120, AccelRating = 2, HandlingRating = 3, Toughness = 2,
		Color = Color3.fromRGB(110, 242, 196), Size = Vector3.new(6.8, 1.8, 13.5) }),
	car("SunrayPatrol", { DisplayName = "Sunray Patrol", Class = "Police", Price = 0, Starter = "Cop", Police = true, MaxSpeed = 135, AccelRating = 3, HandlingRating = 3, Toughness = 3,
		Color = Color3.fromRGB(245, 245, 250), Size = Vector3.new(7.2, 1.8, 13.5) }),
	car("Gatorback", { Class = "Pickup", Price = 10000, MaxSpeed = 125, AccelRating = 2, HandlingRating = 2, Toughness = 4, OffRoad = true, Seats = 4,
		Color = Color3.fromRGB(86, 120, 72), Size = Vector3.new(7.6, 2.2, 16), RestLength = 1.8,
		SeatDrop = -1.35, SeatTilt = 6, SeatZ = 0.9 }), -- open roll cage: the auto fit put the driver low in the bed
	car("Mangrove", { Class = "SUV", Price = 14000, MaxSpeed = 130, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(40, 70, 90), Size = Vector3.new(7.8, 2.4, 15.5), RestLength = 1.7 }),
	-- OpenTop: no roof (buggy, convertible). CarBuilder's seat fit then never treats the glass as a
	-- closed cabin and keeps the old seat height (the driver's head is meant to be out in the air).
	car("Sandpiper", { Class = "Buggy", Price = 22000, MaxSpeed = 130, AccelRating = 4, HandlingRating = 4, Toughness = 2, OffRoad = true,
		OpenTop = true, Color = Color3.fromRGB(255, 138, 61), Size = Vector3.new(7, 1.4, 12.5), RestLength = 2,
		SeatDrop = -0.35 }), -- sits up in the cage, hair under the top bar
	car("Flamingo", { Class = "Convertible", Price = 28000, MaxSpeed = 150, AccelRating = 3, HandlingRating = 5, Toughness = 2,
		OpenTop = true, Color = Color3.fromRGB(255, 62, 165), Size = Vector3.new(7.2, 1.6, 13),
		SeatDrop = -0.5 }), -- shoulders above the doors, legs inside
	car("NightHeron", { DisplayName = "Night Heron", Class = "Muscle", Price = 38000, MaxSpeed = 165, AccelRating = 3, HandlingRating = 2, Toughness = 3,
		Color = Color3.fromRGB(123, 47, 255), DriftGrip = 1.95 }), -- muscle: the widest slides (about 43 degrees)
	car("Voltline", { Class = "Sports", Price = 45000, MaxSpeed = 160, AccelRating = 5, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(34, 225, 255), Size = Vector3.new(7.2, 1.7, 13) }),
	car("SolanaGT", { DisplayName = "Solana GT", Class = "Super", Price = 95000, MaxSpeed = 190, AccelRating = 4, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(255, 214, 10), Size = Vector3.new(7.4, 1.5, 15.5), RestLength = 1.1,
		SeatTilt = 40 }), -- low wedge roof: the head poked through at the auto 30 deg recline
	car("PursuitSpecial", { DisplayName = "Pursuit Special", Class = "Police", Price = 0, Police = true, UnlockCopRank = 5, MaxSpeed = 175, AccelRating = 4, HandlingRating = 4, Toughness = 4,
		Color = Color3.fromRGB(20, 24, 40), Size = Vector3.new(7.2, 1.7, 13.5) }),
	car("RiotTruck", { DisplayName = "Riot Truck", Class = "Police", Price = 0, Police = true, Pass = "SWATUnit", MaxSpeed = 125, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(30, 34, 44), Size = Vector3.new(8.4, 3.2, 15), RestLength = 1.8,
		SeatDrop = -0.7, SeatZ = -0.6 }), -- up in the cab, head in the middle of the windscreen (the auto fit sat the driver low and 2 studs back, hidden in the box)
	car("Vortex", { Class = "Hyper", Price = 0, Pass = "Hypercar", MaxSpeed = 200, AccelRating = 5, HandlingRating = 4, Toughness = 3,
		Color = Color3.fromRGB(20, 20, 24), Size = Vector3.new(7.6, 1.4, 12.5), RestLength = 1.05, SeatTilt = 40 }), -- low roof: head clipped at 30 deg
	-- Boats (Boat = true): CarPhysics rides the water surface and beaches on land; they spawn on the
	-- marina's boat pads. Low grip = long, splashy slides.
	car("Splash", { DisplayName = "Splash Jet Ski", Class = "Jet Ski", Price = 0, Boat = true, MaxSpeed = 110, AccelRating = 5,
		HandlingRating = 5, Toughness = 1, Grip = 5, DriftGrip = 1.5, Color = Color3.fromRGB(255, 62, 165),
		Size = Vector3.new(4, 1.2, 9), RestLength = 1.2, WheelRadius = 0.5 }),
	car("Marlin", { Class = "Speedboat", Price = 16000, Boat = true, MaxSpeed = 140, AccelRating = 3, HandlingRating = 3,
		Toughness = 3, Grip = 4, DriftGrip = 1.2, Color = Color3.fromRGB(245, 245, 250),
		Size = Vector3.new(8, 1.8, 20), RestLength = 1.4, WheelRadius = 0.6 }),
	car("HarborPatrol", { DisplayName = "Harbor Patrol", Class = "Police Boat", Price = 0, Police = true, Boat = true, MaxSpeed = 140,
		AccelRating = 3, HandlingRating = 3, Toughness = 4, Grip = 4, DriftGrip = 1.2, Color = Color3.fromRGB(245, 245, 250),
		Size = Vector3.new(8.5, 2, 21), RestLength = 1.4, WheelRadius = 0.6,
		SeatY = 3.4, SeatZ = -0.5 }), -- on deck (42% of the 13-stud hull): the old spot sat the crew inside the hull. Estimated, not seen
	-- Premium cars and boats (civilian, cash only). The Solana GT ($95,000) used to be the top car and a
	-- heist pays $900-$16,000, so these take many big heists to afford. Kept at the end of the list so
	-- the Studio test keys (first 12 entries) don't move. The top three (Riptide R, Storm Petrel,
	-- Moonstone Yacht) also need big heists (UnlockHeists), so a cash pack can't skip the crime game;
	-- the Silver Egret and Albatross GT stay cash-only.
	car("SilverEgret", { DisplayName = "Silver Egret", Class = "Luxury", Price = 120000, MaxSpeed = 185, AccelRating = 4,
		HandlingRating = 3, Toughness = 5, Color = Color3.fromRGB(236, 232, 222), Size = Vector3.new(7.8, 1.8, 16),
		RestLength = 1.3 }),
	car("AlbatrossGT", { DisplayName = "Albatross GT", Class = "Grand Tourer", Price = 180000, MaxSpeed = 198, AccelRating = 4,
		HandlingRating = 4, Toughness = 3, Color = Color3.fromRGB(150, 24, 58), Size = Vector3.new(7.8, 1.6, 15.5),
		RestLength = 1.2 }),
	-- Track car: extra grip (above the Handling 5 value) and tidy slides (it also steers the hardest).
	car("Riptide", { DisplayName = "Riptide R", Class = "Track", Price = 260000, UnlockHeists = 3, MaxSpeed = 205, AccelRating = 5,
		HandlingRating = 5, Toughness = 2, Grip = 20, DriftGrip = 3.1, Color = Color3.fromRGB(150, 255, 60),
		Size = Vector3.new(7.8, 1.4, 14.5), RestLength = 1.05, SeatTilt = 40 }), -- low roof: head clipped at the auto 30 deg recline
	-- Electric hypercar: the fastest car you can buy, with a longer, quicker-charging boost.
	car("StormPetrel", { DisplayName = "Storm Petrel", Class = "Electric Hyper", Price = 450000, UnlockHeists = 6, MaxSpeed = 215, AccelRating = 5,
		HandlingRating = 4, Toughness = 3, Color = Color3.fromRGB(40, 110, 255), Size = Vector3.new(8, 1.4, 15),
		RestLength = 1.0, NitroSeconds = 4, NitroRecharge = 14 }),
	car("Swordfish", { Class = "Offshore Racer", Price = 85000, Boat = true, MaxSpeed = 175, AccelRating = 5, HandlingRating = 4,
		Toughness = 3, Grip = 5, DriftGrip = 1.2, Color = Color3.fromRGB(255, 90, 40),
		Size = Vector3.new(8, 1.8, 20), RestLength = 1.4, WheelRadius = 0.6 }),
	car("Moonstone", { DisplayName = "Moonstone Yacht", Class = "Luxury Yacht", Price = 300000, UnlockHeists = 4, Boat = true, MaxSpeed = 160,
		AccelRating = 3, HandlingRating = 2, Toughness = 5, Grip = 3, DriftGrip = 1.2, Color = Color3.fromRGB(230, 236, 255),
		Size = Vector3.new(10, 2.4, 26), RestLength = 1.4, WheelRadius = 0.6,
		SeatY = 4.5, SeatZ = 7 }), -- on the aft deck (42% of the 16-stud hull): the old spot sat the owner inside the hull. Estimated, not seen
	-- Street cars (Hidden = true): the city's everyday traffic cars, only ever driven after a carjacking
	-- (CarjackService). Never sold or owned, so dealerships, the phone, garages, homes and the Studio test
	-- keys all skip Hidden entries. TrafficModel: the ReplicatedStorage.TrafficModels body CarBuilder puts
	-- on it, at the body's own size (the chassis is fitted to it; Size is only the no-body fallback).
	-- Seat heights come from the body's roof (CarBuilder.fitSeats). Traffic bodies have no CarBodies template,
	-- so their hand-tuned SeatZ / SeatDrop / SeatTilt (see the top of the file) live here only.
	car("StreetHatch", { DisplayName = "Hatchback", Class = "Compact", Price = 0, Hidden = true, TrafficModel = "Hatchback",
		MaxSpeed = 118, AccelRating = 2, HandlingRating = 3, Toughness = 2, Color = Color3.fromRGB(220, 220, 224),
		Size = Vector3.new(6.6, 1.8, 13) }),
	car("StreetSedan", { DisplayName = "Sedan", Class = "Sedan", Price = 0, Hidden = true, TrafficModel = "Sedan",
		MaxSpeed = 124, AccelRating = 2, HandlingRating = 2, Toughness = 3, Color = Color3.fromRGB(34, 70, 140),
		Size = Vector3.new(7, 1.8, 14), SeatZ = -1.3 }), -- front seat (0.4 put the driver in the back)
	car("StreetPickup", { DisplayName = "Pickup", Class = "Pickup", Price = 0, Hidden = true, TrafficModel = "Pickup",
		MaxSpeed = 112, AccelRating = 2, HandlingRating = 2, Toughness = 4, OffRoad = true, Color = Color3.fromRGB(150, 24, 40),
		Size = Vector3.new(7.4, 2, 15.5), RestLength = 1.6, SeatZ = -3.0 }), -- head behind the cab window
	-- The Big Score's armored van (Hidden = true): BigScoreService builds the one van a crew hacks; nobody
	-- owns it. Riot Truck build with a lower top speed: heavy, tough and slow. No TrafficModel: its mesh
	-- body is a ServerStorage.CarBodies template named "ArmoredVan" (the greybox until there is one).
	car("ArmoredVan", { DisplayName = "Armored Van", Class = "Armored", Price = 0, Hidden = true, MaxSpeed = 112,
		AccelRating = 2, HandlingRating = 2, Toughness = 5, Color = Color3.fromRGB(196, 190, 172),
		Size = Vector3.new(8.4, 3.2, 15), RestLength = 1.8,
		SeatDrop = -0.7, SeatZ = -0.6 }), -- the Riot Truck's body: the same cab seats
}

Vehicles.ById = {}
Vehicles.TopSpeed = 0 -- the fastest MaxSpeed in the list (e.g. to scale the dealer's speed bars)
for _, v in ipairs(Vehicles.List) do
	setmetatable(v, { __index = Vehicles.Defaults })
	Vehicles.ById[v.Id] = v
	Vehicles.TopSpeed = math.max(Vehicles.TopSpeed, v.MaxSpeed or 0)
end

-- Plain table of every tuning field for a vehicle (defaults filled in), for copying onto model attributes.
function Vehicles.Resolve(id)
	local v = Vehicles.ById[id]
	if not v then
		return nil
	end
	local out = {}
	for k, val in pairs(Vehicles.Defaults) do
		out[k] = val
	end
	for k, val in pairs(v) do
		out[k] = val
	end
	if not out.SpringHz then
		-- Resting compression x = g / (2*pi*f)^2; solve for f with x = 45% of the travel.
		out.SpringHz = math.sqrt(workspace.Gravity / (0.45 * out.RestLength)) / (2 * math.pi)
	end
	return out
end

return Vehicles
