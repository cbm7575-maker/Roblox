-- CarPhysics (ModuleScript, ReplicatedStorage.Shared.Util.CarPhysics)
-- The arcade raycast car, shared by the player's DriveController (client, owns their car) and the
-- AI police (server, owns AI cars). Same feel for everyone.
--   * Four rays hold the body up on springs (forces at each wheel, along the ground normal).
--   * Drive, brake and sideways grip push at the centre of mass.
--   * Steering is a yaw-rate target reached with a torque; a second torque keeps the car upright.
-- Tuning comes from the car's attributes (Config.Vehicles, copied by CarBuilder).
--
--   local phys = CarPhysics.New(car, { extra instances the rays should ignore })
--   CarPhysics.Step(phys, dt, { Throttle = -1..1, Steer = -1..1, Handbrake = bool, Nitro = bool })
--   phys.FwdSpeed, phys.NitroOn, phys.NitroFuel (0..1), phys.Flat, phys.Hits, phys.Grounded
--   CarPhysics.Zero(phys) when nobody drives it any more.

local Workspace = game:GetService("Workspace")

local CarPhysics = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
CarPhysics.Wheels = WHEELS

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
		if fwdSpeed > maxSpeed * 1.02 then
			long = math.min(long, -(fwdSpeed - maxSpeed) * 2)
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

return CarPhysics
