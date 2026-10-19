-- CarPhysics (ModuleScript, ReplicatedStorage.Shared.Util.CarPhysics)
-- The arcade raycast car, shared by the player's DriveController (client, owns their car) and the
-- AI police (server, owns AI cars). Same feel for everyone.
--   * Four rays hold the body up on springs (forces at each wheel, along the ground normal).
--   * Drive, brake and sideways grip push at the centre of mass.
--   * Steering is a yaw-rate target reached with a torque; a second torque keeps the car upright.
-- Tuning comes from the car's attributes (Config.Vehicles, copied by CarBuilder).
-- Damage (VehicleDamageService sets car attribute Health 0-100, read live every step):
--   * Health < 35: acceleration and top speed x0.7.
--   * Health 0: the engine stalls until StallUntil (server time; brakes and steering still work),
--     then limp mode until repaired: 30 studs/s top speed, no nitro.
-- Nitro fuel is kept per car (getting out and back in doesn't refill it; it recharges meanwhile).
--
--   local phys = CarPhysics.New(car, { extra instances the rays should ignore })
--   CarPhysics.Step(phys, dt, { Throttle = -1..1, Steer = -1..1, Handbrake = bool, Nitro = bool })
--   phys.FwdSpeed, phys.NitroOn, phys.NitroFuel (0..1), phys.Flat, phys.Hits, phys.Grounded,
--   phys.Health, phys.Stalled, phys.Limp
--   CarPhysics.Zero(phys) when nobody drives it any more.
-- Crash maths (pure functions, shared by DriveController's crash feedback and VehicleDamageService):
--   CarPhysics.ImpactExcess, JoltExcess, BoxContact, PairImpact, CrashDamage.

local Workspace = game:GetService("Workspace")

local CarPhysics = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
CarPhysics.Wheels = WHEELS

CarPhysics.SMOKE_HEALTH = 35 -- below this: smoke, x0.7 acceleration and top speed
CarPhysics.LIMP_SPEED = 30 -- studs/s top speed at Health 0
local DAMAGED_SCALE = 0.7

-- Nitro left in each car when it was last driven (weak keys: forgotten when the car goes).
local fuelLeft = setmetatable({}, { __mode = "k" }) -- [car] = seconds of boost
local fuelAt = setmetatable({}, { __mode = "k" }) -- [car] = os.clock() of that

local function sign(x)
	return x > 0 and 1 or (x < 0 and -1 or 0)
end

function CarPhysics.New(car, ignore)
	local chassis = car.PrimaryPart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { car }
	for _, x in ipairs(ignore or {}) do
		table.insert(list, x)
	end
	-- Smoke clouds block sight lines, not tyres.
	local smoke = Workspace:FindFirstChild("Smoke")
	if smoke then
		table.insert(list, smoke)
	end
	params.FilterDescendantsInstances = list
	-- Cars' rays pass through water (they sink); boats' rays stop on the water surface and ride it.
	local boat = car:GetAttribute("Boat") == true
	params.IgnoreWater = not boat
	local cfg = car:GetAttributes()
	-- Fuel carries over from the last drive, plus whatever recharged since.
	local tank = cfg.NitroSeconds or 3
	local fuel = tank
	if fuelLeft[car] then
		local away = os.clock() - (fuelAt[car] or 0)
		fuel = math.clamp(fuelLeft[car] + away * tank / (cfg.NitroRecharge or 20), 0, tank)
	end
	local phys = {
		Car = car,
		Chassis = chassis,
		Cfg = cfg,
		Params = params,
		Size = chassis.Size,
		Atts = {},
		Forces = {},
		Hits = {},
		DriveForce = chassis:FindFirstChild("DriveForce"),
		BodyTorque = chassis:FindFirstChild("BodyTorque"),
		Fuel = fuel, -- seconds of boost left
		NitroFuel = fuel / tank,
		NitroOn = false,
		FwdSpeed = 0,
		Steer = 0,
		Flat = false,
		Grounded = 0,
		Boat = boat,
		Beached = false,
		Health = 100,
		Stalled = false,
		Limp = false,
	}
	for _, name in ipairs(WHEELS) do
		phys.Atts[name] = chassis:FindFirstChild("Wheel" .. name)
		phys.Forces[name] = chassis:FindFirstChild("Force" .. name)
	end
	return phys
end

function CarPhysics.Step(phys, dt, input)
	local chassis = phys.Chassis
	local cfg = phys.Cfg
	dt = math.max(dt, 1 / 240)
	local mass = chassis.AssemblyMass
	local quarter = mass / 4
	local omega = 2 * math.pi * cfg.SpringHz
	local k = quarter * omega * omega
	local c = 2 * cfg.DampingRatio * math.sqrt(k * quarter)
	local rayLen = cfg.RestLength + cfg.WheelRadius

	local cf = chassis.CFrame
	local up, look = cf.UpVector, cf.LookVector
	local vel = chassis.AssemblyLinearVelocity
	local angVel = chassis.AssemblyAngularVelocity
	local fwdSpeed = vel:Dot(look)
	local throttle = math.clamp(input.Throttle or 0, -1, 1)
	local steer = math.clamp(input.Steer or 0, -1, 1)
	local handbrake = input.Handbrake == true

	-- Damage (read live: the MaxSpeed attribute stays as built).
	local car = phys.Car
	local health = car:GetAttribute("Health") or 100
	local wrecked = health <= 0
	local stalled = wrecked and (car:GetAttribute("StallUntil") or 0) > Workspace:GetServerTimeNow()
	if stalled and not ((throttle < 0 and fwdSpeed > 2) or (throttle > 0 and fwdSpeed < -2)) then
		throttle = 0 -- engine off: the brakes still work, the gas and reverse don't
	end

	-- Nitro fuel is in seconds of boost.
	local nitroOn = input.Nitro == true and phys.Fuel > 0 and throttle > 0.1 and not wrecked
	if nitroOn then
		phys.Fuel = math.max(0, phys.Fuel - dt)
	else
		phys.Fuel = math.min(cfg.NitroSeconds, phys.Fuel + dt * cfg.NitroSeconds / cfg.NitroRecharge)
	end
	fuelLeft[car] = phys.Fuel
	fuelAt[car] = os.clock()
	local maxSpeed = cfg.MaxSpeed * (nitroOn and cfg.NitroSpeed or 1) * (input.SpeedScale or 1)
	local accel = cfg.Accel * (nitroOn and cfg.NitroAccel or 1)
	if health < CarPhysics.SMOKE_HEALTH then
		maxSpeed *= DAMAGED_SCALE
		accel *= DAMAGED_SCALE
	end
	if wrecked then
		maxSpeed = math.min(maxSpeed, CarPhysics.LIMP_SPEED)
	end
	-- Spike strips: flat tyres until FlatUntil (server time) -> slow, weak and slidey.
	local flat = not phys.Boat and (phys.Car:GetAttribute("FlatUntil") or 0) > Workspace:GetServerTimeNow()
	if flat then
		maxSpeed *= 0.4
		accel *= 0.6
	end

	-- Springs
	local grounded = 0
	local normalSum = Vector3.zero
	local loadSum = 0
	-- Boats cast from a little higher: a parked boat floats low enough that its ray origins sit under
	-- the surface, and a ray that starts inside water never hits the water.
	local lift = phys.Boat and 3 or 0
	for _, name in ipairs(WHEELS) do
		local origin = phys.Atts[name].WorldPosition + up * lift
		local hit = Workspace:Raycast(origin, -up * (rayLen + lift), phys.Params)
		phys.Hits[name] = hit
		local force = Vector3.zero
		if hit then
			grounded += 1
			normalSum += hit.Normal
			local compression = rayLen - (hit.Distance - lift)
			local springSpeed = chassis:GetVelocityAtPosition(origin):Dot(up)
			local load = math.max(0, k * compression - c * springSpeed)
			loadSum += load
			-- Push along the ground normal: pushing along a slightly leaning body would nudge it sideways.
			force = hit.Normal * load
		end
		phys.Forces[name].Force = force
	end
	local gf = grounded / 4

	-- Boats: only water pushes. Run aground and the engine is useless; the hull scrapes to a stop.
	if phys.Boat then
		local wet = 0
		for _, name in ipairs(WHEELS) do
			local h = phys.Hits[name]
			if h and h.Material == Enum.Material.Water then
				wet += 1
			end
		end
		phys.Beached = grounded > 0 and wet < grounded / 2
		if phys.Beached then
			-- Aground: the boat can only crawl (walking pace, either way, and it can still turn),
			-- enough to wriggle back into the water but useless as a land vehicle.
			throttle *= 0.3
			maxSpeed = math.min(maxSpeed, 10)
			handbrake = false
			nitroOn = false
		end
	end

	-- Drive, brake, grip (at the centre of mass)
	local drive = Vector3.zero
	local gravity = Vector3.new(0, -Workspace.Gravity, 0)
	if grounded > 0 then
		local n = normalSum.Unit
		local fwd = look - n * look:Dot(n)
		fwd = fwd.Magnitude > 1e-3 and fwd.Unit or look
		local side = fwd:Cross(n)

		local long
		if throttle > 0.05 then
			if fwdSpeed < -2 then
				long = cfg.Brake * throttle
			else
				local frac = math.clamp(fwdSpeed / maxSpeed, 0, 1)
				long = accel * throttle * (1 - frac * frac)
			end
		elseif throttle < -0.05 then
			if fwdSpeed > 2 then
				long = -cfg.Brake * -throttle
			else
				local reverseMax = wrecked and math.min(cfg.ReverseSpeed, CarPhysics.LIMP_SPEED) or cfg.ReverseSpeed
				local frac = math.clamp(-fwdSpeed / reverseMax, 0, 1)
				long = -accel * 0.6 * -throttle * (1 - frac * frac)
			end
		elseif math.abs(fwdSpeed) > 1 then
			-- A stalled engine drags the car to a stop (so the cops can reach it).
			long = -sign(fwdSpeed) * (stalled and cfg.Brake * 0.5 or cfg.Coast)
		else
			-- Hold still, including on slopes (cancel gravity along the car's nose).
			long = math.clamp(-fwdSpeed / dt * 0.5 - gravity:Dot(fwd), -cfg.Brake, cfg.Brake)
		end
		if handbrake and math.abs(fwdSpeed) > 1 then
			long -= sign(fwdSpeed) * cfg.Brake * 0.15
		end
		if fwdSpeed > maxSpeed * 1.02 then
			-- Never harder than the brakes (VehicleDamageService counts anything harder as a crash).
			long = math.min(long, -math.min((fwdSpeed - maxSpeed) * 2, cfg.Brake))
		end

		-- Cancel a share of the sideways slide each step; the share depends on the grip rate (per second).
		local grip = handbrake and cfg.DriftGrip or cfg.Grip
		if flat then
			grip *= 0.45
		end
		-- Rain storms (WorldService): wet roads grip a bit less.
		if Workspace:GetAttribute("Raining") then
			grip *= 0.75
		end
		local latSpeed = vel:Dot(side)
		local lat = -latSpeed * (1 - math.exp(-grip * dt)) * mass / dt
		-- Tyres also hold against gravity sideways (slopes, or the lean from the driver's weight).
		lat -= gravity:Dot(side) * mass
		local maxLat = cfg.TireFriction * loadSum
		lat = math.clamp(lat, -maxLat, maxLat)

		-- A little downforce at speed keeps the car planted over bumps.
		local speedFrac = math.clamp(math.abs(fwdSpeed) / cfg.MaxSpeed, 0, 1.3)
		local downforce = phys.Boat and 0 or mass * 30 * speedFrac * speedFrac * gf
		if phys.Beached and throttle == 0 then
			long = -sign(fwdSpeed) * math.min(math.abs(fwdSpeed) / dt, cfg.Brake * 0.6)
		end
		drive = fwd * (long * mass * gf) + side * lat - n * downforce
	end
	phys.DriveForce.Force = drive

	-- Steering (yaw rate) and keeping upright
	local W, H, L = phys.Size.X, phys.Size.Y, phys.Size.Z
	local yawInertia = mass * (L * L + W * W) / 12
	local tiltInertia = mass * (W * W + H * H + L * L * 0.5) / 12
	local torque = Vector3.zero
	if grounded > 0 then
		local speedAbs = math.abs(fwdSpeed)
		local low = math.clamp(speedAbs / 15, 0, 1)
		local high = 1 - (1 - cfg.HighSpeedSteer) * math.clamp(speedAbs / cfg.MaxSpeed, 0, 1)
		local dir = fwdSpeed >= -1 and 1 or -1
		local target = -steer * cfg.SteerRate * low * high * dir * (handbrake and 1.35 or 1)
		local current = angVel:Dot(up)
		torque += up * ((target - current) * cfg.YawResponse * yawInertia * gf)
	end
	local tiltAxis = up:Cross(Vector3.yAxis)
	local spinNoYaw = angVel - up * angVel:Dot(up)
	local uprightScale = grounded > 0 and 0.35 or 1
	torque += (tiltAxis * cfg.UprightStrength - spinNoYaw * cfg.UprightDamp) * tiltInertia * uprightScale
	phys.BodyTorque.Torque = torque

	phys.FwdSpeed = fwdSpeed
	phys.NitroOn = nitroOn
	phys.NitroFuel = phys.Fuel / cfg.NitroSeconds
	phys.Steer = steer
	phys.Flat = flat
	phys.Grounded = grounded
	phys.Health = health
	phys.Stalled = stalled
	phys.Limp = wrecked and not stalled
end

function CarPhysics.Zero(phys)
	for _, f in pairs(phys.Forces) do
		if f.Parent then
			f.Force = Vector3.zero
		end
	end
	if phys.DriveForce and phys.DriveForce.Parent then
		phys.DriveForce.Force = Vector3.zero
	end
	if phys.BodyTorque and phys.BodyTorque.Parent then
		phys.BodyTorque.Torque = Vector3.zero
	end
end

------------------------------------------------------------------ crash maths (pure, no Roblox APIs)

-- The most sideways acceleration tyres can give (studs/s^2 per unit of TireFriction): gravity plus
-- downforce, with room for the load spikes of bumps and landings.
local GRIP_ACCEL = 360

-- Speed lost over one sample beyond what the car itself explains (studs/s, 0 = no crash).
--   h0, h1: horizontal speed before/after. s0, s1: full 3D speed before/after. Both must drop: a ramp
--   turns horizontal speed into climb and a landing only loses vertical speed, neither is a crash.
--   slide: sideways speed before (tyres may scrub that off). brake, tireFriction: the car's tuning.
--   flat: flat tyres. minLoss: slack per sample for noise.
function CarPhysics.ImpactExcess(h0, h1, s0, s1, slide, dt, brake, tireFriction, flat, minLoss)
	local loss = math.min(h0 - h1, s0 - s1)
	if loss <= 0 then
		return 0
	end
	-- Brakes (+15% handbrake, + slack); flat tyres drag the car down to 40% of its top speed.
	local brakeCap = (brake * (flat and 1.6 or 1.3) + 15) * dt
	local scrub = math.min(math.abs(slide), tireFriction * GRIP_ACCEL * dt)
	return math.max(0, loss - brakeCap - scrub - (minLoss or 0))
end

-- Horizontal velocity change over one sample that the car's own engine, brakes and tyres can't
-- explain (studs/s, any direction: a shove from behind or the side counts too).
--   dvx, dvz: velocity change. fx, fz: horizontal heading (unit). accelMax: strongest forward push.
function CarPhysics.JoltExcess(dvx, dvz, fx, fz, dt, brake, accelMax, tireFriction, minJolt)
	local along = dvx * fx + dvz * fz
	local across = dvx * -fz + dvz * fx
	local capAlong = (math.max(brake * 1.3, accelMax) + 15) * dt
	local capAcross = tireFriction * GRIP_ACCEL * dt
	local ea = math.max(0, math.abs(along) - capAlong)
	local ec = math.max(0, math.abs(across) - capAcross)
	return math.max(0, math.sqrt(ea * ea + ec * ec) - (minJolt or 0))
end

-- Overlap of two boxes projected on axis (ux, uz); negative = a gap on that axis.
local function overlapOn(ux, uz, dx, dz, alx, alz, aw, al, blx, blz, bw, bl)
	local ra = aw * math.abs(-alz * ux + alx * uz) + al * math.abs(alx * ux + alz * uz)
	local rb = bw * math.abs(-blz * ux + blx * uz) + bl * math.abs(blx * ux + blz * uz)
	local dist = dx * ux + dz * uz
	return ra + rb - math.abs(dist), dist
end

-- Do two cars' footprints (rectangles seen from above) overlap? Returns the overlap depth and the
-- contact axis (unit, pointing from a to b) along the shallowest overlap, or nil when apart.
--   dx, dz: b's centre minus a's. alx, alz: a's heading (unit). aw, al: a's half width and length.
function CarPhysics.BoxContact(dx, dz, alx, alz, aw, al, blx, blz, bw, bl)
	local best, nx, nz = math.huge, 0, 0
	for i = 1, 4 do
		local ux, uz
		if i == 1 then
			ux, uz = alx, alz
		elseif i == 2 then
			ux, uz = -alz, alx
		elseif i == 3 then
			ux, uz = blx, blz
		else
			ux, uz = -blz, blx
		end
		local o, dist = overlapOn(ux, uz, dx, dz, alx, alz, aw, al, blx, blz, bw, bl)
		if o < 0 then
			return nil
		end
		if o < best then
			local sgn = dist >= 0 and 1 or -1
			best, nx, nz = o, ux * sgn, uz * sgn
		end
	end
	return best, nx, nz
end

-- How hard two touching cars hit (studs/s, 0 = no hit): their closing speed along the contact axis,
-- but only if at least one of them was really jolted (evidence > 0: cars passing close by aren't a
-- crash), and never more than about twice the bigger velocity change either of them showed.
function CarPhysics.PairImpact(closing, evidence, dvMax, minClosing)
	if closing < minClosing or evidence <= 0 then
		return 0
	end
	return math.min(closing, dvMax * 2.2 + 10)
end

-- Health lost in a crash: impact (studs/s) past the dead zone, x rate, x the other side's mass over
-- ours (0.4..2.5; 1 for walls), x 2 / Toughness (Toughness 2 = x1), at most maxHit.
function CarPhysics.CrashDamage(impact, deadzone, massRatio, toughness, rate, maxHit)
	local over = impact - deadzone
	if over <= 0 then
		return 0
	end
	local ratio = math.clamp(massRatio, 0.4, 2.5)
	return math.min(maxHit, over * rate * ratio * 2 / math.max(toughness or 2, 0.5))
end

return CarPhysics
