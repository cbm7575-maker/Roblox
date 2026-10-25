-- Vehicles (ModuleScript, ReplicatedStorage.Shared.Config.Vehicles)
-- One entry per vehicle. Accelerations are in studs/s^2 so tuning doesn't depend on part mass.
-- Stats come from the Game Design Spec; they are starting values for playtest tuning.
-- Brake / ReverseSpeed differ by class (heavy trucks stop later, sports cars sooner). Palmetto,
-- Vortex and the Sunray Patrol (also the AI police car) keep the defaults they were tested with.
--
-- Cabin layout (CarBuilder places the seats from it; all studs, relative to the chassis centre, +Z = rear):
--   Seats = 2 (driver + front passenger) or 4 (two more on a back row; up to 3 passengers).
--   Cabin = { Y = seat top surface height, Z = front-row seat centre, X = how far the seats sit from the
--             centre line (driver left, passenger right; 0 = one behind the other, then Inline = how far
--             back the passenger sits), Tilt = recline in degrees (low cars lean the rider back),
--             Rear = { Y, Z, X, Tilt } for the back row }.
--   Worked out from each mesh body's real bounds (ServerStorage.CarBodies) for a seated R15 avatar at 1.05
--   height scale (head top ~4.1 studs over the seat): the head stays under the roof / window line, the
--   hips on the floor, the feet inside the body. Open cars (Flamingo, Sandpiper, Splash) just sit naturally.
--   BodyScale = visual mesh body scale (default 1) for cabins too low even with the seat down and leaned
--   back; the wheels and arches scale with it (physics never change).
--   Hull (boats) = { Turn = degrees, Size = Vector3 }: turns the stored hull about its pivot and refits it to
--   Size (Splash and Harbor Patrol were stored sideways: their long axis ran across the boat).

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
	DriftGrip = 2, -- the same while handbraking; low = long slides
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
		Color = Color3.fromRGB(110, 242, 196), Size = Vector3.new(6.8, 1.8, 13.5), Seats = 4,
		BodyScale = 1.02, Cabin = { Y = -0.76, Z = -0.3, X = 1.3, Tilt = 14, Rear = { Y = -0.76, Z = 1.95, X = 1.3, Tilt = 14 } } }),
	car("SunrayPatrol", { DisplayName = "Sunray Patrol", Class = "Police", Price = 0, Starter = "Cop", Police = true, MaxSpeed = 135, AccelRating = 3, HandlingRating = 3, Toughness = 3,
		Color = Color3.fromRGB(245, 245, 250), Size = Vector3.new(7.2, 1.8, 13.5), Seats = 4,
		BodyScale = 1.02, Cabin = { Y = -1.22, Z = -0.15, X = 1.5, Tilt = 14, Rear = { Y = -1.22, Z = 1.9, X = 1.5, Tilt = 14 } } }),
	car("Gatorback", { Class = "Pickup", Price = 10000, MaxSpeed = 125, Brake = 105, ReverseSpeed = 35, AccelRating = 2, HandlingRating = 2, Toughness = 4, OffRoad = true, Seats = 4,
		Color = Color3.fromRGB(86, 120, 72), Size = Vector3.new(7.6, 2.2, 16), RestLength = 1.8,
		Cabin = { Y = -0.45, Z = -0.65, X = 1.7, Tilt = 0, Rear = { Y = -0.45, Z = 1.5, X = 1.7, Tilt = 0 } } }),
	car("Mangrove", { Class = "SUV", Price = 14000, MaxSpeed = 130, Brake = 108, ReverseSpeed = 36, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(40, 70, 90), Size = Vector3.new(7.8, 2.4, 15.5), RestLength = 1.7, Seats = 4,
		Cabin = { Y = -0.6, Z = -0.6, X = 1.8, Tilt = 0, Rear = { Y = -0.6, Z = 1.75, X = 1.8, Tilt = 0 } } }),
	car("Sandpiper", { Class = "Buggy", Price = 22000, MaxSpeed = 130, Brake = 125, ReverseSpeed = 45, AccelRating = 4, HandlingRating = 4, Toughness = 2, OffRoad = true,
		Color = Color3.fromRGB(255, 138, 61), Size = Vector3.new(7, 1.4, 12.5), RestLength = 2,
		Cabin = { Y = -1.05, Z = 0.9, X = 1.4, Tilt = 5 } }),
	car("Flamingo", { Class = "Convertible", Price = 28000, MaxSpeed = 150, Brake = 128, ReverseSpeed = 42, AccelRating = 3, HandlingRating = 5, Toughness = 2,
		Color = Color3.fromRGB(255, 62, 165), Size = Vector3.new(7.2, 1.6, 13),
		Cabin = { Y = -1.2, Z = 1.3, X = 1.5, Tilt = 8 } }),
	car("NightHeron", { DisplayName = "Night Heron", Class = "Muscle", Price = 38000, MaxSpeed = 165, Brake = 112, ReverseSpeed = 40, AccelRating = 3, HandlingRating = 2, Toughness = 3,
		Color = Color3.fromRGB(123, 47, 255), DriftGrip = 1.4,
		Cabin = { Y = -1.23, Z = 0.1, X = 1.5, Tilt = 22 } }),
	car("Voltline", { Class = "Sports", Price = 45000, MaxSpeed = 160, Brake = 135, ReverseSpeed = 45, AccelRating = 5, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(34, 225, 255), Size = Vector3.new(7.2, 1.7, 13),
		Cabin = { Y = -0.8, Z = 1.25, X = 1.5, Tilt = 4 } }),
	car("SolanaGT", { DisplayName = "Solana GT", Class = "Super", Price = 95000, MaxSpeed = 190, Brake = 145, ReverseSpeed = 48, AccelRating = 4, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(255, 214, 10), Size = Vector3.new(7.4, 1.5, 15.5), RestLength = 1.1,
		BodyScale = 1.08, Cabin = { Y = -1.26, Z = -0.55, X = 1.6, Tilt = 30 } }),
	car("PursuitSpecial", { DisplayName = "Pursuit Special", Class = "Police", Price = 0, Police = true, UnlockCopRank = 5, MaxSpeed = 175, Brake = 138, ReverseSpeed = 45, AccelRating = 4, HandlingRating = 4, Toughness = 4,
		Color = Color3.fromRGB(20, 24, 40), Size = Vector3.new(7.2, 1.7, 13.5),
		BodyScale = 1.08, Cabin = { Y = -1.27, Z = -0.8, X = 1.5, Tilt = 22 } }),
	car("RiotTruck", { DisplayName = "Riot Truck", Class = "Police", Price = 0, Police = true, Pass = "SWATUnit", MaxSpeed = 125, Brake = 100, ReverseSpeed = 32, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(30, 34, 44), Size = Vector3.new(8.4, 3.2, 15), RestLength = 1.8, Seats = 4,
		Cabin = { Y = 0.45, Z = -0.85, X = 2.1, Tilt = 0, Rear = { Y = 0.2, Z = 1.6, X = 2.1, Tilt = 0 } } }),
	car("Vortex", { Class = "Hyper", Price = 0, Pass = "Hypercar", MaxSpeed = 200, AccelRating = 5, HandlingRating = 4, Toughness = 3,
		Color = Color3.fromRGB(20, 20, 24), Size = Vector3.new(7.6, 1.4, 12.5), RestLength = 1.05,
		BodyScale = 1.12, Cabin = { Y = -1.38, Z = -0.85, X = 1.7, Tilt = 30 } }),
	-- Boats (Boat = true): CarPhysics rides the water surface and beaches on land; they spawn on the
	-- marina's boat pads. Low grip = long, splashy slides.
	car("Splash", { DisplayName = "Splash Jet Ski", Class = "Jet Ski", Price = 0, Boat = true, MaxSpeed = 110, AccelRating = 5,
		HandlingRating = 5, Toughness = 1, Grip = 5, DriftGrip = 1.5, Color = Color3.fromRGB(255, 62, 165),
		Size = Vector3.new(4, 1.2, 9), RestLength = 1.2, WheelRadius = 0.5,
		Hull = { Turn = 90, Size = Vector3.new(5, 5.4, 10) }, Cabin = { Y = 1.45, Z = 0.3, X = 0, Inline = 2.3, Tilt = 0 } }),
	car("Marlin", { Class = "Speedboat", Price = 16000, Boat = true, MaxSpeed = 140, AccelRating = 3, HandlingRating = 3,
		Toughness = 3, Grip = 4, DriftGrip = 1.2, Color = Color3.fromRGB(245, 245, 250),
		Size = Vector3.new(8, 1.8, 20), RestLength = 1.4, WheelRadius = 0.6,
		Cabin = { Y = 1.3, Z = 0.5, X = 1.5, Tilt = 0 } }),
	car("HarborPatrol", { DisplayName = "Harbor Patrol", Class = "Police Boat", Price = 0, Police = true, Boat = true, MaxSpeed = 140,
		AccelRating = 3, HandlingRating = 3, Toughness = 4, Grip = 4, DriftGrip = 1.2, Color = Color3.fromRGB(245, 245, 250),
		Size = Vector3.new(8.5, 2, 21), RestLength = 1.4, WheelRadius = 0.6,
		Hull = { Turn = -90, Size = Vector3.new(9.5, 10.2, 22) }, Cabin = { Y = 1.9, Z = -1.5, X = 1.6, Tilt = 0 } }),
}

Vehicles.ById = {}
for _, v in ipairs(Vehicles.List) do
	setmetatable(v, { __index = Vehicles.Defaults })
	Vehicles.ById[v.Id] = v
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
