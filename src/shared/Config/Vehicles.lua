-- Vehicles (ModuleScript, ReplicatedStorage.Shared.Config.Vehicles)
-- One entry per vehicle. Accelerations are in studs/s^2 so tuning doesn't depend on part mass.
-- Stats come from the Game Design Spec; they are starting values for playtest tuning.
-- Brake / ReverseSpeed differ by class (heavy trucks stop later, sports cars sooner). Palmetto,
-- Vortex and the Sunray Patrol (also the AI police car) keep the defaults they were tested with.

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
		Color = Color3.fromRGB(110, 242, 196), Size = Vector3.new(6.8, 1.8, 13.5) }),
	car("SunrayPatrol", { DisplayName = "Sunray Patrol", Class = "Police", Price = 0, Starter = "Cop", Police = true, MaxSpeed = 135, AccelRating = 3, HandlingRating = 3, Toughness = 3,
		Color = Color3.fromRGB(245, 245, 250), Size = Vector3.new(7.2, 1.8, 13.5) }),
	car("Gatorback", { Class = "Pickup", Price = 10000, MaxSpeed = 125, Brake = 105, ReverseSpeed = 35, AccelRating = 2, HandlingRating = 2, Toughness = 4, OffRoad = true, Seats = 4,
		Color = Color3.fromRGB(86, 120, 72), Size = Vector3.new(7.6, 2.2, 16), RestLength = 1.8 }),
	car("Mangrove", { Class = "SUV", Price = 14000, MaxSpeed = 130, Brake = 108, ReverseSpeed = 36, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(40, 70, 90), Size = Vector3.new(7.8, 2.4, 15.5), RestLength = 1.7 }),
	car("Sandpiper", { Class = "Buggy", Price = 22000, MaxSpeed = 130, Brake = 125, ReverseSpeed = 45, AccelRating = 4, HandlingRating = 4, Toughness = 2, OffRoad = true,
		Color = Color3.fromRGB(255, 138, 61), Size = Vector3.new(7, 1.4, 12.5), RestLength = 2 }),
	car("Flamingo", { Class = "Convertible", Price = 28000, MaxSpeed = 150, Brake = 128, ReverseSpeed = 42, AccelRating = 3, HandlingRating = 5, Toughness = 2,
		Color = Color3.fromRGB(255, 62, 165), Size = Vector3.new(7.2, 1.6, 13) }),
	car("NightHeron", { DisplayName = "Night Heron", Class = "Muscle", Price = 38000, MaxSpeed = 165, Brake = 112, ReverseSpeed = 40, AccelRating = 3, HandlingRating = 2, Toughness = 3,
		Color = Color3.fromRGB(123, 47, 255), DriftGrip = 1.4 }),
	car("Voltline", { Class = "Sports", Price = 45000, MaxSpeed = 160, Brake = 135, ReverseSpeed = 45, AccelRating = 5, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(34, 225, 255), Size = Vector3.new(7.2, 1.7, 13) }),
	car("SolanaGT", { DisplayName = "Solana GT", Class = "Super", Price = 95000, MaxSpeed = 190, Brake = 145, ReverseSpeed = 48, AccelRating = 4, HandlingRating = 4, Toughness = 2,
		Color = Color3.fromRGB(255, 214, 10), Size = Vector3.new(7.4, 1.5, 15.5), RestLength = 1.1 }),
	car("PursuitSpecial", { DisplayName = "Pursuit Special", Class = "Police", Price = 0, Police = true, UnlockCopRank = 5, MaxSpeed = 175, Brake = 138, ReverseSpeed = 45, AccelRating = 4, HandlingRating = 4, Toughness = 4,
		Color = Color3.fromRGB(20, 24, 40), Size = Vector3.new(7.2, 1.7, 13.5) }),
	car("RiotTruck", { DisplayName = "Riot Truck", Class = "Police", Price = 0, Police = true, Pass = "SWATUnit", MaxSpeed = 125, Brake = 100, ReverseSpeed = 32, AccelRating = 2, HandlingRating = 2, Toughness = 5,
		Color = Color3.fromRGB(30, 34, 44), Size = Vector3.new(8.4, 3.2, 15), RestLength = 1.8 }),
	car("Vortex", { Class = "Hyper", Price = 0, Pass = "Hypercar", MaxSpeed = 200, AccelRating = 5, HandlingRating = 4, Toughness = 3,
		Color = Color3.fromRGB(20, 20, 24), Size = Vector3.new(7.6, 1.4, 12.5), RestLength = 1.05 }),
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
		Size = Vector3.new(8.5, 2, 21), RestLength = 1.4, WheelRadius = 0.6 }),
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
