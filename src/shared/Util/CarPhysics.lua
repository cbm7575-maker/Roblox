-- CarPhysics (ModuleScript, ReplicatedStorage.Shared.Util.CarPhysics)
-- The arcade raycast car, shared by the player's DriveController (client, owns their car) and the
-- AI police (server, owns AI cars). Same feel for everyone.
--   * Four rays hold the body up on springs (forces at each wheel, along the ground normal).
--   * Drive, brake and sideways grip push at the centre of mass.
--   * Steering is a yaw-rate target reached with a torque; a second torque keeps the car upright.
--   * Weight transfer you can see (cars, not boats): a real tyre pushes at the road, below the centre of
--     mass, so the same grip and drive forces also lean the body. It rolls out of a corner, dips its
--     nose under braking and squats pulling away, a couple of degrees on the springs (LEAN_ARM; 0 turns
--     it off). It only tilts the body: grip, steering and speed are the same with or without it.
-- Tuning comes from the car's attributes (Config.Vehicles, copied by CarBuilder). phys.Cfg follows the
-- attributes live: when the server changes one (a tune-up while you sit in the car), the next step
-- already uses it. Numbers can't vanish, turn into something else or (for the ones we divide by) drop
-- to zero: such a change is ignored.
--
-- Drifting (cars only; boats just get the low handbrake grip, as before):
--   * Handbrake = the tyres let go: sideways grip falls from Grip to DriftGrip and the car steers
--     DriftSteer times harder, so handbrake + steer swings the tail out (about 15 degrees in 0.3 s).
--   * The slide then HOLDS without the handbrake for as long as the driver stays on the throttle and
--     keeps steering into the turn (a power slide). The engine pays back DriftPower of the speed the
--     sliding tyres scrub off, so the car keeps moving instead of crawling to a stop.
--     For half a second after the handbrake is let go, steering into the slide alone holds it (a phone
--     thumb needs that long to get from DRIFT back to GAS).
--   * Steering the other way (counter-steer, even inside that half second), straightening the wheel or
--     lifting off ends it: grip comes back over about 0.2 s (never in one snap) and the car goes where
--     its nose points, without swinging into a slide the other way. The yaw is always a rate target,
--     so a slide can't turn into a spin.
--   * Without the handbrake none of this happens: phys.Slide stays 0 and grip, steering and speed are
--     the old ones (the AI police never use it).
--   Why: with the old model, handbrake + steer + throttle bled the speed off in about 1.5 s and
--   left the car in a 20 studs/s crawl, too slow to score in the drift zone.
--
--   local phys = CarPhysics.New(car, { extra instances the rays should ignore })
--   CarPhysics.Step(phys, dt, { Throttle = -1..1, Steer = -1..1, Handbrake = bool, Nitro = bool })
--   phys.FwdSpeed, phys.NitroOn, phys.NitroFuel (0..1), phys.Flat, phys.Hits, phys.Grounded
--   phys.SlipAngle  degrees between the nose and the way the car really moves (0 when slow or airborne)
--   phys.Drifting   true while sliding the way DriftService scores it: cars only, nose first, 12-80 degrees,
--                   over 30 studs/s (a boat's ordinary turn or a car going backwards never counts)
--   phys.Slide      0..1, how far the tyres have let go (1 = full drift grip)
--   CarPhysics.Zero(phys) when nobody drives it any more.

local Workspace = game:GetService("Workspace")

local CarPhysics = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
CarPhysics.Wheels = WHEELS

-- Drift numbers shared by every car (the per-car ones are Grip, DriftGrip, DriftSteer, DriftPower).
local SLIDE_IN = 20 -- per second: the tyres let go in 0.05 s
local SLIDE_OUT = 5 -- per second: grip comes back over 0.2 s
local SLIDE_LATCH = 0.5 -- seconds after the handbrake that steering into the slide alone holds it
local HOLD_SPEED = 20 -- studs/s: slower than this there is no slide to hold
local HOLD_SLIP_MIN, HOLD_SLIP_MAX = 8, 85 -- degrees: a slide inside this range can be held on the throttle
local SLIP_SPEED = 15 -- studs/s: below this the slip angle reads 0
-- What counts as drifting: the same test as DriftService (MIN_SPEED, MIN_ANGLE, MAX_ANGLE), so the
-- DRIFT tag never shows while nothing scores.
local DRIFT_SPEED, DRIFT_ANGLE, DRIFT_MAX_ANGLE = 30, 12, 80
local DRIFT_STEER, DRIFT_POWER, DRIFT_GRIP = 1.35, 0.55, 2.6 -- used when a car has no such attribute
-- Body lean: studs from the centre of mass down to where the tyres' push is taken to act. 0.8 gives
-- about 2 degrees of roll in a hard corner or a drift and about 1 degree of nose dive braking on the
-- starter car's springs. The push used for it is capped at 1 g, so at most the lean adds under a third
-- of what it would take to tip a car sideways (a fifth end over end): it never rolls one. Raise it
-- with care.
local LEAN_ARM = 0.8

-- Tuning numbers the physics divides by: a live change to zero or less is ignored.
local POSITIVE = {
	MaxSpeed = true, ReverseSpeed = true, NitroSeconds = true, NitroRecharge = true, Grip = true,
	DriftGrip = true, SpringHz = true, RestLength = true, WheelRadius = true,
}

-- The sea's swell: how far (studs) the water stands above its flat level at this spot right now.
-- Terrain water draws its own waves (Terrain.WaterWaveSize) but holds a boat up as a flat sheet, so a
-- boat rode dead level across moving water. Two crossing waves, about 57 and 37 studs long, 3.3 s and
-- 2.4 s apart; timed off the server clock so every device sees a boat rise at the same moment.
local SWELL = 0.3 -- studs: the bigger wave's height either side of level (the smaller one adds 0.18)
local function swell(pos, t)
	return SWELL * math.sin(pos.X * 0.11 + t * 1.9) + SWELL * 0.6 * math.sin(pos.Z * 0.17 + pos.X * 0.05 - t * 2.6)
end

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
	-- Wheel rays only land on what the car itself can bump into (every car is in the "Vehicles"
	-- collision group, CarBuilder.EnsureGroups). Street furniture is in "Props" (PropService): cars drive
	-- through it, so a wheel must not climb onto a bench the body is passing through.
	local okGroup, known = pcall(function()
		return game:GetService("PhysicsService"):IsCollisionGroupRegistered("Vehicles")
	end)
	if okGroup and known then
		params.CollisionGroup = "Vehicles"
	end
	-- Cars' rays pass through water (they sink); boats' rays stop on the water surface and ride it.
	local boat = car:GetAttribute("Boat") == true
	params.IgnoreWater = not boat
	local cfg = car:GetAttributes()
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
		Fuel = cfg.NitroSeconds or 3, -- seconds of boost left
		NitroFuel = 1,
		NitroOn = false,
		FwdSpeed = 0,
		Steer = 0,
		Flat = false,
		Grounded = 0,
		Boat = boat,
		Beached = false,
		Slide = 0,
		SlideLatch = 0,
		SlipAngle = 0,
		Drifting = false,
	}
	for _, name in ipairs(WHEELS) do
		phys.Atts[name] = chassis:FindFirstChild("Wheel" .. name)
		phys.Forces[name] = chassis:FindFirstChild("Force" .. name)
	end
	-- Live tuning: the server may change the car's attributes while someone drives it.
	phys.CfgConn = car.AttributeChanged:Connect(function(name)
		local value = car:GetAttribute(name)
		if type(cfg[name]) == "number" then
			if type(value) ~= "number" or value ~= value or (POSITIVE[name] and value <= 0) then
				return
			end
		end
		cfg[name] = value
	end)
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

	-- Nitro fuel is in seconds of boost.
	local nitroOn = input.Nitro == true and phys.Fuel > 0 and throttle > 0.1
	if nitroOn then
		phys.Fuel = math.max(0, phys.Fuel - dt)
	else
		phys.Fuel = math.min(cfg.NitroSeconds, phys.Fuel + dt * cfg.NitroSeconds / cfg.NitroRecharge)
	end
	local maxSpeed = cfg.MaxSpeed * (nitroOn and cfg.NitroSpeed or 1) * (input.SpeedScale or 1)
	local accel = cfg.Accel * (nitroOn and cfg.NitroAccel or 1)
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
	-- A boat rides the swell: each corner floats on the water as it stands there right now, so the hull
	-- rises, pitches and rolls with the waves. Less of it at speed (a fast boat skims the tops; the full
	-- swell at 100 studs/s would hammer the springs twice a second).
	local swellNow, swellTime = 0, 0
	if phys.Boat then
		swellNow = 1 - 0.55 * math.clamp(chassis.AssemblyLinearVelocity.Magnitude / 110, 0, 1)
		swellTime = Workspace:GetServerTimeNow()
	end
	for _, name in ipairs(WHEELS) do
		local origin = phys.Atts[name].WorldPosition + up * lift
		local hit = Workspace:Raycast(origin, -up * (rayLen + lift), phys.Params)
		phys.Hits[name] = hit
		local force = Vector3.zero
		if hit then
			grounded += 1
			normalSum += hit.Normal
			local compression = rayLen - (hit.Distance - lift)
			if swellNow > 0 and hit.Material == Enum.Material.Water then
				compression += swell(hit.Position, swellTime) * swellNow
			end
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

	-- Where the car really goes compared with where it points (on the ground only).
	local n, fwd, side
	local latSpeed, planar, slip = 0, 0, 0
	if grounded > 0 then
		n = normalSum.Unit
		fwd = look - n * look:Dot(n)
		fwd = fwd.Magnitude > 1e-3 and fwd.Unit or look
		side = fwd:Cross(n)
		latSpeed = vel:Dot(side)
		planar = math.sqrt(fwdSpeed * fwdSpeed + latSpeed * latSpeed)
		if planar > SLIP_SPEED then
			slip = math.deg(math.atan2(math.abs(latSpeed), math.abs(fwdSpeed)))
		end
	end

	-- Have the tyres let go? The handbrake always does it. After that a car keeps sliding while the
	-- driver powers through it: on the throttle and steering into the turn (see the header).
	local latch = handbrake and SLIDE_LATCH or math.max(0, phys.SlideLatch - dt)
	phys.SlideLatch = latch
	local wantSlide = handbrake
	-- Only while steering INTO the slide (steer and latSpeed have opposite signs then). Counter-steering
	-- lets the grip come back at once, latch or not: holding the low grip through a counter-steer
	-- whipped the nose past the travel direction into a held slide the other way.
	if not handbrake and not phys.Boat and phys.Slide > 0.02 and grounded > 0 and fwdSpeed > 5 and planar > HOLD_SPEED
		and math.abs(steer) > 0.2 and steer * latSpeed < 0 then
		wantSlide = latch > 0 or (throttle > 0.3 and slip > HOLD_SLIP_MIN and slip < HOLD_SLIP_MAX)
	end
	local slide = phys.Slide
	if wantSlide then
		slide = math.min(1, slide + SLIDE_IN * dt)
	else
		slide = math.max(0, slide - SLIDE_OUT * dt)
	end
	phys.Slide = slide

	-- Drive, brake, grip (at the centre of mass)
	local drive = Vector3.zero
	local lean = nil -- the tyres' push at the road (grip + drive), for the body lean below; nil = none
	local gravity = Vector3.new(0, -Workspace.Gravity, 0)
	if grounded > 0 then
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
				local frac = math.clamp(-fwdSpeed / cfg.ReverseSpeed, 0, 1)
				long = -accel * 0.6 * -throttle * (1 - frac * frac)
			end
		elseif math.abs(fwdSpeed) > 1 then
			long = -sign(fwdSpeed) * cfg.Coast
		else
			-- Hold still, including on slopes (cancel gravity along the car's nose).
			long = math.clamp(-fwdSpeed / dt * 0.5 - gravity:Dot(fwd), -cfg.Brake, cfg.Brake)
		end
		if handbrake and math.abs(fwdSpeed) > 1 then
			long -= sign(fwdSpeed) * cfg.Brake * 0.15
		end

		-- Cancel a share of the sideways slide each step; the share depends on the grip rate (per second).
		-- Grip glides between the normal and the drift value as the tyres let go and bite again
		-- (slide 0 gives exactly cfg.Grip).
		local grip = cfg.Grip
		if slide > 0 then
			grip *= ((cfg.DriftGrip or DRIFT_GRIP) / grip) ^ slide
		end
		if flat then
			grip *= 0.45
		end
		-- Rain storms (WorldService): wet roads grip a bit less.
		if Workspace:GetAttribute("Raining") then
			grip *= 0.75
		end

		-- Power slide: sliding tyres scrub off grip x latSpeed^2 of speed every second. On the throttle
		-- the engine pays a share of that back along the nose, which also pulls the car round the turn.
		-- Without it a drift dies in about a second. Fades out near top speed so a drift is never a
		-- way to go faster, and never more than twice the engine's own push.
		if slide > 0 and throttle > 0.05 and fwdSpeed > 5 and not phys.Boat then
			local room = math.clamp((maxSpeed - planar) / (maxSpeed * 0.15), 0, 1)
			local push = (cfg.DriftPower or DRIFT_POWER) * grip * latSpeed * latSpeed / math.max(fwdSpeed, 10)
			long += math.min(push * throttle * slide * room, accel * 2)
		end
		if fwdSpeed > maxSpeed * 1.02 then
			long = math.min(long, -(fwdSpeed - maxSpeed) * 2)
		end

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
		if not phys.Boat then
			-- (at most 1 g of push either way: a hard landing in a slide or a physics fling can spike these,
			-- and the lean must never be what rolls a car)
			local cap = mass * Workspace.Gravity
			lean = side * math.clamp(lat, -cap, cap) + fwd * math.clamp(long * mass * gf, -cap, cap)
		end
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
		-- Sliding: steer harder (the tail swings out) and answer the wheel twice as fast (it kicks out
		-- at once, and comes back at once when the driver steers the other way).
		local driftSteer = 1 + ((cfg.DriftSteer or DRIFT_STEER) - 1) * slide
		local target = -steer * cfg.SteerRate * low * high * dir * driftSteer
		local current = angVel:Dot(up)
		torque += up * ((target - current) * cfg.YawResponse * (1 + slide) * yawInertia * gf)
	end
	if lean then
		-- The push acts LEAN_ARM below the centre of mass, along the ground normal. That adds only roll
		-- (from the sideways part) and pitch (from the forward part), never yaw, so the steering above
		-- is untouched.
		torque += (n * -LEAN_ARM):Cross(lean)
	end
	local tiltAxis = up:Cross(Vector3.yAxis)
	local spinNoYaw = angVel - up * angVel:Dot(up)
	local uprightScale = grounded > 0 and 0.35 or 1
	torque += (tiltAxis * cfg.UprightStrength - spinNoYaw * cfg.UprightDamp) * tiltInertia * uprightScale
	phys.BodyTorque.Torque = torque

	phys.FwdSpeed = fwdSpeed
	phys.NitroOn = nitroOn
	phys.NitroFuel = math.clamp(phys.Fuel / cfg.NitroSeconds, 0, 1)
	phys.Steer = steer
	phys.Flat = flat
	phys.Grounded = grounded
	phys.SlipAngle = slip
	-- (slip folds a backwards slide onto 0-90 degrees, and a boat's low grip slides ~20 degrees in any
	-- turn: DriftService scores neither, so neither shows as drifting)
	phys.Drifting = not phys.Boat and fwdSpeed > 0 and slip >= DRIFT_ANGLE and slip <= DRIFT_MAX_ANGLE
		and planar > DRIFT_SPEED
end

function CarPhysics.Zero(phys)
	if phys.CfgConn then
		phys.CfgConn:Disconnect()
		phys.CfgConn = nil
	end
	phys.Slide, phys.SlideLatch, phys.SlipAngle, phys.Drifting = 0, 0, 0, false
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

return CarPhysics
